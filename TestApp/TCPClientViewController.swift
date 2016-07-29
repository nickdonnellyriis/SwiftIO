//
//  TCPClientViewController.swift
//  SwiftIO
//
//  Created by Jonathan Wight on 1/25/16.
//  Copyright © 2016 schwa.io. All rights reserved.
//

import Cocoa

import SwiftIO
import SwiftUtilities

class TCPClientViewController: NSViewController {

    var clientChannel: TCPChannel?
    var count: Int = 0

    dynamic var address: String? = "localhost:8888"
    dynamic var reconnect: Bool = false
    dynamic var state: String? = nil
    dynamic var connected: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    func createClient() throws -> TCPChannel {

        guard let addressString = self.address else {
            throw Error.generic("Could not create address")
        }

        let address = try Address(address: addressString)

        let clientChannel = TCPChannel(address: address)
        clientChannel.configureSocket = {
            socket in

            socket.socketOptions.keepAlive = true
            socket.socketOptions.sendTimeout = 2
            socket.socketOptions.receiveTimeout = 2

            socket.socketOptions.noDelay = true
            socket.socketOptions.keepAliveIdleTime = 10
            socket.socketOptions.connectionTimeout = 10
            socket.socketOptions.keepAliveInterval = 10
            socket.socketOptions.keepAliveCount = 10
        }
        clientChannel.state.addObserver(self, queue: dispatch_get_main_queue()) {
            (old, new) in

            log?.debug("State changed: \(old) -> \(new)")

            self.state = String(new)

            switch (old, new) {
                case (_, .disconnected):
                    self.connected = false
                case (_, .connected):
                    self.connected = true
                default:
                    break
            }
        }

        clientChannel.readCallback = {
            (result) in
            if case .failure(let error) = result {
                log?.debug("Client read callback: \(error)")
                return
            }
            log?.debug("Result: \(result)")
        }

        clientChannel.reconnectionDelay = 1 / 8
        clientChannel.shouldReconnect = {
            return self.reconnect
        }

        return clientChannel
    }

    @IBAction func connect(sender: AnyObject?) {

        if clientChannel == nil {
            try! clientChannel = createClient()
        }

        guard let clientChannel = clientChannel else {
            fatalError()
        }

        clientChannel.connect() {
            (result) in

            if case .failure(let error) = result {
                assert(clientChannel.state.value == .disconnected)
                SwiftIO.log?.debug("Client connect callback: \(error)")
                dispatch_async(dispatch_get_main_queue()) {
                    self.presentError(error as NSError)
                }
                return
            }
        }
    }

    @IBAction func disconnect(sender: AnyObject?) {
        guard let clientChannel = clientChannel else {
            fatalError()
        }

        clientChannel.disconnect() {
            (result) in
            SwiftIO.log?.debug("Client disconnect callback: \(result)")
        }
    }

    @IBAction func ping(sender: AnyObject?) {
        guard let clientChannel = clientChannel else {
            fatalError()
        }

        clientChannel.write(try! GenericDispatchData <UInt8> ("Hello \(count)\r\n")) {
            result in
        }

        count += 1
    }

}
