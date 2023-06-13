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
import CoreData
import os.log
import ObvEngine
import OlvidUtils
import ObvTypes
import ObvUICoreData


protocol UnprocessedPersistedMessageSentProvider: Operation {
    var messageSentPermanentID: ObvManagedObjectPermanentID<PersistedMessageSent>? { get }
}

protocol ExtendedPayloadProvider: Operation {
    var extendedPayload: Data? { get }
}


final class SendUnprocessedPersistedMessageSentOperation: ContextualOperationWithSpecificReasonForCancel<SendUnprocessedPersistedMessageSentOperationReasonForCancel> {

    private enum Input {
        case messagePermanentID(_: ObvManagedObjectPermanentID<PersistedMessageSent>)
        case provider(_: UnprocessedPersistedMessageSentProvider)
    }
    
    private let input: Input

    private let extendedPayloadProvider: ExtendedPayloadProvider?
    private let obvEngine: ObvEngine
    private let completionHandler: (() -> Void)?

    init(messageSentPermanentID: ObvManagedObjectPermanentID<PersistedMessageSent>, extendedPayloadProvider: ExtendedPayloadProvider?, obvEngine: ObvEngine, completionHandler: (() -> Void)? = nil) {
        self.input = .messagePermanentID(messageSentPermanentID)
        self.obvEngine = obvEngine
        self.completionHandler = completionHandler
        self.extendedPayloadProvider = extendedPayloadProvider
        super.init()
    }

