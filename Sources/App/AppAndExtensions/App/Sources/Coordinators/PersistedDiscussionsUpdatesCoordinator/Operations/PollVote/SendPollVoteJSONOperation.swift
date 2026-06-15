/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvUICoreData
import ObvAppTypes


final class SendPollVoteJSONOperation: ContextualOperationWithSpecificReasonForCancel<SendPollVoteJSONOperationReasonForCancel>, @unchecked Sendable {

    private let obvEngine: ObvEngine
    private let messageObjectID: TypeSafeManagedObjectID<PersistedMessage>
    private let pollVoteCandidateUuid: UUID
    private let voted: Bool
    private let version: Int
    private let originalServerTimestamp: Date? // Set when re-sending a poll vote to a group v2 member that switch from the pending to the non-pending state

    init(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, obvEngine: ObvEngine, pollVoteCandidateUuid: UUID, voted: Bool, version: Int, originalServerTimestamp: Date?) {
        self.messageObjectID = messageObjectID
        self.obvEngine = obvEngine
        self.pollVoteCandidateUuid = pollVoteCandidateUuid
        self.voted = voted
        self.version = version
        self.originalServerTimestamp = originalServerTimestamp
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        let message: PersistedMessage
        do {
            guard let _message = try PersistedMessage.get(with: messageObjectID, within: obvContext.context) else {
                return cancel(withReason: .cannotFindMessage)
            }
            message = _message
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
        let itemJSON: PersistedItemJSON
        do {
            let pollVoteJSON = try PollVoteJSON(persistedMessageToReact: message, pollCandidateUuid: pollVoteCandidateUuid, voted: voted, version: version, originalServerTimestamp: originalServerTimestamp)
            itemJSON = PersistedItemJSON(pollVoteJSON: pollVoteJSON)
        } catch {
            return cancel(withReason: .couldNotConstructPollVoteJSON)
        }
        
        // Find all the contacts to which this item should be sent.
        
        guard let discussion = message.discussion else {
            return cancel(withReason: .couldNotDetermineDiscussion)
        }
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
                                   withUserContent: true,
                                   isVoipMessageForStartingCall: false,
                                   attachmentsToSend: [],
                                   toContactIdentitiesWithCryptoId: contactCryptoIds,
                                   ofOwnedIdentityWithCryptoId: ownCryptoId,
                                   alsoPostToOtherOwnedDevices: true)
        } catch {
            return cancel(withReason: .couldNotPostMessageWithinEngine)
        }
        
    }
}

enum SendPollVoteJSONOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case contextIsNil
    case cannotFindMessage
    case couldNotConstructPollVoteJSON
    case couldNotGetCryptoIdOfDiscussionParticipants(error: Error)
    case failedToEncodePersistedItemJSON
    case couldNotPostMessageWithinEngine
    case couldNotDetermineDiscussion
    
    var logType: OSLogType { .fault }
    
    var errorDescription: String? {
        switch self {
        case .cannotFindMessage:
            return "Cannot find message to react"
        case .contextIsNil:
            return "The context is not set"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotConstructPollVoteJSON:
            return "Could not construct PollVoteJSON"
        case .couldNotGetCryptoIdOfDiscussionParticipants(error: let error):
            return "Could not get the cryptoId of the discussion participants: \(error.localizedDescription)"
        case .failedToEncodePersistedItemJSON:
            return "We failed to encode the persisted item JSON"
        case .couldNotPostMessageWithinEngine:
            return "We failed to post the serialized DeleteMessagesJSON within the engine"
        case .couldNotDetermineDiscussion:
            return "Could not determine discussion"
        }
    }
}
