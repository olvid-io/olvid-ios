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
import Network

struct FetchRetryManager {
    
    private var timers = [DispatchSourceTimer]()
    private let privateQueue = DispatchQueue(label: "FetchRetryManager")

    /// Execute the specified block in the future.
    /// - Parameters:
    ///   - delay: A delay in milliseconds
    ///   - block: The block to execute.
    mutating func executeWithDelay(_ delay: Int, block: @escaping () -> Void) {
        let timer = DispatchSource.makeTimerSource(flags: [], queue: privateQueue)
        timer.setEventHandler {
            block()
        }
        timers.append(timer)
        timer.schedule(deadline: .now() + .milliseconds(delay), repeating: .never)
        timer.resume()
    }
    
    
    mutating func executeAllWithNoDelay() {
        while let timer = timers.popLast() {
            timer.activate()
        }
    }
    
}
