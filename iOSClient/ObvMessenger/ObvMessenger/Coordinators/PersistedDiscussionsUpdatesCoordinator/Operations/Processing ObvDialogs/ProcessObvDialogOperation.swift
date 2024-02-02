/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvUICoreData
import CoreData
import ObvTypes
import ObvSettings


final class ProcessObvDialogOperation: ContextualOperationWithSpecificReasonForCancel<ProcessObvDialogOperation.ReasonForCancel> {
    
    private let obvDialog: ObvDialog
    private let obvEngine: ObvEngine
    private let syncAtomRequestDelegate: ObvSyncAtomRequestDelegate

    init(obvDialog: ObvDialog, obvEngine: ObvEngine, syncAtomRequestDelegate: ObvSyncAtomRequestDelegate) {
        self.obvDialog = obvDialog
        self.obvEngine = obvEngine
        self.syncAtomRequestDelegate = syncAtomRequestDelegate
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
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
                let dialogForEngine = localDialog
                Task {
                    try? await obvEngine.respondTo(dialogForEngine)
                }
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
                        let dialogForEngine = localDialog
                        Task {
                            try? await obvEngine.respondTo(dialogForEngine)
                        }
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
                let dialogForEngine = localDialog
                Task {
                    try? await obvEngine.respondTo(dialogForEngine)
                }
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
                        let dialogForEngine = localDialog
                        Task {
                            try? await obvEngine.respondTo(dialogForEngine)
                        }
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
        
        // In case we receive an ObvSyncAtom from the protocol manager, we can process it immediately
        
        switch obvDialog.category {
        case .syncRequestReceivedFromOtherOwnedDevice(otherOwnedDeviceIdentifier: _, syncAtom: let syncAtom):
            do {
                try process(syncAtom: syncAtom, ownedCryptoId: obvDialog.ownedCryptoId, within: obvContext, viewContext: viewContext)
                try syncAtomRequestDelegate.deleteDialog(with: obvDialog.uuid)
            } catch {
                return cancel(withReason: .couldNotProcessSyncAtom(syncAtom: syncAtom))
            }
            // The atom was processed, we can return
            return
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
    
    
    private func process(syncAtom: ObvSyncAtom, ownedCryptoId: ObvCryptoId, within obvContext: ObvContext, viewContext: NSManagedObjectContext) throws {
        
        switch syncAtom {
        case .contactNickname(contactCryptoId: let contactCryptoId, contactNickname: let contactNickname):
            let contactIdentifier = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            guard let contact = try PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: obvContext.context) else { assertionFailure(); return }
            let op1 = UpdateCustomNicknameAndPictureForContactOperation(persistedContactObjectID: contact.objectID, customDisplayName: contactNickname, customPhoto: .url(url: contact.customPhotoURL), makeSyncAtomRequest: false, syncAtomRequestDelegate: nil)
            op1.main(obvContext: obvContext, viewContext: viewContext)
            assert(!op1.isCancelled)
        case .groupV1Nickname(groupOwner: let groupOwner, groupUid: let groupUid, groupNickname: let groupNickname):
            let groupIdentifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            let op1 = SetCustomNameOfJoinedGroupV1Operation(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier, groupNameCustom: groupNickname, makeSyncAtomRequest: false, syncAtomRequestDelegate: nil)
            op1.main(obvContext: obvContext, viewContext: viewContext)
            assert(!op1.isCancelled)
        case .groupV2Nickname(groupIdentifier: let groupIdentifier, groupNickname: let groupNickname):
            let op1 = UpdateCustomNameAndGroupV2PhotoOperation(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier, update: .customName(customName: groupNickname), makeSyncAtomRequest: false, syncAtomRequestDelegate: nil)
            op1.main(obvContext: obvContext, viewContext: viewContext)
            assert(!op1.isCancelled)
        case .contactPersonalNote(contactCryptoId: let contactCryptoId, note: let note):
            let contactIdentifier = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            let op1 = UpdatePersonalNoteOnContactOperation(contactIdentifier: contactIdentifier, newText: note, makeSyncAtomRequest: false, syncAtomRequestDelegate: nil)
            op1.main(obvContext: obvContext, viewContext: viewContext)
            assert(!op1.isCancelled)
        case .groupV1PersonalNote(groupOwner: let groupOwner, groupUid: let groupUid, note: let note):
            let groupIdentifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            let op1 = UpdatePersonalNoteOnGroupV1Operation(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier, newText: note, makeSyncAtomRequest: false, syncAtomRequestDelegate: nil)
            op1.main(obvContext: obvContext, viewContext: viewContext)
            assert(!op1.isCancelled)
        case .groupV2PersonalNote(groupIdentifier: let groupIdentifier, note: let note):
            let op1 = UpdatePersonalNoteOnGroupV2Operation(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier, newText: note, makeSyncAtomRequest: false, syncAtomRequestDelegate: nil)
            op1.main(obvContext: obvContext, viewContext: viewContext)
            assert(!op1.isCancelled)
        case .ownProfileNickname(nickname: let nickname):
            let op1 = UpdateOwnedCustomDisplayNameOperation(ownedCryptoId: ownedCryptoId, newCustomDisplayName: nickname, makeSyncAtomRequest: false, syncAtomRequestDelegate: nil)
            op1.main(obvContext: obvContext, viewContext: viewContext)
            assert(!op1.isCancelled)
        case .contactCustomHue(contactCryptoId: _, customHue: _):
            // Not implemented under iOS. The protocol manager is not supposed to notify us
            assertionFailure()
            return
        case .contactSendReadReceipt(contactCryptoId: let contactCryptoId, doSendReadReceipt: let doSendReadReceipt):
            let contactIdentifier = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            let op1 = UpdateDiscussionLocalConfigurationOperation(
                value: .doSendReadReceipt(doSendReadReceipt),
                input: .discussionWithOneToOneContact(contactIdentifier: contactIdentifier),
                makeSyncAtomRequest: false,
                syncAtomRequestDelegate: nil)
            op1.main(obvContext: obvContext, viewContext: viewContext)
            assert(!op1.isCancelled)
        case .groupV1ReadReceipt(groupOwner: let groupOwner, groupUid: let groupUid, doSendReadReceipt: let doSendReadReceipt):
            let groupIdentifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            let op1 = UpdateDiscussionLocalConfigurationOperation(
                value: .doSendReadReceipt(doSendReadReceipt),
                input: .groupV1Discussion(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier),
                makeSyncAtomRequest: false,
                syncAtomRequestDelegate: nil)
            op1.main(obvContext: obvContext, viewContext: viewContext)
            assert(!op1.isCancelled)
        case .groupV2ReadReceipt(groupIdentifier: let groupIdentifier, doSendReadReceipt: let doSendReadReceipt):
            let op1 = UpdateDiscussionLocalConfigurationOperation(
                value: .doSendReadReceipt(doSendReadReceipt),
                input: .groupV2Discussion(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier),
                makeSyncAtomRequest: false,
                syncAtomRequestDelegate: nil)
            op1.main(obvContext: obvContext, viewContext: viewContext)
            assert(!op1.isCancelled)
        case .trustContactDetails:
            // This atom should be dealt with by the identity manager and shouldn't have been received here
            assertionFailure()
            return
        case .trustGroupV1Details:
            // This atom should be dealt with by the identity manager and shouldn't have been received here
            assertionFailure()
            return
        case .trustGroupV2Details:
            // This atom should be dealt with by the identity manager and shouldn't have been received here
            assertionFailure()
        case .pinnedDiscussions(discussionIdentifiers: let discussionIdentifiers, ordered: let ordered):
            let op1 = ReorderDiscussionsOperation(input: .discussionsIdentifiers(discussionIdentifiers: discussionIdentifiers, ordered: ordered), ownedIdentity: ownedCryptoId, makeSyncAtomRequest: false, syncAtomRequestDelegate: nil)
            op1.main(obvContext: obvContext, viewContext: viewContext)
            assert(!op1.isCancelled)
        case .settingDefaultSendReadReceipts(sendReadReceipt: let sendReadReceipt):
            ObvMessengerSettings.Discussions.setDoSendReadReceipt(to: sendReadReceipt, changeMadeFromAnotherOwnedDevice: true, ownedCryptoId: ownedCryptoId)
        case .settingAutoJoinGroups(category: let category):
            let autoAccept = getAutoAcceptGroupInviteFromObvSyncAtomAutoJoinGroupsCategory(category: category)
            ObvMessengerSettings.ContactsAndGroups.setAutoAcceptGroupInviteFrom(to: autoAccept, changeMadeFromAnotherOwnedDevice: true, ownedCryptoId: ownedCryptoId)
        }
        
    }
 
    
    private func getAutoAcceptGroupInviteFromObvSyncAtomAutoJoinGroupsCategory(category:  ObvSyncAtom.AutoJoinGroupsCategory) -> ObvMessengerSettings.ContactsAndGroups.AutoAcceptGroupInviteFrom {
        switch category {
        case .everyone:
            return .everyone
        case .contacts:
            return .oneToOneContactsOnly
        case .nobody:
            return .noOne
        }
    }

    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case contextIsNil
        case couldNotRespondToDialog(error: Error)
        case couldNotProcessSyncAtom(syncAtom: ObvSyncAtom)

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
            case .couldNotProcessSyncAtom(syncAtom: let syncAtom):
                return "Could not process syncAtom \(syncAtom.debugDescription)"
            }
        }

    }

}
