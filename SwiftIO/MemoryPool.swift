//
//  main.swift
//  MemoryPool
//
//  Created by Jonathan Wight on 9/30/15.
//  Copyright © 2015 schwa.io. All rights reserved.
//

import Foundation

public class MemoryPool {

    public let length: Int
    public let maximumCount: Int // Maximum # of blocks in the recycled set

    public struct Statistics {
        var allocations: Int = 0
        var gets: Int = 0
        var recyles: Int = 0
        var countHighWaterMark: Int = 0
    }

    public private (set) var statistics = Statistics()

    public let queue = dispatch_queue_create("io.schwa.MemoryPool", DISPATCH_QUEUE_SERIAL)
    private var spares: [NSMutableData] = []

    public init(length: Int, initialCount: Int = 0, maximumCount: Int = 20/*Int.max*/) {
        assert(initialCount < maximumCount)
        assert(maximumCount > 0)
        self.length = length
        self.maximumCount = maximumCount
        statistics.countHighWaterMark = initialCount
        spares = (0..<initialCount).map() {
            (_) in
            return NSMutableData()
        }
    }

    public func get() -> (UnsafeMutableBufferPointer <Void>, dispatch_data_t) {

        var data: NSMutableData! = nil
        var dispatchData: dispatch_data_t! = nil

        dispatch_sync(queue) {

            self.statistics.gets++

            if self.spares.isEmpty == false {
//                print("++ Claiming from pool")
                data = self.spares.popLast()!
            }
            else {
//                print("++ Allocating new")
                self.statistics.allocations++
                data = NSMutableData(length: self.length)!
            }
        }

        dispatchData = dispatch_data_create(data.mutableBytes, self.length, self.queue) {
            [weak self, data] in

//            print("-- Returning to pool (of reused data)")

            guard let strong_self = self else {
                return
            }
            strong_self.recyle(data)
        }

        let buffer = UnsafeMutableBufferPointer <Void> (start: data.mutableBytes, count: data.length)

        return (buffer, dispatchData)
    }

    private func recyle(data:NSMutableData) {
        spares.append(data)

        statistics.recyles++
        statistics.countHighWaterMark = max(statistics.countHighWaterMark, spares.count)

//        print(spares.count, countHighWaterMark)
        if spares.count > maximumCount {
            spares = Array(spares[0..<maximumCount])
        }
    }

    private func purge() {
        dispatch_sync(queue) {
            self.spares = []
        }
    }
}
