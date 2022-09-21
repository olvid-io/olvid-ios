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
import ObvTypes


/// This struct allows to simulate the behavior of two important methods of the UIApplication object available when launching the full
/// version of the engine, but not available when launching limited version of the engine.
final class BackgroundActivityEmulator: ObvBackgroundTaskManager {
    
    private let internalQueue = DispatchQueue(label: "BackgroundActivityEmulator Queue")
    private var _semaphoreForTaskIdentifier = [UIBackgroundTaskIdentifier: DispatchSemaphore]()
        
    
    func beginBackgroundTask(expirationHandler handler: (() -> Void)? = nil) -> UIBackgroundTaskIdentifier {
        
        let taskIdentifier = UIBackgroundTaskIdentifier.random()
        
        let semaphore = DispatchSemaphore(value: 0)
        
        internalQueue.sync {
            _semaphoreForTaskIdentifier[taskIdentifier] = semaphore
        }
        
        ProcessInfo.processInfo.performExpiringActivity(withReason: "BackgroundActivityEmulator") { (expired) in
            
            guard !expired else {
                debugPrint("[DEBUG] BAD SIGNAL")
                handler?()
                semaphore.signal()
                self._semaphoreForTaskIdentifier.removeValue(forKey: taskIdentifier)
                return
            }
            
            debugPrint("[DEBUG] WAITING...")
            semaphore.wait()
            debugPrint("[DEBUG] WAITING END")

        }
        
        return taskIdentifier
        
    }
    
    /// This is used by the share extension
    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier, completionHandler: (() -> Void)? = nil) {
        
        var semaphore: DispatchSemaphore?
        
        internalQueue.sync {
            semaphore = _semaphoreForTaskIdentifier.removeValue(forKey: identifier)
        }
        
        debugPrint("[DEBUG] GOOD SIGNAL ON \(String(describing: semaphore?.debugDescription))")
        semaphore?.signal()
        
        completionHandler?()
    }
}


fileprivate extension UIBackgroundTaskIdentifier {
    
    static func random() -> UIBackgroundTaskIdentifier {
        let randInt = Int.random(in: Int.min..<Int.max)
        return UIBackgroundTaskIdentifier(rawValue: randInt)
    }
    
}
