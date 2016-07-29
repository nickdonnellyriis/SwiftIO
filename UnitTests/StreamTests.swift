//
//  StreamTests.swift
//  SwiftIO
//
//  Created by Jonathan Wight on 12/29/15.
//  Copyright © 2015 schwa.io. All rights reserved.
//

import XCTest

import SwiftIO
import SwiftUtilities

class StreamTests: XCTestCase {
    func testNative() {
        try! readWriteValue(Int(100))
        try! readWriteValue(Int16(100))
        try! readWriteValue(Int32(100))
        try! readWriteValue(Int64(100))
        try! readWriteValue(UInt(100))
        try! readWriteValue(UInt16(100))
        try! readWriteValue(UInt32(100))
        try! readWriteValue(UInt64(100))
        try! readWriteValue(Float(100))
        try! readWriteValue(Double(100))
    }

    func testBig() {
        try! readWriteValue(Int(100), endianness: .Big)
        try! readWriteValue(Int16(100), endianness: .Big)
        try! readWriteValue(Int32(100), endianness: .Big)
        try! readWriteValue(Int64(100), endianness: .Big)
        try! readWriteValue(UInt(100), endianness: .Big)
        try! readWriteValue(UInt16(100), endianness: .Big)
        try! readWriteValue(UInt32(100), endianness: .Big)
        try! readWriteValue(UInt64(100), endianness: .Big)
        try! readWriteValue(Float(100), endianness: .Big)
        try! readWriteValue(Double(100), endianness: .Big)
    }

    func testLittle() {
        try! readWriteValue(Int(100), endianness: .Little)
        try! readWriteValue(Int16(100), endianness: .Little)
        try! readWriteValue(Int32(100), endianness: .Little)
        try! readWriteValue(Int64(100), endianness: .Little)
        try! readWriteValue(UInt(100), endianness: .Little)
        try! readWriteValue(UInt16(100), endianness: .Little)
        try! readWriteValue(UInt32(100), endianness: .Little)
        try! readWriteValue(UInt64(100), endianness: .Little)
        try! readWriteValue(Float(100), endianness: .Little)
        try! readWriteValue(Double(100), endianness: .Little)
    }
}

func readWriteValue <T: BinaryStreamable where T: Equatable> (_ value: T, endianness: Endianness = .Native) throws {
    let stream = MemoryStream()
    stream.endianness = endianness
    try stream.write(value)
    stream.rewind()
    let newValue: T = try stream.read()
    XCTAssertEqual(value, newValue)
}
