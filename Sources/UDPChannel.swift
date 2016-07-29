//
//  UDPMavlinkReceiver.swift
//  SwiftIO
//
//  Created by Jonathan Wight on 4/22/15.
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

/**
 *  A GCD based UDP listener.
 */
public class UDPChannel {

    public enum PreconditionError: ErrorProtocol {
        case queueSuspended
        case queueNotExist
    }

    public let label: String?

    public let address: Address

    public var readHandler: ((Datagram) -> Void)? = loggingReadHandler
    public var errorHandler: ((ErrorProtocol) -> Void)? = loggingErrorHandler

    private var resumed: Bool = false
    private let receiveQueue: DispatchQueue!
    private let sendQueue: DispatchQueue!
    private var source: DispatchSource!

    public private(set) var socket: Socket!
    public var configureSocket: ((Socket) -> Void)?

    // MARK: - Initialization

    public init(label: String? = nil, address: Address, qos: DispatchQueueAttributes = DispatchQueueAttributes.qosDefault, readHandler: ((Datagram) -> Void)? = nil) {
        self.label = label
        self.address = address

        assert(address.port != nil)
        if let readHandler = readHandler {
            self.readHandler = readHandler
        }

        let queueAttribute = DispatchQueueAttributes.serial.union(qos)

        receiveQueue = DispatchQueue(label: "io.schwa.SwiftIO.UDP.receiveQueue", attributes: queueAttribute)
        guard receiveQueue != nil else {
            fatalError("dispatch_queue_create() failed")
        }

        sendQueue = DispatchQueue(label: "io.schwa.SwiftIO.UDP.sendQueue", attributes: queueAttribute)
        guard sendQueue != nil else {
            fatalError("dispatch_queue_create() failed")
        }
    }

    // MARK: - Actions

    public func resume() throws {
        do {
            socket = try Socket(domain: address.family.rawValue, type: SOCK_DGRAM, protocol: IPPROTO_UDP)
        }
        catch let error {
            cleanup()
            errorHandler?(error)
        }

        configureSocket?(socket)

        source = DispatchSource.read(fileDescriptor: socket.descriptor, queue: receiveQueue) /*Migrator FIXME: Use DispatchSourceRead to avoid the cast*/ as! DispatchSource
        guard source != nil else {
            cleanup()
            throw Error.generic("dispatch_source_create() failed")
        }

        source.setCancelHandler {
            [weak self] in
            guard let strong_self = self else {
                return
            }

            strong_self.cleanup()
            strong_self.resumed = false
        }

        source.setEventHandler {
            [weak self] in
            guard let strong_self = self else {
                return
            }
            do {
                try strong_self.read()
            }
            catch let error {
                strong_self.errorHandler?(error)
            }
        }

        source.setRegistrationHandler {
            [weak self] in
            guard let strong_self = self else {
                return
            }
            do {
                try strong_self.socket.bind(strong_self.address)
                strong_self.resumed = true
            }
            catch let error {
                strong_self.errorHandler?(error)
                tryElseFatalError() {
                    try strong_self.cancel()
                }
                return
            }
        }
        source.resume()
    }

    public func cancel() throws {
        if resumed == true {
            assert(source != nil, "Cancel called with source = nil.")
            source.cancel()
        }
    }

    public func send(_ data: GenericDispatchData <UInt8>, address: Address? = nil, callback: (Result <Void>) -> Void) {
        guard sendQueue != nil else {
            callback(.failure(PreconditionError.queueNotExist))
            return
        }
        guard resumed else {
            callback(.failure(PreconditionError.queueSuspended))
            return
        }

        sendQueue.async {
            [weak self] in

            guard let strong_self = self else {
                return
            }
            do {
                // use default address if address parameter is not set
                let address = address ?? strong_self.address

                if address.family != strong_self.address.family {
                    throw Error.generic("Cannot send UDP data down a IPV6 socket with a IPV4 address or vice versa.")
                }

                try strong_self.socket.sendto(data, address: address)
            }
            catch let error {
                strong_self.errorHandler?(error)
                callback(.failure(error))
                return
            }
            callback(.success())
        }
    }

    public static func send(_ data: GenericDispatchData <UInt8>, address: Address, queue: DispatchQueue, writeHandler: (Result <Void>) -> Void) {
        let socket = try! Socket(domain: address.family.rawValue, type: SOCK_DGRAM, protocol: IPPROTO_UDP)
        queue.async {
            do {
                try socket.sendto(data, address: address)
            }
            catch let error {
                writeHandler(.failure(error))
                return
            }
            writeHandler(.success())
        }
    }
}

// MARK: -

extension UDPChannel: CustomStringConvertible {
    public var description: String {
        return "\(self.dynamicType)(\"\(label ?? "")\")"
    }
}

// MARK: -

private extension UDPChannel {

    func read() throws {

        let data: NSMutableData! = NSMutableData(length: 4096)

        var addressData = Array <Int8> (repeating: 0, count: Int(SOCK_MAXADDRLEN))
        let (result, address) = addressData.withUnsafeMutableBufferPointer() {
            (ptr: inout UnsafeMutableBufferPointer <Int8>) -> (Int, Address?) in
            var addrlen: socklen_t = socklen_t(SOCK_MAXADDRLEN)
            let result = Darwin.recvfrom(socket.descriptor, data.mutableBytes, data.length, 0, UnsafeMutablePointer<sockaddr> (ptr.baseAddress), &addrlen)
            guard result >= 0 else {
                return (result, nil)
            }
            let addr = UnsafeMutablePointer <sockaddr_storage> (ptr.baseAddress)

            let address = Address(sockaddr: (addr?.pointee)!)
            return (result, address)
        }

        guard result >= 0 else {
            let error = Error.generic("recvfrom() failed")
            errorHandler?(error)
            throw error
        }

        data.length = result
        let dispatchData = GenericDispatchData <UInt8> (start: UnsafePointer(data.bytes), count: data.length)
        let datagram = Datagram(from: address!, timestamp: Timestamp(), data: dispatchData)
        readHandler?(datagram)
    }

    func cleanup() {
        defer {
            socket = nil
            source = nil
        }

        do {
            try socket.close()
        }
        catch let error {
            errorHandler?(error)
        }
    }
}

// MARK: -

public extension UDPChannel {
    public func send(_ data: Data, address: Address? = nil, callback: (Result <Void>) -> Void) {

        data.withUnsafeBytes() {
            (bytes: UnsafePointer <UInt8>) -> Void in
            let dispatchData = GenericDispatchData <UInt8> (start: bytes, count: data.count)
            send(dispatchData, address: address ?? self.address, callback: callback)
        }

    }
}

// Private for now - make public soon?
private extension Socket {
    func sendto(_ data: GenericDispatchData <UInt8>, address: Address) throws {
        var addr = sockaddr_storage(address: address)
        let result = withUnsafePointer(&addr) {
            ptr in
            return data.createMap() {
                buffer in
                return Darwin.sendto(descriptor, buffer.baseAddress, buffer.count, 0, UnsafePointer <sockaddr> (ptr), socklen_t(addr.ss_len))
            }
        }
        // TODO: what about "partial" sends.
        if result < data.length {
            throw Errno(rawValue: errno) ?? Error.unknown
        }
    }
}
