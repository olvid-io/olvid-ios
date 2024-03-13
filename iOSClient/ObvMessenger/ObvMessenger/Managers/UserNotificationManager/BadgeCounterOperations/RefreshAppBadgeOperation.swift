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
import os.log
import ObvEngine
import ObvUICoreData
import OlvidUtils

/// Operations that updates the badge on the app icon. This is the only allowed place to do so.
final class RefreshAppBadgeOperation: Operation {
    
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

            userDefaults.set(newBadgeValue, forKey: UserDefaultsKeyForBadge.keyForAppBadgeCount)

            let log = self.log
            
            DispatchQueue.main.async {
                
                os_log("[🔴][RefreshAppBadgeOperation] setting new badge value to %d", log: log, type: .debug, newBadgeValue)

                if #available(iOS 16, *) {
                    UNUserNotificationCenter.current().setBadgeCount(newBadgeValue) { error in
                        guard error == nil else { assertionFailure(); return }
                    }
                } else {
                    guard UIApplication.shared.applicationIconBadgeNumber != newBadgeValue else { return }
                    UIApplication.shared.applicationIconBadgeNumber = newBadgeValue
                }
                
            }
            
        }
        
    }
    
}
