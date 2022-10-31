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
import os.log


/// When a contact member from a group v2 turns from pending to non pending, or when a non pending member becomes a contact,
/// we are notified when certain sent messages (sent to other members before we could sent them to the new non pending contact member)
/// have infos that indicate that this message can be sent to this new non pending contact member.
/// This operation looks for *all* infos that can now be sent, extracts the corresponding sent messages, allowing the coordinator to
/// queue one (or more) operations allowing to send those messages to the appropriate new non pending group v2 members.
final class FindSentMessagesWithPersistedMessageSentRecipientInfosCanNowBeSentByEngineOperation: OperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, ObvErrorMaker {
    
    static let errorDomain = "FindSentMessagesWithPersistedMessageSentRecipientInfosCanNowBeSentByEngineOperation"

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "FindSentMessagesWithPersistedMessageSentRecipientInfosCanNowBeSentByEngineOperation")

    /// If this operation finishes without cancelling, this is guaranteed to be set.
    /// It will contain the object IDs of all the sent messages that can now be sent.
    private(set) var persistedMessageSentObjectIDs = Set<TypeSafeManagedObjectID<PersistedMessageSent>>()
    
    override func main() {
        
        ObvStack.shared.performBackgroundTaskAndWait { context in
            
            do {
            
                let unprocessedInfos = try PersistedMessageSentRecipientInfos.getAllUnprocessed(within: context)
                
                for info in unprocessedInfos {

                    do {
                        
                        guard info.messageIdentifierFromEngine == nil else {
                            throw Self.makeError(message: "Unexpected since the query should only return infos with no message identifier from engine")
                        }
                        
                        // Make sure the message is not wiped
                        
                        guard !info.messageSent.isWiped else {
                            assertionFailure("The infos should have been deleted when the message was wiped")
                            try? info.delete()
                            continue
                        }

                        // Determine the discussion kind
                        
                        let discussionKind: PersistedDiscussion.Kind
                        do {
                            discussionKind = try info.messageSent.discussion.kind
                        } catch {
                            throw Self.makeError(message: "Could not determine discussion kind, cannot send infos")
                        }
                        
                        // Determine the owned identity
                        
                        guard let ownedCryptoId = info.messageSent.discussion.ownedIdentity?.cryptoId else {
                            throw Self.makeError(message: "Could not determine owned identity")
                        }
                        
                        switch discussionKind {
                            
                        case .oneToOne:
                            
                            // In a oneToOne discussion, the infos can be sent if the recipient is a contact with at least one device.
                            // The contact must also be one2one
                            
                            // Determine the contact identity
                            
                            guard let contact = try PersistedObvContactIdentity.get(
                                contactCryptoId: info.recipientCryptoId,
                                ownedIdentityCryptoId: ownedCryptoId,
                                whereOneToOneStatusIs: .oneToOne,
                                within: context) else {
                                throw Self.makeError(message: "Could not find contact of a one2one discussion")
                            }

                            guard !contact.devices.isEmpty else {
                                // Continue anyway, this may happen
                                continue
                            }

                            // If we reach this point, we can send the message to the recipient indicated in the infos.
                            // We add the message to the set of messages to send.
                            
                            persistedMessageSentObjectIDs.insert(info.messageSent.typedObjectID)
                            
                        case .groupV1(withContactGroup: let group):
                            
                            // In a groupV1 discussion, the infos can be sent if the recipient
                            // - is a contact with at least one device
                            // - is a group member
                            // The contact is not required to be oneToOne
                            
                            guard let group = group else {
                                throw Self.makeError(message: "Could not find groupV1 associated with the discussion")
                            }

                            // Determine the contact identity
                            
                            guard let contact = try PersistedObvContactIdentity.get(
                                contactCryptoId: info.recipientCryptoId,
                                ownedIdentityCryptoId: ownedCryptoId,
                                whereOneToOneStatusIs: .any,
                                within: context) else {
                                throw Self.makeError(message: "Could not find contact of a one2one discussion")
                            }
                            
                            // Make sure the contact is part of the group
                            
                            guard group.contactIdentities.contains(contact) else {
                                throw Self.makeError(message: "Cannot send the message to a contact not part of the group V1")
                            }
                            
                            // Make sure we have a channel with the contact

                            guard !contact.devices.isEmpty else {
                                // Continue anyway, this may happen
                                continue
                            }

                            // If we reach this point, we can send the message to the recipient indicated in the infos.
                            // We add the message to the set of messages to send.
                            
                            persistedMessageSentObjectIDs.insert(info.messageSent.typedObjectID)

                        case .groupV2(withGroup: let group):
                            
                            // In a groupV2 discussion, the infos can be sent if the recipient
                            // - is a contact
                            // - with at least one device
                            // - a member of the group
                            // The contact is not required to be oneToOne
                            
                            guard let group = group else {
                                throw Self.makeError(message: "Could not find groupV1 associated with the discussion")
                            }

                            // Determine the contact identity
                            
                            guard let contact = try PersistedObvContactIdentity.get(
                                contactCryptoId: info.recipientCryptoId,
                                ownedIdentityCryptoId: ownedCryptoId,
                                whereOneToOneStatusIs: .any,
                                within: context) else {
                                // Continue anyway, this happens when the recipient is a pending member
                                continue
                            }

                            guard !contact.devices.isEmpty else {
                                // Continue anyway, this may happen
                                continue
                            }

                            // Make sure the contact is a non-pending member of the group
                            
                            guard let member = group.otherMembers.first(where: { $0.identity == info.recipientCryptoId.getIdentity() }) else {
                                throw Self.makeError(message: "Cannot send the message to a contact not part of the group V2")
                            }
                            
                            guard !member.isPending else {
                                continue
                            }
                                                        
                            // If we reach this point, we can send the message to the recipient indicated in the infos.
                            // We add the message to the set of messages to send.
                            
                            persistedMessageSentObjectIDs.insert(info.messageSent.typedObjectID)

                        }
                        
                    } catch {
                        os_log("Core data error: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                        // In production, continue anyway
                    }
                    
                }
                                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
        
    }
    
}
