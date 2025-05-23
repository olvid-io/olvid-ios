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
import os.log
import CoreData
import OlvidUtils
import ObvUICoreData
import ObvAppCoreConstants


final class CreateUnprocessedForwardPersistedMessageSentFromMessageOperation: ContextualOperationWithSpecificReasonForCancel<CreateUnprocessedForwardPersistedMessageSentFromMessageOperationOperationReasonForCancel>, @unchecked Sendable, UnprocessedPersistedMessageSentProvider {

    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: CreateUnprocessedForwardPersistedMessageSentFromMessageOperation.self))

    let messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>
    let discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>

    private(set) var messageSentPermanentID: MessageSentPermanentID?

    init(messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>, discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) {
        self.messagePermanentID = messagePermanentID
        self.discussionPermanentID = discussionPermanentID
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            // Find discussion
            guard let discussion = try PersistedDiscussion.getManagedObject(withPermanentID: discussionPermanentID, within: obvContext.context) else {
                assertionFailure()
                return cancel(withReason: .couldNotFindDiscussionInDatabase)
            }
            
            // Find message to forward
            guard let messageToForward = try PersistedMessage.getManagedObject(withPermanentID: messagePermanentID, within: obvContext.context) else {
                assertionFailure()
                return cancel(withReason: .couldNotFindMessageInDatabase)
            }
            
            // Make sure the message can be forwarded
            guard messageToForward.forwardActionCanBeMadeAvailable else {
                assertionFailure()
                return cancel(withReason: .cannotForwardMessage)
            }
            
            let forwarded: Bool
            switch messageToForward.kind {
            case .received:
                forwarded = true
            case .sent:
                // Do not mark the message as forwarded if the user forwards its own messages.
                forwarded = false
            case .none, .system:
                forwarded = false
                assertionFailure("It is not possible to forward a system message and none kind should be overridden in subclasses.")
            }
            
            // Create message to send
            
            let persistedMessageSent = try PersistedMessageSent.createPersistedMessageSentWhenForwardingAMessage(
                messageToForward: messageToForward,
                discussion: discussion,
                forwarded: forwarded)
            
            self.messageSentPermanentID = try? persistedMessageSent.objectPermanentID
            
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }

}

enum CreateUnprocessedForwardPersistedMessageSentFromMessageOperationOperationReasonForCancel: LocalizedErrorWithLogType {
    case contextIsNil
    case coreDataError(error: Error)
    case couldNotFindDiscussionInDatabase
    case couldNotFindMessageInDatabase
    case cannotForwardMessage

    var logType: OSLogType {
        switch self {
        case .contextIsNil, .cannotForwardMessage:
            return .fault
        case .coreDataError:
            return .fault
        case .couldNotFindDiscussionInDatabase:
            return .error
        case .couldNotFindMessageInDatabase:
            return .error
        }
    }

    var errorDescription: String? {
        switch self {
        case .contextIsNil: return "Context is nil"
        case .coreDataError(error: let error): return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindDiscussionInDatabase: return "Could not obtain persisted discussion in database"
        case .couldNotFindMessageInDatabase: return "Could not find message in database"
        case .cannotForwardMessage: return "Cannot forward message"
        }
    }

}
