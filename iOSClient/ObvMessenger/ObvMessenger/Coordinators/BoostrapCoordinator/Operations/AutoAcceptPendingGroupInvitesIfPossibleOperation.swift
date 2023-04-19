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
import OlvidUtils
import ObvEngine
import os.log


final class AutoAcceptPendingGroupInvitesIfPossibleOperation: ContextualOperationWithSpecificReasonForCancel<AutoAcceptPendingGroupInvitesIfPossibleOperationReasonForCancel> {
    
    private let obvEngine: ObvEngine

    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        super.init()
    }

    override func main() {

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        // If the app settings is sich that we should never auto-accept group invitations, we are done.
        guard ObvMessengerSettings.ContactsAndGroups.autoAcceptGroupInviteFrom != .noOne else { return }
        
        obvContext.performAndWait {

            do {

                let allGroupInvites = try PersistedInvitation.getAllGroupInvitesForAllOwnedIdentities(within: obvContext.context)

                for groupInvite in allGroupInvites {

                    guard let ownedIdentity = groupInvite.ownedIdentity else { continue }
                    guard let obvDialog = groupInvite.obvDialog else { assertionFailure(); continue }

                    switch obvDialog.category {

                    case .acceptGroupInvite(groupMembers: _, groupOwner: let groupOwner):
                        
                        switch ObvMessengerSettings.ContactsAndGroups.autoAcceptGroupInviteFrom {
                        case .noOne:
                            continue
                        case .oneToOneContactsOnly:
                            let groupOwner = try PersistedObvContactIdentity.get(cryptoId: groupOwner.cryptoId, ownedIdentity: ownedIdentity, whereOneToOneStatusIs: .oneToOne)
                            let groupOwnerIsAOneToOneContact = (groupOwner != nil)
                            if groupOwnerIsAOneToOneContact {
                                var localDialog = obvDialog
                                try localDialog.setResponseToAcceptGroupInvite(acceptInvite: true)
                                obvEngine.respondTo(localDialog)
                            }
                        case .everyone:
                            var localDialog = obvDialog
                            try localDialog.setResponseToAcceptGroupInvite(acceptInvite: true)
                            obvEngine.respondTo(localDialog)
                        }
                        
                    case .acceptGroupV2Invite(inviter: let inviter, group: _):
                        
                        switch ObvMessengerSettings.ContactsAndGroups.autoAcceptGroupInviteFrom {
                        case .noOne:
                            continue
                        case .oneToOneContactsOnly:
                            let inviterContact = try PersistedObvContactIdentity.get(cryptoId: inviter, ownedIdentity: ownedIdentity, whereOneToOneStatusIs: .oneToOne)
                            let groupOwnerIsAOneToOneContact = (inviterContact != nil)
                            if groupOwnerIsAOneToOneContact {
                                var localDialog = obvDialog
                                try localDialog.setResponseToAcceptGroupV2Invite(acceptInvite: true)
                                obvEngine.respondTo(localDialog)
                            }
                        case .everyone:
                            var localDialog = obvDialog
                            try localDialog.setResponseToAcceptGroupV2Invite(acceptInvite: true)
                            obvEngine.respondTo(localDialog)
                        }

                    default:

                        assertionFailure("There is a bug with the getAllGroupInvites query")
                        continue

                    }
                }
                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
        
    }
    
}


public enum AutoAcceptPendingGroupInvitesIfPossibleOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case contextIsNil
    case couldNotAcceptGroupInvitation(error: Error)

    public var logType: OSLogType {
        .fault
    }

    public var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotAcceptGroupInvitation(error: let error):
            return "Could not accept group invitation: \(error.localizedDescription)"
        }
    }

}
