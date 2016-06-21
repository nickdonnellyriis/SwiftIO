//
//  TCPChannel.swift
//  SwiftIO
//
//  Created by Jonathan Wight on 6/23/15.
//
//  Copyright (c) 2014, Jonathan Wight
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  * Redistributions of source code must retain the above copyright notice, this
//    list of conditions and the following disclaimer.
//
//  * Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
//  FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
//  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
//  SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
//  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
//  OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import Darwin
import Dispatch

import SwiftUtilities

public class TCPChannel: Connectable {
    public enum Error: ErrorType {
        case IncorrectState(String)
        case Unknown
    }

    public let label: String?
    public let address: Address
    public let state = ObservableProperty(ConnectionState.Disconnected)

    // MARK: Callbacks

    public var readCallback: (Result <DispatchData <Void>> -> Void)? {
        willSet {
            preconditionConnected()
        }
    }

    /// Return true from shouldReconnect to initiate a reconnect. Does not make sense on a server socket.
    public var shouldReconnect: (Void -> Bool)? {
        willSet {
            preconditionConnected()
        }
    }
    public var reconnectionDelay: NSTimeInterval = 5.0 {
        willSet {
            preconditionConnected()
        }
    }

    // MARK: Private properties

    private let queue: dispatch_queue_t
    private let lock = NSRecursiveLock()
    public private(set) var socket: Socket!
    private var channel: dispatch_io_t!
    private var disconnectCallback: (Result <Void> -> Void)?

    // MARK: Initialization

