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
import AVFAudio
import Combine
import CoreData
import QuickLook
import ObvAppCoreConstants
import ObvAppTypes
import ObvComposition
import ObvLocation
import ObvPollFeature
import ObvDesignSystem
import ObvSingleDiscussion
import ObvTypes
import ObvUI
import ObvUICoreData


/// The actions of the SwiftUI single discussion screen and of its cells, for the ones that need a view controller.
///
/// Everything asked of a message so far has ended at the engine, which the data source reaches on its own — so the data source has *been* the actions of this screen.
/// A place is the first thing a reader can ask for that has to be **presented**: a map inside the app, or a maps application, or the alert that chooses between
/// several of them. None of that belongs to a data source, and none of it can be done without a controller.
///
/// So this class stands between the two: what belongs to the data source is forwarded to it unchanged, and what needs the screen is done here. It is the shape
/// ``SwiftUISingleDiscussionComposeActions`` already has, and for the same reason — the SwiftUI view tree holds its actions **strongly**, so a controller
/// implementing them would be retained by the very hierarchy it owns. Hence the weak controller.
@MainActor
final class SwiftUISingleDiscussionActions {

    /// What the data source answers on its own: everything to do with an attachment or a recording.
    private let dataSourceActions: any SingleDiscussionAttachmentActions

    /// Weak, see the note on this class. Also the sender expected by ``SingleDiscussionViewControllerDelegate``.
    ///
    /// Handed on to the presenter, which needs something to present from and must not be told separately: two places to set one controller is one place to forget.
    weak var viewController: (any SomeSingleDiscussionViewController)? {
        didSet {
            attachmentPresenter.viewController = viewController
            messagePresenter.viewController = viewController
        }
    }

    /// Weak as well: this is the flow controller, which owns the navigation stack this screen sits in.
    ///
    /// Handed on to the message presenter for the same reason the controller is: most of what a context menu asks for ends at this delegate.
    weak var delegate: (any SingleDiscussionViewControllerDelegate)? {
        didSet { messagePresenter.delegate = delegate }
    }

    /// The composition bar's own state, set by the controller that owns both — the same one ``SwiftUISingleDiscussionComposeActions`` is given.
    ///
    /// Held here because a drop on the **messages** ends in the draft, which is the bar's business and not the transcript's: it goes to the very method the bar's own
    /// drop calls, so that where the reader let go changes nothing about what happens next.
    weak var composeViewSharedState: ComposeView.SharedState?

    /// The composition bar's own actions, set by the controller that owns both.
    ///
    /// Needed for one thing only: Esc, when the screen had nothing of its own to dismiss, drops the reply quote. Only this object holds the `draftObjectID` that
    /// takes, and the discussion screen sees the bar as an opaque view, so the two are joined here rather than there.
    weak var composeActions: SwiftUISingleDiscussionComposeActions?

    /// Opens attachments, and animates the opening out of the picture that was tapped. A type of its own because QuickLook's delegate wants an `NSObject`, and
    /// because presenting a viewer is not the same job as answering for a message — see ``SwiftUISingleDiscussionAttachmentPresenter``.
    private let attachmentPresenter = SwiftUISingleDiscussionAttachmentPresenter()

    /// Carries out what a message's context menu offers. A type of its own for the reason its own documentation gives: three of the twelve entries are conversations
    /// with a view controller, each with a delegate of its own to answer.
    private let messagePresenter: SwiftUISingleDiscussionMessagePresenter

    /// What the screen last said was on it, and which discussion it was.
    ///
    /// **Kept because a refusal must be retryable.** ``messagesAreOnScreen(discussionIdentifier:onScreenNow:seenSinceTheLastReport:)`` declines to mark anything
    /// read while the reader is not really in front of the window, and the screen *clears* what it has reported — so without this the refusal is final and a message
    /// that arrived while Olvid was in the background stays unread for as long as the discussion is left open. Recorded on **every** report, refused ones included,
    /// which is the whole point: the set that could not be acted on is exactly the one to come back to.
    private var whatTheScreenLastSaidWasOnIt: (discussionIdentifier: ObvDiscussionIdentifier, onScreen: Set<SingleDiscussionView.CellIdentifier>)?

    /// What is watching for the reader's attention coming back. Emptied with this object, which lives as long as the screen.
    private var observationTokens = [NSObjectProtocol]()
    private var cancellables = Set<AnyCancellable>()

    init(dataSourceActions: any SingleDiscussionAttachmentActions, messageReactionsViewDataSource: any ObvMessageReactionsViewDataSource, avatarViewDataSource: any ObvAvatarViewDataSource) {
        self.dataSourceActions = dataSourceActions
        // The two data sources the sheet of who reacted is built from. They belong to the presenter that shows that sheet and are only passed through here.
        self.messagePresenter = .init(messageReactionsViewDataSource: messageReactionsViewDataSource, avatarViewDataSource: avatarViewDataSource)
        watchesForTheReadersAttentionComingBack()
    }


