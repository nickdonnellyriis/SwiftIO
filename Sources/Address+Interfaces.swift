//
//  Address+Interfaces.swift
//  SwiftIO
//
//  Created by Jonathan Wight on 3/18/16.
//  Copyright © 2016 schwa.io. All rights reserved.
//

import Darwin

public extension Address {
    static func addressesForInterfaces() throws -> [String: [Address]] {
        let addressesForInterfaces = getAddressesForInterfaces() as! [String: [Data]]
        let pairs: [(key: String, value: [Address])] = addressesForInterfaces.flatMap() {
            (interface, addressData) -> (String, [Address])? in

            if addressData.count == 0 {
                return nil
            }
            let addresses = addressData.map() {
                (addressData: Data) -> Address in
                let addr = sockaddr_storage(addr: UnsafePointer <sockaddr> ((addressData as NSData).bytes), length: addressData.count)
                let address = Address(sockaddr: addr)
                return address
            }
            return (interface, addresses.sorted(isOrderedBefore: <))
        }

        return Dictionary <String, [Address]> (pairs: pairs)
    }
}

// MARK: -


private extension Dictionary {
    init(pairs: [Element]) {
        self.init()
        for (k, v) in pairs {
            self[k] = v
        }
    }
}
