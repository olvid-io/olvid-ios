/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import os.log
import UserNotifications
import ObvEngine
import ObvUICoreData
import OlvidUtils

/// Operation that updates the badge on the app icon. This is the only place where the **app** does so: user notifications scheduled
/// from the app must never carry a badge value, as it would override the value computed here.
///
/// Note that the app is not the only process setting the app icon badge: the notification extension does so through the badge
/// value of the user notifications it publishes (computed from the currently shown user notifications rather than from the app
/// database, as the latter is usually unaware of the messages received since the app was last running), and the intents extension
/// does so directly when Siri marks a message as read.
final class RefreshAppBadgeOperation: Operation, @unchecked Sendable {
    
    let log: OSLog
    let userDefaults: UserDefaults

    init(userDefaults: UserDefaults, log: OSLog) {
        self.userDefaults = userDefaults
        self.log = log
        super.init()
    }

    
    override func main() {
        
        os_log("[🔴][RefreshAppBadgeOperation] start", log: log, type: .debug)
        defer {
            os_log("[🔴][RefreshAppBadgeOperation] end", log: log, type: .debug)
        }
        
        ObvStack.shared.performBackgroundTaskAndWait { [weak self] (context) in
            
            guard let self else { return }
            
            guard let newBadgeValue = try? PersistedObvOwnedIdentity.computeAppBadgeValue(within: context) else { cancel(); return }

            let log = self.log
            
            DispatchQueue.main.async {
                
                os_log("[🔴][RefreshAppBadgeOperation] setting new badge value to %d", log: log, type: .debug, newBadgeValue)

                UNUserNotificationCenter.current().setBadgeCount(newBadgeValue) { error in
                    guard error == nil else { assertionFailure(); return }
                }
                
            }
            
        }
        
    }
    
}
