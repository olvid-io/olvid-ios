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
import ObvCrypto
import ObvTypes
import OlvidUtils


public struct ObvNetworkPostNotification {
    
    
    // MARK: - Outbox messages
    
    public struct NewOutboxMessageAndAttachmentsToUpload {
        public static let name = Notification.Name("ObvNetworkPostNotification.NewOutboxMessageAndAttachmentsToUpload")
        public struct Key {
            public static let messageId = "messageId"
            public static let attachmentIds = "attachmentIds"
            public static let flowId = "flowId"
        }
        public static func parse(_ notification: Notification) -> (messageId: MessageIdentifier, attachmentIds: [AttachmentIdentifier], flowId: FlowIdentifier)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let messageId = userInfo[Key.messageId] as? MessageIdentifier else { return nil }
            guard let attachmentIds = userInfo[Key.attachmentIds] as? [AttachmentIdentifier] else { return nil }
            guard let flowId = userInfo[Key.flowId] as? FlowIdentifier else { return nil }
            return (messageId, attachmentIds, flowId)
        }
    }
    
    public struct OutboxMessageAndAttachmentsDeleted {
        public static let name = Notification.Name("ObvNetworkPostNotification.OutboxMessageAndAttachmentsDeleted")
        public struct Key {
            public static let messageId = "messageId"
            public static let flowId = "flowId"
        }
        public static func parse(_ notification: Notification) -> (messageId: MessageIdentifier, flowId: FlowIdentifier)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let messageId = userInfo[Key.messageId] as? MessageIdentifier else { return nil }
            guard let flowId = userInfo[Key.flowId] as? FlowIdentifier else { return nil }
            return (messageId, flowId)
        }
    }

    
    // MARK: - Outbox attachments
    
    public struct AttachmentUploadRequestIsTakenCareOf {
        public static let name = Notification.Name("ObvNetworkPostNotification.AttachmentUploadRequestIsTakenCareOf")
        public struct Key {
            public static let flowId = "flowId"
            public static let attachmentId = "attachmentId"
        }
        public static func parse(_ notification: Notification) -> (attachmendId: AttachmentIdentifier, flowId: FlowIdentifier)? {
            guard notification.name == name else { assert(false); return nil }
            guard let userInfo = notification.userInfo else { assert(false); return nil }
            guard let flowId = userInfo[Key.flowId] as? FlowIdentifier else { assert(false); return nil }
            guard let attachmentId = userInfo[Key.attachmentId] as? AttachmentIdentifier else { assert(false); return nil }
            return (attachmentId, flowId)
        }
    }

    
    public struct PoWChallengeMethodWasRequested {
        public static let name = Notification.Name("ObvNetworkPostNotification.PoWChallengeMethodWasRequested")
        public struct Key {
            public static let messageId = "messageId"
            public static let flowId = "flowId"
        }
        public static func parse(_ notification: Notification) -> (messageId: MessageIdentifier, flowId: FlowIdentifier)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let messageId = userInfo[Key.messageId] as? MessageIdentifier else { return nil }
            guard let flowId = userInfo[Key.flowId] as? FlowIdentifier else { return nil }
            return (messageId, flowId)
        }
    }
    
    
}


public enum ObvNetworkPostNotificationNew {
    
    case postNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
    case outboxMessageWasUploaded(messageId: MessageIdentifier, timestampFromServer: Date, isAppMessageWithUserContent: Bool, isVoipMessage: Bool, flowId: FlowIdentifier)
    case outboxAttachmentHasNewProgress(attachmentId: AttachmentIdentifier, newProgress: Progress, flowId: FlowIdentifier)
    /// Posted after all the attachment's bytes have been acknowledged by the server
    case outboxAttachmentWasAcknowledged(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier)
    case outboxMessagesAndAllTheirAttachmentsWereAcknowledged(messageIdsAndTimestampsFromServer: [(messageId: MessageIdentifier, timestampFromServer: Date)], flowId: FlowIdentifier)

    private enum Name {
        case postNetworkOperationFailedSinceOwnedIdentityIsNotActive
        case outboxMessageWasUploaded
        case outboxAttachmentHasNewProgress
        case outboxAttachmentWasAcknowledged
        case outboxMessagesAndAllTheirAttachmentsWereAcknowledged

        private var namePrefix: String { return "ObvNetworkPostNotificationNew" }
        
        private var nameSuffix: String {
            switch self {
            case .postNetworkOperationFailedSinceOwnedIdentityIsNotActive: return "postNetworkOperationFailedSinceOwnedIdentityIsNotActive"
            case .outboxMessageWasUploaded: return "outboxMessageWasUploaded"
            case .outboxAttachmentHasNewProgress: return "outboxAttachmentHasNewProgress"
            case .outboxAttachmentWasAcknowledged: return "outboxAttachmentWasAcknowledged"
            case .outboxMessagesAndAllTheirAttachmentsWereAcknowledged: return "outboxMessagesAndAllTheirAttachmentsWereAcknowledged"
            }
        }

        var name: NSNotification.Name {
            let name = [namePrefix, nameSuffix].joined(separator: ".")
            return NSNotification.Name(name)
        }
        
        static func forInternalNotification(_ notification: ObvNetworkPostNotificationNew) -> NSNotification.Name {
            switch notification {
            case .postNetworkOperationFailedSinceOwnedIdentityIsNotActive: return Name.postNetworkOperationFailedSinceOwnedIdentityIsNotActive.name
            case .outboxMessageWasUploaded: return Name.outboxMessageWasUploaded.name
            case .outboxAttachmentHasNewProgress: return Name.outboxAttachmentHasNewProgress.name
            case .outboxAttachmentWasAcknowledged: return Name.outboxAttachmentWasAcknowledged.name
            case .outboxMessagesAndAllTheirAttachmentsWereAcknowledged: return Name.outboxMessagesAndAllTheirAttachmentsWereAcknowledged.name
            }
        }
        
    }

