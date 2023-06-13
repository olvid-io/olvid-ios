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
import ObvTypes
import OlvidUtils
import ObvEngine
import ObvUICoreData


final class SendGlobalDeleteMessagesJSONOperation: OperationWithSpecificReasonForCancel<SendGlobalDeleteMessagesJSONOperationReasonForCancel> {

    private let persistedMessageObjectIDs: [NSManagedObjectID]
    private let obvEngine: ObvEngine
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: SendGlobalDeleteMessagesJSONOperation.self))

    init(persistedMessageObjectIDs: [NSManagedObjectID], obvEngine: ObvEngine) {
        self.persistedMessageObjectIDs = persistedMessageObjectIDs
        self.obvEngine = obvEngine
        super.init()
    }

    override func main() {

        guard !persistedMessageObjectIDs.isEmpty else { assertionFailure(); return }
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            
            // We create the PersistedItemJSON instance to send

            let messages: [PersistedMessage]
            do {
                messages = try PersistedMessage.getAll(with: persistedMessageObjectIDs, within: context)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            let discussion: PersistedDiscussion
            do {
                let discussions = Set(messages.map { $0.discussion })
                guard discussions.count == 1 else {
                    return cancel(withReason: .unexpectedNumberOfDiscussions(discussionCount: discussions.count))
                }
                discussion = discussions.first!
            }
            

            let deleteMessagesJSON: DeleteMessagesJSON
            do {
                deleteMessagesJSON = try DeleteMessagesJSON(persistedMessagesToDelete: messages)
            } catch {
                return cancel(withReason: .couldNotConstructDeleteMessagesJSON(error: error))
            }
            let itemJSON = PersistedItemJSON(deleteMessagesJSON: deleteMessagesJSON)

            // Find all the contacts to which this item should be sent.
            
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
                payload = try itemJSON.jsonEncode()
            } catch {
                return cancel(withReason: .failedToEncodePersistedItemJSON)
            }
            
            do {
                _ = try obvEngine.post(messagePayload: payload,
                                       extendedPayload: nil,
                                       withUserContent: false,
                                       isVoipMessageForStartingCall: false,
                                       attachmentsToSend: [],
                                       toContactIdentitiesWithCryptoId: contactCryptoIds,
                                       ofOwnedIdentityWithCryptoId: ownCryptoId)
            } catch {
                return cancel(withReason: .couldNotPostMessageWithinEngine)
            }

        }
        
    }
    
}


enum SendGlobalDeleteMessagesJSONOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case couldNotConstructDeleteMessagesJSON(error: Error)
    case unexpectedNumberOfDiscussions(discussionCount: Int)
    case failedToEncodePersistedItemJSON
    case couldNotPostMessageWithinEngine
    case couldNotGetCryptoIdOfDiscussionParticipants(error: Error)

    var logType: OSLogType {
        switch self {
        case .coreDataError,
             .couldNotConstructDeleteMessagesJSON,
             .failedToEncodePersistedItemJSON,
             .couldNotPostMessageWithinEngine,
             .couldNotGetCryptoIdOfDiscussionParticipants,
             .unexpectedNumberOfDiscussions:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotConstructDeleteMessagesJSON(error: let error):
            return "Could not construct DeleteMessagesJSON: \(error.localizedDescription)"
        case .unexpectedNumberOfDiscussions(discussionCount: let count):
            return "Unexpected discussion count. Expecting 1, got \(count)"
        case .failedToEncodePersistedItemJSON:
            return "We failed to encode the persisted item JSON"
        case .couldNotPostMessageWithinEngine:
            return "We failed to post the serialized DeleteMessagesJSON within the engine"
        case .couldNotGetCryptoIdOfDiscussionParticipants(error: let error):
            return "Could not get the cryptoId of the discussion participants: \(error.localizedDescription)"
        }
    }

}