    public init(label: String? = nil, address: Address, qos: qos_class_t = QOS_CLASS_DEFAULT) {
        assert(address.port != nil)

        self.label = label
        self.address = address
        let queueAttribute = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, qos, 0)
        self.queue = dispatch_queue_create("io.schwa.SwiftIO.TCP.queue", queueAttribute)

    }

    public func connect(callback: Result <Void> -> Void) {
        connect(timeout: 30, callback: callback)
    }

    public func connect(timeout timeout: Int, callback: Result <Void> -> Void) {
        dispatch_async(queue) {
            [weak self, address] in

            guard let strong_self = self else {
                return
            }

            if strong_self.state.value != .Disconnected {
                callback(.Failure(Error.IncorrectState("Cannot connect channel in state \(strong_self.state.value)")))
                return
            }

            log?.debug("\(strong_self): Trying to connect.")

            do {
                strong_self.state.value = .Connecting
                let socket: Socket

                socket = try Socket(domain: address.family.rawValue, type: SOCK_STREAM, protocol: IPPROTO_TCP)

                strong_self.configureSocket?(socket)
                try socket.connect(address, timeout: timeout)

                strong_self.socket = socket
                strong_self.state.value = .Connected
                strong_self.createStream()
                log?.debug("\(strong_self): Connection success.")
                callback(.Success())
            }
            catch let error {
                strong_self.state.value = .Disconnected
                log?.debug("\(strong_self): Connection failure: \(error).")
                callback(.Failure(error))
            }
        }

    }

    public func disconnect(callback: Result <Void> -> Void) {
        retrier?.cancel()
        retrier = nil

        dispatch_async(queue) {
            [weak self] in

            guard let strong_self = self else {
                return
            }
            if Set([.Disconnected, .Disconnecting]).contains(strong_self.state.value) {
                callback(.Failure(Error.IncorrectState("Cannot disconnect channel in state \(strong_self.state.value)")))
                return
            }

            log?.debug("\(strong_self): Trying to disconnect.")

            strong_self.state.value = .Disconnecting
            strong_self.disconnectCallback = callback
            dispatch_io_close(strong_self.channel, DISPATCH_IO_STOP)
        }
    }

    var retrier: Retrier? = nil
    var retryOptions = Retrier.Options()

    public func connect(retryDelay retryDelay: NSTimeInterval?, retryMultiplier: Double? = nil, retryMaximumDelay: NSTimeInterval? = nil, retryMaximumAttempts: Int? = nil, callback: Result <Void> -> Void) {
        var options = Retrier.Options()
        if let retryDelay = retryDelay {
            options.delay = retryDelay
        }
        if let retryMultiplier = retryMultiplier {
            options.multiplier = retryMultiplier
        }
        if let retryMaximumDelay = retryMaximumDelay {
            options.maximumDelay = retryMaximumDelay
        }
        if let retryMaximumAttempts = retryMaximumAttempts {
            options.maximumAttempts = retryMaximumAttempts
        }
        connect(retryOptions: options, callback: callback)
    }

    private func connect(retryOptions retryOptions: Retrier.Options, callback: Result <Void> -> Void) {
        self.retryOptions = retryOptions
        let retrier = Retrier(options: retryOptions) {
            [weak self] (retryCallback) in

            guard let strong_self = self else {
                return
            }

            strong_self.connect() {
                (result: Result <Void>) -> Void in

                if case .Failure(let error) = result {
                    if retryCallback(.Failure(error)) == false {
                        log?.debug("\(strong_self): Connection retry failed with \(error).")
                        callback(result)
                        strong_self.retrier = nil
                    }
                }
                else {
                    retryCallback(.Success())
                    log?.debug("\(strong_self): Connection retry succeeded.")
                    callback(result)
                    strong_self.retrier = nil
                }
            }
        }
        self.retrier = retrier
        retrier.resume()
    }

    // MARK: -

    public func write(data: DispatchData <Void>, callback: Result <Void> -> Void) {
        dispatch_io_write(channel, 0, data.data, queue) {
            (done, data, error) in

            guard error == 0 else {
                callback(Result.Failure(Errno(rawValue: error)!))
                return
            }
            callback(Result.Success())
        }
    }

    private func createStream() {

        channel = dispatch_io_create(DISPATCH_IO_STREAM, socket.descriptor, queue) {
            [weak self] (error) in

            guard let strong_self = self else {
                return
            }
            tryElseFatalError() {
                try strong_self.handleDisconnect()
            }
        }
        assert(channel != nil)
        precondition(state.value == .Connected)

        dispatch_io_set_low_water(channel, 0)

        dispatch_io_read(channel, 0, -1 /* Int(truncatingBitPattern:SIZE_MAX) */, queue) {
            [weak self] (done, data, error) in

            guard let strong_self = self else {
                return
            }
            guard error == 0 else {
                if error == ECONNRESET {
                    tryElseFatalError() {
                        try strong_self.handleDisconnect()
                    }
                    return
                }
                strong_self.readCallback?(Result.Failure(Errno(rawValue: error)!))
                return
            }
            switch (done, dispatch_data_get_size(data!) > 0) {
                case (false, _), (true, true):
                    let dispatchData = DispatchData <Void> (data: data!)
                    strong_self.readCallback?(Result.Success(dispatchData))
                case (true, false):
                    dispatch_io_close(strong_self.channel, dispatch_io_close_flags_t())
            }
        }
    }

    private func handleDisconnect() throws {
        let remoteDisconnect = (state.value != .Disconnecting)

        try socket.close()

        state.value = .Disconnected

        if let shouldReconnect = shouldReconnect where remoteDisconnect == true {
            let reconnectFlag = shouldReconnect()
            if reconnectFlag == true {
                let time = dispatch_time(DISPATCH_TIME_NOW, Int64(reconnectionDelay * 1000000000))
                dispatch_after(time, queue) {
                    [weak self] (result) in

                    guard let strong_self = self else {
                        return
                    }

                    strong_self.reconnect()
                }
                return
            }
        }

        disconnectCallback?(Result.Success())
        disconnectCallback = nil
    }

    private func reconnect() {
        connect(retryOptions: retryOptions) {
            [weak self] (result) in

            guard let strong_self = self else {
                return
            }

            if case .Failure = result {
                strong_self.disconnectCallback?(result)
                strong_self.disconnectCallback = nil
            }
        }
    }

    private func preconditionConnected() {
        precondition(state.value == .Disconnected, "Cannot change parameter while socket connected")
    }

    // MARK: -

    public var configureSocket: (Socket -> Void)?
}

// MARK: -

extension TCPChannel {

    /// Create a TCPChannel from a pre-existing socket. The setup closure is called after the channel is created but before the state has changed to `Connecting`. This gives consumers a chance to configure the channel before it is fully connected.
    public convenience init(label: String? = nil, address: Address, socket: Socket, qos: qos_class_t = QOS_CLASS_DEFAULT, @noescape setup: (TCPChannel -> Void)) {
        self.init(label: label, address: address)
        self.socket = socket
        setup(self)
        state.value = .Connected
        createStream()
    }

}

// MARK: -

extension TCPChannel: CustomStringConvertible {
    public var description: String {
        return "TCPChannel(label: \(label), address: \(address)), state: \(state.value))"
    }
}

// MARK: -

extension TCPChannel: Hashable {
    public var hashValue: Int {
        return ObjectIdentifier(self).hashValue
    }
}

public func == (lhs: TCPChannel, rhs: TCPChannel) -> Bool {
    return lhs === rhs
}
