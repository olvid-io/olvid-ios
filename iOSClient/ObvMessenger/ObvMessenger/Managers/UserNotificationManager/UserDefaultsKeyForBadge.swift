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
import ObvEngine


// MARK: - Identifiers for the UserDefaults database

struct UserDefaultsKeyForBadge {
    
    static func keyForNewMessagesCountForOwnedIdentiy(with ownedCryptoId: ObvCryptoId) -> String {
        return "unread_messages_badge_for_\(ownedCryptoId.getIdentity().hexString())"
    }

    static func keyForInvitationsCountForOwnedIdentiy(with ownedCryptoId: ObvCryptoId) -> String {
        return "invitations_badge_for_\(ownedCryptoId.getIdentity().hexString())"
    }
    
    static let keyForAppBadgeCount = "app_badge_counter"

}
