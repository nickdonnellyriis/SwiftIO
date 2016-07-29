//
//  Utilities.swift
//  SwiftIO
//
//  Created by Jonathan Wight on 1/10/16.
//  Copyright © 2016 schwa.io. All rights reserved.
//

import Darwin

internal extension timeval {
    init(time: TimeInterval) {
        tv_sec = __darwin_time_t(time)
        tv_usec = __darwin_suseconds_t((time - floor(time)) * TimeInterval(USEC_PER_SEC))
    }

    var timeInterval: TimeInterval {
        return TimeInterval(tv_sec) + TimeInterval(tv_usec) / TimeInterval(USEC_PER_SEC)
    }
}

internal extension timeval64 {
    init(time: TimeInterval) {
        tv_sec = __int64_t(time)
        tv_usec = __int64_t((time - floor(time)) * TimeInterval(USEC_PER_SEC))
    }

    var timeInterval: TimeInterval {
        return TimeInterval(tv_sec) + TimeInterval(tv_usec) / TimeInterval(USEC_PER_SEC)
    }

}

internal func unsafeCopy <DST, SRC> (destination: UnsafeMutablePointer <DST>, source: UnsafePointer <SRC>) {
    let length = min(sizeof(DST.self), sizeof(SRC.self))
    unsafeCopy(destination: destination, source: source, length: length)
}

internal func unsafeCopy <DST> (destination: UnsafeMutablePointer <DST>, source: UnsafePointer <Void>, length: Int) {
    precondition(sizeof(DST.self) >= length)
    memcpy(destination, source, length)
}
