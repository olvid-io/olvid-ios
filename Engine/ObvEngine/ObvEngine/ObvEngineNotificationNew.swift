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

public enum ObvEngineNotificationNew {
	case newBackupKeyGenerated(backupKeyString: String, obvBackupKeyInformation: ObvBackupKeyInformation)
	case ownedIdentityWasDeactivated(ownedIdentity: ObvCryptoId)
	case ownedIdentityWasReactivated(ownedIdentity: ObvCryptoId)
	case networkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ObvCryptoId)
	case serverRequiresThisDeviceToRegisterToPushNotifications(ownedIdentity: ObvCryptoId)
	case backupForUploadWasUploaded(backupRequestUuid: UUID, backupKeyUid: UID, version: Int)
	case backupForExportWasExported(backupRequestUuid: UUID, backupKeyUid: UID, version: Int)
	case outboxMessagesAndAllTheirAttachmentsWereAcknowledged(messageIdsAndTimestampsFromServer: [(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, timestampFromServer: Date)])
	case inboxAttachmentNewProgress(obvAttachment: ObvAttachment, newProgress: Progress)
	case callerTurnCredentialsReceived(ownedIdentity: ObvCryptoId, callUuid: UUID, turnCredentials: ObvTurnCredentials)
	case callerTurnCredentialsReceptionFailure(ownedIdentity: ObvCryptoId, callUuid: UUID)
	case callerTurnCredentialsReceptionPermissionDenied(ownedIdentity: ObvCryptoId, callUuid: UUID)
	case callerTurnCredentialsServerDoesNotSupportCalls(ownedIdentity: ObvCryptoId, callUuid: UUID)
	case messageWasAcknowledged(ownedIdentity: ObvCryptoId, messageIdentifierFromEngine: Data, timestampFromServer: Date, isAppMessageWithUserContent: Bool, isVoipMessage: Bool)
	case newMessageReceived(obvMessage: ObvMessage, completionHandler: (Set<ObvAttachment>) -> Void)
	case attachmentWasAcknowledgedByServer(messageIdentifierFromEngine: Data, attachmentNumber: Int)
	case attachmentUploadNewProgress(messageIdentifierFromEngine: Data, attachmentNumber: Int, newProgress: Progress)
	case attachmentDownloadCancelledByServer(obvAttachment: ObvAttachment)
	case cannotReturnAnyProgressForMessageAttachments(messageIdentifierFromEngine: Data)
	case attachmentDownloaded(obvAttachment: ObvAttachment)
	case newObvReturnReceiptToProcess(obvReturnReceipt: ObvReturnReceipt)
	case contactWasDeleted(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId)
	case newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(ownedIdentity: ObvCryptoId, apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: EngineOptionalWrapper<Date>)
	case newAPIKeyElementsForAPIKey(serverURL: URL, apiKey: UUID, apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: EngineOptionalWrapper<Date>)
	case noMoreFreeTrialAPIKeyAvailableForOwnedIdentity(ownedIdentity: ObvCryptoId)
	case freeTrialIsStillAvailableForOwnedIdentity(ownedIdentity: ObvCryptoId)
	case appStoreReceiptVerificationSucceededAndSubscriptionIsValid(ownedIdentity: ObvCryptoId, transactionIdentifier: String)
	case appStoreReceiptVerificationFailed(ownedIdentity: ObvCryptoId, transactionIdentifier: String)
	case appStoreReceiptVerificationSucceededButSubscriptionIsExpired(ownedIdentity: ObvCryptoId, transactionIdentifier: String)
	case newObliviousChannelWithContactDevice(obvContactDevice: ObvContactDevice)
	case latestPhotoOfContactGroupOwnedHasBeenUpdated(group: ObvContactGroup)
	case publishedPhotoOfContactGroupOwnedHasBeenUpdated(group: ObvContactGroup)
	case publishedPhotoOfContactGroupJoinedHasBeenUpdated(group: ObvContactGroup)
	case trustedPhotoOfContactGroupJoinedHasBeenUpdated(group: ObvContactGroup)
	case publishedPhotoOfOwnedIdentityHasBeenUpdated(ownedIdentity: ObvOwnedIdentity)
	case publishedPhotoOfContactIdentityHasBeenUpdated(contactIdentity: ObvContactIdentity)
	case trustedPhotoOfContactIdentityHasBeenUpdated(contactIdentity: ObvContactIdentity)
	case wellKnownDownloadedSuccess(serverURL: URL, appInfo: [String: AppInfo])
	case wellKnownDownloadedFailure(serverURL: URL)
	case wellKnownUpdatedSuccess(serverURL: URL, appInfo: [String: AppInfo])
	case apiKeyStatusQueryFailed(serverURL: URL, apiKey: UUID)
	case updatedContactIdentity(obvContactIdentity: ObvContactIdentity, trustedIdentityDetailsWereUpdated: Bool, publishedIdentityDetailsWereUpdated: Bool)
	case ownedIdentityUnbindingFromKeycloakPerformed(ownedIdentity: ObvCryptoId, result: Result<Void, Error>)
	case updatedSetOfContactsCertifiedByOwnKeycloak(ownedIdentity: ObvCryptoId, contactsCertifiedByOwnKeycloak: Set<ObvCryptoId>)
	case updatedOwnedIdentity(obvOwnedIdentity: ObvOwnedIdentity)
	case mutualScanContactAdded(obvContactIdentity: ObvContactIdentity, signature: Data)
	case messageExtendedPayloadAvailable(obvMessage: ObvMessage, extendedMessagePayload: Data)
	case contactIsActiveChangedWithinEngine(obvContactIdentity: ObvContactIdentity)
	case contactWasRevokedAsCompromisedWithinEngine(obvContactIdentity: ObvContactIdentity)
	case ContactObvCapabilitiesWereUpdated(contact: ObvContactIdentity)
	case OwnedIdentityCapabilitiesWereUpdated(ownedIdentity: ObvOwnedIdentity)
	case newUserDialogToPresent(obvDialog: ObvDialog)
	case aPersistedDialogWasDeleted(uuid: UUID)

	private enum Name {
		case newBackupKeyGenerated
		case ownedIdentityWasDeactivated
		case ownedIdentityWasReactivated
		case networkOperationFailedSinceOwnedIdentityIsNotActive
		case serverRequiresThisDeviceToRegisterToPushNotifications
		case backupForUploadWasUploaded
		case backupForExportWasExported
		case outboxMessagesAndAllTheirAttachmentsWereAcknowledged
		case inboxAttachmentNewProgress
		case callerTurnCredentialsReceived
		case callerTurnCredentialsReceptionFailure
		case callerTurnCredentialsReceptionPermissionDenied
		case callerTurnCredentialsServerDoesNotSupportCalls
		case messageWasAcknowledged
		case newMessageReceived
		case attachmentWasAcknowledgedByServer
		case attachmentUploadNewProgress
		case attachmentDownloadCancelledByServer
		case cannotReturnAnyProgressForMessageAttachments
		case attachmentDownloaded
		case newObvReturnReceiptToProcess
		case contactWasDeleted
		case newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity
		case newAPIKeyElementsForAPIKey
		case noMoreFreeTrialAPIKeyAvailableForOwnedIdentity
		case freeTrialIsStillAvailableForOwnedIdentity
		case appStoreReceiptVerificationSucceededAndSubscriptionIsValid
		case appStoreReceiptVerificationFailed
		case appStoreReceiptVerificationSucceededButSubscriptionIsExpired
		case newObliviousChannelWithContactDevice
		case latestPhotoOfContactGroupOwnedHasBeenUpdated
		case publishedPhotoOfContactGroupOwnedHasBeenUpdated
		case publishedPhotoOfContactGroupJoinedHasBeenUpdated
		case trustedPhotoOfContactGroupJoinedHasBeenUpdated
		case publishedPhotoOfOwnedIdentityHasBeenUpdated
		case publishedPhotoOfContactIdentityHasBeenUpdated
		case trustedPhotoOfContactIdentityHasBeenUpdated
		case wellKnownDownloadedSuccess
		case wellKnownDownloadedFailure
		case wellKnownUpdatedSuccess
		case apiKeyStatusQueryFailed
		case updatedContactIdentity
		case ownedIdentityUnbindingFromKeycloakPerformed
		case updatedSetOfContactsCertifiedByOwnKeycloak
		case updatedOwnedIdentity
		case mutualScanContactAdded
		case messageExtendedPayloadAvailable
		case contactIsActiveChangedWithinEngine
		case contactWasRevokedAsCompromisedWithinEngine
		case ContactObvCapabilitiesWereUpdated
		case OwnedIdentityCapabilitiesWereUpdated
		case newUserDialogToPresent
		case aPersistedDialogWasDeleted

		private var namePrefix: String { String(describing: ObvEngineNotificationNew.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: ObvEngineNotificationNew) -> NSNotification.Name {
			switch notification {
			case .newBackupKeyGenerated: return Name.newBackupKeyGenerated.name
			case .ownedIdentityWasDeactivated: return Name.ownedIdentityWasDeactivated.name
			case .ownedIdentityWasReactivated: return Name.ownedIdentityWasReactivated.name
			case .networkOperationFailedSinceOwnedIdentityIsNotActive: return Name.networkOperationFailedSinceOwnedIdentityIsNotActive.name
			case .serverRequiresThisDeviceToRegisterToPushNotifications: return Name.serverRequiresThisDeviceToRegisterToPushNotifications.name
			case .backupForUploadWasUploaded: return Name.backupForUploadWasUploaded.name
			case .backupForExportWasExported: return Name.backupForExportWasExported.name
			case .outboxMessagesAndAllTheirAttachmentsWereAcknowledged: return Name.outboxMessagesAndAllTheirAttachmentsWereAcknowledged.name
			case .inboxAttachmentNewProgress: return Name.inboxAttachmentNewProgress.name
			case .callerTurnCredentialsReceived: return Name.callerTurnCredentialsReceived.name
			case .callerTurnCredentialsReceptionFailure: return Name.callerTurnCredentialsReceptionFailure.name
			case .callerTurnCredentialsReceptionPermissionDenied: return Name.callerTurnCredentialsReceptionPermissionDenied.name
			case .callerTurnCredentialsServerDoesNotSupportCalls: return Name.callerTurnCredentialsServerDoesNotSupportCalls.name
			case .messageWasAcknowledged: return Name.messageWasAcknowledged.name
			case .newMessageReceived: return Name.newMessageReceived.name
			case .attachmentWasAcknowledgedByServer: return Name.attachmentWasAcknowledgedByServer.name
			case .attachmentUploadNewProgress: return Name.attachmentUploadNewProgress.name
			case .attachmentDownloadCancelledByServer: return Name.attachmentDownloadCancelledByServer.name
			case .cannotReturnAnyProgressForMessageAttachments: return Name.cannotReturnAnyProgressForMessageAttachments.name
			case .attachmentDownloaded: return Name.attachmentDownloaded.name
			case .newObvReturnReceiptToProcess: return Name.newObvReturnReceiptToProcess.name
			case .contactWasDeleted: return Name.contactWasDeleted.name
			case .newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity: return Name.newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity.name
			case .newAPIKeyElementsForAPIKey: return Name.newAPIKeyElementsForAPIKey.name
			case .noMoreFreeTrialAPIKeyAvailableForOwnedIdentity: return Name.noMoreFreeTrialAPIKeyAvailableForOwnedIdentity.name
			case .freeTrialIsStillAvailableForOwnedIdentity: return Name.freeTrialIsStillAvailableForOwnedIdentity.name
			case .appStoreReceiptVerificationSucceededAndSubscriptionIsValid: return Name.appStoreReceiptVerificationSucceededAndSubscriptionIsValid.name
			case .appStoreReceiptVerificationFailed: return Name.appStoreReceiptVerificationFailed.name
			case .appStoreReceiptVerificationSucceededButSubscriptionIsExpired: return Name.appStoreReceiptVerificationSucceededButSubscriptionIsExpired.name
			case .newObliviousChannelWithContactDevice: return Name.newObliviousChannelWithContactDevice.name
			case .latestPhotoOfContactGroupOwnedHasBeenUpdated: return Name.latestPhotoOfContactGroupOwnedHasBeenUpdated.name
			case .publishedPhotoOfContactGroupOwnedHasBeenUpdated: return Name.publishedPhotoOfContactGroupOwnedHasBeenUpdated.name
			case .publishedPhotoOfContactGroupJoinedHasBeenUpdated: return Name.publishedPhotoOfContactGroupJoinedHasBeenUpdated.name
			case .trustedPhotoOfContactGroupJoinedHasBeenUpdated: return Name.trustedPhotoOfContactGroupJoinedHasBeenUpdated.name
			case .publishedPhotoOfOwnedIdentityHasBeenUpdated: return Name.publishedPhotoOfOwnedIdentityHasBeenUpdated.name
			case .publishedPhotoOfContactIdentityHasBeenUpdated: return Name.publishedPhotoOfContactIdentityHasBeenUpdated.name
			case .trustedPhotoOfContactIdentityHasBeenUpdated: return Name.trustedPhotoOfContactIdentityHasBeenUpdated.name
			case .wellKnownDownloadedSuccess: return Name.wellKnownDownloadedSuccess.name
			case .wellKnownDownloadedFailure: return Name.wellKnownDownloadedFailure.name
			case .wellKnownUpdatedSuccess: return Name.wellKnownUpdatedSuccess.name
			case .apiKeyStatusQueryFailed: return Name.apiKeyStatusQueryFailed.name
			case .updatedContactIdentity: return Name.updatedContactIdentity.name
			case .ownedIdentityUnbindingFromKeycloakPerformed: return Name.ownedIdentityUnbindingFromKeycloakPerformed.name
			case .updatedSetOfContactsCertifiedByOwnKeycloak: return Name.updatedSetOfContactsCertifiedByOwnKeycloak.name
			case .updatedOwnedIdentity: return Name.updatedOwnedIdentity.name
			case .mutualScanContactAdded: return Name.mutualScanContactAdded.name
			case .messageExtendedPayloadAvailable: return Name.messageExtendedPayloadAvailable.name
			case .contactIsActiveChangedWithinEngine: return Name.contactIsActiveChangedWithinEngine.name
			case .contactWasRevokedAsCompromisedWithinEngine: return Name.contactWasRevokedAsCompromisedWithinEngine.name
			case .ContactObvCapabilitiesWereUpdated: return Name.ContactObvCapabilitiesWereUpdated.name
			case .OwnedIdentityCapabilitiesWereUpdated: return Name.OwnedIdentityCapabilitiesWereUpdated.name
			case .newUserDialogToPresent: return Name.newUserDialogToPresent.name
			case .aPersistedDialogWasDeleted: return Name.aPersistedDialogWasDeleted.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .newBackupKeyGenerated(backupKeyString: let backupKeyString, obvBackupKeyInformation: let obvBackupKeyInformation):
			info = [
				"backupKeyString": backupKeyString,
				"obvBackupKeyInformation": obvBackupKeyInformation,
			]
		case .ownedIdentityWasDeactivated(ownedIdentity: let ownedIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
			]
		case .ownedIdentityWasReactivated(ownedIdentity: let ownedIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
			]
		case .networkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: let ownedIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
			]
		case .serverRequiresThisDeviceToRegisterToPushNotifications(ownedIdentity: let ownedIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
			]
		case .backupForUploadWasUploaded(backupRequestUuid: let backupRequestUuid, backupKeyUid: let backupKeyUid, version: let version):
			info = [
				"backupRequestUuid": backupRequestUuid,
				"backupKeyUid": backupKeyUid,
				"version": version,
			]
		case .backupForExportWasExported(backupRequestUuid: let backupRequestUuid, backupKeyUid: let backupKeyUid, version: let version):
			info = [
				"backupRequestUuid": backupRequestUuid,
				"backupKeyUid": backupKeyUid,
				"version": version,
			]
		case .outboxMessagesAndAllTheirAttachmentsWereAcknowledged(messageIdsAndTimestampsFromServer: let messageIdsAndTimestampsFromServer):
			info = [
				"messageIdsAndTimestampsFromServer": messageIdsAndTimestampsFromServer,
			]
		case .inboxAttachmentNewProgress(obvAttachment: let obvAttachment, newProgress: let newProgress):
			info = [
				"obvAttachment": obvAttachment,
				"newProgress": newProgress,
			]
		case .callerTurnCredentialsReceived(ownedIdentity: let ownedIdentity, callUuid: let callUuid, turnCredentials: let turnCredentials):
			info = [
				"ownedIdentity": ownedIdentity,
				"callUuid": callUuid,
				"turnCredentials": turnCredentials,
			]
		case .callerTurnCredentialsReceptionFailure(ownedIdentity: let ownedIdentity, callUuid: let callUuid):
			info = [
				"ownedIdentity": ownedIdentity,
				"callUuid": callUuid,
			]
		case .callerTurnCredentialsReceptionPermissionDenied(ownedIdentity: let ownedIdentity, callUuid: let callUuid):
			info = [
				"ownedIdentity": ownedIdentity,
				"callUuid": callUuid,
			]
		case .callerTurnCredentialsServerDoesNotSupportCalls(ownedIdentity: let ownedIdentity, callUuid: let callUuid):
			info = [
				"ownedIdentity": ownedIdentity,
				"callUuid": callUuid,
			]
		case .messageWasAcknowledged(ownedIdentity: let ownedIdentity, messageIdentifierFromEngine: let messageIdentifierFromEngine, timestampFromServer: let timestampFromServer, isAppMessageWithUserContent: let isAppMessageWithUserContent, isVoipMessage: let isVoipMessage):
			info = [
				"ownedIdentity": ownedIdentity,
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
				"timestampFromServer": timestampFromServer,
				"isAppMessageWithUserContent": isAppMessageWithUserContent,
				"isVoipMessage": isVoipMessage,
			]
		case .newMessageReceived(obvMessage: let obvMessage, completionHandler: let completionHandler):
			info = [
				"obvMessage": obvMessage,
				"completionHandler": completionHandler,
			]
		case .attachmentWasAcknowledgedByServer(messageIdentifierFromEngine: let messageIdentifierFromEngine, attachmentNumber: let attachmentNumber):
			info = [
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
				"attachmentNumber": attachmentNumber,
			]
		case .attachmentUploadNewProgress(messageIdentifierFromEngine: let messageIdentifierFromEngine, attachmentNumber: let attachmentNumber, newProgress: let newProgress):
			info = [
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
				"attachmentNumber": attachmentNumber,
				"newProgress": newProgress,
			]
		case .attachmentDownloadCancelledByServer(obvAttachment: let obvAttachment):
			info = [
				"obvAttachment": obvAttachment,
			]
		case .cannotReturnAnyProgressForMessageAttachments(messageIdentifierFromEngine: let messageIdentifierFromEngine):
			info = [
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
			]
		case .attachmentDownloaded(obvAttachment: let obvAttachment):
			info = [
				"obvAttachment": obvAttachment,
			]
		case .newObvReturnReceiptToProcess(obvReturnReceipt: let obvReturnReceipt):
			info = [
				"obvReturnReceipt": obvReturnReceipt,
			]
		case .contactWasDeleted(ownedCryptoId: let ownedCryptoId, contactCryptoId: let contactCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"contactCryptoId": contactCryptoId,
			]
		case .newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(ownedIdentity: let ownedIdentity, apiKeyStatus: let apiKeyStatus, apiPermissions: let apiPermissions, apiKeyExpirationDate: let apiKeyExpirationDate):
			info = [
				"ownedIdentity": ownedIdentity,
				"apiKeyStatus": apiKeyStatus,
				"apiPermissions": apiPermissions,
				"apiKeyExpirationDate": apiKeyExpirationDate,
			]
		case .newAPIKeyElementsForAPIKey(serverURL: let serverURL, apiKey: let apiKey, apiKeyStatus: let apiKeyStatus, apiPermissions: let apiPermissions, apiKeyExpirationDate: let apiKeyExpirationDate):
			info = [
				"serverURL": serverURL,
				"apiKey": apiKey,
				"apiKeyStatus": apiKeyStatus,
				"apiPermissions": apiPermissions,
				"apiKeyExpirationDate": apiKeyExpirationDate,
			]
		case .noMoreFreeTrialAPIKeyAvailableForOwnedIdentity(ownedIdentity: let ownedIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
			]
		case .freeTrialIsStillAvailableForOwnedIdentity(ownedIdentity: let ownedIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
			]
		case .appStoreReceiptVerificationSucceededAndSubscriptionIsValid(ownedIdentity: let ownedIdentity, transactionIdentifier: let transactionIdentifier):
			info = [
				"ownedIdentity": ownedIdentity,
				"transactionIdentifier": transactionIdentifier,
			]
		case .appStoreReceiptVerificationFailed(ownedIdentity: let ownedIdentity, transactionIdentifier: let transactionIdentifier):
			info = [
				"ownedIdentity": ownedIdentity,
				"transactionIdentifier": transactionIdentifier,
			]
		case .appStoreReceiptVerificationSucceededButSubscriptionIsExpired(ownedIdentity: let ownedIdentity, transactionIdentifier: let transactionIdentifier):
			info = [
				"ownedIdentity": ownedIdentity,
				"transactionIdentifier": transactionIdentifier,
			]
		case .newObliviousChannelWithContactDevice(obvContactDevice: let obvContactDevice):
			info = [
				"obvContactDevice": obvContactDevice,
			]
		case .latestPhotoOfContactGroupOwnedHasBeenUpdated(group: let group):
			info = [
				"group": group,
			]
		case .publishedPhotoOfContactGroupOwnedHasBeenUpdated(group: let group):
			info = [
				"group": group,
			]
		case .publishedPhotoOfContactGroupJoinedHasBeenUpdated(group: let group):
			info = [
				"group": group,
			]
		case .trustedPhotoOfContactGroupJoinedHasBeenUpdated(group: let group):
			info = [
				"group": group,
			]
		case .publishedPhotoOfOwnedIdentityHasBeenUpdated(ownedIdentity: let ownedIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
			]
		case .publishedPhotoOfContactIdentityHasBeenUpdated(contactIdentity: let contactIdentity):
			info = [
				"contactIdentity": contactIdentity,
			]
		case .trustedPhotoOfContactIdentityHasBeenUpdated(contactIdentity: let contactIdentity):
			info = [
				"contactIdentity": contactIdentity,
			]
		case .wellKnownDownloadedSuccess(serverURL: let serverURL, appInfo: let appInfo):
			info = [
				"serverURL": serverURL,
				"appInfo": appInfo,
			]
		case .wellKnownDownloadedFailure(serverURL: let serverURL):
			info = [
				"serverURL": serverURL,
			]
		case .wellKnownUpdatedSuccess(serverURL: let serverURL, appInfo: let appInfo):
			info = [
				"serverURL": serverURL,
				"appInfo": appInfo,
			]
		case .apiKeyStatusQueryFailed(serverURL: let serverURL, apiKey: let apiKey):
			info = [
				"serverURL": serverURL,
				"apiKey": apiKey,
			]
		case .updatedContactIdentity(obvContactIdentity: let obvContactIdentity, trustedIdentityDetailsWereUpdated: let trustedIdentityDetailsWereUpdated, publishedIdentityDetailsWereUpdated: let publishedIdentityDetailsWereUpdated):
			info = [
				"obvContactIdentity": obvContactIdentity,
				"trustedIdentityDetailsWereUpdated": trustedIdentityDetailsWereUpdated,
				"publishedIdentityDetailsWereUpdated": publishedIdentityDetailsWereUpdated,
			]
		case .ownedIdentityUnbindingFromKeycloakPerformed(ownedIdentity: let ownedIdentity, result: let result):
			info = [
				"ownedIdentity": ownedIdentity,
				"result": result,
			]
		case .updatedSetOfContactsCertifiedByOwnKeycloak(ownedIdentity: let ownedIdentity, contactsCertifiedByOwnKeycloak: let contactsCertifiedByOwnKeycloak):
			info = [
				"ownedIdentity": ownedIdentity,
				"contactsCertifiedByOwnKeycloak": contactsCertifiedByOwnKeycloak,
			]
		case .updatedOwnedIdentity(obvOwnedIdentity: let obvOwnedIdentity):
			info = [
				"obvOwnedIdentity": obvOwnedIdentity,
			]
		case .mutualScanContactAdded(obvContactIdentity: let obvContactIdentity, signature: let signature):
			info = [
				"obvContactIdentity": obvContactIdentity,
				"signature": signature,
			]
		case .messageExtendedPayloadAvailable(obvMessage: let obvMessage, extendedMessagePayload: let extendedMessagePayload):
			info = [
				"obvMessage": obvMessage,
				"extendedMessagePayload": extendedMessagePayload,
			]
		case .contactIsActiveChangedWithinEngine(obvContactIdentity: let obvContactIdentity):
			info = [
				"obvContactIdentity": obvContactIdentity,
			]
		case .contactWasRevokedAsCompromisedWithinEngine(obvContactIdentity: let obvContactIdentity):
			info = [
				"obvContactIdentity": obvContactIdentity,
			]
		case .ContactObvCapabilitiesWereUpdated(contact: let contact):
			info = [
				"contact": contact,
			]
		case .OwnedIdentityCapabilitiesWereUpdated(ownedIdentity: let ownedIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
			]
		case .newUserDialogToPresent(obvDialog: let obvDialog):
			info = [
				"obvDialog": obvDialog,
			]
		case .aPersistedDialogWasDeleted(uuid: let uuid):
			info = [
				"uuid": uuid,
			]
		}
		return info
	}

	public func postOnBackgroundQueue(_ queue: DispatchQueue? = nil, within appNotificationCenter: NotificationCenter) {
		let name = Name.forInternalNotification(self)
		let label = "Queue for posting \(name.rawValue) notification"
		let backgroundQueue = queue ?? DispatchQueue(label: label)
		backgroundQueue.async {
			appNotificationCenter.post(name: name, object: nil, userInfo: userInfo)
		}
	}

	public static func observeNewBackupKeyGenerated(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (String, ObvBackupKeyInformation) -> Void) -> NSObjectProtocol {
		let name = Name.newBackupKeyGenerated.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let backupKeyString = notification.userInfo!["backupKeyString"] as! String
			let obvBackupKeyInformation = notification.userInfo!["obvBackupKeyInformation"] as! ObvBackupKeyInformation
			block(backupKeyString, obvBackupKeyInformation)
		}
	}

	public static func observeOwnedIdentityWasDeactivated(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityWasDeactivated.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			block(ownedIdentity)
		}
	}

	public static func observeOwnedIdentityWasReactivated(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityWasReactivated.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			block(ownedIdentity)
		}
	}

	public static func observeNetworkOperationFailedSinceOwnedIdentityIsNotActive(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.networkOperationFailedSinceOwnedIdentityIsNotActive.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			block(ownedIdentity)
		}
	}

	public static func observeServerRequiresThisDeviceToRegisterToPushNotifications(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.serverRequiresThisDeviceToRegisterToPushNotifications.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			block(ownedIdentity)
		}
	}

	public static func observeBackupForUploadWasUploaded(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (UUID, UID, Int) -> Void) -> NSObjectProtocol {
		let name = Name.backupForUploadWasUploaded.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let backupRequestUuid = notification.userInfo!["backupRequestUuid"] as! UUID
			let backupKeyUid = notification.userInfo!["backupKeyUid"] as! UID
			let version = notification.userInfo!["version"] as! Int
			block(backupRequestUuid, backupKeyUid, version)
		}
	}

	public static func observeBackupForExportWasExported(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (UUID, UID, Int) -> Void) -> NSObjectProtocol {
		let name = Name.backupForExportWasExported.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let backupRequestUuid = notification.userInfo!["backupRequestUuid"] as! UUID
			let backupKeyUid = notification.userInfo!["backupKeyUid"] as! UID
			let version = notification.userInfo!["version"] as! Int
			block(backupRequestUuid, backupKeyUid, version)
		}
	}

	public static func observeOutboxMessagesAndAllTheirAttachmentsWereAcknowledged(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping ([(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, timestampFromServer: Date)]) -> Void) -> NSObjectProtocol {
		let name = Name.outboxMessagesAndAllTheirAttachmentsWereAcknowledged.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let messageIdsAndTimestampsFromServer = notification.userInfo!["messageIdsAndTimestampsFromServer"] as! [(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, timestampFromServer: Date)]
			block(messageIdsAndTimestampsFromServer)
		}
	}

	public static func observeInboxAttachmentNewProgress(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvAttachment, Progress) -> Void) -> NSObjectProtocol {
		let name = Name.inboxAttachmentNewProgress.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvAttachment = notification.userInfo!["obvAttachment"] as! ObvAttachment
			let newProgress = notification.userInfo!["newProgress"] as! Progress
			block(obvAttachment, newProgress)
		}
	}

	public static func observeCallerTurnCredentialsReceived(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, UUID, ObvTurnCredentials) -> Void) -> NSObjectProtocol {
		let name = Name.callerTurnCredentialsReceived.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			let callUuid = notification.userInfo!["callUuid"] as! UUID
			let turnCredentials = notification.userInfo!["turnCredentials"] as! ObvTurnCredentials
			block(ownedIdentity, callUuid, turnCredentials)
		}
	}

	public static func observeCallerTurnCredentialsReceptionFailure(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, UUID) -> Void) -> NSObjectProtocol {
		let name = Name.callerTurnCredentialsReceptionFailure.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			let callUuid = notification.userInfo!["callUuid"] as! UUID
			block(ownedIdentity, callUuid)
		}
	}

	public static func observeCallerTurnCredentialsReceptionPermissionDenied(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, UUID) -> Void) -> NSObjectProtocol {
		let name = Name.callerTurnCredentialsReceptionPermissionDenied.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			let callUuid = notification.userInfo!["callUuid"] as! UUID
			block(ownedIdentity, callUuid)
		}
	}

	public static func observeCallerTurnCredentialsServerDoesNotSupportCalls(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, UUID) -> Void) -> NSObjectProtocol {
		let name = Name.callerTurnCredentialsServerDoesNotSupportCalls.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			let callUuid = notification.userInfo!["callUuid"] as! UUID
			block(ownedIdentity, callUuid)
		}
	}

	public static func observeMessageWasAcknowledged(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Data, Date, Bool, Bool) -> Void) -> NSObjectProtocol {
		let name = Name.messageWasAcknowledged.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			let timestampFromServer = notification.userInfo!["timestampFromServer"] as! Date
			let isAppMessageWithUserContent = notification.userInfo!["isAppMessageWithUserContent"] as! Bool
			let isVoipMessage = notification.userInfo!["isVoipMessage"] as! Bool
			block(ownedIdentity, messageIdentifierFromEngine, timestampFromServer, isAppMessageWithUserContent, isVoipMessage)
		}
	}

	public static func observeNewMessageReceived(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvMessage, @escaping (Set<ObvAttachment>) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.newMessageReceived.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvMessage = notification.userInfo!["obvMessage"] as! ObvMessage
			let completionHandler = notification.userInfo!["completionHandler"] as! (Set<ObvAttachment>) -> Void
			block(obvMessage, completionHandler)
		}
	}

	public static func observeAttachmentWasAcknowledgedByServer(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (Data, Int) -> Void) -> NSObjectProtocol {
		let name = Name.attachmentWasAcknowledgedByServer.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			let attachmentNumber = notification.userInfo!["attachmentNumber"] as! Int
			block(messageIdentifierFromEngine, attachmentNumber)
		}
	}

	public static func observeAttachmentUploadNewProgress(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (Data, Int, Progress) -> Void) -> NSObjectProtocol {
		let name = Name.attachmentUploadNewProgress.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			let attachmentNumber = notification.userInfo!["attachmentNumber"] as! Int
			let newProgress = notification.userInfo!["newProgress"] as! Progress
			block(messageIdentifierFromEngine, attachmentNumber, newProgress)
		}
	}

	public static func observeAttachmentDownloadCancelledByServer(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvAttachment) -> Void) -> NSObjectProtocol {
		let name = Name.attachmentDownloadCancelledByServer.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvAttachment = notification.userInfo!["obvAttachment"] as! ObvAttachment
			block(obvAttachment)
		}
	}

	public static func observeCannotReturnAnyProgressForMessageAttachments(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (Data) -> Void) -> NSObjectProtocol {
		let name = Name.cannotReturnAnyProgressForMessageAttachments.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			block(messageIdentifierFromEngine)
		}
	}

	public static func observeAttachmentDownloaded(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvAttachment) -> Void) -> NSObjectProtocol {
		let name = Name.attachmentDownloaded.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvAttachment = notification.userInfo!["obvAttachment"] as! ObvAttachment
			block(obvAttachment)
		}
	}

	public static func observeNewObvReturnReceiptToProcess(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvReturnReceipt) -> Void) -> NSObjectProtocol {
		let name = Name.newObvReturnReceiptToProcess.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvReturnReceipt = notification.userInfo!["obvReturnReceipt"] as! ObvReturnReceipt
			block(obvReturnReceipt)
		}
	}

	public static func observeContactWasDeleted(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.contactWasDeleted.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			block(ownedCryptoId, contactCryptoId)
		}
	}

	public static func observeNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, APIKeyStatus, APIPermissions, EngineOptionalWrapper<Date>) -> Void) -> NSObjectProtocol {
		let name = Name.newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			let apiKeyStatus = notification.userInfo!["apiKeyStatus"] as! APIKeyStatus
			let apiPermissions = notification.userInfo!["apiPermissions"] as! APIPermissions
			let apiKeyExpirationDate = notification.userInfo!["apiKeyExpirationDate"] as! EngineOptionalWrapper<Date>
			block(ownedIdentity, apiKeyStatus, apiPermissions, apiKeyExpirationDate)
		}
	}

	public static func observeNewAPIKeyElementsForAPIKey(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (URL, UUID, APIKeyStatus, APIPermissions, EngineOptionalWrapper<Date>) -> Void) -> NSObjectProtocol {
		let name = Name.newAPIKeyElementsForAPIKey.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let serverURL = notification.userInfo!["serverURL"] as! URL
			let apiKey = notification.userInfo!["apiKey"] as! UUID
			let apiKeyStatus = notification.userInfo!["apiKeyStatus"] as! APIKeyStatus
			let apiPermissions = notification.userInfo!["apiPermissions"] as! APIPermissions
			let apiKeyExpirationDate = notification.userInfo!["apiKeyExpirationDate"] as! EngineOptionalWrapper<Date>
			block(serverURL, apiKey, apiKeyStatus, apiPermissions, apiKeyExpirationDate)
		}
	}

	public static func observeNoMoreFreeTrialAPIKeyAvailableForOwnedIdentity(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.noMoreFreeTrialAPIKeyAvailableForOwnedIdentity.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			block(ownedIdentity)
		}
	}

	public static func observeFreeTrialIsStillAvailableForOwnedIdentity(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.freeTrialIsStillAvailableForOwnedIdentity.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			block(ownedIdentity)
		}
	}

	public static func observeAppStoreReceiptVerificationSucceededAndSubscriptionIsValid(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, String) -> Void) -> NSObjectProtocol {
		let name = Name.appStoreReceiptVerificationSucceededAndSubscriptionIsValid.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			let transactionIdentifier = notification.userInfo!["transactionIdentifier"] as! String
			block(ownedIdentity, transactionIdentifier)
		}
	}

	public static func observeAppStoreReceiptVerificationFailed(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, String) -> Void) -> NSObjectProtocol {
		let name = Name.appStoreReceiptVerificationFailed.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			let transactionIdentifier = notification.userInfo!["transactionIdentifier"] as! String
			block(ownedIdentity, transactionIdentifier)
		}
	}

	public static func observeAppStoreReceiptVerificationSucceededButSubscriptionIsExpired(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, String) -> Void) -> NSObjectProtocol {
		let name = Name.appStoreReceiptVerificationSucceededButSubscriptionIsExpired.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			let transactionIdentifier = notification.userInfo!["transactionIdentifier"] as! String
			block(ownedIdentity, transactionIdentifier)
		}
	}

	public static func observeNewObliviousChannelWithContactDevice(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactDevice) -> Void) -> NSObjectProtocol {
		let name = Name.newObliviousChannelWithContactDevice.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvContactDevice = notification.userInfo!["obvContactDevice"] as! ObvContactDevice
			block(obvContactDevice)
		}
	}

	public static func observeLatestPhotoOfContactGroupOwnedHasBeenUpdated(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactGroup) -> Void) -> NSObjectProtocol {
		let name = Name.latestPhotoOfContactGroupOwnedHasBeenUpdated.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let group = notification.userInfo!["group"] as! ObvContactGroup
			block(group)
		}
	}

	public static func observePublishedPhotoOfContactGroupOwnedHasBeenUpdated(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactGroup) -> Void) -> NSObjectProtocol {
		let name = Name.publishedPhotoOfContactGroupOwnedHasBeenUpdated.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let group = notification.userInfo!["group"] as! ObvContactGroup
			block(group)
		}
	}

	public static func observePublishedPhotoOfContactGroupJoinedHasBeenUpdated(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactGroup) -> Void) -> NSObjectProtocol {
		let name = Name.publishedPhotoOfContactGroupJoinedHasBeenUpdated.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let group = notification.userInfo!["group"] as! ObvContactGroup
			block(group)
		}
	}

	public static func observeTrustedPhotoOfContactGroupJoinedHasBeenUpdated(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactGroup) -> Void) -> NSObjectProtocol {
		let name = Name.trustedPhotoOfContactGroupJoinedHasBeenUpdated.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let group = notification.userInfo!["group"] as! ObvContactGroup
			block(group)
		}
	}

	public static func observePublishedPhotoOfOwnedIdentityHasBeenUpdated(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvOwnedIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.publishedPhotoOfOwnedIdentityHasBeenUpdated.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvOwnedIdentity
			block(ownedIdentity)
		}
	}

	public static func observePublishedPhotoOfContactIdentityHasBeenUpdated(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.publishedPhotoOfContactIdentityHasBeenUpdated.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let contactIdentity = notification.userInfo!["contactIdentity"] as! ObvContactIdentity
			block(contactIdentity)
		}
	}

	public static func observeTrustedPhotoOfContactIdentityHasBeenUpdated(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.trustedPhotoOfContactIdentityHasBeenUpdated.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let contactIdentity = notification.userInfo!["contactIdentity"] as! ObvContactIdentity
			block(contactIdentity)
		}
	}

	public static func observeWellKnownDownloadedSuccess(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (URL, [String: AppInfo]) -> Void) -> NSObjectProtocol {
		let name = Name.wellKnownDownloadedSuccess.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let serverURL = notification.userInfo!["serverURL"] as! URL
			let appInfo = notification.userInfo!["appInfo"] as! [String: AppInfo]
			block(serverURL, appInfo)
		}
	}

	public static func observeWellKnownDownloadedFailure(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (URL) -> Void) -> NSObjectProtocol {
		let name = Name.wellKnownDownloadedFailure.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let serverURL = notification.userInfo!["serverURL"] as! URL
			block(serverURL)
		}
	}

	public static func observeWellKnownUpdatedSuccess(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (URL, [String: AppInfo]) -> Void) -> NSObjectProtocol {
		let name = Name.wellKnownUpdatedSuccess.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let serverURL = notification.userInfo!["serverURL"] as! URL
			let appInfo = notification.userInfo!["appInfo"] as! [String: AppInfo]
			block(serverURL, appInfo)
		}
	}

	public static func observeApiKeyStatusQueryFailed(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (URL, UUID) -> Void) -> NSObjectProtocol {
		let name = Name.apiKeyStatusQueryFailed.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let serverURL = notification.userInfo!["serverURL"] as! URL
			let apiKey = notification.userInfo!["apiKey"] as! UUID
			block(serverURL, apiKey)
		}
	}

	public static func observeUpdatedContactIdentity(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactIdentity, Bool, Bool) -> Void) -> NSObjectProtocol {
		let name = Name.updatedContactIdentity.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvContactIdentity = notification.userInfo!["obvContactIdentity"] as! ObvContactIdentity
			let trustedIdentityDetailsWereUpdated = notification.userInfo!["trustedIdentityDetailsWereUpdated"] as! Bool
			let publishedIdentityDetailsWereUpdated = notification.userInfo!["publishedIdentityDetailsWereUpdated"] as! Bool
			block(obvContactIdentity, trustedIdentityDetailsWereUpdated, publishedIdentityDetailsWereUpdated)
		}
	}

	public static func observeOwnedIdentityUnbindingFromKeycloakPerformed(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Result<Void, Error>) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityUnbindingFromKeycloakPerformed.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			let result = notification.userInfo!["result"] as! Result<Void, Error>
			block(ownedIdentity, result)
		}
	}

	public static func observeUpdatedSetOfContactsCertifiedByOwnKeycloak(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Set<ObvCryptoId>) -> Void) -> NSObjectProtocol {
		let name = Name.updatedSetOfContactsCertifiedByOwnKeycloak.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			let contactsCertifiedByOwnKeycloak = notification.userInfo!["contactsCertifiedByOwnKeycloak"] as! Set<ObvCryptoId>
			block(ownedIdentity, contactsCertifiedByOwnKeycloak)
		}
	}

	public static func observeUpdatedOwnedIdentity(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvOwnedIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.updatedOwnedIdentity.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvOwnedIdentity = notification.userInfo!["obvOwnedIdentity"] as! ObvOwnedIdentity
			block(obvOwnedIdentity)
		}
	}

	public static func observeMutualScanContactAdded(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactIdentity, Data) -> Void) -> NSObjectProtocol {
		let name = Name.mutualScanContactAdded.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvContactIdentity = notification.userInfo!["obvContactIdentity"] as! ObvContactIdentity
			let signature = notification.userInfo!["signature"] as! Data
			block(obvContactIdentity, signature)
		}
	}

	public static func observeMessageExtendedPayloadAvailable(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvMessage, Data) -> Void) -> NSObjectProtocol {
		let name = Name.messageExtendedPayloadAvailable.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvMessage = notification.userInfo!["obvMessage"] as! ObvMessage
			let extendedMessagePayload = notification.userInfo!["extendedMessagePayload"] as! Data
			block(obvMessage, extendedMessagePayload)
		}
	}

	public static func observeContactIsActiveChangedWithinEngine(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.contactIsActiveChangedWithinEngine.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvContactIdentity = notification.userInfo!["obvContactIdentity"] as! ObvContactIdentity
			block(obvContactIdentity)
		}
	}

	public static func observeContactWasRevokedAsCompromisedWithinEngine(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.contactWasRevokedAsCompromisedWithinEngine.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvContactIdentity = notification.userInfo!["obvContactIdentity"] as! ObvContactIdentity
			block(obvContactIdentity)
		}
	}

	public static func observeContactObvCapabilitiesWereUpdated(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.ContactObvCapabilitiesWereUpdated.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let contact = notification.userInfo!["contact"] as! ObvContactIdentity
			block(contact)
		}
	}

	public static func observeOwnedIdentityCapabilitiesWereUpdated(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvOwnedIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.OwnedIdentityCapabilitiesWereUpdated.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvOwnedIdentity
			block(ownedIdentity)
		}
	}

	public static func observeNewUserDialogToPresent(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvDialog) -> Void) -> NSObjectProtocol {
		let name = Name.newUserDialogToPresent.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvDialog = notification.userInfo!["obvDialog"] as! ObvDialog
			block(obvDialog)
		}
	}

	public static func observeAPersistedDialogWasDeleted(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (UUID) -> Void) -> NSObjectProtocol {
		let name = Name.aPersistedDialogWasDeleted.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let uuid = notification.userInfo!["uuid"] as! UUID
			block(uuid)
		}
	}

}
