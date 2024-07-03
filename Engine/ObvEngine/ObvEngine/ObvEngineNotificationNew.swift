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
import ObvTypes
import OlvidUtils
import ObvCrypto

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
	case contactGroupHasUpdatedPendingMembersAndGroupMembers(obvContactGroup: ObvContactGroup)
	case newContactGroup(obvContactGroup: ObvContactGroup)
	case newPendingGroupMemberDeclinedStatus(obvContactGroup: ObvContactGroup)
	case contactGroupDeleted(ownedIdentity: ObvOwnedIdentity, groupOwner: ObvCryptoId, groupUid: UID)
	case contactGroupHasUpdatedPublishedDetails(obvContactGroup: ObvContactGroup)
	case contactGroupJoinedHasUpdatedTrustedDetails(obvContactGroup: ObvContactGroup)
	case contactGroupOwnedDiscardedLatestDetails(obvContactGroup: ObvContactGroup)
	case contactGroupOwnedHasUpdatedLatestDetails(obvContactGroup: ObvContactGroup)
	case deletedObliviousChannelWithContactDevice(obvContactIdentifier: ObvContactIdentifier)
	case newTrustedContactIdentity(obvContactIdentity: ObvContactIdentity)
	case newBackupKeyGenerated(backupKeyString: String, obvBackupKeyInformation: ObvBackupKeyInformation)
	case ownedIdentityWasDeactivated(ownedIdentity: ObvCryptoId)
	case ownedIdentityWasReactivated(ownedIdentity: ObvCryptoId)
	case networkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ObvCryptoId)
	case serverRequiresAllActiveOwnedIdentitiesToRegisterToPushNotifications
	case engineRequiresOwnedIdentityToRegisterToPushNotifications(ownedCryptoId: ObvCryptoId, performOwnedDeviceDiscoveryOnFinish: Bool)
	case outboxMessagesAndAllTheirAttachmentsWereAcknowledged(messageIdsAndTimestampsFromServer: [(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, timestampFromServer: Date)])
	case outboxMessageCouldNotBeSentToServer(messageIdentifierFromEngine: Data, ownedIdentity: ObvCryptoId)
	case callerTurnCredentialsReceived(ownedIdentity: ObvCryptoId, callUuid: UUID, turnCredentials: ObvTurnCredentials)
	case messageWasAcknowledged(ownedIdentity: ObvCryptoId, messageIdentifierFromEngine: Data, timestampFromServer: Date, isAppMessageWithUserContent: Bool, isVoipMessage: Bool)
	case newMessageReceived(obvMessage: ObvMessage)
	case attachmentWasAcknowledgedByServer(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int)
	case attachmentDownloadCancelledByServer(obvAttachment: ObvAttachment)
	case cannotReturnAnyProgressForMessageAttachments(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data)
	case attachmentDownloaded(obvAttachment: ObvAttachment)
	case attachmentDownloadWasResumed(ownCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int)
	case attachmentDownloadWasPaused(ownCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int)
	case newObvReturnReceiptToProcess(obvReturnReceipt: ObvReturnReceipt)
	case contactWasDeleted(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId)
	case newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(ownedIdentity: ObvCryptoId, apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?)
	case newObliviousChannelWithContactDevice(obvContactIdentifier: ObvContactIdentifier)
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
	case updatedContactIdentity(obvContactIdentity: ObvContactIdentity, trustedIdentityDetailsWereUpdated: Bool, publishedIdentityDetailsWereUpdated: Bool)
	case ownedIdentityUnbindingFromKeycloakPerformed(ownedIdentity: ObvCryptoId, result: Result<Void, Error>)
	case updatedOwnedIdentity(obvOwnedIdentity: ObvOwnedIdentity)
	case mutualScanContactAdded(obvContactIdentity: ObvContactIdentity, signature: Data)
	case contactMessageExtendedPayloadAvailable(obvMessage: ObvMessage)
	case ownedMessageExtendedPayloadAvailable(obvOwnedMessage: ObvOwnedMessage)
	case contactIsActiveChangedWithinEngine(obvContactIdentity: ObvContactIdentity)
	case contactWasRevokedAsCompromisedWithinEngine(obvContactIdentifier: ObvContactIdentifier)
	case ContactObvCapabilitiesWereUpdated(contact: ObvContactIdentity)
	case OwnedIdentityCapabilitiesWereUpdated(ownedIdentity: ObvOwnedIdentity)
	case newUserDialogToPresent(obvDialog: ObvDialog)
	case aPersistedDialogWasDeleted(ownedCryptoId: ObvCryptoId, uuid: UUID)
	case groupV2WasCreatedOrUpdated(obvGroupV2: ObvGroupV2, initiator: ObvGroupV2.CreationOrUpdateInitiator)
	case groupV2WasDeleted(ownedIdentity: ObvCryptoId, appGroupIdentifier: Data)
	case groupV2UpdateDidFail(ownedIdentity: ObvCryptoId, appGroupIdentifier: Data)
	case aPushTopicWasReceivedViaWebsocket(pushTopic: String)
	case ownedIdentityWasDeleted
	case aKeycloakTargetedPushNotificationReceivedViaWebsocket(ownedIdentity: ObvCryptoId)
	case deletedObliviousChannelWithRemoteOwnedDevice
	case newConfirmedObliviousChannelWithRemoteOwnedDevice
	case newOwnedMessageReceived(obvOwnedMessage: ObvOwnedMessage)
	case newRemoteOwnedDevice
	case ownedAttachmentDownloaded(obvOwnedAttachment: ObvOwnedAttachment)
	case ownedAttachmentDownloadWasResumed(ownCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int)
	case ownedAttachmentDownloadWasPaused(ownCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int)
	case keycloakSynchronizationRequired(ownCryptoId: ObvCryptoId)
	case contactIntroductionInvitationSent(ownedIdentity: ObvCryptoId, contactIdentityA: ObvCryptoId, contactIdentityB: ObvCryptoId)
	case anOwnedDeviceWasUpdated(ownedCryptoId: ObvCryptoId)
	case anOwnedDeviceWasDeleted(ownedCryptoId: ObvCryptoId)
	case ownedAttachmentDownloadCancelledByServer(obvOwnedAttachment: ObvOwnedAttachment)
	case newContactDevice(obvContactIdentifier: ObvContactIdentifier)
	case updatedContactDevice(deviceIdentifier: ObvContactDeviceIdentifier)
	case anOwnedIdentityTransferProtocolFailed(ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID, error: Error)

	private enum Name {
		case contactGroupHasUpdatedPendingMembersAndGroupMembers
		case newContactGroup
		case newPendingGroupMemberDeclinedStatus
		case contactGroupDeleted
		case contactGroupHasUpdatedPublishedDetails
		case contactGroupJoinedHasUpdatedTrustedDetails
		case contactGroupOwnedDiscardedLatestDetails
		case contactGroupOwnedHasUpdatedLatestDetails
		case deletedObliviousChannelWithContactDevice
		case newTrustedContactIdentity
		case newBackupKeyGenerated
		case ownedIdentityWasDeactivated
		case ownedIdentityWasReactivated
		case networkOperationFailedSinceOwnedIdentityIsNotActive
		case serverRequiresAllActiveOwnedIdentitiesToRegisterToPushNotifications
		case engineRequiresOwnedIdentityToRegisterToPushNotifications
		case outboxMessagesAndAllTheirAttachmentsWereAcknowledged
		case outboxMessageCouldNotBeSentToServer
		case callerTurnCredentialsReceived
		case messageWasAcknowledged
		case newMessageReceived
		case attachmentWasAcknowledgedByServer
		case attachmentDownloadCancelledByServer
		case cannotReturnAnyProgressForMessageAttachments
		case attachmentDownloaded
		case attachmentDownloadWasResumed
		case attachmentDownloadWasPaused
		case newObvReturnReceiptToProcess
		case contactWasDeleted
		case newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity
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
		case updatedContactIdentity
		case ownedIdentityUnbindingFromKeycloakPerformed
		case updatedOwnedIdentity
		case mutualScanContactAdded
		case contactMessageExtendedPayloadAvailable
		case ownedMessageExtendedPayloadAvailable
		case contactIsActiveChangedWithinEngine
		case contactWasRevokedAsCompromisedWithinEngine
		case ContactObvCapabilitiesWereUpdated
		case OwnedIdentityCapabilitiesWereUpdated
		case newUserDialogToPresent
		case aPersistedDialogWasDeleted
		case groupV2WasCreatedOrUpdated
		case groupV2WasDeleted
		case groupV2UpdateDidFail
		case aPushTopicWasReceivedViaWebsocket
		case ownedIdentityWasDeleted
		case aKeycloakTargetedPushNotificationReceivedViaWebsocket
		case deletedObliviousChannelWithRemoteOwnedDevice
		case newConfirmedObliviousChannelWithRemoteOwnedDevice
		case newOwnedMessageReceived
		case newRemoteOwnedDevice
		case ownedAttachmentDownloaded
		case ownedAttachmentDownloadWasResumed
		case ownedAttachmentDownloadWasPaused
		case keycloakSynchronizationRequired
		case contactIntroductionInvitationSent
		case anOwnedDeviceWasUpdated
		case anOwnedDeviceWasDeleted
		case ownedAttachmentDownloadCancelledByServer
		case newContactDevice
		case updatedContactDevice
		case anOwnedIdentityTransferProtocolFailed

		private var namePrefix: String { String(describing: ObvEngineNotificationNew.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: ObvEngineNotificationNew) -> NSNotification.Name {
			switch notification {
			case .contactGroupHasUpdatedPendingMembersAndGroupMembers: return Name.contactGroupHasUpdatedPendingMembersAndGroupMembers.name
			case .newContactGroup: return Name.newContactGroup.name
			case .newPendingGroupMemberDeclinedStatus: return Name.newPendingGroupMemberDeclinedStatus.name
			case .contactGroupDeleted: return Name.contactGroupDeleted.name
			case .contactGroupHasUpdatedPublishedDetails: return Name.contactGroupHasUpdatedPublishedDetails.name
			case .contactGroupJoinedHasUpdatedTrustedDetails: return Name.contactGroupJoinedHasUpdatedTrustedDetails.name
			case .contactGroupOwnedDiscardedLatestDetails: return Name.contactGroupOwnedDiscardedLatestDetails.name
			case .contactGroupOwnedHasUpdatedLatestDetails: return Name.contactGroupOwnedHasUpdatedLatestDetails.name
			case .deletedObliviousChannelWithContactDevice: return Name.deletedObliviousChannelWithContactDevice.name
			case .newTrustedContactIdentity: return Name.newTrustedContactIdentity.name
			case .newBackupKeyGenerated: return Name.newBackupKeyGenerated.name
			case .ownedIdentityWasDeactivated: return Name.ownedIdentityWasDeactivated.name
			case .ownedIdentityWasReactivated: return Name.ownedIdentityWasReactivated.name
			case .networkOperationFailedSinceOwnedIdentityIsNotActive: return Name.networkOperationFailedSinceOwnedIdentityIsNotActive.name
			case .serverRequiresAllActiveOwnedIdentitiesToRegisterToPushNotifications: return Name.serverRequiresAllActiveOwnedIdentitiesToRegisterToPushNotifications.name
			case .engineRequiresOwnedIdentityToRegisterToPushNotifications: return Name.engineRequiresOwnedIdentityToRegisterToPushNotifications.name
			case .outboxMessagesAndAllTheirAttachmentsWereAcknowledged: return Name.outboxMessagesAndAllTheirAttachmentsWereAcknowledged.name
			case .outboxMessageCouldNotBeSentToServer: return Name.outboxMessageCouldNotBeSentToServer.name
			case .callerTurnCredentialsReceived: return Name.callerTurnCredentialsReceived.name
			case .messageWasAcknowledged: return Name.messageWasAcknowledged.name
			case .newMessageReceived: return Name.newMessageReceived.name
			case .attachmentWasAcknowledgedByServer: return Name.attachmentWasAcknowledgedByServer.name
			case .attachmentDownloadCancelledByServer: return Name.attachmentDownloadCancelledByServer.name
			case .cannotReturnAnyProgressForMessageAttachments: return Name.cannotReturnAnyProgressForMessageAttachments.name
			case .attachmentDownloaded: return Name.attachmentDownloaded.name
			case .attachmentDownloadWasResumed: return Name.attachmentDownloadWasResumed.name
			case .attachmentDownloadWasPaused: return Name.attachmentDownloadWasPaused.name
			case .newObvReturnReceiptToProcess: return Name.newObvReturnReceiptToProcess.name
			case .contactWasDeleted: return Name.contactWasDeleted.name
			case .newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity: return Name.newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity.name
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
			case .updatedContactIdentity: return Name.updatedContactIdentity.name
			case .ownedIdentityUnbindingFromKeycloakPerformed: return Name.ownedIdentityUnbindingFromKeycloakPerformed.name
			case .updatedOwnedIdentity: return Name.updatedOwnedIdentity.name
			case .mutualScanContactAdded: return Name.mutualScanContactAdded.name
			case .contactMessageExtendedPayloadAvailable: return Name.contactMessageExtendedPayloadAvailable.name
			case .ownedMessageExtendedPayloadAvailable: return Name.ownedMessageExtendedPayloadAvailable.name
			case .contactIsActiveChangedWithinEngine: return Name.contactIsActiveChangedWithinEngine.name
			case .contactWasRevokedAsCompromisedWithinEngine: return Name.contactWasRevokedAsCompromisedWithinEngine.name
			case .ContactObvCapabilitiesWereUpdated: return Name.ContactObvCapabilitiesWereUpdated.name
			case .OwnedIdentityCapabilitiesWereUpdated: return Name.OwnedIdentityCapabilitiesWereUpdated.name
			case .newUserDialogToPresent: return Name.newUserDialogToPresent.name
			case .aPersistedDialogWasDeleted: return Name.aPersistedDialogWasDeleted.name
			case .groupV2WasCreatedOrUpdated: return Name.groupV2WasCreatedOrUpdated.name
			case .groupV2WasDeleted: return Name.groupV2WasDeleted.name
			case .groupV2UpdateDidFail: return Name.groupV2UpdateDidFail.name
			case .aPushTopicWasReceivedViaWebsocket: return Name.aPushTopicWasReceivedViaWebsocket.name
			case .ownedIdentityWasDeleted: return Name.ownedIdentityWasDeleted.name
			case .aKeycloakTargetedPushNotificationReceivedViaWebsocket: return Name.aKeycloakTargetedPushNotificationReceivedViaWebsocket.name
			case .deletedObliviousChannelWithRemoteOwnedDevice: return Name.deletedObliviousChannelWithRemoteOwnedDevice.name
			case .newConfirmedObliviousChannelWithRemoteOwnedDevice: return Name.newConfirmedObliviousChannelWithRemoteOwnedDevice.name
			case .newOwnedMessageReceived: return Name.newOwnedMessageReceived.name
			case .newRemoteOwnedDevice: return Name.newRemoteOwnedDevice.name
			case .ownedAttachmentDownloaded: return Name.ownedAttachmentDownloaded.name
			case .ownedAttachmentDownloadWasResumed: return Name.ownedAttachmentDownloadWasResumed.name
			case .ownedAttachmentDownloadWasPaused: return Name.ownedAttachmentDownloadWasPaused.name
			case .keycloakSynchronizationRequired: return Name.keycloakSynchronizationRequired.name
			case .contactIntroductionInvitationSent: return Name.contactIntroductionInvitationSent.name
			case .anOwnedDeviceWasUpdated: return Name.anOwnedDeviceWasUpdated.name
			case .anOwnedDeviceWasDeleted: return Name.anOwnedDeviceWasDeleted.name
			case .ownedAttachmentDownloadCancelledByServer: return Name.ownedAttachmentDownloadCancelledByServer.name
			case .newContactDevice: return Name.newContactDevice.name
			case .updatedContactDevice: return Name.updatedContactDevice.name
			case .anOwnedIdentityTransferProtocolFailed: return Name.anOwnedIdentityTransferProtocolFailed.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .contactGroupHasUpdatedPendingMembersAndGroupMembers(obvContactGroup: let obvContactGroup):
			info = [
				"obvContactGroup": obvContactGroup,
			]
		case .newContactGroup(obvContactGroup: let obvContactGroup):
			info = [
				"obvContactGroup": obvContactGroup,
			]
		case .newPendingGroupMemberDeclinedStatus(obvContactGroup: let obvContactGroup):
			info = [
				"obvContactGroup": obvContactGroup,
			]
		case .contactGroupDeleted(ownedIdentity: let ownedIdentity, groupOwner: let groupOwner, groupUid: let groupUid):
			info = [
				"ownedIdentity": ownedIdentity,
				"groupOwner": groupOwner,
				"groupUid": groupUid,
			]
		case .contactGroupHasUpdatedPublishedDetails(obvContactGroup: let obvContactGroup):
			info = [
				"obvContactGroup": obvContactGroup,
			]
		case .contactGroupJoinedHasUpdatedTrustedDetails(obvContactGroup: let obvContactGroup):
			info = [
				"obvContactGroup": obvContactGroup,
			]
		case .contactGroupOwnedDiscardedLatestDetails(obvContactGroup: let obvContactGroup):
			info = [
				"obvContactGroup": obvContactGroup,
			]
		case .contactGroupOwnedHasUpdatedLatestDetails(obvContactGroup: let obvContactGroup):
			info = [
				"obvContactGroup": obvContactGroup,
			]
		case .deletedObliviousChannelWithContactDevice(obvContactIdentifier: let obvContactIdentifier):
			info = [
				"obvContactIdentifier": obvContactIdentifier,
			]
		case .newTrustedContactIdentity(obvContactIdentity: let obvContactIdentity):
			info = [
				"obvContactIdentity": obvContactIdentity,
			]
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
		case .serverRequiresAllActiveOwnedIdentitiesToRegisterToPushNotifications:
			info = nil
		case .engineRequiresOwnedIdentityToRegisterToPushNotifications(ownedCryptoId: let ownedCryptoId, performOwnedDeviceDiscoveryOnFinish: let performOwnedDeviceDiscoveryOnFinish):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"performOwnedDeviceDiscoveryOnFinish": performOwnedDeviceDiscoveryOnFinish,
			]
		case .outboxMessagesAndAllTheirAttachmentsWereAcknowledged(messageIdsAndTimestampsFromServer: let messageIdsAndTimestampsFromServer):
			info = [
				"messageIdsAndTimestampsFromServer": messageIdsAndTimestampsFromServer,
			]
		case .outboxMessageCouldNotBeSentToServer(messageIdentifierFromEngine: let messageIdentifierFromEngine, ownedIdentity: let ownedIdentity):
			info = [
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
				"ownedIdentity": ownedIdentity,
			]
		case .callerTurnCredentialsReceived(ownedIdentity: let ownedIdentity, callUuid: let callUuid, turnCredentials: let turnCredentials):
			info = [
				"ownedIdentity": ownedIdentity,
				"callUuid": callUuid,
				"turnCredentials": turnCredentials,
			]
		case .messageWasAcknowledged(ownedIdentity: let ownedIdentity, messageIdentifierFromEngine: let messageIdentifierFromEngine, timestampFromServer: let timestampFromServer, isAppMessageWithUserContent: let isAppMessageWithUserContent, isVoipMessage: let isVoipMessage):
			info = [
				"ownedIdentity": ownedIdentity,
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
				"timestampFromServer": timestampFromServer,
				"isAppMessageWithUserContent": isAppMessageWithUserContent,
				"isVoipMessage": isVoipMessage,
			]
		case .newMessageReceived(obvMessage: let obvMessage):
			info = [
				"obvMessage": obvMessage,
			]
		case .attachmentWasAcknowledgedByServer(ownedCryptoId: let ownedCryptoId, messageIdentifierFromEngine: let messageIdentifierFromEngine, attachmentNumber: let attachmentNumber):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
				"attachmentNumber": attachmentNumber,
			]
		case .attachmentDownloadCancelledByServer(obvAttachment: let obvAttachment):
			info = [
				"obvAttachment": obvAttachment,
			]
		case .cannotReturnAnyProgressForMessageAttachments(ownedCryptoId: let ownedCryptoId, messageIdentifierFromEngine: let messageIdentifierFromEngine):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
			]
		case .attachmentDownloaded(obvAttachment: let obvAttachment):
			info = [
				"obvAttachment": obvAttachment,
			]
		case .attachmentDownloadWasResumed(ownCryptoId: let ownCryptoId, messageIdentifierFromEngine: let messageIdentifierFromEngine, attachmentNumber: let attachmentNumber):
			info = [
				"ownCryptoId": ownCryptoId,
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
				"attachmentNumber": attachmentNumber,
			]
		case .attachmentDownloadWasPaused(ownCryptoId: let ownCryptoId, messageIdentifierFromEngine: let messageIdentifierFromEngine, attachmentNumber: let attachmentNumber):
			info = [
				"ownCryptoId": ownCryptoId,
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
				"attachmentNumber": attachmentNumber,
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
				"apiKeyExpirationDate": OptionalWrapper(apiKeyExpirationDate),
			]
		case .newObliviousChannelWithContactDevice(obvContactIdentifier: let obvContactIdentifier):
			info = [
				"obvContactIdentifier": obvContactIdentifier,
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
		case .updatedOwnedIdentity(obvOwnedIdentity: let obvOwnedIdentity):
			info = [
				"obvOwnedIdentity": obvOwnedIdentity,
			]
		case .mutualScanContactAdded(obvContactIdentity: let obvContactIdentity, signature: let signature):
			info = [
				"obvContactIdentity": obvContactIdentity,
				"signature": signature,
			]
		case .contactMessageExtendedPayloadAvailable(obvMessage: let obvMessage):
			info = [
				"obvMessage": obvMessage,
			]
		case .ownedMessageExtendedPayloadAvailable(obvOwnedMessage: let obvOwnedMessage):
			info = [
				"obvOwnedMessage": obvOwnedMessage,
			]
		case .contactIsActiveChangedWithinEngine(obvContactIdentity: let obvContactIdentity):
			info = [
				"obvContactIdentity": obvContactIdentity,
			]
		case .contactWasRevokedAsCompromisedWithinEngine(obvContactIdentifier: let obvContactIdentifier):
			info = [
				"obvContactIdentifier": obvContactIdentifier,
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
		case .aPersistedDialogWasDeleted(ownedCryptoId: let ownedCryptoId, uuid: let uuid):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"uuid": uuid,
			]
		case .groupV2WasCreatedOrUpdated(obvGroupV2: let obvGroupV2, initiator: let initiator):
			info = [
				"obvGroupV2": obvGroupV2,
				"initiator": initiator,
			]
		case .groupV2WasDeleted(ownedIdentity: let ownedIdentity, appGroupIdentifier: let appGroupIdentifier):
			info = [
				"ownedIdentity": ownedIdentity,
				"appGroupIdentifier": appGroupIdentifier,
			]
		case .groupV2UpdateDidFail(ownedIdentity: let ownedIdentity, appGroupIdentifier: let appGroupIdentifier):
			info = [
				"ownedIdentity": ownedIdentity,
				"appGroupIdentifier": appGroupIdentifier,
			]
		case .aPushTopicWasReceivedViaWebsocket(pushTopic: let pushTopic):
			info = [
				"pushTopic": pushTopic,
			]
		case .ownedIdentityWasDeleted:
			info = nil
		case .aKeycloakTargetedPushNotificationReceivedViaWebsocket(ownedIdentity: let ownedIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
			]
		case .deletedObliviousChannelWithRemoteOwnedDevice:
			info = nil
		case .newConfirmedObliviousChannelWithRemoteOwnedDevice:
			info = nil
		case .newOwnedMessageReceived(obvOwnedMessage: let obvOwnedMessage):
			info = [
				"obvOwnedMessage": obvOwnedMessage,
			]
		case .newRemoteOwnedDevice:
			info = nil
		case .ownedAttachmentDownloaded(obvOwnedAttachment: let obvOwnedAttachment):
			info = [
				"obvOwnedAttachment": obvOwnedAttachment,
			]
		case .ownedAttachmentDownloadWasResumed(ownCryptoId: let ownCryptoId, messageIdentifierFromEngine: let messageIdentifierFromEngine, attachmentNumber: let attachmentNumber):
			info = [
				"ownCryptoId": ownCryptoId,
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
				"attachmentNumber": attachmentNumber,
			]
		case .ownedAttachmentDownloadWasPaused(ownCryptoId: let ownCryptoId, messageIdentifierFromEngine: let messageIdentifierFromEngine, attachmentNumber: let attachmentNumber):
			info = [
				"ownCryptoId": ownCryptoId,
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
				"attachmentNumber": attachmentNumber,
			]
		case .keycloakSynchronizationRequired(ownCryptoId: let ownCryptoId):
			info = [
				"ownCryptoId": ownCryptoId,
			]
		case .contactIntroductionInvitationSent(ownedIdentity: let ownedIdentity, contactIdentityA: let contactIdentityA, contactIdentityB: let contactIdentityB):
			info = [
				"ownedIdentity": ownedIdentity,
				"contactIdentityA": contactIdentityA,
				"contactIdentityB": contactIdentityB,
			]
		case .anOwnedDeviceWasUpdated(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
			]
		case .anOwnedDeviceWasDeleted(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
			]
		case .ownedAttachmentDownloadCancelledByServer(obvOwnedAttachment: let obvOwnedAttachment):
			info = [
				"obvOwnedAttachment": obvOwnedAttachment,
			]
		case .newContactDevice(obvContactIdentifier: let obvContactIdentifier):
			info = [
				"obvContactIdentifier": obvContactIdentifier,
			]
		case .updatedContactDevice(deviceIdentifier: let deviceIdentifier):
			info = [
				"deviceIdentifier": deviceIdentifier,
			]
		case .anOwnedIdentityTransferProtocolFailed(ownedCryptoId: let ownedCryptoId, protocolInstanceUID: let protocolInstanceUID, error: let error):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"protocolInstanceUID": protocolInstanceUID,
				"error": error,
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

	public static func observeContactGroupHasUpdatedPendingMembersAndGroupMembers(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactGroup) -> Void) -> NSObjectProtocol {
		let name = Name.contactGroupHasUpdatedPendingMembersAndGroupMembers.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvContactGroup = notification.userInfo!["obvContactGroup"] as! ObvContactGroup
			block(obvContactGroup)
		}
	}

	public static func observeNewContactGroup(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactGroup) -> Void) -> NSObjectProtocol {
		let name = Name.newContactGroup.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvContactGroup = notification.userInfo!["obvContactGroup"] as! ObvContactGroup
			block(obvContactGroup)
		}
	}

	public static func observeNewPendingGroupMemberDeclinedStatus(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactGroup) -> Void) -> NSObjectProtocol {
		let name = Name.newPendingGroupMemberDeclinedStatus.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvContactGroup = notification.userInfo!["obvContactGroup"] as! ObvContactGroup
			block(obvContactGroup)
		}
	}

	public static func observeContactGroupDeleted(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvOwnedIdentity, ObvCryptoId, UID) -> Void) -> NSObjectProtocol {
		let name = Name.contactGroupDeleted.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvOwnedIdentity
			let groupOwner = notification.userInfo!["groupOwner"] as! ObvCryptoId
			let groupUid = notification.userInfo!["groupUid"] as! UID
			block(ownedIdentity, groupOwner, groupUid)
		}
	}

	public static func observeContactGroupHasUpdatedPublishedDetails(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactGroup) -> Void) -> NSObjectProtocol {
		let name = Name.contactGroupHasUpdatedPublishedDetails.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvContactGroup = notification.userInfo!["obvContactGroup"] as! ObvContactGroup
			block(obvContactGroup)
		}
	}

	public static func observeContactGroupJoinedHasUpdatedTrustedDetails(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactGroup) -> Void) -> NSObjectProtocol {
		let name = Name.contactGroupJoinedHasUpdatedTrustedDetails.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvContactGroup = notification.userInfo!["obvContactGroup"] as! ObvContactGroup
			block(obvContactGroup)
		}
	}

	public static func observeContactGroupOwnedDiscardedLatestDetails(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactGroup) -> Void) -> NSObjectProtocol {
		let name = Name.contactGroupOwnedDiscardedLatestDetails.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvContactGroup = notification.userInfo!["obvContactGroup"] as! ObvContactGroup
			block(obvContactGroup)
		}
	}

	public static func observeContactGroupOwnedHasUpdatedLatestDetails(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactGroup) -> Void) -> NSObjectProtocol {
		let name = Name.contactGroupOwnedHasUpdatedLatestDetails.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvContactGroup = notification.userInfo!["obvContactGroup"] as! ObvContactGroup
			block(obvContactGroup)
		}
	}

	public static func observeDeletedObliviousChannelWithContactDevice(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.deletedObliviousChannelWithContactDevice.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvContactIdentifier = notification.userInfo!["obvContactIdentifier"] as! ObvContactIdentifier
			block(obvContactIdentifier)
		}
	}

	public static func observeNewTrustedContactIdentity(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.newTrustedContactIdentity.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvContactIdentity = notification.userInfo!["obvContactIdentity"] as! ObvContactIdentity
			block(obvContactIdentity)
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

	public static func observeServerRequiresAllActiveOwnedIdentitiesToRegisterToPushNotifications(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.serverRequiresAllActiveOwnedIdentitiesToRegisterToPushNotifications.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			block()
		}
	}

	public static func observeEngineRequiresOwnedIdentityToRegisterToPushNotifications(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Bool) -> Void) -> NSObjectProtocol {
		let name = Name.engineRequiresOwnedIdentityToRegisterToPushNotifications.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let performOwnedDeviceDiscoveryOnFinish = notification.userInfo!["performOwnedDeviceDiscoveryOnFinish"] as! Bool
			block(ownedCryptoId, performOwnedDeviceDiscoveryOnFinish)
		}
	}

	public static func observeOutboxMessagesAndAllTheirAttachmentsWereAcknowledged(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping ([(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, timestampFromServer: Date)]) -> Void) -> NSObjectProtocol {
		let name = Name.outboxMessagesAndAllTheirAttachmentsWereAcknowledged.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let messageIdsAndTimestampsFromServer = notification.userInfo!["messageIdsAndTimestampsFromServer"] as! [(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, timestampFromServer: Date)]
			block(messageIdsAndTimestampsFromServer)
		}
	}

	public static func observeOutboxMessageCouldNotBeSentToServer(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (Data, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.outboxMessageCouldNotBeSentToServer.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			block(messageIdentifierFromEngine, ownedIdentity)
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

	public static func observeNewMessageReceived(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvMessage) -> Void) -> NSObjectProtocol {
		let name = Name.newMessageReceived.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvMessage = notification.userInfo!["obvMessage"] as! ObvMessage
			block(obvMessage)
		}
	}

	public static func observeAttachmentWasAcknowledgedByServer(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Data, Int) -> Void) -> NSObjectProtocol {
		let name = Name.attachmentWasAcknowledgedByServer.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			let attachmentNumber = notification.userInfo!["attachmentNumber"] as! Int
			block(ownedCryptoId, messageIdentifierFromEngine, attachmentNumber)
		}
	}

	public static func observeAttachmentDownloadCancelledByServer(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvAttachment) -> Void) -> NSObjectProtocol {
		let name = Name.attachmentDownloadCancelledByServer.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvAttachment = notification.userInfo!["obvAttachment"] as! ObvAttachment
			block(obvAttachment)
		}
	}

	public static func observeCannotReturnAnyProgressForMessageAttachments(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Data) -> Void) -> NSObjectProtocol {
		let name = Name.cannotReturnAnyProgressForMessageAttachments.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			block(ownedCryptoId, messageIdentifierFromEngine)
		}
	}

	public static func observeAttachmentDownloaded(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvAttachment) -> Void) -> NSObjectProtocol {
		let name = Name.attachmentDownloaded.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvAttachment = notification.userInfo!["obvAttachment"] as! ObvAttachment
			block(obvAttachment)
		}
	}

	public static func observeAttachmentDownloadWasResumed(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Data, Int) -> Void) -> NSObjectProtocol {
		let name = Name.attachmentDownloadWasResumed.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownCryptoId = notification.userInfo!["ownCryptoId"] as! ObvCryptoId
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			let attachmentNumber = notification.userInfo!["attachmentNumber"] as! Int
			block(ownCryptoId, messageIdentifierFromEngine, attachmentNumber)
		}
	}

	public static func observeAttachmentDownloadWasPaused(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Data, Int) -> Void) -> NSObjectProtocol {
		let name = Name.attachmentDownloadWasPaused.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownCryptoId = notification.userInfo!["ownCryptoId"] as! ObvCryptoId
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			let attachmentNumber = notification.userInfo!["attachmentNumber"] as! Int
			block(ownCryptoId, messageIdentifierFromEngine, attachmentNumber)
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

	public static func observeNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, APIKeyStatus, APIPermissions, Date?) -> Void) -> NSObjectProtocol {
		let name = Name.newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			let apiKeyStatus = notification.userInfo!["apiKeyStatus"] as! APIKeyStatus
			let apiPermissions = notification.userInfo!["apiPermissions"] as! APIPermissions
			let apiKeyExpirationDateWrapper = notification.userInfo!["apiKeyExpirationDate"] as! OptionalWrapper<Date>
			let apiKeyExpirationDate = apiKeyExpirationDateWrapper.value
			block(ownedIdentity, apiKeyStatus, apiPermissions, apiKeyExpirationDate)
		}
	}

	public static func observeNewObliviousChannelWithContactDevice(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.newObliviousChannelWithContactDevice.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvContactIdentifier = notification.userInfo!["obvContactIdentifier"] as! ObvContactIdentifier
			block(obvContactIdentifier)
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

	public static func observeContactMessageExtendedPayloadAvailable(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvMessage) -> Void) -> NSObjectProtocol {
		let name = Name.contactMessageExtendedPayloadAvailable.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvMessage = notification.userInfo!["obvMessage"] as! ObvMessage
			block(obvMessage)
		}
	}

	public static func observeOwnedMessageExtendedPayloadAvailable(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvOwnedMessage) -> Void) -> NSObjectProtocol {
		let name = Name.ownedMessageExtendedPayloadAvailable.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvOwnedMessage = notification.userInfo!["obvOwnedMessage"] as! ObvOwnedMessage
			block(obvOwnedMessage)
		}
	}

	public static func observeContactIsActiveChangedWithinEngine(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.contactIsActiveChangedWithinEngine.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvContactIdentity = notification.userInfo!["obvContactIdentity"] as! ObvContactIdentity
			block(obvContactIdentity)
		}
	}

	public static func observeContactWasRevokedAsCompromisedWithinEngine(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.contactWasRevokedAsCompromisedWithinEngine.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvContactIdentifier = notification.userInfo!["obvContactIdentifier"] as! ObvContactIdentifier
			block(obvContactIdentifier)
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

	public static func observeAPersistedDialogWasDeleted(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, UUID) -> Void) -> NSObjectProtocol {
		let name = Name.aPersistedDialogWasDeleted.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let uuid = notification.userInfo!["uuid"] as! UUID
			block(ownedCryptoId, uuid)
		}
	}

	public static func observeGroupV2WasCreatedOrUpdated(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvGroupV2, ObvGroupV2.CreationOrUpdateInitiator) -> Void) -> NSObjectProtocol {
		let name = Name.groupV2WasCreatedOrUpdated.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvGroupV2 = notification.userInfo!["obvGroupV2"] as! ObvGroupV2
			let initiator = notification.userInfo!["initiator"] as! ObvGroupV2.CreationOrUpdateInitiator
			block(obvGroupV2, initiator)
		}
	}

	public static func observeGroupV2WasDeleted(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Data) -> Void) -> NSObjectProtocol {
		let name = Name.groupV2WasDeleted.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			let appGroupIdentifier = notification.userInfo!["appGroupIdentifier"] as! Data
			block(ownedIdentity, appGroupIdentifier)
		}
	}

	public static func observeGroupV2UpdateDidFail(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Data) -> Void) -> NSObjectProtocol {
		let name = Name.groupV2UpdateDidFail.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			let appGroupIdentifier = notification.userInfo!["appGroupIdentifier"] as! Data
			block(ownedIdentity, appGroupIdentifier)
		}
	}

	public static func observeAPushTopicWasReceivedViaWebsocket(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (String) -> Void) -> NSObjectProtocol {
		let name = Name.aPushTopicWasReceivedViaWebsocket.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let pushTopic = notification.userInfo!["pushTopic"] as! String
			block(pushTopic)
		}
	}

	public static func observeOwnedIdentityWasDeleted(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityWasDeleted.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			block()
		}
	}

	public static func observeAKeycloakTargetedPushNotificationReceivedViaWebsocket(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.aKeycloakTargetedPushNotificationReceivedViaWebsocket.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			block(ownedIdentity)
		}
	}

	public static func observeDeletedObliviousChannelWithRemoteOwnedDevice(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.deletedObliviousChannelWithRemoteOwnedDevice.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			block()
		}
	}

	public static func observeNewConfirmedObliviousChannelWithRemoteOwnedDevice(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.newConfirmedObliviousChannelWithRemoteOwnedDevice.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			block()
		}
	}

	public static func observeNewOwnedMessageReceived(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvOwnedMessage) -> Void) -> NSObjectProtocol {
		let name = Name.newOwnedMessageReceived.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvOwnedMessage = notification.userInfo!["obvOwnedMessage"] as! ObvOwnedMessage
			block(obvOwnedMessage)
		}
	}

	public static func observeNewRemoteOwnedDevice(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.newRemoteOwnedDevice.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			block()
		}
	}

	public static func observeOwnedAttachmentDownloaded(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvOwnedAttachment) -> Void) -> NSObjectProtocol {
		let name = Name.ownedAttachmentDownloaded.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvOwnedAttachment = notification.userInfo!["obvOwnedAttachment"] as! ObvOwnedAttachment
			block(obvOwnedAttachment)
		}
	}

	public static func observeOwnedAttachmentDownloadWasResumed(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Data, Int) -> Void) -> NSObjectProtocol {
		let name = Name.ownedAttachmentDownloadWasResumed.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownCryptoId = notification.userInfo!["ownCryptoId"] as! ObvCryptoId
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			let attachmentNumber = notification.userInfo!["attachmentNumber"] as! Int
			block(ownCryptoId, messageIdentifierFromEngine, attachmentNumber)
		}
	}

	public static func observeOwnedAttachmentDownloadWasPaused(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Data, Int) -> Void) -> NSObjectProtocol {
		let name = Name.ownedAttachmentDownloadWasPaused.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownCryptoId = notification.userInfo!["ownCryptoId"] as! ObvCryptoId
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			let attachmentNumber = notification.userInfo!["attachmentNumber"] as! Int
			block(ownCryptoId, messageIdentifierFromEngine, attachmentNumber)
		}
	}

	public static func observeKeycloakSynchronizationRequired(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.keycloakSynchronizationRequired.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownCryptoId = notification.userInfo!["ownCryptoId"] as! ObvCryptoId
			block(ownCryptoId)
		}
	}

	public static func observeContactIntroductionInvitationSent(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvCryptoId, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.contactIntroductionInvitationSent.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			let contactIdentityA = notification.userInfo!["contactIdentityA"] as! ObvCryptoId
			let contactIdentityB = notification.userInfo!["contactIdentityB"] as! ObvCryptoId
			block(ownedIdentity, contactIdentityA, contactIdentityB)
		}
	}

	public static func observeAnOwnedDeviceWasUpdated(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.anOwnedDeviceWasUpdated.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(ownedCryptoId)
		}
	}

	public static func observeAnOwnedDeviceWasDeleted(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.anOwnedDeviceWasDeleted.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(ownedCryptoId)
		}
	}

	public static func observeOwnedAttachmentDownloadCancelledByServer(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvOwnedAttachment) -> Void) -> NSObjectProtocol {
		let name = Name.ownedAttachmentDownloadCancelledByServer.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvOwnedAttachment = notification.userInfo!["obvOwnedAttachment"] as! ObvOwnedAttachment
			block(obvOwnedAttachment)
		}
	}

	public static func observeNewContactDevice(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.newContactDevice.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let obvContactIdentifier = notification.userInfo!["obvContactIdentifier"] as! ObvContactIdentifier
			block(obvContactIdentifier)
		}
	}

	public static func observeUpdatedContactDevice(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvContactDeviceIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.updatedContactDevice.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let deviceIdentifier = notification.userInfo!["deviceIdentifier"] as! ObvContactDeviceIdentifier
			block(deviceIdentifier)
		}
	}

	public static func observeAnOwnedIdentityTransferProtocolFailed(within appNotificationCenter: NotificationCenter, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, UID, Error) -> Void) -> NSObjectProtocol {
		let name = Name.anOwnedIdentityTransferProtocolFailed.name
		return appNotificationCenter.addObserver(forName: name, object: nil, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let protocolInstanceUID = notification.userInfo!["protocolInstanceUID"] as! UID
			let error = notification.userInfo!["error"] as! Error
			block(ownedCryptoId, protocolInstanceUID, error)
		}
	}

}
