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
import CoreData
import OSLog
import ObvEngine
import OlvidUtils
import ObvTypes
import ObvAppCoreConstants
import ObvUICoreDataStructs


public protocol UnprocessedPersistedMessageSentProvider: Operation {
    var messageSentPermanentID: MessageSentPermanentID? { get }
}

public protocol ExtendedPayloadProvider: Operation {
    var extendedPayload: Data? { get }
}


public final class SendUnprocessedPersistedMessageSentOperation: ContextualOperationWithSpecificReasonForCancel<SendUnprocessedPersistedMessageSentOperationReasonForCancel>, @unchecked Sendable {

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "SendUnprocessedPersistedMessageSentOperation")
    
    private enum Input {
        case messagePermanentID(_: MessageSentPermanentID)
        case provider(_: UnprocessedPersistedMessageSentProvider)
    }
    
    private let input: Input

    private let alsoPostToOtherOwnedDevices: Bool
    private let extendedPayloadProvider: ExtendedPayloadProvider?
    private let obvEngine: ObvEngine
    private let callCompletionWhenMessageAndAttachmentsAreSent: Bool
    private let completionHandler: (() -> Void)?
    
    /// Set if we reach the end of this operation. This is essentially used by the share extension in order to donate an intent
    public private(set) var messentSent: PersistedMessageSentStructure?
    
    public private(set) var nonceOfReturnReceiptGeneratedOnCurrentDevice: Data?

    public init(messageSentPermanentID: MessageSentPermanentID, alsoPostToOtherOwnedDevices: Bool, extendedPayloadProvider: ExtendedPayloadProvider?, obvEngine: ObvEngine, callCompletionWhenMessageAndAttachmentsAreSent: Bool = false, completionHandler: (() -> Void)? = nil) {
        self.input = .messagePermanentID(messageSentPermanentID)
        self.obvEngine = obvEngine
        self.completionHandler = completionHandler
        self.extendedPayloadProvider = extendedPayloadProvider
        self.alsoPostToOtherOwnedDevices = alsoPostToOtherOwnedDevices
        self.callCompletionWhenMessageAndAttachmentsAreSent = callCompletionWhenMessageAndAttachmentsAreSent
        super.init()
    }

    public init(unprocessedPersistedMessageSentProvider: UnprocessedPersistedMessageSentProvider, alsoPostToOtherOwnedDevices: Bool, extendedPayloadProvider: ExtendedPayloadProvider?, obvEngine: ObvEngine, callCompletionWhenMessageAndAttachmentsAreSent: Bool = false, completionHandler: (() -> Void)? = nil) {
        self.input = .provider(unprocessedPersistedMessageSentProvider)
        self.obvEngine = obvEngine
        self.completionHandler = completionHandler
        self.extendedPayloadProvider = extendedPayloadProvider
        self.alsoPostToOtherOwnedDevices = alsoPostToOtherOwnedDevices
        self.callCompletionWhenMessageAndAttachmentsAreSent = callCompletionWhenMessageAndAttachmentsAreSent
        super.init()
    }

    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: SendUnprocessedPersistedMessageSentOperation.self))

    
    public override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        let messageSentPermanentID: MessageSentPermanentID
        
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
        
        do {
            
            guard let persistedMessageSent = try PersistedMessageSent.getManagedObject(withPermanentID: messageSentPermanentID, within: obvContext.context) else {
                return cancel(withReason: .couldNotFindPersistedMessageSentInDatabase)
            }
            
            let messageJSONToSend = try persistedMessageSent.toMessageJSONToSend()
                        
            // Construct the return receipts, payload, etc.
            
            let returnReceiptElements: ObvReturnReceiptElements = obvEngine.generateReturnReceiptElements()

            let messagePayload: Data
            do {
                let returnReceiptJSON = ReturnReceiptJSON(returnReceiptElements: returnReceiptElements)
                messagePayload = try PersistedItemJSON(messageJSON: messageJSONToSend.messageJSON, returnReceiptJSON: returnReceiptJSON).jsonEncode()
            } catch {
                return cancel(withReason: .encodingError(error: error))
            }

            // If there is an extendedPayloadProvider, get the extended payload
            
            let extendedPayload: Data?
            if let extendedPayloadProvider {
                assert(extendedPayloadProvider.isFinished)
                extendedPayload = extendedPayloadProvider.extendedPayload
            } else {
                extendedPayload = nil
            }
            
            // Post the message
            
            let messageIdentifierForContactToWhichTheMessageWasSent: [ObvCryptoId: Data]
            // We do not propagate a read once message to our other owned devices
            let finalAlsoPostToOtherOwnedDevices = alsoPostToOtherOwnedDevices && !messageJSONToSend.isReadOnce && messageJSONToSend.hasAnotherDeviceWhichIsReachable
            if !messageJSONToSend.contactCryptoIds.isEmpty || finalAlsoPostToOtherOwnedDevices {
                do {
                    messageIdentifierForContactToWhichTheMessageWasSent =
                    try obvEngine.post(messagePayload: messagePayload,
                                       extendedPayload: extendedPayload,
                                       withUserContent: true,
                                       isVoipMessageForStartingCall: false,
                                       attachmentsToSend: messageJSONToSend.attachmentsToSend,
                                       toContactIdentitiesWithCryptoId: messageJSONToSend.contactCryptoIds,
                                       ofOwnedIdentityWithCryptoId: messageJSONToSend.ownedCryptoId,
                                       alsoPostToOtherOwnedDevices: finalAlsoPostToOtherOwnedDevices,
                                       callCompletionWhenMessageAndAttachmentsAreSent: callCompletionWhenMessageAndAttachmentsAreSent,
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
            
            // Make the sent message available for a intent donation outside of this operation
            
            do {
                self.messentSent = try persistedMessageSent.toStructure()
            } catch {
                Self.logger.fault("Failed to create persisted structure: \(error.localizedDescription)")
                assertionFailure()
            }
            
            // We will save the nonce of the generated return receipt so, when receiving the return receipt back,
            // we can process it with high priority

            self.nonceOfReturnReceiptGeneratedOnCurrentDevice = returnReceiptElements.nonce
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}


public enum SendUnprocessedPersistedMessageSentOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case persistedMessageSentObjectIDIsNil
    case couldNotFindPersistedMessageSentInDatabase
    case couldNotPostMessageWithinEngine
    case encodingError(error: Error)
    case coreDataError(error: Error)
    
    public var logType: OSLogType {
        switch self {
        case .couldNotFindPersistedMessageSentInDatabase,
             .couldNotPostMessageWithinEngine:
            return .error
        case .encodingError,
             .coreDataError,
             .persistedMessageSentObjectIDIsNil:
            return .fault
        }
    }
    
    public var errorDescription: String? {
        switch self {
        case .persistedMessageSentObjectIDIsNil:
            return "persistedMessageSentObjectID is nil"
        case .couldNotFindPersistedMessageSentInDatabase:
            return "Could not find the PersistedMessageSent in database"
        case .couldNotPostMessageWithinEngine:
            return "Could not post message within the engine"
        case .encodingError(error: let error):
            return "Encoding error: \(error.localizedDescription)"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        }
    }
}
