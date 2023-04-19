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
import os.log
import CoreData
import OlvidUtils
import ObvCrypto

final class CreateUnprocessedReplyToPersistedMessageSentFromBodyOperation: ContextualOperationWithSpecificReasonForCancel<CreateUnprocessedReplyToPersistedMessageSentFromBodyOperationReasonForCancel>, UnprocessedPersistedMessageSentProvider {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: CreateUnprocessedReplyToPersistedMessageSentFromBodyOperation.self))

    let textBody: String
    let contactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>
    let messageIdentifierFromEngine: Data

    private(set) var messageSentPermanentID: ObvManagedObjectPermanentID<PersistedMessageSent>?

    init(contactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>, messageIdentifierFromEngine: Data, textBody: String) {
        self.textBody = textBody
        self.contactPermanentID = contactPermanentID
        self.messageIdentifierFromEngine = messageIdentifierFromEngine
        super.init()
    }

    override func main() {

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {
            do {
                guard let contactIdentity = try PersistedObvContactIdentity.getManagedObject(withPermanentID: contactPermanentID, within: obvContext.context) else {
                    assertionFailure()
                    return cancel(withReason: .couldNotFindContactIdentityInDatabase)
                }

                // Find message to reply to
                guard let messageToReply = try PersistedMessageReceived.get(messageIdentifierFromEngine: messageIdentifierFromEngine, from: contactIdentity) else {
                    assertionFailure()
                    return cancel(withReason: .couldNotFindReceivedMessageInDatabase)
                }

                let discussion = messageToReply.discussion
                let lastMessage = try PersistedMessage.getLastMessage(in: discussion)

                // Do not set replyTo if the message to reply to is the last message of the discussion.
                let effectiveReplyTo = lastMessage == messageToReply ? nil : messageToReply

                // Create message to send
                let persistedMessageSent = try PersistedMessageSent(body: textBody, replyTo: effectiveReplyTo, fyleJoins: [], discussion: discussion, readOnce: false, visibilityDuration: nil, existenceDuration: nil, forwarded: false)

                do {
                    try obvContext.context.obtainPermanentIDs(for: [persistedMessageSent])
                } catch {
                    return cancel(withReason: .couldNotObtainPermanentIDForPersistedMessageSent)
                }

                self.messageSentPermanentID = persistedMessageSent.objectPermanentID

            } catch {
                assertionFailure()
                return cancel(withReason: .coreDataError(error: error))
            }
        }
    }

}

enum CreateUnprocessedReplyToPersistedMessageSentFromBodyOperationReasonForCancel: LocalizedErrorWithLogType {

    case contextIsNil
    case coreDataError(error: Error)
    case couldNotFindPendingReplyToMessageToSendInDatabase
    case couldNotObtainPermanentIDForPersistedMessageSent
    case couldNotFindContactIdentityInDatabase
    case couldNotFindReceivedMessageInDatabase

    var logType: OSLogType {
        switch self {
        case .contextIsNil:
            return .fault
        case .coreDataError:
            return .fault
        case .couldNotFindReceivedMessageInDatabase:
            return .error
        case .couldNotFindPendingReplyToMessageToSendInDatabase:
            return .error
        case .couldNotObtainPermanentIDForPersistedMessageSent:
            return .error
        case .couldNotFindContactIdentityInDatabase:
            return .error
        }
    }

    var errorDescription: String? {
        switch self {
        case .contextIsNil: return "Context is nil"
        case .couldNotFindContactIdentityInDatabase: return "Could not obtain persisted contact identity in database"
        case .couldNotFindPendingReplyToMessageToSendInDatabase: return "Could not find pending replyTo message to send in database"
        case .coreDataError(error: let error): return "Core Data error: \(error.localizedDescription)"
        case .couldNotObtainPermanentIDForPersistedMessageSent: return "Could not obtain persisted permanent ID for PersistedMessageSent"
        case .couldNotFindReceivedMessageInDatabase: return "Could not find received message in database"
        }
    }

}
