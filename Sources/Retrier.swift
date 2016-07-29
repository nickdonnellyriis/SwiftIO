//
//  Retrier.swift
//  SwiftIO
//
//  Created by Jonathan Wight on 1/25/16.
//  Copyright © 2016 schwa.io. All rights reserved.
//

import SwiftUtilities

/// Helper to retry closures ('retryClosure') with truncated exponential backoff. See: https://en.wikipedia.org/wiki/Exponential_backoff
public class Retrier {

    // MARK:  Public Properties

    /// Configuration options for Retrier. Bundled into struct to add reuse.
    public struct Options {
        public var delay: TimeInterval = 0.25
        public var multiplier: Double = 2
        public var maximumDelay: TimeInterval = 8
        public var maximumAttempts: Int? = nil

        public init() {
        }
    }
    public let options: Options

    /// Pass in a Result describing success or failure. Return true if `Retrier` will retry.
    public typealias RetryStatus = (Result <Void>) -> Bool

    /// This is the action closure that is called repeated until it succeeds or a (optional) maximum attempts is exceeded. This closure is passed a `RetryStatus` closure that is used to pass success or failure back to `Retrier`.
    public let retryClosure: (RetryStatus) -> Void

    // MARK: Internal/Private Properties

    private let queue = DispatchQueue(label: "retrier", attributes: DispatchQueueAttributes.serial)
    private var attempts = Atomic(0)
    private var running = Atomic(false)

    // MARK: Public methods

    /// Initialisation. `Retrier` is created in an un-resumed state, you should call `resume()`.
    public init(options: Options, retryClosure: (RetryStatus) -> Void) {
        self.options = options
        self.retryClosure = retryClosure
    }

    /// Resume a `Retrier`
    public func resume() {
        running.with() {
            (running: inout Bool) in
            if running == false {
                running = true
                attempt()
            }
        }
    }

    /// Cancel a `retrier`. This will not cancel `retryClosure` already running, but will prevent subsequent retry attempts.
    public func cancel() {
        running.with() {
            (running: inout Bool) in
            if running == true {
                running = false
            }
        }
    }

    // Computer the next delay before retrying `retryClosure`.
    public func delayForAttempt(_ attempt: Int) -> TimeInterval {
        let expotentialDelay = options.delay * pow(TimeInterval(options.multiplier), TimeInterval(attempt))
        let truncatedDelay = min(expotentialDelay, options.maximumDelay)
        return truncatedDelay
    }

    // MARK: Internal/Private Methods

    private func attempt() {
        queue.async {
            [weak self] in

            guard let strong_self = self else {
                return
            }

            log?.debug("Retrying: Attempt \(strong_self.attempts.value)")

            if strong_self.running.value == true {
                strong_self.attempts.value += 1
                strong_self.retryClosure(strong_self.callback)
            }
        }
    }

    private func retry() {
        let delay = delayForAttempt(attempts.value - 1)
        log?.debug("Retrying: Sleeping for \(delay)")
        let time = DispatchTime.now() + Double(Int64(delay * TimeInterval(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
        (queue).after(when: time) {
            self.attempt()
        }
    }

    private func callback(_ result: Result <Void>) -> Bool {
        if case .failure = result {
            if let maximumAttempts = options.maximumAttempts, attempts.value > maximumAttempts {
                return false
            }
            retry()
        }
        return true
    }
}

extension Retrier {
    convenience init(delay: TimeInterval = 0.25, multiplier: Double = 2.0, maximumDelay: TimeInterval = 8, maximumAttempts: Int? = nil, retryClosure: (RetryStatus) -> Void) {
        var options = Options()
        options.delay = delay
        options.multiplier = multiplier
        options.maximumDelay = maximumDelay
        options.maximumAttempts = maximumAttempts
        self.init(options: options, retryClosure: retryClosure)
    }
}