    /// Retries the marking when the reader's attention comes back, and **two triggers, because a Mac has two ways of coming back.**
    ///
    /// Legacy has exactly these, and its own comment on the refusal says why they are what makes it safe: *"if the scene is not foreground active, we do not mark
    /// visible messages as not new. When going back to the `active` state, a call to `markNewVisibleReceivedAndRelevantSystemMessagesAsNotNew(..)` will be made."*
    ///
    /// - `UIScene.didActivateNotification` is the app coming back from the background, which is the case on every platform.
    /// - `traitCollectionActiveAppearance` becoming `.active` is a **Mac window coming forward**, and legacy observes it separately with the note *"this is
    ///   important under macOS only"*. It has to be separate: a window behind another is still `foregroundActive`, which is the 2024-11-18 lesson recorded in
    ///   ``theReaderIsReallyLooking()`` — so the appearance changes with no scene notification at all, and a screen watching only the scene would never retry.
    ///
    /// **Here and not on the screen**, though the screen is what knows about rows. Three reasons, and they point the same way: this object is the one that
    /// *refused*, so it is the one that owes a retry; `OlvidUserActivitySingleton` is the app's and no view module can see it; and the set to retry is the one that
    /// was reported and declined, which is here. What the screen still answers for is the other edge — see its `willDeactivate` — which covers the one thing this
    /// cannot know: rows that went by while the list was moving and are no longer on screen.
    private func watchesForTheReadersAttentionComingBack() {

        observationTokens.append(NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: nil) { [weak self] _ in
            Task { @MainActor [weak self] in self?.saysAgainWhatTheReaderIsLookingAt() }
        })

        OlvidUserActivitySingleton.shared.$traitCollectionActiveAppearance
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] traitCollectionActiveAppearance in
                guard traitCollectionActiveAppearance == .active else { return }
                self?.saysAgainWhatTheReaderIsLookingAt()
            }
            .store(in: &cancellables)

    }


    /// Acts on the last thing the screen said was on it, as though it had just said it again.
    ///
    /// Everything on screen is offered as *seen*, which is what legacy's repair claims too — `markNewVisibleReceivedAndRelevantSystemMessagesAsNotNew` marks the
    /// **visible** messages and nothing more. It costs nothing when there is nothing to do: `markAsReadTheMessagesThatAreStillUnread` filters to the messages whose
    /// status is still `new`, so a retry over messages long since read changes nothing.
    private func saysAgainWhatTheReaderIsLookingAt() {
        guard let (discussionIdentifier, onScreen) = whatTheScreenLastSaidWasOnIt, !onScreen.isEmpty else { return }
        Task {
            let objectIDs = objectIDsOfMessages(among: onScreen)
            guard !objectIDs.isEmpty, theReaderIsReallyLooking() else { return }
            await markAsReadTheMessagesThatAreStillUnread(objectIDs: objectIDs, discussionIdentifier: discussionIdentifier)
        }
    }

}


// MARK: - SingleDiscussionViewActions

extension SwiftUISingleDiscussionActions: SingleDiscussionViewActions {

    /// Claims the discussion the reader is looking at, and everything the app hangs off that: read-once messages wiped on leaving, notifications suppressed while
    /// here, the user activity for Handoff and Siri, and the discussions list's own idea of where the reader is.
    ///
    /// **Said by the screen**, and routed to the same delegate methods the legacy controller calls from its `viewWillAppear` — the chain being
    /// `ObvFlowController` → `OlvidUserActivitySingleton.switchCurrentDiscussion(to:)` → `currentDiscussionDidChange` →
    /// `PersistedDiscussionsUpdatesCoordinator.userEnteredDiscussion` / `userLeftDiscussion`.
    ///
    /// **The identifier is what reaches the chain, and no controller is involved.** It has to be that way: this is said from the screen's own `onDisappear`, and
    /// SwiftUI may run that *after* the hosting controller has been released — a weak reference to it is then nil, and a discussion announced through the controller
    /// would never be given up. Which is exactly what happened, and what the identifier-taking pair on `SingleDiscussionViewControllerDelegate` exists for.
    func discussionAppeared(discussionIdentifier: ObvDiscussionIdentifier) {
        guard let delegate else { assertionFailure(); return }
        delegate.discussionAppeared(discussionIdentifier: discussionIdentifier)
    }


    /// The reader has left. Silencing whatever was playing belongs here too: a recording goes on sounding while the message showing it is scrolled out of sight, and
    /// only leaving the discussion altogether stops it — which is what the hosting controller used to say from `viewWillDisappear`, the last thing in it.
    func discussionDisappeared(discussionIdentifier: ObvDiscussionIdentifier) {
        ObvAudioPlayer.shared.stop()
        guard let delegate else { assertionFailure(); return }
        delegate.discussionDisappeared(discussionIdentifier: discussionIdentifier)
    }


    /// **Esc, when the screen had nothing of its own to dismiss**.
    ///
    /// The screen answers Esc for the context menu, a search and select mode, in that order, and says this when none was up. What is left of legacy's own list
    /// is the **reply draft**, and it lands here because it is the app's: the quote is a value on the draft, taken off through the same delegate call the
    /// quote's own close button makes, and the discussion module sees the composition bar as an opaque view.
    ///
    /// **Legacy's third priority — dismiss the top presented controller — is deliberately not here.** Esc reaches this screen as a keyboard shortcut, so it
    /// never does while something is presented over it: a presented screen answers Esc for itself.
    ///
    /// **Then the bar's own things, innermost first.** The mention suggestions, if they are showing, go and the caret stays, exactly as closing a completion list
    /// leaves the word being typed. Then the reply quote. **And last of all, the caret leaves the editor**: with nothing left, Esc means *I have finished typing*,
    /// the bar resigns its text view, and a second Esc finds nothing focused and does nothing. Both facts are read off the bar's shared state, the quote's removal
    /// itself being unable to say whether it removed anything.
    func userPressedEscapeWithNothingOnThisScreenToDismiss(discussionIdentifier: ObvDiscussionIdentifier) {
        guard let composeViewSharedState else {
            Task { await composeActions?.theReplyDraftGoesAwayIfThereIsOne() }
            return
        }
        if composeViewSharedState.theMentionSuggestionsAreShowing {
            composeViewSharedState.dismissTheMentionSuggestions()
        } else if composeViewSharedState.theDraftQuotesAMessage {
            Task { await composeActions?.theReplyDraftGoesAwayIfThereIsOne() }
        } else {
            composeViewSharedState.stopEditing()
        }
    }


