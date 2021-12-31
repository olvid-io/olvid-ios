/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
