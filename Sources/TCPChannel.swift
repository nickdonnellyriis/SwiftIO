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
    public enum Error: ErrorProtocol {
        case incorrectState(String)
        case unknown
    }

    public let label: String?
    public let address: Address
    public let state = ObservableProperty(ConnectionState.disconnected)

    // MARK: Callbacks

    public var readCallback: ((Result <GenericDispatchData <UInt8>>) -> Void)? {
        willSet {
            preconditionConnected()
        }
    }

    /// Return true from shouldReconnect to initiate a reconnect. Does not make sense on a server socket.
    public var shouldReconnect: ((Void) -> Bool)? {
        willSet {
            preconditionConnected()
        }
    }
    public var reconnectionDelay: TimeInterval = 5.0 {
        willSet {
            preconditionConnected()
        }
    }

    // MARK: Private properties

    private let queue: DispatchQueue
    private let lock = RecursiveLock()
    public private(set) var socket: Socket!
    private var channel: DispatchIO!
    private var disconnectCallback: ((Result <Void>) -> Void)?

    // MARK: Initialization

    public init(label: String? = nil, address: Address, qos: DispatchQueueAttributes = DispatchQueueAttributes.qosDefault) {
        assert(address.port != nil)

        self.label = label
        self.address = address
        let queueAttribute = DispatchQueueAttributes.serial.union(qos)
        self.queue = DispatchQueue(label: "io.schwa.SwiftIO.TCP.queue", attributes: queueAttribute)

    }

    public func connect(_ callback: (Result <Void>) -> Void) {
        connect(timeout: 30, callback: callback)
    }

    public func connect(timeout: Int, callback: (Result <Void>) -> Void) {
        queue.async {
            [weak self, address] in

            guard let strong_self = self else {
                return
            }

            if strong_self.state.value != .disconnected {
                callback(.failure(Error.incorrectState("Cannot connect channel in state \(strong_self.state.value)")))
                return
            }

            log?.debug("\(strong_self): Trying to connect.")

            do {
                strong_self.state.value = .connecting
                let socket: Socket

                socket = try Socket(domain: address.family.rawValue, type: SOCK_STREAM, protocol: IPPROTO_TCP)

                strong_self.configureSocket?(socket)
                try socket.connect(address, timeout: timeout)

                strong_self.socket = socket
                strong_self.state.value = .connected
                strong_self.createStream()
                log?.debug("\(strong_self): Connection success.")
                callback(.success())
            }
            catch let error {
                strong_self.state.value = .disconnected
                log?.debug("\(strong_self): Connection failure: \(error).")
                callback(.failure(error))
            }
        }

    }

    public func disconnect(_ callback: (Result <Void>) -> Void) {
        retrier?.cancel()
        retrier = nil

        queue.async {
            [weak self] in

            guard let strong_self = self else {
                return
            }
            if Set([.disconnected, .disconnecting]).contains(strong_self.state.value) {
                callback(.failure(Error.incorrectState("Cannot disconnect channel in state \(strong_self.state.value)")))
                return
            }

            log?.debug("\(strong_self): Trying to disconnect.")

            strong_self.state.value = .disconnecting
            strong_self.disconnectCallback = callback
            strong_self.channel.close(flags: DispatchIO.CloseFlags.stop)
        }
    }

    var retrier: Retrier? = nil
    var retryOptions = Retrier.Options()

    public func connect(retryDelay: TimeInterval?, retryMultiplier: Double? = nil, retryMaximumDelay: TimeInterval? = nil, retryMaximumAttempts: Int? = nil, callback: (Result <Void>) -> Void) {
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

    private func connect(retryOptions: Retrier.Options, callback: (Result <Void>) -> Void) {
        self.retryOptions = retryOptions
        let retrier = Retrier(options: retryOptions) {
            [weak self] (retryCallback) in

            guard let strong_self = self else {
                return
            }

            strong_self.connect() {
                (result: Result <Void>) -> Void in

                if case .failure(let error) = result {
                    if retryCallback(.failure(error)) == false {
                        log?.debug("\(strong_self): Connection retry failed with \(error).")
                        callback(result)
                        strong_self.retrier = nil
                    }
                }
                else {
                    _ = retryCallback(.success())
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

    public func write(_ data: GenericDispatchData <Void>, callback: (Result <Void>) -> Void) {
        (channel).write(offset: 0, data: data.data, queue: queue) {
            (done, data, error) in

            guard error == 0 else {
                callback(Result.failure(Errno(rawValue: error)!))
                return
            }
            callback(Result.success())
        }
    }

    private func createStream() {

        channel = DispatchIO(type: DispatchIO.StreamType.stream, fileDescriptor: socket.descriptor, queue: queue) {
            [weak self] (error) in

            guard let strong_self = self else {
                return
            }
            tryElseFatalError() {
                try strong_self.handleDisconnect()
            }
        }
        assert(channel != nil)
        precondition(state.value == .connected)

        channel.setLimit(lowWater: 0)

        channel.read(offset: 0, length: -1 /* Int(truncatingBitPattern:SIZE_MAX) */, queue: queue) {
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
                strong_self.readCallback?(Result.failure(Errno(rawValue: error)!))
                return
            }
            switch (done, data!.count > 0) {
                case (false, _), (true, true):
                    let dispatchData = GenericDispatchData <UInt8> (data: data!)
                    strong_self.readCallback?(Result.success(dispatchData))
                case (true, false):
                    strong_self.channel.close(flags: DispatchIO.CloseFlags())
            }
        }
    }

    private func handleDisconnect() throws {
        let remoteDisconnect = (state.value != .disconnecting)

        try socket.close()

        state.value = .disconnected

        if let shouldReconnect = shouldReconnect, remoteDisconnect == true {
            let reconnectFlag = shouldReconnect()
            if reconnectFlag == true {
                let time = DispatchTime.now() + Double(Int64(reconnectionDelay * 1000000000)) / Double(NSEC_PER_SEC)
                queue.after(when: time) {
                    [weak self] (result) in

                    guard let strong_self = self else {
                        return
                    }

                    strong_self.reconnect()
                }
                return
            }
        }

        disconnectCallback?(Result.success())
        disconnectCallback = nil
    }

    private func reconnect() {
        connect(retryOptions: retryOptions) {
            [weak self] (result) in

            guard let strong_self = self else {
                return
            }

            if case .failure = result {
                strong_self.disconnectCallback?(result)
                strong_self.disconnectCallback = nil
            }
        }
    }

    private func preconditionConnected() {
        precondition(state.value == .disconnected, "Cannot change parameter while socket connected")
    }

    // MARK: -

    public var configureSocket: ((Socket) -> Void)?
}

// MARK: -

extension TCPChannel {

    /// Create a TCPChannel from a pre-existing socket. The setup closure is called after the channel is created but before the state has changed to `Connecting`. This gives consumers a chance to configure the channel before it is fully connected.
    public convenience init(label: String? = nil, address: Address, socket: Socket, qos: DispatchQueueAttributes = DispatchQueueAttributes.qosDefault, setup: @noescape (TCPChannel) -> Void) {
        self.init(label: label, address: address)
        self.socket = socket
        setup(self)
        state.value = .connected
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
