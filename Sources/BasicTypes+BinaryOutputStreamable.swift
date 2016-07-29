//
//  IntegerType+BinaryOutputStreamable.swift
//  SwiftIO
//
//  Created by Jonathan Wight on 12/5/15.
//  Copyright © 2015 schwa.io. All rights reserved.
//

import SwiftUtilities


private func write <T: EndianConvertable> (_ stream: BinaryOutputStream, value: T) throws {
    var value = value.toEndianness(stream.endianness)
    let buffer = withUnsafePointer(&value) {
        (pointer: UnsafePointer <T>) -> UnsafeBufferPointer <UInt8> in
        return UnsafeBufferPointer(start: UnsafePointer(pointer), count: sizeof(T.self))
    }
    try stream.write(buffer)
}

// MARK: -

extension Int: BinaryOutputStreamable {
    public func writeTo(_ stream: BinaryOutputStream) throws {
        try write(stream, value: self)
    }
}

extension Int8: BinaryOutputStreamable {
    public func writeTo(_ stream: BinaryOutputStream) throws {
        try write(stream, value: self)
    }
}

extension Int16: BinaryOutputStreamable {
    public func writeTo(_ stream: BinaryOutputStream) throws {
        try write(stream, value: self)
    }
}

extension Int32: BinaryOutputStreamable {
    public func writeTo(_ stream: BinaryOutputStream) throws {
        try write(stream, value: self)
    }
}

extension Int64: BinaryOutputStreamable {
    public func writeTo(_ stream: BinaryOutputStream) throws {
        try write(stream, value: self)
    }
}

// MARK: -

extension UInt: BinaryOutputStreamable {
    public func writeTo(_ stream: BinaryOutputStream) throws {
        try write(stream, value: self)
    }
}

extension UInt8: BinaryOutputStreamable {
    public func writeTo(_ stream: BinaryOutputStream) throws {
        try write(stream, value: self)
    }
}

extension UInt16: BinaryOutputStreamable {
    public func writeTo(_ stream: BinaryOutputStream) throws {
        try write(stream, value: self)
    }
}

extension UInt32: BinaryOutputStreamable {
    public func writeTo(_ stream: BinaryOutputStream) throws {
        try write(stream, value: self)
    }
}

extension UInt64: BinaryOutputStreamable {
    public func writeTo(_ stream: BinaryOutputStream) throws {
        try write(stream, value: self)
    }
}

// MARK: -

extension Float: BinaryOutputStreamable {
    public func writeTo(_ stream: BinaryOutputStream) throws {
        let bitValue = unsafeBitCast(self, to: UInt32.self)
        try write(stream, value: bitValue)
    }
}

extension Double: BinaryOutputStreamable {
    public func writeTo(_ stream: BinaryOutputStream) throws {
        let bitValue = unsafeBitCast(self, to: UInt64.self)
        try write(stream, value: bitValue)
    }
}
