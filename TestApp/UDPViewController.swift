//
//  UDPViewController.swift
//  SwiftIO
//
//  Created by Jonathan Wight on 9/30/15.
//  Copyright © 2015 schwa.io. All rights reserved.
//

import Cocoa

import SwiftIO
import SwiftUtilities

class UDPViewController: NSViewController {

    var writer: UDPChannel?

    let queue = dispatch_queue_create("test", DISPATCH_QUEUE_CONCURRENT)

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.

        writer = try! UDPChannel(hostname: "localhost", port: 5000) {
            (datagram) in

            dispatch_async(dispatch_get_main_queue()) {
                print(datagram.data.toString())
            }
        }
        try! writer?.resume()
    }

    @IBAction func startWriting(sender:AnyObject?) {
        for N in 0..<1000 {
            dispatch_async(queue) {
                let data = try! DispatchData <Void> (string: "Hello world \(N)")
                try! self.writer?.send(data, port: 5000)
            }
        }
    }

    @IBAction func dumpStats(sender:AnyObject?) {
        print(writer?.memoryPool.statistics)
    }
}

extension DispatchData {
    init(string:String) throws {
        let data = string.dataUsingEncoding(NSUTF8StringEncoding)!
        let dispatchData = DispatchData <Void> (start: data.bytes, count: data.length)
        self = DispatchData(data: dispatchData.data)
    }

    func toString() -> String {
        let data = self.data as! NSData
        return String(data:data, encoding:NSUTF8StringEncoding)!
    }
}


