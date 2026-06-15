/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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

import UIKit
import ObvEngine
import ObvUICoreData
import ObvTypes
import ObvAppTypes

@MainActor
protocol SingleDiscussionViewControllerDelegate: AnyObject {
    
    func userTappedTitleOfDiscussion(_ vc: NewSingleDiscussionViewController, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>)
    func userDidTapOnContactImage(contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>)


    /// Delegation method called whenever a user taps on a user mention within the text
    /// - Parameters:
    ///   - viewController: An instance of ``SomeSingleDiscussionViewController``.
    ///   - mentionableIdentity: An instance of ``ObvMentionableIdentityAttribute.Value`` that the user tapped.
    func singleDiscussionViewController(_ viewController: SomeSingleDiscussionViewController, userDidTapOn mentionableIdentity: ObvMentionAttribute.Value) async
    
    func userWantsToSendDraft(_ singleDiscussionViewController: SomeSingleDiscussionViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, textBody: AttributedString) async throws
    func userWantsToAddAttachmentsToDraft(_ singleDiscussionViewController: SomeSingleDiscussionViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, itemProviders: [NSItemProvider], source: LoadItemProviderHelper.ItemProviderProviderSource) async throws -> [LoadedItemProviderToPaste]
    func userWantsToAddAttachmentsToDraftFromURLs(_ singleDiscussionViewController: SomeSingleDiscussionViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, urls: [URL]) async throws
    func userWantsToUpdateDraftBodyAndMentions(_ singleDiscussionViewController: SomeSingleDiscussionViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, body: AttributedString) async throws
    func userWantsToDeleteDraftAttachment(_ singleDiscussionViewController: SomeSingleDiscussionViewController, draftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>) async throws
    func userWantsToReplyToMessage(_ singleDiscussionViewController: SomeSingleDiscussionViewController, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws
    func userWantsToDownloadReceivedFyleMessageJoinWithStatus(_ singleDiscussionViewController: SomeSingleDiscussionViewController, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws
    func userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(_ singleDiscussionViewController: SomeSingleDiscussionViewController, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws
    func userWantsToDownloadSentFyleMessageJoinWithStatusFromOtherOwnedDevice(_ singleDiscussionViewController: SomeSingleDiscussionViewController, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws
    func userWantsToPauseSentFyleMessageJoinWithStatusFromOtherOwnedDevice(_ singleDiscussionViewController: SomeSingleDiscussionViewController, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws
    func userWantsToRemoveReplyToMessage(_ singleDiscussionViewController: SomeSingleDiscussionViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws
    func insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(_ singleDiscussionViewController: SomeSingleDiscussionViewController, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, markAsRead: Bool) async throws
    func userWantsToUpdateDraftExpiration(_ singleDiscussionViewController: SomeSingleDiscussionViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, value: PersistedDiscussionSharedConfigurationValue?) async throws
    func userWantsToReadReceivedMessageThatRequiresUserAction(_ singleDiscussionViewController: SomeSingleDiscussionViewController, ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageId: ReceivedMessageIdentifier) async throws
    func updatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(_ singleDiscussionViewController: SomeSingleDiscussionViewController, discussionPermanentID: ObvUICoreData.ObvManagedObjectPermanentID<ObvUICoreData.PersistedDiscussion>, messagePermanentIDs: Set<ObvUICoreData.ObvManagedObjectPermanentID<ObvUICoreData.PersistedMessage>>) async throws
    func messagesAreNotNewAnymore(_ singleDiscussionViewController: SomeSingleDiscussionViewController, ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageIds: [MessageIdentifier]) async throws
    func userWantsToUpdateReaction(_ singleDiscussionViewController: SomeSingleDiscussionViewController, ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, newEmoji: String?) async throws
    func userWantsToUpdatePollVote(_ singleDiscussionViewController: SomeSingleDiscussionViewController, ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, pollVoteCandidateUuid: UUID, voted: Bool, version: Int) async throws
    func userWantsToShowMapToConsultLocationSharedContinously(_ singleDiscussionViewController: SomeSingleDiscussionViewController, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>) async throws
    func userWantsToShowMapToSendOrShareLocationContinuously(_ singleDiscussionViewController: SomeSingleDiscussionViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws
    func userWantsToCreatePoll(_ singleDiscussionViewController: SomeSingleDiscussionViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws
    func userWantsToDisplayPollView(_ singleDiscussionViewController: SomeSingleDiscussionViewController, pollObjectID: TypeSafeManagedObjectID<PersistedPoll>) async throws
    func userWantsToStopSharingLocationInDiscussion(_ singleDiscussionViewController: SomeSingleDiscussionViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws
    
    func userWantsToProcessReceiptsStoredForLater(_ singleDiscussionViewController: SomeSingleDiscussionViewController, ownedCryptoId: ObvCryptoId, returnReceiptElements: Set<ObvReturnReceiptElements>) async

    func discussionViewWillAppear(_ singleDiscussionViewController: SomeSingleDiscussionViewController)
    func discussionViewWillDisappear(_ singleDiscussionViewController: SomeSingleDiscussionViewController)
    
    func userWantsToDisplayContactIntroductionScreen(_ singleDiscussionViewController: SomeSingleDiscussionViewController, contactIdentifier: ObvTypes.ObvContactIdentifier)
    
    func userWantsToUpdateDiscussionLocalConfiguration(_ vc: SomeSingleDiscussionViewController, value: PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>) async throws

    func userWantsToForwardMessage(_ vc: SomeSingleDiscussionViewController, identifierOfMessageToForwad: ObvMessageAppIdentifier, identifiersOfDiscussionsWhereMessageShouldBeForwarded: Set<ObvDiscussionIdentifier>) async throws
    
}
