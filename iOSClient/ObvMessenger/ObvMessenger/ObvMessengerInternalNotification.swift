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
import CoreData
import ObvTypes
import ObvEngine
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

enum ObvMessengerInternalNotification {
	case messagesAreNotNewAnymore(persistedMessageObjectIDs: Set<TypeSafeManagedObjectID<PersistedMessage>>)
	case persistedContactGroupHasUpdatedContactIdentities(persistedContactGroupObjectID: NSManagedObjectID, insertedContacts: Set<PersistedObvContactIdentity>, removedContacts: Set<PersistedObvContactIdentity>)
	case persistedDiscussionHasNewTitle(objectID: TypeSafeManagedObjectID<PersistedDiscussion>, title: String)
	case newDraftToSend(persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>)
	case draftWasSent(persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>)
	case newOrUpdatedPersistedInvitation(obvDialog: ObvDialog, persistedInvitationUUID: UUID)
	case persistedMessageReceivedWasDeleted(objectID: NSManagedObjectID, messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, sortIndex: Double, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>)
	case newPersistedObvContactDevice(contactDeviceObjectID: NSManagedObjectID, contactCryptoId: ObvCryptoId)
	case deletedPersistedObvContactDevice(contactCryptoId: ObvCryptoId)
	case persistedContactWasInserted(objectID: NSManagedObjectID, contactCryptoId: ObvCryptoId)
	case persistedContactWasDeleted(objectID: NSManagedObjectID, identity: Data)
	case persistedContactHasNewCustomDisplayName(contactCryptoId: ObvCryptoId)
	case newPersistedObvOwnedIdentity(ownedCryptoId: ObvCryptoId)
	case userWantsToRefreshContactGroupJoined(obvContactGroup: ObvContactGroup)
	case currentOwnedCryptoIdChanged(newOwnedCryptoId: ObvCryptoId, apiKey: UUID)
	case ownedIdentityWasDeactivated(ownedIdentityObjectID: NSManagedObjectID)
	case ownedIdentityWasReactivated(ownedIdentityObjectID: NSManagedObjectID)
	case userWantsToPerfomCloudKitBackupNow
	case externalTransactionsWereMergedIntoViewContext
	case userWantsToPerfomBackupForExportNow(sourceView: UIView)
	case newMessageExpiration(expirationDate: Date)
	case newMuteExpiration(expirationDate: Date)
	case wipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask: Bool, completionHandler: (Bool) -> Void)
	case persistedMessageHasNewMetadata(persistedMessageObjectID: NSManagedObjectID)
	case fyleMessageJoinWithStatusHasNewProgress(objectID: NSManagedObjectID, progress: Progress)
	case aViewRequiresFyleMessageJoinWithStatusProgresses(objectIDs: [NSManagedObjectID])
	case userWantsToCallAndIsAllowedTo(contactIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>], groupId: (groupUid: UID, groupOwner: ObvCryptoId)?)
	case userWantsToSelectAndCallContacts(contactIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>], groupId: (groupUid: UID, groupOwner: ObvCryptoId)?)
	case userWantsToCallButWeShouldCheckSheIsAllowedTo(contactIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>], groupId: (groupUid: UID, groupOwner: ObvCryptoId)?)
	case userWantsToKickParticipant(call: Call, callParticipant: CallParticipant)
	case userWantsToAddParticipants(call: Call, contactIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>])
	case newWebRTCMessageWasReceived(webrtcMessage: WebRTCMessageJSON, contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, messageUploadTimestampFromServer: Date, messageIdentifierFromEngine: Data)
	case callHasBeenUpdated(call: Call, updateKind: CallUpdateKind)
	case callParticipantHasBeenUpdated(callParticipant: CallParticipant, updateKind: CallParticipantUpdateKind)
	case toggleCallView
	case hideCallView
	case newObvMessageWasReceivedViaPushKitNotification(obvMessage: ObvMessage)
	case newWebRTCMessageToSend(webrtcMessage: WebRTCMessageJSON, contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, forStartingCall: Bool, completion: () -> Void)
	case isCallKitEnabledSettingDidChange
	case isIncludesCallsInRecentsEnabledSettingDidChange
	case networkInterfaceTypeChanged(isConnected: Bool)
	case noMoreCallInProgress
	case appStateChanged(previousState: AppState, currentState: AppState)
	case outgoingCallFailedBecauseUserDeniedRecordPermission
	case voiceMessageFailedBecauseUserDeniedRecordPermission
	case rejectedIncomingCallBecauseUserDeniedRecordPermission
	case userRequestedDeletionOfPersistedMessage(persistedMessageObjectID: NSManagedObjectID, deletionType: DeletionType)
	case trashShouldBeEmptied
	case userRequestedDeletionOfPersistedDiscussion(persistedDiscussionObjectID: NSManagedObjectID, deletionType: DeletionType, completionHandler: (Bool) -> Void)
	case reportCallEvent(callUUID: UUID, callReport: CallReport, groupId: (groupUid: UID, groupOwner: ObvCryptoId)?, ownedCryptoId: ObvCryptoId)
	case newCallLogItem(objectID: TypeSafeManagedObjectID<PersistedCallLogItem>)
	case callLogItemWasUpdated(objectID: TypeSafeManagedObjectID<PersistedCallLogItem>)
	case userWantsToIntroduceContactToAnotherContact(ownedCryptoId: ObvCryptoId, firstContactCryptoId: ObvCryptoId, secondContactCryptoIds: Set<ObvCryptoId>)
	case showCallViewControllerForAnsweringNonCallKitIncomingCall(incomingCall: IncomingCall)
	case userWantsToShareOwnPublishedDetails(ownedCryptoId: ObvCryptoId, sourceView: UIView)
	case userWantsToSendInvite(ownedIdentity: ObvOwnedIdentity, urlIdentity: ObvURLIdentity)
	case userRequestedAPIKeyStatus(ownedCryptoId: ObvCryptoId, apiKey: UUID)
	case userRequestedNewAPIKeyActivation(ownedCryptoId: ObvCryptoId, apiKey: UUID)
	case userWantsToNavigateToDeepLink(deepLink: ObvDeepLink)
	case useLoadBalancedTurnServersDidChange
	case userWantsToReadReceivedMessagesThatRequiresUserAction(persistedMessageObjectIDs: Set<TypeSafeManagedObjectID<PersistedMessageReceived>>)
	case requestThumbnail(fyleElement: FyleElement, size: CGSize, thumbnailType: ThumbnailType, completionHandler: ((Thumbnail) -> Void))
	case persistedMessageReceivedWasRead(persistedMessageReceivedObjectID: NSManagedObjectID)
	case aReadOncePersistedMessageSentWasSent(persistedMessageSentObjectID: NSManagedObjectID, persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>)
	case userWantsToSetAndShareNewDiscussionSharedExpirationConfiguration(persistedDiscussionObjectID: NSManagedObjectID, expirationJSON: ExpirationJSON, ownedCryptoId: ObvCryptoId)
	case persistedDiscussionSharedConfigurationShouldBeSent(persistedDiscussionObjectID: NSManagedObjectID)
	case userWantsToDeleteContact(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId, viewController: UIViewController, completionHandler: ((Bool) -> Void))
	case cleanExpiredMessagesBackgroundTaskWasLaunched(completionHandler: (Bool) -> Void)
	case applyRetentionPoliciesBackgroundTaskWasLaunched(completionHandler: (Bool) -> Void)
	case updateBadgeBackgroundTaskWasLaunched(completionHandler: (Bool) -> Void)
	case applyAllRetentionPoliciesNow(launchedByBackgroundTask: Bool, completionHandler: (Bool) -> Void)
	case persistedMessageSystemWasDeleted(objectID: NSManagedObjectID, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>)
	case anOldDiscussionSharedConfigurationWasReceived(persistedDiscussionObjectID: NSManagedObjectID)
	case userWantsToSendEditedVersionOfSentMessage(sentMessageObjectID: NSManagedObjectID, newTextBody: String)
	case theBodyOfPersistedMessageReceivedDidChange(persistedMessageReceivedObjectID: NSManagedObjectID)
	case newProfilePictureCandidateToCache(requestUUID: UUID, profilePicture: UIImage)
	case newCachedProfilePictureCandidate(requestUUID: UUID, url: URL)
	case newCustomContactPictureCandidateToSave(requestUUID: UUID, profilePicture: UIImage)
	case newSavedCustomContactPictureCandidate(requestUUID: UUID, url: URL)
	case obvContactRequest(requestUUID: UUID, contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case obvContactAnswer(requestUUID: UUID, obvContact: ObvContactIdentity)
	case userWantsToMarkAllMessagesAsNotNewWithinDiscussion(persistedDiscussionObjectID: NSManagedObjectID, completionHandler: (Bool) -> Void)
	case resyncContactIdentityDevicesWithEngine(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case resyncContactIdentityDetailsStatusWithEngine(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case serverDoesNotSuppoortCall
	case pastedStringIsNotValidOlvidURL
	case serverDoesNotSupportCall
	case userWantsToRestartChannelEstablishmentProtocol(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case userWantsToReCreateChannelEstablishmentProtocol(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case persistedContactHasNewStatus(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case contactIdentityDetailsWereUpdated(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case userDidSeeNewDetailsOfContact(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case userWantsToEditContactNicknameAndPicture(persistedContactObjectID: NSManagedObjectID, nicknameAndPicture: CustomNicknameAndPicture)
	case userWantsToBindOwnedIdentityToKeycloak(ownedCryptoId: ObvCryptoId, obvKeycloakState: ObvKeycloakState, keycloakUserId: String, completionHandler: (Bool) -> Void)
	case userWantsToUnbindOwnedIdentityFromKeycloak(ownedCryptoId: ObvCryptoId, completionHandler: (Bool) -> Void)
	case requestHardLinkToFyle(fyleElement: FyleElement, completionHandler: ((HardLinkToFyle) -> Void))
	case requestAllHardLinksToFyles(fyleElements: [FyleElement], completionHandler: (([HardLinkToFyle?]) -> Void))
	case persistedDiscussionWasDeleted(discussionUriRepresentation: TypeSafeURL<PersistedDiscussion>)
	case newLockedPersistedDiscussion(previousDiscussionUriRepresentation: TypeSafeURL<PersistedDiscussion>, newLockedDiscussionId: TypeSafeManagedObjectID<PersistedDiscussion>)
	case persistedMessagesWereDeleted(discussionUriRepresentation: TypeSafeURL<PersistedDiscussion>, messageUriRepresentations: Set<TypeSafeURL<PersistedMessage>>)
	case persistedMessagesWereWiped(discussionUriRepresentation: TypeSafeURL<PersistedDiscussion>, messageUriRepresentations: Set<TypeSafeURL<PersistedMessage>>)
	case draftToSendWasReset(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>)
	case draftFyleJoinWasDeleted(discussionUriRepresentation: TypeSafeURL<PersistedDiscussion>, draftUriRepresentation: TypeSafeURL<PersistedDraft>, draftFyleJoinUriRepresentation: TypeSafeURL<PersistedDraftFyleJoin>)
	case shareExtensionExtensionContextWillCompleteRequest
	case userWantsToRemoveDraftFyleJoin(draftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>)
	case AppInitializationEnded
	case userWantsToChangeContactsSortOrder(ownedCryptoId: ObvCryptoId, sortOrder: ContactsSortOrder)
	case contactsSortOrderDidChange
	case identityColorStyleDidChange
	case userWantsToUpdateDiscussionLocalConfiguration(value: PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>)
	case userWantsToUpdateLocalConfigurationOfDiscussion(value: PersistedDiscussionLocalConfigurationValue, persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>)
	case discussionLocalConfigurationHasBeenUpdated(newValue: PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>)
	case audioInputHasBeenActivated(label: String, activate: () -> Void)
	case aViewRequiresObvMutualScanUrl(remoteIdentity: Data, ownedCryptoId: ObvCryptoId, completionHandler: ((ObvMutualScanUrl) -> Void))
	case userWantsToStartTrustEstablishmentWithMutualScanProtocol(ownedCryptoId: ObvCryptoId, mutualScanUrl: ObvMutualScanUrl)
	case insertDebugMessagesInAllExistingDiscussions
	case draftExpirationWasBeenUpdated(persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>)
	case badgesNeedToBeUpdated(ownedCryptoId: ObvCryptoId)
	case cleanExpiredMuteNotficationsThatExpiredEarlierThanNow
	case needToRecomputeAllBadges
	case userWantsToDisplayContactIntroductionScreen(contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, viewController: UIViewController)
	case userDidTapOnMissedMessageBubble
	case olvidSnackBarShouldBeShown(ownedCryptoId: ObvCryptoId, snackBarCategory: OlvidSnackBarCategory)
	case UserWantsToSeeDetailedExplanationsOfSnackBar(ownedCryptoId: ObvCryptoId, snackBarCategory: OlvidSnackBarCategory)
	case UserDismissedSnackBarForLater(ownedCryptoId: ObvCryptoId, snackBarCategory: OlvidSnackBarCategory)
	case UserRequestedToResetAllAlerts
	case olvidSnackBarShouldBeHidden(ownedCryptoId: ObvCryptoId)
	case userWantsToUpdateReaction(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, emoji: String?)
	case currentUserActivityDidChange(previousUserActivity: ObvUserActivityType, currentUserActivity: ObvUserActivityType)
	case displayedSnackBarShouldBeRefreshed
	case requestUserDeniedRecordPermissionAlert
	case incrementalCleanBackupStarts(initialCount: Int)
	case incrementalCleanBackupInProgress(currentCount: Int, cleanAllDevices: Bool)
	case incrementalCleanBackupTerminates(totalCount: Int)
	case userWantsToUnblockContact(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId)
	case userWantsToReblockContact(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId)
	case persistedContactIsActiveChanged(contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>)
	case installedOlvidAppIsOutdated(presentingViewController: UIViewController?)
	case userOwnedIdentityWasRevokedByKeycloak(ownedCryptoId: ObvCryptoId)
	case aOneToOneDiscussionTitleNeedsToBeReset(ownedIdentityObjectID: TypeSafeManagedObjectID<PersistedObvOwnedIdentity>)
	case uiRequiresSignedContactDetails(ownedIdentityCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId, completion: (SignedUserDetails?) -> Void)
	case preferredComposeMessageViewActionsDidChange
	case requestSyncAppDatabasesWithEngine(completion: (Result<Void,Error>) -> Void)

	private enum Name {
		case messagesAreNotNewAnymore
		case persistedContactGroupHasUpdatedContactIdentities
		case persistedDiscussionHasNewTitle
		case newDraftToSend
		case draftWasSent
		case newOrUpdatedPersistedInvitation
		case persistedMessageReceivedWasDeleted
		case newPersistedObvContactDevice
		case deletedPersistedObvContactDevice
		case persistedContactWasInserted
		case persistedContactWasDeleted
		case persistedContactHasNewCustomDisplayName
		case newPersistedObvOwnedIdentity
		case userWantsToRefreshContactGroupJoined
		case currentOwnedCryptoIdChanged
		case ownedIdentityWasDeactivated
		case ownedIdentityWasReactivated
		case userWantsToPerfomCloudKitBackupNow
		case externalTransactionsWereMergedIntoViewContext
		case userWantsToPerfomBackupForExportNow
		case newMessageExpiration
		case newMuteExpiration
		case wipeAllMessagesThatExpiredEarlierThanNow
		case persistedMessageHasNewMetadata
		case fyleMessageJoinWithStatusHasNewProgress
		case aViewRequiresFyleMessageJoinWithStatusProgresses
		case userWantsToCallAndIsAllowedTo
		case userWantsToSelectAndCallContacts
		case userWantsToCallButWeShouldCheckSheIsAllowedTo
		case userWantsToKickParticipant
		case userWantsToAddParticipants
		case newWebRTCMessageWasReceived
		case callHasBeenUpdated
		case callParticipantHasBeenUpdated
		case toggleCallView
		case hideCallView
		case newObvMessageWasReceivedViaPushKitNotification
		case newWebRTCMessageToSend
		case isCallKitEnabledSettingDidChange
		case isIncludesCallsInRecentsEnabledSettingDidChange
		case networkInterfaceTypeChanged
		case noMoreCallInProgress
		case appStateChanged
		case outgoingCallFailedBecauseUserDeniedRecordPermission
		case voiceMessageFailedBecauseUserDeniedRecordPermission
		case rejectedIncomingCallBecauseUserDeniedRecordPermission
		case userRequestedDeletionOfPersistedMessage
		case trashShouldBeEmptied
		case userRequestedDeletionOfPersistedDiscussion
		case reportCallEvent
		case newCallLogItem
		case callLogItemWasUpdated
		case userWantsToIntroduceContactToAnotherContact
		case showCallViewControllerForAnsweringNonCallKitIncomingCall
		case userWantsToShareOwnPublishedDetails
		case userWantsToSendInvite
		case userRequestedAPIKeyStatus
		case userRequestedNewAPIKeyActivation
		case userWantsToNavigateToDeepLink
		case useLoadBalancedTurnServersDidChange
		case userWantsToReadReceivedMessagesThatRequiresUserAction
		case requestThumbnail
		case persistedMessageReceivedWasRead
		case aReadOncePersistedMessageSentWasSent
		case userWantsToSetAndShareNewDiscussionSharedExpirationConfiguration
		case persistedDiscussionSharedConfigurationShouldBeSent
		case userWantsToDeleteContact
		case cleanExpiredMessagesBackgroundTaskWasLaunched
		case applyRetentionPoliciesBackgroundTaskWasLaunched
		case updateBadgeBackgroundTaskWasLaunched
		case applyAllRetentionPoliciesNow
		case persistedMessageSystemWasDeleted
		case anOldDiscussionSharedConfigurationWasReceived
		case userWantsToSendEditedVersionOfSentMessage
		case theBodyOfPersistedMessageReceivedDidChange
		case newProfilePictureCandidateToCache
		case newCachedProfilePictureCandidate
		case newCustomContactPictureCandidateToSave
		case newSavedCustomContactPictureCandidate
		case obvContactRequest
		case obvContactAnswer
		case userWantsToMarkAllMessagesAsNotNewWithinDiscussion
		case resyncContactIdentityDevicesWithEngine
		case resyncContactIdentityDetailsStatusWithEngine
		case serverDoesNotSuppoortCall
		case pastedStringIsNotValidOlvidURL
		case serverDoesNotSupportCall
		case userWantsToRestartChannelEstablishmentProtocol
		case userWantsToReCreateChannelEstablishmentProtocol
		case persistedContactHasNewStatus
		case contactIdentityDetailsWereUpdated
		case userDidSeeNewDetailsOfContact
		case userWantsToEditContactNicknameAndPicture
		case userWantsToBindOwnedIdentityToKeycloak
		case userWantsToUnbindOwnedIdentityFromKeycloak
		case requestHardLinkToFyle
		case requestAllHardLinksToFyles
		case persistedDiscussionWasDeleted
		case newLockedPersistedDiscussion
		case persistedMessagesWereDeleted
		case persistedMessagesWereWiped
		case draftToSendWasReset
		case draftFyleJoinWasDeleted
		case shareExtensionExtensionContextWillCompleteRequest
		case userWantsToRemoveDraftFyleJoin
		case AppInitializationEnded
		case userWantsToChangeContactsSortOrder
		case contactsSortOrderDidChange
		case identityColorStyleDidChange
		case userWantsToUpdateDiscussionLocalConfiguration
		case userWantsToUpdateLocalConfigurationOfDiscussion
		case discussionLocalConfigurationHasBeenUpdated
		case audioInputHasBeenActivated
		case aViewRequiresObvMutualScanUrl
		case userWantsToStartTrustEstablishmentWithMutualScanProtocol
		case insertDebugMessagesInAllExistingDiscussions
		case draftExpirationWasBeenUpdated
		case badgesNeedToBeUpdated
		case cleanExpiredMuteNotficationsThatExpiredEarlierThanNow
		case needToRecomputeAllBadges
		case userWantsToDisplayContactIntroductionScreen
		case userDidTapOnMissedMessageBubble
		case olvidSnackBarShouldBeShown
		case UserWantsToSeeDetailedExplanationsOfSnackBar
		case UserDismissedSnackBarForLater
		case UserRequestedToResetAllAlerts
		case olvidSnackBarShouldBeHidden
		case userWantsToUpdateReaction
		case currentUserActivityDidChange
		case displayedSnackBarShouldBeRefreshed
		case requestUserDeniedRecordPermissionAlert
		case incrementalCleanBackupStarts
		case incrementalCleanBackupInProgress
		case incrementalCleanBackupTerminates
		case userWantsToUnblockContact
		case userWantsToReblockContact
		case persistedContactIsActiveChanged
		case installedOlvidAppIsOutdated
		case userOwnedIdentityWasRevokedByKeycloak
		case aOneToOneDiscussionTitleNeedsToBeReset
		case uiRequiresSignedContactDetails
		case preferredComposeMessageViewActionsDidChange
		case requestSyncAppDatabasesWithEngine

		private var namePrefix: String { String(describing: ObvMessengerInternalNotification.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: ObvMessengerInternalNotification) -> NSNotification.Name {
			switch notification {
			case .messagesAreNotNewAnymore: return Name.messagesAreNotNewAnymore.name
			case .persistedContactGroupHasUpdatedContactIdentities: return Name.persistedContactGroupHasUpdatedContactIdentities.name
			case .persistedDiscussionHasNewTitle: return Name.persistedDiscussionHasNewTitle.name
			case .newDraftToSend: return Name.newDraftToSend.name
			case .draftWasSent: return Name.draftWasSent.name
			case .newOrUpdatedPersistedInvitation: return Name.newOrUpdatedPersistedInvitation.name
			case .persistedMessageReceivedWasDeleted: return Name.persistedMessageReceivedWasDeleted.name
			case .newPersistedObvContactDevice: return Name.newPersistedObvContactDevice.name
			case .deletedPersistedObvContactDevice: return Name.deletedPersistedObvContactDevice.name
			case .persistedContactWasInserted: return Name.persistedContactWasInserted.name
			case .persistedContactWasDeleted: return Name.persistedContactWasDeleted.name
			case .persistedContactHasNewCustomDisplayName: return Name.persistedContactHasNewCustomDisplayName.name
			case .newPersistedObvOwnedIdentity: return Name.newPersistedObvOwnedIdentity.name
			case .userWantsToRefreshContactGroupJoined: return Name.userWantsToRefreshContactGroupJoined.name
			case .currentOwnedCryptoIdChanged: return Name.currentOwnedCryptoIdChanged.name
			case .ownedIdentityWasDeactivated: return Name.ownedIdentityWasDeactivated.name
			case .ownedIdentityWasReactivated: return Name.ownedIdentityWasReactivated.name
			case .userWantsToPerfomCloudKitBackupNow: return Name.userWantsToPerfomCloudKitBackupNow.name
			case .externalTransactionsWereMergedIntoViewContext: return Name.externalTransactionsWereMergedIntoViewContext.name
			case .userWantsToPerfomBackupForExportNow: return Name.userWantsToPerfomBackupForExportNow.name
			case .newMessageExpiration: return Name.newMessageExpiration.name
			case .newMuteExpiration: return Name.newMuteExpiration.name
			case .wipeAllMessagesThatExpiredEarlierThanNow: return Name.wipeAllMessagesThatExpiredEarlierThanNow.name
			case .persistedMessageHasNewMetadata: return Name.persistedMessageHasNewMetadata.name
			case .fyleMessageJoinWithStatusHasNewProgress: return Name.fyleMessageJoinWithStatusHasNewProgress.name
			case .aViewRequiresFyleMessageJoinWithStatusProgresses: return Name.aViewRequiresFyleMessageJoinWithStatusProgresses.name
			case .userWantsToCallAndIsAllowedTo: return Name.userWantsToCallAndIsAllowedTo.name
			case .userWantsToSelectAndCallContacts: return Name.userWantsToSelectAndCallContacts.name
			case .userWantsToCallButWeShouldCheckSheIsAllowedTo: return Name.userWantsToCallButWeShouldCheckSheIsAllowedTo.name
			case .userWantsToKickParticipant: return Name.userWantsToKickParticipant.name
			case .userWantsToAddParticipants: return Name.userWantsToAddParticipants.name
			case .newWebRTCMessageWasReceived: return Name.newWebRTCMessageWasReceived.name
			case .callHasBeenUpdated: return Name.callHasBeenUpdated.name
			case .callParticipantHasBeenUpdated: return Name.callParticipantHasBeenUpdated.name
			case .toggleCallView: return Name.toggleCallView.name
			case .hideCallView: return Name.hideCallView.name
			case .newObvMessageWasReceivedViaPushKitNotification: return Name.newObvMessageWasReceivedViaPushKitNotification.name
			case .newWebRTCMessageToSend: return Name.newWebRTCMessageToSend.name
			case .isCallKitEnabledSettingDidChange: return Name.isCallKitEnabledSettingDidChange.name
			case .isIncludesCallsInRecentsEnabledSettingDidChange: return Name.isIncludesCallsInRecentsEnabledSettingDidChange.name
			case .networkInterfaceTypeChanged: return Name.networkInterfaceTypeChanged.name
			case .noMoreCallInProgress: return Name.noMoreCallInProgress.name
			case .appStateChanged: return Name.appStateChanged.name
			case .outgoingCallFailedBecauseUserDeniedRecordPermission: return Name.outgoingCallFailedBecauseUserDeniedRecordPermission.name
			case .voiceMessageFailedBecauseUserDeniedRecordPermission: return Name.voiceMessageFailedBecauseUserDeniedRecordPermission.name
			case .rejectedIncomingCallBecauseUserDeniedRecordPermission: return Name.rejectedIncomingCallBecauseUserDeniedRecordPermission.name
			case .userRequestedDeletionOfPersistedMessage: return Name.userRequestedDeletionOfPersistedMessage.name
			case .trashShouldBeEmptied: return Name.trashShouldBeEmptied.name
			case .userRequestedDeletionOfPersistedDiscussion: return Name.userRequestedDeletionOfPersistedDiscussion.name
			case .reportCallEvent: return Name.reportCallEvent.name
			case .newCallLogItem: return Name.newCallLogItem.name
			case .callLogItemWasUpdated: return Name.callLogItemWasUpdated.name
			case .userWantsToIntroduceContactToAnotherContact: return Name.userWantsToIntroduceContactToAnotherContact.name
			case .showCallViewControllerForAnsweringNonCallKitIncomingCall: return Name.showCallViewControllerForAnsweringNonCallKitIncomingCall.name
			case .userWantsToShareOwnPublishedDetails: return Name.userWantsToShareOwnPublishedDetails.name
			case .userWantsToSendInvite: return Name.userWantsToSendInvite.name
			case .userRequestedAPIKeyStatus: return Name.userRequestedAPIKeyStatus.name
			case .userRequestedNewAPIKeyActivation: return Name.userRequestedNewAPIKeyActivation.name
			case .userWantsToNavigateToDeepLink: return Name.userWantsToNavigateToDeepLink.name
			case .useLoadBalancedTurnServersDidChange: return Name.useLoadBalancedTurnServersDidChange.name
			case .userWantsToReadReceivedMessagesThatRequiresUserAction: return Name.userWantsToReadReceivedMessagesThatRequiresUserAction.name
			case .requestThumbnail: return Name.requestThumbnail.name
			case .persistedMessageReceivedWasRead: return Name.persistedMessageReceivedWasRead.name
			case .aReadOncePersistedMessageSentWasSent: return Name.aReadOncePersistedMessageSentWasSent.name
			case .userWantsToSetAndShareNewDiscussionSharedExpirationConfiguration: return Name.userWantsToSetAndShareNewDiscussionSharedExpirationConfiguration.name
			case .persistedDiscussionSharedConfigurationShouldBeSent: return Name.persistedDiscussionSharedConfigurationShouldBeSent.name
			case .userWantsToDeleteContact: return Name.userWantsToDeleteContact.name
			case .cleanExpiredMessagesBackgroundTaskWasLaunched: return Name.cleanExpiredMessagesBackgroundTaskWasLaunched.name
			case .applyRetentionPoliciesBackgroundTaskWasLaunched: return Name.applyRetentionPoliciesBackgroundTaskWasLaunched.name
			case .updateBadgeBackgroundTaskWasLaunched: return Name.updateBadgeBackgroundTaskWasLaunched.name
			case .applyAllRetentionPoliciesNow: return Name.applyAllRetentionPoliciesNow.name
			case .persistedMessageSystemWasDeleted: return Name.persistedMessageSystemWasDeleted.name
			case .anOldDiscussionSharedConfigurationWasReceived: return Name.anOldDiscussionSharedConfigurationWasReceived.name
			case .userWantsToSendEditedVersionOfSentMessage: return Name.userWantsToSendEditedVersionOfSentMessage.name
			case .theBodyOfPersistedMessageReceivedDidChange: return Name.theBodyOfPersistedMessageReceivedDidChange.name
			case .newProfilePictureCandidateToCache: return Name.newProfilePictureCandidateToCache.name
			case .newCachedProfilePictureCandidate: return Name.newCachedProfilePictureCandidate.name
			case .newCustomContactPictureCandidateToSave: return Name.newCustomContactPictureCandidateToSave.name
			case .newSavedCustomContactPictureCandidate: return Name.newSavedCustomContactPictureCandidate.name
			case .obvContactRequest: return Name.obvContactRequest.name
			case .obvContactAnswer: return Name.obvContactAnswer.name
			case .userWantsToMarkAllMessagesAsNotNewWithinDiscussion: return Name.userWantsToMarkAllMessagesAsNotNewWithinDiscussion.name
			case .resyncContactIdentityDevicesWithEngine: return Name.resyncContactIdentityDevicesWithEngine.name
			case .resyncContactIdentityDetailsStatusWithEngine: return Name.resyncContactIdentityDetailsStatusWithEngine.name
			case .serverDoesNotSuppoortCall: return Name.serverDoesNotSuppoortCall.name
			case .pastedStringIsNotValidOlvidURL: return Name.pastedStringIsNotValidOlvidURL.name
			case .serverDoesNotSupportCall: return Name.serverDoesNotSupportCall.name
			case .userWantsToRestartChannelEstablishmentProtocol: return Name.userWantsToRestartChannelEstablishmentProtocol.name
			case .userWantsToReCreateChannelEstablishmentProtocol: return Name.userWantsToReCreateChannelEstablishmentProtocol.name
			case .persistedContactHasNewStatus: return Name.persistedContactHasNewStatus.name
			case .contactIdentityDetailsWereUpdated: return Name.contactIdentityDetailsWereUpdated.name
			case .userDidSeeNewDetailsOfContact: return Name.userDidSeeNewDetailsOfContact.name
			case .userWantsToEditContactNicknameAndPicture: return Name.userWantsToEditContactNicknameAndPicture.name
			case .userWantsToBindOwnedIdentityToKeycloak: return Name.userWantsToBindOwnedIdentityToKeycloak.name
			case .userWantsToUnbindOwnedIdentityFromKeycloak: return Name.userWantsToUnbindOwnedIdentityFromKeycloak.name
			case .requestHardLinkToFyle: return Name.requestHardLinkToFyle.name
			case .requestAllHardLinksToFyles: return Name.requestAllHardLinksToFyles.name
			case .persistedDiscussionWasDeleted: return Name.persistedDiscussionWasDeleted.name
			case .newLockedPersistedDiscussion: return Name.newLockedPersistedDiscussion.name
			case .persistedMessagesWereDeleted: return Name.persistedMessagesWereDeleted.name
			case .persistedMessagesWereWiped: return Name.persistedMessagesWereWiped.name
			case .draftToSendWasReset: return Name.draftToSendWasReset.name
			case .draftFyleJoinWasDeleted: return Name.draftFyleJoinWasDeleted.name
			case .shareExtensionExtensionContextWillCompleteRequest: return Name.shareExtensionExtensionContextWillCompleteRequest.name
			case .userWantsToRemoveDraftFyleJoin: return Name.userWantsToRemoveDraftFyleJoin.name
			case .AppInitializationEnded: return Name.AppInitializationEnded.name
			case .userWantsToChangeContactsSortOrder: return Name.userWantsToChangeContactsSortOrder.name
			case .contactsSortOrderDidChange: return Name.contactsSortOrderDidChange.name
			case .identityColorStyleDidChange: return Name.identityColorStyleDidChange.name
			case .userWantsToUpdateDiscussionLocalConfiguration: return Name.userWantsToUpdateDiscussionLocalConfiguration.name
			case .userWantsToUpdateLocalConfigurationOfDiscussion: return Name.userWantsToUpdateLocalConfigurationOfDiscussion.name
			case .discussionLocalConfigurationHasBeenUpdated: return Name.discussionLocalConfigurationHasBeenUpdated.name
			case .audioInputHasBeenActivated: return Name.audioInputHasBeenActivated.name
			case .aViewRequiresObvMutualScanUrl: return Name.aViewRequiresObvMutualScanUrl.name
			case .userWantsToStartTrustEstablishmentWithMutualScanProtocol: return Name.userWantsToStartTrustEstablishmentWithMutualScanProtocol.name
			case .insertDebugMessagesInAllExistingDiscussions: return Name.insertDebugMessagesInAllExistingDiscussions.name
			case .draftExpirationWasBeenUpdated: return Name.draftExpirationWasBeenUpdated.name
			case .badgesNeedToBeUpdated: return Name.badgesNeedToBeUpdated.name
			case .cleanExpiredMuteNotficationsThatExpiredEarlierThanNow: return Name.cleanExpiredMuteNotficationsThatExpiredEarlierThanNow.name
			case .needToRecomputeAllBadges: return Name.needToRecomputeAllBadges.name
			case .userWantsToDisplayContactIntroductionScreen: return Name.userWantsToDisplayContactIntroductionScreen.name
			case .userDidTapOnMissedMessageBubble: return Name.userDidTapOnMissedMessageBubble.name
			case .olvidSnackBarShouldBeShown: return Name.olvidSnackBarShouldBeShown.name
			case .UserWantsToSeeDetailedExplanationsOfSnackBar: return Name.UserWantsToSeeDetailedExplanationsOfSnackBar.name
			case .UserDismissedSnackBarForLater: return Name.UserDismissedSnackBarForLater.name
			case .UserRequestedToResetAllAlerts: return Name.UserRequestedToResetAllAlerts.name
			case .olvidSnackBarShouldBeHidden: return Name.olvidSnackBarShouldBeHidden.name
			case .userWantsToUpdateReaction: return Name.userWantsToUpdateReaction.name
			case .currentUserActivityDidChange: return Name.currentUserActivityDidChange.name
			case .displayedSnackBarShouldBeRefreshed: return Name.displayedSnackBarShouldBeRefreshed.name
			case .requestUserDeniedRecordPermissionAlert: return Name.requestUserDeniedRecordPermissionAlert.name
			case .incrementalCleanBackupStarts: return Name.incrementalCleanBackupStarts.name
			case .incrementalCleanBackupInProgress: return Name.incrementalCleanBackupInProgress.name
			case .incrementalCleanBackupTerminates: return Name.incrementalCleanBackupTerminates.name
			case .userWantsToUnblockContact: return Name.userWantsToUnblockContact.name
			case .userWantsToReblockContact: return Name.userWantsToReblockContact.name
			case .persistedContactIsActiveChanged: return Name.persistedContactIsActiveChanged.name
			case .installedOlvidAppIsOutdated: return Name.installedOlvidAppIsOutdated.name
			case .userOwnedIdentityWasRevokedByKeycloak: return Name.userOwnedIdentityWasRevokedByKeycloak.name
			case .aOneToOneDiscussionTitleNeedsToBeReset: return Name.aOneToOneDiscussionTitleNeedsToBeReset.name
			case .uiRequiresSignedContactDetails: return Name.uiRequiresSignedContactDetails.name
			case .preferredComposeMessageViewActionsDidChange: return Name.preferredComposeMessageViewActionsDidChange.name
			case .requestSyncAppDatabasesWithEngine: return Name.requestSyncAppDatabasesWithEngine.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .messagesAreNotNewAnymore(persistedMessageObjectIDs: let persistedMessageObjectIDs):
			info = [
				"persistedMessageObjectIDs": persistedMessageObjectIDs,
			]
		case .persistedContactGroupHasUpdatedContactIdentities(persistedContactGroupObjectID: let persistedContactGroupObjectID, insertedContacts: let insertedContacts, removedContacts: let removedContacts):
			info = [
				"persistedContactGroupObjectID": persistedContactGroupObjectID,
				"insertedContacts": insertedContacts,
				"removedContacts": removedContacts,
			]
		case .persistedDiscussionHasNewTitle(objectID: let objectID, title: let title):
			info = [
				"objectID": objectID,
				"title": title,
			]
		case .newDraftToSend(persistedDraftObjectID: let persistedDraftObjectID):
			info = [
				"persistedDraftObjectID": persistedDraftObjectID,
			]
		case .draftWasSent(persistedDraftObjectID: let persistedDraftObjectID):
			info = [
				"persistedDraftObjectID": persistedDraftObjectID,
			]
		case .newOrUpdatedPersistedInvitation(obvDialog: let obvDialog, persistedInvitationUUID: let persistedInvitationUUID):
			info = [
				"obvDialog": obvDialog,
				"persistedInvitationUUID": persistedInvitationUUID,
			]
		case .persistedMessageReceivedWasDeleted(objectID: let objectID, messageIdentifierFromEngine: let messageIdentifierFromEngine, ownedCryptoId: let ownedCryptoId, sortIndex: let sortIndex, discussionObjectID: let discussionObjectID):
			info = [
				"objectID": objectID,
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
				"ownedCryptoId": ownedCryptoId,
				"sortIndex": sortIndex,
				"discussionObjectID": discussionObjectID,
			]
		case .newPersistedObvContactDevice(contactDeviceObjectID: let contactDeviceObjectID, contactCryptoId: let contactCryptoId):
			info = [
				"contactDeviceObjectID": contactDeviceObjectID,
				"contactCryptoId": contactCryptoId,
			]
		case .deletedPersistedObvContactDevice(contactCryptoId: let contactCryptoId):
			info = [
				"contactCryptoId": contactCryptoId,
			]
		case .persistedContactWasInserted(objectID: let objectID, contactCryptoId: let contactCryptoId):
			info = [
				"objectID": objectID,
				"contactCryptoId": contactCryptoId,
			]
		case .persistedContactWasDeleted(objectID: let objectID, identity: let identity):
			info = [
				"objectID": objectID,
				"identity": identity,
			]
		case .persistedContactHasNewCustomDisplayName(contactCryptoId: let contactCryptoId):
			info = [
				"contactCryptoId": contactCryptoId,
			]
		case .newPersistedObvOwnedIdentity(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
			]
		case .userWantsToRefreshContactGroupJoined(obvContactGroup: let obvContactGroup):
			info = [
				"obvContactGroup": obvContactGroup,
			]
		case .currentOwnedCryptoIdChanged(newOwnedCryptoId: let newOwnedCryptoId, apiKey: let apiKey):
			info = [
				"newOwnedCryptoId": newOwnedCryptoId,
				"apiKey": apiKey,
			]
		case .ownedIdentityWasDeactivated(ownedIdentityObjectID: let ownedIdentityObjectID):
			info = [
				"ownedIdentityObjectID": ownedIdentityObjectID,
			]
		case .ownedIdentityWasReactivated(ownedIdentityObjectID: let ownedIdentityObjectID):
			info = [
				"ownedIdentityObjectID": ownedIdentityObjectID,
			]
		case .userWantsToPerfomCloudKitBackupNow:
			info = nil
		case .externalTransactionsWereMergedIntoViewContext:
			info = nil
		case .userWantsToPerfomBackupForExportNow(sourceView: let sourceView):
			info = [
				"sourceView": sourceView,
			]
		case .newMessageExpiration(expirationDate: let expirationDate):
			info = [
				"expirationDate": expirationDate,
			]
		case .newMuteExpiration(expirationDate: let expirationDate):
			info = [
				"expirationDate": expirationDate,
			]
		case .wipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask: let launchedByBackgroundTask, completionHandler: let completionHandler):
			info = [
				"launchedByBackgroundTask": launchedByBackgroundTask,
				"completionHandler": completionHandler,
			]
		case .persistedMessageHasNewMetadata(persistedMessageObjectID: let persistedMessageObjectID):
			info = [
				"persistedMessageObjectID": persistedMessageObjectID,
			]
		case .fyleMessageJoinWithStatusHasNewProgress(objectID: let objectID, progress: let progress):
			info = [
				"objectID": objectID,
				"progress": progress,
			]
		case .aViewRequiresFyleMessageJoinWithStatusProgresses(objectIDs: let objectIDs):
			info = [
				"objectIDs": objectIDs,
			]
		case .userWantsToCallAndIsAllowedTo(contactIDs: let contactIDs, groupId: let groupId):
			info = [
				"contactIDs": contactIDs,
				"groupId": OptionalWrapper(groupId),
			]
		case .userWantsToSelectAndCallContacts(contactIDs: let contactIDs, groupId: let groupId):
			info = [
				"contactIDs": contactIDs,
				"groupId": OptionalWrapper(groupId),
			]
		case .userWantsToCallButWeShouldCheckSheIsAllowedTo(contactIDs: let contactIDs, groupId: let groupId):
			info = [
				"contactIDs": contactIDs,
				"groupId": OptionalWrapper(groupId),
			]
		case .userWantsToKickParticipant(call: let call, callParticipant: let callParticipant):
			info = [
				"call": call,
				"callParticipant": callParticipant,
			]
		case .userWantsToAddParticipants(call: let call, contactIDs: let contactIDs):
			info = [
				"call": call,
				"contactIDs": contactIDs,
			]
		case .newWebRTCMessageWasReceived(webrtcMessage: let webrtcMessage, contactID: let contactID, messageUploadTimestampFromServer: let messageUploadTimestampFromServer, messageIdentifierFromEngine: let messageIdentifierFromEngine):
			info = [
				"webrtcMessage": webrtcMessage,
				"contactID": contactID,
				"messageUploadTimestampFromServer": messageUploadTimestampFromServer,
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
			]
		case .callHasBeenUpdated(call: let call, updateKind: let updateKind):
			info = [
				"call": call,
				"updateKind": updateKind,
			]
		case .callParticipantHasBeenUpdated(callParticipant: let callParticipant, updateKind: let updateKind):
			info = [
				"callParticipant": callParticipant,
				"updateKind": updateKind,
			]
		case .toggleCallView:
			info = nil
		case .hideCallView:
			info = nil
		case .newObvMessageWasReceivedViaPushKitNotification(obvMessage: let obvMessage):
			info = [
				"obvMessage": obvMessage,
			]
		case .newWebRTCMessageToSend(webrtcMessage: let webrtcMessage, contactID: let contactID, forStartingCall: let forStartingCall, completion: let completion):
			info = [
				"webrtcMessage": webrtcMessage,
				"contactID": contactID,
				"forStartingCall": forStartingCall,
				"completion": completion,
			]
		case .isCallKitEnabledSettingDidChange:
			info = nil
		case .isIncludesCallsInRecentsEnabledSettingDidChange:
			info = nil
		case .networkInterfaceTypeChanged(isConnected: let isConnected):
			info = [
				"isConnected": isConnected,
			]
		case .noMoreCallInProgress:
			info = nil
		case .appStateChanged(previousState: let previousState, currentState: let currentState):
			info = [
				"previousState": previousState,
				"currentState": currentState,
			]
		case .outgoingCallFailedBecauseUserDeniedRecordPermission:
			info = nil
		case .voiceMessageFailedBecauseUserDeniedRecordPermission:
			info = nil
		case .rejectedIncomingCallBecauseUserDeniedRecordPermission:
			info = nil
		case .userRequestedDeletionOfPersistedMessage(persistedMessageObjectID: let persistedMessageObjectID, deletionType: let deletionType):
			info = [
				"persistedMessageObjectID": persistedMessageObjectID,
				"deletionType": deletionType,
			]
		case .trashShouldBeEmptied:
			info = nil
		case .userRequestedDeletionOfPersistedDiscussion(persistedDiscussionObjectID: let persistedDiscussionObjectID, deletionType: let deletionType, completionHandler: let completionHandler):
			info = [
				"persistedDiscussionObjectID": persistedDiscussionObjectID,
				"deletionType": deletionType,
				"completionHandler": completionHandler,
			]
		case .reportCallEvent(callUUID: let callUUID, callReport: let callReport, groupId: let groupId, ownedCryptoId: let ownedCryptoId):
			info = [
				"callUUID": callUUID,
				"callReport": callReport,
				"groupId": OptionalWrapper(groupId),
				"ownedCryptoId": ownedCryptoId,
			]
		case .newCallLogItem(objectID: let objectID):
			info = [
				"objectID": objectID,
			]
		case .callLogItemWasUpdated(objectID: let objectID):
			info = [
				"objectID": objectID,
			]
		case .userWantsToIntroduceContactToAnotherContact(ownedCryptoId: let ownedCryptoId, firstContactCryptoId: let firstContactCryptoId, secondContactCryptoIds: let secondContactCryptoIds):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"firstContactCryptoId": firstContactCryptoId,
				"secondContactCryptoIds": secondContactCryptoIds,
			]
		case .showCallViewControllerForAnsweringNonCallKitIncomingCall(incomingCall: let incomingCall):
			info = [
				"incomingCall": incomingCall,
			]
		case .userWantsToShareOwnPublishedDetails(ownedCryptoId: let ownedCryptoId, sourceView: let sourceView):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"sourceView": sourceView,
			]
		case .userWantsToSendInvite(ownedIdentity: let ownedIdentity, urlIdentity: let urlIdentity):
			info = [
				"ownedIdentity": ownedIdentity,
				"urlIdentity": urlIdentity,
			]
		case .userRequestedAPIKeyStatus(ownedCryptoId: let ownedCryptoId, apiKey: let apiKey):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"apiKey": apiKey,
			]
		case .userRequestedNewAPIKeyActivation(ownedCryptoId: let ownedCryptoId, apiKey: let apiKey):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"apiKey": apiKey,
			]
		case .userWantsToNavigateToDeepLink(deepLink: let deepLink):
			info = [
				"deepLink": deepLink,
			]
		case .useLoadBalancedTurnServersDidChange:
			info = nil
		case .userWantsToReadReceivedMessagesThatRequiresUserAction(persistedMessageObjectIDs: let persistedMessageObjectIDs):
			info = [
				"persistedMessageObjectIDs": persistedMessageObjectIDs,
			]
		case .requestThumbnail(fyleElement: let fyleElement, size: let size, thumbnailType: let thumbnailType, completionHandler: let completionHandler):
			info = [
				"fyleElement": fyleElement,
				"size": size,
				"thumbnailType": thumbnailType,
				"completionHandler": completionHandler,
			]
		case .persistedMessageReceivedWasRead(persistedMessageReceivedObjectID: let persistedMessageReceivedObjectID):
			info = [
				"persistedMessageReceivedObjectID": persistedMessageReceivedObjectID,
			]
		case .aReadOncePersistedMessageSentWasSent(persistedMessageSentObjectID: let persistedMessageSentObjectID, persistedDiscussionObjectID: let persistedDiscussionObjectID):
			info = [
				"persistedMessageSentObjectID": persistedMessageSentObjectID,
				"persistedDiscussionObjectID": persistedDiscussionObjectID,
			]
		case .userWantsToSetAndShareNewDiscussionSharedExpirationConfiguration(persistedDiscussionObjectID: let persistedDiscussionObjectID, expirationJSON: let expirationJSON, ownedCryptoId: let ownedCryptoId):
			info = [
				"persistedDiscussionObjectID": persistedDiscussionObjectID,
				"expirationJSON": expirationJSON,
				"ownedCryptoId": ownedCryptoId,
			]
		case .persistedDiscussionSharedConfigurationShouldBeSent(persistedDiscussionObjectID: let persistedDiscussionObjectID):
			info = [
				"persistedDiscussionObjectID": persistedDiscussionObjectID,
			]
		case .userWantsToDeleteContact(contactCryptoId: let contactCryptoId, ownedCryptoId: let ownedCryptoId, viewController: let viewController, completionHandler: let completionHandler):
			info = [
				"contactCryptoId": contactCryptoId,
				"ownedCryptoId": ownedCryptoId,
				"viewController": viewController,
				"completionHandler": completionHandler,
			]
		case .cleanExpiredMessagesBackgroundTaskWasLaunched(completionHandler: let completionHandler):
			info = [
				"completionHandler": completionHandler,
			]
		case .applyRetentionPoliciesBackgroundTaskWasLaunched(completionHandler: let completionHandler):
			info = [
				"completionHandler": completionHandler,
			]
		case .updateBadgeBackgroundTaskWasLaunched(completionHandler: let completionHandler):
			info = [
				"completionHandler": completionHandler,
			]
		case .applyAllRetentionPoliciesNow(launchedByBackgroundTask: let launchedByBackgroundTask, completionHandler: let completionHandler):
			info = [
				"launchedByBackgroundTask": launchedByBackgroundTask,
				"completionHandler": completionHandler,
			]
		case .persistedMessageSystemWasDeleted(objectID: let objectID, discussionObjectID: let discussionObjectID):
			info = [
				"objectID": objectID,
				"discussionObjectID": discussionObjectID,
			]
		case .anOldDiscussionSharedConfigurationWasReceived(persistedDiscussionObjectID: let persistedDiscussionObjectID):
			info = [
				"persistedDiscussionObjectID": persistedDiscussionObjectID,
			]
		case .userWantsToSendEditedVersionOfSentMessage(sentMessageObjectID: let sentMessageObjectID, newTextBody: let newTextBody):
			info = [
				"sentMessageObjectID": sentMessageObjectID,
				"newTextBody": newTextBody,
			]
		case .theBodyOfPersistedMessageReceivedDidChange(persistedMessageReceivedObjectID: let persistedMessageReceivedObjectID):
			info = [
				"persistedMessageReceivedObjectID": persistedMessageReceivedObjectID,
			]
		case .newProfilePictureCandidateToCache(requestUUID: let requestUUID, profilePicture: let profilePicture):
			info = [
				"requestUUID": requestUUID,
				"profilePicture": profilePicture,
			]
		case .newCachedProfilePictureCandidate(requestUUID: let requestUUID, url: let url):
			info = [
				"requestUUID": requestUUID,
				"url": url,
			]
		case .newCustomContactPictureCandidateToSave(requestUUID: let requestUUID, profilePicture: let profilePicture):
			info = [
				"requestUUID": requestUUID,
				"profilePicture": profilePicture,
			]
		case .newSavedCustomContactPictureCandidate(requestUUID: let requestUUID, url: let url):
			info = [
				"requestUUID": requestUUID,
				"url": url,
			]
		case .obvContactRequest(requestUUID: let requestUUID, contactCryptoId: let contactCryptoId, ownedCryptoId: let ownedCryptoId):
			info = [
				"requestUUID": requestUUID,
				"contactCryptoId": contactCryptoId,
				"ownedCryptoId": ownedCryptoId,
			]
		case .obvContactAnswer(requestUUID: let requestUUID, obvContact: let obvContact):
			info = [
				"requestUUID": requestUUID,
				"obvContact": obvContact,
			]
		case .userWantsToMarkAllMessagesAsNotNewWithinDiscussion(persistedDiscussionObjectID: let persistedDiscussionObjectID, completionHandler: let completionHandler):
			info = [
				"persistedDiscussionObjectID": persistedDiscussionObjectID,
				"completionHandler": completionHandler,
			]
		case .resyncContactIdentityDevicesWithEngine(contactCryptoId: let contactCryptoId, ownedCryptoId: let ownedCryptoId):
			info = [
				"contactCryptoId": contactCryptoId,
				"ownedCryptoId": ownedCryptoId,
			]
		case .resyncContactIdentityDetailsStatusWithEngine(contactCryptoId: let contactCryptoId, ownedCryptoId: let ownedCryptoId):
			info = [
				"contactCryptoId": contactCryptoId,
				"ownedCryptoId": ownedCryptoId,
			]
		case .serverDoesNotSuppoortCall:
			info = nil
		case .pastedStringIsNotValidOlvidURL:
			info = nil
		case .serverDoesNotSupportCall:
			info = nil
		case .userWantsToRestartChannelEstablishmentProtocol(contactCryptoId: let contactCryptoId, ownedCryptoId: let ownedCryptoId):
			info = [
				"contactCryptoId": contactCryptoId,
				"ownedCryptoId": ownedCryptoId,
			]
		case .userWantsToReCreateChannelEstablishmentProtocol(contactCryptoId: let contactCryptoId, ownedCryptoId: let ownedCryptoId):
			info = [
				"contactCryptoId": contactCryptoId,
				"ownedCryptoId": ownedCryptoId,
			]
		case .persistedContactHasNewStatus(contactCryptoId: let contactCryptoId, ownedCryptoId: let ownedCryptoId):
			info = [
				"contactCryptoId": contactCryptoId,
				"ownedCryptoId": ownedCryptoId,
			]
		case .contactIdentityDetailsWereUpdated(contactCryptoId: let contactCryptoId, ownedCryptoId: let ownedCryptoId):
			info = [
				"contactCryptoId": contactCryptoId,
				"ownedCryptoId": ownedCryptoId,
			]
		case .userDidSeeNewDetailsOfContact(contactCryptoId: let contactCryptoId, ownedCryptoId: let ownedCryptoId):
			info = [
				"contactCryptoId": contactCryptoId,
				"ownedCryptoId": ownedCryptoId,
			]
		case .userWantsToEditContactNicknameAndPicture(persistedContactObjectID: let persistedContactObjectID, nicknameAndPicture: let nicknameAndPicture):
			info = [
				"persistedContactObjectID": persistedContactObjectID,
				"nicknameAndPicture": nicknameAndPicture,
			]
		case .userWantsToBindOwnedIdentityToKeycloak(ownedCryptoId: let ownedCryptoId, obvKeycloakState: let obvKeycloakState, keycloakUserId: let keycloakUserId, completionHandler: let completionHandler):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"obvKeycloakState": obvKeycloakState,
				"keycloakUserId": keycloakUserId,
				"completionHandler": completionHandler,
			]
		case .userWantsToUnbindOwnedIdentityFromKeycloak(ownedCryptoId: let ownedCryptoId, completionHandler: let completionHandler):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"completionHandler": completionHandler,
			]
		case .requestHardLinkToFyle(fyleElement: let fyleElement, completionHandler: let completionHandler):
			info = [
				"fyleElement": fyleElement,
				"completionHandler": completionHandler,
			]
		case .requestAllHardLinksToFyles(fyleElements: let fyleElements, completionHandler: let completionHandler):
			info = [
				"fyleElements": fyleElements,
				"completionHandler": completionHandler,
			]
		case .persistedDiscussionWasDeleted(discussionUriRepresentation: let discussionUriRepresentation):
			info = [
				"discussionUriRepresentation": discussionUriRepresentation,
			]
		case .newLockedPersistedDiscussion(previousDiscussionUriRepresentation: let previousDiscussionUriRepresentation, newLockedDiscussionId: let newLockedDiscussionId):
			info = [
				"previousDiscussionUriRepresentation": previousDiscussionUriRepresentation,
				"newLockedDiscussionId": newLockedDiscussionId,
			]
		case .persistedMessagesWereDeleted(discussionUriRepresentation: let discussionUriRepresentation, messageUriRepresentations: let messageUriRepresentations):
			info = [
				"discussionUriRepresentation": discussionUriRepresentation,
				"messageUriRepresentations": messageUriRepresentations,
			]
		case .persistedMessagesWereWiped(discussionUriRepresentation: let discussionUriRepresentation, messageUriRepresentations: let messageUriRepresentations):
			info = [
				"discussionUriRepresentation": discussionUriRepresentation,
				"messageUriRepresentations": messageUriRepresentations,
			]
		case .draftToSendWasReset(discussionObjectID: let discussionObjectID, draftObjectID: let draftObjectID):
			info = [
				"discussionObjectID": discussionObjectID,
				"draftObjectID": draftObjectID,
			]
		case .draftFyleJoinWasDeleted(discussionUriRepresentation: let discussionUriRepresentation, draftUriRepresentation: let draftUriRepresentation, draftFyleJoinUriRepresentation: let draftFyleJoinUriRepresentation):
			info = [
				"discussionUriRepresentation": discussionUriRepresentation,
				"draftUriRepresentation": draftUriRepresentation,
				"draftFyleJoinUriRepresentation": draftFyleJoinUriRepresentation,
			]
		case .shareExtensionExtensionContextWillCompleteRequest:
			info = nil
		case .userWantsToRemoveDraftFyleJoin(draftFyleJoinObjectID: let draftFyleJoinObjectID):
			info = [
				"draftFyleJoinObjectID": draftFyleJoinObjectID,
			]
		case .AppInitializationEnded:
			info = nil
		case .userWantsToChangeContactsSortOrder(ownedCryptoId: let ownedCryptoId, sortOrder: let sortOrder):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"sortOrder": sortOrder,
			]
		case .contactsSortOrderDidChange:
			info = nil
		case .identityColorStyleDidChange:
			info = nil
		case .userWantsToUpdateDiscussionLocalConfiguration(value: let value, localConfigurationObjectID: let localConfigurationObjectID):
			info = [
				"value": value,
				"localConfigurationObjectID": localConfigurationObjectID,
			]
		case .userWantsToUpdateLocalConfigurationOfDiscussion(value: let value, persistedDiscussionObjectID: let persistedDiscussionObjectID):
			info = [
				"value": value,
				"persistedDiscussionObjectID": persistedDiscussionObjectID,
			]
		case .discussionLocalConfigurationHasBeenUpdated(newValue: let newValue, localConfigurationObjectID: let localConfigurationObjectID):
			info = [
				"newValue": newValue,
				"localConfigurationObjectID": localConfigurationObjectID,
			]
		case .audioInputHasBeenActivated(label: let label, activate: let activate):
			info = [
				"label": label,
				"activate": activate,
			]
		case .aViewRequiresObvMutualScanUrl(remoteIdentity: let remoteIdentity, ownedCryptoId: let ownedCryptoId, completionHandler: let completionHandler):
			info = [
				"remoteIdentity": remoteIdentity,
				"ownedCryptoId": ownedCryptoId,
				"completionHandler": completionHandler,
			]
		case .userWantsToStartTrustEstablishmentWithMutualScanProtocol(ownedCryptoId: let ownedCryptoId, mutualScanUrl: let mutualScanUrl):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"mutualScanUrl": mutualScanUrl,
			]
		case .insertDebugMessagesInAllExistingDiscussions:
			info = nil
		case .draftExpirationWasBeenUpdated(persistedDraftObjectID: let persistedDraftObjectID):
			info = [
				"persistedDraftObjectID": persistedDraftObjectID,
			]
		case .badgesNeedToBeUpdated(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
			]
		case .cleanExpiredMuteNotficationsThatExpiredEarlierThanNow:
			info = nil
		case .needToRecomputeAllBadges:
			info = nil
		case .userWantsToDisplayContactIntroductionScreen(contactObjectID: let contactObjectID, viewController: let viewController):
			info = [
				"contactObjectID": contactObjectID,
				"viewController": viewController,
			]
		case .userDidTapOnMissedMessageBubble:
			info = nil
		case .olvidSnackBarShouldBeShown(ownedCryptoId: let ownedCryptoId, snackBarCategory: let snackBarCategory):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"snackBarCategory": snackBarCategory,
			]
		case .UserWantsToSeeDetailedExplanationsOfSnackBar(ownedCryptoId: let ownedCryptoId, snackBarCategory: let snackBarCategory):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"snackBarCategory": snackBarCategory,
			]
		case .UserDismissedSnackBarForLater(ownedCryptoId: let ownedCryptoId, snackBarCategory: let snackBarCategory):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"snackBarCategory": snackBarCategory,
			]
		case .UserRequestedToResetAllAlerts:
			info = nil
		case .olvidSnackBarShouldBeHidden(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
			]
		case .userWantsToUpdateReaction(messageObjectID: let messageObjectID, emoji: let emoji):
			info = [
				"messageObjectID": messageObjectID,
				"emoji": OptionalWrapper(emoji),
			]
		case .currentUserActivityDidChange(previousUserActivity: let previousUserActivity, currentUserActivity: let currentUserActivity):
			info = [
				"previousUserActivity": previousUserActivity,
				"currentUserActivity": currentUserActivity,
			]
		case .displayedSnackBarShouldBeRefreshed:
			info = nil
		case .requestUserDeniedRecordPermissionAlert:
			info = nil
		case .incrementalCleanBackupStarts(initialCount: let initialCount):
			info = [
				"initialCount": initialCount,
			]
		case .incrementalCleanBackupInProgress(currentCount: let currentCount, cleanAllDevices: let cleanAllDevices):
			info = [
				"currentCount": currentCount,
				"cleanAllDevices": cleanAllDevices,
			]
		case .incrementalCleanBackupTerminates(totalCount: let totalCount):
			info = [
				"totalCount": totalCount,
			]
		case .userWantsToUnblockContact(ownedCryptoId: let ownedCryptoId, contactCryptoId: let contactCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"contactCryptoId": contactCryptoId,
			]
		case .userWantsToReblockContact(ownedCryptoId: let ownedCryptoId, contactCryptoId: let contactCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"contactCryptoId": contactCryptoId,
			]
		case .persistedContactIsActiveChanged(contactID: let contactID):
			info = [
				"contactID": contactID,
			]
		case .installedOlvidAppIsOutdated(presentingViewController: let presentingViewController):
			info = [
				"presentingViewController": OptionalWrapper(presentingViewController),
			]
		case .userOwnedIdentityWasRevokedByKeycloak(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
			]
		case .aOneToOneDiscussionTitleNeedsToBeReset(ownedIdentityObjectID: let ownedIdentityObjectID):
			info = [
				"ownedIdentityObjectID": ownedIdentityObjectID,
			]
		case .uiRequiresSignedContactDetails(ownedIdentityCryptoId: let ownedIdentityCryptoId, contactCryptoId: let contactCryptoId, completion: let completion):
			info = [
				"ownedIdentityCryptoId": ownedIdentityCryptoId,
				"contactCryptoId": contactCryptoId,
				"completion": completion,
			]
		case .preferredComposeMessageViewActionsDidChange:
			info = nil
		case .requestSyncAppDatabasesWithEngine(completion: let completion):
			info = [
				"completion": completion,
			]
		}
		return info
	}

	func post(object anObject: Any? = nil) {
		let name = Name.forInternalNotification(self)
		NotificationCenter.default.post(name: name, object: anObject, userInfo: userInfo)
	}

	func postOnDispatchQueue(object anObject: Any? = nil) {
		let name = Name.forInternalNotification(self)
		postOnDispatchQueue(withLabel: "Queue for posting \(name.rawValue) notification", object: anObject)
	}

	func postOnDispatchQueue(_ queue: DispatchQueue) {
		let name = Name.forInternalNotification(self)
		queue.async {
			NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
		}
	}

	private func postOnDispatchQueue(withLabel label: String, object anObject: Any? = nil) {
		let name = Name.forInternalNotification(self)
		let userInfo = self.userInfo
		DispatchQueue(label: label).async {
			NotificationCenter.default.post(name: name, object: anObject, userInfo: userInfo)
		}
	}

	static func observeMessagesAreNotNewAnymore(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Set<TypeSafeManagedObjectID<PersistedMessage>>) -> Void) -> NSObjectProtocol {
		let name = Name.messagesAreNotNewAnymore.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedMessageObjectIDs = notification.userInfo!["persistedMessageObjectIDs"] as! Set<TypeSafeManagedObjectID<PersistedMessage>>
			block(persistedMessageObjectIDs)
		}
	}

	static func observePersistedContactGroupHasUpdatedContactIdentities(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, Set<PersistedObvContactIdentity>, Set<PersistedObvContactIdentity>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactGroupHasUpdatedContactIdentities.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedContactGroupObjectID = notification.userInfo!["persistedContactGroupObjectID"] as! NSManagedObjectID
			let insertedContacts = notification.userInfo!["insertedContacts"] as! Set<PersistedObvContactIdentity>
			let removedContacts = notification.userInfo!["removedContacts"] as! Set<PersistedObvContactIdentity>
			block(persistedContactGroupObjectID, insertedContacts, removedContacts)
		}
	}

	static func observePersistedDiscussionHasNewTitle(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDiscussion>, String) -> Void) -> NSObjectProtocol {
		let name = Name.persistedDiscussionHasNewTitle.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			let title = notification.userInfo!["title"] as! String
			block(objectID, title)
		}
	}

	static func observeNewDraftToSend(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDraft>) -> Void) -> NSObjectProtocol {
		let name = Name.newDraftToSend.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedDraftObjectID = notification.userInfo!["persistedDraftObjectID"] as! TypeSafeManagedObjectID<PersistedDraft>
			block(persistedDraftObjectID)
		}
	}

	static func observeDraftWasSent(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDraft>) -> Void) -> NSObjectProtocol {
		let name = Name.draftWasSent.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedDraftObjectID = notification.userInfo!["persistedDraftObjectID"] as! TypeSafeManagedObjectID<PersistedDraft>
			block(persistedDraftObjectID)
		}
	}

	static func observeNewOrUpdatedPersistedInvitation(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvDialog, UUID) -> Void) -> NSObjectProtocol {
		let name = Name.newOrUpdatedPersistedInvitation.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let obvDialog = notification.userInfo!["obvDialog"] as! ObvDialog
			let persistedInvitationUUID = notification.userInfo!["persistedInvitationUUID"] as! UUID
			block(obvDialog, persistedInvitationUUID)
		}
	}

	static func observePersistedMessageReceivedWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, Data, ObvCryptoId, Double, TypeSafeManagedObjectID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageReceivedWasDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! NSManagedObjectID
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let sortIndex = notification.userInfo!["sortIndex"] as! Double
			let discussionObjectID = notification.userInfo!["discussionObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			block(objectID, messageIdentifierFromEngine, ownedCryptoId, sortIndex, discussionObjectID)
		}
	}

	static func observeNewPersistedObvContactDevice(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.newPersistedObvContactDevice.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactDeviceObjectID = notification.userInfo!["contactDeviceObjectID"] as! NSManagedObjectID
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			block(contactDeviceObjectID, contactCryptoId)
		}
	}

	static func observeDeletedPersistedObvContactDevice(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.deletedPersistedObvContactDevice.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			block(contactCryptoId)
		}
	}

	static func observePersistedContactWasInserted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactWasInserted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! NSManagedObjectID
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			block(objectID, contactCryptoId)
		}
	}

	static func observePersistedContactWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, Data) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactWasDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! NSManagedObjectID
			let identity = notification.userInfo!["identity"] as! Data
			block(objectID, identity)
		}
	}

	static func observePersistedContactHasNewCustomDisplayName(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactHasNewCustomDisplayName.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			block(contactCryptoId)
		}
	}

	static func observeNewPersistedObvOwnedIdentity(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.newPersistedObvOwnedIdentity.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(ownedCryptoId)
		}
	}

	static func observeUserWantsToRefreshContactGroupJoined(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvContactGroup) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToRefreshContactGroupJoined.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let obvContactGroup = notification.userInfo!["obvContactGroup"] as! ObvContactGroup
			block(obvContactGroup)
		}
	}

	static func observeCurrentOwnedCryptoIdChanged(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, UUID) -> Void) -> NSObjectProtocol {
		let name = Name.currentOwnedCryptoIdChanged.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let newOwnedCryptoId = notification.userInfo!["newOwnedCryptoId"] as! ObvCryptoId
			let apiKey = notification.userInfo!["apiKey"] as! UUID
			block(newOwnedCryptoId, apiKey)
		}
	}

	static func observeOwnedIdentityWasDeactivated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityWasDeactivated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedIdentityObjectID = notification.userInfo!["ownedIdentityObjectID"] as! NSManagedObjectID
			block(ownedIdentityObjectID)
		}
	}

	static func observeOwnedIdentityWasReactivated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID) -> Void) -> NSObjectProtocol {
		let name = Name.ownedIdentityWasReactivated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedIdentityObjectID = notification.userInfo!["ownedIdentityObjectID"] as! NSManagedObjectID
			block(ownedIdentityObjectID)
		}
	}

	static func observeUserWantsToPerfomCloudKitBackupNow(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToPerfomCloudKitBackupNow.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeExternalTransactionsWereMergedIntoViewContext(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.externalTransactionsWereMergedIntoViewContext.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeUserWantsToPerfomBackupForExportNow(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (UIView) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToPerfomBackupForExportNow.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let sourceView = notification.userInfo!["sourceView"] as! UIView
			block(sourceView)
		}
	}

	static func observeNewMessageExpiration(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Date) -> Void) -> NSObjectProtocol {
		let name = Name.newMessageExpiration.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let expirationDate = notification.userInfo!["expirationDate"] as! Date
			block(expirationDate)
		}
	}

	static func observeNewMuteExpiration(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Date) -> Void) -> NSObjectProtocol {
		let name = Name.newMuteExpiration.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let expirationDate = notification.userInfo!["expirationDate"] as! Date
			block(expirationDate)
		}
	}

	static func observeWipeAllMessagesThatExpiredEarlierThanNow(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Bool, (Bool) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.wipeAllMessagesThatExpiredEarlierThanNow.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let launchedByBackgroundTask = notification.userInfo!["launchedByBackgroundTask"] as! Bool
			let completionHandler = notification.userInfo!["completionHandler"] as! (Bool) -> Void
			block(launchedByBackgroundTask, completionHandler)
		}
	}

	static func observePersistedMessageHasNewMetadata(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageHasNewMetadata.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedMessageObjectID = notification.userInfo!["persistedMessageObjectID"] as! NSManagedObjectID
			block(persistedMessageObjectID)
		}
	}

	static func observeFyleMessageJoinWithStatusHasNewProgress(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, Progress) -> Void) -> NSObjectProtocol {
		let name = Name.fyleMessageJoinWithStatusHasNewProgress.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! NSManagedObjectID
			let progress = notification.userInfo!["progress"] as! Progress
			block(objectID, progress)
		}
	}

	static func observeAViewRequiresFyleMessageJoinWithStatusProgresses(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping ([NSManagedObjectID]) -> Void) -> NSObjectProtocol {
		let name = Name.aViewRequiresFyleMessageJoinWithStatusProgresses.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectIDs = notification.userInfo!["objectIDs"] as! [NSManagedObjectID]
			block(objectIDs)
		}
	}

	static func observeUserWantsToCallAndIsAllowedTo(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping ([TypeSafeManagedObjectID<PersistedObvContactIdentity>], (groupUid: UID, groupOwner: ObvCryptoId)?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToCallAndIsAllowedTo.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactIDs = notification.userInfo!["contactIDs"] as! [TypeSafeManagedObjectID<PersistedObvContactIdentity>]
			let groupIdWrapper = notification.userInfo!["groupId"] as! OptionalWrapper<(groupUid: UID, groupOwner: ObvCryptoId)>
			let groupId = groupIdWrapper.value
			block(contactIDs, groupId)
		}
	}

	static func observeUserWantsToSelectAndCallContacts(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping ([TypeSafeManagedObjectID<PersistedObvContactIdentity>], (groupUid: UID, groupOwner: ObvCryptoId)?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToSelectAndCallContacts.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactIDs = notification.userInfo!["contactIDs"] as! [TypeSafeManagedObjectID<PersistedObvContactIdentity>]
			let groupIdWrapper = notification.userInfo!["groupId"] as! OptionalWrapper<(groupUid: UID, groupOwner: ObvCryptoId)>
			let groupId = groupIdWrapper.value
			block(contactIDs, groupId)
		}
	}

	static func observeUserWantsToCallButWeShouldCheckSheIsAllowedTo(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping ([TypeSafeManagedObjectID<PersistedObvContactIdentity>], (groupUid: UID, groupOwner: ObvCryptoId)?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToCallButWeShouldCheckSheIsAllowedTo.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactIDs = notification.userInfo!["contactIDs"] as! [TypeSafeManagedObjectID<PersistedObvContactIdentity>]
			let groupIdWrapper = notification.userInfo!["groupId"] as! OptionalWrapper<(groupUid: UID, groupOwner: ObvCryptoId)>
			let groupId = groupIdWrapper.value
			block(contactIDs, groupId)
		}
	}

	static func observeUserWantsToKickParticipant(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Call, CallParticipant) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToKickParticipant.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let call = notification.userInfo!["call"] as! Call
			let callParticipant = notification.userInfo!["callParticipant"] as! CallParticipant
			block(call, callParticipant)
		}
	}

	static func observeUserWantsToAddParticipants(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Call, [TypeSafeManagedObjectID<PersistedObvContactIdentity>]) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToAddParticipants.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let call = notification.userInfo!["call"] as! Call
			let contactIDs = notification.userInfo!["contactIDs"] as! [TypeSafeManagedObjectID<PersistedObvContactIdentity>]
			block(call, contactIDs)
		}
	}

	static func observeNewWebRTCMessageWasReceived(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (WebRTCMessageJSON, TypeSafeManagedObjectID<PersistedObvContactIdentity>, Date, Data) -> Void) -> NSObjectProtocol {
		let name = Name.newWebRTCMessageWasReceived.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let webrtcMessage = notification.userInfo!["webrtcMessage"] as! WebRTCMessageJSON
			let contactID = notification.userInfo!["contactID"] as! TypeSafeManagedObjectID<PersistedObvContactIdentity>
			let messageUploadTimestampFromServer = notification.userInfo!["messageUploadTimestampFromServer"] as! Date
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			block(webrtcMessage, contactID, messageUploadTimestampFromServer, messageIdentifierFromEngine)
		}
	}

	static func observeCallHasBeenUpdated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Call, CallUpdateKind) -> Void) -> NSObjectProtocol {
		let name = Name.callHasBeenUpdated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let call = notification.userInfo!["call"] as! Call
			let updateKind = notification.userInfo!["updateKind"] as! CallUpdateKind
			block(call, updateKind)
		}
	}

	static func observeCallParticipantHasBeenUpdated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (CallParticipant, CallParticipantUpdateKind) -> Void) -> NSObjectProtocol {
		let name = Name.callParticipantHasBeenUpdated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let callParticipant = notification.userInfo!["callParticipant"] as! CallParticipant
			let updateKind = notification.userInfo!["updateKind"] as! CallParticipantUpdateKind
			block(callParticipant, updateKind)
		}
	}

	static func observeToggleCallView(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.toggleCallView.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeHideCallView(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.hideCallView.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeNewObvMessageWasReceivedViaPushKitNotification(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvMessage) -> Void) -> NSObjectProtocol {
		let name = Name.newObvMessageWasReceivedViaPushKitNotification.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let obvMessage = notification.userInfo!["obvMessage"] as! ObvMessage
			block(obvMessage)
		}
	}

	static func observeNewWebRTCMessageToSend(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (WebRTCMessageJSON, TypeSafeManagedObjectID<PersistedObvContactIdentity>, Bool, @escaping () -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.newWebRTCMessageToSend.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let webrtcMessage = notification.userInfo!["webrtcMessage"] as! WebRTCMessageJSON
			let contactID = notification.userInfo!["contactID"] as! TypeSafeManagedObjectID<PersistedObvContactIdentity>
			let forStartingCall = notification.userInfo!["forStartingCall"] as! Bool
			let completion = notification.userInfo!["completion"] as! () -> Void
			block(webrtcMessage, contactID, forStartingCall, completion)
		}
	}

	static func observeIsCallKitEnabledSettingDidChange(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.isCallKitEnabledSettingDidChange.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeIsIncludesCallsInRecentsEnabledSettingDidChange(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.isIncludesCallsInRecentsEnabledSettingDidChange.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeNetworkInterfaceTypeChanged(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Bool) -> Void) -> NSObjectProtocol {
		let name = Name.networkInterfaceTypeChanged.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let isConnected = notification.userInfo!["isConnected"] as! Bool
			block(isConnected)
		}
	}

	static func observeNoMoreCallInProgress(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.noMoreCallInProgress.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeAppStateChanged(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (AppState, AppState) -> Void) -> NSObjectProtocol {
		let name = Name.appStateChanged.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let previousState = notification.userInfo!["previousState"] as! AppState
			let currentState = notification.userInfo!["currentState"] as! AppState
			block(previousState, currentState)
		}
	}

	static func observeOutgoingCallFailedBecauseUserDeniedRecordPermission(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.outgoingCallFailedBecauseUserDeniedRecordPermission.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeVoiceMessageFailedBecauseUserDeniedRecordPermission(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.voiceMessageFailedBecauseUserDeniedRecordPermission.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeRejectedIncomingCallBecauseUserDeniedRecordPermission(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.rejectedIncomingCallBecauseUserDeniedRecordPermission.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeUserRequestedDeletionOfPersistedMessage(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, DeletionType) -> Void) -> NSObjectProtocol {
		let name = Name.userRequestedDeletionOfPersistedMessage.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedMessageObjectID = notification.userInfo!["persistedMessageObjectID"] as! NSManagedObjectID
			let deletionType = notification.userInfo!["deletionType"] as! DeletionType
			block(persistedMessageObjectID, deletionType)
		}
	}

	static func observeTrashShouldBeEmptied(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.trashShouldBeEmptied.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeUserRequestedDeletionOfPersistedDiscussion(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, DeletionType, @escaping (Bool) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.userRequestedDeletionOfPersistedDiscussion.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedDiscussionObjectID = notification.userInfo!["persistedDiscussionObjectID"] as! NSManagedObjectID
			let deletionType = notification.userInfo!["deletionType"] as! DeletionType
			let completionHandler = notification.userInfo!["completionHandler"] as! (Bool) -> Void
			block(persistedDiscussionObjectID, deletionType, completionHandler)
		}
	}

	static func observeReportCallEvent(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (UUID, CallReport, (groupUid: UID, groupOwner: ObvCryptoId)?, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.reportCallEvent.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let callUUID = notification.userInfo!["callUUID"] as! UUID
			let callReport = notification.userInfo!["callReport"] as! CallReport
			let groupIdWrapper = notification.userInfo!["groupId"] as! OptionalWrapper<(groupUid: UID, groupOwner: ObvCryptoId)>
			let groupId = groupIdWrapper.value
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(callUUID, callReport, groupId, ownedCryptoId)
		}
	}

	static func observeNewCallLogItem(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedCallLogItem>) -> Void) -> NSObjectProtocol {
		let name = Name.newCallLogItem.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! TypeSafeManagedObjectID<PersistedCallLogItem>
			block(objectID)
		}
	}

	static func observeCallLogItemWasUpdated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedCallLogItem>) -> Void) -> NSObjectProtocol {
		let name = Name.callLogItemWasUpdated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! TypeSafeManagedObjectID<PersistedCallLogItem>
			block(objectID)
		}
	}

	static func observeUserWantsToIntroduceContactToAnotherContact(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvCryptoId, Set<ObvCryptoId>) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToIntroduceContactToAnotherContact.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let firstContactCryptoId = notification.userInfo!["firstContactCryptoId"] as! ObvCryptoId
			let secondContactCryptoIds = notification.userInfo!["secondContactCryptoIds"] as! Set<ObvCryptoId>
			block(ownedCryptoId, firstContactCryptoId, secondContactCryptoIds)
		}
	}

	static func observeShowCallViewControllerForAnsweringNonCallKitIncomingCall(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (IncomingCall) -> Void) -> NSObjectProtocol {
		let name = Name.showCallViewControllerForAnsweringNonCallKitIncomingCall.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let incomingCall = notification.userInfo!["incomingCall"] as! IncomingCall
			block(incomingCall)
		}
	}

	static func observeUserWantsToShareOwnPublishedDetails(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, UIView) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToShareOwnPublishedDetails.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let sourceView = notification.userInfo!["sourceView"] as! UIView
			block(ownedCryptoId, sourceView)
		}
	}

	static func observeUserWantsToSendInvite(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvOwnedIdentity, ObvURLIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToSendInvite.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvOwnedIdentity
			let urlIdentity = notification.userInfo!["urlIdentity"] as! ObvURLIdentity
			block(ownedIdentity, urlIdentity)
		}
	}

	static func observeUserRequestedAPIKeyStatus(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, UUID) -> Void) -> NSObjectProtocol {
		let name = Name.userRequestedAPIKeyStatus.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let apiKey = notification.userInfo!["apiKey"] as! UUID
			block(ownedCryptoId, apiKey)
		}
	}

	static func observeUserRequestedNewAPIKeyActivation(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, UUID) -> Void) -> NSObjectProtocol {
		let name = Name.userRequestedNewAPIKeyActivation.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let apiKey = notification.userInfo!["apiKey"] as! UUID
			block(ownedCryptoId, apiKey)
		}
	}

	static func observeUserWantsToNavigateToDeepLink(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvDeepLink) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToNavigateToDeepLink.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let deepLink = notification.userInfo!["deepLink"] as! ObvDeepLink
			block(deepLink)
		}
	}

	static func observeUseLoadBalancedTurnServersDidChange(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.useLoadBalancedTurnServersDidChange.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeUserWantsToReadReceivedMessagesThatRequiresUserAction(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Set<TypeSafeManagedObjectID<PersistedMessageReceived>>) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToReadReceivedMessagesThatRequiresUserAction.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedMessageObjectIDs = notification.userInfo!["persistedMessageObjectIDs"] as! Set<TypeSafeManagedObjectID<PersistedMessageReceived>>
			block(persistedMessageObjectIDs)
		}
	}

	static func observeRequestThumbnail(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (FyleElement, CGSize, ThumbnailType, @escaping ((Thumbnail) -> Void)) -> Void) -> NSObjectProtocol {
		let name = Name.requestThumbnail.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let fyleElement = notification.userInfo!["fyleElement"] as! FyleElement
			let size = notification.userInfo!["size"] as! CGSize
			let thumbnailType = notification.userInfo!["thumbnailType"] as! ThumbnailType
			let completionHandler = notification.userInfo!["completionHandler"] as! ((Thumbnail) -> Void)
			block(fyleElement, size, thumbnailType, completionHandler)
		}
	}

	static func observePersistedMessageReceivedWasRead(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageReceivedWasRead.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedMessageReceivedObjectID = notification.userInfo!["persistedMessageReceivedObjectID"] as! NSManagedObjectID
			block(persistedMessageReceivedObjectID)
		}
	}

	static func observeAReadOncePersistedMessageSentWasSent(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, TypeSafeManagedObjectID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.aReadOncePersistedMessageSentWasSent.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedMessageSentObjectID = notification.userInfo!["persistedMessageSentObjectID"] as! NSManagedObjectID
			let persistedDiscussionObjectID = notification.userInfo!["persistedDiscussionObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			block(persistedMessageSentObjectID, persistedDiscussionObjectID)
		}
	}

	static func observeUserWantsToSetAndShareNewDiscussionSharedExpirationConfiguration(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, ExpirationJSON, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToSetAndShareNewDiscussionSharedExpirationConfiguration.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedDiscussionObjectID = notification.userInfo!["persistedDiscussionObjectID"] as! NSManagedObjectID
			let expirationJSON = notification.userInfo!["expirationJSON"] as! ExpirationJSON
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(persistedDiscussionObjectID, expirationJSON, ownedCryptoId)
		}
	}

	static func observePersistedDiscussionSharedConfigurationShouldBeSent(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID) -> Void) -> NSObjectProtocol {
		let name = Name.persistedDiscussionSharedConfigurationShouldBeSent.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedDiscussionObjectID = notification.userInfo!["persistedDiscussionObjectID"] as! NSManagedObjectID
			block(persistedDiscussionObjectID)
		}
	}

	static func observeUserWantsToDeleteContact(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvCryptoId, UIViewController, @escaping ((Bool) -> Void)) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToDeleteContact.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let viewController = notification.userInfo!["viewController"] as! UIViewController
			let completionHandler = notification.userInfo!["completionHandler"] as! ((Bool) -> Void)
			block(contactCryptoId, ownedCryptoId, viewController, completionHandler)
		}
	}

	static func observeCleanExpiredMessagesBackgroundTaskWasLaunched(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (@escaping (Bool) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.cleanExpiredMessagesBackgroundTaskWasLaunched.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let completionHandler = notification.userInfo!["completionHandler"] as! (Bool) -> Void
			block(completionHandler)
		}
	}

	static func observeApplyRetentionPoliciesBackgroundTaskWasLaunched(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (@escaping (Bool) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.applyRetentionPoliciesBackgroundTaskWasLaunched.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let completionHandler = notification.userInfo!["completionHandler"] as! (Bool) -> Void
			block(completionHandler)
		}
	}

	static func observeUpdateBadgeBackgroundTaskWasLaunched(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (@escaping (Bool) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.updateBadgeBackgroundTaskWasLaunched.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let completionHandler = notification.userInfo!["completionHandler"] as! (Bool) -> Void
			block(completionHandler)
		}
	}

	static func observeApplyAllRetentionPoliciesNow(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Bool, (Bool) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.applyAllRetentionPoliciesNow.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let launchedByBackgroundTask = notification.userInfo!["launchedByBackgroundTask"] as! Bool
			let completionHandler = notification.userInfo!["completionHandler"] as! (Bool) -> Void
			block(launchedByBackgroundTask, completionHandler)
		}
	}

	static func observePersistedMessageSystemWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, TypeSafeManagedObjectID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageSystemWasDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectID = notification.userInfo!["objectID"] as! NSManagedObjectID
			let discussionObjectID = notification.userInfo!["discussionObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			block(objectID, discussionObjectID)
		}
	}

	static func observeAnOldDiscussionSharedConfigurationWasReceived(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID) -> Void) -> NSObjectProtocol {
		let name = Name.anOldDiscussionSharedConfigurationWasReceived.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedDiscussionObjectID = notification.userInfo!["persistedDiscussionObjectID"] as! NSManagedObjectID
			block(persistedDiscussionObjectID)
		}
	}

	static func observeUserWantsToSendEditedVersionOfSentMessage(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, String) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToSendEditedVersionOfSentMessage.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let sentMessageObjectID = notification.userInfo!["sentMessageObjectID"] as! NSManagedObjectID
			let newTextBody = notification.userInfo!["newTextBody"] as! String
			block(sentMessageObjectID, newTextBody)
		}
	}

	static func observeTheBodyOfPersistedMessageReceivedDidChange(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID) -> Void) -> NSObjectProtocol {
		let name = Name.theBodyOfPersistedMessageReceivedDidChange.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedMessageReceivedObjectID = notification.userInfo!["persistedMessageReceivedObjectID"] as! NSManagedObjectID
			block(persistedMessageReceivedObjectID)
		}
	}

	static func observeNewProfilePictureCandidateToCache(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (UUID, UIImage) -> Void) -> NSObjectProtocol {
		let name = Name.newProfilePictureCandidateToCache.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let requestUUID = notification.userInfo!["requestUUID"] as! UUID
			let profilePicture = notification.userInfo!["profilePicture"] as! UIImage
			block(requestUUID, profilePicture)
		}
	}

	static func observeNewCachedProfilePictureCandidate(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (UUID, URL) -> Void) -> NSObjectProtocol {
		let name = Name.newCachedProfilePictureCandidate.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let requestUUID = notification.userInfo!["requestUUID"] as! UUID
			let url = notification.userInfo!["url"] as! URL
			block(requestUUID, url)
		}
	}

	static func observeNewCustomContactPictureCandidateToSave(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (UUID, UIImage) -> Void) -> NSObjectProtocol {
		let name = Name.newCustomContactPictureCandidateToSave.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let requestUUID = notification.userInfo!["requestUUID"] as! UUID
			let profilePicture = notification.userInfo!["profilePicture"] as! UIImage
			block(requestUUID, profilePicture)
		}
	}

	static func observeNewSavedCustomContactPictureCandidate(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (UUID, URL) -> Void) -> NSObjectProtocol {
		let name = Name.newSavedCustomContactPictureCandidate.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let requestUUID = notification.userInfo!["requestUUID"] as! UUID
			let url = notification.userInfo!["url"] as! URL
			block(requestUUID, url)
		}
	}

	static func observeObvContactRequest(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (UUID, ObvCryptoId, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.obvContactRequest.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let requestUUID = notification.userInfo!["requestUUID"] as! UUID
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(requestUUID, contactCryptoId, ownedCryptoId)
		}
	}

	static func observeObvContactAnswer(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (UUID, ObvContactIdentity) -> Void) -> NSObjectProtocol {
		let name = Name.obvContactAnswer.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let requestUUID = notification.userInfo!["requestUUID"] as! UUID
			let obvContact = notification.userInfo!["obvContact"] as! ObvContactIdentity
			block(requestUUID, obvContact)
		}
	}

	static func observeUserWantsToMarkAllMessagesAsNotNewWithinDiscussion(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, @escaping (Bool) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToMarkAllMessagesAsNotNewWithinDiscussion.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedDiscussionObjectID = notification.userInfo!["persistedDiscussionObjectID"] as! NSManagedObjectID
			let completionHandler = notification.userInfo!["completionHandler"] as! (Bool) -> Void
			block(persistedDiscussionObjectID, completionHandler)
		}
	}

	static func observeResyncContactIdentityDevicesWithEngine(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.resyncContactIdentityDevicesWithEngine.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(contactCryptoId, ownedCryptoId)
		}
	}

	static func observeResyncContactIdentityDetailsStatusWithEngine(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.resyncContactIdentityDetailsStatusWithEngine.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(contactCryptoId, ownedCryptoId)
		}
	}

	static func observeServerDoesNotSuppoortCall(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.serverDoesNotSuppoortCall.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observePastedStringIsNotValidOlvidURL(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.pastedStringIsNotValidOlvidURL.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeServerDoesNotSupportCall(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.serverDoesNotSupportCall.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeUserWantsToRestartChannelEstablishmentProtocol(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToRestartChannelEstablishmentProtocol.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(contactCryptoId, ownedCryptoId)
		}
	}

	static func observeUserWantsToReCreateChannelEstablishmentProtocol(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToReCreateChannelEstablishmentProtocol.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(contactCryptoId, ownedCryptoId)
		}
	}

	static func observePersistedContactHasNewStatus(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactHasNewStatus.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(contactCryptoId, ownedCryptoId)
		}
	}

	static func observeContactIdentityDetailsWereUpdated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.contactIdentityDetailsWereUpdated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(contactCryptoId, ownedCryptoId)
		}
	}

	static func observeUserDidSeeNewDetailsOfContact(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.userDidSeeNewDetailsOfContact.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(contactCryptoId, ownedCryptoId)
		}
	}

	static func observeUserWantsToEditContactNicknameAndPicture(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, CustomNicknameAndPicture) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToEditContactNicknameAndPicture.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedContactObjectID = notification.userInfo!["persistedContactObjectID"] as! NSManagedObjectID
			let nicknameAndPicture = notification.userInfo!["nicknameAndPicture"] as! CustomNicknameAndPicture
			block(persistedContactObjectID, nicknameAndPicture)
		}
	}

	static func observeUserWantsToBindOwnedIdentityToKeycloak(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvKeycloakState, String, @escaping (Bool) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToBindOwnedIdentityToKeycloak.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let obvKeycloakState = notification.userInfo!["obvKeycloakState"] as! ObvKeycloakState
			let keycloakUserId = notification.userInfo!["keycloakUserId"] as! String
			let completionHandler = notification.userInfo!["completionHandler"] as! (Bool) -> Void
			block(ownedCryptoId, obvKeycloakState, keycloakUserId, completionHandler)
		}
	}

	static func observeUserWantsToUnbindOwnedIdentityFromKeycloak(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, @escaping (Bool) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUnbindOwnedIdentityFromKeycloak.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let completionHandler = notification.userInfo!["completionHandler"] as! (Bool) -> Void
			block(ownedCryptoId, completionHandler)
		}
	}

	static func observeRequestHardLinkToFyle(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (FyleElement, ((HardLinkToFyle) -> Void)) -> Void) -> NSObjectProtocol {
		let name = Name.requestHardLinkToFyle.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let fyleElement = notification.userInfo!["fyleElement"] as! FyleElement
			let completionHandler = notification.userInfo!["completionHandler"] as! ((HardLinkToFyle) -> Void)
			block(fyleElement, completionHandler)
		}
	}

	static func observeRequestAllHardLinksToFyles(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping ([FyleElement], (([HardLinkToFyle?]) -> Void)) -> Void) -> NSObjectProtocol {
		let name = Name.requestAllHardLinksToFyles.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let fyleElements = notification.userInfo!["fyleElements"] as! [FyleElement]
			let completionHandler = notification.userInfo!["completionHandler"] as! (([HardLinkToFyle?]) -> Void)
			block(fyleElements, completionHandler)
		}
	}

	static func observePersistedDiscussionWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeURL<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedDiscussionWasDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionUriRepresentation = notification.userInfo!["discussionUriRepresentation"] as! TypeSafeURL<PersistedDiscussion>
			block(discussionUriRepresentation)
		}
	}

	static func observeNewLockedPersistedDiscussion(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeURL<PersistedDiscussion>, TypeSafeManagedObjectID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.newLockedPersistedDiscussion.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let previousDiscussionUriRepresentation = notification.userInfo!["previousDiscussionUriRepresentation"] as! TypeSafeURL<PersistedDiscussion>
			let newLockedDiscussionId = notification.userInfo!["newLockedDiscussionId"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			block(previousDiscussionUriRepresentation, newLockedDiscussionId)
		}
	}

	static func observePersistedMessagesWereDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeURL<PersistedDiscussion>, Set<TypeSafeURL<PersistedMessage>>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessagesWereDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionUriRepresentation = notification.userInfo!["discussionUriRepresentation"] as! TypeSafeURL<PersistedDiscussion>
			let messageUriRepresentations = notification.userInfo!["messageUriRepresentations"] as! Set<TypeSafeURL<PersistedMessage>>
			block(discussionUriRepresentation, messageUriRepresentations)
		}
	}

	static func observePersistedMessagesWereWiped(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeURL<PersistedDiscussion>, Set<TypeSafeURL<PersistedMessage>>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessagesWereWiped.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionUriRepresentation = notification.userInfo!["discussionUriRepresentation"] as! TypeSafeURL<PersistedDiscussion>
			let messageUriRepresentations = notification.userInfo!["messageUriRepresentations"] as! Set<TypeSafeURL<PersistedMessage>>
			block(discussionUriRepresentation, messageUriRepresentations)
		}
	}

	static func observeDraftToSendWasReset(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDiscussion>, TypeSafeManagedObjectID<PersistedDraft>) -> Void) -> NSObjectProtocol {
		let name = Name.draftToSendWasReset.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionObjectID = notification.userInfo!["discussionObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			let draftObjectID = notification.userInfo!["draftObjectID"] as! TypeSafeManagedObjectID<PersistedDraft>
			block(discussionObjectID, draftObjectID)
		}
	}

	static func observeDraftFyleJoinWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeURL<PersistedDiscussion>, TypeSafeURL<PersistedDraft>, TypeSafeURL<PersistedDraftFyleJoin>) -> Void) -> NSObjectProtocol {
		let name = Name.draftFyleJoinWasDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionUriRepresentation = notification.userInfo!["discussionUriRepresentation"] as! TypeSafeURL<PersistedDiscussion>
			let draftUriRepresentation = notification.userInfo!["draftUriRepresentation"] as! TypeSafeURL<PersistedDraft>
			let draftFyleJoinUriRepresentation = notification.userInfo!["draftFyleJoinUriRepresentation"] as! TypeSafeURL<PersistedDraftFyleJoin>
			block(discussionUriRepresentation, draftUriRepresentation, draftFyleJoinUriRepresentation)
		}
	}

	static func observeShareExtensionExtensionContextWillCompleteRequest(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.shareExtensionExtensionContextWillCompleteRequest.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeUserWantsToRemoveDraftFyleJoin(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDraftFyleJoin>) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToRemoveDraftFyleJoin.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let draftFyleJoinObjectID = notification.userInfo!["draftFyleJoinObjectID"] as! TypeSafeManagedObjectID<PersistedDraftFyleJoin>
			block(draftFyleJoinObjectID)
		}
	}

	static func observeAppInitializationEnded(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.AppInitializationEnded.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeUserWantsToChangeContactsSortOrder(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ContactsSortOrder) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToChangeContactsSortOrder.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let sortOrder = notification.userInfo!["sortOrder"] as! ContactsSortOrder
			block(ownedCryptoId, sortOrder)
		}
	}

	static func observeContactsSortOrderDidChange(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.contactsSortOrderDidChange.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeIdentityColorStyleDidChange(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.identityColorStyleDidChange.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeUserWantsToUpdateDiscussionLocalConfiguration(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (PersistedDiscussionLocalConfigurationValue, TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUpdateDiscussionLocalConfiguration.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let value = notification.userInfo!["value"] as! PersistedDiscussionLocalConfigurationValue
			let localConfigurationObjectID = notification.userInfo!["localConfigurationObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>
			block(value, localConfigurationObjectID)
		}
	}

	static func observeUserWantsToUpdateLocalConfigurationOfDiscussion(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (PersistedDiscussionLocalConfigurationValue, TypeSafeManagedObjectID<PersistedDiscussion>) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUpdateLocalConfigurationOfDiscussion.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let value = notification.userInfo!["value"] as! PersistedDiscussionLocalConfigurationValue
			let persistedDiscussionObjectID = notification.userInfo!["persistedDiscussionObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			block(value, persistedDiscussionObjectID)
		}
	}

	static func observeDiscussionLocalConfigurationHasBeenUpdated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (PersistedDiscussionLocalConfigurationValue, TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>) -> Void) -> NSObjectProtocol {
		let name = Name.discussionLocalConfigurationHasBeenUpdated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let newValue = notification.userInfo!["newValue"] as! PersistedDiscussionLocalConfigurationValue
			let localConfigurationObjectID = notification.userInfo!["localConfigurationObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>
			block(newValue, localConfigurationObjectID)
		}
	}

	static func observeAudioInputHasBeenActivated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (String, @escaping () -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.audioInputHasBeenActivated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let label = notification.userInfo!["label"] as! String
			let activate = notification.userInfo!["activate"] as! () -> Void
			block(label, activate)
		}
	}

	static func observeAViewRequiresObvMutualScanUrl(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Data, ObvCryptoId, @escaping ((ObvMutualScanUrl) -> Void)) -> Void) -> NSObjectProtocol {
		let name = Name.aViewRequiresObvMutualScanUrl.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let remoteIdentity = notification.userInfo!["remoteIdentity"] as! Data
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let completionHandler = notification.userInfo!["completionHandler"] as! ((ObvMutualScanUrl) -> Void)
			block(remoteIdentity, ownedCryptoId, completionHandler)
		}
	}

	static func observeUserWantsToStartTrustEstablishmentWithMutualScanProtocol(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvMutualScanUrl) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToStartTrustEstablishmentWithMutualScanProtocol.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let mutualScanUrl = notification.userInfo!["mutualScanUrl"] as! ObvMutualScanUrl
			block(ownedCryptoId, mutualScanUrl)
		}
	}

	static func observeInsertDebugMessagesInAllExistingDiscussions(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.insertDebugMessagesInAllExistingDiscussions.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeDraftExpirationWasBeenUpdated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDraft>) -> Void) -> NSObjectProtocol {
		let name = Name.draftExpirationWasBeenUpdated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedDraftObjectID = notification.userInfo!["persistedDraftObjectID"] as! TypeSafeManagedObjectID<PersistedDraft>
			block(persistedDraftObjectID)
		}
	}

	static func observeBadgesNeedToBeUpdated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.badgesNeedToBeUpdated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(ownedCryptoId)
		}
	}

	static func observeCleanExpiredMuteNotficationsThatExpiredEarlierThanNow(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.cleanExpiredMuteNotficationsThatExpiredEarlierThanNow.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeNeedToRecomputeAllBadges(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.needToRecomputeAllBadges.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeUserWantsToDisplayContactIntroductionScreen(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedObvContactIdentity>, UIViewController) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToDisplayContactIntroductionScreen.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactObjectID = notification.userInfo!["contactObjectID"] as! TypeSafeManagedObjectID<PersistedObvContactIdentity>
			let viewController = notification.userInfo!["viewController"] as! UIViewController
			block(contactObjectID, viewController)
		}
	}

	static func observeUserDidTapOnMissedMessageBubble(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.userDidTapOnMissedMessageBubble.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeOlvidSnackBarShouldBeShown(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, OlvidSnackBarCategory) -> Void) -> NSObjectProtocol {
		let name = Name.olvidSnackBarShouldBeShown.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let snackBarCategory = notification.userInfo!["snackBarCategory"] as! OlvidSnackBarCategory
			block(ownedCryptoId, snackBarCategory)
		}
	}

	static func observeUserWantsToSeeDetailedExplanationsOfSnackBar(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, OlvidSnackBarCategory) -> Void) -> NSObjectProtocol {
		let name = Name.UserWantsToSeeDetailedExplanationsOfSnackBar.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let snackBarCategory = notification.userInfo!["snackBarCategory"] as! OlvidSnackBarCategory
			block(ownedCryptoId, snackBarCategory)
		}
	}

	static func observeUserDismissedSnackBarForLater(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, OlvidSnackBarCategory) -> Void) -> NSObjectProtocol {
		let name = Name.UserDismissedSnackBarForLater.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let snackBarCategory = notification.userInfo!["snackBarCategory"] as! OlvidSnackBarCategory
			block(ownedCryptoId, snackBarCategory)
		}
	}

	static func observeUserRequestedToResetAllAlerts(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.UserRequestedToResetAllAlerts.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeOlvidSnackBarShouldBeHidden(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.olvidSnackBarShouldBeHidden.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(ownedCryptoId)
		}
	}

	static func observeUserWantsToUpdateReaction(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedMessage>, String?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUpdateReaction.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let messageObjectID = notification.userInfo!["messageObjectID"] as! TypeSafeManagedObjectID<PersistedMessage>
			let emojiWrapper = notification.userInfo!["emoji"] as! OptionalWrapper<String>
			let emoji = emojiWrapper.value
			block(messageObjectID, emoji)
		}
	}

	static func observeCurrentUserActivityDidChange(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvUserActivityType, ObvUserActivityType) -> Void) -> NSObjectProtocol {
		let name = Name.currentUserActivityDidChange.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let previousUserActivity = notification.userInfo!["previousUserActivity"] as! ObvUserActivityType
			let currentUserActivity = notification.userInfo!["currentUserActivity"] as! ObvUserActivityType
			block(previousUserActivity, currentUserActivity)
		}
	}

	static func observeDisplayedSnackBarShouldBeRefreshed(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.displayedSnackBarShouldBeRefreshed.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeRequestUserDeniedRecordPermissionAlert(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.requestUserDeniedRecordPermissionAlert.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeIncrementalCleanBackupStarts(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Int) -> Void) -> NSObjectProtocol {
		let name = Name.incrementalCleanBackupStarts.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let initialCount = notification.userInfo!["initialCount"] as! Int
			block(initialCount)
		}
	}

	static func observeIncrementalCleanBackupInProgress(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Int, Bool) -> Void) -> NSObjectProtocol {
		let name = Name.incrementalCleanBackupInProgress.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let currentCount = notification.userInfo!["currentCount"] as! Int
			let cleanAllDevices = notification.userInfo!["cleanAllDevices"] as! Bool
			block(currentCount, cleanAllDevices)
		}
	}

	static func observeIncrementalCleanBackupTerminates(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Int) -> Void) -> NSObjectProtocol {
		let name = Name.incrementalCleanBackupTerminates.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let totalCount = notification.userInfo!["totalCount"] as! Int
			block(totalCount)
		}
	}

	static func observeUserWantsToUnblockContact(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUnblockContact.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			block(ownedCryptoId, contactCryptoId)
		}
	}

	static func observeUserWantsToReblockContact(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToReblockContact.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			block(ownedCryptoId, contactCryptoId)
		}
	}

	static func observePersistedContactIsActiveChanged(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedObvContactIdentity>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedContactIsActiveChanged.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactID = notification.userInfo!["contactID"] as! TypeSafeManagedObjectID<PersistedObvContactIdentity>
			block(contactID)
		}
	}

	static func observeInstalledOlvidAppIsOutdated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (UIViewController?) -> Void) -> NSObjectProtocol {
		let name = Name.installedOlvidAppIsOutdated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let presentingViewControllerWrapper = notification.userInfo!["presentingViewController"] as! OptionalWrapper<UIViewController>
			let presentingViewController = presentingViewControllerWrapper.value
			block(presentingViewController)
		}
	}

	static func observeUserOwnedIdentityWasRevokedByKeycloak(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.userOwnedIdentityWasRevokedByKeycloak.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(ownedCryptoId)
		}
	}

	static func observeAOneToOneDiscussionTitleNeedsToBeReset(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedObvOwnedIdentity>) -> Void) -> NSObjectProtocol {
		let name = Name.aOneToOneDiscussionTitleNeedsToBeReset.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedIdentityObjectID = notification.userInfo!["ownedIdentityObjectID"] as! TypeSafeManagedObjectID<PersistedObvOwnedIdentity>
			block(ownedIdentityObjectID)
		}
	}

	static func observeUiRequiresSignedContactDetails(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvCryptoId, @escaping (SignedUserDetails?) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.uiRequiresSignedContactDetails.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedIdentityCryptoId = notification.userInfo!["ownedIdentityCryptoId"] as! ObvCryptoId
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			let completion = notification.userInfo!["completion"] as! (SignedUserDetails?) -> Void
			block(ownedIdentityCryptoId, contactCryptoId, completion)
		}
	}

	static func observePreferredComposeMessageViewActionsDidChange(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.preferredComposeMessageViewActionsDidChange.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeRequestSyncAppDatabasesWithEngine(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (@escaping (Result<Void,Error>) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.requestSyncAppDatabasesWithEngine.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let completion = notification.userInfo!["completion"] as! (Result<Void,Error>) -> Void
			block(completion)
		}
	}

}
