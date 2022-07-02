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
	case persistedMessageReceivedWasDeleted(objectID: NSManagedObjectID, messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, sortIndex: Double, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>)
	case userWantsToRefreshContactGroupJoined(obvContactGroup: ObvContactGroup)
	case currentOwnedCryptoIdChanged(newOwnedCryptoId: ObvCryptoId, apiKey: UUID)
	case userWantsToPerfomCloudKitBackupNow
	case externalTransactionsWereMergedIntoViewContext
	case userWantsToPerfomBackupForExportNow(sourceView: UIView)
	case newMuteExpiration(expirationDate: Date)
	case wipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask: Bool, completionHandler: (Bool) -> Void)
	case fyleMessageJoinWithStatusHasNewProgress(objectID: NSManagedObjectID, progress: Progress)
	case aViewRequiresFyleMessageJoinWithStatusProgresses(objectIDs: [NSManagedObjectID])
	case userWantsToCallAndIsAllowedTo(contactIds: [OlvidUserId], groupId: (groupUid: UID, groupOwner: ObvCryptoId)?)
	case userWantsToSelectAndCallContacts(contactIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>], groupId: (groupUid: UID, groupOwner: ObvCryptoId)?)
	case userWantsToCallButWeShouldCheckSheIsAllowedTo(contactIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>], groupId: (groupUid: UID, groupOwner: ObvCryptoId)?)
	case newWebRTCMessageWasReceived(webrtcMessage: WebRTCMessageJSON, contactId: OlvidUserId, messageUploadTimestampFromServer: Date, messageIdentifierFromEngine: Data)
	case toggleCallView
	case hideCallView
	case newObvMessageWasReceivedViaPushKitNotification(obvMessage: ObvMessage)
	case newWebRTCMessageToSend(webrtcMessage: WebRTCMessageJSON, contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, forStartingCall: Bool)
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
	case persistedMessageReceivedWasRead(persistedMessageReceivedObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>)
	case userWantsToSetAndShareNewDiscussionSharedExpirationConfiguration(persistedDiscussionObjectID: NSManagedObjectID, expirationJSON: ExpirationJSON, ownedCryptoId: ObvCryptoId)
	case persistedDiscussionSharedConfigurationShouldBeSent(persistedDiscussionObjectID: NSManagedObjectID)
	case userWantsToDeleteContact(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId, viewController: UIViewController, completionHandler: ((Bool) -> Void))
	case cleanExpiredMessagesBackgroundTaskWasLaunched(completionHandler: (Bool) -> Void)
	case applyRetentionPoliciesBackgroundTaskWasLaunched(completionHandler: (Bool) -> Void)
	case updateBadgeBackgroundTaskWasLaunched(completionHandler: (Bool) -> Void)
	case applyAllRetentionPoliciesNow(launchedByBackgroundTask: Bool, completionHandler: (Bool) -> Void)
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
	case contactIdentityDetailsWereUpdated(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case userDidSeeNewDetailsOfContact(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId)
	case userWantsToEditContactNicknameAndPicture(persistedContactObjectID: NSManagedObjectID, nicknameAndPicture: CustomNicknameAndPicture)
	case userWantsToBindOwnedIdentityToKeycloak(ownedCryptoId: ObvCryptoId, obvKeycloakState: ObvKeycloakState, keycloakUserId: String, completionHandler: (Bool) -> Void)
	case userWantsToUnbindOwnedIdentityFromKeycloak(ownedCryptoId: ObvCryptoId, completionHandler: (Bool) -> Void)
	case requestHardLinkToFyle(fyleElement: FyleElement, completionHandler: ((Result<HardLinkToFyle,Error>) -> Void))
	case requestAllHardLinksToFyles(fyleElements: [FyleElement], completionHandler: (([HardLinkToFyle?]) -> Void))
	case userWantsToRemoveDraftFyleJoin(draftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>)
	case userWantsToChangeContactsSortOrder(ownedCryptoId: ObvCryptoId, sortOrder: ContactsSortOrder)
	case userWantsToUpdateLocalConfigurationOfDiscussion(value: PersistedDiscussionLocalConfigurationValue, persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, completionHandler: (Bool) -> Void)
	case discussionLocalConfigurationHasBeenUpdated(newValue: PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>)
	case audioInputHasBeenActivated(label: String, activate: () -> Void)
	case aViewRequiresObvMutualScanUrl(remoteIdentity: Data, ownedCryptoId: ObvCryptoId, completionHandler: ((ObvMutualScanUrl) -> Void))
	case userWantsToStartTrustEstablishmentWithMutualScanProtocol(ownedCryptoId: ObvCryptoId, mutualScanUrl: ObvMutualScanUrl)
	case insertDebugMessagesInAllExistingDiscussions
	case draftExpirationWasBeenUpdated(persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>)
	case badgesNeedToBeUpdated(ownedCryptoId: ObvCryptoId)
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
	case userRepliedToReceivedMessageWithinTheNotificationExtension(persistedContactObjectID: NSManagedObjectID, messageIdentifierFromEngine: Data, textBody: String, completionHandler: (Bool) -> Void)
	case userRepliedToMissedCallWithinTheNotificationExtension(persistedDiscussionObjectID: NSManagedObjectID, textBody: String, completionHandler: (Bool) -> Void)
	case userWantsToMarkAsReadMessageWithinTheNotificationExtension(persistedContactObjectID: NSManagedObjectID, messageIdentifierFromEngine: Data, completionHandler: (Bool) -> Void)
	case userWantsToWipeFyleMessageJoinWithStatus(objectIDs: Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>)

	private enum Name {
		case messagesAreNotNewAnymore
		case persistedMessageReceivedWasDeleted
		case userWantsToRefreshContactGroupJoined
		case currentOwnedCryptoIdChanged
		case userWantsToPerfomCloudKitBackupNow
		case externalTransactionsWereMergedIntoViewContext
		case userWantsToPerfomBackupForExportNow
		case newMuteExpiration
		case wipeAllMessagesThatExpiredEarlierThanNow
		case fyleMessageJoinWithStatusHasNewProgress
		case aViewRequiresFyleMessageJoinWithStatusProgresses
		case userWantsToCallAndIsAllowedTo
		case userWantsToSelectAndCallContacts
		case userWantsToCallButWeShouldCheckSheIsAllowedTo
		case newWebRTCMessageWasReceived
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
		case persistedMessageReceivedWasRead
		case userWantsToSetAndShareNewDiscussionSharedExpirationConfiguration
		case persistedDiscussionSharedConfigurationShouldBeSent
		case userWantsToDeleteContact
		case cleanExpiredMessagesBackgroundTaskWasLaunched
		case applyRetentionPoliciesBackgroundTaskWasLaunched
		case updateBadgeBackgroundTaskWasLaunched
		case applyAllRetentionPoliciesNow
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
		case contactIdentityDetailsWereUpdated
		case userDidSeeNewDetailsOfContact
		case userWantsToEditContactNicknameAndPicture
		case userWantsToBindOwnedIdentityToKeycloak
		case userWantsToUnbindOwnedIdentityFromKeycloak
		case requestHardLinkToFyle
		case requestAllHardLinksToFyles
		case userWantsToRemoveDraftFyleJoin
		case userWantsToChangeContactsSortOrder
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

		private var namePrefix: String { String(describing: ObvMessengerInternalNotification.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: ObvMessengerInternalNotification) -> NSNotification.Name {
			switch notification {
			case .messagesAreNotNewAnymore: return Name.messagesAreNotNewAnymore.name
			case .persistedMessageReceivedWasDeleted: return Name.persistedMessageReceivedWasDeleted.name
			case .userWantsToRefreshContactGroupJoined: return Name.userWantsToRefreshContactGroupJoined.name
			case .currentOwnedCryptoIdChanged: return Name.currentOwnedCryptoIdChanged.name
			case .userWantsToPerfomCloudKitBackupNow: return Name.userWantsToPerfomCloudKitBackupNow.name
			case .externalTransactionsWereMergedIntoViewContext: return Name.externalTransactionsWereMergedIntoViewContext.name
			case .userWantsToPerfomBackupForExportNow: return Name.userWantsToPerfomBackupForExportNow.name
			case .newMuteExpiration: return Name.newMuteExpiration.name
			case .wipeAllMessagesThatExpiredEarlierThanNow: return Name.wipeAllMessagesThatExpiredEarlierThanNow.name
			case .fyleMessageJoinWithStatusHasNewProgress: return Name.fyleMessageJoinWithStatusHasNewProgress.name
			case .aViewRequiresFyleMessageJoinWithStatusProgresses: return Name.aViewRequiresFyleMessageJoinWithStatusProgresses.name
			case .userWantsToCallAndIsAllowedTo: return Name.userWantsToCallAndIsAllowedTo.name
			case .userWantsToSelectAndCallContacts: return Name.userWantsToSelectAndCallContacts.name
			case .userWantsToCallButWeShouldCheckSheIsAllowedTo: return Name.userWantsToCallButWeShouldCheckSheIsAllowedTo.name
			case .newWebRTCMessageWasReceived: return Name.newWebRTCMessageWasReceived.name
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
			case .persistedMessageReceivedWasRead: return Name.persistedMessageReceivedWasRead.name
			case .userWantsToSetAndShareNewDiscussionSharedExpirationConfiguration: return Name.userWantsToSetAndShareNewDiscussionSharedExpirationConfiguration.name
			case .persistedDiscussionSharedConfigurationShouldBeSent: return Name.persistedDiscussionSharedConfigurationShouldBeSent.name
			case .userWantsToDeleteContact: return Name.userWantsToDeleteContact.name
			case .cleanExpiredMessagesBackgroundTaskWasLaunched: return Name.cleanExpiredMessagesBackgroundTaskWasLaunched.name
			case .applyRetentionPoliciesBackgroundTaskWasLaunched: return Name.applyRetentionPoliciesBackgroundTaskWasLaunched.name
			case .updateBadgeBackgroundTaskWasLaunched: return Name.updateBadgeBackgroundTaskWasLaunched.name
			case .applyAllRetentionPoliciesNow: return Name.applyAllRetentionPoliciesNow.name
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
			case .contactIdentityDetailsWereUpdated: return Name.contactIdentityDetailsWereUpdated.name
			case .userDidSeeNewDetailsOfContact: return Name.userDidSeeNewDetailsOfContact.name
			case .userWantsToEditContactNicknameAndPicture: return Name.userWantsToEditContactNicknameAndPicture.name
			case .userWantsToBindOwnedIdentityToKeycloak: return Name.userWantsToBindOwnedIdentityToKeycloak.name
			case .userWantsToUnbindOwnedIdentityFromKeycloak: return Name.userWantsToUnbindOwnedIdentityFromKeycloak.name
			case .requestHardLinkToFyle: return Name.requestHardLinkToFyle.name
			case .requestAllHardLinksToFyles: return Name.requestAllHardLinksToFyles.name
			case .userWantsToRemoveDraftFyleJoin: return Name.userWantsToRemoveDraftFyleJoin.name
			case .userWantsToChangeContactsSortOrder: return Name.userWantsToChangeContactsSortOrder.name
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
		case .persistedMessageReceivedWasDeleted(objectID: let objectID, messageIdentifierFromEngine: let messageIdentifierFromEngine, ownedCryptoId: let ownedCryptoId, sortIndex: let sortIndex, discussionObjectID: let discussionObjectID):
			info = [
				"objectID": objectID,
				"messageIdentifierFromEngine": messageIdentifierFromEngine,
				"ownedCryptoId": ownedCryptoId,
				"sortIndex": sortIndex,
				"discussionObjectID": discussionObjectID,
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
		case .userWantsToPerfomBackupForExportNow(sourceView: let sourceView):
			info = [
				"sourceView": sourceView,
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
		case .fyleMessageJoinWithStatusHasNewProgress(objectID: let objectID, progress: let progress):
			info = [
				"objectID": objectID,
				"progress": progress,
			]
		case .aViewRequiresFyleMessageJoinWithStatusProgresses(objectIDs: let objectIDs):
			info = [
				"objectIDs": objectIDs,
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
		case .toggleCallView:
			info = nil
		case .hideCallView:
			info = nil
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
		case .persistedMessageReceivedWasRead(persistedMessageReceivedObjectID: let persistedMessageReceivedObjectID):
			info = [
				"persistedMessageReceivedObjectID": persistedMessageReceivedObjectID,
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
		case .badgesNeedToBeUpdated(ownedCryptoId: let ownedCryptoId):
			info = [
				"ownedCryptoId": ownedCryptoId,
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
		case .userWantsToWipeFyleMessageJoinWithStatus(objectIDs: let objectIDs):
			info = [
				"objectIDs": objectIDs,
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

	static func observeUserWantsToPerfomBackupForExportNow(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (UIView) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToPerfomBackupForExportNow.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let sourceView = notification.userInfo!["sourceView"] as! UIView
			block(sourceView)
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

	static func observeUserWantsToCallAndIsAllowedTo(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping ([OlvidUserId], (groupUid: UID, groupOwner: ObvCryptoId)?) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToCallAndIsAllowedTo.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let contactIds = notification.userInfo!["contactIds"] as! [OlvidUserId]
			let groupIdWrapper = notification.userInfo!["groupId"] as! OptionalWrapper<(groupUid: UID, groupOwner: ObvCryptoId)>
			let groupId = groupIdWrapper.value
			block(contactIds, groupId)
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

	static func observePersistedMessageReceivedWasRead(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (TypeSafeManagedObjectID<PersistedMessageReceived>) -> Void) -> NSObjectProtocol {
		let name = Name.persistedMessageReceivedWasRead.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedMessageReceivedObjectID = notification.userInfo!["persistedMessageReceivedObjectID"] as! TypeSafeManagedObjectID<PersistedMessageReceived>
			block(persistedMessageReceivedObjectID)
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

	static func observeRequestHardLinkToFyle(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (FyleElement, @escaping ((Result<HardLinkToFyle,Error>) -> Void)) -> Void) -> NSObjectProtocol {
		let name = Name.requestHardLinkToFyle.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let fyleElement = notification.userInfo!["fyleElement"] as! FyleElement
			let completionHandler = notification.userInfo!["completionHandler"] as! ((Result<HardLinkToFyle,Error>) -> Void)
			block(fyleElement, completionHandler)
		}
	}

	static func observeRequestAllHardLinksToFyles(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping ([FyleElement], @escaping (([HardLinkToFyle?]) -> Void)) -> Void) -> NSObjectProtocol {
		let name = Name.requestAllHardLinksToFyles.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let fyleElements = notification.userInfo!["fyleElements"] as! [FyleElement]
			let completionHandler = notification.userInfo!["completionHandler"] as! (([HardLinkToFyle?]) -> Void)
			block(fyleElements, completionHandler)
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

	static func observeUserWantsToUpdateLocalConfigurationOfDiscussion(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (PersistedDiscussionLocalConfigurationValue, TypeSafeManagedObjectID<PersistedDiscussion>, @escaping (Bool) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToUpdateLocalConfigurationOfDiscussion.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let value = notification.userInfo!["value"] as! PersistedDiscussionLocalConfigurationValue
			let persistedDiscussionObjectID = notification.userInfo!["persistedDiscussionObjectID"] as! TypeSafeManagedObjectID<PersistedDiscussion>
			let completionHandler = notification.userInfo!["completionHandler"] as! (Bool) -> Void
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

	static func observeUserRepliedToReceivedMessageWithinTheNotificationExtension(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, Data, String, @escaping (Bool) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.userRepliedToReceivedMessageWithinTheNotificationExtension.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedContactObjectID = notification.userInfo!["persistedContactObjectID"] as! NSManagedObjectID
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			let textBody = notification.userInfo!["textBody"] as! String
			let completionHandler = notification.userInfo!["completionHandler"] as! (Bool) -> Void
			block(persistedContactObjectID, messageIdentifierFromEngine, textBody, completionHandler)
		}
	}

	static func observeUserRepliedToMissedCallWithinTheNotificationExtension(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, String, @escaping (Bool) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.userRepliedToMissedCallWithinTheNotificationExtension.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedDiscussionObjectID = notification.userInfo!["persistedDiscussionObjectID"] as! NSManagedObjectID
			let textBody = notification.userInfo!["textBody"] as! String
			let completionHandler = notification.userInfo!["completionHandler"] as! (Bool) -> Void
			block(persistedDiscussionObjectID, textBody, completionHandler)
		}
	}

	static func observeUserWantsToMarkAsReadMessageWithinTheNotificationExtension(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (NSManagedObjectID, Data, @escaping (Bool) -> Void) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToMarkAsReadMessageWithinTheNotificationExtension.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let persistedContactObjectID = notification.userInfo!["persistedContactObjectID"] as! NSManagedObjectID
			let messageIdentifierFromEngine = notification.userInfo!["messageIdentifierFromEngine"] as! Data
			let completionHandler = notification.userInfo!["completionHandler"] as! (Bool) -> Void
			block(persistedContactObjectID, messageIdentifierFromEngine, completionHandler)
		}
	}

	static func observeUserWantsToWipeFyleMessageJoinWithStatus(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>) -> Void) -> NSObjectProtocol {
		let name = Name.userWantsToWipeFyleMessageJoinWithStatus.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let objectIDs = notification.userInfo!["objectIDs"] as! Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>
			block(objectIDs)
		}
	}

}
