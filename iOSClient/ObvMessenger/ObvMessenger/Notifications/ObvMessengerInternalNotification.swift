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
import CoreData
import ObvTypes
import ObvEngine
import OlvidUtils
import ObvCrypto
import ObvUICoreData
import ObvSettings

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
	case messagesAreNotNewAnymore(ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageIds: [MessageIdentifier])
	case userWantsToRefreshContactGroupJoined(obvContactGroup: ObvContactGroup)
	case externalTransactionsWereMergedIntoViewContext
	case newMuteExpiration(expirationDate: Date)
	case wipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask: Bool, completionHandler: (Bool) -> Void)
	case userWantsToCallAndIsAllowedTo(ownedCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>, ownedIdentityForRequestingTurnCredentials: ObvCryptoId, groupId: GroupIdentifier?)
	case userWantsToSelectAndCallContacts(ownedCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>, groupId: GroupIdentifier?)
	case userWantsToCallButWeShouldCheckSheIsAllowedTo(ownedCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>, groupId: GroupIdentifier?)
	case newWebRTCMessageWasReceived(webrtcMessage: WebRTCMessageJSON, fromOlvidUser: OlvidUserId, messageUID: UID)
	case newObvEncryptedPushNotificationWasReceivedViaPushKitNotification(encryptedNotification: ObvEncryptedPushNotification)
	case isIncludesCallsInRecentsEnabledSettingDidChange
	case networkInterfaceTypeChanged(isConnected: Bool)
	case outgoingCallFailedBecauseUserDeniedRecordPermission
	case voiceMessageFailedBecauseUserDeniedRecordPermission
	case rejectedIncomingCallBecauseUserDeniedRecordPermission
	case userRequestedDeletionOfPersistedMessage(ownedCryptoId: ObvCryptoId, persistedMessageObjectID: NSManagedObjectID, deletionType: DeletionType)
	case trashShouldBeEmptied
	case userRequestedDeletionOfPersistedDiscussion(ownedCryptoId: ObvCryptoId, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, deletionType: DeletionType, completionHandler: (Bool) -> Void)
	case newCallLogItem(objectID: TypeSafeManagedObjectID<PersistedCallLogItem>)
	case callLogItemWasUpdated(objectID: TypeSafeManagedObjectID<PersistedCallLogItem>)
	case userWantsToIntroduceContactToAnotherContact(ownedCryptoId: ObvCryptoId, firstContactCryptoId: ObvCryptoId, secondContactCryptoIds: Set<ObvCryptoId>)
	case userWantsToShareOwnPublishedDetails(ownedCryptoId: ObvCryptoId, sourceView: UIView)
	case userWantsToSendInvite(ownedIdentity: ObvOwnedIdentity, urlIdentity: ObvURLIdentity)
	case userWantsToNavigateToDeepLink(deepLink: ObvDeepLink)
	case useLoadBalancedTurnServersDidChange
	case userWantsToReadReceivedMessageThatRequiresUserAction(ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageId: ReceivedMessageIdentifier)
	case requestThumbnail(fyleElement: FyleElement, size: CGSize, thumbnailType: ThumbnailType, completionHandler: ((Thumbnail) -> Void))
	case userHasOpenedAReceivedAttachment(receivedFyleJoinID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>)
	case userWantsToSetAndShareNewDiscussionSharedExpirationConfiguration(ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, expirationJSON: ExpirationJSON)
	case userWantsToDeleteContact(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId, viewController: UIViewController, completionHandler: ((Bool) -> Void))
	case cleanExpiredMessagesBackgroundTaskWasLaunched(completionHandler: (Bool) -> Void)
	case applyRetentionPoliciesBackgroundTaskWasLaunched(completionHandler: (Bool) -> Void)
	case updateBadgeBackgroundTaskWasLaunched(completionHandler: (Bool) -> Void)
	case applyAllRetentionPoliciesNow(launchedByBackgroundTask: Bool, completionHandler: (Bool) -> Void)
	case userWantsToSendEditedVersionOfSentMessage(ownedCryptoId: ObvCryptoId, sentMessageObjectID: TypeSafeManagedObjectID<PersistedMessageSent>, newTextBody: String)
	case newProfilePictureCandidateToCache(requestUUID: UUID, profilePicture: UIImage)
	case newCachedProfilePictureCandidate(requestUUID: UUID, url: URL)
	case newCustomContactPictureCandidateToSave(requestUUID: UUID, profilePicture: UIImage)
	case newSavedCustomContactPictureCandidate(requestUUID: UUID, url: URL)
	case obvContactRequest(requestUUID: UUID, contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case obvContactAnswer(requestUUID: UUID, obvContact: ObvContactIdentity)
	case userWantsToMarkAllMessagesAsNotNewWithinDiscussion(persistedDiscussionObjectID: NSManagedObjectID, completionHandler: (Bool) -> Void)
	case resyncContactIdentityDevicesWithEngine(obvContactIdentifier: ObvContactIdentifier)
	case serverDoesNotSuppoortCall
	case pastedStringIsNotValidOlvidURL
	case userWantsToRestartChannelEstablishmentProtocol(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case contactIdentityDetailsWereUpdated(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case userDidSeeNewDetailsOfContact(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case userWantsToEditContactNicknameAndPicture(persistedContactObjectID: NSManagedObjectID, customDisplayName: String?, customPhoto: UIImage?)
	case userWantsToBindOwnedIdentityToKeycloak(ownedCryptoId: ObvCryptoId, obvKeycloakState: ObvKeycloakState, keycloakUserId: String, completionHandler: (Bool) -> Void)
	case userWantsToUnbindOwnedIdentityFromKeycloak(ownedCryptoId: ObvCryptoId, completionHandler: (Bool) -> Void)
	case userWantsToRemoveDraftFyleJoin(draftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>)
	case userWantsToChangeContactsSortOrder(ownedCryptoId: ObvCryptoId, sortOrder: ContactsSortOrder)
	case userWantsToUpdateLocalConfigurationOfDiscussion(value: PersistedDiscussionLocalConfigurationValue, discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, completionHandler: () -> Void)
	case audioInputHasBeenActivated(label: String, activate: () -> Void)
	case aViewRequiresObvMutualScanUrl(remoteIdentity: Data, ownedCryptoId: ObvCryptoId, completionHandler: ((ObvMutualScanUrl) -> Void))
	case userWantsToStartTrustEstablishmentWithMutualScanProtocol(ownedCryptoId: ObvCryptoId, mutualScanUrl: ObvMutualScanUrl)
	case insertDebugMessagesInAllExistingDiscussions
	case draftExpirationWasBeenUpdated(persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>)
	case cleanExpiredMuteNotficationsThatExpiredEarlierThanNow
	case userWantsToDisplayContactIntroductionScreen(contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, viewController: UIViewController)
	case userDidTapOnMissedMessageBubble
	case olvidSnackBarShouldBeShown(ownedCryptoId: ObvCryptoId, snackBarCategory: OlvidSnackBarCategory)
	case UserWantsToSeeDetailedExplanationsOfSnackBar(ownedCryptoId: ObvCryptoId, snackBarCategory: OlvidSnackBarCategory)
	case UserDismissedSnackBarForLater(ownedCryptoId: ObvCryptoId, snackBarCategory: OlvidSnackBarCategory)
	case UserRequestedToResetAllAlerts
	case olvidSnackBarShouldBeHidden(ownedCryptoId: ObvCryptoId)
	case userWantsToUpdateReaction(ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, newEmoji: String?)
	case currentUserActivityDidChange(previousUserActivity: ObvUserActivityType, currentUserActivity: ObvUserActivityType)
	case displayedSnackBarShouldBeRefreshed
	case requestUserDeniedRecordPermissionAlert
	case userWantsToStartIncrementalCleanBackup(cleanAllDevices: Bool)
	case incrementalCleanBackupStarts
	case incrementalCleanBackupTerminates
	case userWantsToUnblockContact(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId)
	case userWantsToReblockContact(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId)
	case installedOlvidAppIsOutdated(presentingViewController: UIViewController?)
	case userOwnedIdentityWasRevokedByKeycloak(ownedCryptoId: ObvCryptoId)
	case uiRequiresSignedContactDetails(ownedIdentityCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId, completion: (SignedObvKeycloakUserDetails?) -> Void)
	case requestSyncAppDatabasesWithEngine(queuePriority: Operation.QueuePriority, isRestoringSyncSnapshotOrBackup: Bool, completion: (Result<(coordinatorsQueue: OperationQueue, queueForComposedOperations: OperationQueue),Error>) -> Void)
	case uiRequiresSignedOwnedDetails(ownedIdentityCryptoId: ObvCryptoId, completion: (SignedObvKeycloakUserDetails?) -> Void)
	case listMessagesOnServerBackgroundTaskWasLaunched(completionHandler: (Bool) -> Void)
	case userWantsToSendOneToOneInvitationToContact(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId)
	case userRepliedToReceivedMessageWithinTheNotificationExtension(contactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>, messageIdentifierFromEngine: Data, textBody: String, completionHandler: () -> Void)
	case userRepliedToMissedCallWithinTheNotificationExtension(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, textBody: String, completionHandler: () -> Void)
	case userWantsToMarkAsReadMessageWithinTheNotificationExtension(contactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>, messageIdentifierFromEngine: Data, completionHandler: () -> Void)
	case userWantsToWipeFyleMessageJoinWithStatus(ownedCryptoId: ObvCryptoId, objectIDs: Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>)
	case userWantsToCreateNewGroupV1(groupName: String, groupDescription: String?, groupMembersCryptoIds: Set<ObvCryptoId>, ownedCryptoId: ObvCryptoId, photoURL: URL?)
	case userWantsToCreateNewGroupV2(groupCoreDetails: GroupV2CoreDetails, ownPermissions: Set<ObvGroupV2.Permission>, otherGroupMembers: Set<ObvGroupV2.IdentityAndPermissions>, ownedCryptoId: ObvCryptoId, photoURL: URL?)
	case userWantsToForwardMessage(messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>, discussionPermanentIDs: Set<ObvManagedObjectPermanentID<PersistedDiscussion>>)
	case userWantsToUpdateGroupV2(groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2>, changeset: ObvGroupV2.Changeset)
	case inviteContactsToGroupOwned(groupUid: UID, ownedCryptoId: ObvCryptoId, newGroupMembers: Set<ObvCryptoId>)
	case removeContactsFromGroupOwned(groupUid: UID, ownedCryptoId: ObvCryptoId, removedContacts: Set<ObvCryptoId>)
	case badgeForNewMessagesHasBeenUpdated(ownedCryptoId: ObvCryptoId, newCount: Int)
	case badgeForInvitationsHasBeenUpdated(ownedCryptoId: ObvCryptoId, newCount: Int)
	case requestRunningLog(completion: (RunningLogError) -> Void)
	case metaFlowControllerViewDidAppear
	case userWantsToUpdateCustomNameAndGroupV2Photo(ownedCryptoId: ObvCryptoId, groupIdentifier: Data, customName: String?, customPhoto: UIImage?)
	case userHasSeenPublishedDetailsOfGroupV2(groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2>)
	case tooManyWrongPasscodeAttemptsCausedLockOut
	case backupForExportWasExported
	case backupForUploadWasUploaded
	case backupForUploadFailedToUpload
	case userWantsToAddOwnedProfile
	case userWantsToSwitchToOtherOwnedIdentity(ownedCryptoId: ObvCryptoId)
	case userWantsToDeleteOwnedIdentityButHasNotConfirmedYet(ownedCryptoId: ObvCryptoId)
	case userWantsToDeleteOwnedIdentityAndHasConfirmed(ownedCryptoId: ObvCryptoId, globalOwnedIdentityDeletion: Bool)
	case userWantsToHideOwnedIdentity(ownedCryptoId: ObvCryptoId, password: String)
	case failedToHideOwnedIdentity(ownedCryptoId: ObvCryptoId)
	case userWantsToSwitchToOtherHiddenOwnedIdentity(password: String)
	case userWantsToUnhideOwnedIdentity(ownedCryptoId: ObvCryptoId)
	case metaFlowControllerDidSwitchToOwnedIdentity(ownedCryptoId: ObvCryptoId)
	case closeAnyOpenHiddenOwnedIdentity
	case userWantsToUpdateOwnedCustomDisplayName(ownedCryptoId: ObvCryptoId, newCustomDisplayName: String?)
	case userWantsToReorderDiscussions(discussionObjectIds: [NSManagedObjectID], ownedIdentity: ObvCryptoId, completionHandler: ((Bool) -> Void)?)
	case betaUserWantsToDebugCoordinatorsQueue
	case betaUserWantsToSeeLogString(logString: String)
	case draftFyleJoinWasDeleted(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, draftFyleJoinPermanentID: ObvManagedObjectPermanentID<PersistedDraftFyleJoin>)
	case draftToSendWasReset(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>)
	case fyleMessageJoinWasWiped(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>, fyleMessageJoinPermanentID: ObvManagedObjectPermanentID<FyleMessageJoinWithStatus>)
	case userWantsToUpdateDiscussionLocalConfiguration(value: PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>)
	case userWantsToArchiveDiscussion(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, completionHandler: ((Bool) -> Void)?)
	case userWantsToUnarchiveDiscussion(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, updateTimestampOfLastMessage: Bool, completionHandler: ((Bool) -> Void)?)
	case userWantsToRefreshDiscussions(completionHandler: (() -> Void))
	case updateNormalizedSearchKeyOnPersistedDiscussions(ownedIdentity: ObvCryptoId, completionHandler: (() -> Void)?)
	case aDiscussionSharedConfigurationIsNeededByContact(contactIdentifier: ObvContactIdentifier, discussionId: DiscussionIdentifier)
	case aDiscussionSharedConfigurationIsNeededByAnotherOwnedDevice(ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier)
	case userWantsToDeleteOwnedContactGroup(ownedCryptoId: ObvCryptoId, groupUid: UID)
	case singleOwnedIdentityFlowViewControllerDidAppear(ownedCryptoId: ObvCryptoId)
	case userWantsToSetCustomNameOfJoinedGroupV1(ownedCryptoId: ObvCryptoId, groupId: GroupV1Identifier, groupNameCustom: String?)
	case userWantsToUpdatePersonalNoteOnContact(contactIdentifier: ObvContactIdentifier, newText: String?)
	case userWantsToUpdatePersonalNoteOnGroupV1(ownedCryptoId: ObvCryptoId, groupId: GroupV1Identifier, newText: String?)
	case userWantsToUpdatePersonalNoteOnGroupV2(ownedCryptoId: ObvCryptoId, groupIdentifier: Data, newText: String?)
	case allPersistedInvitationCanBeMarkedAsOld(ownedCryptoId: ObvCryptoId)
	case userHasSeenPublishedDetailsOfContactGroupJoined(obvGroupIdentifier: ObvGroupV1Identifier)

	private enum Name {
		case messagesAreNotNewAnymore
		case userWantsToRefreshContactGroupJoined
		case externalTransactionsWereMergedIntoViewContext
		case newMuteExpiration
		case wipeAllMessagesThatExpiredEarlierThanNow
		case userWantsToCallAndIsAllowedTo
		case userWantsToSelectAndCallContacts
		case userWantsToCallButWeShouldCheckSheIsAllowedTo
		case newWebRTCMessageWasReceived
		case newObvEncryptedPushNotificationWasReceivedViaPushKitNotification
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
		case userWantsToNavigateToDeepLink
		case useLoadBalancedTurnServersDidChange
		case userWantsToReadReceivedMessageThatRequiresUserAction
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
		case serverDoesNotSuppoortCall
		case pastedStringIsNotValidOlvidURL
		case userWantsToRestartChannelEstablishmentProtocol
		case contactIdentityDetailsWereUpdated
		case userDidSeeNewDetailsOfContact
		case userWantsToEditContactNicknameAndPicture
		case userWantsToBindOwnedIdentityToKeycloak
		case userWantsToUnbindOwnedIdentityFromKeycloak
		case userWantsToRemoveDraftFyleJoin
		case userWantsToChangeContactsSortOrder
		case userWantsToUpdateLocalConfigurationOfDiscussion
		case audioInputHasBeenActivated
		case aViewRequiresObvMutualScanUrl
		case userWantsToStartTrustEstablishmentWithMutualScanProtocol
		case insertDebugMessagesInAllExistingDiscussions
		case draftExpirationWasBeenUpdated
		case cleanExpiredMuteNotficationsThatExpiredEarlierThanNow
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
		case userWantsToStartIncrementalCleanBackup
		case incrementalCleanBackupStarts
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
		case backupForExportWasExported
		case backupForUploadWasUploaded
		case backupForUploadFailedToUpload
		case userWantsToAddOwnedProfile
		case userWantsToSwitchToOtherOwnedIdentity
		case userWantsToDeleteOwnedIdentityButHasNotConfirmedYet
		case userWantsToDeleteOwnedIdentityAndHasConfirmed
		case userWantsToHideOwnedIdentity
		case failedToHideOwnedIdentity
		case userWantsToSwitchToOtherHiddenOwnedIdentity
		case userWantsToUnhideOwnedIdentity
		case metaFlowControllerDidSwitchToOwnedIdentity
		case closeAnyOpenHiddenOwnedIdentity
		case userWantsToUpdateOwnedCustomDisplayName
		case userWantsToReorderDiscussions
		case betaUserWantsToDebugCoordinatorsQueue
		case betaUserWantsToSeeLogString
		case draftFyleJoinWasDeleted
		case draftToSendWasReset
		case fyleMessageJoinWasWiped
		case userWantsToUpdateDiscussionLocalConfiguration
		case userWantsToArchiveDiscussion
		case userWantsToUnarchiveDiscussion
		case userWantsToRefreshDiscussions
		case updateNormalizedSearchKeyOnPersistedDiscussions
		case aDiscussionSharedConfigurationIsNeededByContact
		case aDiscussionSharedConfigurationIsNeededByAnotherOwnedDevice
		case userWantsToDeleteOwnedContactGroup
		case singleOwnedIdentityFlowViewControllerDidAppear
		case userWantsToSetCustomNameOfJoinedGroupV1
		case userWantsToUpdatePersonalNoteOnContact
		case userWantsToUpdatePersonalNoteOnGroupV1
		case userWantsToUpdatePersonalNoteOnGroupV2
		case allPersistedInvitationCanBeMarkedAsOld
		case userHasSeenPublishedDetailsOfContactGroupJoined

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
			case .externalTransactionsWereMergedIntoViewContext: return Name.externalTransactionsWereMergedIntoViewContext.name
			case .newMuteExpiration: return Name.newMuteExpiration.name
			case .wipeAllMessagesThatExpiredEarlierThanNow: return Name.wipeAllMessagesThatExpiredEarlierThanNow.name
			case .userWantsToCallAndIsAllowedTo: return Name.userWantsToCallAndIsAllowedTo.name
			case .userWantsToSelectAndCallContacts: return Name.userWantsToSelectAndCallContacts.name
			case .userWantsToCallButWeShouldCheckSheIsAllowedTo: return Name.userWantsToCallButWeShouldCheckSheIsAllowedTo.name
			case .newWebRTCMessageWasReceived: return Name.newWebRTCMessageWasReceived.name
			case .newObvEncryptedPushNotificationWasReceivedViaPushKitNotification: return Name.newObvEncryptedPushNotificationWasReceivedViaPushKitNotification.name
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
			case .userWantsToNavigateToDeepLink: return Name.userWantsToNavigateToDeepLink.name
			case .useLoadBalancedTurnServersDidChange: return Name.useLoadBalancedTurnServersDidChange.name
			case .userWantsToReadReceivedMessageThatRequiresUserAction: return Name.userWantsToReadReceivedMessageThatRequiresUserAction.name
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
			case .serverDoesNotSuppoortCall: return Name.serverDoesNotSuppoortCall.name
			case .pastedStringIsNotValidOlvidURL: return Name.pastedStringIsNotValidOlvidURL.name
			case .userWantsToRestartChannelEstablishmentProtocol: return Name.userWantsToRestartChannelEstablishmentProtocol.name
			case .contactIdentityDetailsWereUpdated: return Name.contactIdentityDetailsWereUpdated.name
			case .userDidSeeNewDetailsOfContact: return Name.userDidSeeNewDetailsOfContact.name
			case .userWantsToEditContactNicknameAndPicture: return Name.userWantsToEditContactNicknameAndPicture.name
			case .userWantsToBindOwnedIdentityToKeycloak: return Name.userWantsToBindOwnedIdentityToKeycloak.name
			case .userWantsToUnbindOwnedIdentityFromKeycloak: return Name.userWantsToUnbindOwnedIdentityFromKeycloak.name
			case .userWantsToRemoveDraftFyleJoin: return Name.userWantsToRemoveDraftFyleJoin.name
			case .userWantsToChangeContactsSortOrder: return Name.userWantsToChangeContactsSortOrder.name
			case .userWantsToUpdateLocalConfigurationOfDiscussion: return Name.userWantsToUpdateLocalConfigurationOfDiscussion.name
			case .audioInputHasBeenActivated: return Name.audioInputHasBeenActivated.name
			case .aViewRequiresObvMutualScanUrl: return Name.aViewRequiresObvMutualScanUrl.name
			case .userWantsToStartTrustEstablishmentWithMutualScanProtocol: return Name.userWantsToStartTrustEstablishmentWithMutualScanProtocol.name
			case .insertDebugMessagesInAllExistingDiscussions: return Name.insertDebugMessagesInAllExistingDiscussions.name
			case .draftExpirationWasBeenUpdated: return Name.draftExpirationWasBeenUpdated.name
			case .cleanExpiredMuteNotficationsThatExpiredEarlierThanNow: return Name.cleanExpiredMuteNotficationsThatExpiredEarlierThanNow.name
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
			case .userWantsToStartIncrementalCleanBackup: return Name.userWantsToStartIncrementalCleanBackup.name
			case .incrementalCleanBackupStarts: return Name.incrementalCleanBackupStarts.name
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
			case .backupForExportWasExported: return Name.backupForExportWasExported.name
			case .backupForUploadWasUploaded: return Name.backupForUploadWasUploaded.name
			case .backupForUploadFailedToUpload: return Name.backupForUploadFailedToUpload.name
			case .userWantsToAddOwnedProfile: return Name.userWantsToAddOwnedProfile.name
			case .userWantsToSwitchToOtherOwnedIdentity: return Name.userWantsToSwitchToOtherOwnedIdentity.name
			case .userWantsToDeleteOwnedIdentityButHasNotConfirmedYet: return Name.userWantsToDeleteOwnedIdentityButHasNotConfirmedYet.name
			case .userWantsToDeleteOwnedIdentityAndHasConfirmed: return Name.userWantsToDeleteOwnedIdentityAndHasConfirmed.name
			case .userWantsToHideOwnedIdentity: return Name.userWantsToHideOwnedIdentity.name
			case .failedToHideOwnedIdentity: return Name.failedToHideOwnedIdentity.name
			case .userWantsToSwitchToOtherHiddenOwnedIdentity: return Name.userWantsToSwitchToOtherHiddenOwnedIdentity.name
			case .userWantsToUnhideOwnedIdentity: return Name.userWantsToUnhideOwnedIdentity.name
			case .metaFlowControllerDidSwitchToOwnedIdentity: return Name.metaFlowControllerDidSwitchToOwnedIdentity.name
			case .closeAnyOpenHiddenOwnedIdentity: return Name.closeAnyOpenHiddenOwnedIdentity.name
			case .userWantsToUpdateOwnedCustomDisplayName: return Name.userWantsToUpdateOwnedCustomDisplayName.name
			case .userWantsToReorderDiscussions: return Name.userWantsToReorderDiscussions.name
			case .betaUserWantsToDebugCoordinatorsQueue: return Name.betaUserWantsToDebugCoordinatorsQueue.name
			case .betaUserWantsToSeeLogString: return Name.betaUserWantsToSeeLogString.name
			case .draftFyleJoinWasDeleted: return Name.draftFyleJoinWasDeleted.name
			case .draftToSendWasReset: return Name.draftToSendWasReset.name
			case .fyleMessageJoinWasWiped: return Name.fyleMessageJoinWasWiped.name
			case .userWantsToUpdateDiscussionLocalConfiguration: return Name.userWantsToUpdateDiscussionLocalConfiguration.name
			case .userWantsToArchiveDiscussion: return Name.userWantsToArchiveDiscussion.name
			case .userWantsToUnarchiveDiscussion: return Name.userWantsToUnarchiveDiscussion.name
			case .userWantsToRefreshDiscussions: return Name.userWantsToRefreshDiscussions.name
			case .updateNormalizedSearchKeyOnPersistedDiscussions: return Name.updateNormalizedSearchKeyOnPersistedDiscussions.name
			case .aDiscussionSharedConfigurationIsNeededByContact: return Name.aDiscussionSharedConfigurationIsNeededByContact.name
			case .aDiscussionSharedConfigurationIsNeededByAnotherOwnedDevice: return Name.aDiscussionSharedConfigurationIsNeededByAnotherOwnedDevice.name
			case .userWantsToDeleteOwnedContactGroup: return Name.userWantsToDeleteOwnedContactGroup.name
			case .singleOwnedIdentityFlowViewControllerDidAppear: return Name.singleOwnedIdentityFlowViewControllerDidAppear.name
			case .userWantsToSetCustomNameOfJoinedGroupV1: return Name.userWantsToSetCustomNameOfJoinedGroupV1.name
			case .userWantsToUpdatePersonalNoteOnContact: return Name.userWantsToUpdatePersonalNoteOnContact.name
			case .userWantsToUpdatePersonalNoteOnGroupV1: return Name.userWantsToUpdatePersonalNoteOnGroupV1.name
			case .userWantsToUpdatePersonalNoteOnGroupV2: return Name.userWantsToUpdatePersonalNoteOnGroupV2.name
			case .allPersistedInvitationCanBeMarkedAsOld: return Name.allPersistedInvitationCanBeMarkedAsOld.name
			case .userHasSeenPublishedDetailsOfContactGroupJoined: return Name.userHasSeenPublishedDetailsOfContactGroupJoined.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .messagesAreNotNewAnymore(ownedCryptoId: let ownedCryptoId, discussionId: let discussionId, messageIds: let messageIds):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"discussionId": discussionId,
				"messageIds": messageIds,
			]
		case .userWantsToRefreshContactGroupJoined(obvContactGroup: let obvContactGroup):
			info = [
				"obvContactGroup": obvContactGroup,
			]
		case .externalTransactionsWereMergedIntoViewContext:
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
		case .userWantsToCallAndIsAllowedTo(ownedCryptoId: let ownedCryptoId, contactCryptoIds: let contactCryptoIds, ownedIdentityForRequestingTurnCredentials: let ownedIdentityForRequestingTurnCredentials, groupId: let groupId):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"contactCryptoIds": contactCryptoIds,
				"ownedIdentityForRequestingTurnCredentials": ownedIdentityForRequestingTurnCredentials,
				"groupId": OptionalWrapper(groupId),
			]
		case .userWantsToSelectAndCallContacts(ownedCryptoId: let ownedCryptoId, contactCryptoIds: let contactCryptoIds, groupId: let groupId):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"contactCryptoIds": contactCryptoIds,
				"groupId": OptionalWrapper(groupId),
			]
		case .userWantsToCallButWeShouldCheckSheIsAllowedTo(ownedCryptoId: let ownedCryptoId, contactCryptoIds: let contactCryptoIds, groupId: let groupId):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"contactCryptoIds": contactCryptoIds,
				"groupId": OptionalWrapper(groupId),
			]
		case .newWebRTCMessageWasReceived(webrtcMessage: let webrtcMessage, fromOlvidUser: let fromOlvidUser, messageUID: let messageUID):
			info = [
				"webrtcMessage": webrtcMessage,
				"fromOlvidUser": fromOlvidUser,
				"messageUID": messageUID,
			]
		case .newObvEncryptedPushNotificationWasReceivedViaPushKitNotification(encryptedNotification: let encryptedNotification):
			info = [
				"encryptedNotification": encryptedNotification,
			]
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
		case .userRequestedDeletionOfPersistedDiscussion(ownedCryptoId: let ownedCryptoId, discussionObjectID: let discussionObjectID, deletionType: let deletionType, completionHandler: let completionHandler):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"discussionObjectID": discussionObjectID,
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
		case .userWantsToNavigateToDeepLink(deepLink: let deepLink):
			info = [
				"deepLink": deepLink,
			]
		case .useLoadBalancedTurnServersDidChange:
			info = nil
		case .userWantsToReadReceivedMessageThatRequiresUserAction(ownedCryptoId: let ownedCryptoId, discussionId: let discussionId, messageId: let messageId):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"discussionId": discussionId,
				"messageId": messageId,
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
		case .userWantsToSetAndShareNewDiscussionSharedExpirationConfiguration(ownedCryptoId: let ownedCryptoId, discussionId: let discussionId, expirationJSON: let expirationJSON):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"discussionId": discussionId,
				"expirationJSON": expirationJSON,
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
		case .userWantsToSendEditedVersionOfSentMessage(ownedCryptoId: let ownedCryptoId, sentMessageObjectID: let sentMessageObjectID, newTextBody: let newTextBody):
			info = [
				"ownedCryptoId": ownedCryptoId,
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
		case .resyncContactIdentityDevicesWithEngine(obvContactIdentifier: let obvContactIdentifier):
			info = [
				"obvContactIdentifier": obvContactIdentifier,
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
		case .userWantsToEditContactNicknameAndPicture(persistedContactObjectID: let persistedContactObjectID, customDisplayName: let customDisplayName, customPhoto: let customPhoto):
			info = [
				"persistedContactObjectID": persistedContactObjectID,
				"customDisplayName": OptionalWrapper(customDisplayName),
				"customPhoto": OptionalWrapper(customPhoto),
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
		case .userWantsToUpdateLocalConfigurationOfDiscussion(value: let value, discussionPermanentID: let discussionPermanentID, completionHandler: let completionHandler):
			info = [
				"value": value,
				"discussionPermanentID": discussionPermanentID,
				"completionHandler": completionHandler,
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
		case .userWantsToUpdateReaction(ownedCryptoId: let ownedCryptoId, messageObjectID: let messageObjectID, newEmoji: let newEmoji):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"messageObjectID": messageObjectID,
				"newEmoji": OptionalWrapper(newEmoji),
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
		case .userWantsToStartIncrementalCleanBackup(cleanAllDevices: let cleanAllDevices):
			info = [
				"cleanAllDevices": cleanAllDevices,
			]
		case .incrementalCleanBackupStarts:
			info = nil
		case .incrementalCleanBackupTerminates:
			info = nil
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
		case .requestSyncAppDatabasesWithEngine(queuePriority: let queuePriority, isRestoringSyncSnapshotOrBackup: let isRestoringSyncSnapshotOrBackup, completion: let completion):
			info = [
				"queuePriority": queuePriority,
				"isRestoringSyncSnapshotOrBackup": isRestoringSyncSnapshotOrBackup,
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
		case .userRepliedToReceivedMessageWithinTheNotificationExtension(contactPermanentID: let contactPermanentID, messageIdentifierFromEngine: let messageIdentifierFromEngine, textBody: let textBody, completionHandler: let completionHandler):
			info = [
				"contactPermanentID": contactPermanentID,
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
				"textBody": textBody,
				"completionHandler": completionHandler,
			]
		case .userRepliedToMissedCallWithinTheNotificationExtension(discussionPermanentID: let discussionPermanentID, textBody: let textBody, completionHandler: let completionHandler):
			info = [
				"discussionPermanentID": discussionPermanentID,
				"textBody": textBody,
				"completionHandler": completionHandler,
			]
		case .userWantsToMarkAsReadMessageWithinTheNotificationExtension(contactPermanentID: let contactPermanentID, messageIdentifierFromEngine: let messageIdentifierFromEngine, completionHandler: let completionHandler):
			info = [
				"contactPermanentID": contactPermanentID,
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
		case .userWantsToForwardMessage(messagePermanentID: let messagePermanentID, discussionPermanentIDs: let discussionPermanentIDs):
			info = [
				"messagePermanentID": messagePermanentID,
				"discussionPermanentIDs": discussionPermanentIDs,
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
		case .userWantsToUpdateCustomNameAndGroupV2Photo(ownedCryptoId: let ownedCryptoId, groupIdentifier: let groupIdentifier, customName: let customName, customPhoto: let customPhoto):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"groupIdentifier": groupIdentifier,
				"customName": OptionalWrapper(customName),
				"customPhoto": OptionalWrapper(customPhoto),
			]
		case .userHasSeenPublishedDetailsOfGroupV2(groupObjectID: let groupObjectID):
			info = [
				"groupObjectID": groupObjectID,
			]
		case .tooManyWrongPasscodeAttemptsCausedLockOut:
			info = nil
		case .backupForExportWasExported:
			info = nil
		case .backupForUploadWasUploaded:
			info = nil
		case .backupForUploadFailedToUpload:
			info = nil
		case .userWantsToAddOwnedProfile:
			info = nil
		case .userWantsToSwitchToOtherOwnedIdentity(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
			]
		case .userWantsToDeleteOwnedIdentityButHasNotConfirmedYet(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
			]
		case .userWantsToDeleteOwnedIdentityAndHasConfirmed(ownedCryptoId: let ownedCryptoId, globalOwnedIdentityDeletion: let globalOwnedIdentityDeletion):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"globalOwnedIdentityDeletion": globalOwnedIdentityDeletion,
			]
		case .userWantsToHideOwnedIdentity(ownedCryptoId: let ownedCryptoId, password: let password):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"password": password,
			]
		case .failedToHideOwnedIdentity(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
			]
		case .userWantsToSwitchToOtherHiddenOwnedIdentity(password: let password):
			info = [
				"password": password,
			]
		case .userWantsToUnhideOwnedIdentity(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
			]
		case .metaFlowControllerDidSwitchToOwnedIdentity(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
			]
		case .closeAnyOpenHiddenOwnedIdentity:
			info = nil
		case .userWantsToUpdateOwnedCustomDisplayName(ownedCryptoId: let ownedCryptoId, newCustomDisplayName: let newCustomDisplayName):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"newCustomDisplayName": OptionalWrapper(newCustomDisplayName),
			]
		case .userWantsToReorderDiscussions(discussionObjectIds: let discussionObjectIds, ownedIdentity: let ownedIdentity, completionHandler: let completionHandler):
			info = [
				"discussionObjectIds": discussionObjectIds,
				"ownedIdentity": ownedIdentity,
				"completionHandler": OptionalWrapper(completionHandler),
			]
		case .betaUserWantsToDebugCoordinatorsQueue:
			info = nil
		case .betaUserWantsToSeeLogString(logString: let logString):
			info = [
				"logString": logString,
			]
		case .draftFyleJoinWasDeleted(discussionPermanentID: let discussionPermanentID, draftPermanentID: let draftPermanentID, draftFyleJoinPermanentID: let draftFyleJoinPermanentID):
			info = [
				"discussionPermanentID": discussionPermanentID,
				"draftPermanentID": draftPermanentID,
				"draftFyleJoinPermanentID": draftFyleJoinPermanentID,
			]
		case .draftToSendWasReset(discussionPermanentID: let discussionPermanentID, draftPermanentID: let draftPermanentID):
			info = [
				"discussionPermanentID": discussionPermanentID,
				"draftPermanentID": draftPermanentID,
			]
		case .fyleMessageJoinWasWiped(discussionPermanentID: let discussionPermanentID, messagePermanentID: let messagePermanentID, fyleMessageJoinPermanentID: let fyleMessageJoinPermanentID):
			info = [
				"discussionPermanentID": discussionPermanentID,
				"messagePermanentID": messagePermanentID,
				"fyleMessageJoinPermanentID": fyleMessageJoinPermanentID,
			]
		case .userWantsToUpdateDiscussionLocalConfiguration(value: let value, localConfigurationObjectID: let localConfigurationObjectID):
			info = [
				"value": value,
				"localConfigurationObjectID": localConfigurationObjectID,
			]
		case .userWantsToArchiveDiscussion(discussionPermanentID: let discussionPermanentID, completionHandler: let completionHandler):
			info = [
				"discussionPermanentID": discussionPermanentID,
				"completionHandler": OptionalWrapper(completionHandler),
			]
		case .userWantsToUnarchiveDiscussion(discussionPermanentID: let discussionPermanentID, updateTimestampOfLastMessage: let updateTimestampOfLastMessage, completionHandler: let completionHandler):
			info = [
				"discussionPermanentID": discussionPermanentID,
				"updateTimestampOfLastMessage": updateTimestampOfLastMessage,
				"completionHandler": OptionalWrapper(completionHandler),
			]
		case .userWantsToRefreshDiscussions(completionHandler: let completionHandler):
			info = [
				"completionHandler": completionHandler,
			]
		case .updateNormalizedSearchKeyOnPersistedDiscussions(ownedIdentity: let ownedIdentity, completionHandler: let completionHandler):
			info = [
				"ownedIdentity": ownedIdentity,
				"completionHandler": OptionalWrapper(completionHandler),
			]
		case .aDiscussionSharedConfigurationIsNeededByContact(contactIdentifier: let contactIdentifier, discussionId: let discussionId):
			info = [
				"contactIdentifier": contactIdentifier,
				"discussionId": discussionId,
			]
		case .aDiscussionSharedConfigurationIsNeededByAnotherOwnedDevice(ownedCryptoId: let ownedCryptoId, discussionId: let discussionId):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"discussionId": discussionId,
			]
		case .userWantsToDeleteOwnedContactGroup(ownedCryptoId: let ownedCryptoId, groupUid: let groupUid):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"groupUid": groupUid,
			]
		case .singleOwnedIdentityFlowViewControllerDidAppear(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
			]
		case .userWantsToSetCustomNameOfJoinedGroupV1(ownedCryptoId: let ownedCryptoId, groupId: let groupId, groupNameCustom: let groupNameCustom):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"groupId": groupId,
				"groupNameCustom": OptionalWrapper(groupNameCustom),
			]
		case .userWantsToUpdatePersonalNoteOnContact(contactIdentifier: let contactIdentifier, newText: let newText):
			info = [
				"contactIdentifier": contactIdentifier,
				"newText": OptionalWrapper(newText),
			]
		case .userWantsToUpdatePersonalNoteOnGroupV1(ownedCryptoId: let ownedCryptoId, groupId: let groupId, newText: let newText):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"groupId": groupId,
				"newText": OptionalWrapper(newText),
			]
		case .userWantsToUpdatePersonalNoteOnGroupV2(ownedCryptoId: let ownedCryptoId, groupIdentifier: let groupIdentifier, newText: let newText):
			info = [
				"ownedCryptoId": ownedCryptoId,
				"groupIdentifier": groupIdentifier,
				"newText": OptionalWrapper(newText),
			]
		case .allPersistedInvitationCanBeMarkedAsOld(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
			]
		case .userHasSeenPublishedDetailsOfContactGroupJoined(obvGroupIdentifier: let obvGroupIdentifier):
			info = [
				"obvGroupIdentifier": obvGroupIdentifier,
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

	static func observeMessagesAreNotNewAnymore(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, DiscussionIdentifier, [MessageIdentifier]) -> Void) -> NSObjectProtocol {
		let name = Name.messagesAreNotNewAnymore.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let discussionId = notification.userInfo!["discussionId"] as! DiscussionIdentifier
			let messageIds = notification.userInfo!["messageIds"] as! [MessageIdentifier]
			block(ownedCryptoId, discussionId, messageIds)
		}
	}

	static func observeUserWantsToRefreshContactGroupJoined(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvContactGroup) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToRefreshContactGroupJoined.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let obvContactGroup = notification.userInfo!["obvContactGroup"] as! ObvContactGroup
			block(obvContactGroup)
		}
	}

	static func observeExternalTransactionsWereMergedIntoViewContext(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.externalTransactionsWereMergedIntoViewContext.name
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

	static func observeWipeAllMessagesThatExpiredEarlierThanNow(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Bool, @escaping (Bool) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.wipeAllMessagesThatExpiredEarlierThanNow.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let launchedByBackgroundTask = notification.userInfo!["launchedByBackgroundTask"] as! Bool
			let completionHandler = notification.userInfo!["completionHandler"] as! (Bool) -> Void
			block(launchedByBackgroundTask, completionHandler)
		}
	}

	static func observeUserWantsToCallAndIsAllowedTo(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Set<ObvCryptoId>, ObvCryptoId, GroupIdentifier?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToCallAndIsAllowedTo.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let contactCryptoIds = notification.userInfo!["contactCryptoIds"] as! Set<ObvCryptoId>
			let ownedIdentityForRequestingTurnCredentials = notification.userInfo!["ownedIdentityForRequestingTurnCredentials"] as! ObvCryptoId
			let groupIdWrapper = notification.userInfo!["groupId"] as! OptionalWrapper<GroupIdentifier>
			let groupId = groupIdWrapper.value
			block(ownedCryptoId, contactCryptoIds, ownedIdentityForRequestingTurnCredentials, groupId)
		}
	}

	static func observeUserWantsToSelectAndCallContacts(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Set<ObvCryptoId>, GroupIdentifier?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToSelectAndCallContacts.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let contactCryptoIds = notification.userInfo!["contactCryptoIds"] as! Set<ObvCryptoId>
			let groupIdWrapper = notification.userInfo!["groupId"] as! OptionalWrapper<GroupIdentifier>
			let groupId = groupIdWrapper.value
			block(ownedCryptoId, contactCryptoIds, groupId)
		}
	}

	static func observeUserWantsToCallButWeShouldCheckSheIsAllowedTo(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Set<ObvCryptoId>, GroupIdentifier?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToCallButWeShouldCheckSheIsAllowedTo.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let contactCryptoIds = notification.userInfo!["contactCryptoIds"] as! Set<ObvCryptoId>
			let groupIdWrapper = notification.userInfo!["groupId"] as! OptionalWrapper<GroupIdentifier>
			let groupId = groupIdWrapper.value
			block(ownedCryptoId, contactCryptoIds, groupId)
		}
	}

	static func observeNewWebRTCMessageWasReceived(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (WebRTCMessageJSON, OlvidUserId, UID) -> Void) -> NSObjectProtocol {
		let name = Name.newWebRTCMessageWasReceived.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let webrtcMessage = notification.userInfo!["webrtcMessage"] as! WebRTCMessageJSON
			let fromOlvidUser = notification.userInfo!["fromOlvidUser"] as! OlvidUserId
			let messageUID = notification.userInfo!["messageUID"] as! UID
			block(webrtcMessage, fromOlvidUser, messageUID)
		}
	}

	static func observeNewObvEncryptedPushNotificationWasReceivedViaPushKitNotification(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvEncryptedPushNotification) -> Void) -> NSObjectProtocol {
		let name = Name.newObvEncryptedPushNotificationWasReceivedViaPushKitNotification.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let encryptedNotification = notification.userInfo!["encryptedNotification"] as! ObvEncryptedPushNotification
			block(encryptedNotification)
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

	static func observeUserRequestedDeletionOfPersistedDiscussion(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, TypeSafeManagedObjectID<PersistedDiscussion>, DeletionType, @escaping (Bool) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.userRequestedDeletionOfPersistedDiscussion.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let discussionObjectID = notification.userInfo!["discussionObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			let deletionType = notification.userInfo!["deletionType"] as! DeletionType
			let completionHandler = notification.userInfo!["completionHandler"] as! (Bool) -> Void
			block(ownedCryptoId, discussionObjectID, deletionType, completionHandler)
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

	static func observeUserWantsToReadReceivedMessageThatRequiresUserAction(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, DiscussionIdentifier, ReceivedMessageIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToReadReceivedMessageThatRequiresUserAction.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let discussionId = notification.userInfo!["discussionId"] as! DiscussionIdentifier
			let messageId = notification.userInfo!["messageId"] as! ReceivedMessageIdentifier
			block(ownedCryptoId, discussionId, messageId)
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

	static func observeUserWantsToSetAndShareNewDiscussionSharedExpirationConfiguration(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, DiscussionIdentifier, ExpirationJSON) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToSetAndShareNewDiscussionSharedExpirationConfiguration.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let discussionId = notification.userInfo!["discussionId"] as! DiscussionIdentifier
			let expirationJSON = notification.userInfo!["expirationJSON"] as! ExpirationJSON
			block(ownedCryptoId, discussionId, expirationJSON)
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

	static func observeApplyAllRetentionPoliciesNow(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Bool, @escaping (Bool) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.applyAllRetentionPoliciesNow.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let launchedByBackgroundTask = notification.userInfo!["launchedByBackgroundTask"] as! Bool
			let completionHandler = notification.userInfo!["completionHandler"] as! (Bool) -> Void
			block(launchedByBackgroundTask, completionHandler)
		}
	}

	static func observeUserWantsToSendEditedVersionOfSentMessage(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, TypeSafeManagedObjectID<PersistedMessageSent>, String) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToSendEditedVersionOfSentMessage.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let sentMessageObjectID = notification.userInfo!["sentMessageObjectID"] as! TypeSafeManagedObjectID<PersistedMessageSent>
			let newTextBody = notification.userInfo!["newTextBody"] as! String
			block(ownedCryptoId, sentMessageObjectID, newTextBody)
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

	static func observeResyncContactIdentityDevicesWithEngine(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvContactIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.resyncContactIdentityDevicesWithEngine.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let obvContactIdentifier = notification.userInfo!["obvContactIdentifier"] as! ObvContactIdentifier
			block(obvContactIdentifier)
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

	static func observeUserWantsToEditContactNicknameAndPicture(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, String?, UIImage?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToEditContactNicknameAndPicture.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedContactObjectID = notification.userInfo!["persistedContactObjectID"] as! NSManagedObjectID
			let customDisplayNameWrapper = notification.userInfo!["customDisplayName"] as! OptionalWrapper<String>
			let customDisplayName = customDisplayNameWrapper.value
			let customPhotoWrapper = notification.userInfo!["customPhoto"] as! OptionalWrapper<UIImage>
			let customPhoto = customPhotoWrapper.value
			block(persistedContactObjectID, customDisplayName, customPhoto)
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

	static func observeUserWantsToUpdateLocalConfigurationOfDiscussion(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (PersistedDiscussionLocalConfigurationValue, ObvManagedObjectPermanentID<PersistedDiscussion>, @escaping () -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUpdateLocalConfigurationOfDiscussion.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let value = notification.userInfo!["value"] as! PersistedDiscussionLocalConfigurationValue
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let completionHandler = notification.userInfo!["completionHandler"] as! () -> Void
			block(value, discussionPermanentID, completionHandler)
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

	static func observeUserWantsToUpdateReaction(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, TypeSafeManagedObjectID<PersistedMessage>, String?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUpdateReaction.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let messageObjectID = notification.userInfo!["messageObjectID"] as! TypeSafeManagedObjectID<PersistedMessage>
			let newEmojiWrapper = notification.userInfo!["newEmoji"] as! OptionalWrapper<String>
			let newEmoji = newEmojiWrapper.value
			block(ownedCryptoId, messageObjectID, newEmoji)
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

	static func observeUserWantsToStartIncrementalCleanBackup(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Bool) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToStartIncrementalCleanBackup.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let cleanAllDevices = notification.userInfo!["cleanAllDevices"] as! Bool
			block(cleanAllDevices)
		}
	}

	static func observeIncrementalCleanBackupStarts(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.incrementalCleanBackupStarts.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeIncrementalCleanBackupTerminates(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.incrementalCleanBackupTerminates.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
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

	static func observeUiRequiresSignedContactDetails(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, ObvCryptoId, @escaping (SignedObvKeycloakUserDetails?) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.uiRequiresSignedContactDetails.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedIdentityCryptoId = notification.userInfo!["ownedIdentityCryptoId"] as! ObvCryptoId
			let contactCryptoId = notification.userInfo!["contactCryptoId"] as! ObvCryptoId
			let completion = notification.userInfo!["completion"] as! (SignedObvKeycloakUserDetails?) -> Void
			block(ownedIdentityCryptoId, contactCryptoId, completion)
		}
	}

	static func observeRequestSyncAppDatabasesWithEngine(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Operation.QueuePriority, Bool, @escaping (Result<(coordinatorsQueue: OperationQueue, queueForComposedOperations: OperationQueue),Error>) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.requestSyncAppDatabasesWithEngine.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let queuePriority = notification.userInfo!["queuePriority"] as! Operation.QueuePriority
			let isRestoringSyncSnapshotOrBackup = notification.userInfo!["isRestoringSyncSnapshotOrBackup"] as! Bool
			let completion = notification.userInfo!["completion"] as! (Result<(coordinatorsQueue: OperationQueue, queueForComposedOperations: OperationQueue),Error>) -> Void
			block(queuePriority, isRestoringSyncSnapshotOrBackup, completion)
		}
	}

	static func observeUiRequiresSignedOwnedDetails(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, @escaping (SignedObvKeycloakUserDetails?) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.uiRequiresSignedOwnedDetails.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedIdentityCryptoId = notification.userInfo!["ownedIdentityCryptoId"] as! ObvCryptoId
			let completion = notification.userInfo!["completion"] as! (SignedObvKeycloakUserDetails?) -> Void
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

	static func observeUserRepliedToReceivedMessageWithinTheNotificationExtension(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedObvContactIdentity>, Data, String, @escaping () -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.userRepliedToReceivedMessageWithinTheNotificationExtension.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactPermanentID = notification.userInfo!["contactPermanentID"] as! ObvManagedObjectPermanentID<PersistedObvContactIdentity>
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			let textBody = notification.userInfo!["textBody"] as! String
			let completionHandler = notification.userInfo!["completionHandler"] as! () -> Void
			block(contactPermanentID, messageIdentifierFromEngine, textBody, completionHandler)
		}
	}

	static func observeUserRepliedToMissedCallWithinTheNotificationExtension(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, String, @escaping () -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.userRepliedToMissedCallWithinTheNotificationExtension.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let textBody = notification.userInfo!["textBody"] as! String
			let completionHandler = notification.userInfo!["completionHandler"] as! () -> Void
			block(discussionPermanentID, textBody, completionHandler)
		}
	}

	static func observeUserWantsToMarkAsReadMessageWithinTheNotificationExtension(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedObvContactIdentity>, Data, @escaping () -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToMarkAsReadMessageWithinTheNotificationExtension.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactPermanentID = notification.userInfo!["contactPermanentID"] as! ObvManagedObjectPermanentID<PersistedObvContactIdentity>
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			let completionHandler = notification.userInfo!["completionHandler"] as! () -> Void
			block(contactPermanentID, messageIdentifierFromEngine, completionHandler)
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

	static func observeUserWantsToForwardMessage(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedMessage>, Set<ObvManagedObjectPermanentID<PersistedDiscussion>>) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToForwardMessage.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let messagePermanentID = notification.userInfo!["messagePermanentID"] as! ObvManagedObjectPermanentID<PersistedMessage>
			let discussionPermanentIDs = notification.userInfo!["discussionPermanentIDs"] as! Set<ObvManagedObjectPermanentID<PersistedDiscussion>>
			block(messagePermanentID, discussionPermanentIDs)
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

	static func observeUserWantsToUpdateCustomNameAndGroupV2Photo(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Data, String?, UIImage?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUpdateCustomNameAndGroupV2Photo.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let groupIdentifier = notification.userInfo!["groupIdentifier"] as! Data
			let customNameWrapper = notification.userInfo!["customName"] as! OptionalWrapper<String>
			let customName = customNameWrapper.value
			let customPhotoWrapper = notification.userInfo!["customPhoto"] as! OptionalWrapper<UIImage>
			let customPhoto = customPhotoWrapper.value
			block(ownedCryptoId, groupIdentifier, customName, customPhoto)
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

	static func observeBackupForExportWasExported(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.backupForExportWasExported.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeBackupForUploadWasUploaded(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.backupForUploadWasUploaded.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeBackupForUploadFailedToUpload(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.backupForUploadFailedToUpload.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeUserWantsToAddOwnedProfile(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToAddOwnedProfile.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeUserWantsToSwitchToOtherOwnedIdentity(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToSwitchToOtherOwnedIdentity.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(ownedCryptoId)
		}
	}

	static func observeUserWantsToDeleteOwnedIdentityButHasNotConfirmedYet(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToDeleteOwnedIdentityButHasNotConfirmedYet.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(ownedCryptoId)
		}
	}

	static func observeUserWantsToDeleteOwnedIdentityAndHasConfirmed(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Bool) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToDeleteOwnedIdentityAndHasConfirmed.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let globalOwnedIdentityDeletion = notification.userInfo!["globalOwnedIdentityDeletion"] as! Bool
			block(ownedCryptoId, globalOwnedIdentityDeletion)
		}
	}

	static func observeUserWantsToHideOwnedIdentity(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, String) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToHideOwnedIdentity.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let password = notification.userInfo!["password"] as! String
			block(ownedCryptoId, password)
		}
	}

	static func observeFailedToHideOwnedIdentity(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.failedToHideOwnedIdentity.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(ownedCryptoId)
		}
	}

	static func observeUserWantsToSwitchToOtherHiddenOwnedIdentity(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (String) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToSwitchToOtherHiddenOwnedIdentity.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let password = notification.userInfo!["password"] as! String
			block(password)
		}
	}

	static func observeUserWantsToUnhideOwnedIdentity(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUnhideOwnedIdentity.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(ownedCryptoId)
		}
	}

	static func observeMetaFlowControllerDidSwitchToOwnedIdentity(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.metaFlowControllerDidSwitchToOwnedIdentity.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(ownedCryptoId)
		}
	}

	static func observeCloseAnyOpenHiddenOwnedIdentity(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.closeAnyOpenHiddenOwnedIdentity.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeUserWantsToUpdateOwnedCustomDisplayName(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, String?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUpdateOwnedCustomDisplayName.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let newCustomDisplayNameWrapper = notification.userInfo!["newCustomDisplayName"] as! OptionalWrapper<String>
			let newCustomDisplayName = newCustomDisplayNameWrapper.value
			block(ownedCryptoId, newCustomDisplayName)
		}
	}

	static func observeUserWantsToReorderDiscussions(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping ([NSManagedObjectID], ObvCryptoId, ((Bool) -> Void)?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToReorderDiscussions.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionObjectIds = notification.userInfo!["discussionObjectIds"] as! [NSManagedObjectID]
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			let completionHandlerWrapper = notification.userInfo!["completionHandler"] as! OptionalWrapper<((Bool) -> Void)>
			let completionHandler = completionHandlerWrapper.value
			block(discussionObjectIds, ownedIdentity, completionHandler)
		}
	}

	static func observeBetaUserWantsToDebugCoordinatorsQueue(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.betaUserWantsToDebugCoordinatorsQueue.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeBetaUserWantsToSeeLogString(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (String) -> Void) -> NSObjectProtocol {
		let name = Name.betaUserWantsToSeeLogString.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let logString = notification.userInfo!["logString"] as! String
			block(logString)
		}
	}

	static func observeDraftFyleJoinWasDeleted(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, ObvManagedObjectPermanentID<PersistedDraft>, ObvManagedObjectPermanentID<PersistedDraftFyleJoin>) -> Void) -> NSObjectProtocol {
		let name = Name.draftFyleJoinWasDeleted.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let draftPermanentID = notification.userInfo!["draftPermanentID"] as! ObvManagedObjectPermanentID<PersistedDraft>
			let draftFyleJoinPermanentID = notification.userInfo!["draftFyleJoinPermanentID"] as! ObvManagedObjectPermanentID<PersistedDraftFyleJoin>
			block(discussionPermanentID, draftPermanentID, draftFyleJoinPermanentID)
		}
	}

	static func observeDraftToSendWasReset(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, ObvManagedObjectPermanentID<PersistedDraft>) -> Void) -> NSObjectProtocol {
		let name = Name.draftToSendWasReset.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let draftPermanentID = notification.userInfo!["draftPermanentID"] as! ObvManagedObjectPermanentID<PersistedDraft>
			block(discussionPermanentID, draftPermanentID)
		}
	}

	static func observeFyleMessageJoinWasWiped(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, ObvManagedObjectPermanentID<PersistedMessage>, ObvManagedObjectPermanentID<FyleMessageJoinWithStatus>) -> Void) -> NSObjectProtocol {
		let name = Name.fyleMessageJoinWasWiped.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let messagePermanentID = notification.userInfo!["messagePermanentID"] as! ObvManagedObjectPermanentID<PersistedMessage>
			let fyleMessageJoinPermanentID = notification.userInfo!["fyleMessageJoinPermanentID"] as! ObvManagedObjectPermanentID<FyleMessageJoinWithStatus>
			block(discussionPermanentID, messagePermanentID, fyleMessageJoinPermanentID)
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

	static func observeUserWantsToArchiveDiscussion(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, ((Bool) -> Void)?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToArchiveDiscussion.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let completionHandlerWrapper = notification.userInfo!["completionHandler"] as! OptionalWrapper<((Bool) -> Void)>
			let completionHandler = completionHandlerWrapper.value
			block(discussionPermanentID, completionHandler)
		}
	}

	static func observeUserWantsToUnarchiveDiscussion(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvManagedObjectPermanentID<PersistedDiscussion>, Bool, ((Bool) -> Void)?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUnarchiveDiscussion.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let discussionPermanentID = notification.userInfo!["discussionPermanentID"] as! ObvManagedObjectPermanentID<PersistedDiscussion>
			let updateTimestampOfLastMessage = notification.userInfo!["updateTimestampOfLastMessage"] as! Bool
			let completionHandlerWrapper = notification.userInfo!["completionHandler"] as! OptionalWrapper<((Bool) -> Void)>
			let completionHandler = completionHandlerWrapper.value
			block(discussionPermanentID, updateTimestampOfLastMessage, completionHandler)
		}
	}

	static func observeUserWantsToRefreshDiscussions(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (@escaping (() -> Void)) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToRefreshDiscussions.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let completionHandler = notification.userInfo!["completionHandler"] as! (() -> Void)
			block(completionHandler)
		}
	}

	static func observeUpdateNormalizedSearchKeyOnPersistedDiscussions(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, (() -> Void)?) -> Void) -> NSObjectProtocol {
		let name = Name.updateNormalizedSearchKeyOnPersistedDiscussions.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoId
			let completionHandlerWrapper = notification.userInfo!["completionHandler"] as! OptionalWrapper<(() -> Void)>
			let completionHandler = completionHandlerWrapper.value
			block(ownedIdentity, completionHandler)
		}
	}

	static func observeADiscussionSharedConfigurationIsNeededByContact(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvContactIdentifier, DiscussionIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.aDiscussionSharedConfigurationIsNeededByContact.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactIdentifier = notification.userInfo!["contactIdentifier"] as! ObvContactIdentifier
			let discussionId = notification.userInfo!["discussionId"] as! DiscussionIdentifier
			block(contactIdentifier, discussionId)
		}
	}

	static func observeADiscussionSharedConfigurationIsNeededByAnotherOwnedDevice(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, DiscussionIdentifier) -> Void) -> NSObjectProtocol {
		let name = Name.aDiscussionSharedConfigurationIsNeededByAnotherOwnedDevice.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let discussionId = notification.userInfo!["discussionId"] as! DiscussionIdentifier
			block(ownedCryptoId, discussionId)
		}
	}

	static func observeUserWantsToDeleteOwnedContactGroup(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, UID) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToDeleteOwnedContactGroup.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let groupUid = notification.userInfo!["groupUid"] as! UID
			block(ownedCryptoId, groupUid)
		}
	}

	static func observeSingleOwnedIdentityFlowViewControllerDidAppear(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.singleOwnedIdentityFlowViewControllerDidAppear.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(ownedCryptoId)
		}
	}

	static func observeUserWantsToSetCustomNameOfJoinedGroupV1(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, GroupV1Identifier, String?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToSetCustomNameOfJoinedGroupV1.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let groupId = notification.userInfo!["groupId"] as! GroupV1Identifier
			let groupNameCustomWrapper = notification.userInfo!["groupNameCustom"] as! OptionalWrapper<String>
			let groupNameCustom = groupNameCustomWrapper.value
			block(ownedCryptoId, groupId, groupNameCustom)
		}
	}

	static func observeUserWantsToUpdatePersonalNoteOnContact(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvContactIdentifier, String?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUpdatePersonalNoteOnContact.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactIdentifier = notification.userInfo!["contactIdentifier"] as! ObvContactIdentifier
			let newTextWrapper = notification.userInfo!["newText"] as! OptionalWrapper<String>
			let newText = newTextWrapper.value
			block(contactIdentifier, newText)
		}
	}

	static func observeUserWantsToUpdatePersonalNoteOnGroupV1(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, GroupV1Identifier, String?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUpdatePersonalNoteOnGroupV1.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let groupId = notification.userInfo!["groupId"] as! GroupV1Identifier
			let newTextWrapper = notification.userInfo!["newText"] as! OptionalWrapper<String>
			let newText = newTextWrapper.value
			block(ownedCryptoId, groupId, newText)
		}
	}

	static func observeUserWantsToUpdatePersonalNoteOnGroupV2(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId, Data, String?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUpdatePersonalNoteOnGroupV2.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			let groupIdentifier = notification.userInfo!["groupIdentifier"] as! Data
			let newTextWrapper = notification.userInfo!["newText"] as! OptionalWrapper<String>
			let newText = newTextWrapper.value
			block(ownedCryptoId, groupIdentifier, newText)
		}
	}

	static func observeAllPersistedInvitationCanBeMarkedAsOld(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoId) -> Void) -> NSObjectProtocol {
		let name = Name.allPersistedInvitationCanBeMarkedAsOld.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let ownedCryptoId = notification.userInfo!["ownedCryptoId"] as! ObvCryptoId
			block(ownedCryptoId)
		}
	}

	static func observeUserHasSeenPublishedDetailsOfContactGroupJoined(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvGroupV1Identifier) -> Void) -> NSObjectProtocol {
		let name = Name.userHasSeenPublishedDetailsOfContactGroupJoined.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let obvGroupIdentifier = notification.userInfo!["obvGroupIdentifier"] as! ObvGroupV1Identifier
			block(obvGroupIdentifier)
		}
	}

}
