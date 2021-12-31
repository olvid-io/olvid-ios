/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
    case powWasRequestedToTheServer(messageId: MessageIdentifier)
    case outboxMessageWasUploaded(messageId: MessageIdentifier)
    case deletionOfOutboxMessage(withId: MessageIdentifier)
    
    // For inbox messages
    case uidsOfMessagesThatWillBeDownloaded
    case networkReceivedMessageWasProcessed(messageId: MessageIdentifier)
    case applicationMessageDecrypted(messageId: MessageIdentifier)
    case extendedMessagePayloadWasDownloaded(messageId: MessageIdentifier)
    case protocolMessageToProcess
    case processingOfProtocolMessage(withId: MessageIdentifier)
    case deletionOfInboxMessage(withId: MessageIdentifier)
    
    // For outbox attachments
    case attachmentUploadRequestIsTakenCareOfForAttachment(withId: AttachmentIdentifier)
    
    // For inbox attachments
    case decisionToDownloadAttachmentOrNotHasBeenTaken(attachmentId: AttachmentIdentifier)
    
    
    static func == (lhs: Expectation, rhs: Expectation) -> Bool {
        switch lhs {
        case .extendedMessagePayloadWasDownloaded(messageId: let id1):
            switch rhs {
            case .extendedMessagePayloadWasDownloaded(messageId: let id2):
                return id1 == id2
            default:
                return false
            }
        case .powWasRequestedToTheServer(messageId: let id1):
            switch rhs {
            case .powWasRequestedToTheServer(messageId: let id2):
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
        case .processingOfProtocolMessage(withId: let id1):
            switch rhs {
            case .processingOfProtocolMessage(withId: let id2):
                return id1 == id2
            default:
                return false
            }
        case .uidsOfMessagesThatWillBeDownloaded:
            switch rhs {
            case .uidsOfMessagesThatWillBeDownloaded:
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
        }
    }
    
    var debugDescription: String {
        switch self {
        case .powWasRequestedToTheServer(messageId: let uid):
            return "powWasRequestedToTheServer<\(uid.debugDescription)>"
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
        case .processingOfProtocolMessage(withId: let uid):
            return "processingOfProtocolMessage<\(uid.debugDescription)>"
        case .uidsOfMessagesThatWillBeDownloaded:
            return "uidsOfMessagesThatWillBeDownloaded"
        case .applicationMessageDecrypted(messageId: let uid):
            return "applicationMessageDecrypted<\(uid.debugDescription)>"
        case .deletionOfInboxMessage(withId: let uid):
            return "deletionOfInboxMessage<\(uid.debugDescription)>"
        case .decisionToDownloadAttachmentOrNotHasBeenTaken(attachmentId: let attachmentId):
            return "decisionToDownloadAttachmentOrNotHasBeenTaken<\(attachmentId.debugDescription)>"
        case .extendedMessagePayloadWasDownloaded(messageId: let uid):
            return "extendedMessagePayloadWasDownloaded<\(uid.debugDescription)>"
        }
    }
    
    static func description(of expectations: Set<Expectation>) -> String {
        let descriptions = expectations.map { $0.debugDescription }
        return "[\(descriptions.joined(separator: ", "))]"
    }

    
}
