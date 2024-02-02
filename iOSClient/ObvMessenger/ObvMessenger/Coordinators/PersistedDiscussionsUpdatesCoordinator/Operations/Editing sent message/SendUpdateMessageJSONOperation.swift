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
import CoreData
import os.log
import ObvEngine
import OlvidUtils
import ObvTypes
import ObvUICoreData


/// This operation is typically used when the user decides to update the text body of one of here sent messages. This operation assumes that the persisted message sent body has already been updated within the given context (typically, using a `EditTextBodyOfSentMessageOperation`).
final class SendUpdateMessageJSONOperation: ContextualOperationWithSpecificReasonForCancel<SendUpdateMessageJSONOperationReasonForCancel> {

    private let obvEngine: ObvEngine
    private let sentMessageObjectID: TypeSafeManagedObjectID<PersistedMessageSent>
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: SendUpdateMessageJSONOperation.self))

    init(sentMessageObjectID: TypeSafeManagedObjectID<PersistedMessageSent>, obvEngine: ObvEngine) {
        self.sentMessageObjectID = sentMessageObjectID
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        let messageSent: PersistedMessageSent
        do {
            guard let _messageSent = try PersistedMessageSent.getPersistedMessageSent(objectID: sentMessageObjectID, within: obvContext.context) else {
                return cancel(withReason: .cannotFindMessageSent)
            }
            messageSent = _messageSent
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
        let newTextBody: String?
        let userMentions: [MessageJSON.UserMention]
        if let textBodyToSend = messageSent.textBodyToSend {
            newTextBody = textBodyToSend.isEmpty ? nil : textBodyToSend
            userMentions = messageSent
                .mentions
                .compactMap({ try? $0.userMention })
        } else {
            newTextBody = nil
            userMentions = []
        }
        
        let itemJSON: PersistedItemJSON
        do {
            let updateMessageJSON = try UpdateMessageJSON(persistedMessageSentToEdit: messageSent,
                                                          newTextBody: newTextBody,
                                                          userMentions: userMentions)
            itemJSON = PersistedItemJSON(updateMessageJSON: updateMessageJSON)
        } catch {
            return cancel(withReason: .couldNotConstructUpdateMessageJSON)
        }
        
        // Find all the contacts to which this item should be sent.
        
        guard let discussion = messageSent.discussion else {
            return cancel(withReason: .couldNotDetermineDiscussion)
        }
        let contactCryptoIds: Set<ObvCryptoId>
        let ownCryptoId: ObvCryptoId
        do {
            (ownCryptoId, contactCryptoIds) = try discussion.getAllActiveParticipants()
        } catch {
            return cancel(withReason: .couldNotGetCryptoIdOfDiscussionParticipants(error: error))
        }
        
        // Determine if the owned identity has other owned devices
        
        let ownedIdentityHasOtherOwnedDevices: Bool
        do {
            guard let ownedIdentity = discussion.ownedIdentity else {
                return cancel(withReason: .cannotFindOwnedIdentity)
            }
            ownedIdentityHasOtherOwnedDevices = (ownedIdentity.devices.count > 1)
        }
        
        // Create a payload of the PersistedItemJSON we just created and send it.
        // We do not keep track of the message identifiers from engine.
        
        let payload: Data
        do {
            payload = try itemJSON.jsonEncode()
        } catch {
            return cancel(withReason: .failedToEncodePersistedItemJSON)
        }
        
        if !contactCryptoIds.isEmpty || ownedIdentityHasOtherOwnedDevices {
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
                                               ofOwnedIdentityWithCryptoId: ownCryptoId,
                                               alsoPostToOtherOwnedDevices: true)
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
    case couldNotDetermineDiscussion
    case cannotFindOwnedIdentity

    var logType: OSLogType {
        switch self {
        case .coreDataError,
             .couldNotConstructUpdateMessageJSON,
             .couldNotGetCryptoIdOfDiscussionParticipants,
             .couldNotAddContextDidSaveCompletionHandler,
             .failedToEncodePersistedItemJSON,
             .cannotFindMessageSent,
             .cannotFindOwnedIdentity,
             .couldNotDetermineDiscussion,
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
        case .couldNotDetermineDiscussion:
            return "Could not determine discussion"
        case .cannotFindOwnedIdentity:
            return "Cannot find owned identity"
        }
    }

}
