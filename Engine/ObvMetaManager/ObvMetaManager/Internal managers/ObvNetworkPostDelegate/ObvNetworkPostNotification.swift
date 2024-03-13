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
import ObvCrypto
import ObvTypes
import OlvidUtils

fileprivate struct OptionalWrapper<T> {
	let value: T?
	public init() {
		self.value = nil
	}
	public init(_ value: T?) {
		self.value = value
	}
}

public enum ObvNetworkPostNotification {
	case newOutboxMessageAndAttachmentsToUpload(messageId: ObvMessageIdentifier, attachmentIds: [ObvAttachmentIdentifier], flowId: FlowIdentifier)
	case outboxMessageAndAttachmentsDeleted(messageId: ObvMessageIdentifier, flowId: FlowIdentifier)
	case attachmentUploadRequestIsTakenCareOf(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier)
	case postNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
	case outboxMessageWasUploaded(messageId: ObvMessageIdentifier, timestampFromServer: Date, isAppMessageWithUserContent: Bool, isVoipMessage: Bool, flowId: FlowIdentifier)
	case outboxAttachmentWasAcknowledged(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier)
	case outboxMessagesAndAllTheirAttachmentsWereAcknowledged(messageIdsAndTimestampsFromServer: [(messageId: ObvMessageIdentifier, timestampFromServer: Date)], flowId: FlowIdentifier)
	case outboxMessageCouldNotBeSentToServer(messageId: ObvMessageIdentifier, flowId: FlowIdentifier)

	private enum Name {
		case newOutboxMessageAndAttachmentsToUpload
		case outboxMessageAndAttachmentsDeleted
		case attachmentUploadRequestIsTakenCareOf
		case postNetworkOperationFailedSinceOwnedIdentityIsNotActive
		case outboxMessageWasUploaded
		case outboxAttachmentWasAcknowledged
		case outboxMessagesAndAllTheirAttachmentsWereAcknowledged
		case outboxMessageCouldNotBeSentToServer

		private var namePrefix: String { String(describing: ObvNetworkPostNotification.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: ObvNetworkPostNotification) -> NSNotification.Name {
			switch notification {
			case .newOutboxMessageAndAttachmentsToUpload: return Name.newOutboxMessageAndAttachmentsToUpload.name
			case .outboxMessageAndAttachmentsDeleted: return Name.outboxMessageAndAttachmentsDeleted.name
			case .attachmentUploadRequestIsTakenCareOf: return Name.attachmentUploadRequestIsTakenCareOf.name
			case .postNetworkOperationFailedSinceOwnedIdentityIsNotActive: return Name.postNetworkOperationFailedSinceOwnedIdentityIsNotActive.name
			case .outboxMessageWasUploaded: return Name.outboxMessageWasUploaded.name
			case .outboxAttachmentWasAcknowledged: return Name.outboxAttachmentWasAcknowledged.name
			case .outboxMessagesAndAllTheirAttachmentsWereAcknowledged: return Name.outboxMessagesAndAllTheirAttachmentsWereAcknowledged.name
			case .outboxMessageCouldNotBeSentToServer: return Name.outboxMessageCouldNotBeSentToServer.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .newOutboxMessageAndAttachmentsToUpload(messageId: let messageId, attachmentIds: let attachmentIds, flowId: let flowId):
			info = [
				"messageId": messageId,
				"attachmentIds": attachmentIds,
				"flowId": flowId,
			]
		case .outboxMessageAndAttachmentsDeleted(messageId: let messageId, flowId: let flowId):
			info = [
				"messageId": messageId,
				"flowId": flowId,
			]
		case .attachmentUploadRequestIsTakenCareOf(attachmentId: let attachmentId, flowId: let flowId):
			info = [
				"attachmentId": attachmentId,
				"flowId": flowId,
			]
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
		case .outboxMessageCouldNotBeSentToServer(messageId: let messageId, flowId: let flowId):
			info = [
				"messageId": messageId,
				"flowId": flowId,
			]
		}
		return info
	}

	public func postOnBackgroundQueue(_ queue: DispatchQueue? = nil, within notificationDelegate: ObvNotificationDelegate) {
		let name = Name.forInternalNotification(self)
		let label = "Queue for posting \(name.rawValue) notification"
		let backgroundQueue = queue ?? DispatchQueue(label: label)
		backgroundQueue.async {
			notificationDelegate.post(name: name, userInfo: userInfo)
		}
	}

	public static func observeNewOutboxMessageAndAttachmentsToUpload(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvMessageIdentifier, [ObvAttachmentIdentifier], FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.newOutboxMessageAndAttachmentsToUpload.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let messageId = notification.userInfo!["messageId"] as! ObvMessageIdentifier
			let attachmentIds = notification.userInfo!["attachmentIds"] as! [ObvAttachmentIdentifier]
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(messageId, attachmentIds, flowId)
		}
	}

	public static func observeOutboxMessageAndAttachmentsDeleted(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvMessageIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.outboxMessageAndAttachmentsDeleted.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let messageId = notification.userInfo!["messageId"] as! ObvMessageIdentifier
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(messageId, flowId)
		}
	}

	public static func observeAttachmentUploadRequestIsTakenCareOf(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvAttachmentIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.attachmentUploadRequestIsTakenCareOf.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let attachmentId = notification.userInfo!["attachmentId"] as! ObvAttachmentIdentifier
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(attachmentId, flowId)
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

	public static func observeOutboxMessageWasUploaded(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvMessageIdentifier, Date, Bool, Bool, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.outboxMessageWasUploaded.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let messageId = notification.userInfo!["messageId"] as! ObvMessageIdentifier
			let timestampFromServer = notification.userInfo!["timestampFromServer"] as! Date
			let isAppMessageWithUserContent = notification.userInfo!["isAppMessageWithUserContent"] as! Bool
			let isVoipMessage = notification.userInfo!["isVoipMessage"] as! Bool
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(messageId, timestampFromServer, isAppMessageWithUserContent, isVoipMessage, flowId)
		}
	}

	public static func observeOutboxAttachmentWasAcknowledged(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvAttachmentIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.outboxAttachmentWasAcknowledged.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let attachmentId = notification.userInfo!["attachmentId"] as! ObvAttachmentIdentifier
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(attachmentId, flowId)
		}
	}

	public static func observeOutboxMessagesAndAllTheirAttachmentsWereAcknowledged(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping ([(messageId: ObvMessageIdentifier, timestampFromServer: Date)], FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.outboxMessagesAndAllTheirAttachmentsWereAcknowledged.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let messageIdsAndTimestampsFromServer = notification.userInfo!["messageIdsAndTimestampsFromServer"] as! [(messageId: ObvMessageIdentifier, timestampFromServer: Date)]
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(messageIdsAndTimestampsFromServer, flowId)
		}
	}

	public static func observeOutboxMessageCouldNotBeSentToServer(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvMessageIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.outboxMessageCouldNotBeSentToServer.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let messageId = notification.userInfo!["messageId"] as! ObvMessageIdentifier
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(messageId, flowId)
		}
	}

}
