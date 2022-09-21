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
import ObvTypes
import ObvMetaManager

enum Expectation: Equatable, Hashable, CustomDebugStringConvertible {
    
    // For outbox messages
    case outboxMessageWasUploaded(messageId: MessageIdentifier)
    case deletionOfOutboxMessage(withId: MessageIdentifier)
    
    // For inbox messages
    case uidsOfMessagesToProcess
    case networkReceivedMessageWasProcessed(messageId: MessageIdentifier)
    case applicationMessageDecrypted(messageId: MessageIdentifier)
    case extendedMessagePayloadWasDownloaded(messageId: MessageIdentifier)
    case protocolMessageToProcess
    case endOfProcessingOfProtocolMessage(withId: MessageIdentifier)
    case deletionOfInboxMessage(withId: MessageIdentifier)
    
    // For outbox attachments
    case attachmentUploadRequestIsTakenCareOfForAttachment(withId: AttachmentIdentifier)
    
    // For inbox attachments
    case decisionToDownloadAttachmentOrNotHasBeenTaken(attachmentId: AttachmentIdentifier)
    
    // For posting return receipts
    case returnReceiptWasPostedForMessage(messageId: MessageIdentifier)
    case returnReceiptWasPostedForAttachment(attachmentId: AttachmentIdentifier)

    
    static func == (lhs: Expectation, rhs: Expectation) -> Bool {
        switch lhs {
        case .extendedMessagePayloadWasDownloaded(messageId: let id1):
            switch rhs {
            case .extendedMessagePayloadWasDownloaded(messageId: let id2):
                return id1 == id2
            default:
                return false
            }
        case .outboxMessageWasUploaded(messageId: let id1):
            switch rhs {
            case .outboxMessageWasUploaded(messageId: let id2):
                return id1 == id2
            default:
                return false
            }
        case .attachmentUploadRequestIsTakenCareOfForAttachment(withId: let id1):
            switch rhs {
            case .attachmentUploadRequestIsTakenCareOfForAttachment(withId: let id2):
                return id1 == id2
            default:
                return false
            }
        case .deletionOfOutboxMessage(withId: let id1):
            switch rhs {
            case .deletionOfOutboxMessage(withId: let id2):
                return id1 == id2
            default:
                return false
            }
        case .protocolMessageToProcess:
            switch rhs {
            case .protocolMessageToProcess:
                return true
            default:
                return false
            }
        case .endOfProcessingOfProtocolMessage(withId: let id1):
            switch rhs {
            case .endOfProcessingOfProtocolMessage(withId: let id2):
                return id1 == id2
            default:
                return false
            }
        case .uidsOfMessagesToProcess:
            switch rhs {
            case .uidsOfMessagesToProcess:
                return true
            default:
                return false
            }
        case .networkReceivedMessageWasProcessed(messageId: let id1):
            switch rhs {
            case .networkReceivedMessageWasProcessed(messageId: let id2):
                return id1 == id2
            default:
                return false
            }
        case .applicationMessageDecrypted(messageId: let id1):
            switch rhs {
            case .applicationMessageDecrypted(messageId: let id2):
                return id1 == id2
            default:
                return false
            }
        case .deletionOfInboxMessage(withId: let id1):
            switch rhs {
            case .deletionOfInboxMessage(withId: let id2):
                return id1 == id2
            default:
                return false
            }
        case .decisionToDownloadAttachmentOrNotHasBeenTaken(attachmentId: let id1):
            switch rhs {
            case .decisionToDownloadAttachmentOrNotHasBeenTaken(attachmentId: let id2):
                return id1 == id2
            default:
                return false
            }
        case .returnReceiptWasPostedForMessage(messageId: let id1):
            switch rhs {
            case .returnReceiptWasPostedForMessage(messageId: let id2):
                return id1 == id2
            default:
                return false
            }
        case .returnReceiptWasPostedForAttachment(attachmentId: let id1):
            switch rhs {
            case .returnReceiptWasPostedForAttachment(attachmentId: let id2):
                return id1 == id2
            default:
                return false
            }
        }
    }
    
    var debugDescription: String {
        switch self {
        case .networkReceivedMessageWasProcessed(messageId: let uid):
            return "networkReceivedMessageWasProcessed<\(uid.debugDescription)>"
        case .outboxMessageWasUploaded(messageId: let uid):
            return "outboxMessageWasUploaded<\(uid.debugDescription)>"
        case .attachmentUploadRequestIsTakenCareOfForAttachment(withId: let attachmentId):
            return "attachmentUploadRequestIsTakenCareOfForAttachment<\(attachmentId.debugDescription)>"
        case .deletionOfOutboxMessage(withId: let uid):
            return "deletionOfOutboxMessage<\(uid.debugDescription)>"
        case .protocolMessageToProcess:
            return "protocolMessageToProcess"
        case .endOfProcessingOfProtocolMessage(withId: let uid):
            return "endOfProcessingOfProtocolMessage<\(uid.debugDescription)>"
        case .uidsOfMessagesToProcess:
            return "uidsOfMessagesToProcess"
        case .applicationMessageDecrypted(messageId: let uid):
            return "applicationMessageDecrypted<\(uid.debugDescription)>"
        case .deletionOfInboxMessage(withId: let uid):
            return "deletionOfInboxMessage<\(uid.debugDescription)>"
        case .decisionToDownloadAttachmentOrNotHasBeenTaken(attachmentId: let attachmentId):
            return "decisionToDownloadAttachmentOrNotHasBeenTaken<\(attachmentId.debugDescription)>"
        case .extendedMessagePayloadWasDownloaded(messageId: let uid):
            return "extendedMessagePayloadWasDownloaded<\(uid.debugDescription)>"
        case .returnReceiptWasPostedForMessage(messageId: let uid):
            return "returnReceiptWasPostedForMessage<\(uid.debugDescription)>"
        case .returnReceiptWasPostedForAttachment(attachmentId: let attachmentId):
            return "returnReceiptWasPostedForAttachment<\(attachmentId.debugDescription)>"
        }
    }
    
    static func description(of expectations: Set<Expectation>) -> String {
        let descriptions = expectations.map { $0.debugDescription }
        return "[\(descriptions.joined(separator: ", "))]"
    }

    
}
