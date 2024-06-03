/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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

//struct SendRetryManager {
//    
//    private var timers = [DispatchSourceTimer]()
//    private let privateQueue = DispatchQueue(label: "SendRetryManager")
//
//    /// Execute the specified block in the future.
//    /// - Parameters:
//    ///   - delay: A delay in milliseconds
//    ///   - block: The block to execute.
//    mutating func executeWithDelay(_ delay: Int, block: @escaping () -> Void) {
//        let timer = DispatchSource.makeTimerSource(flags: [], queue: privateQueue)
//        timer.setEventHandler {
//            block()
//        }
//        timers.append(timer)
//        timer.schedule(deadline: .now() + .milliseconds(delay), repeating: .never)
//        timer.resume()
//    }
//    
//    
//    mutating func executeAllWithNoDelay() {
//        while let timer = timers.popLast() {
//            timer.activate()
//        }
//    }
//    
//}


actor SendRetryManager {
    
    private var sleepTasks = [UUID: Task<Void, Never>]()
    
    func waitForDelay(milliseconds: Int) async {
        let uuid = UUID()
        let task = Task { () -> Void in
            do { try await Task.sleep(milliseconds: milliseconds) } catch {}
        }
        sleepTasks[uuid] = task
        await task.value
        _ = sleepTasks.removeValue(forKey: uuid)
    }
    
    
    func executeAllWithNoDelay() {
        while let (_, task) = sleepTasks.popFirst() {
            guard !task.isCancelled else { return }
            task.cancel()
        }
    }

}
