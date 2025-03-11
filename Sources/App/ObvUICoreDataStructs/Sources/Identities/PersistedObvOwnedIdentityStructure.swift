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
import ObvTypes


public struct PersistedObvOwnedIdentityStructure {
    
    public let cryptoId: ObvCryptoId
    public let fullDisplayName: String
    public let identityCoreDetails: ObvIdentityCoreDetails
    public let photoURL: URL?
    public let isHidden: Bool
    public let badgeCountForDiscussionsTab: Int
    public let badgeCountForInvitationsTab: Int

    public init(cryptoId: ObvCryptoId, fullDisplayName: String, identityCoreDetails: ObvIdentityCoreDetails, photoURL: URL?, isHidden: Bool, badgeCountForDiscussionsTab: Int, badgeCountForInvitationsTab: Int) {
        self.cryptoId = cryptoId
        self.fullDisplayName = fullDisplayName
        self.identityCoreDetails = identityCoreDetails
        self.photoURL = photoURL
        self.isHidden = isHidden
        self.badgeCountForDiscussionsTab = badgeCountForDiscussionsTab
        self.badgeCountForInvitationsTab = badgeCountForInvitationsTab
    }
    
    public var badgeCount: Int {
        badgeCountForDiscussionsTab + badgeCountForInvitationsTab
    }
    
}
