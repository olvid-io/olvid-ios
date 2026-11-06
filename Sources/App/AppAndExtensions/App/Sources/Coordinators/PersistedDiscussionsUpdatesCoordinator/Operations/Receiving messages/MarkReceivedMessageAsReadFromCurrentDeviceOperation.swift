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
import os.log
import CoreData
import OlvidUtils
import ObvUICoreData
import ObvTypes
import ObvAppTypes
import ObvAppCoreConstants


/// This is used when replying to a received message from a user notification, or when marking a received message as "read" from a user notification.
final class MarkReceivedMessageAsReadFromCurrentDeviceOperation: ContextualOperationWithSpecificReasonForCancel<MarkReceivedMessageAsReadFromCurrentDeviceOperation.ReasonForCancel>, @unchecked Sendable, OperationProvidingDiscussionReadJSON {

    enum Input {
        case messageReceivedID(MessageReceivedPermanentID)
        case messageID(MessagePermanentID)
        case messageAppIdentifier(ObvMessageAppIdentifier)
    }
    
    private let input: Input
    
    init(_ input: Input) {
        self.input = input
        super.init()
    }

    private(set) var persistedMessageReceivedObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>?
    private(set) var ownedCryptoId: ObvCryptoId?
    private(set) var ownedIdentityHasAnotherReachableDevice = false
    private(set) var discussionReadJSONToSend: DiscussionReadJSON?

    /// The `.read` return receipt produced by the producer after the message was marked as not new
    /// on this device. `nil` when the read obligation was already resolved (the user had opted out
    /// at insert time, the Intents extension already posted the receipt for a Siri-driven mark,
    /// a previous mark-as-read call on this message already emitted, the sender's payload carries
    /// no receipt element, or the contact has no known device UIDs). The caller is responsible for
    /// forwarding the receipt to the engine after the composed save commits.
    private(set) var readReceiptToSend: ObvReturnReceiptToSend?

    override public func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            let persistedMessageReceived: PersistedMessageReceived
            
            switch input {
            case .messageReceivedID(let messageReceivedID):
                guard let _persistedMessageReceived = try PersistedMessageReceived.getManagedObject(withPermanentID: messageReceivedID, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindReceivedMessageInDatabase)
                }
                persistedMessageReceived = _persistedMessageReceived
            case .messageID(let messagePermanentID):
                guard let _persistedMessageReceived = try PersistedMessage.getManagedObject(withPermanentID: messagePermanentID, within: obvContext.context) as? PersistedMessageReceived else {
                    return cancel(withReason: .couldNotFindReceivedMessageInDatabase)
                }
                persistedMessageReceived = _persistedMessageReceived
            case .messageAppIdentifier(let messageAppIdentifier):
                guard let _persistedMessageReceived = try PersistedMessage.getMessage(messageAppIdentifier: messageAppIdentifier, within: obvContext.context) as? PersistedMessageReceived else {
                    return cancel(withReason: .couldNotFindReceivedMessageInDatabase)
                }
                persistedMessageReceived = _persistedMessageReceived
            }
            
            let receivedMessageId = persistedMessageReceived.receivedMessageIdentifier
            
            guard let discussion = persistedMessageReceived.discussion else {
                return cancel(withReason: .couldNotFindDiscussionInDatabase)
            }
            
            let discussionId = try discussion.identifier
            
            guard let ownedIdentity = discussion.ownedIdentity else {
                assertionFailure()
                return cancel(withReason: .couldNotFindOwnedIdentity)
            }
            
            self.ownedCryptoId = ownedIdentity.cryptoId
            self.ownedIdentityHasAnotherReachableDevice = ownedIdentity.hasAnotherDeviceWhichIsReachable
            
            let dateWhenMessageTurnedNotNew = Date()
            let lastReadMessageServerTimestamp = try ownedIdentity.markReceivedMessageAsNotNew(discussionId: discussionId,
                                                                                               receivedMessageId: receivedMessageId,
                                                                                               dateWhenMessageTurnedNotNew: dateWhenMessageTurnedNotNew,
                                                                                               requestedOnAnotherOwnedDevice: false)

            // The mark-as-not-new above transitioned the status to .read on *this* device, so the
            // read-receipt producer can fire. The producer is idempotent: it returns nil if the
            // read obligation was already resolved (opt-out at insert, prior emission, …) and
            // atomically flips the flag so a subsequent call can never re-emit.
            self.readReceiptToSend = persistedMessageReceived.produceReadReceiptToSendIfAppropriate()

            do {
                if let lastReadMessageServerTimestamp {
                    discussionReadJSONToSend = try ownedIdentity.getDiscussionReadJSON(discussionId: discussionId, lastReadMessageServerTimestamp: lastReadMessageServerTimestamp)
                }
            } catch {
                assertionFailure(error.localizedDescription) // Continue anyway
            }

            
            do {
                persistedMessageReceivedObjectID = try ownedIdentity.getReceivedMessageTypedObjectID(discussionId: discussionId, receivedMessageId: receivedMessageId)
            } catch {
                assertionFailure(error.localizedDescription) // Continue anyway
            }
            
        } catch(let error) {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {

        case coreDataError(error: Error)
        case couldNotFindReceivedMessageInDatabase
        case couldNotFindDiscussionInDatabase
        case couldNotFindOwnedIdentity

        var logType: OSLogType {
            switch self {
            case .couldNotFindOwnedIdentity, .coreDataError, .couldNotFindDiscussionInDatabase:
                return .fault
            case .couldNotFindReceivedMessageInDatabase:
                return .error
            }
        }

        var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error): return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindReceivedMessageInDatabase: return "Could not find received message in database"
            case .couldNotFindOwnedIdentity: return "Could not find owned identity"
            case .couldNotFindDiscussionInDatabase: return "Could not find discussion in database"
            }
        }

    }

}
