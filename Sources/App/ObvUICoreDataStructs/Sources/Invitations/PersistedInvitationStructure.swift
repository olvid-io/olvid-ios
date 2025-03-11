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


public struct PersistedInvitationStructure {
    
    let actionRequired: Bool
    let date: Date
    public let obvDialog: ObvDialog
    let status: Status
    public let ownedIdentity: PersistedObvOwnedIdentityStructure
    public let inviterOrMediator: PersistedObvContactIdentityStructure? // Only set when the obvDialog.category is acceptGroupV2Invite or acceptMediatorInvite
    public let oneToOneDiscussionWithInviterOrMediator: PersistedOneToOneDiscussionStructure? // May be set if the obvDialog.category is acceptGroupV2Invite or acceptMediatorInvite, but only if the inviter/mediator is a one2one contact

    public enum Status: Int {
        case new = 0
        case updated = 1
        case old = 3
    }

    public init(actionRequired: Bool, date: Date, obvDialog: ObvDialog, status: Status, ownedIdentity: PersistedObvOwnedIdentityStructure, inviterOrMediator: PersistedObvContactIdentityStructure?, oneToOneDiscussionWithInviterOrMediator: PersistedOneToOneDiscussionStructure?) {
        self.actionRequired = actionRequired
        self.date = date
        self.obvDialog = obvDialog
        self.status = status
        self.ownedIdentity = ownedIdentity
        self.inviterOrMediator = inviterOrMediator
        self.oneToOneDiscussionWithInviterOrMediator = oneToOneDiscussionWithInviterOrMediator
    }
    
}