    /// A click on the messages, on a Mac: the reader has finished typing, and the caret leaves the composition bar.
    func userClickedOnTheMessages(discussionIdentifier: ObvDiscussionIdentifier) {
        composeViewSharedState?.stopEditing()
    }


    /// Step 60: the screen is holding a message beside the composition bar, so the bar folds its quote down to the name alone.
    ///
    /// **The same property legacy sets**, `hasReplyViewDisplayedAbove` — `NewSingleDiscussionViewController` sets it true before the reply reaches the draft and
    /// false in the completion that takes the lifted view away. What it does is hide the quote's body and its thumbnail, each on a quarter-second ease-in-out,
    /// while the message itself is on show above the bar. It lives in `ComposeView.SharedState` because the bar is shared with the legacy screen.
    func aMessageIsShownBesideTheCompositionBar(discussionIdentifier: ObvDiscussionIdentifier, isShown: Bool) {
        composeViewSharedState?.setHasReplyViewDisplayedAbove(to: isShown)
    }


    /// The messages on screen, which two different things follow from.
    ///
    /// The screen says *what is on it*; everything that decides what to do with that is here, because none of it is a question a view can answer: whether the reader
    /// is really in front of the window, whether a message is still unread, whether it is one whose visibility is running out.
    func messagesAreOnScreen(discussionIdentifier: ObvDiscussionIdentifier, onScreenNow: Set<SingleDiscussionView.CellIdentifier>, seenSinceTheLastReport: Set<SingleDiscussionView.CellIdentifier>) {

        // Remembered before anything is decided, and whatever is decided. This is what makes a refusal retryable when the reader's attention comes back;
        // see ``whatTheScreenLastSaidWasOnIt``. Recording it *after* the guard below would remember only the reports that needed no retry.
        whatTheScreenLastSaidWasOnIt = (discussionIdentifier, onScreenNow)

        Task {

            // What is on screen is what a screenshot would capture, so it is said whatever the set contains — its *emptiness* matters just as much, being what says a
            // screenshot taken now would catch nothing sensitive. Not gated on the window being frontmost, as legacy does not gate its own tracker either.
            await reportTheSensitiveMessagesOnScreen(objectIDs: objectIDsOfMessages(among: onScreenNow))

            // Being *read*, on the other hand, is a claim about the reader — so it is made only when they are really in front of the window.
            let objectIDsSeen = objectIDsOfMessages(among: seenSinceTheLastReport)
            guard !objectIDsSeen.isEmpty, theReaderIsReallyLooking() else { return }
            await markAsReadTheMessagesThatAreStillUnread(objectIDs: objectIDsSeen, discussionIdentifier: discussionIdentifier)

        }

    }


