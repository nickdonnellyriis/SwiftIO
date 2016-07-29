//
//  TLV.swift
//  SwiftIO
//
//  Created by Jonathan Wight on 12/7/15.
//  Copyright © 2015 schwa.io. All rights reserved.
//

// MARK: -

import SwiftUtilities

public typealias TLVType = protocol <BinaryStreamable, Equatable, EndianConvertable>
public typealias TLVlength = protocol <BinaryStreamable, UnsignedInteger, EndianConvertable>

public struct TLVRecord <Type: TLVType, Length: TLVlength> {
    public let type: Type
    public let data: GenericDispatchData <UInt8>

    public init(type: Type, data: GenericDispatchData <UInt8>) {
        self.type = type

        // TODO
//        guard data.length <= Length.max else {
//            throw Error.generic("Data too big")
//        }

        self.data = data
    }
}

// MARK: -

extension TLVRecord: Equatable {
}

public func == <Type, Length> (lhs: TLVRecord <Type, Length>, rhs: TLVRecord <Type, Length>) -> Bool {
    return lhs.type == rhs.type && lhs.data == rhs.data
}

// MARK: -

extension TLVRecord: BinaryInputStreamable {
    public static func readFrom(_ stream: BinaryInputStream) throws -> TLVRecord {
        let type: Type = try stream.read()
        let length: Length = try stream.read()
        let data: GenericDispatchData <UInt8> = try stream.readData(length: Int(length.toUIntMax()))
        let record = TLVRecord(type: type, data: data)
        return record
     }
}

// MARK: -

extension TLVRecord: BinaryOutputStreamable {
    public func writeTo(_ stream: BinaryOutputStream) throws {
        try stream.write(type)
        let length = Length(UIntMax(data.length.toEndianness(stream.endianness)))

        // TODO
//        guard length <= Length.max else {
//            throw Error.generic("Data too big")
//        }

        try stream.write(length)
        try stream.write(data)
    }
}


// MARK: -

public extension TLVRecord {
    func toGenericDispatchData(_ endianness: Endianness) throws -> GenericDispatchData <UInt8> {
        let length = Length(UIntMax(self.data.length))
        let data = GenericDispatchData <UInt8> ()
            + GenericDispatchData <UInt8> (value: type.toEndianness(endianness))
            + GenericDispatchData <UInt8> (value: length.toEndianness(endianness))
            + self.data
        return data
    }
}

// MARK: -

public extension TLVRecord {
    static func read(_ data: GenericDispatchData <UInt8>, endianness: Endianness) throws -> (TLVRecord?, GenericDispatchData <UInt8>) {
        // If we don't have enough data to read the TLV header exit
        if data.length < (sizeof(Type.self) + sizeof(Length.self)) {
            return (nil, data)
        }
        return try data.split() {
            (type: Type, remaining: GenericDispatchData <UInt8>) in
            // Convert the type from endianness
            let type = type.fromEndianness(endianness)
            return try remaining.split() {
                (length: Length, remaining: GenericDispatchData <UInt8>) in
                // Convert the length from endianness
                let length = Int(length.fromEndianness(endianness).toIntMax())
                // If we don't have enough remaining data to read the payload: exit.
                if remaining.length < length {
                    return (nil, data)
                }
                // Get the payload.
                return try remaining.split(length) {
                    (payload, remaining) in
                    // Produce a record.
                    let record = TLVRecord(type: type.fromEndianness(endianness), data: payload)
                    return (record, remaining)
                }
            }
        }
    }

    static func readMultiple(_ data: GenericDispatchData <UInt8>, endianness: Endianness) throws -> ([TLVRecord], GenericDispatchData <UInt8>) {
        var records: [TLVRecord] = []
        var data = data
        while true {
            let (maybeRecord, remainingData) = try read(data, endianness: endianness)
            guard let record = maybeRecord else {
                break
            }
            records.append(record)
            data = remainingData
        }
        return (records, data)
    }
}

// TODO: Move to SwiftUtilities?
private extension GenericDispatchData {
    func split<T, R>(_ closure: (T, GenericDispatchData) throws -> R) throws -> R {
        let (value, remaining): (T, GenericDispatchData) = try split()
        return try closure(value, remaining)
    }

    func split <R> (_ startIndex: Int, closure: (GenericDispatchData, GenericDispatchData) throws -> R) throws -> R {
        let (left, right) = try split(startIndex)
        return try closure(left, right)
    }
}
