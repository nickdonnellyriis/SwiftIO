//
//  TCPServerViewController.swift
//  SwiftIO
//
//  Created by Jonathan Wight on 12/8/15.
//  Copyright © 2015 schwa.io. All rights reserved.
//

import AppKit

import SwiftIO
import SwiftUtilities

class TCPServerViewController: NSViewController {

    typealias Record = TLVRecord <UInt16, UInt16>
    let endianness = Endianness.Big

    let port: UInt16 = 40000
    var server: TCPServer?

    dynamic var serving: Bool = false

    dynamic var addressString: String? = "0.0.0.0:40000"

}

extension TCPServerViewController {

    func createServer() throws -> TCPServer {

        let address = try Address(address: "0.0.0.0", port: self.port)
        let server = try TCPServer(address: address)

        server.clientWillConnect = {
            (client) in

            log?.debug("clientWillConnect: \(try! client.socket.getPeer())")

            var buffer = GenericDispatchData <UInt8> ()
            client.readCallback = {
                (result) in

                log?.debug("Server Got data")

                if case .success(let data) = result {
                    buffer = buffer + data
                    let (records, remaining) = try! Record.readMultiple(buffer, endianness: self.endianness)
                    for record in records {
                        dispatch_async(dispatch_get_main_queue()) {
                            let string = try! String(data: record.data)
                            SwiftIO.log?.debug("Server received: \(string)")
                        }
                    }
                    buffer = remaining
                }
            }
        }
        server.clientDidDisconnect = {
            (client) in

            log?.debug("clientDidDisconnect")
        }
        return server
    }

}


extension TCPServerViewController {

    @IBAction func startStopServer(sender: SwitchControl) {
        if sender.on {
            log?.debug("Server start listening")

            let server = try! createServer()
            try! server.startListening()
            self.server = server
            serving = true
        }
        else {
            log?.debug("Server stop listening")
            try! server?.stopListening()
            server = nil
            serving = false
        }
    }

    @IBAction func disconnectAll(sender: AnyObject?) {
        try! server?.disconnectAllClients()
    }

}


extension String {
    init(data: GenericDispatchData <UInt8>, encoding: NSStringEncoding = NSUTF8StringEncoding) throws {
        let nsdata = data.toNSData()
        self = NSString(data: nsdata, encoding: encoding) as! String
    }
}


class BoxedAddressValueTransformer: NSValueTransformer {

    override func transformedValue(value: AnyObject?) -> AnyObject? {
        guard let box = value as? Box <Address> else {
            return nil
        }
        let address = box.value
        return String(address)
    }

    override func reverseTransformedValue(value: AnyObject?) -> AnyObject? {
        guard let string = value as? String else {
            return nil
        }
        guard let address = try? Address(address: string) else {
            return nil
        }
        let box = Box(address)
        return box
    }



}
