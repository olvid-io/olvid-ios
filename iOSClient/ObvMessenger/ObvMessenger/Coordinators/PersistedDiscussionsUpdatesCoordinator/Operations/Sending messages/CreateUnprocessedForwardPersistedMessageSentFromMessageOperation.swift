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

final class CreateUnprocessedForwardPersistedMessageSentFromMessageOperation: ContextualOperationWithSpecificReasonForCancel<CreateUnprocessedForwardPersistedMessageSentFromMessageOperationOperationReasonForCancel>, UnprocessedPersistedMessageSentProvider {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: CreateUnprocessedForwardPersistedMessageSentFromMessageOperation.self))

    let messageObjectID: TypeSafeManagedObjectID<PersistedMessage>
    let discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>

    private(set) var persistedMessageSentObjectID: TypeSafeManagedObjectID<PersistedMessageSent>?

    init(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) {
        self.messageObjectID = messageObjectID
        self.discussionObjectID = discussionObjectID
        super.init()
    }

    override func main() {

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        obvContext.performAndWait {
            do {
                // Find discussion
                guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectID, within: obvContext.context) else {
                    assertionFailure()
                    return cancel(withReason: .couldNotFindDiscussionInDatabase)
                }

                // Find message to forward
                guard let messageToForward = try PersistedMessage.get(with: messageObjectID, within: obvContext.context) else {
                    assertionFailure()
                    return cancel(withReason: .couldNotFindMessageInDatabase)
                }

                // Create message to send
                let persistedMessageSent = try PersistedMessageSent(body: messageToForward.textBody, replyTo: nil, fyleJoins: messageToForward.fyleMessageJoinWithStatus ?? [], discussion: discussion, readOnce: false, visibilityDuration: nil, existenceDuration: nil, forwarded: true)

                do {
                    try obvContext.context.obtainPermanentIDs(for: [persistedMessageSent])
                } catch {
                    return cancel(withReason: .couldNotObtainPermanentIDForPersistedMessageSent)
                }

                self.persistedMessageSentObjectID = persistedMessageSent.typedObjectID

            } catch {
                assertionFailure()
                return cancel(withReason: .coreDataError(error: error))
            }

        }

    }

}

enum CreateUnprocessedForwardPersistedMessageSentFromMessageOperationOperationReasonForCancel: LocalizedErrorWithLogType {
    case contextIsNil
    case coreDataError(error: Error)
    case couldNotFindDiscussionInDatabase
    case couldNotFindMessageInDatabase
    case couldNotObtainPermanentIDForPersistedMessageSent

    var logType: OSLogType {
        switch self {
        case .contextIsNil:
            return .fault
        case .coreDataError:
            return .fault
        case .couldNotFindDiscussionInDatabase:
            return .error
        case .couldNotFindMessageInDatabase:
            return .error
        case .couldNotObtainPermanentIDForPersistedMessageSent:
            return .error
        }
    }

    var errorDescription: String? {
        switch self {
        case .contextIsNil: return "Context is nil"
        case .coreDataError(error: let error): return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindDiscussionInDatabase: return "Could not obtain persisted discussion in database"
        case .couldNotFindMessageInDatabase: return "Could not find message in database"
        case .couldNotObtainPermanentIDForPersistedMessageSent: return "Could not obtain persisted permanent ID for PersistedMessageSent"
        }
    }

}
