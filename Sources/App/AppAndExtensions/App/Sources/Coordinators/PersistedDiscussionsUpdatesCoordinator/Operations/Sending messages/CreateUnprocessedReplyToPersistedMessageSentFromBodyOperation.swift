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
import OSLog
import CoreData
import OlvidUtils
import ObvCrypto
import ObvUICoreData
import ObvAppCoreConstants
import ObvAppTypes


/// Called when the user replies to a received message from the user notification shown in the notification center.
final class CreateUnprocessedReplyToPersistedMessageSentFromBodyOperation: ContextualOperationWithSpecificReasonForCancel<CreateUnprocessedReplyToPersistedMessageSentFromBodyOperationReasonForCancel>, @unchecked Sendable, UnprocessedPersistedMessageSentProvider {

    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: CreateUnprocessedReplyToPersistedMessageSentFromBodyOperation.self))

    let replyBody: String
    let messageRepliedTo: ObvMessageAppIdentifier

    private(set) var messageSentPermanentID: MessageSentPermanentID?

    init(replyBody: String, messageRepliedTo: ObvMessageAppIdentifier) {
        self.replyBody = replyBody
        self.messageRepliedTo = messageRepliedTo
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            // Find message to reply to
            guard let messageToReply = try PersistedMessageReceived.getMessage(messageAppIdentifier: messageRepliedTo, within: obvContext.context) as? PersistedMessageReceived else {
                assertionFailure()
                return cancel(withReason: .couldNotFindReceivedMessageInDatabase)
            }
            
            guard let discussion = messageToReply.discussion else {
                return cancel(withReason: .couldNotDetermineDiscussion)
            }
            let lastMessage = try PersistedMessage.getLastMessage(in: discussion)
            
            // Do not set replyTo if the message to reply to is the last message of the discussion.
            let effectiveReplyTo = lastMessage == messageToReply ? nil : messageToReply
            
            // Create message to send
            
            let persistedMessageSent = try PersistedMessageSent.createPersistedMessageSentWhenReplyingFromTheNotificationExtensionNotification(
                body: replyBody,
                discussion: discussion,
                effectiveReplyTo: effectiveReplyTo)
            
            do {
                try obvContext.context.obtainPermanentIDs(for: [persistedMessageSent])
            } catch {
                return cancel(withReason: .couldNotObtainPermanentIDForPersistedMessageSent)
            }
            
            self.messageSentPermanentID = try? persistedMessageSent.objectPermanentID
            
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
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
    case couldNotDetermineDiscussion

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
        case .couldNotDetermineDiscussion:
            return .fault
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
        case .couldNotDetermineDiscussion: return "Could not determine discussion"
        }
    }

}
