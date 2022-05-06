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


protocol UnprocessedPersistedMessageSentProvider: Operation {
    var persistedMessageSentObjectID: TypeSafeManagedObjectID<PersistedMessageSent>? { get }
}

protocol ExtendedPayloadProvider: Operation {
    var extendedPayload: Data? { get }
}


final class SendUnprocessedPersistedMessageSentOperation: ContextualOperationWithSpecificReasonForCancel<SendUnprocessedPersistedMessageSentOperationReasonForCancel> {

    private enum Input {
        case messageObjectID(_: TypeSafeManagedObjectID<PersistedMessageSent>)
        case provider(_: UnprocessedPersistedMessageSentProvider)
    }
    
    private let input: Input

    private let extendedPayloadProvider: ExtendedPayloadProvider?
    private let obvEngine: ObvEngine
    private let completionHandler: (() -> Void)?

    init(persistedMessageSentObjectID: TypeSafeManagedObjectID<PersistedMessageSent>, extendedPayloadProvider: ExtendedPayloadProvider?, obvEngine: ObvEngine, completionHandler: (() -> Void)? = nil) {
        self.input = .messageObjectID(persistedMessageSentObjectID)
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
        
        let persistedMessageSentObjectID: TypeSafeManagedObjectID<PersistedMessageSent>

        switch input {
        case .messageObjectID(let _persistedMessageSentObjectID):
            persistedMessageSentObjectID = _persistedMessageSentObjectID
        case .provider(let provider):
            assert(provider.isFinished)
            guard let _persistedMessageSentObjectID = provider.persistedMessageSentObjectID else {
                return cancel(withReason: .persistedMessageSentObjectIDIsNil)
            }
            persistedMessageSentObjectID = _persistedMessageSentObjectID
        }
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {

            let persistedMessageSent: PersistedMessageSent
            do {
                guard let _persistedMessageSent = try PersistedMessageSent.getPersistedMessageSent(objectID: persistedMessageSentObjectID, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindPersistedMessageSentInDatabase)
                }
                persistedMessageSent = _persistedMessageSent
            } catch(let error) {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            guard persistedMessageSent.status == .unprocessed || persistedMessageSent.status == .processing else {
                return
            }
            
            guard let ownedCryptoId = persistedMessageSent.discussion.ownedIdentity?.cryptoId else {
                return cancel(withReason: .couldNotDetermineOwnedCryptoId)
            }

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
                    messagePayload = try PersistedItemJSON(messageJSON: messageJSON, returnReceiptJSON: returnReceiptJSON).encode()
                } catch {
                    return cancel(withReason: .encodingError(error: error))
                }
                
                // For each the of fyles of the SendMessageToProcess, we create a ObvAttachmentToSend
                
                do {
                    attachmentsToSend = try persistedMessageSent.fyleMessageJoinWithStatuses.compactMap {
                        guard let metadata = try $0.getFyleMetadata()?.encode() else { return nil }
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

            /* Create a set of all the cryptoId's to which the message needs to be sent by the engine,
             * i.e., that has no identifier from the engine.
             */

            let contactCryptoIds = Set(persistedMessageSent.unsortedRecipientsInfos.filter({ $0.messageIdentifierFromEngine == nil }).map({ $0.recipientCryptoId }))

            let extendedPayload: Data?
            if let extendedPayloadProvider = extendedPayloadProvider {
                assert(extendedPayloadProvider.isFinished)
                extendedPayload = extendedPayloadProvider.extendedPayload
            } else {
                extendedPayload = nil
            }

            // Post the message
                        
            let messageIdentifierForContactToWhichTheMessageWasSent: [ObvCryptoId: Data]
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
            
            // The engine returned a array containing all the contacts to which it could send the message.
            // We use this array generated  by the engine in order to update the appropriate PersistedMessageSentRecipientInfos.

            for recipientInfos in persistedMessageSent.unsortedRecipientsInfos {
                if let messageIdentifierFromEngine = messageIdentifierForContactToWhichTheMessageWasSent[recipientInfos.recipientCryptoId] {
                    os_log("🆗 Setting messageIdentifierFromEngine %{public}@ within recipientInfos", log: log, type: .info, messageIdentifierFromEngine.hexString())
                    recipientInfos.setMessageIdentifierFromEngine(to: messageIdentifierFromEngine, andReturnReceiptElementsTo: returnReceiptElements)
                }
            }

        }
        
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
             .contextIsNil,
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
        case .couldNotDetermineOwnedCryptoId:
            return "Could not determine the owned crypto identity"
        case .encodingError(error: let error):
            return "Encoding error: \(error.localizedDescription)"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        }
    }
}
