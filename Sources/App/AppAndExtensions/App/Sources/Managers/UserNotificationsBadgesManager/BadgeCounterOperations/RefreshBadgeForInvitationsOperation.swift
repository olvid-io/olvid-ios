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
import OSLog
import ObvUICoreData
import OlvidUtils
import ObvTypes


final class RefreshBadgeForInvitationsOperation: Operation, @unchecked Sendable {
    
    let ownedCryptoId: ObvCryptoId
    let log: OSLog
    let userDefaults: UserDefaults
    
    init(ownedCryptoId: ObvCryptoId, userDefaults: UserDefaults, log: OSLog) {
        self.ownedCryptoId = ownedCryptoId
        self.userDefaults = userDefaults
        self.log = log
        super.init()
    }

    override func main() {
        guard !isCancelled else { return }
        
//        ObvDisplayableLogs.shared.log("[🔴][RefreshBadgeForInvitationsOperation] start")
//        defer {
//            ObvDisplayableLogs.shared.log("[🔴][RefreshBadgeForInvitationsOperation] end")
//        }
        
        let ownedCryptoId = self.ownedCryptoId
        
        ObvStack.shared.performBackgroundTaskAndWait { [weak self] (context) in
            guard let _self = self else { return }
            guard let persistedOwnedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: _self.ownedCryptoId, within: context) else { _self.cancel();  return }
            guard !_self.isCancelled else { return }
            
            let appropriateNewCount = max(0, persistedOwnedIdentity.badgeCountForInvitationsTab)
            ObvMessengerInternalNotification.badgeForInvitationsHasBeenUpdated(ownedCryptoId: ownedCryptoId, newCount: appropriateNewCount)
                .postOnDispatchQueue()

        }
    }
    
}
