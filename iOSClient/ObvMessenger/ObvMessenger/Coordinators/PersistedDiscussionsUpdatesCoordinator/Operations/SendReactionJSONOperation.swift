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

final class SendReactionJSONOperation: ContextualOperationWithSpecificReasonForCancel<SendReactionJSONOperationReasonForCancel> {

    private let obvEngine: ObvEngine
    private let messageObjectID: TypeSafeManagedObjectID<PersistedMessage>
    private let emoji: String?

    init(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, obvEngine: ObvEngine, emoji: String?) {
        self.messageObjectID = messageObjectID
        self.obvEngine = obvEngine
        self.emoji = emoji
        super.init()
    }

    override func main() {
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {

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
                let reactionJSON = try ReactionJSON(persistedMessageToReact: message, emoji: emoji)
                itemJSON = PersistedItemJSON(reactionJSON: reactionJSON)
            } catch {
                return cancel(withReason: .couldNotConstructReactionJSON)
            }

            // Find all the contacts to which this item should be sent.

            let discussion = message.discussion
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

            do {
                _ = try obvEngine.post(messagePayload: payload,
                                       extendedPayload: nil,
                                       withUserContent: true,
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

enum SendReactionJSONOperationReasonForCancel: LocalizedErrorWithLogType {

    case coreDataError(error: Error)
    case contextIsNil
    case cannotFindMessage
    case couldNotConstructReactionJSON
    case couldNotGetCryptoIdOfDiscussionParticipants(error: Error)
    case failedToEncodePersistedItemJSON
    case couldNotPostMessageWithinEngine

    var logType: OSLogType { .fault }

    var errorDescription: String? {
        switch self {
        case .cannotFindMessage:
            return "Cannot find message to react"
        case .contextIsNil:
            return "The context is not set"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotConstructReactionJSON:
            return "Could not construct ReactionJSON"
        case .couldNotGetCryptoIdOfDiscussionParticipants(error: let error):
            return "Could not get the cryptoId of the discussion participants: \(error.localizedDescription)"
        case .failedToEncodePersistedItemJSON:
            return "We failed to encode the persisted item JSON"
        case .couldNotPostMessageWithinEngine:
            return "We failed to post the serialized DeleteMessagesJSON within the engine"
        }
    }

}
