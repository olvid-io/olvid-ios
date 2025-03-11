/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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

public enum ObvNetworkFetchNotificationNew {
	case fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
	case serverRequiresThisDeviceToRegisterToPushNotifications(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
	case inboxAttachmentWasDownloaded(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier)
	case inboxAttachmentDownloadCancelledByServer(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier)
	case inboxAttachmentDownloadWasResumed(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier)
	case inboxAttachmentDownloadWasPaused(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier)
	case cannotReturnAnyProgressForMessageAttachments(messageId: ObvMessageIdentifier, flowId: FlowIdentifier)
	case newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(ownedIdentity: ObvCryptoIdentity, apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?)
	case wellKnownHasBeenUpdated(serverURL: URL, appInfo: [String: AppInfo], flowId: FlowIdentifier)
	case wellKnownHasBeenDownloaded(serverURL: URL, appInfo: [String: AppInfo], flowId: FlowIdentifier)
	case wellKnownDownloadFailure(serverURL: URL, flowId: FlowIdentifier)
	case applicationMessagesDecrypted(messages: [ObvMessageOrObvOwnedMessage], flowId: FlowIdentifier)
	case downloadingMessageExtendedPayloadWasPerformed(message: ObvMessageOrObvOwnedMessage, flowId: FlowIdentifier)
	case pushTopicReceivedViaWebsocket(pushTopic: String)
	case keycloakTargetedPushNotificationReceivedViaWebsocket(ownedIdentity: ObvCryptoIdentity)
	case ownedDevicesMessageReceivedViaWebsocket(ownedIdentity: ObvCryptoIdentity)
	case newReturnReceiptToProcess(encryptedReceivedReturnReceipt: ObvEncryptedReceivedReturnReceipt)
	case serverAndInboxContainNoMoreUnprocessedMessages(ownedIdentity: ObvCryptoIdentity, downloadTimestampFromServer: Date)

	private enum Name {
		case fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive
		case serverRequiresThisDeviceToRegisterToPushNotifications
		case inboxAttachmentWasDownloaded
		case inboxAttachmentDownloadCancelledByServer
		case inboxAttachmentDownloadWasResumed
		case inboxAttachmentDownloadWasPaused
		case cannotReturnAnyProgressForMessageAttachments
		case newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity
		case wellKnownHasBeenUpdated
		case wellKnownHasBeenDownloaded
		case wellKnownDownloadFailure
		case applicationMessagesDecrypted
		case downloadingMessageExtendedPayloadWasPerformed
		case pushTopicReceivedViaWebsocket
		case keycloakTargetedPushNotificationReceivedViaWebsocket
		case ownedDevicesMessageReceivedViaWebsocket
		case newReturnReceiptToProcess
		case serverAndInboxContainNoMoreUnprocessedMessages

		private var namePrefix: String { String(describing: ObvNetworkFetchNotificationNew.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: ObvNetworkFetchNotificationNew) -> NSNotification.Name {
			switch notification {
			case .fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive: return Name.fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive.name
			case .serverRequiresThisDeviceToRegisterToPushNotifications: return Name.serverRequiresThisDeviceToRegisterToPushNotifications.name
			case .inboxAttachmentWasDownloaded: return Name.inboxAttachmentWasDownloaded.name
			case .inboxAttachmentDownloadCancelledByServer: return Name.inboxAttachmentDownloadCancelledByServer.name
			case .inboxAttachmentDownloadWasResumed: return Name.inboxAttachmentDownloadWasResumed.name
			case .inboxAttachmentDownloadWasPaused: return Name.inboxAttachmentDownloadWasPaused.name
			case .cannotReturnAnyProgressForMessageAttachments: return Name.cannotReturnAnyProgressForMessageAttachments.name
			case .newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity: return Name.newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity.name
			case .wellKnownHasBeenUpdated: return Name.wellKnownHasBeenUpdated.name
			case .wellKnownHasBeenDownloaded: return Name.wellKnownHasBeenDownloaded.name
			case .wellKnownDownloadFailure: return Name.wellKnownDownloadFailure.name
			case .applicationMessagesDecrypted: return Name.applicationMessagesDecrypted.name
			case .downloadingMessageExtendedPayloadWasPerformed: return Name.downloadingMessageExtendedPayloadWasPerformed.name
			case .pushTopicReceivedViaWebsocket: return Name.pushTopicReceivedViaWebsocket.name
			case .keycloakTargetedPushNotificationReceivedViaWebsocket: return Name.keycloakTargetedPushNotificationReceivedViaWebsocket.name
			case .ownedDevicesMessageReceivedViaWebsocket: return Name.ownedDevicesMessageReceivedViaWebsocket.name
			case .newReturnReceiptToProcess: return Name.newReturnReceiptToProcess.name
			case .serverAndInboxContainNoMoreUnprocessedMessages: return Name.serverAndInboxContainNoMoreUnprocessedMessages.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: let ownedIdentity, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"flowId": flowId,
			]
		case .serverRequiresThisDeviceToRegisterToPushNotifications(ownedIdentity: let ownedIdentity, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"flowId": flowId,
			]
		case .inboxAttachmentWasDownloaded(attachmentId: let attachmentId, flowId: let flowId):
			info = [
				"attachmentId": attachmentId,
				"flowId": flowId,
			]
		case .inboxAttachmentDownloadCancelledByServer(attachmentId: let attachmentId, flowId: let flowId):
			info = [
				"attachmentId": attachmentId,
				"flowId": flowId,
			]
		case .inboxAttachmentDownloadWasResumed(attachmentId: let attachmentId, flowId: let flowId):
			info = [
				"attachmentId": attachmentId,
				"flowId": flowId,
			]
		case .inboxAttachmentDownloadWasPaused(attachmentId: let attachmentId, flowId: let flowId):
			info = [
				"attachmentId": attachmentId,
				"flowId": flowId,
			]
		case .cannotReturnAnyProgressForMessageAttachments(messageId: let messageId, flowId: let flowId):
			info = [
				"messageId": messageId,
				"flowId": flowId,
			]
		case .newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(ownedIdentity: let ownedIdentity, apiKeyStatus: let apiKeyStatus, apiPermissions: let apiPermissions, apiKeyExpirationDate: let apiKeyExpirationDate):
			info = [
				"ownedIdentity": ownedIdentity,
				"apiKeyStatus": apiKeyStatus,
				"apiPermissions": apiPermissions,
				"apiKeyExpirationDate": OptionalWrapper(apiKeyExpirationDate),
			]
		case .wellKnownHasBeenUpdated(serverURL: let serverURL, appInfo: let appInfo, flowId: let flowId):
			info = [
				"serverURL": serverURL,
				"appInfo": appInfo,
				"flowId": flowId,
			]
		case .wellKnownHasBeenDownloaded(serverURL: let serverURL, appInfo: let appInfo, flowId: let flowId):
			info = [
				"serverURL": serverURL,
				"appInfo": appInfo,
				"flowId": flowId,
			]
		case .wellKnownDownloadFailure(serverURL: let serverURL, flowId: let flowId):
			info = [
				"serverURL": serverURL,
				"flowId": flowId,
			]
		case .applicationMessagesDecrypted(messages: let messages, flowId: let flowId):
			info = [
				"messages": messages,
				"flowId": flowId,
			]
		case .downloadingMessageExtendedPayloadWasPerformed(message: let message, flowId: let flowId):
			info = [
				"message": message,
				"flowId": flowId,
			]
		case .pushTopicReceivedViaWebsocket(pushTopic: let pushTopic):
			info = [
				"pushTopic": pushTopic,
			]
		case .keycloakTargetedPushNotificationReceivedViaWebsocket(ownedIdentity: let ownedIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
			]
		case .ownedDevicesMessageReceivedViaWebsocket(ownedIdentity: let ownedIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
			]
		case .newReturnReceiptToProcess(encryptedReceivedReturnReceipt: let encryptedReceivedReturnReceipt):
			info = [
				"encryptedReceivedReturnReceipt": encryptedReceivedReturnReceipt,
			]
		case .serverAndInboxContainNoMoreUnprocessedMessages(ownedIdentity: let ownedIdentity, downloadTimestampFromServer: let downloadTimestampFromServer):
			info = [
				"ownedIdentity": ownedIdentity,
				"downloadTimestampFromServer": downloadTimestampFromServer,
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

	public static func observeFetchNetworkOperationFailedSinceOwnedIdentityIsNotActive(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, flowId)
		}
	}

	public static func observeServerRequiresThisDeviceToRegisterToPushNotifications(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.serverRequiresThisDeviceToRegisterToPushNotifications.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, flowId)
		}
	}

	public static func observeInboxAttachmentWasDownloaded(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvAttachmentIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.inboxAttachmentWasDownloaded.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let attachmentId = notification.userInfo!["attachmentId"] as! ObvAttachmentIdentifier
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(attachmentId, flowId)
		}
	}

