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
import ObvCrypto

enum Expectation: Equatable, Hashable, CustomDebugStringConvertible {
    
    // For outbox messages
    case outboxMessageWasUploaded(messageId: ObvMessageIdentifier)
    case deletionOfOutboxMessage(withId: ObvMessageIdentifier)
    
    // For inbox messages
    case uidsOfMessagesToProcess(ownedCryptoIdentity: ObvCryptoIdentity)
    case networkReceivedMessageWasProcessed(messageId: ObvMessageIdentifier)
    case applicationMessageDecrypted(messageId: ObvMessageIdentifier)
    case extendedMessagePayloadWasDownloaded(messageId: ObvMessageIdentifier)
    case protocolMessageToProcess
    case endOfProcessingOfProtocolMessage(withId: ObvMessageIdentifier)
    case deletionOfInboxMessage(withId: ObvMessageIdentifier)
    
    // For outbox attachments
    case attachmentUploadRequestIsTakenCareOfForAttachment(withId: ObvAttachmentIdentifier)
    
    // For inbox attachments
    case decisionToDownloadAttachmentOrNotHasBeenTaken(attachmentId: ObvAttachmentIdentifier)
    
    // For posting return receipts
    case returnReceiptWasPostedForMessage(messageId: ObvMessageIdentifier)
    case returnReceiptWasPostedForAttachment(attachmentId: ObvAttachmentIdentifier)

    
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
        case .uidsOfMessagesToProcess(ownedCryptoIdentity: let a1):
            switch rhs {
            case .uidsOfMessagesToProcess(ownedCryptoIdentity: let a2):
                return a1 == a2
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
        case .uidsOfMessagesToProcess(let ownedCryptoIdentity):
            return "uidsOfMessagesToProcess<\(ownedCryptoIdentity.debugDescription)>"
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
