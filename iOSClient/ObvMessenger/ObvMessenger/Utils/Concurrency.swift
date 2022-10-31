/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
 *
 *  This file is part of Olvid for iOS.
 *
 *  Olvid is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License, version 3,
 *  as published by the Free Software Foundation.
 *
 *  Olvid is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation

struct Concurrency {

    private init() { /* You shall not pass */ }

    /// Queue used to synchronize creation of the queues.
    private static let internalQueue = DispatchQueue(label: "Concurrency.internalQueue")

    /// Internal queues
    private static var queues: [String: DispatchQueue] = [:]

    /// Returns the queue that corresponds to the given lock name
    private static func internalQueue(_ lock: String) -> DispatchQueue {
        internalQueue.sync {
            if let queue = queues[lock] {
                return queue
            }
            let queue = DispatchQueue(label: "Concurrency.\(lock).queue")
            queues[lock] = queue
            return queue
        }
    }

    /// Synchronize the given code on the given lock
    static func sync<T>(lock: String, code: () -> T) -> T {
        let queue = internalQueue(lock)
        return queue.sync(execute: code)
    }

}

/// Stores a continuation to resume it later when the result it available and passed to ``setResult``
/// This actor can be used in a ``withCheckedContinuation`` block.
actor CheckedContinuationHolder<T> {

    private(set) var result: T? = nil
    private var continuation: CheckedContinuation<T, Never>?
    private var continuationHasBeenSet = false

    /// Set the continuation and resume it if the result is set, must be called only once
    func setContinuation(_ continuation: CheckedContinuation<T, Never>) {
        guard !continuationHasBeenSet else { assertionFailure(); return }
        if let result = self.result {
            // ``result`` has been set by ``setResult()`` we can resume the continuation
            continuation.resume(returning: result)
        } else {
            // Store continuation, to resume it with ``setResult()``
            guard self.continuation == nil else { assertionFailure(); return }
            self.continuation = continuation
            self.continuationHasBeenSet = true
        }
    }

    /// Set the result and resume the continuation if it is set, do nothing if the result is already set.
    func setResult(_ result: T) {
        if let continuation = self.continuation {
            continuation.resume(returning: result)
            self.continuation = nil // To be sure to not resume the continuation twice
        } else {
            guard self.result == nil else { return }
            // Store result to pass it later to continuation that will be set by ``setContinuation``
            self.result = result
        }
    }

}
