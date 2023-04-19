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

final class ProcessObvDialogOperation: ContextualOperationWithSpecificReasonForCancel<ProcessObvDialogOperationReasonForCancel> {
    
    private let obvDialog: ObvDialog
    private let obvEngine: ObvEngine

    init(obvDialog: ObvDialog, obvEngine: ObvEngine) {
        self.obvDialog = obvDialog
        self.obvEngine = obvEngine
        super.init()
    }

    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {
            
            // In the case the ObvDialog is a group invite, it might be possible to auto-accept the invitation
                        
            switch obvDialog.category {
                
            case .acceptGroupInvite(groupMembers: _, groupOwner: let groupOwner):
                
                switch ObvMessengerSettings.ContactsAndGroups.autoAcceptGroupInviteFrom {
                case .everyone:
                    var localDialog = obvDialog
                    do {
                        try localDialog.setResponseToAcceptGroupInvite(acceptInvite: true)
                    } catch {
                        return cancel(withReason: .couldNotRespondToDialog(error: error))
                    }
                    obvEngine.respondTo(localDialog)
                    return
                case .oneToOneContactsOnly:
                    do {
                        let persistedOneToOneContact = try PersistedObvContactIdentity.get(contactCryptoId: groupOwner.cryptoId, ownedIdentityCryptoId: obvDialog.ownedCryptoId, whereOneToOneStatusIs: .oneToOne, within: obvContext.context)
                        if persistedOneToOneContact != nil {
                            var localDialog = obvDialog
                            do {
                                try localDialog.setResponseToAcceptGroupInvite(acceptInvite: true)
                            } catch {
                                return cancel(withReason: .couldNotRespondToDialog(error: error))
                            }
                            obvEngine.respondTo(localDialog)
                            return
                        }
                    } catch {
                        return cancel(withReason: .coreDataError(error: error))
                    }
                case .noOne:
                    break
                }
                
            case .acceptGroupV2Invite(inviter: let inviter, group: _):
                
                switch ObvMessengerSettings.ContactsAndGroups.autoAcceptGroupInviteFrom {
                case .everyone:
                    var localDialog = obvDialog
                    do {
                        try localDialog.setResponseToAcceptGroupV2Invite(acceptInvite: true)
                    } catch {
                        return cancel(withReason: .couldNotRespondToDialog(error: error))
                    }
                    obvEngine.respondTo(localDialog)
                    return
                case .oneToOneContactsOnly:
                    do {
                        let inviterContact = try PersistedObvContactIdentity.get(contactCryptoId: inviter, ownedIdentityCryptoId: obvDialog.ownedCryptoId, whereOneToOneStatusIs: .oneToOne, within: obvContext.context)
                        if inviterContact != nil {
                            var localDialog = obvDialog
                            do {
                                try localDialog.setResponseToAcceptGroupV2Invite(acceptInvite: true)
                            } catch {
                                return cancel(withReason: .couldNotRespondToDialog(error: error))
                            }
                            obvEngine.respondTo(localDialog)
                            return
                        }
                    } catch {
                        return cancel(withReason: .coreDataError(error: error))
                    }
                case .noOne:
                    break
                }

            default:
                break
            }
            
            // If we reach this point, we could not auto-accept the ObvDialog.
            // We persist it. Depending on the category, we create a subentity of
            // PersistedInvitation (which is the "new" way of dealing with invitations),
            // Or create a "generic" PersistedInvitation.

            do {
                switch obvDialog.category {
                case .oneToOneInvitationSent:
                    if try PersistedInvitationOneToOneInvitationSent.getPersistedInvitation(uuid: obvDialog.uuid, ownedCryptoId: obvDialog.ownedCryptoId, within: obvContext.context) == nil {
                        _ = try PersistedInvitationOneToOneInvitationSent(obvDialog: obvDialog, within: obvContext.context)
                    }
                default:
                    try PersistedInvitation.insertOrUpdate(obvDialog, within: obvContext.context)
                }
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
        
    }
        
}


enum ProcessObvDialogOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case contextIsNil
    case couldNotRespondToDialog(error: Error)

    var logType: OSLogType {
        .fault
    }
    
    var errorDescription: String? {
        switch self {
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .contextIsNil:
            return "The context is not set"
        case .couldNotRespondToDialog(error: let error):
            return "Could not respond to dialog: \(error.localizedDescription)"
        }
    }

}
