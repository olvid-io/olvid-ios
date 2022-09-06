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
import OlvidUtils
import ObvEngine
import os.log
import ObvTypes


/// This operation looks for an existing `PendingMessageReaction`. If one is found, this operation executes a `UpdateReactionsOfMessageOperation`.
final class ApplyPendingReactionsOperation: ContextualOperationWithSpecificReasonForCancel<ApplyPendingReactionsOperationReasonForCancel> {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ApplyPendingReactionsOperation.self))

    private let obvMessage: ObvMessage
    private let messageJSON: MessageJSON

    init(obvMessage: ObvMessage, messageJSON: MessageJSON) {
        self.obvMessage = obvMessage
        self.messageJSON = messageJSON
        super.init()
    }

    override func main() {

        os_log("Executing an ApplyPendingReactionsOperation for obvMessage %{public}@", log: log, type: .debug, obvMessage.messageIdentifierFromEngine.debugDescription)

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {

            // Grab the persisted contact and the appropriate discussion

            let persistedContactIdentity: PersistedObvContactIdentity
            do {
                guard let _persistedContactIdentity = try PersistedObvContactIdentity.get(persisted: obvMessage.fromContactIdentity, whereOneToOneStatusIs: .any, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindPersistedObvContactIdentityInDatabase)
                }
                persistedContactIdentity = _persistedContactIdentity
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

            guard let ownedIdentity = persistedContactIdentity.ownedIdentity else {
                return cancel(withReason: .couldNotDetermineOwnedIdentity)
            }

            let discussion: PersistedDiscussion
            do {
                if let groupId = messageJSON.groupId {
                    guard let contactGroup = try PersistedContactGroup.getContactGroup(groupId: groupId, ownedIdentity: ownedIdentity) else {
                        return cancel(withReason: .couldNotFindPersistedContactGroupInDatabase)
                    }
                    discussion = contactGroup.discussion
                } else if let oneToOneDiscussion = persistedContactIdentity.oneToOneDiscussion {
                    discussion = oneToOneDiscussion
                } else {
                    return cancel(withReason: .couldNotFindDiscussion)
                }
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

            // Look for an existing PendingMessageReaction for the received message in that discussion

            let pendingReaction: PendingMessageReaction?
            do {
                pendingReaction = try PendingMessageReaction.getPendingMessageReaction(
                    discussion: discussion,
                    senderIdentifier: obvMessage.fromContactIdentity.cryptoId.getIdentity(),
                    senderThreadIdentifier: messageJSON.senderThreadIdentifier,
                    senderSequenceNumber: messageJSON.senderSequenceNumber)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

            guard let pendingReaction = pendingReaction else {
                // We found no existing pending reaction, there is nothing left to do
                return
            }

            let op = UpdateReactionsOfMessageOperation(emoji: pendingReaction.emoji,
                                                       messageReference: pendingReaction.messageReferenceJSON,
                                                       groupId: messageJSON.groupId,
                                                       contactIdentity: obvMessage.fromContactIdentity,
                                                       reactionTimestamp: pendingReaction.serverTimestamp,
                                                       addPendingReactionIfMessageCannotBeFound: false)
            op.obvContext = obvContext
            op.main()
            guard !op.isCancelled else {
                guard let reason = op.reasonForCancel else { return cancel(withReason: .unknownReason) }
                return cancel(withReason: .updateReactionsOperationCancelled(reason: reason))
            }

            // If we reach this point, the remote request has been processed, we can delete it

            do {
                try pendingReaction.delete()
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
        }

    }


}


enum ApplyPendingReactionsOperationReasonForCancel: LocalizedErrorWithLogType {

    case unknownReason
    case contextIsNil
    case couldNotFindPersistedObvContactIdentityInDatabase
    case couldNotDetermineOwnedIdentity
    case couldNotFindPersistedContactGroupInDatabase
    case coreDataError(error: Error)
    case couldNotFindPersistedMessageReceived
    case updateReactionsOperationCancelled(reason: UpdateReactionsOperationReasonForCancel)
    case couldNotFindDiscussion

    var logType: OSLogType {
        switch self {
        case .couldNotFindPersistedObvContactIdentityInDatabase,
                .couldNotFindPersistedContactGroupInDatabase,
                .couldNotFindDiscussion:
            return .error
        case .unknownReason,
                .contextIsNil,
                .coreDataError,
                .couldNotDetermineOwnedIdentity,
                .couldNotFindPersistedMessageReceived:
            return .fault
        case .updateReactionsOperationCancelled(reason: let reason):
            return reason.logType
        }
    }

    var errorDescription: String? {
        switch self {
        case .unknownReason:
            return "One of the operations cancelled without speciying a reason. This is a bug."
        case .contextIsNil:
            return "The context is not set"
        case .couldNotFindPersistedObvContactIdentityInDatabase:
            return "Could not find contact identity of received message in database"
        case .couldNotFindPersistedContactGroupInDatabase:
            return "Could not find group of received message in database"
        case .couldNotDetermineOwnedIdentity:
            return "Could not determine owned identity"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindPersistedMessageReceived:
            return "Could not find message received although it is expected to be created within this context at this point"
        case .updateReactionsOperationCancelled(reason: let reason):
            return reason.errorDescription
        case .couldNotFindDiscussion:
            return "Could not find discussion"
        }
    }

}
