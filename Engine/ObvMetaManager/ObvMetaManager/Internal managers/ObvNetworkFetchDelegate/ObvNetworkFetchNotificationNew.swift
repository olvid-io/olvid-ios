/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
	case serverReportedThatAnotherDeviceIsAlreadyRegistered(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
	case serverReportedThatThisDeviceWasSuccessfullyRegistered(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
	case fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
	case serverRequiresThisDeviceToRegisterToPushNotifications(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
	case inboxAttachmentWasDownloaded(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier)
	case inboxAttachmentDownloadCancelledByServer(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier)
	case inboxAttachmentDownloadWasResumed(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier)
	case inboxAttachmentDownloadWasPaused(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier)
	case inboxAttachmentWasTakenCareOf(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier)
	case noInboxMessageToProcess(flowId: FlowIdentifier, ownedCryptoIdentity: ObvCryptoIdentity)
	case newInboxMessageToProcess(messageId: MessageIdentifier, attachmentIds: [AttachmentIdentifier], flowId: FlowIdentifier)
	case turnCredentialsReceived(ownedIdentity: ObvCryptoIdentity, callUuid: UUID, turnCredentialsWithTurnServers: TurnCredentialsWithTurnServers, flowId: FlowIdentifier)
	case turnCredentialsReceptionFailure(ownedIdentity: ObvCryptoIdentity, callUuid: UUID, flowId: FlowIdentifier)
	case turnCredentialsReceptionPermissionDenied(ownedIdentity: ObvCryptoIdentity, callUuid: UUID, flowId: FlowIdentifier)
	case turnCredentialServerDoesNotSupportCalls(ownedIdentity: ObvCryptoIdentity, callUuid: UUID, flowId: FlowIdentifier)
	case cannotReturnAnyProgressForMessageAttachments(messageId: MessageIdentifier, flowId: FlowIdentifier)
	case newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(ownedIdentity: ObvCryptoIdentity, apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?)
	case newAPIKeyElementsForAPIKey(serverURL: URL, apiKey: UUID, apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?)
	case newFreeTrialAPIKeyForOwnedIdentity(ownedIdentity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier)
	case noMoreFreeTrialAPIKeyAvailableForOwnedIdentity(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
	case freeTrialIsStillAvailableForOwnedIdentity(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
	case appStoreReceiptVerificationFailed(ownedIdentity: ObvCryptoIdentity, transactionIdentifier: String, flowId: FlowIdentifier)
	case appStoreReceiptVerificationSucceededAndSubscriptionIsValid(ownedIdentity: ObvCryptoIdentity, transactionIdentifier: String, apiKey: UUID, flowId: FlowIdentifier)
	case appStoreReceiptVerificationSucceededButSubscriptionIsExpired(ownedIdentity: ObvCryptoIdentity, transactionIdentifier: String, flowId: FlowIdentifier)
	case wellKnownHasBeenUpdated(serverURL: URL, appInfo: [String: AppInfo], flowId: FlowIdentifier)
	case wellKnownHasBeenDownloaded(serverURL: URL, appInfo: [String: AppInfo], flowId: FlowIdentifier)
	case wellKnownDownloadFailure(serverURL: URL, flowId: FlowIdentifier)
	case apiKeyStatusQueryFailed(ownedIdentity: ObvCryptoIdentity, apiKey: UUID)
	case applicationMessageDecrypted(messageId: MessageIdentifier, attachmentIds: [AttachmentIdentifier], hasEncryptedExtendedMessagePayload: Bool, flowId: FlowIdentifier)
	case downloadingMessageExtendedPayloadWasPerformed(messageId: MessageIdentifier, flowId: FlowIdentifier)
	case downloadingMessageExtendedPayloadFailed(messageId: MessageIdentifier, flowId: FlowIdentifier)
	case pushTopicReceivedViaWebsocket(pushTopic: String)
	case keycloakTargetedPushNotificationReceivedViaWebsocket(ownedIdentity: ObvCryptoIdentity)

	private enum Name {
		case serverReportedThatAnotherDeviceIsAlreadyRegistered
		case serverReportedThatThisDeviceWasSuccessfullyRegistered
		case fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive
		case serverRequiresThisDeviceToRegisterToPushNotifications
		case inboxAttachmentWasDownloaded
		case inboxAttachmentDownloadCancelledByServer
		case inboxAttachmentDownloadWasResumed
		case inboxAttachmentDownloadWasPaused
		case inboxAttachmentWasTakenCareOf
		case noInboxMessageToProcess
		case newInboxMessageToProcess
		case turnCredentialsReceived
		case turnCredentialsReceptionFailure
		case turnCredentialsReceptionPermissionDenied
		case turnCredentialServerDoesNotSupportCalls
		case cannotReturnAnyProgressForMessageAttachments
		case newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity
		case newAPIKeyElementsForAPIKey
		case newFreeTrialAPIKeyForOwnedIdentity
		case noMoreFreeTrialAPIKeyAvailableForOwnedIdentity
		case freeTrialIsStillAvailableForOwnedIdentity
		case appStoreReceiptVerificationFailed
		case appStoreReceiptVerificationSucceededAndSubscriptionIsValid
		case appStoreReceiptVerificationSucceededButSubscriptionIsExpired
		case wellKnownHasBeenUpdated
		case wellKnownHasBeenDownloaded
		case wellKnownDownloadFailure
		case apiKeyStatusQueryFailed
		case applicationMessageDecrypted
		case downloadingMessageExtendedPayloadWasPerformed
		case downloadingMessageExtendedPayloadFailed
		case pushTopicReceivedViaWebsocket
		case keycloakTargetedPushNotificationReceivedViaWebsocket

		private var namePrefix: String { String(describing: ObvNetworkFetchNotificationNew.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: ObvNetworkFetchNotificationNew) -> NSNotification.Name {
			switch notification {
			case .serverReportedThatAnotherDeviceIsAlreadyRegistered: return Name.serverReportedThatAnotherDeviceIsAlreadyRegistered.name
			case .serverReportedThatThisDeviceWasSuccessfullyRegistered: return Name.serverReportedThatThisDeviceWasSuccessfullyRegistered.name
			case .fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive: return Name.fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive.name
			case .serverRequiresThisDeviceToRegisterToPushNotifications: return Name.serverRequiresThisDeviceToRegisterToPushNotifications.name
			case .inboxAttachmentWasDownloaded: return Name.inboxAttachmentWasDownloaded.name
			case .inboxAttachmentDownloadCancelledByServer: return Name.inboxAttachmentDownloadCancelledByServer.name
			case .inboxAttachmentDownloadWasResumed: return Name.inboxAttachmentDownloadWasResumed.name
			case .inboxAttachmentDownloadWasPaused: return Name.inboxAttachmentDownloadWasPaused.name
			case .inboxAttachmentWasTakenCareOf: return Name.inboxAttachmentWasTakenCareOf.name
			case .noInboxMessageToProcess: return Name.noInboxMessageToProcess.name
			case .newInboxMessageToProcess: return Name.newInboxMessageToProcess.name
			case .turnCredentialsReceived: return Name.turnCredentialsReceived.name
			case .turnCredentialsReceptionFailure: return Name.turnCredentialsReceptionFailure.name
			case .turnCredentialsReceptionPermissionDenied: return Name.turnCredentialsReceptionPermissionDenied.name
			case .turnCredentialServerDoesNotSupportCalls: return Name.turnCredentialServerDoesNotSupportCalls.name
			case .cannotReturnAnyProgressForMessageAttachments: return Name.cannotReturnAnyProgressForMessageAttachments.name
			case .newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity: return Name.newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity.name
			case .newAPIKeyElementsForAPIKey: return Name.newAPIKeyElementsForAPIKey.name
			case .newFreeTrialAPIKeyForOwnedIdentity: return Name.newFreeTrialAPIKeyForOwnedIdentity.name
			case .noMoreFreeTrialAPIKeyAvailableForOwnedIdentity: return Name.noMoreFreeTrialAPIKeyAvailableForOwnedIdentity.name
			case .freeTrialIsStillAvailableForOwnedIdentity: return Name.freeTrialIsStillAvailableForOwnedIdentity.name
			case .appStoreReceiptVerificationFailed: return Name.appStoreReceiptVerificationFailed.name
			case .appStoreReceiptVerificationSucceededAndSubscriptionIsValid: return Name.appStoreReceiptVerificationSucceededAndSubscriptionIsValid.name
			case .appStoreReceiptVerificationSucceededButSubscriptionIsExpired: return Name.appStoreReceiptVerificationSucceededButSubscriptionIsExpired.name
			case .wellKnownHasBeenUpdated: return Name.wellKnownHasBeenUpdated.name
			case .wellKnownHasBeenDownloaded: return Name.wellKnownHasBeenDownloaded.name
			case .wellKnownDownloadFailure: return Name.wellKnownDownloadFailure.name
			case .apiKeyStatusQueryFailed: return Name.apiKeyStatusQueryFailed.name
			case .applicationMessageDecrypted: return Name.applicationMessageDecrypted.name
			case .downloadingMessageExtendedPayloadWasPerformed: return Name.downloadingMessageExtendedPayloadWasPerformed.name
			case .downloadingMessageExtendedPayloadFailed: return Name.downloadingMessageExtendedPayloadFailed.name
			case .pushTopicReceivedViaWebsocket: return Name.pushTopicReceivedViaWebsocket.name
			case .keycloakTargetedPushNotificationReceivedViaWebsocket: return Name.keycloakTargetedPushNotificationReceivedViaWebsocket.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .serverReportedThatAnotherDeviceIsAlreadyRegistered(ownedIdentity: let ownedIdentity, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"flowId": flowId,
			]
		case .serverReportedThatThisDeviceWasSuccessfullyRegistered(ownedIdentity: let ownedIdentity, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"flowId": flowId,
			]
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
		case .inboxAttachmentWasTakenCareOf(attachmentId: let attachmentId, flowId: let flowId):
			info = [
				"attachmentId": attachmentId,
				"flowId": flowId,
			]
		case .noInboxMessageToProcess(flowId: let flowId, ownedCryptoIdentity: let ownedCryptoIdentity):
			info = [
				"flowId": flowId,
				"ownedCryptoIdentity": ownedCryptoIdentity,
			]
		case .newInboxMessageToProcess(messageId: let messageId, attachmentIds: let attachmentIds, flowId: let flowId):
			info = [
				"messageId": messageId,
				"attachmentIds": attachmentIds,
				"flowId": flowId,
			]
		case .turnCredentialsReceived(ownedIdentity: let ownedIdentity, callUuid: let callUuid, turnCredentialsWithTurnServers: let turnCredentialsWithTurnServers, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"callUuid": callUuid,
				"turnCredentialsWithTurnServers": turnCredentialsWithTurnServers,
				"flowId": flowId,
			]
		case .turnCredentialsReceptionFailure(ownedIdentity: let ownedIdentity, callUuid: let callUuid, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"callUuid": callUuid,
				"flowId": flowId,
			]
		case .turnCredentialsReceptionPermissionDenied(ownedIdentity: let ownedIdentity, callUuid: let callUuid, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"callUuid": callUuid,
				"flowId": flowId,
			]
		case .turnCredentialServerDoesNotSupportCalls(ownedIdentity: let ownedIdentity, callUuid: let callUuid, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"callUuid": callUuid,
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
		case .newAPIKeyElementsForAPIKey(serverURL: let serverURL, apiKey: let apiKey, apiKeyStatus: let apiKeyStatus, apiPermissions: let apiPermissions, apiKeyExpirationDate: let apiKeyExpirationDate):
			info = [
				"serverURL": serverURL,
				"apiKey": apiKey,
				"apiKeyStatus": apiKeyStatus,
				"apiPermissions": apiPermissions,
				"apiKeyExpirationDate": OptionalWrapper(apiKeyExpirationDate),
			]
		case .newFreeTrialAPIKeyForOwnedIdentity(ownedIdentity: let ownedIdentity, apiKey: let apiKey, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"apiKey": apiKey,
				"flowId": flowId,
			]
		case .noMoreFreeTrialAPIKeyAvailableForOwnedIdentity(ownedIdentity: let ownedIdentity, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"flowId": flowId,
			]
		case .freeTrialIsStillAvailableForOwnedIdentity(ownedIdentity: let ownedIdentity, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"flowId": flowId,
			]
		case .appStoreReceiptVerificationFailed(ownedIdentity: let ownedIdentity, transactionIdentifier: let transactionIdentifier, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"transactionIdentifier": transactionIdentifier,
				"flowId": flowId,
			]
		case .appStoreReceiptVerificationSucceededAndSubscriptionIsValid(ownedIdentity: let ownedIdentity, transactionIdentifier: let transactionIdentifier, apiKey: let apiKey, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"transactionIdentifier": transactionIdentifier,
				"apiKey": apiKey,
				"flowId": flowId,
			]
		case .appStoreReceiptVerificationSucceededButSubscriptionIsExpired(ownedIdentity: let ownedIdentity, transactionIdentifier: let transactionIdentifier, flowId: let flowId):
			info = [
				"ownedIdentity": ownedIdentity,
				"transactionIdentifier": transactionIdentifier,
				"flowId": flowId,
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
		case .apiKeyStatusQueryFailed(ownedIdentity: let ownedIdentity, apiKey: let apiKey):
			info = [
				"ownedIdentity": ownedIdentity,
				"apiKey": apiKey,
			]
		case .applicationMessageDecrypted(messageId: let messageId, attachmentIds: let attachmentIds, hasEncryptedExtendedMessagePayload: let hasEncryptedExtendedMessagePayload, flowId: let flowId):
			info = [
				"messageId": messageId,
				"attachmentIds": attachmentIds,
				"hasEncryptedExtendedMessagePayload": hasEncryptedExtendedMessagePayload,
				"flowId": flowId,
			]
		case .downloadingMessageExtendedPayloadWasPerformed(messageId: let messageId, flowId: let flowId):
			info = [
				"messageId": messageId,
				"flowId": flowId,
			]
		case .downloadingMessageExtendedPayloadFailed(messageId: let messageId, flowId: let flowId):
			info = [
				"messageId": messageId,
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

	public static func observeServerReportedThatAnotherDeviceIsAlreadyRegistered(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.serverReportedThatAnotherDeviceIsAlreadyRegistered.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, flowId)
		}
	}

	public static func observeServerReportedThatThisDeviceWasSuccessfullyRegistered(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.serverReportedThatThisDeviceWasSuccessfullyRegistered.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, flowId)
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

	public static func observeInboxAttachmentWasDownloaded(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (AttachmentIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.inboxAttachmentWasDownloaded.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let attachmentId = notification.userInfo!["attachmentId"] as! AttachmentIdentifier
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(attachmentId, flowId)
		}
	}

	public static func observeInboxAttachmentDownloadCancelledByServer(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (AttachmentIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.inboxAttachmentDownloadCancelledByServer.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let attachmentId = notification.userInfo!["attachmentId"] as! AttachmentIdentifier
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(attachmentId, flowId)
		}
	}

	public static func observeInboxAttachmentDownloadWasResumed(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (AttachmentIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.inboxAttachmentDownloadWasResumed.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let attachmentId = notification.userInfo!["attachmentId"] as! AttachmentIdentifier
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(attachmentId, flowId)
		}
	}

	public static func observeInboxAttachmentDownloadWasPaused(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (AttachmentIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.inboxAttachmentDownloadWasPaused.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let attachmentId = notification.userInfo!["attachmentId"] as! AttachmentIdentifier
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(attachmentId, flowId)
		}
	}

	public static func observeInboxAttachmentWasTakenCareOf(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (AttachmentIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.inboxAttachmentWasTakenCareOf.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let attachmentId = notification.userInfo!["attachmentId"] as! AttachmentIdentifier
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(attachmentId, flowId)
		}
	}

	public static func observeNoInboxMessageToProcess(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (FlowIdentifier, ObvCryptoIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.noInboxMessageToProcess.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			let ownedCryptoIdentity = notification.userInfo!["ownedCryptoIdentity"] as! ObvCryptoIdentity
			block(flowId, ownedCryptoIdentity)
		}
	}

	public static func observeNewInboxMessageToProcess(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (MessageIdentifier, [AttachmentIdentifier], FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.newInboxMessageToProcess.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let messageId = notification.userInfo!["messageId"] as! MessageIdentifier
			let attachmentIds = notification.userInfo!["attachmentIds"] as! [AttachmentIdentifier]
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(messageId, attachmentIds, flowId)
		}
	}

	public static func observeTurnCredentialsReceived(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, UUID, TurnCredentialsWithTurnServers, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.turnCredentialsReceived.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let callUuid = notification.userInfo!["callUuid"] as! UUID
			let turnCredentialsWithTurnServers = notification.userInfo!["turnCredentialsWithTurnServers"] as! TurnCredentialsWithTurnServers
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, callUuid, turnCredentialsWithTurnServers, flowId)
		}
	}

	public static func observeTurnCredentialsReceptionFailure(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, UUID, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.turnCredentialsReceptionFailure.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let callUuid = notification.userInfo!["callUuid"] as! UUID
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, callUuid, flowId)
		}
	}

	public static func observeTurnCredentialsReceptionPermissionDenied(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, UUID, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.turnCredentialsReceptionPermissionDenied.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let callUuid = notification.userInfo!["callUuid"] as! UUID
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, callUuid, flowId)
		}
	}

	public static func observeTurnCredentialServerDoesNotSupportCalls(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, UUID, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.turnCredentialServerDoesNotSupportCalls.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let callUuid = notification.userInfo!["callUuid"] as! UUID
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, callUuid, flowId)
		}
	}

	public static func observeCannotReturnAnyProgressForMessageAttachments(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (MessageIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.cannotReturnAnyProgressForMessageAttachments.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let messageId = notification.userInfo!["messageId"] as! MessageIdentifier
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

	public static func observeNewAPIKeyElementsForAPIKey(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (URL, UUID, APIKeyStatus, APIPermissions, Date?) -> Void) -> NSObjectProtocol {
		let name = Name.newAPIKeyElementsForAPIKey.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let serverURL = notification.userInfo!["serverURL"] as! URL
			let apiKey = notification.userInfo!["apiKey"] as! UUID
			let apiKeyStatus = notification.userInfo!["apiKeyStatus"] as! APIKeyStatus
			let apiPermissions = notification.userInfo!["apiPermissions"] as! APIPermissions
			let apiKeyExpirationDateWrapper = notification.userInfo!["apiKeyExpirationDate"] as! OptionalWrapper<Date>
			let apiKeyExpirationDate = apiKeyExpirationDateWrapper.value
			block(serverURL, apiKey, apiKeyStatus, apiPermissions, apiKeyExpirationDate)
		}
	}

	public static func observeNewFreeTrialAPIKeyForOwnedIdentity(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, UUID, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.newFreeTrialAPIKeyForOwnedIdentity.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let apiKey = notification.userInfo!["apiKey"] as! UUID
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, apiKey, flowId)
		}
	}

	public static func observeNoMoreFreeTrialAPIKeyAvailableForOwnedIdentity(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.noMoreFreeTrialAPIKeyAvailableForOwnedIdentity.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, flowId)
		}
	}

	public static func observeFreeTrialIsStillAvailableForOwnedIdentity(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.freeTrialIsStillAvailableForOwnedIdentity.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, flowId)
		}
	}

	public static func observeAppStoreReceiptVerificationFailed(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, String, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.appStoreReceiptVerificationFailed.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let transactionIdentifier = notification.userInfo!["transactionIdentifier"] as! String
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, transactionIdentifier, flowId)
		}
	}

	public static func observeAppStoreReceiptVerificationSucceededAndSubscriptionIsValid(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, String, UUID, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.appStoreReceiptVerificationSucceededAndSubscriptionIsValid.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let transactionIdentifier = notification.userInfo!["transactionIdentifier"] as! String
			let apiKey = notification.userInfo!["apiKey"] as! UUID
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, transactionIdentifier, apiKey, flowId)
		}
	}

	public static func observeAppStoreReceiptVerificationSucceededButSubscriptionIsExpired(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, String, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.appStoreReceiptVerificationSucceededButSubscriptionIsExpired.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let transactionIdentifier = notification.userInfo!["transactionIdentifier"] as! String
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(ownedIdentity, transactionIdentifier, flowId)
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

	public static func observeApiKeyStatusQueryFailed(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, UUID) -> Void) -> NSObjectProtocol {
		let name = Name.apiKeyStatusQueryFailed.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
			let apiKey = notification.userInfo!["apiKey"] as! UUID
			block(ownedIdentity, apiKey)
		}
	}

	public static func observeApplicationMessageDecrypted(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (MessageIdentifier, [AttachmentIdentifier], Bool, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.applicationMessageDecrypted.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let messageId = notification.userInfo!["messageId"] as! MessageIdentifier
			let attachmentIds = notification.userInfo!["attachmentIds"] as! [AttachmentIdentifier]
			let hasEncryptedExtendedMessagePayload = notification.userInfo!["hasEncryptedExtendedMessagePayload"] as! Bool
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(messageId, attachmentIds, hasEncryptedExtendedMessagePayload, flowId)
		}
	}

	public static func observeDownloadingMessageExtendedPayloadWasPerformed(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (MessageIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.downloadingMessageExtendedPayloadWasPerformed.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let messageId = notification.userInfo!["messageId"] as! MessageIdentifier
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(messageId, flowId)
		}
	}

	public static func observeDownloadingMessageExtendedPayloadFailed(within notificationDelegate: ObvNotificationDelegate, queue: OperationQueue? = nil, block: @escaping (MessageIdentifier, FlowIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.downloadingMessageExtendedPayloadFailed.name
		return notificationDelegate.addObserver(forName: name, queue: queue) { (notification) in
			let messageId = notification.userInfo!["messageId"] as! MessageIdentifier
			let flowId = notification.userInfo!["flowId"] as! FlowIdentifier
			block(messageId, flowId)
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

}
