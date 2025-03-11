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
import ObvUICoreDataStructs


extension PersistedInvitation {
    
    public func toStructure() throws -> PersistedInvitationStructure {
        guard let obvDialog else {
            assertionFailure()
            throw ObvUICoreDataError.obvDialogIsNil
        }
        guard let ownedIdentity = self.ownedIdentity else {
            throw ObvUICoreDataError.contactsOwnedIdentityRelationshipIsNil
        }
        let inviterOrMediator: PersistedObvContactIdentityStructure?
        let oneToOneDiscussionWithInviterOrMediator: PersistedOneToOneDiscussionStructure?
        switch obvDialog.category {
        case .acceptGroupV2Invite(inviter: let inviterCryptoId, group: _):
            guard let context = self.managedObjectContext else {
                assertionFailure()
                throw ObvUICoreDataError.noContext
            }
            guard let inviterContact = try PersistedObvContactIdentity.get(contactCryptoId: inviterCryptoId, ownedIdentityCryptoId: obvDialog.ownedCryptoId, whereOneToOneStatusIs: .any, within: context) else {
                assertionFailure()
                throw ObvUICoreDataError.unexpectedContact
            }
            inviterOrMediator = try inviterContact.toStructure()
            oneToOneDiscussionWithInviterOrMediator = try inviterContact.oneToOneDiscussion?.toStructure()
        case .acceptMediatorInvite(contactIdentity: _, mediatorIdentity: let mediatorIdentity):
            guard let context = self.managedObjectContext else {
                assertionFailure()
                throw ObvUICoreDataError.noContext
            }
            guard let mediatorContact = try PersistedObvContactIdentity.get(contactCryptoId: mediatorIdentity.cryptoId, ownedIdentityCryptoId: obvDialog.ownedCryptoId, whereOneToOneStatusIs: .any, within: context) else {
                assertionFailure()
                throw ObvUICoreDataError.unexpectedContact
            }
            inviterOrMediator = try mediatorContact.toStructure()
            oneToOneDiscussionWithInviterOrMediator = try mediatorContact.oneToOneDiscussion?.toStructure()
        default:
            inviterOrMediator = nil
            oneToOneDiscussionWithInviterOrMediator = nil
        }
        return .init(actionRequired: self.actionRequired,
                     date: self.date,
                     obvDialog: obvDialog,
                     status: self.status.toPersistedInvitationStructureStatus,
                     ownedIdentity: try ownedIdentity.toStructure(),
                     inviterOrMediator: inviterOrMediator,
                     oneToOneDiscussionWithInviterOrMediator: oneToOneDiscussionWithInviterOrMediator)
    }
    
}


fileprivate extension PersistedInvitation.Status {
    
    var toPersistedInvitationStructureStatus: PersistedInvitationStructure.Status {
        switch self {
        case .new: return .new
        case .updated: return .updated
        case .old: return .old
        }
    }
    
}
