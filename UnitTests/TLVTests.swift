//
//  TLVTests.swift
//  SwiftIO
//
//  Created by Jonathan Wight on 12/7/15.
//  Copyright © 2015 schwa.io. All rights reserved.
//

import XCTest

import SwiftIO
import SwiftUtilities


class TLVTests: XCTestCase {

//    func testReadWrite16Native() throws {
//        typealias RecordType = TLVRecord <UInt16, UInt16>
//        let data = try GenericDispatchData <Void> ("Hello world")
//        let memory = MemoryStream()
//        let original = RecordType(type: 100, data: data)
//        try memory.write(original)
//        let record: RecordType = try memory.read()
//        XCTAssertEqual(record, original)
//    }
//
//    func testReadWrite16Big() throws {
//        typealias RecordType = TLVRecord <UInt16, UInt16>
//        let data = try GenericDispatchData <Void> ("Hello world")
//        let memory = MemoryStream()
//        memory.endianness = .Big
//        let original = RecordType(type: 100, data: data)
//        try memory.write(original)
//        let record: RecordType = try memory.read()
//        XCTAssertEqual(record, original)
//    }
//
//    func testReadWrite32Big() throws {
//        typealias RecordType = TLVRecord <UInt32, UInt32>
//        let data = try GenericDispatchData <Void> ("Hello world")
//        let memory = MemoryStream()
//        let original = RecordType(type: 100, data: data)
//        try memory.write(original)
//        let record: RecordType = try memory.read()
//        XCTAssertEqual(record, original)
//    }

    func testMultipleFrames() {

        typealias RecordType = TLVRecord <UInt16, UInt16>
        let memory = MemoryStream()

        for _ in 0..<2 {
            let data = try! GenericDispatchData <Void> ("Hello world")
            let original = RecordType(type: 100, data: data)
            try! memory.write(original)
        }

        let data = GenericDispatchData <Void> (buffer: memory.buffer)

        let (records, _) = try! RecordType.readMultiple(data, endianness: .Native)

        // TODO: Actually test the data here!
    }

}
