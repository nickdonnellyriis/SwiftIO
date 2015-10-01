//
//  TCPViewController.swift
//  TestApp
//
//  Created by Jonathan Wight on 8/8/15.
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


import Cocoa

import SwiftIO
import SwiftUtilities

class TCPViewController: NSViewController {

    var channel: TCPChannel!
    var task: NSTask?
    dynamic var connected: Bool = false

    dynamic var input: String?
    dynamic var output: String?

    override func viewDidLoad() {
        super.viewDidLoad()

        // socat TCP4-LISTEN:12345,reuseaddr exec:'tr A-Z a-z',pty,raw,echo=0
//        task = NSTask.launchedTaskWithLaunchPath("/usr/local/bin/socat", arguments: ["TCP4-LISTEN:12345,reuseaddr", "exec:'tr a-z A-Z',pty,raw,echo=0"])
//        sleep(1)

        channel = try! TCPChannel(hostname: "schwa.io", port: 12345)

        channel.serverDisconnectedCallback = {
            assert(self.channel.state == .Unconnected)
            print("Disconnected!")

            Async.main() {
                self.updateConnected()
            }
            return true
        }

        channel.readCallback = {
            (result) in
            if let error = result.error {
                print(error)
                return
            }
            if let data = result.value {
                let string = String(data: data.toNSData(), encoding:NSUTF8StringEncoding)!

                Async.main() {
                    self.output = string
                    self.updateConnected()
                }
            }
        }

//        channel.connect() {
//            (result) in
//
//            Async.main() {
//                self.updateConnected()
//            }
//
//            if let error = result.error {
//                assert(self.channel.state == .Unconnected)
//                print("Connection failure: \(error)")
//                return
//            }
//
//            let data = "Hello world".dataUsingEncoding(NSUTF8StringEncoding)!
//            let dispatchData = DispatchData <Void> (start: data.bytes, count: data.length)
//            self.channel!.write(dispatchData) {
//                (result) in
//                print("Write: ", result)
//            }
//        }
    }

    @IBAction func connect(sender:AnyObject?) {
        channel.connect() {
            (result) in
            print("Connect \(result)")
            self.updateConnected()
        }
    }

    @IBAction func disconnect(sender:AnyObject?) {
        channel.disconnect() {
            (result) in
            print("Disconnect \(result)")
        }
    }

    @IBAction func write(sender:AnyObject?) {

        guard let input = input else {
            return
        }

        let data = input.dataUsingEncoding(NSUTF8StringEncoding)!
        let dispatchData = DispatchData <Void> (start: data.bytes, count: data.length)
        self.channel!.write(dispatchData) {
            (result) in
            print("Write: ", result)
        }

    }

    func updateConnected() {
        connected = channel.state == .Connected
        print(channel.state, connected)
    }

}

struct Async {

    static func main(closure:() -> Void) {
        dispatch_async(dispatch_get_main_queue(), closure)
    }


}