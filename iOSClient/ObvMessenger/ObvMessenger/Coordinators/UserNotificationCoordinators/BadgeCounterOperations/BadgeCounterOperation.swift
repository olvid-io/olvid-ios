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
import os.log
import ObvEngine


class BadgeCounterOperation: Operation {
    
    let ownedCryptoId: ObvCryptoId
    let log: OSLog
    let userDefaults: UserDefaults
    
    init(ownedCryptoId: ObvCryptoId, userDefaults: UserDefaults, log: OSLog) {
        self.ownedCryptoId = ownedCryptoId
        self.userDefaults = userDefaults
        self.log = log
        super.init()
    }
    
    
    func setCurrentCountForNewMessagesBadge(to newCount: Int) {
        let appropriateNewCount = max(0, newCount)
        userDefaults.set(appropriateNewCount, forKey: UserDefaultsKeyForBadge.keyForNewMessagesCountForOwnedIdentiy(with: ownedCryptoId))
        sendBadgesNeedToBeUpdatedNotification()
    }
    
    
    func setCurrentCountForInvitationsBadge(to newCount: Int) {
        let appropriateNewCount = max(0, newCount)
        userDefaults.set(appropriateNewCount, forKey: UserDefaultsKeyForBadge.keyForInvitationsCountForOwnedIdentiy(with: ownedCryptoId))
        sendBadgesNeedToBeUpdatedNotification()
    }

    
    private func sendBadgesNeedToBeUpdatedNotification() {
        ObvMessengerInternalNotification.badgesNeedToBeUpdated(ownedCryptoId: ownedCryptoId).postOnDispatchQueue()
    }
}