    public static let outboxMessageWasUploadedName = Name.outboxMessageWasUploaded.name
    public static let outboxAttachmentHasNewProgressName = Name.outboxAttachmentHasNewProgress.name
    public static let outboxAttachmentWasAcknowledgedName = Name.outboxAttachmentWasAcknowledged.name

    private var userInfo: [AnyHashable: Any]? {
        let info: [AnyHashable: Any]?
        switch self {
        case .postNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: let ownedIdentity, flowId: let flowId):
            info = [
                "ownedIdentity": ownedIdentity,
                "flowId": flowId,
            ]
        case .outboxMessageWasUploaded(messageId: let messageId, timestampFromServer: let timestampFromServer, isAppMessageWithUserContent: let isAppMessageWithUserContent, isVoipMessage: let isVoipMessage, flowId: let flowId):
            info = [
                "messageId": messageId,
                "timestampFromServer": timestampFromServer,
                "isAppMessageWithUserContent": isAppMessageWithUserContent,
                "isVoipMessage": isVoipMessage,
                "flowId": flowId,
            ]
        case .outboxAttachmentHasNewProgress(attachmentId: let attachmentId, newProgress: let newProgress, flowId: let flowId):
            info = [
                "attachmentId": attachmentId,
                "newProgress": newProgress,
                "flowId": flowId,
            ]
        case .outboxAttachmentWasAcknowledged(attachmentId: let attachmentId, flowId: let flowId):
            info = [
                "attachmentId": attachmentId,
                "flowId": flowId,
            ]
        case .outboxMessagesAndAllTheirAttachmentsWereAcknowledged(messageIdsAndTimestampsFromServer: let messageIdsAndTimestampsFromServer, flowId: let flowId):
            info = [
                "messageIdsAndTimestampsFromServer": messageIdsAndTimestampsFromServer,
                "flowId": flowId,
            ]
        }
        return info
    }
    
    func post(within notificationDelegate: ObvNotificationDelegate) {
        let name = Name.forInternalNotification(self)
        notificationDelegate.post(name: name, userInfo: userInfo)
    }

    public func postOnDispatchQueue(withLabel label: String, within notificationDelegate: ObvNotificationDelegate) {
        let name = Name.forInternalNotification(self)
        let userInfo = self.userInfo
        DispatchQueue(label: label).async {
            notificationDelegate.post(name: name, userInfo: userInfo)
        }
    }

    public func postOnDispatchQueue(dispatchQueue: DispatchQueue, within notificationDelegate: ObvNotificationDelegate) {
        let name = Name.forInternalNotification(self)
        let userInfo = self.userInfo
        dispatchQueue.async {
            notificationDelegate.post(name: name, userInfo: userInfo)
        }
    }

    public func postOnOperationQueue(operationQueue: OperationQueue, within notificationDelegate: ObvNotificationDelegate) {
        let name = Name.forInternalNotification(self)
        let userInfo = self.userInfo
        operationQueue.addOperation {
            notificationDelegate.post(name: name, userInfo: userInfo)
        }
    }

    
    public static func observeOutboxMessagesAndAllTheirAttachmentsWereAcknowledged(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping ([(messageId: MessageIdentifier, timestampFromServer: Date)], FlowIdentifier) -> Void) -> NSObjectProtocol {
        let name = Name.outboxMessagesAndAllTheirAttachmentsWereAcknowledged.name
        return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
            let messageIdsAndTimestampsFromServer = notification.userInfo!["messageIdsAndTimestampsFromServer"] as! [(messageId: MessageIdentifier, timestampFromServer: Date)]
            let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
            block(messageIdsAndTimestampsFromServer, flowId)
        }
    }

    
    public static func observeOutboxAttachmentWasAcknowledged(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (AttachmentIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
        let name = Name.outboxAttachmentWasAcknowledged.name
        return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
            let attachmentId = notification.userInfo!["attachmentId"] as! AttachmentIdentifier
            let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
            block(attachmentId, flowId)
        }
    }

    
    public static func observeOutboxAttachmentHasNewProgress(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (AttachmentIdentifier, Progress, FlowIdentifier) -> Void) -> NSObjectProtocol {
        let name = Name.outboxAttachmentHasNewProgress.name
        return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
            let attachmentId = notification.userInfo!["attachmentId"] as! AttachmentIdentifier
            let newProgress = notification.userInfo!["newProgress"] as! Progress
            let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
            block(attachmentId, newProgress, flowId)
        }
    }

    
    public static func observeOutboxMessageWasUploaded(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (MessageIdentifier, Date, Bool, Bool, FlowIdentifier) -> Void) -> NSObjectProtocol {
        let name = Name.outboxMessageWasUploaded.name
        return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
            let messageId = notification.userInfo!["messageId"] as! MessageIdentifier
            let timestampFromServer = notification.userInfo!["timestampFromServer"] as! Date
            let isAppMessageWithUserContent = notification.userInfo!["isAppMessageWithUserContent"] as! Bool
            let isVoipMessage = notification.userInfo!["isVoipMessage"] as! Bool
            let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
            block(messageId, timestampFromServer, isAppMessageWithUserContent, isVoipMessage, flowId)
        }
    }

    public static func observePostNetworkOperationFailedSinceOwnedIdentityIsNotActive(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, FlowIdentifier) -> Void) -> NSObjectProtocol {
        let name = Name.postNetworkOperationFailedSinceOwnedIdentityIsNotActive.name
        return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
            let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
            let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
            block(ownedIdentity, flowId)
        }
    }

}