	public static func observeInboxAttachmentDownloadCancelledByServer(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvAttachmentIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.inboxAttachmentDownloadCancelledByServer.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let attachmentId = notification.userInfo!["attachmentId"] as! ObvAttachmentIdentifier
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(attachmentId, flowId)
		}
	}

	public static func observeInboxAttachmentDownloadWasResumed(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvAttachmentIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.inboxAttachmentDownloadWasResumed.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let attachmentId = notification.userInfo!["attachmentId"] as! ObvAttachmentIdentifier
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(attachmentId, flowId)
		}
	}

	public static func observeInboxAttachmentDownloadWasPaused(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvAttachmentIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.inboxAttachmentDownloadWasPaused.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let attachmentId = notification.userInfo!["attachmentId"] as! ObvAttachmentIdentifier
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(attachmentId, flowId)
		}
	}

	public static func observeCannotReturnAnyProgressForMessageAttachments(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvMessageIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.cannotReturnAnyProgressForMessageAttachments.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let messageId = notification.userInfo!["messageId"] as! ObvMessageIdentifier
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(messageId, flowId)
		}
	}

	public static func observeNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, APIKeyStatus, APIPermissions, Date?) -> Void) -> NSObjectProtocol {
		let name = Name.newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let apiKeyStatus = notification.userInfo!["apiKeyStatus"] as! APIKeyStatus
			let apiPermissions = notification.userInfo!["apiPermissions"] as! APIPermissions
			let apiKeyExpirationDateWrapper = notification.userInfo!["apiKeyExpirationDate"] as! OptionalWrapper<Date>
			let apiKeyExpirationDate = apiKeyExpirationDateWrapper.value
			block(ownedIdentity, apiKeyStatus, apiPermissions, apiKeyExpirationDate)
		}
	}

	public static func observeWellKnownHasBeenUpdated(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (URL, [String: AppInfo], FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.wellKnownHasBeenUpdated.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let serverURL = notification.userInfo!["serverURL"] as! URL
			let appInfo = notification.userInfo!["appInfo"] as! [String: AppInfo]
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(serverURL, appInfo, flowId)
		}
	}

	public static func observeWellKnownHasBeenDownloaded(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (URL, [String: AppInfo], FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.wellKnownHasBeenDownloaded.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let serverURL = notification.userInfo!["serverURL"] as! URL
			let appInfo = notification.userInfo!["appInfo"] as! [String: AppInfo]
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(serverURL, appInfo, flowId)
		}
	}

	public static func observeWellKnownDownloadFailure(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (URL, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.wellKnownDownloadFailure.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let serverURL = notification.userInfo!["serverURL"] as! URL
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(serverURL, flowId)
		}
	}

	public static func observeApplicationMessagesDecrypted(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping ([ObvMessageOrObvOwnedMessage], FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.applicationMessagesDecrypted.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let messages = notification.userInfo!["messages"] as! [ObvMessageOrObvOwnedMessage]
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(messages, flowId)
		}
	}

	public static func observeDownloadingMessageExtendedPayloadWasPerformed(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvMessageOrObvOwnedMessage, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.downloadingMessageExtendedPayloadWasPerformed.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let message = notification.userInfo!["message"] as! ObvMessageOrObvOwnedMessage
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(message, flowId)
		}
	}

	public static func observePushTopicReceivedViaWebsocket(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (String) -> Void) -> NSObjectProtocol {
		let name = Name.pushTopicReceivedViaWebsocket.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let pushTopic = notification.userInfo!["pushTopic"] as! String
			block(pushTopic)
		}
	}

	public static func observeKeycloakTargetedPushNotificationReceivedViaWebsocket(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.keycloakTargetedPushNotificationReceivedViaWebsocket.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			block(ownedIdentity)
		}
	}

	public static func observeOwnedDevicesMessageReceivedViaWebsocket(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.ownedDevicesMessageReceivedViaWebsocket.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			block(ownedIdentity)
		}
	}

	public static func observeNewReturnReceiptToProcess(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvEncryptedReceivedReturnReceipt) -> Void) -> NSObjectProtocol {
		let name = Name.newReturnReceiptToProcess.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let encryptedReceivedReturnReceipt = notification.userInfo!["encryptedReceivedReturnReceipt"] as! ObvEncryptedReceivedReturnReceipt
			block(encryptedReceivedReturnReceipt)
		}
	}

	public static func observeServerAndInboxContainNoMoreUnprocessedMessages(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, Date) -> Void) -> NSObjectProtocol {
		let name = Name.serverAndInboxContainNoMoreUnprocessedMessages.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let downloadTimestampFromServer = notification.userInfo!["downloadTimestampFromServer"] as! Date
			block(ownedIdentity, downloadTimestampFromServer)
		}
	}

}