    /// Shows whoever this discussion is with, as tapping the legacy title view does — the same delegate call, `userTappedTitleOfDiscussion(_:discussionObjectID:)`,
    /// which is what decides between a contact's details and a group's.
    ///
    /// Here rather than on the data source because it *presents* something, and only a controller can present.
    func userTappedTheHeader(discussionIdentifier: ObvDiscussionIdentifier) {
        guard let viewController, let delegate else { assertionFailure(); return }
        guard let discussion = try? PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: discussionIdentifier, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            return
        }
        delegate.userTappedTitleOfDiscussion(viewController, discussionObjectID: discussion.typedObjectID)
    }


    /// Carries out what the reader asked of the navigation bar, as the legacy menu's four actions do.
    ///
    /// Three of these present a view controller, which is why they are here and not on the data source. The fourth writes to the database, and does it the way the
    /// rest of the app does: by posting the notification the legacy button posts.
    func userWantsToActOnTheDiscussion(discussionIdentifier: ObvDiscussionIdentifier, action: DiscussionBarAction) {

        guard let viewController else { assertionFailure(); return }
        guard let discussion = try? PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: discussionIdentifier, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            return
        }

        switch action {

        case .showTheDiscussionSettings:
            // The same sheet the legacy `settingsButtonTapped()` presents, built from the same two configurations.
            guard let vc = DiscussionSettingsHostingViewController(discussionSharedConfiguration: discussion.sharedConfiguration,
                                                                   discussionLocalConfiguration: discussion.localConfiguration) else {
                assertionFailure()
                return
            }
            viewController.present(vc, animated: true)

        case .showTheGallery:
            // Still the UIKit gallery, as `galleryButtonTapped()` presents it. A SwiftUI one is Step 25.
            let vc = DiscussionGalleryViewController(discussionObjectID: discussion.typedObjectID)
            viewController.present(ObvNavigationController(rootViewController: vc), animated: true)

        case .call:
            callTheDiscussion(discussion)

        case .unmute:
            ObvMessengerInternalNotification.userWantsToUpdateDiscussionLocalConfiguration(
                value: .muteNotificationsEndDate(nil),
                localConfigurationObjectID: discussion.localConfiguration.typedObjectID)
            .postOnDispatchQueue()

        }

    }


    /// Calls whoever a discussion is with — one contact directly, and a group through the chooser, exactly as the legacy `callButtonTapped()` does.
    ///
    /// It is transcribed rather than shared because the legacy version reads its discussion from an object ID this screen does not hold; everything below the
    /// first line is the same, notification for notification.
    private func callTheDiscussion(_ discussion: PersistedDiscussion) {
        switch try? discussion.kind {
        case .oneToOne(withContactIdentity: let contactIdentity):
            guard let contactCryptoId = try? contactIdentity?.cryptoId,
                  let ownedCryptoId = contactIdentity?.ownedIdentity?.cryptoId else { return }
            ObvMessengerInternalNotification.userWantsToCallOrUpdateCallCapabilityButWeShouldCheckSheIsAllowedTo(
                ownedCryptoId: ownedCryptoId,
                contactCryptoIds: Set([contactCryptoId]),
                groupId: nil,
                startCallIntent: nil)
            .postOnDispatchQueue()
        case .groupV1(withContactGroup: let contactGroup):
            guard let contactGroup, let groupV1Identifier = try? contactGroup.getGroupId() else { return }
            guard let ownedCryptoId = contactGroup.ownedIdentity?.cryptoId else { return }
            let contactCryptoIds = contactGroup.contactIdentities.compactMap { try? $0.cryptoId }
            ObvMessengerInternalNotification.userWantsToSelectAndCallContacts(
                ownedCryptoId: ownedCryptoId,
                contactCryptoIds: Set(contactCryptoIds),
                groupId: .groupV1(groupV1Identifier: groupV1Identifier))
            .postOnDispatchQueue()
        case .groupV2(withGroup: let group):
            guard let group, let ownedCryptoId = try? group.ownCryptoId else { return }
            let contactCryptoIds = group.contactsAmongNonPendingOtherMembers.compactMap { try? $0.cryptoId }
            ObvMessengerInternalNotification.userWantsToSelectAndCallContacts(
                ownedCryptoId: ownedCryptoId,
                contactCryptoIds: Set(contactCryptoIds),
                groupId: .groupV2(groupV2Identifier: group.groupIdentifier))
            .postOnDispatchQueue()
        case .none:
            assertionFailure()
        }
    }


    /// Whatever the reader dropped on the messages, put in the draft.
    ///
    /// **Straight to the composition bar's own state, which is the point.** The bar answers its own drops in `ObvComposition`; this one can only be answered on the
    /// `List`'s collection view, several modules away — but it means the same thing, so it ends in the same `itemsWereDropped(_:)`. That method is what decides what
    /// each item becomes, closes the bar to editing while a large file is copied out of another application, and puts back into the editor whatever turned out to be
    /// text. The legacy screen arranges all three by hand around its own drop, in `performDropWith`.
    ///
    /// Nothing is filtered here: `canHandle(session:)` accepts anything on both screens, and what cannot be made into an attachment is dropped by the operation that
    /// tries.
    func userDroppedItemsOnTheMessages(discussionIdentifier: ObvDiscussionIdentifier, itemProviders: [NSItemProvider]) {
        guard let composeViewSharedState else { assertionFailure(); return }
        composeViewSharedState.itemsWereDropped(itemProviders)
    }


    /// Deletes the messages the reader has chosen.
    ///
    /// **A delegate method and not a notification, which is the one decision worth defending here.** The single-message deletion posts
    /// `ObvMessengerInternalNotification.userRequestedDeletionOfPersistedMessage`, which is a line at each end and cannot be awaited, cannot throw, and does not
    /// appear in a stack trace. This screen needs all three: it has a bar to dismiss, a mode to leave and a failure to report, and it must do none of them until
    /// the messages are actually gone. The route is `userWantsToForwardMessage`'s, hop for hop.
    ///
    /// **The whole selection in one request.** Everything below is already plural, down to a `DeleteMessagesJSON` that carries a reference per message — so a
    /// deletion for everyone is one protocol message rather than one each. A loop here would send as many as there are messages.
    func userWantsToDeleteMessages(discussionIdentifier: ObvDiscussionIdentifier, cellIdentifiers: Set<SingleDiscussionView.CellIdentifier>, kind: WhatCanBeDeleted.Kind) async throws {
        guard let viewController, let delegate else { assertionFailure(); throw ObvError.theDelegateIsNotSet }
        let objectIDs = Set(objectIDsOfMessages(among: cellIdentifiers))
        guard !objectIDs.isEmpty else { return }
        try await delegate.userWantsToDeleteMessages(viewController,
                                                     persistedMessageObjectIDs: objectIDs,
                                                     deletionType: .init(kind))
    }


    /// Forwards the messages the reader has chosen, once they have said where to.
    ///
    /// **The asking and the sending are one call**, which is why this returns a `Bool` rather than handing a set of discussions back to the screen: where the
    /// messages go is answered by a `UIViewController` the screen has no way to present, and a module that knows nothing of Core Data has no vocabulary for
    /// discussions it would then have to carry. So the presenter puts the question, waits, and sends. See
    /// ``SwiftUISingleDiscussionMessagePresenter/forward(_:)``, which the single-message context menu reaches by the same route.
    ///
    /// **The order is decided here and nowhere else.** A selection is a set of ticks; a recipient must read the messages in the order the discussion holds them,
    /// which is `sortIndex` and which only this side can see. Sorting on the way in is what makes the coordinator's loop enough.
    /// **A failure throws and a cancellation returns `false`**, which must not be the same answer: backing out of the chooser leaves the reader exactly as they
    /// were, where a failure may have delivered some of the messages already. Any message having gone between the ticking and the sending is a failure of that
    /// kind rather than a change of mind, so it throws too — the reader is told, rather than left with a mode that appeared to do nothing.
    ///
    /// **As many messages as rows, or none.** All-or-none is what one Forward over a whole selection promises, and a shortfall here would break it as surely as
    /// forwarding the eligible part of an ineligible selection would: the reader would believe they had sent what they ticked. So each step is required to keep
    /// the count, and the two ways it can drop are told apart — a row that is not a message cannot be ticked on any platform and is a programming error, where a
    /// message that has gone is an ordinary race a deletion from another device can win.
    func userWantsToForwardMessages(discussionIdentifier: ObvDiscussionIdentifier, cellIdentifiers: Set<SingleDiscussionView.CellIdentifier>) async throws -> Bool {
        let objectIDs = objectIDsOfMessages(among: cellIdentifiers)
        guard !objectIDs.isEmpty else { throw ObvError.theMessagesAreNoLongerThere }
        guard objectIDs.count == cellIdentifiers.count else { assertionFailure(); throw ObvError.somethingChosenIsNotAMessage }
        let messages = messagesInTheOrderTheDiscussionHoldsThem(objectIDs)
        guard messages.count == objectIDs.count else { throw ObvError.theMessagesAreNoLongerThere }
        return try await messagePresenter.forward(messages)
    }


    enum ObvError: Error {
        /// Nothing to forward a request to. It cannot happen while the screen is on screen, this being set as the screen is built, and it is thrown rather than
        /// swallowed so that the reader is told the deletion did not happen — see Step 42c.
        case theDelegateIsNotSet
        /// A message the reader had ticked has gone — deleted from another device, or wiped as it expired — between the choosing and the sending. Thrown
        /// rather than answered as a cancellation, so that the reader is told the forward did not happen instead of watching it silently do nothing.
        case theMessagesAreNoLongerThere
        /// A ticked row that is not a message. No platform lets the unread marker be ticked, and it is the only such row there is, so this is a programming
        /// error rather than anything the reader can cause.
        case somethingChosenIsNotAMessage
    }


    /// These messages, oldest first.
    ///
    /// **Sorted on `sortIndex`, which is the discussion's own order** and the only one a recipient would recognise. Sorting on the way in is what makes the
    /// coordinator's loop enough.
    ///
    /// One that can no longer be read is left out rather than refused here — **whether a shortfall matters is the caller's** to decide, and
    /// ``userWantsToForwardMessages(discussionIdentifier:cellIdentifiers:)`` decides that it does.
    private func messagesInTheOrderTheDiscussionHoldsThem(_ objectIDs: [NSManagedObjectID]) -> [PersistedMessage] {
        objectIDs
            .compactMap { try? ObvStack.shared.viewContext.existingObject(with: $0) as? PersistedMessage }
            .sorted { $0.sortIndex < $1.sortIndex }
    }


    /// The messages among a set of rows — a row identifying anything else, the unread marker above all, is not one.
    private func objectIDsOfMessages(among cellIdentifiers: Set<SingleDiscussionView.CellIdentifier>) -> [NSManagedObjectID] {
        cellIdentifiers.compactMap { cellIdentifier in
            guard case .objectID(let objectID) = cellIdentifier else { return nil }
            return objectID
        }
    }


    /// Whether the reader is in front of this window, which is what makes "on screen" mean "seen".
    ///
    /// Two tests, and the second is the one that is easy to miss: a window **behind another** on a Mac passes `foregroundActive`, so the legacy screen also requires
    /// the appearance to be active there — a lesson it records under the date it was learnt, 2024-11-18. Messages must not be marked read because Olvid happens to be
    /// running behind whatever the reader is actually looking at.
    private func theReaderIsReallyLooking() -> Bool {
        guard let viewController else { return false }
        guard viewController.view.window?.windowScene?.activationState == .foregroundActive else { return false }
        if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
            guard OlvidUserActivitySingleton.shared.traitCollectionActiveAppearance == .active else { return false }
        }
        return true
    }


    /// Marks read whichever of the messages on screen are still unread, which clears the discussion's badge and sends their senders the receipt they are owed.
    ///
    /// The filtering is the legacy screen's, from `markAsNotNewTheMessageInCell(_:)`: a *received* message whose status is still `new`, and a *system* message that is
    /// `new` **and** counts towards the unread total — the others are counted nowhere, so marking them would mean nothing.
    ///
    /// Re-reporting a message already read is free, which is what lets the screen say the whole set every time: nothing here is left of it after this filter.
    @MainActor
    private func markAsReadTheMessagesThatAreStillUnread(objectIDs: [NSManagedObjectID], discussionIdentifier: ObvDiscussionIdentifier) async {

        guard let viewController, let delegate else { return }

        let messageIds: [MessageIdentifier] = objectIDs.compactMap { objectID in
            guard let message = try? ObvStack.shared.viewContext.existingObject(with: objectID) as? PersistedMessage else { return nil }
            if let received = message as? PersistedMessageReceived {
                guard received.status == .new else { return nil }
                return .received(id: .objectID(objectID: received.objectID))
            } else if let system = message as? PersistedMessageSystem {
                guard system.status == .new, system.isRelevantForCountingUnread else { return nil }
                return .system(id: .objectID(objectID: system.objectID))
            } else {
                return nil
            }
        }

        guard !messageIds.isEmpty else { return }

        do {
            try await delegate.messagesAreNotNewAnymore(viewController,
                                                        ownedCryptoId: discussionIdentifier.ownedCryptoId,
                                                        discussionId: discussionIdentifier.toDiscussionIdentifier(),
                                                        messageIds: messageIds)
        } catch {
            assertionFailure()
        }

    }


    /// Says which of the messages on screen are sensitive — the ones a screenshot would betray.
    ///
    /// **This is what tells a sender that their ephemeral message was captured.** The set reaches `ScreenCaptureDetector`, which combines it with the system's
    /// screenshot and screen-recording notifications; a capture while the set is non-empty is what produces the "sensitive messages were captured" system message and
    /// the warning sent to the other side. Without it a screenshot on this screen told nobody anything.
    ///
    /// The rule is `VisibilityTrackerForSensitiveMessages`': a message *sent* counts when its visibility is limited, and a message *received* counts only once it has
    /// been **read** — one still to be revealed shows nothing to capture, which is the guard Step 11a makes in the model.
    ///
    /// The set is sent whether or not it is empty: becoming empty is exactly what says a screenshot would now catch nothing.
    @MainActor
    private func reportTheSensitiveMessagesOnScreen(objectIDs: [NSManagedObjectID]) async {

        guard let viewController, let delegate else { return }

        guard let discussionPermanentIDOfThisScreen = Self.discussionPermanentID(ofMessagesWith: objectIDs) else { return }

        var messagePermanentIDs = Set<ObvManagedObjectPermanentID<PersistedMessage>>()

        for objectID in objectIDs {
            guard let message = try? ObvStack.shared.viewContext.existingObject(with: objectID) as? PersistedMessage else { continue }
            if let sent = message as? PersistedMessageSent {
                guard sent.isEphemeralMessageWithLimitedVisibility else { continue }
                messagePermanentIDs.insert(sent.messagePermanentID)
            } else if let received = message as? PersistedMessageReceived {
                guard received.isEphemeralMessageWithUserAction, received.status == .read else { continue }
                messagePermanentIDs.insert(received.messagePermanentID)
            }
        }

        do {
            try await delegate.updatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(viewController,
                                                                                          discussionPermanentID: discussionPermanentIDOfThisScreen,
                                                                                          messagePermanentIDs: messagePermanentIDs)
        } catch {
            assertionFailure()
        }

    }

}


