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

enum ObvMessengerInternalNotification {
	case messagesAreNotNewAnymore(persistedMessageObjectIDs: Set<TypeSafeManagedObjectID<PersistedMessage>>)
	case userWantsToRefreshContactGroupJoined(obvContactGroup: ObvContactGroup)
	case currentOwnedCryptoIdChanged(newOwnedCryptoId: ObvCryptoId, apiKey: UUID)
	case userWantsToPerfomCloudKitBackupNow
	case externalTransactionsWereMergedIntoViewContext
	case userWantsToPerfomBackupForExportNow(sourceView: UIView, sourceViewController: UIViewController)
	case userCancelledBackupForExportNow
	case newMuteExpiration(expirationDate: Date)
	case wipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask: Bool, completionHandler: (Bool) -> Void)
	case userWantsToCallAndIsAllowedTo(contactIds: [OlvidUserId], groupId: GroupIdentifierBasedOnObjectID?)
	case userWantsToSelectAndCallContacts(contactIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>], groupId: GroupIdentifierBasedOnObjectID?)
	case userWantsToCallButWeShouldCheckSheIsAllowedTo(contactIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>], groupId: GroupIdentifierBasedOnObjectID?)
	case newWebRTCMessageWasReceived(webrtcMessage: WebRTCMessageJSON, contactId: OlvidUserId, messageUploadTimestampFromServer: Date, messageIdentifierFromEngine: Data)
	case newObvMessageWasReceivedViaPushKitNotification(obvMessage: ObvMessage)
	case newWebRTCMessageToSend(webrtcMessage: WebRTCMessageJSON, contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, forStartingCall: Bool)
	case isCallKitEnabledSettingDidChange
	case isIncludesCallsInRecentsEnabledSettingDidChange
	case networkInterfaceTypeChanged(isConnected: Bool)
	case outgoingCallFailedBecauseUserDeniedRecordPermission
	case voiceMessageFailedBecauseUserDeniedRecordPermission
	case rejectedIncomingCallBecauseUserDeniedRecordPermission
	case userRequestedDeletionOfPersistedMessage(ownedCryptoId: ObvCryptoId, persistedMessageObjectID: NSManagedObjectID, deletionType: DeletionType)
	case trashShouldBeEmptied
	case userRequestedDeletionOfPersistedDiscussion(persistedDiscussionObjectID: NSManagedObjectID, deletionType: DeletionType, completionHandler: (Bool) -> Void)
	case newCallLogItem(objectID: TypeSafeManagedObjectID<PersistedCallLogItem>)
	case callLogItemWasUpdated(objectID: TypeSafeManagedObjectID<PersistedCallLogItem>)
	case userWantsToIntroduceContactToAnotherContact(ownedCryptoId: ObvCryptoId, firstContactCryptoId: ObvCryptoId, secondContactCryptoIds: Set<ObvCryptoId>)
	case userWantsToShareOwnPublishedDetails(ownedCryptoId: ObvCryptoId, sourceView: UIView)
	case userWantsToSendInvite(ownedIdentity: ObvOwnedIdentity, urlIdentity: ObvURLIdentity)
	case userRequestedAPIKeyStatus(ownedCryptoId: ObvCryptoId, apiKey: UUID)
	case userRequestedNewAPIKeyActivation(ownedCryptoId: ObvCryptoId, apiKey: UUID)
	case userWantsToNavigateToDeepLink(deepLink: ObvDeepLink)
	case useLoadBalancedTurnServersDidChange
	case userWantsToReadReceivedMessagesThatRequiresUserAction(persistedMessageObjectIDs: Set<TypeSafeManagedObjectID<PersistedMessageReceived>>)
	case requestThumbnail(fyleElement: FyleElement, size: CGSize, thumbnailType: ThumbnailType, completionHandler: ((Thumbnail) -> Void))
	case userHasOpenedAReceivedAttachment(receivedFyleJoinID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>)
	case userWantsToSetAndShareNewDiscussionSharedExpirationConfiguration(persistedDiscussionObjectID: NSManagedObjectID, expirationJSON: ExpirationJSON, ownedCryptoId: ObvCryptoId)
	case userWantsToDeleteContact(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId, viewController: UIViewController, completionHandler: ((Bool) -> Void))
	case cleanExpiredMessagesBackgroundTaskWasLaunched(completionHandler: (Bool) -> Void)
	case applyRetentionPoliciesBackgroundTaskWasLaunched(completionHandler: (Bool) -> Void)
	case updateBadgeBackgroundTaskWasLaunched(completionHandler: (Bool) -> Void)
	case applyAllRetentionPoliciesNow(launchedByBackgroundTask: Bool, completionHandler: (Bool) -> Void)
	case userWantsToSendEditedVersionOfSentMessage(sentMessageObjectID: NSManagedObjectID, newTextBody: String)
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
	case userWantsToRestartChannelEstablishmentProtocol(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case userWantsToReCreateChannelEstablishmentProtocol(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case contactIdentityDetailsWereUpdated(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case userDidSeeNewDetailsOfContact(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case userWantsToEditContactNicknameAndPicture(persistedContactObjectID: NSManagedObjectID, customDisplayName: String?, customPhotoURL: URL?)
	case userWantsToBindOwnedIdentityToKeycloak(ownedCryptoId: ObvCryptoId, obvKeycloakState: ObvKeycloakState, keycloakUserId: String, completionHandler: (Bool) -> Void)
	case userWantsToUnbindOwnedIdentityFromKeycloak(ownedCryptoId: ObvCryptoId, completionHandler: (Bool) -> Void)
	case userWantsToRemoveDraftFyleJoin(draftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>)
	case userWantsToChangeContactsSortOrder(ownedCryptoId: ObvCryptoId, sortOrder: ContactsSortOrder)
	case userWantsToUpdateLocalConfigurationOfDiscussion(value: PersistedDiscussionLocalConfigurationValue, persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, completionHandler: () -> Void)
	case discussionLocalConfigurationHasBeenUpdated(newValue: PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>)
	case audioInputHasBeenActivated(label: String, activate: () -> Void)
	case aViewRequiresObvMutualScanUrl(remoteIdentity: Data, ownedCryptoId: ObvCryptoId, completionHandler: ((ObvMutualScanUrl) -> Void))
	case userWantsToStartTrustEstablishmentWithMutualScanProtocol(ownedCryptoId: ObvCryptoId, mutualScanUrl: ObvMutualScanUrl)
	case insertDebugMessagesInAllExistingDiscussions
	case draftExpirationWasBeenUpdated(persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>)
	case cleanExpiredMuteNotficationsThatExpiredEarlierThanNow
	case needToRecomputeAllBadges(completionHandler: (Bool) -> Void)
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
	case installedOlvidAppIsOutdated(presentingViewController: UIViewController?)
	case userOwnedIdentityWasRevokedByKeycloak(ownedCryptoId: ObvCryptoId)
	case uiRequiresSignedContactDetails(ownedIdentityCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId, completion: (SignedUserDetails?) -> Void)
	case requestSyncAppDatabasesWithEngine(completion: (Result<Void,Error>) -> Void)
	case uiRequiresSignedOwnedDetails(ownedIdentityCryptoId: ObvCryptoId, completion: (SignedUserDetails?) -> Void)
	case listMessagesOnServerBackgroundTaskWasLaunched(completionHandler: (Bool) -> Void)
	case userWantsToSendOneToOneInvitationToContact(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId)
	case userRepliedToReceivedMessageWithinTheNotificationExtension(persistedContactObjectID: NSManagedObjectID, messageIdentifierFromEngine: Data, textBody: String, completionHandler: () -> Void)
	case userRepliedToMissedCallWithinTheNotificationExtension(persistedDiscussionObjectID: NSManagedObjectID, textBody: String, completionHandler: () -> Void)
	case userWantsToMarkAsReadMessageWithinTheNotificationExtension(persistedContactObjectID: NSManagedObjectID, messageIdentifierFromEngine: Data, completionHandler: () -> Void)
	case userWantsToWipeFyleMessageJoinWithStatus(ownedCryptoId: ObvCryptoId, objectIDs: Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>)
	case userWantsToCreateNewGroupV1(groupName: String, groupDescription: String?, groupMembersCryptoIds: Set<ObvCryptoId>, ownedCryptoId: ObvCryptoId, photoURL: URL?)
	case userWantsToCreateNewGroupV2(groupCoreDetails: GroupV2CoreDetails, ownPermissions: Set<ObvGroupV2.Permission>, otherGroupMembers: Set<ObvGroupV2.IdentityAndPermissions>, ownedCryptoId: ObvCryptoId, photoURL: URL?)
	case userWantsToForwardMessage(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, discussionObjectIDs: Set<TypeSafeManagedObjectID<PersistedDiscussion>>)
	case userWantsToUpdateGroupV2(groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2>, changeset: ObvGroupV2.Changeset)
	case inviteContactsToGroupOwned(groupUid: UID, ownedCryptoId: ObvCryptoId, newGroupMembers: Set<ObvCryptoId>)
	case removeContactsFromGroupOwned(groupUid: UID, ownedCryptoId: ObvCryptoId, removedContacts: Set<ObvCryptoId>)
	case badgeForNewMessagesHasBeenUpdated(ownedCryptoId: ObvCryptoId, newCount: Int)
	case badgeForInvitationsHasBeenUpdated(ownedCryptoId: ObvCryptoId, newCount: Int)
	case requestRunningLog(completion: (RunningLogError) -> Void)
	case metaFlowControllerViewDidAppear
	case userWantsToUpdateCustomNameAndGroupV2Photo(groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2>, customName: String?, customPhotoURL: URL?)
	case userHasSeenPublishedDetailsOfGroupV2(groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2>)
	case tooManyWrongPasscodeAttemptsCausedLockOut

	private enum Name {
		case messagesAreNotNewAnymore
		case userWantsToRefreshContactGroupJoined
		case currentOwnedCryptoIdChanged
		case userWantsToPerfomCloudKitBackupNow
		case externalTransactionsWereMergedIntoViewContext
		case userWantsToPerfomBackupForExportNow
		case userCancelledBackupForExportNow
		case newMuteExpiration
		case wipeAllMessagesThatExpiredEarlierThanNow
		case userWantsToCallAndIsAllowedTo
		case userWantsToSelectAndCallContacts
		case userWantsToCallButWeShouldCheckSheIsAllowedTo
		case newWebRTCMessageWasReceived
		case newObvMessageWasReceivedViaPushKitNotification
		case newWebRTCMessageToSend
		case isCallKitEnabledSettingDidChange
		case isIncludesCallsInRecentsEnabledSettingDidChange
		case networkInterfaceTypeChanged
		case outgoingCallFailedBecauseUserDeniedRecordPermission
		case voiceMessageFailedBecauseUserDeniedRecordPermission
		case rejectedIncomingCallBecauseUserDeniedRecordPermission
		case userRequestedDeletionOfPersistedMessage
		case trashShouldBeEmptied
		case userRequestedDeletionOfPersistedDiscussion
		case newCallLogItem
		case callLogItemWasUpdated
		case userWantsToIntroduceContactToAnotherContact
		case userWantsToShareOwnPublishedDetails
		case userWantsToSendInvite
		case userRequestedAPIKeyStatus
		case userRequestedNewAPIKeyActivation
		case userWantsToNavigateToDeepLink
		case useLoadBalancedTurnServersDidChange
		case userWantsToReadReceivedMessagesThatRequiresUserAction
		case requestThumbnail
		case userHasOpenedAReceivedAttachment
		case userWantsToSetAndShareNewDiscussionSharedExpirationConfiguration
		case userWantsToDeleteContact
		case cleanExpiredMessagesBackgroundTaskWasLaunched
		case applyRetentionPoliciesBackgroundTaskWasLaunched
		case updateBadgeBackgroundTaskWasLaunched
		case applyAllRetentionPoliciesNow
		case userWantsToSendEditedVersionOfSentMessage
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
		case userWantsToRestartChannelEstablishmentProtocol
		case userWantsToReCreateChannelEstablishmentProtocol
		case contactIdentityDetailsWereUpdated
		case userDidSeeNewDetailsOfContact
		case userWantsToEditContactNicknameAndPicture
		case userWantsToBindOwnedIdentityToKeycloak
		case userWantsToUnbindOwnedIdentityFromKeycloak
		case userWantsToRemoveDraftFyleJoin
		case userWantsToChangeContactsSortOrder
		case userWantsToUpdateLocalConfigurationOfDiscussion
		case discussionLocalConfigurationHasBeenUpdated
		case audioInputHasBeenActivated
		case aViewRequiresObvMutualScanUrl
		case userWantsToStartTrustEstablishmentWithMutualScanProtocol
		case insertDebugMessagesInAllExistingDiscussions
		case draftExpirationWasBeenUpdated
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
		case installedOlvidAppIsOutdated
		case userOwnedIdentityWasRevokedByKeycloak
		case uiRequiresSignedContactDetails
		case requestSyncAppDatabasesWithEngine
		case uiRequiresSignedOwnedDetails
		case listMessagesOnServerBackgroundTaskWasLaunched
		case userWantsToSendOneToOneInvitationToContact
		case userRepliedToReceivedMessageWithinTheNotificationExtension
		case userRepliedToMissedCallWithinTheNotificationExtension
		case userWantsToMarkAsReadMessageWithinTheNotificationExtension
		case userWantsToWipeFyleMessageJoinWithStatus
		case userWantsToCreateNewGroupV1
		case userWantsToCreateNewGroupV2
		case userWantsToForwardMessage
		case userWantsToUpdateGroupV2
		case inviteContactsToGroupOwned
		case removeContactsFromGroupOwned
		case badgeForNewMessagesHasBeenUpdated
		case badgeForInvitationsHasBeenUpdated
		case requestRunningLog
		case metaFlowControllerViewDidAppear
		case userWantsToUpdateCustomNameAndGroupV2Photo
		case userHasSeenPublishedDetailsOfGroupV2
		case tooManyWrongPasscodeAttemptsCausedLockOut

		private var namePrefix: String { String(describing: ObvMessengerInternalNotification.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: ObvMessengerInternalNotification) -> NSNotification.Name {
			switch notification {
			case .messagesAreNotNewAnymore: return Name.messagesAreNotNewAnymore.name
			case .userWantsToRefreshContactGroupJoined: return Name.userWantsToRefreshContactGroupJoined.name
			case .currentOwnedCryptoIdChanged: return Name.currentOwnedCryptoIdChanged.name
			case .userWantsToPerfomCloudKitBackupNow: return Name.userWantsToPerfomCloudKitBackupNow.name
			case .externalTransactionsWereMergedIntoViewContext: return Name.externalTransactionsWereMergedIntoViewContext.name
			case .userWantsToPerfomBackupForExportNow: return Name.userWantsToPerfomBackupForExportNow.name
			case .userCancelledBackupForExportNow: return Name.userCancelledBackupForExportNow.name
			case .newMuteExpiration: return Name.newMuteExpiration.name
			case .wipeAllMessagesThatExpiredEarlierThanNow: return Name.wipeAllMessagesThatExpiredEarlierThanNow.name
			case .userWantsToCallAndIsAllowedTo: return Name.userWantsToCallAndIsAllowedTo.name
			case .userWantsToSelectAndCallContacts: return Name.userWantsToSelectAndCallContacts.name
			case .userWantsToCallButWeShouldCheckSheIsAllowedTo: return Name.userWantsToCallButWeShouldCheckSheIsAllowedTo.name
			case .newWebRTCMessageWasReceived: return Name.newWebRTCMessageWasReceived.name
			case .newObvMessageWasReceivedViaPushKitNotification: return Name.newObvMessageWasReceivedViaPushKitNotification.name
			case .newWebRTCMessageToSend: return Name.newWebRTCMessageToSend.name
			case .isCallKitEnabledSettingDidChange: return Name.isCallKitEnabledSettingDidChange.name
			case .isIncludesCallsInRecentsEnabledSettingDidChange: return Name.isIncludesCallsInRecentsEnabledSettingDidChange.name
			case .networkInterfaceTypeChanged: return Name.networkInterfaceTypeChanged.name
			case .outgoingCallFailedBecauseUserDeniedRecordPermission: return Name.outgoingCallFailedBecauseUserDeniedRecordPermission.name
			case .voiceMessageFailedBecauseUserDeniedRecordPermission: return Name.voiceMessageFailedBecauseUserDeniedRecordPermission.name
			case .rejectedIncomingCallBecauseUserDeniedRecordPermission: return Name.rejectedIncomingCallBecauseUserDeniedRecordPermission.name
			case .userRequestedDeletionOfPersistedMessage: return Name.userRequestedDeletionOfPersistedMessage.name
			case .trashShouldBeEmptied: return Name.trashShouldBeEmptied.name
			case .userRequestedDeletionOfPersistedDiscussion: return Name.userRequestedDeletionOfPersistedDiscussion.name
			case .newCallLogItem: return Name.newCallLogItem.name
			case .callLogItemWasUpdated: return Name.callLogItemWasUpdated.name
			case .userWantsToIntroduceContactToAnotherContact: return Name.userWantsToIntroduceContactToAnotherContact.name
			case .userWantsToShareOwnPublishedDetails: return Name.userWantsToShareOwnPublishedDetails.name
			case .userWantsToSendInvite: return Name.userWantsToSendInvite.name
			case .userRequestedAPIKeyStatus: return Name.userRequestedAPIKeyStatus.name
			case .userRequestedNewAPIKeyActivation: return Name.userRequestedNewAPIKeyActivation.name
			case .userWantsToNavigateToDeepLink: return Name.userWantsToNavigateToDeepLink.name
			case .useLoadBalancedTurnServersDidChange: return Name.useLoadBalancedTurnServersDidChange.name
			case .userWantsToReadReceivedMessagesThatRequiresUserAction: return Name.userWantsToReadReceivedMessagesThatRequiresUserAction.name
			case .requestThumbnail: return Name.requestThumbnail.name
			case .userHasOpenedAReceivedAttachment: return Name.userHasOpenedAReceivedAttachment.name
			case .userWantsToSetAndShareNewDiscussionSharedExpirationConfiguration: return Name.userWantsToSetAndShareNewDiscussionSharedExpirationConfiguration.name
			case .userWantsToDeleteContact: return Name.userWantsToDeleteContact.name
			case .cleanExpiredMessagesBackgroundTaskWasLaunched: return Name.cleanExpiredMessagesBackgroundTaskWasLaunched.name
			case .applyRetentionPoliciesBackgroundTaskWasLaunched: return Name.applyRetentionPoliciesBackgroundTaskWasLaunched.name
			case .updateBadgeBackgroundTaskWasLaunched: return Name.updateBadgeBackgroundTaskWasLaunched.name
			case .applyAllRetentionPoliciesNow: return Name.applyAllRetentionPoliciesNow.name
			case .userWantsToSendEditedVersionOfSentMessage: return Name.userWantsToSendEditedVersionOfSentMessage.name
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
			case .userWantsToRestartChannelEstablishmentProtocol: return Name.userWantsToRestartChannelEstablishmentProtocol.name
			case .userWantsToReCreateChannelEstablishmentProtocol: return Name.userWantsToReCreateChannelEstablishmentProtocol.name
			case .contactIdentityDetailsWereUpdated: return Name.contactIdentityDetailsWereUpdated.name
			case .userDidSeeNewDetailsOfContact: return Name.userDidSeeNewDetailsOfContact.name
			case .userWantsToEditContactNicknameAndPicture: return Name.userWantsToEditContactNicknameAndPicture.name
			case .userWantsToBindOwnedIdentityToKeycloak: return Name.userWantsToBindOwnedIdentityToKeycloak.name
			case .userWantsToUnbindOwnedIdentityFromKeycloak: return Name.userWantsToUnbindOwnedIdentityFromKeycloak.name
			case .userWantsToRemoveDraftFyleJoin: return Name.userWantsToRemoveDraftFyleJoin.name
			case .userWantsToChangeContactsSortOrder: return Name.userWantsToChangeContactsSortOrder.name
			case .userWantsToUpdateLocalConfigurationOfDiscussion: return Name.userWantsToUpdateLocalConfigurationOfDiscussion.name
			case .discussionLocalConfigurationHasBeenUpdated: return Name.discussionLocalConfigurationHasBeenUpdated.name
			case .audioInputHasBeenActivated: return Name.audioInputHasBeenActivated.name
			case .aViewRequiresObvMutualScanUrl: return Name.aViewRequiresObvMutualScanUrl.name
			case .userWantsToStartTrustEstablishmentWithMutualScanProtocol: return Name.userWantsToStartTrustEstablishmentWithMutualScanProtocol.name
			case .insertDebugMessagesInAllExistingDiscussions: return Name.insertDebugMessagesInAllExistingDiscussions.name
			case .draftExpirationWasBeenUpdated: return Name.draftExpirationWasBeenUpdated.name
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
			case .installedOlvidAppIsOutdated: return Name.installedOlvidAppIsOutdated.name
			case .userOwnedIdentityWasRevokedByKeycloak: return Name.userOwnedIdentityWasRevokedByKeycloak.name
			case .uiRequiresSignedContactDetails: return Name.uiRequiresSignedContactDetails.name
			case .requestSyncAppDatabasesWithEngine: return Name.requestSyncAppDatabasesWithEngine.name
			case .uiRequiresSignedOwnedDetails: return Name.uiRequiresSignedOwnedDetails.name
			case .listMessagesOnServerBackgroundTaskWasLaunched: return Name.listMessagesOnServerBackgroundTaskWasLaunched.name
			case .userWantsToSendOneToOneInvitationToContact: return Name.userWantsToSendOneToOneInvitationToContact.name
			case .userRepliedToReceivedMessageWithinTheNotificationExtension: return Name.userRepliedToReceivedMessageWithinTheNotificationExtension.name
			case .userRepliedToMissedCallWithinTheNotificationExtension: return Name.userRepliedToMissedCallWithinTheNotificationExtension.name
			case .userWantsToMarkAsReadMessageWithinTheNotificationExtension: return Name.userWantsToMarkAsReadMessageWithinTheNotificationExtension.name
			case .userWantsToWipeFyleMessageJoinWithStatus: return Name.userWantsToWipeFyleMessageJoinWithStatus.name
			case .userWantsToCreateNewGroupV1: return Name.userWantsToCreateNewGroupV1.name
			case .userWantsToCreateNewGroupV2: return Name.userWantsToCreateNewGroupV2.name
			case .userWantsToForwardMessage: return Name.userWantsToForwardMessage.name
			case .userWantsToUpdateGroupV2: return Name.userWantsToUpdateGroupV2.name
			case .inviteContactsToGroupOwned: return Name.inviteContactsToGroupOwned.name
			case .removeContactsFromGroupOwned: return Name.removeContactsFromGroupOwned.name
			case .badgeForNewMessagesHasBeenUpdated: return Name.badgeForNewMessagesHasBeenUpdated.name
			case .badgeForInvitationsHasBeenUpdated: return Name.badgeForInvitationsHasBeenUpdated.name
			case .requestRunningLog: return Name.requestRunningLog.name
			case .metaFlowControllerViewDidAppear: return Name.metaFlowControllerViewDidAppear.name
			case .userWantsToUpdateCustomNameAndGroupV2Photo: return Name.userWantsToUpdateCustomNameAndGroupV2Photo.name
			case .userHasSeenPublishedDetailsOfGroupV2: return Name.userHasSeenPublishedDetailsOfGroupV2.name
			case .tooManyWrongPasscodeAttemptsCausedLockOut: return Name.tooManyWrongPasscodeAttemptsCausedLockOut.name
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
		case .userWantsToRefreshContactGroupJoined(obvContactGroup: let obvContactGroup):
			info = [
				"obvContactGroup": obvContactGroup,
			]
		case .currentOwnedCryptoIdChanged(newOwnedCryptoId: let newOwnedCryptoId, apiKey: let apiKey):
			info = [
				"newOwnedCryptoId": newOwnedCryptoId,
				"apiKey": apiKey,
			]
		case .userWantsToPerfomCloudKitBackupNow:
			info = nil
		case .externalTransactionsWereMergedIntoViewContext:
			info = nil
		case .userWantsToPerfomBackupForExportNow(sourceView: let sourceView, sourceViewController: let sourceViewController):
			info = [
				"sourceView": sourceView,
				"sourceViewController": sourceViewController,
			]
		case .userCancelledBackupForExportNow:
			info = nil
		case .newMuteExpiration(expirationDate: let expirationDate):
			info = [
				"expirationDate": expirationDate,
			]
		case .wipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask: let launchedByBackgroundTask, completionHandler: let completionHandler):
			info = [
				"launchedByBackgroundTask": launchedByBackgroundTask,
				"completionHandler": completionHandler,
			]
		case .userWantsToCallAndIsAllowedTo(contactIds: let contactIds, groupId: let groupId):
			info = [
				"contactIds": contactIds,
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
		case .newWebRTCMessageWasReceived(webrtcMessage: let webrtcMessage, contactId: let contactId, messageUploadTimestampFromServer: let messageUploadTimestampFromServer, messageIdentifierFromEngine: let messageIdentifierFromEngine):
			info = [
				"webrtcMessage": webrtcMessage,
				"contactId": contactId,
				"messageUploadTimestampFromServer": messageUploadTimestampFromServer,
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
			]
		case .newObvMessageWasReceivedViaPushKitNotification(obvMessage: let obvMessage):
			info = [
				"obvMessage": obvMessage,
			]
		case .newWebRTCMessageToSend(webrtcMessage: let webrtcMessage, contactID: let contactID, forStartingCall: let forStartingCall):
			info = [
				"webrtcMessage": webrtcMessage,
				"contactID": contactID,
				"forStartingCall": forStartingCall,
			]
		case .isCallKitEnabledSettingDidChange:
			info = nil
		case .isIncludesCallsInRecentsEnabledSettingDidChange:
			info = nil
		case .networkInterfaceTypeChanged(isConnected: let isConnected):
			info = [
				"isConnected": isConnected,
			]
		case .outgoingCallFailedBecauseUserDeniedRecordPermission:
			info = nil
		case .voiceMessageFailedBecauseUserDeniedRecordPermission:
			info = nil
		case .rejectedIncomingCallBecauseUserDeniedRecordPermission:
			info = nil
		case .userRequestedDeletionOfPersistedMessage(ownedCryptoId: let ownedCryptoId, persistedMessageObjectID: let persistedMessageObjectID, deletionType: let deletionType):
			info = [
				"ownedCryptoId": ownedCryptoId,
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
		case .userHasOpenedAReceivedAttachment(receivedFyleJoinID: let receivedFyleJoinID):
			info = [
				"receivedFyleJoinID": receivedFyleJoinID,
			]
		case .userWantsToSetAndShareNewDiscussionSharedExpirationConfiguration(persistedDiscussionObjectID: let persistedDiscussionObjectID, expirationJSON: let expirationJSON, ownedCryptoId: let ownedCryptoId):
			info = [
				"persistedDiscussionObjectID": persistedDiscussionObjectID,
				"expirationJSON": expirationJSON,
				"ownedCryptoId": ownedCryptoId,
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
		case .userWantsToSendEditedVersionOfSentMessage(sentMessageObjectID: let sentMessageObjectID, newTextBody: let newTextBody):
			info = [
				"sentMessageObjectID": sentMessageObjectID,
				"newTextBody": newTextBody,
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
		case .userWantsToEditContactNicknameAndPicture(persistedContactObjectID: let persistedContactObjectID, customDisplayName: let customDisplayName, customPhotoURL: let customPhotoURL):
			info = [
				"persistedContactObjectID": persistedContactObjectID,
				"customDisplayName": OptionalWrapper(customDisplayName),
				"customPhotoURL": OptionalWrapper(customPhotoURL),
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
		case .userWantsToRemoveDraftFyleJoin(draftFyleJoinObjectID: let draftFyleJoinObjectID):
			info = [
				"draftFyleJoinObjectID": draftFyleJoinObjectID,
			]
		case .userWantsToChangeContactsSortOrder(ownedCryptoId: let ownedCryptoId, sortOrder: let sortOrder):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"sortOrder": sortOrder,
			]
		case .userWantsToUpdateLocalConfigurationOfDiscussion(value: let value, persistedDiscussionObjectID: let persistedDiscussionObjectID, completionHandler: let completionHandler):
			info = [
				"value": value,
				"persistedDiscussionObjectID": persistedDiscussionObjectID,
				"completionHandler": completionHandler,
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
		case .cleanExpiredMuteNotficationsThatExpiredEarlierThanNow:
			info = nil
		case .needToRecomputeAllBadges(completionHandler: let completionHandler):
			info = [
				"completionHandler": completionHandler,
			]
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
		case .installedOlvidAppIsOutdated(presentingViewController: let presentingViewController):
			info = [
				"presentingViewController": OptionalWrapper(presentingViewController),
			]
		case .userOwnedIdentityWasRevokedByKeycloak(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
			]
		case .uiRequiresSignedContactDetails(ownedIdentityCryptoId: let ownedIdentityCryptoId, contactCryptoId: let contactCryptoId, completion: let completion):
			info = [
				"ownedIdentityCryptoId": ownedIdentityCryptoId,
				"contactCryptoId": contactCryptoId,
				"completion": completion,
			]
		case .requestSyncAppDatabasesWithEngine(completion: let completion):
			info = [
				"completion": completion,
			]
		case .uiRequiresSignedOwnedDetails(ownedIdentityCryptoId: let ownedIdentityCryptoId, completion: let completion):
			info = [
				"ownedIdentityCryptoId": ownedIdentityCryptoId,
				"completion": completion,
			]
		case .listMessagesOnServerBackgroundTaskWasLaunched(completionHandler: let completionHandler):
			info = [
				"completionHandler": completionHandler,
			]
		case .userWantsToSendOneToOneInvitationToContact(ownedCryptoId: let ownedCryptoId, contactCryptoId: let contactCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"contactCryptoId": contactCryptoId,
			]
		case .userRepliedToReceivedMessageWithinTheNotificationExtension(persistedContactObjectID: let persistedContactObjectID, messageIdentifierFromEngine: let messageIdentifierFromEngine, textBody: let textBody, completionHandler: let completionHandler):
			info = [
				"persistedContactObjectID": persistedContactObjectID,
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
				"textBody": textBody,
				"completionHandler": completionHandler,
			]
		case .userRepliedToMissedCallWithinTheNotificationExtension(persistedDiscussionObjectID: let persistedDiscussionObjectID, textBody: let textBody, completionHandler: let completionHandler):
			info = [
				"persistedDiscussionObjectID": persistedDiscussionObjectID,
				"textBody": textBody,
				"completionHandler": completionHandler,
			]
		case .userWantsToMarkAsReadMessageWithinTheNotificationExtension(persistedContactObjectID: let persistedContactObjectID, messageIdentifierFromEngine: let messageIdentifierFromEngine, completionHandler: let completionHandler):
			info = [
				"persistedContactObjectID": persistedContactObjectID,
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
				"completionHandler": completionHandler,
			]
		case .userWantsToWipeFyleMessageJoinWithStatus(ownedCryptoId: let ownedCryptoId, objectIDs: let objectIDs):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"objectIDs": objectIDs,
			]
		case .userWantsToCreateNewGroupV1(groupName: let groupName, groupDescription: let groupDescription, groupMembersCryptoIds: let groupMembersCryptoIds, ownedCryptoId: let ownedCryptoId, photoURL: let photoURL):
			info = [
				"groupName": groupName,
				"groupDescription": OptionalWrapper(groupDescription),
				"groupMembersCryptoIds": groupMembersCryptoIds,
				"ownedCryptoId": ownedCryptoId,
				"photoURL": OptionalWrapper(photoURL),
			]
		case .userWantsToCreateNewGroupV2(groupCoreDetails: let groupCoreDetails, ownPermissions: let ownPermissions, otherGroupMembers: let otherGroupMembers, ownedCryptoId: let ownedCryptoId, photoURL: let photoURL):
			info = [
				"groupCoreDetails": groupCoreDetails,
				"ownPermissions": ownPermissions,
				"otherGroupMembers": otherGroupMembers,
				"ownedCryptoId": ownedCryptoId,
				"photoURL": OptionalWrapper(photoURL),
			]
		case .userWantsToForwardMessage(messageObjectID: let messageObjectID, discussionObjectIDs: let discussionObjectIDs):
			info = [
				"messageObjectID": messageObjectID,
				"discussionObjectIDs": discussionObjectIDs,
			]
		case .userWantsToUpdateGroupV2(groupObjectID: let groupObjectID, changeset: let changeset):
			info = [
				"groupObjectID": groupObjectID,
				"changeset": changeset,
			]
		case .inviteContactsToGroupOwned(groupUid: let groupUid, ownedCryptoId: let ownedCryptoId, newGroupMembers: let newGroupMembers):
			info = [
				"groupUid": groupUid,
				"ownedCryptoId": ownedCryptoId,
				"newGroupMembers": newGroupMembers,
			]
		case .removeContactsFromGroupOwned(groupUid: let groupUid, ownedCryptoId: let ownedCryptoId, removedContacts: let removedContacts):
			info = [
				"groupUid": groupUid,
				"ownedCryptoId": ownedCryptoId,
				"removedContacts": removedContacts,
			]
		case .badgeForNewMessagesHasBeenUpdated(ownedCryptoId: let ownedCryptoId, newCount: let newCount):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"newCount": newCount,
			]
		case .badgeForInvitationsHasBeenUpdated(ownedCryptoId: let ownedCryptoId, newCount: let newCount):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"newCount": newCount,
			]
		case .requestRunningLog(completion: let completion):
			info = [
				"completion": completion,
			]
		case .metaFlowControllerViewDidAppear:
			info = nil
		case .userWantsToUpdateCustomNameAndGroupV2Photo(groupObjectID: let groupObjectID, customName: let customName, customPhotoURL: let customPhotoURL):
			info = [
				"groupObjectID": groupObjectID,
				"customName": OptionalWrapper(customName),
				"customPhotoURL": OptionalWrapper(customPhotoURL),
			]
		case .userHasSeenPublishedDetailsOfGroupV2(groupObjectID: let groupObjectID):
			info = [
				"groupObjectID": groupObjectID,
			]
		case .tooManyWrongPasscodeAttemptsCausedLockOut:
			info = nil
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

	static func observeUserWantsToPerfomBackupForExportNow(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (UIView, UIViewController) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToPerfomBackupForExportNow.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let sourceView = notification.userInfo!["sourceView"] as! UIView
			let sourceViewController = notification.userInfo!["sourceViewController"] as! UIViewController
			block(sourceView, sourceViewController)
		}
	}

	static func observeUserCancelledBackupForExportNow(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.userCancelledBackupForExportNow.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
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

	static func observeUserWantsToCallAndIsAllowedTo(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping ([OlvidUserId], GroupIdentifierBasedOnObjectID?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToCallAndIsAllowedTo.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactIds = notification.userInfo!["contactIds"] as! [OlvidUserId]
			let groupIdWrapper = notification.userInfo!["groupId"] as! OptionalWrapper<GroupIdentifierBasedOnObjectID>
			let groupId = groupIdWrapper.value
			block(contactIds, groupId)
		}
	}

	static func observeUserWantsToSelectAndCallContacts(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping ([TypeSafeManagedObjectID<PersistedObvContactIdentity>], GroupIdentifierBasedOnObjectID?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToSelectAndCallContacts.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactIDs = notification.userInfo!["contactIDs"] as! [TypeSafeManagedObjectID<PersistedObvContactIdentity>]
			let groupIdWrapper = notification.userInfo!["groupId"] as! OptionalWrapper<GroupIdentifierBasedOnObjectID>
			let groupId = groupIdWrapper.value
			block(contactIDs, groupId)
		}
	}

	static func observeUserWantsToCallButWeShouldCheckSheIsAllowedTo(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping ([TypeSafeManagedObjectID<PersistedObvContactIdentity>], GroupIdentifierBasedOnObjectID?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToCallButWeShouldCheckSheIsAllowedTo.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactIDs = notification.userInfo!["contactIDs"] as! [TypeSafeManagedObjectID<PersistedObvContactIdentity>]
			let groupIdWrapper = notification.userInfo!["groupId"] as! OptionalWrapper<GroupIdentifierBasedOnObjectID>
			let groupId = groupIdWrapper.value
			block(contactIDs, groupId)
		}
	}

	static func observeNewWebRTCMessageWasReceived(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (WebRTCMessageJSON, OlvidUserId, Date, Data) -> Void) -> NSObjectProtocol {
		let name = Name.newWebRTCMessageWasReceived.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let webrtcMessage = notification.userInfo!["webrtcMessage"] as! WebRTCMessageJSON
			let contactId = notification.userInfo!["contactId"] as! OlvidUserId
			let messageUploadTimestampFromServer = notification.userInfo!["messageUploadTimestampFromServer"] as! Date
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			block(webrtcMessage, contactId, messageUploadTimestampFromServer, messageIdentifierFromEngine)
		}
	}

	static func observeNewObvMessageWasReceivedViaPushKitNotification(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvMessage) -> Void) -> NSObjectProtocol {
		let name = Name.newObvMessageWasReceivedViaPushKitNotification.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let obvMessage = notification.userInfo!["obvMessage"] as! ObvMessage
			block(obvMessage)
		}
	}

	static func observeNewWebRTCMessageToSend(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (WebRTCMessageJSON, TypeSafeManagedObjectID<PersistedObvContactIdentity>, Bool) -> Void) -> NSObjectProtocol {
		let name = Name.newWebRTCMessageToSend.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let webrtcMessage = notification.userInfo!["webrtcMessage"] as! WebRTCMessageJSON
			let contactID = notification.userInfo!["contactID"] as! TypeSafeManagedObjectID<PersistedObvContactIdentity>
			let forStartingCall = notification.userInfo!["forStartingCall"] as! Bool
			block(webrtcMessage, contactID, forStartingCall)
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

	static func observeUserRequestedDeletionOfPersistedMessage(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, NSManagedObjectID, DeletionType) -> Void) -> NSObjectProtocol {
		let name = Name.userRequestedDeletionOfPersistedMessage.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let persistedMessageObjectID = notification.userInfo!["persistedMessageObjectID"] as! NSManagedObjectID
			let deletionType = notification.userInfo!["deletionType"] as! DeletionType
			block(ownedCryptoId, persistedMessageObjectID, deletionType)
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

	static func observeUserHasOpenedAReceivedAttachment(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) -> Void) -> NSObjectProtocol {
		let name = Name.userHasOpenedAReceivedAttachment.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let receivedFyleJoinID = notification.userInfo!["receivedFyleJoinID"] as! TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>
			block(receivedFyleJoinID)
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

	static func observeUserWantsToSendEditedVersionOfSentMessage(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, String) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToSendEditedVersionOfSentMessage.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let sentMessageObjectID = notification.userInfo!["sentMessageObjectID"] as! NSManagedObjectID
			let newTextBody = notification.userInfo!["newTextBody"] as! String
			block(sentMessageObjectID, newTextBody)
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

	static func observeUserWantsToEditContactNicknameAndPicture(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, String?, URL?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToEditContactNicknameAndPicture.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedContactObjectID = notification.userInfo!["persistedContactObjectID"] as! NSManagedObjectID
			let customDisplayNameWrapper = notification.userInfo!["customDisplayName"] as! OptionalWrapper<String>
			let customDisplayName = customDisplayNameWrapper.value
			let customPhotoURLWrapper = notification.userInfo!["customPhotoURL"] as! OptionalWrapper<URL>
			let customPhotoURL = customPhotoURLWrapper.value
			block(persistedContactObjectID, customDisplayName, customPhotoURL)
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

	static func observeUserWantsToRemoveDraftFyleJoin(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedDraftFyleJoin>) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToRemoveDraftFyleJoin.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let draftFyleJoinObjectID = notification.userInfo!["draftFyleJoinObjectID"] as! TypeSafeManagedObjectID<PersistedDraftFyleJoin>
			block(draftFyleJoinObjectID)
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

	static func observeUserWantsToUpdateLocalConfigurationOfDiscussion(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (PersistedDiscussionLocalConfigurationValue, TypeSafeManagedObjectID<PersistedDiscussion>, @escaping () -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUpdateLocalConfigurationOfDiscussion.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let value = notification.userInfo!["value"] as! PersistedDiscussionLocalConfigurationValue
			let persistedDiscussionObjectID = notification.userInfo!["persistedDiscussionObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			let completionHandler = notification.userInfo!["completionHandler"] as! () -> Void
			block(value, persistedDiscussionObjectID, completionHandler)
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

	static func observeCleanExpiredMuteNotficationsThatExpiredEarlierThanNow(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.cleanExpiredMuteNotficationsThatExpiredEarlierThanNow.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeNeedToRecomputeAllBadges(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (@escaping (Bool) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.needToRecomputeAllBadges.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let completionHandler = notification.userInfo!["completionHandler"] as! (Bool) -> Void
			block(completionHandler)
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

	static func observeUiRequiresSignedContactDetails(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvCryptoId, @escaping (SignedUserDetails?) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.uiRequiresSignedContactDetails.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedIdentityCryptoId = notification.userInfo!["ownedIdentityCryptoId"] as! ObvCryptoId
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			let completion = notification.userInfo!["completion"] as! (SignedUserDetails?) -> Void
			block(ownedIdentityCryptoId, contactCryptoId, completion)
		}
	}

	static func observeRequestSyncAppDatabasesWithEngine(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (@escaping (Result<Void,Error>) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.requestSyncAppDatabasesWithEngine.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let completion = notification.userInfo!["completion"] as! (Result<Void,Error>) -> Void
			block(completion)
		}
	}

	static func observeUiRequiresSignedOwnedDetails(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, @escaping (SignedUserDetails?) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.uiRequiresSignedOwnedDetails.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedIdentityCryptoId = notification.userInfo!["ownedIdentityCryptoId"] as! ObvCryptoId
			let completion = notification.userInfo!["completion"] as! (SignedUserDetails?) -> Void
			block(ownedIdentityCryptoId, completion)
		}
	}

	static func observeListMessagesOnServerBackgroundTaskWasLaunched(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (@escaping (Bool) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.listMessagesOnServerBackgroundTaskWasLaunched.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let completionHandler = notification.userInfo!["completionHandler"] as! (Bool) -> Void
			block(completionHandler)
		}
	}

	static func observeUserWantsToSendOneToOneInvitationToContact(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToSendOneToOneInvitationToContact.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			block(ownedCryptoId, contactCryptoId)
		}
	}

	static func observeUserRepliedToReceivedMessageWithinTheNotificationExtension(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, Data, String, @escaping () -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.userRepliedToReceivedMessageWithinTheNotificationExtension.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedContactObjectID = notification.userInfo!["persistedContactObjectID"] as! NSManagedObjectID
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			let textBody = notification.userInfo!["textBody"] as! String
			let completionHandler = notification.userInfo!["completionHandler"] as! () -> Void
			block(persistedContactObjectID, messageIdentifierFromEngine, textBody, completionHandler)
		}
	}

	static func observeUserRepliedToMissedCallWithinTheNotificationExtension(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, String, @escaping () -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.userRepliedToMissedCallWithinTheNotificationExtension.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedDiscussionObjectID = notification.userInfo!["persistedDiscussionObjectID"] as! NSManagedObjectID
			let textBody = notification.userInfo!["textBody"] as! String
			let completionHandler = notification.userInfo!["completionHandler"] as! () -> Void
			block(persistedDiscussionObjectID, textBody, completionHandler)
		}
	}

	static func observeUserWantsToMarkAsReadMessageWithinTheNotificationExtension(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, Data, @escaping () -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToMarkAsReadMessageWithinTheNotificationExtension.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedContactObjectID = notification.userInfo!["persistedContactObjectID"] as! NSManagedObjectID
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			let completionHandler = notification.userInfo!["completionHandler"] as! () -> Void
			block(persistedContactObjectID, messageIdentifierFromEngine, completionHandler)
		}
	}

	static func observeUserWantsToWipeFyleMessageJoinWithStatus(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToWipeFyleMessageJoinWithStatus.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let objectIDs = notification.userInfo!["objectIDs"] as! Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>
			block(ownedCryptoId, objectIDs)
		}
	}

	static func observeUserWantsToCreateNewGroupV1(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (String, String?, Set<ObvCryptoId>, ObvCryptoId, URL?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToCreateNewGroupV1.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let groupName = notification.userInfo!["groupName"] as! String
			let groupDescriptionWrapper = notification.userInfo!["groupDescription"] as! OptionalWrapper<String>
			let groupDescription = groupDescriptionWrapper.value
			let groupMembersCryptoIds = notification.userInfo!["groupMembersCryptoIds"] as! Set<ObvCryptoId>
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let photoURLWrapper = notification.userInfo!["photoURL"] as! OptionalWrapper<URL>
			let photoURL = photoURLWrapper.value
			block(groupName, groupDescription, groupMembersCryptoIds, ownedCryptoId, photoURL)
		}
	}

	static func observeUserWantsToCreateNewGroupV2(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (GroupV2CoreDetails, Set<ObvGroupV2.Permission>, Set<ObvGroupV2.IdentityAndPermissions>, ObvCryptoId, URL?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToCreateNewGroupV2.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let groupCoreDetails = notification.userInfo!["groupCoreDetails"] as! GroupV2CoreDetails
			let ownPermissions = notification.userInfo!["ownPermissions"] as! Set<ObvGroupV2.Permission>
			let otherGroupMembers = notification.userInfo!["otherGroupMembers"] as! Set<ObvGroupV2.IdentityAndPermissions>
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let photoURLWrapper = notification.userInfo!["photoURL"] as! OptionalWrapper<URL>
			let photoURL = photoURLWrapper.value
			block(groupCoreDetails, ownPermissions, otherGroupMembers, ownedCryptoId, photoURL)
		}
	}

	static func observeUserWantsToForwardMessage(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedMessage>, Set<TypeSafeManagedObjectID<PersistedDiscussion>>) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToForwardMessage.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let messageObjectID = notification.userInfo!["messageObjectID"] as! TypeSafeManagedObjectID<PersistedMessage>
			let discussionObjectIDs = notification.userInfo!["discussionObjectIDs"] as! Set<TypeSafeManagedObjectID<PersistedDiscussion>>
			block(messageObjectID, discussionObjectIDs)
		}
	}

	static func observeUserWantsToUpdateGroupV2(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedGroupV2>, ObvGroupV2.Changeset) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUpdateGroupV2.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let groupObjectID = notification.userInfo!["groupObjectID"] as! TypeSafeManagedObjectID<PersistedGroupV2>
			let changeset = notification.userInfo!["changeset"] as! ObvGroupV2.Changeset
			block(groupObjectID, changeset)
		}
	}

	static func observeInviteContactsToGroupOwned(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (UID, ObvCryptoId, Set<ObvCryptoId>) -> Void) -> NSObjectProtocol {
		let name = Name.inviteContactsToGroupOwned.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let groupUid = notification.userInfo!["groupUid"] as! UID
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let newGroupMembers = notification.userInfo!["newGroupMembers"] as! Set<ObvCryptoId>
			block(groupUid, ownedCryptoId, newGroupMembers)
		}
	}

	static func observeRemoveContactsFromGroupOwned(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (UID, ObvCryptoId, Set<ObvCryptoId>) -> Void) -> NSObjectProtocol {
		let name = Name.removeContactsFromGroupOwned.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let groupUid = notification.userInfo!["groupUid"] as! UID
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let removedContacts = notification.userInfo!["removedContacts"] as! Set<ObvCryptoId>
			block(groupUid, ownedCryptoId, removedContacts)
		}
	}

	static func observeBadgeForNewMessagesHasBeenUpdated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Int) -> Void) -> NSObjectProtocol {
		let name = Name.badgeForNewMessagesHasBeenUpdated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let newCount = notification.userInfo!["newCount"] as! Int
			block(ownedCryptoId, newCount)
		}
	}

	static func observeBadgeForInvitationsHasBeenUpdated(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Int) -> Void) -> NSObjectProtocol {
		let name = Name.badgeForInvitationsHasBeenUpdated.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let newCount = notification.userInfo!["newCount"] as! Int
			block(ownedCryptoId, newCount)
		}
	}

	static func observeRequestRunningLog(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping ((RunningLogError) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.requestRunningLog.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let completion = notification.userInfo!["completion"] as! (RunningLogError) -> Void
			block(completion)
		}
	}

	static func observeMetaFlowControllerViewDidAppear(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.metaFlowControllerViewDidAppear.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeUserWantsToUpdateCustomNameAndGroupV2Photo(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedGroupV2>, String?, URL?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUpdateCustomNameAndGroupV2Photo.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let groupObjectID = notification.userInfo!["groupObjectID"] as! TypeSafeManagedObjectID<PersistedGroupV2>
			let customNameWrapper = notification.userInfo!["customName"] as! OptionalWrapper<String>
			let customName = customNameWrapper.value
			let customPhotoURLWrapper = notification.userInfo!["customPhotoURL"] as! OptionalWrapper<URL>
			let customPhotoURL = customPhotoURLWrapper.value
			block(groupObjectID, customName, customPhotoURL)
		}
	}

	static func observeUserHasSeenPublishedDetailsOfGroupV2(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedGroupV2>) -> Void) -> NSObjectProtocol {
		let name = Name.userHasSeenPublishedDetailsOfGroupV2.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let groupObjectID = notification.userInfo!["groupObjectID"] as! TypeSafeManagedObjectID<PersistedGroupV2>
			block(groupObjectID)
		}
	}

	static func observeTooManyWrongPasscodeAttemptsCausedLockOut(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.tooManyWrongPasscodeAttemptsCausedLockOut.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

}
