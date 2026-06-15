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

import Foundation
import ObvTypes
import ObvDesignSystem


public struct OwnedIdentityChooserViewModel: Sendable, Equatable {

    let ownedIdentities: [OwnedIdentity]

    public init(ownedIdentities: [OwnedIdentity]) {
        self.ownedIdentities = ownedIdentities
    }
    
    public struct OwnedIdentity: Sendable, Identifiable, Equatable {
        let ownedCryptoId: ObvCryptoId
        let avatarViewModel: ObvAvatarViewModel
        let title: String
        let subtitle: String
        let totalBadgeCount: Int
        let showGreenShield: Bool
        let showRedShield: Bool
        let showHiddenProfileIcon: Bool
        public var id: Data { ownedCryptoId.getIdentity() }
        
        public init(ownedCryptoId: ObvCryptoId, avatarViewModel: ObvAvatarViewModel, title: String, subtitle: String, totalBadgeCount: Int, showGreenShield: Bool, showRedShield: Bool, showHiddenProfileIcon: Bool) {
            self.ownedCryptoId = ownedCryptoId
            self.avatarViewModel = avatarViewModel
            self.title = title
            self.subtitle = subtitle
            self.totalBadgeCount = totalBadgeCount
            self.showGreenShield = showGreenShield
            self.showRedShield = showRedShield
            self.showHiddenProfileIcon = showHiddenProfileIcon
        }
        
    }
    
}
