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
import CoreData
import ObvEngine
import ObvUICoreData
import ObvTypes
import ObvAppTypes

@MainActor
protocol SingleDiscussionViewControllerDelegate: AnyObject {
    
    /// Takes the reader to whoever the discussion is with — the contact's sheet, or the group.
    ///
    /// Its sender is a `SomeSingleDiscussionViewController` and not the legacy controller, since the SwiftUI screen asks for this too: a system message reporting a
    /// change among the members of a group answers a tap by behaving as if the title had been tapped. The implementation never used its sender.
    func userTappedTitleOfDiscussion(_ vc: SomeSingleDiscussionViewController, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>)
    func userDidTapOnContactImage(contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>)

    /// Shows the reader a contact — asked by the SwiftUI screen when a sender's name or picture is tapped.
    ///
    /// **The identifier and not an object ID**, unlike the method above. That one exists because a legacy cell had an object ID to offer, and its implementation
    /// spends a fetch turning it back into exactly this identifier before presenting anything: the destination, `.contactDetails(contactIdentifier:)`, has always
    /// been keyed this way. A screen that already knows the identifier has no reason to make the round trip. This can replace the method above when the legacy
    /// screen goes.
    func userWantsToSeeAContact(_ vc: SomeSingleDiscussionViewController, contactIdentifier: ObvContactIdentifier)


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
    func userWantsToChangeTheMediaFormatOfTheDraft(_ singleDiscussionViewController: SomeSingleDiscussionViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, format: ObvMediaFormat) async throws
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

    /// The two above, said by a **discussion identifier** rather than by a controller — which is what the SwiftUI screen says them with.
    ///
    /// They exist because that screen has no controller to offer on the way out: it announces itself from its own `onDisappear`, and SwiftUI may run that *after* the
    /// hosting controller has been released, at which point a weak reference to it is nil and the discussion would never be given up — read-once messages left
    /// unwiped, the claim on being the current discussion never released.
    ///
    /// Nothing is lost by taking the identifier: the two above use their sender for exactly one thing, reading its `discussionId`.
    func discussionAppeared(discussionIdentifier: ObvDiscussionIdentifier)
    func discussionDisappeared(discussionIdentifier: ObvDiscussionIdentifier)
    
    func userWantsToDisplayContactIntroductionScreen(_ singleDiscussionViewController: SomeSingleDiscussionViewController, contactIdentifier: ObvTypes.ObvContactIdentifier)
    
    func userWantsToUpdateDiscussionLocalConfiguration(_ vc: SomeSingleDiscussionViewController, value: PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>) async throws

    func userWantsToForwardMessages(_ vc: SomeSingleDiscussionViewController, identifiersOfMessagesToForward: [ObvMessageAppIdentifier], identifiersOfDiscussionsWhereMessagesShouldBeForwarded: Set<ObvDiscussionIdentifier>) async throws

    /// Deletes several messages of one discussion at once.
    ///
    /// **Plural all the way down**, which is not a convenience: the operations behind it take a set, and `DeleteMessagesJSON` carries one reference per message,
    /// so a deletion for everyone is a single protocol message rather than one per message. Returns once the deletion has been carried out, and throws if it
    /// could not be — the screen shows a bar it must not dismiss until then.
    func userWantsToDeleteMessages(_ vc: SomeSingleDiscussionViewController, persistedMessageObjectIDs: Set<NSManagedObjectID>, deletionType: DeletionType) async throws

}
