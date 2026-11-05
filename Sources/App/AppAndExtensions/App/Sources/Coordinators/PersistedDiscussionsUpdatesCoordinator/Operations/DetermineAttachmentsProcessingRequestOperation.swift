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
import ObvCrypto
import OlvidUtils
import ObvTypes
import ObvUICoreData
import ObvAppCoreConstants


/// Determines which attachments the engine should download and which it should delete from the server.
///
/// Covers messages received from a contact (`PersistedMessageReceived`) and messages sent from another owned
/// device (`PersistedMessageSent`) in one place, because the interesting case spans both: `Fyle` is
/// content-addressed, so downloading one copy of a photo completes the joins of *every* message referencing
/// the same content — see `Fyle.updateFyle(obvAttachmentStatus:)` — and those messages can be of either
/// kind. Splitting this by message kind would mean each half still had to walk both kinds, and would leave
/// two places deciding what to tell the engine.
final class DetermineAttachmentsProcessingRequestOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {

    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "DetermineAttachmentsProcessingRequestOperation")
    private let kind: Kind

    enum Kind {
        /// A message just received from a contact, whose permanent ID an upstream operation provides.
        case allAttachmentsOfMessageReceived(op: OperationProvidingMessageReceivedPermanentID)
        /// A message just received from another owned device.
        case allAttachmentsOfMessageSent(messageSentPermanentId: MessageSentPermanentID)
        /// A single attachment, typically one whose download just finished or was cancelled by the server.
        case specificAttachment(attachmentId: ObvAttachmentIdentifier)
    }

    init(kind: Kind) {
        self.kind = kind
        super.init()
    }

    /// What the engine should do with the attachments of each message concerned, one entry per message.
    ///
    /// Usually a single entry, for the message named by `kind`. A downloaded attachment can concern more
    /// than one message though, for the deduplication reason described above: those messages have nothing
    /// left to fetch either, and unless the engine is told, their `InboxMessage` is never released.
    private(set) var attachmentsProcessingRequests = [(messageId: ObvMessageIdentifier, attachmentsProcessingRequest: ObvAttachmentsProcessingRequest)]()

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {

        os_log("Executing a DetermineAttachmentsProcessingRequestOperation", log: log, type: .debug)

        do {

            switch kind {

            case .allAttachmentsOfMessageReceived(let op):

                guard let messageReceivedPermanentId = op.messageReceivedPermanentId else { return }
                guard let message = try PersistedMessageReceived.getManagedObject(withPermanentID: messageReceivedPermanentId, within: obvContext.context) else { return }
                guard let messageId = message.obvMessageIdentifier else { assertionFailure(); return }

                append(receivedMessage: message, messageId: messageId, restrictedToAttachmentNumber: nil)

            case .allAttachmentsOfMessageSent(let messageSentPermanentId):

                guard let message = try PersistedMessageSent.getManagedObject(withPermanentID: messageSentPermanentId, within: obvContext.context) else { return }
                // Nil for a message sent from *this* device: it never went through the engine's inbox.
                guard let messageId = message.obvMessageIdentifier else { return }

                append(sentMessage: message, messageId: messageId, restrictedToAttachmentNumber: nil)

            case .specificAttachment(let attachmentId):

                // An engine message is either from a contact or from another owned device, never both, so
                // exactly one of these lookups succeeds.
                let fyle: Fyle?
                if let message = try PersistedMessageReceived.get(messageId: attachmentId.messageId, within: obvContext.context) {
                    append(receivedMessage: message, messageId: attachmentId.messageId, restrictedToAttachmentNumber: attachmentId.attachmentNumber)
                    fyle = message.fyleMessageJoinWithStatuses.first(where: { $0.index == attachmentId.attachmentNumber })?.fyle
                } else if let message = try PersistedMessageSent.get(messageId: attachmentId.messageId, within: obvContext.context) {
                    append(sentMessage: message, messageId: attachmentId.messageId, restrictedToAttachmentNumber: attachmentId.attachmentNumber)
                    fyle = message.fyleMessageJoinWithStatuses.first(where: { $0.index == attachmentId.attachmentNumber })?.fyle
                } else {
                    return
                }

                // Downloading this attachment also completed the joins of every other message referencing
                // the same content. Report those too, of either kind. Unlike the message above they are
                // reported in full, as *all* of their attachments may now be resolved, not just the one at
                // this attachment number.
                guard let fyle else { return }
                appendOtherMessagesSharing(fyle: fyle, excludingMessageWith: attachmentId.messageId)

            }

        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }

    }


    /// Adds an entry for every message referencing `fyle`, other than the one already reported.
    ///
    /// A message can reference the same content more than once, so entries are deduplicated: the engine
    /// expects one request covering all of a message's attachments, not one per attachment.
    private func appendOtherMessagesSharing(fyle: Fyle, excludingMessageWith messageId: ObvMessageIdentifier) {

        var reportedMessageIds = Set([messageId])

        for join in fyle.allFyleMessageJoinWithStatus {

            if let receivedJoin = join as? ReceivedFyleMessageJoinWithStatus {
                let message = receivedJoin.receivedMessage
                guard let otherMessageId = message.obvMessageIdentifier else { assertionFailure(); continue }
                guard reportedMessageIds.insert(otherMessageId).inserted else { continue }
                append(receivedMessage: message, messageId: otherMessageId, restrictedToAttachmentNumber: nil)

            } else if let sentJoin = join as? SentFyleMessageJoinWithStatus {
                let message = sentJoin.sentMessage
                // Nil for a message sent from this device, which has nothing in the engine's inbox.
                guard let otherMessageId = message.obvMessageIdentifier else { continue }
                guard reportedMessageIds.insert(otherMessageId).inserted else { continue }
                append(sentMessage: message, messageId: otherMessageId, restrictedToAttachmentNumber: nil)
            }

        }

    }


    private func append(receivedMessage: PersistedMessageReceived, messageId: ObvMessageIdentifier, restrictedToAttachmentNumber: Int?) {
        append(messageId: messageId,
               indexesToDownload: Set(receivedMessage.fyleMessageJoinWithStatusesToDownload.map(\.index)),
               indexesToDelete: Set(receivedMessage.fyleMessageJoinWithStatusesToDeleteFromServer.map(\.index)),
               restrictedToAttachmentNumber: restrictedToAttachmentNumber)
    }


    private func append(sentMessage: PersistedMessageSent, messageId: ObvMessageIdentifier, restrictedToAttachmentNumber: Int?) {
        append(messageId: messageId,
               indexesToDownload: Set(sentMessage.fyleMessageJoinWithStatusesToDownload.map(\.index)),
               indexesToDelete: Set(sentMessage.fyleMessageJoinWithStatusesFromOtherOwnedDeviceToDeleteFromServer.map(\.index)),
               restrictedToAttachmentNumber: restrictedToAttachmentNumber)
    }


    /// - Parameter restrictedToAttachmentNumber: when non-nil, only that attachment is considered.
    private func append(messageId: ObvMessageIdentifier, indexesToDownload: Set<Int>, indexesToDelete: Set<Int>, restrictedToAttachmentNumber: Int?) {

        var indexesToDownload = indexesToDownload
        var indexesToDelete = indexesToDelete

        if let restrictedToAttachmentNumber {
            indexesToDownload = indexesToDownload.filter { $0 == restrictedToAttachmentNumber }
            indexesToDelete = indexesToDelete.filter { $0 == restrictedToAttachmentNumber }
        }

        assert(indexesToDownload.intersection(indexesToDelete).isEmpty)

        var processingKindForAttachmentIndex = [Int: ObvAttachmentsProcessingRequest.ProcessingKind]()

        for index in indexesToDownload {
            processingKindForAttachmentIndex[index] = .download
        }

        for index in indexesToDelete {
            processingKindForAttachmentIndex[index] = .deleteFromServer
        }

        attachmentsProcessingRequests.append((messageId, .process(processingKindForAttachmentIndex: processingKindForAttachmentIndex)))

    }

}


protocol OperationProvidingMessageReceivedPermanentID: Operation {

    var messageReceivedPermanentId: MessageReceivedPermanentID? { get }

}