// MARK: - SingleDiscussionCellViewActions

extension SwiftUISingleDiscussionActions: SingleDiscussionCellViewActions {

    func userWantsToActOnAttachment(_ attachment: MessageAttachment, action: AttachmentAction) async {
        await dataSourceActions.userWantsToActOnAttachment(attachment, action: action)
    }


    func userWantsToActOnAudioAttachment(_ attachment: MessageAttachment, action: AudioAction) async {
        await dataSourceActions.userWantsToActOnAudioAttachment(attachment, action: action)
    }


    /// Shows the reader whoever sent a message, they having tapped that sender's name or picture.
    ///
    /// Straight to the flow controller, which owns the navigation stack a contact's screen is presented on. Nothing is decided here: whether that screen offers
    /// *Invite*, or *Discuss* and *Call*, is the contact's own business, and so is where *Discuss* then takes the reader.
    func userWantsToSeeAContact(contactIdentifier: ObvContactIdentifier) async {
        guard let viewController, let delegate else { assertionFailure(); return }
        delegate.userWantsToSeeAContact(viewController, contactIdentifier: contactIdentifier)
    }

    /// The reader tapped a chip of reactions and wants to know who left them.
    ///
    /// **Not forwarded to the flow controller**, unlike a sender being tapped: what opens is a sheet over *this* screen and
    /// nothing about the navigation stack changes, so it is presented from this screen's own controller.
    func userWantsToSeeWhoReactedToAMessage(messageIdentifier: ObvMessageReactionsViewModel.MessageIdentifier) async {
        await messagePresenter.showWhoReacted(to: messageIdentifier)
    }



