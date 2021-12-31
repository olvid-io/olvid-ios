/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

/// This operation is typically used when the user decides to update the text body of one of here sent messages. This operation assumes that the persisted message sent body has already been updated within the given context (typically, using a `EditTextBodyOfSentMessageOperation`).
final class SendUpdateMessageJSONOperation: ContextualOperationWithSpecificReasonForCancel<SendUpdateMessageJSONOperationReasonForCancel> {

    private let obvEngine: ObvEngine
    private let persistedSentMessageObjectID: NSManagedObjectID
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    init(persistedSentMessageObjectID: NSManagedObjectID, obvEngine: ObvEngine) {
        self.persistedSentMessageObjectID = persistedSentMessageObjectID
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main() {

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {
            
            let messageSent: PersistedMessageSent
            do {
                guard let _messageSent = try PersistedMessageSent.get(with: persistedSentMessageObjectID, within: obvContext.context) as? PersistedMessageSent else {
                    return cancel(withReason: .cannotFindMessageSent)
                }
                messageSent = _messageSent
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            let newTextBody: String?
            if let textBodyToSend = messageSent.textBodyToSend {
                newTextBody = textBodyToSend.isEmpty ? nil : textBodyToSend
            } else {
                newTextBody = nil
            }
            
            let itemJSON: PersistedItemJSON
            do {
                let updateMessageJSON = try UpdateMessageJSON(persistedMessageSentToEdit: messageSent,
                                                              newTextBody: newTextBody)
                itemJSON = PersistedItemJSON(updateMessageJSON: updateMessageJSON)
            } catch {
                return cancel(withReason: .couldNotConstructUpdateMessageJSON)
            }
            
            // Find all the contacts to which this item should be sent.
            
            let discussion = messageSent.discussion
            let contactCryptoIds: Set<ObvCryptoId>
            let ownCryptoId: ObvCryptoId
            do {
                (ownCryptoId, contactCryptoIds) = try discussion.getAllActiveParticipants()
            } catch {
                return cancel(withReason: .couldNotGetCryptoIdOfDiscussionParticipants(error: error))
            }

            // Create a payload of the PersistedItemJSON we just created and send it.
            // We do not keep track of the message identifiers from engine.
            
            let payload: Data
            do {
                payload = try itemJSON.encode()
            } catch {
                return cancel(withReason: .failedToEncodePersistedItemJSON)
            }
            
            let log = self.log
            let obvEngine = self.obvEngine
            do {
                try obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else { return }
                    do {
                        _ = try obvEngine.post(messagePayload: payload,
                                               extendedPayload: nil,
                                               withUserContent: false,
                                               isVoipMessageForStartingCall: false,
                                               attachmentsToSend: [],
                                               toContactIdentitiesWithCryptoId: contactCryptoIds,
                                               ofOwnedIdentityWithCryptoId: ownCryptoId)
                    } catch {
                        os_log("Could not post message within engine", type: .fault, log)
                        assertionFailure()
                    }
                }
            } catch {
                return cancel(withReason: .couldNotAddContextDidSaveCompletionHandler)
            }

        }
        
    }
    
}


enum SendUpdateMessageJSONOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case cannotFindMessageSent
    case couldNotConstructUpdateMessageJSON
    case couldNotGetCryptoIdOfDiscussionParticipants(error: Error)
    case failedToEncodePersistedItemJSON
    case couldNotAddContextDidSaveCompletionHandler
    case contextIsNil

    var logType: OSLogType {
        switch self {
        case .coreDataError,
             .couldNotConstructUpdateMessageJSON,
             .couldNotGetCryptoIdOfDiscussionParticipants,
             .couldNotAddContextDidSaveCompletionHandler,
             .failedToEncodePersistedItemJSON,
             .cannotFindMessageSent,
             .contextIsNil:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "Context is nil"
        case .cannotFindMessageSent:
            return "Cannot find message sent to edit"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotConstructUpdateMessageJSON:
            return "Could not construct UpdateMessageJSON"
        case .couldNotGetCryptoIdOfDiscussionParticipants(error: let error):
            return "Could not get the cryptoId of the discussion participants: \(error.localizedDescription)"
        case .failedToEncodePersistedItemJSON:
            return "We failed to encode the persisted item JSON"
        case .couldNotAddContextDidSaveCompletionHandler:
            return "We failed add a completion handler for sending the serialized DeleteMessagesJSON within the engine"
        }
    }

}
