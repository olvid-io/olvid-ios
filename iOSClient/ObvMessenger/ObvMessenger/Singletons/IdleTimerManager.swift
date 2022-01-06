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

import UIKit


/// This singleton centralizes all requests to disable/enable the app idle timer, preventing the system to put the device into a "sleep” state where the screen dims.
final class IdleTimerManager {
    
    static let shared = IdleTimerManager()
    
    private init() {}
    
    private var currentDisableIdleTimerRequestIdentifiers = Set<UUID>()

    
    /// Requests this manager to disable the app idle timer, preventing the system to put the device into a "sleep” state where the screen dims.
    /// - Returns: A request `UUID` that can be used in the ``enableIdleTimer(disableRequestIdentifier:)`` method.
    func disableIdleTimer() -> UUID {
        assert(Thread.isMainThread)
        let requestIdentifier = UUID()
        currentDisableIdleTimerRequestIdentifiers.insert(requestIdentifier)
        UIApplication.shared.isIdleTimerDisabled = true
        return requestIdentifier
    }

    
    /// Requests this manager to enable the app idle timer.
    /// - Parameter disableRequestIdentifier: A request `UUID` as received during the call to ``disableIdleTimer()``.
    ///
    /// This method succeeds, unless another requests to disable the idle timer is still active.
    func enableIdleTimer(disableRequestIdentifier: UUID) {
        assert(Thread.isMainThread)
        _ = currentDisableIdleTimerRequestIdentifiers.remove(disableRequestIdentifier)
        guard currentDisableIdleTimerRequestIdentifiers.isEmpty else { return }
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    
    /// Request this manager to enable the app idle timer. This method always succeeds.
    func forceEnableIdleTimer() {
        assert(Thread.isMainThread)
        currentDisableIdleTimerRequestIdentifiers.removeAll()
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
}
