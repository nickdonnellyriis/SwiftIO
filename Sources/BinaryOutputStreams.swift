//
//  BinaryOutputStreams.swift
//  SwiftIO
//
//  Created by Jonathan Wight on 6/25/15.
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

import SwiftUtilities

// MARK: BinaryOutputStream

public protocol BinaryOutputStream {
    var endianness: Endianness { get }
    func write(_ buffer: UnsafeBufferPointer <UInt8>) throws
}

// MARK: BinaryOutputStreamable

public protocol BinaryOutputStreamable {
    func writeTo(_ stream: BinaryOutputStream) throws
}

public extension BinaryOutputStream {
    func write(_ value: BinaryOutputStreamable) throws {
        try value.writeTo(self)
    }
}

public extension BinaryOutputStreamable {
    // TODO: This can be dangerous (many situations exist in which this can return the wrong length). Deprecate?
    var length: Int {
        return tryElseFatalError() {
            let nullStream = NullStream()
            try nullStream.write(self)
            return nullStream.length
        }
    }
}

// MARK: -

extension GenericDispatchData: BinaryOutputStreamable {
    public func writeTo(_ stream: BinaryOutputStream) throws {
        try apply() {
            (range, buffer) in
            try stream.write(buffer.toUnsafeBufferPointer())
            return true
        }
    }
}

// MARK: -

extension Data: BinaryOutputStreamable {
    public func writeTo(_ stream: BinaryOutputStream) throws {

        try withUnsafeBytes() {
            (bytes: UnsafePointer <UInt8>) -> Void in

            let buffer = UnsafeBufferPointer <UInt8> (start: bytes, count: count)
            try stream.write(buffer)
        }


    }
}

// MARK: -

public extension BinaryOutputStream {
    func write(_ string: String, appendNewline: Bool = false) throws {
        let string = appendNewline == true ? string : string + "\n"
        let data = string.data(using: String.Encoding.utf8)!

        try data.withUnsafeBytes() {
            (bytes: UnsafePointer <UInt8>) -> Void in

            let buffer = UnsafeBufferPointer <UInt8> (start: bytes, count: data.count)
            try write(buffer)
        }
    }
}

// MARK: -

public extension BinaryOutputStream {
    func write <T: UnsignedInteger> (_ value: T) throws {
        var copy: T = value
        try withUnsafePointer(&copy) {
            (ptr: UnsafePointer <T>) -> Void in
            let buffer = UnsafeBufferPointer <UInt8> (start: UnsafePointer(ptr), count: sizeof(T.self))
            try write(buffer)
        }
    }
}