    /// Carries out what the reader chose from a message's context menu. See ``SwiftUISingleDiscussionMessagePresenter``, which does all of it.
    ///
    /// **A reply puts the caret in the composition bar**, at the end of whatever is there, once the quote is in the draft: the reader has said what they are
    /// about to do, and the bar is made ready for it rather than waiting for a tap. Unless the caret is there already, which the bar checks.
    func userWantsToActOnMessage(cellIdentifier: SingleDiscussionView.CellIdentifier, action: MessageAction) async {
        await messagePresenter.userWantsToActOnMessage(cellIdentifier: cellIdentifier, action: action)
        if action == .reply {
            composeViewSharedState?.startEditing()
        }
    }


    /// Answers a tap on something the discussion said about itself. Each of the four ends outside this screen, which is why a view can only ask.
    ///
    /// The routes are the legacy screen's own, from its `tappedStuff` switch: the settings sheet it opens from its ellipsis menu, the microphone permission, the deep
    /// link to the settings for calls, and the title tap — which for a change among the members of a group means "show me that group".
    func userWantsToActOnSystemMessage(_ systemMessage: TappableSystemMessage) async {

        guard case .objectID(let messageObjectID) = systemMessage.identifier else { assertionFailure(); return }

        switch systemMessage.request {

        case .showTheSharedSettings:
            showTheSharedSettings(ofDiscussionOfMessageWith: messageObjectID)

        case .askForPermissionToUseTheMicrophone:
            await askForPermissionToUseTheMicrophone()

        case .showTheSettingsForCalls:
            ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: ObvDeepLink.voipSettings)
                .postOnDispatchQueue()

        case .showWhoTheDiscussionIsWith:
            guard let viewController, let delegate else { assertionFailure(); return }
            guard let discussionObjectID = Self.discussionObjectID(ofMessageWith: messageObjectID) else { return }
            delegate.userTappedTitleOfDiscussion(viewController, discussionObjectID: discussionObjectID)

        }

    }


    /// Shows what the shared settings of the discussion now are, as `settingsButtonTapped()` does on the legacy screen — the same sheet, built from the same two
    /// configurations.
    private func showTheSharedSettings(ofDiscussionOfMessageWith messageObjectID: NSManagedObjectID) {
        guard let viewController else { assertionFailure(); return }
        guard let message = try? ObvStack.shared.viewContext.existingObject(with: messageObjectID) as? PersistedMessage else { return }
        guard let discussion = message.discussion else { return }
        guard let vc = DiscussionSettingsHostingViewController(discussionSharedConfiguration: discussion.sharedConfiguration,
                                                               discussionLocalConfiguration: discussion.localConfiguration) else {
            assertionFailure()
            return
        }
        viewController.present(vc, animated: true)
    }


    /// Asks for the microphone, which is what a reader wants when told a call was refused for want of it.
    ///
    /// Three states and three answers, as on the legacy screen: never asked, so ask; refused, so say where it can be changed — the notification leads to an alert
    /// offering the system settings; already granted, so there is nothing to do and the message is simply out of date.
    ///
    /// `AVAudioApplication` from iOS 17, `AVAudioSession` below it: the second is what legacy calls, and it is deprecated.
    private func askForPermissionToUseTheMicrophone() async {

        let permissionIsUndetermined: Bool
        let permissionWasDenied: Bool

        if #available(iOS 17.0, *) {
            permissionIsUndetermined = AVAudioApplication.shared.recordPermission == .undetermined
            permissionWasDenied = AVAudioApplication.shared.recordPermission == .denied
        } else {
            permissionIsUndetermined = AVAudioSession.sharedInstance().recordPermission == .undetermined
            permissionWasDenied = AVAudioSession.sharedInstance().recordPermission == .denied
        }

        if permissionIsUndetermined {
            if #available(iOS 17.0, *) {
                _ = await AVAudioApplication.requestRecordPermission()
            } else {
                _ = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                    AVAudioSession.sharedInstance().requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
            }
        } else if permissionWasDenied {
            ObvMessengerInternalNotification.rejectedIncomingCallBecauseUserDeniedRecordPermission
                .postOnDispatchQueue()
        }

    }


    /// The discussion these messages belong to, which the visibility tracker is keyed on.
    ///
    /// Taken from the first message that can still be found — they are all of one discussion, this being one screen — and nil when there is none, which is a set of
    /// rows whose messages have all just been deleted. Nothing is reported then rather than reporting an empty set for a discussion nobody can name.
    @MainActor
    private static func discussionPermanentID(ofMessagesWith objectIDs: [NSManagedObjectID]) -> ObvManagedObjectPermanentID<PersistedDiscussion>? {
        for objectID in objectIDs {
            guard let message = try? ObvStack.shared.viewContext.existingObject(with: objectID) as? PersistedMessage else { continue }
            if let discussionPermanentID = message.discussion?.discussionPermanentID { return discussionPermanentID }
        }
        return nil
    }


    /// The discussion a message belongs to, as the object ID the title tap expects. Read from the view context, as the two lookups beside it are.
    @MainActor
    private static func discussionObjectID(ofMessageWith messageObjectID: NSManagedObjectID) -> TypeSafeManagedObjectID<PersistedDiscussion>? {
        guard let message = try? ObvStack.shared.viewContext.existingObject(with: messageObjectID) as? PersistedMessage else { return nil }
        return message.discussion?.typedObjectID
    }


    /// Explains a gap in a discussion, which is what the reader asked for by tapping the bubble that says there is one.
    ///
    /// Through the internal notification the legacy screen posts, `MetaFlowController` answering it with the alert: the wording of the explanation has one writer, and
    /// the two screens should not drift apart on what a missing message means.
    func userWantsToKnowWhyMessagesAreMissing() async {
        ObvMessengerInternalNotification.userDidTapOnMissedMessageBubble
            .postOnDispatchQueue()
    }


    /// Opens a link the reader tapped in the body of a message.
    ///
    /// Through `userSelectedURL(_:within:)`, exactly as the legacy screen does, because the app knows things about a URL that a browser does not: an Olvid link is
    /// an invitation or a configuration and is handled here, and only what is left leaves the app.
    func userWantsToOpenURLFromAMessage(_ url: URL) async {

        guard let viewController else { assertionFailure(); return }

        // **A mention is a link too**, and the one the app has to catch rather than open: it stands for a person, not for a page. The legacy screen tells the two
        // apart in the same place, its text view handing every tapped link to one method. See `MentionInAMessage`.
        if let mentionedCryptoId = SingleDiscussionViewAppDataSource.whoeverIsMentioned(in: url) {
            guard let delegate else { assertionFailure(); return }
            await delegate.singleDiscussionViewController(viewController, userDidTapOn: mentionedCryptoId)
            return
        }

        await UIApplication.shared.userSelectedURL(url, within: viewController)

    }


    /// Opens an attachment, and every other attachment of its message beside it. See ``SwiftUISingleDiscussionAttachmentPresenter``, which does all of it.
    func userWantsToOpenAttachment(_ attachment: MessageAttachment) async {
        attachmentPresenter.userWantsToOpenAttachment(attachment)
    }


    /// Where the attachments of this screen are drawn, which the presenter reads to know what the viewer should fly out of.
    var attachmentFrames: AttachmentFrames {
        attachmentPresenter.attachmentFrames
    }


    /// Shows the reader a place, by whichever map can show it.
    ///
    /// **The choice is made here, and this is the reason the module does not make it.** A location being shared is best followed on the map inside the app, which
    /// exists only from iOS 17 — `ObvMapView` and everything around it is `@available(iOS 17.0, *)`. A place sent once has nothing to follow, so it goes to a maps
    /// application, as it does on every version of the legacy screen. Neither the version of iOS nor the maps applications installed is something a view can see.
    ///
    /// An itinerary always leaves the app, even where the map above would have stayed in it.
    func userWantsToActOnLocation(_ location: LocationInMessage, at coordinate: LocationCoordinate, address: String?, action: LocationAction) async {

        switch action {

        case .showOnAMap:
            if location.kind == .continuous, #available(iOS 17.0, *) {
                guard let viewController, let delegate else { assertionFailure(); return }
                guard case .objectID(let messageObjectID) = location.identifier else { assertionFailure(); return }
                do {
                    try await delegate.userWantsToShowMapToConsultLocationSharedContinously(viewController, messageObjectID: .init(objectID: messageObjectID))
                } catch {
                    assertionFailure()
                }
            } else {
                await openTheMapsApplication(at: coordinate, address: address)
            }

        case .itinerary:
            await openTheMapsApplication(at: coordinate, address: address)

        case .stopSharing:
            await stopSharingLocation()

        }

    }


    /// Stops the sharing this device is doing, for the whole discussion — which is the only granularity there is: one device shares one location, and the messages
    /// showing it are one per discussion.
    ///
    /// `@available(iOS 17.0, *)` all the way down, as it is on the legacy screen. Unreachable below that in practice: sharing cannot be *started* on iOS 16, so no
    /// bubble there ever offers the button that leads here.
    private func stopSharingLocation() async {
        guard #available(iOS 17.0, *) else { assertionFailure(); return }
        guard let viewController, let delegate else { assertionFailure(); return }
        guard let discussionIdentifier = viewController.discussionId else { assertionFailure(); return }
        do {
            try await delegate.userWantsToStopSharingLocationInDiscussion(viewController, discussionIdentifier: discussionIdentifier)
        } catch {
            assertionFailure()
        }
    }


    /// Reveals a message the reader had to ask to see.
    ///
    /// Everything that follows belongs to the app: the message is marked read, which sends the read receipt if the reader allows them and creates the expiration its
    /// sender asked for — a read-once message then leaves, and a message with a visibility begins its countdown. The route is the legacy screen's own, and it wants two
    /// identifiers the *message* can give: the discussion's, and its own.
    func userWantsToRevealMessage(_ message: TapToRead) async {

        guard let viewController, let delegate else { assertionFailure(); return }
        guard case .objectID(let messageObjectID) = message.identifier else { assertionFailure(); return }

        do {
            guard let discussionId = try Self.discussionIdentifier(ofMessageWith: messageObjectID) else { return }
            try await delegate.userWantsToReadReceivedMessageThatRequiresUserAction(viewController,
                                                                                   ownedCryptoId: viewController.currentOwnedCryptoId,
                                                                                   discussionId: discussionId,
                                                                                   messageId: .objectID(objectID: messageObjectID))
        } catch {
            assertionFailure()
        }

    }


    /// Which discussion a message belongs to, in the form the reveal expects — a `DiscussionIdentifier`, and not the `ObvDiscussionIdentifier` this screen is built
    /// around. Read from the view context, as the poll lookup beside it is.
    @MainActor
    private static func discussionIdentifier(ofMessageWith messageObjectID: NSManagedObjectID) throws -> DiscussionIdentifier? {
        guard let message = try ObvStack.shared.viewContext.existingObject(with: messageObjectID) as? PersistedMessage else { return nil }
        return try message.discussion?.identifier
    }


    /// Carries out what the reader asked of a poll: casting or withdrawing a vote, or asking to see the whole poll.
    func userWantsToActOnPoll(_ poll: PollInMessage, action: PollAction) async {

        guard let viewController, let delegate else { assertionFailure(); return }
        guard case .objectID(let messageObjectID) = poll.identifier else { assertionFailure(); return }

        do {
            switch action {

            case .showThePoll:
                guard let pollObjectID = try Self.pollObjectID(ofMessageWith: messageObjectID) else { return }
                try await delegate.userWantsToDisplayPollView(viewController, pollObjectID: pollObjectID)

            case .vote(candidate: let candidateUUID, chosen: let chosen, refusal: let refusal):

                // The view refused it, knowing the poll had finished or that "None" was chosen. All that is left is to say so, which needs a toast.
                if let refusal {
                    Toaster.showToast(toast: .init(style: .warning, message: refusal.toastMessage))
                    return
                }

                guard let version = try Self.versionOfTheNextVote(onCandidateWith: candidateUUID, ofMessageWith: messageObjectID) else { return }

                try await delegate.userWantsToUpdatePollVote(viewController,
                                                             ownedCryptoId: viewController.currentOwnedCryptoId,
                                                             messageObjectID: .init(objectID: messageObjectID),
                                                             pollVoteCandidateUuid: candidateUUID,
                                                             voted: chosen,
                                                             version: version)

            }
        } catch {
            assertionFailure()
        }

    }


    /// The poll of a message, read from the view context — which is where a screen may read, and where the poll screen expects to be given an identifier from.
    @MainActor
    private static func pollObjectID(ofMessageWith messageObjectID: NSManagedObjectID) throws -> TypeSafeManagedObjectID<PersistedPoll>? {
        guard let message = try ObvStack.shared.viewContext.existingObject(with: messageObjectID) as? PersistedMessage else { return nil }
        return message.poll?.typedObjectID
    }


    /// The version to send a vote with, asked of the poll itself: `PersistedPoll.versionForTheNextVoteFromOwnedIdentity`, which is where the arithmetic belongs and
    /// where the reason it is delicate is written down. A version that fails to grow is a vote silently thrown away.
    @MainActor
    private static func versionOfTheNextVote(onCandidateWith candidateUUID: UUID, ofMessageWith messageObjectID: NSManagedObjectID) throws -> Int? {
        guard let message = try ObvStack.shared.viewContext.existingObject(with: messageObjectID) as? PersistedMessage else { return nil }
        guard let poll = message.poll else { return nil }
        guard poll.candidates.contains(where: { $0.uuid == candidateUUID }) else { return nil }
        return poll.versionForTheNextVoteFromOwnedIdentity
    }


    /// Opens the one maps application installed, or asks the reader which of several to use — `MapOptions`' own alert, which is a `UIAlertController` and therefore
    /// belongs on this side of the module boundary.
    private func openTheMapsApplication(at coordinate: LocationCoordinate, address: String?) async {
        guard let viewController else { assertionFailure(); return }
        await UIApplication.shared.userWantsToOpenMapAt(latitude: coordinate.latitude,
                                                       longitude: coordinate.longitude,
                                                       address: address,
                                                       within: viewController)
    }

}

