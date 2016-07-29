//
//  EchoViewController.swift
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

class EchoViewController: NSViewController {

    var channel: TCPChannel!
    var task: NSTask?
    dynamic var connected: Bool = false

    dynamic var input: String?

    override func viewDidLoad() {
        super.viewDidLoad()

//        try! start()
    }

    @IBAction func start(sender: AnyObject?) {

        // socat TCP4-LISTEN:12345,reuseaddr exec:'tr A-Z a-z',pty,raw,echo=0
        task = NSTask.launchedTaskWithLaunchPath("/usr/local/bin/socat", arguments: ["TCP4-LISTEN:12345,reuseaddr", "exec:'tr a-z A-Z',pty,raw,echo=0"])
        sleep(1)

        let address = try! Address(address: "127.0.0.1", port: 12345)

        channel = TCPChannel(address: address)
        channel.state.addObserver(self, queue: dispatch_get_main_queue()) {
            (old, new) in
            log?.debug("STATE CHANGE: \(old) -> \(new)")
        }

        channel.shouldReconnect = {
            assert(self.channel.state.value == .disconnected)
            log?.debug("Disconnected!")

            dispatch_async(dispatch_get_main_queue()) {
                self.updateConnected()
            }
            return true
        }

        channel.readCallback = {
            (result) in
            if case .failure(let error) = result {
                log?.debug(error)
                return
            }
            if case .success(let data) = result {
                let string = String(data: data.toNSData(), encoding:NSUTF8StringEncoding)!

                dispatch_async(dispatch_get_main_queue()) {
                    log?.debug("Received: \(string)")
                    self.updateConnected()
                }
            }
        }

        channel.connect() {
            (result) in

            dispatch_async(dispatch_get_main_queue()) {
                self.updateConnected()
            }

            if case .failure(let error) = result {
                assert(self.channel.state.value == .disconnected)
                log?.debug("Connection failure: \(error)")
                return
            }

            let data = "Hello world".dataUsingEncoding(NSUTF8StringEncoding)!
            let GenericDispatchData = GenericDispatchData <UInt8> (start: data.bytes, count: data.length)
            self.channel!.write(GenericDispatchData) {
                (result) in
                log?.debug("Write: \(result)")
            }
        }
    }

    @IBAction func connect(sender: AnyObject?) {
        channel.connect() {
            (result) in
            log?.debug("Connect \(result)")
            self.updateConnected()
        }
    }

    @IBAction func disconnect(sender: AnyObject?) {
        channel.disconnect() {
            (result) in
            log?.debug("Disconnect \(result)")
        }
    }

    @IBAction func write(sender: AnyObject?) {

        guard let input = input else {
            return
        }

        let data = input.dataUsingEncoding(NSUTF8StringEncoding)!
        let GenericDispatchData = GenericDispatchData <UInt8> (start: data.bytes, count: data.length)
        self.channel!.write(GenericDispatchData) {
            (result) in
            log?.debug("Write: \(result)")
        }

    }

    func updateConnected() {
        connected = channel.state.value == .connected
        log?.debug("\(channel.state), \(connected)")
    }

}