    init(unprocessedPersistedMessageSentProvider: UnprocessedPersistedMessageSentProvider, extendedPayloadProvider: ExtendedPayloadProvider?, obvEngine: ObvEngine, completionHandler: (() -> Void)? = nil) {
        self.input = .provider(unprocessedPersistedMessageSentProvider)
        self.obvEngine = obvEngine
        self.completionHandler = completionHandler
        self.extendedPayloadProvider = extendedPayloadProvider
        super.init()
    }

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: SendUnprocessedPersistedMessageSentOperation.self))

    override func main() {
        
        let messageSentPermanentID: ObvManagedObjectPermanentID<PersistedMessageSent>

        switch input {
        case .messagePermanentID(let _messageSentPermanentID):
            messageSentPermanentID = _messageSentPermanentID
        case .provider(let provider):
            assert(provider.isFinished)
            guard let _messageSentPermanentID = provider.messageSentPermanentID else {
                return cancel(withReason: .persistedMessageSentObjectIDIsNil)
            }
            messageSentPermanentID = _messageSentPermanentID
        }
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {

            do {
                
                guard let persistedMessageSent = try PersistedMessageSent.getManagedObject(withPermanentID: messageSentPermanentID, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindPersistedMessageSentInDatabase)
                }
                
                // Make sure the message is not wiped
                
                guard !persistedMessageSent.isWiped else {
                    assertionFailure()
                    return
                }

                // Determine the crypto ids of the potential recipients of the message, i.e., those to whom the message shall still be sent.
                // We will filter those identities later in this operation to only keep those to whom the message can indeed be sent.
                
                let cryptoIdsWithoutMessageIdentifierFromEngine = Set(persistedMessageSent.unsortedRecipientsInfos
                    .filter({ $0.messageIdentifierFromEngine == nil })
                    .map({ $0.recipientCryptoId }))

                guard let ownedCryptoId = persistedMessageSent.discussion.ownedIdentity?.cryptoId else {
                    return cancel(withReason: .couldNotDetermineOwnedCryptoId)
                }
                
                // Determine the discussion kind
                
                let discussionKind: PersistedDiscussion.Kind
                do {
                    discussionKind = try persistedMessageSent.discussion.kind
                } catch {
                    return cancel(withReason: .couldNotDetermineDiscussionKind)
                }
                                
                /* Create a set of all the cryptoId's to which the message needs to be sent by the engine,
                 * i.e., that has no identifier from the engine (for group v1 and one2one discussions), or that
                 * have no identifer from the engine and such that the recipient accepted
                 * the group invitation (for group v2)
                 */
                
                var contactCryptoIds = Set<ObvCryptoId>()
                
                switch discussionKind {
                    
                case .oneToOne:
                    
                    for contactCryptoId in cryptoIdsWithoutMessageIdentifierFromEngine {
                        
                        // We can send the message to the recipient if
                        // - she is a oneToOne contact
                        // - with at least one device
                        
                        // Determine the contact identity
                        
                        guard let contact = try PersistedObvContactIdentity.get(
                            contactCryptoId: contactCryptoId,
                            ownedIdentityCryptoId: ownedCryptoId,
                            whereOneToOneStatusIs: .oneToOne,
                            within: obvContext.context) else {
                            assertionFailure()
                            continue
                        }
                        
                        guard !contact.devices.isEmpty else {
                            // This may happen, when sending a message before a channel is created
                            continue
                        }
                        
                        // If we reach this point, we can send the message to the recipient indicated in the infos.
                        
                        contactCryptoIds.insert(contactCryptoId)
                        
                    }
                    
                case .groupV1(withContactGroup: let group):
                    
                    guard let group = group else {
                        return cancel(withReason: .couldNotFindCorrespondingGroupV1)
                    }

                    for contactCryptoId in cryptoIdsWithoutMessageIdentifierFromEngine {
                                                
                        // We can send the message to the recipient if
                        // - she is part of the group
                        // - with at least one device
                        
                        // Determine the contact identity
                        
                        guard let contact = try PersistedObvContactIdentity.get(
                            contactCryptoId: contactCryptoId,
                            ownedIdentityCryptoId: ownedCryptoId,
                            whereOneToOneStatusIs: .any,
                            within: obvContext.context) else {
                            assertionFailure()
                            continue
                        }
                        
                        guard !contact.devices.isEmpty else {
                            // This may happen, when sending a message before a channel is created
                            continue
                        }
                        
                        guard group.contactIdentities.contains(contact) else {
                            assertionFailure()
                            continue
                        }
                        
                        // If we reach this point, we can send the message to the recipient indicated in the infos.
                        
                        contactCryptoIds.insert(contactCryptoId)
                        
                    }
                    
                case .groupV2(withGroup: let group):
                    
                    guard let group = group else {
                        return cancel(withReason: .couldNotFindCorrespondingGroupV2)
                    }
                    
                    for contactCryptoId in cryptoIdsWithoutMessageIdentifierFromEngine {
                        
                        // We can send the message to the recipient if
                        // - she is part of the group
                        // - she is not pending
                        // - with at least one device
                        
                        // Determine the contact identity
                        
                        guard let contact = try PersistedObvContactIdentity.get(
                            contactCryptoId: contactCryptoId,
                            ownedIdentityCryptoId: ownedCryptoId,
                            whereOneToOneStatusIs: .any,
                            within: obvContext.context) else {
                            // Can happen when a recipient is a pending member who is not a contact yet
                            continue
                        }
                        
                        guard !contact.devices.isEmpty else {
                            // This may happen, when sending a message before a channel is created
                            continue
                        }
                        
                        // Make sure the contact is a non-pending member of the group
                        
                        guard let member = group.otherMembers.first(where: { $0.identity == contactCryptoId.getIdentity() }) else {
                            assertionFailure()
                            continue
                        }
                        
                        guard !member.isPending else {
                            continue
                        }
                        
                        // If we reach this point, we can send the message to the recipient indicated in the infos.
                        
                        contactCryptoIds.insert(contactCryptoId)
                        
                    }
                    
                }
                
                // Construct the return receipts, payload, etc.
                
                let returnReceiptElements: (nonce: Data, key: Data)
                let messagePayload: Data
                let attachmentsToSend: [ObvAttachmentToSend]
                do {
                    
                    do {
                        guard let messageJSON = persistedMessageSent.toJSON() else {
                            return cancel(withReason: .couldNotTurnPersistedMessageSentIntoAMessageJSON)
                        }
                        returnReceiptElements = obvEngine.generateReturnReceiptElements()
                        let returnReceiptJSON = ReturnReceiptJSON(returnReceiptElements: returnReceiptElements)
                        messagePayload = try PersistedItemJSON(messageJSON: messageJSON, returnReceiptJSON: returnReceiptJSON).jsonEncode()
                    } catch {
                        return cancel(withReason: .encodingError(error: error))
                    }
                    
                    // For each the of fyles of the SendMessageToProcess, we create a ObvAttachmentToSend
                    
                    do {
                        attachmentsToSend = try persistedMessageSent.fyleMessageJoinWithStatuses.compactMap {
                            guard let metadata = try $0.getFyleMetadata()?.jsonEncode() else { return nil }
                            guard let fyle = $0.fyle else { return nil }
                            guard let totalUnitCount = fyle.getFileSize() else { return nil }
                            return ObvAttachmentToSend(fileURL: fyle.url,
                                                       deleteAfterSend: false,
                                                       totalUnitCount: Int(totalUnitCount),
                                                       metadata: metadata)
                        }
                    } catch {
                        return cancel(withReason: .couldNotCreateAnObvAttachmentToSendFromASentFyleMessageJoinWithStatus)
                    }
                    
                }
                

                let extendedPayload: Data?
                if let extendedPayloadProvider = extendedPayloadProvider {
                    assert(extendedPayloadProvider.isFinished)
                    extendedPayload = extendedPayloadProvider.extendedPayload
                } else {
                    extendedPayload = nil
                }
                
                // Post the message
                
                let messageIdentifierForContactToWhichTheMessageWasSent: [ObvCryptoId: Data]
                if !contactCryptoIds.isEmpty {
                    do {
                        messageIdentifierForContactToWhichTheMessageWasSent =
                        try obvEngine.post(messagePayload: messagePayload,
                                           extendedPayload: extendedPayload,
                                           withUserContent: true,
                                           isVoipMessageForStartingCall: false,
                                           attachmentsToSend: attachmentsToSend,
                                           toContactIdentitiesWithCryptoId: contactCryptoIds,
                                           ofOwnedIdentityWithCryptoId: ownedCryptoId,
                                           completionHandler: completionHandler)
                    } catch {
                        return cancel(withReason: .couldNotPostMessageWithinEngine)
                    }
                } else {
                    messageIdentifierForContactToWhichTheMessageWasSent = [:]
                    completionHandler?()
                }
                
                // The engine returned a array containing all the contacts to which it could send the message.
                // We use this array generated  by the engine in order to update the appropriate PersistedMessageSentRecipientInfos.
                
                for recipientInfos in persistedMessageSent.unsortedRecipientsInfos {
                    if let messageIdentifierFromEngine = messageIdentifierForContactToWhichTheMessageWasSent[recipientInfos.recipientCryptoId] {
                        os_log("🆗 Setting messageIdentifierFromEngine %{public}@ within recipientInfos", log: log, type: .info, messageIdentifierFromEngine.hexString())
                        recipientInfos.setMessageIdentifierFromEngine(to: messageIdentifierFromEngine, andReturnReceiptElementsTo: returnReceiptElements)
                    }
                }

                // Make a donation as soon as the message is saved

                if #available(iOS 14.0, *) {
                    do {
                        let persistedMessageSentStruct = try persistedMessageSent.toStruct()
                        let infos = SentMessageIntentInfos(messageSent: persistedMessageSentStruct,
                                                           urlForStoringPNGThumbnail: nil,
                                                           thumbnailPhotoSide: IntentManagerUtils.thumbnailPhotoSide)
                        let intent = IntentManagerUtils.getSendMessageIntentForMessageSent(infos: infos)
                        try obvContext.addContextDidSaveCompletionHandler { error in
                            if let error { assertionFailure(error.localizedDescription); return }
                            Task {
                                await IntentManagerUtils.makeDonation(discussionKind: persistedMessageSentStruct.discussionKind,
                                                                      intent: intent,
                                                                      direction: .outgoing)
                            }
                        }
                    } catch {
                        // In production, this operation should not fail because we could not make a donation
                        assertionFailure(error.localizedDescription)
                    }
                }
                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

        } // end of obvContext.performAndWait
        
    }
    
}


enum SendUnprocessedPersistedMessageSentOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case contextIsNil
    case persistedMessageSentObjectIDIsNil
    case couldNotFindPersistedMessageSentInDatabase
    case couldNotTurnPersistedMessageSentIntoAMessageJSON
    case couldNotCreateAnObvAttachmentToSendFromASentFyleMessageJoinWithStatus
    case couldNotPostMessageWithinEngine
    case couldNotDetermineOwnedCryptoId
    case couldNotFindCorrespondingGroupV1
    case couldNotFindCorrespondingGroupV2
    case couldNotDetermineDiscussionKind
    case couldNotFindContact
    case encodingError(error: Error)
    case coreDataError(error: Error)
    
    var logType: OSLogType {
        switch self {
        case .couldNotFindPersistedMessageSentInDatabase,
             .couldNotPostMessageWithinEngine:
            return .error
        case .couldNotTurnPersistedMessageSentIntoAMessageJSON,
             .couldNotCreateAnObvAttachmentToSendFromASentFyleMessageJoinWithStatus,
             .couldNotDetermineOwnedCryptoId,
             .encodingError,
             .coreDataError,
             .couldNotFindContact,
             .contextIsNil,
             .couldNotDetermineDiscussionKind,
             .couldNotFindCorrespondingGroupV1,
             .couldNotFindCorrespondingGroupV2,
             .persistedMessageSentObjectIDIsNil:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .persistedMessageSentObjectIDIsNil:
            return "persistedMessageSentObjectID is nil"
        case .contextIsNil:
            return "Context is nil"
        case .couldNotFindPersistedMessageSentInDatabase:
            return "Could not find the PersistedMessageSent in database"
        case .couldNotTurnPersistedMessageSentIntoAMessageJSON:
            return "Could not turn the PersistedMessageSent into a MessageJSON"
        case .couldNotCreateAnObvAttachmentToSendFromASentFyleMessageJoinWithStatus:
            return "Could not create an ObvAttachmentToSend from a SentFyleMessageJoinWithStatus"
        case .couldNotPostMessageWithinEngine:
            return "Could not post message within the engine"
        case .couldNotFindCorrespondingGroupV1:
            return "Could not find corresponding group v1"
        case .couldNotFindCorrespondingGroupV2:
            return "Could not find corresponding group v2"
        case .couldNotDetermineOwnedCryptoId:
            return "Could not determine the owned crypto identity"
        case .couldNotDetermineDiscussionKind:
            return "Could not determine discussion kind"
        case .couldNotFindContact:
            return "Could not find contact"
        case .encodingError(error: let error):
            return "Encoding error: \(error.localizedDescription)"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        }
    }
}
