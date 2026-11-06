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
import OSLog
import ObvAppCoreConstants
import ObvAppTypes
import ObvDesignSystem
import ObvSettings
import ObvSingleDiscussion
import ObvTypes
import ObvUI
import ObvUICoreData


/// Carries out what the reader chose from a message's context menu, for the SwiftUI discussion screen — the twelve entries of ``WhatAMessageOffers``.
///
/// **A type of its own, and for the same reason ``SwiftUISingleDiscussionAttachmentPresenter`` is one.** Three of these actions are not a single call but a
/// *conversation*: the forward chooser asks which discussions, the editor asks for a new body, the deletion asks which kind of deletion. Each answers through a
/// delegate of its own, so something has to conform to three more protocols and — for the forward — remember which message was being forwarded while the chooser
/// is up. None of that belongs on the screen's actions, which would otherwise grow three conformances and a piece of state to satisfy view controllers it merely
/// presents.
///
/// Everything here is transcribed from `NewSingleDiscussionViewController.createMenu(for:)` and the methods its actions call. Where it departs, the departure is
/// written at the point it happens.
@MainActor
final class SwiftUISingleDiscussionMessagePresenter {

    /// Weak, as everywhere on this screen: the SwiftUI view tree holds the actions strongly, and the actions hold this.
    weak var viewController: (any SomeSingleDiscussionViewController)?

    /// The flow controller, which is what most of these actions ultimately reach.
    weak var delegate: (any SingleDiscussionViewControllerDelegate)?

    /// Who reacted to a message and with what, read by the sheet a reactions chip opens. Handed in, as this presents that sheet and does not answer it.
    private let messageReactionsViewDataSource: any ObvMessageReactionsViewDataSource

    /// The photos of the people in that sheet. It is the screen's own cell data source, which is an `ObvAvatarViewDataSource` too — so the sheet asks the same photo
    /// cache the cells above it have already filled.
    private let avatarViewDataSource: any ObvAvatarViewDataSource

    /// For the small success or failure the reader feels when a reaction of theirs is removed, or an emoji added to their favourites — as on the legacy screen.
    private let notificationGenerator = UINotificationFeedbackGenerator()

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: SwiftUISingleDiscussionMessagePresenter.self))

    init(messageReactionsViewDataSource: any ObvMessageReactionsViewDataSource, avatarViewDataSource: any ObvAvatarViewDataSource) {
        self.messageReactionsViewDataSource = messageReactionsViewDataSource
        self.avatarViewDataSource = avatarViewDataSource
    }

    /// Whoever is waiting to be told which discussions the reader picked.
    ///
    /// **A continuation, where this used to be the message itself.** `NewDiscussionsSelectionViewControllerDelegate` says only *which discussions were picked*, so
    /// something had to survive from the entry being chosen to the reader accepting; holding the message here worked while a forward was one message begun in one
    /// place. It is now begun in two — a message's own menu, and a whole selection — and what the two share is not the payload but the *question*. So the chooser
    /// is asked as a function that returns an answer, the caller keeps its own messages, and this holds nothing about them.
    ///
    /// **It must be resumed exactly once, and there are three ways out of that chooser**: accepting, the Cancel item, and the reader pulling the sheet down, which
    /// fires neither of the first two. All three go through ``theReaderHasChosen(_:)``, which nils this as it resumes — so a second way out arriving after the
    /// first finds nothing and does nothing. A continuation resumed twice is a crash, and one never resumed is a task that waits for ever and a mode the reader
    /// cannot leave.
    private var whereTheMessagesShouldGo: CheckedContinuation<[TypeSafeManagedObjectID<PersistedDiscussion>], Never>?

    /// Watches for the chooser being pulled down rather than answered. Held for exactly as long as it is up — see ``ADismissalByHand``, which says why it exists
    /// at all and why it cannot simply be this object.
    private var noticesADismissalByHand: ADismissalByHand?


    /// Carries out one entry of a message's context menu.
    ///
    /// The message is read from the **view context** here, and every action below takes it already materialised: the answer that offered these entries was computed
    /// on the view context too, in the same gesture, so re-reading it anywhere else would be asking a second database a question the first one has answered.
    func userWantsToActOnMessage(cellIdentifier: SingleDiscussionView.CellIdentifier, action: MessageAction) async {

        guard case .objectID(let messageObjectID) = cellIdentifier else { assertionFailure(); return }

        // A message deleted between the menu being drawn and an entry being chosen. Nothing to do, and nothing to assert: it is a race the reader can win.
        guard let message = try? ObvStack.shared.viewContext.existingObject(with: messageObjectID) as? PersistedMessage else { return }

        switch action {
        case .showInfo: showWhatIsKnownAbout(message)
        case .react: offerTheEmojiPicker(for: message)
        case .reactWith(emoji: let emoji): await updateTheReaction(of: message, to: emoji)
        case .deleteOwnReaction: await updateTheReaction(of: message, to: nil)
        case .copyText: copyTheText(of: message)
        case .sharePhotos: await shareTheAttachments(of: message, imagesOnly: true)
        case .shareAttachments: await shareTheAttachments(of: message, imagesOnly: false)
        case .saveAttachments: await saveTheAttachments(of: message)
        case .reply: await replyTo(message)
        case .edit: offerToEditTheBodyOf(message)
        case .forward: await forwardFromTheMenu(message)
        case .call: callBackFrom(message)
        case .delete: offerToDelete(message)
        case .select:
            // **Never reaches here, and the assertion is the point.** Choosing several messages presents nothing: the screen answers it itself, in
            // `SingleDiscussionView.choose(_:on:)`, exactly as it answers the ellipsis's own Search entry. The case exists because `MessageAction` is one enum
            // for every entry of the menu and the compiler insists — and it asserts rather than shrugging, so that the day the interception is moved or dropped
            // says so in a debug build instead of silently doing nothing.
            assertionFailure("Choosing several messages is answered by the screen, not by the app")
        }

    }

}


// MARK: - Info

extension SwiftUISingleDiscussionMessagePresenter {

    /// Shows what is known about a message and its delivery, as the legacy Info entry does — the same two hosting controllers, in a navigation controller styled the
    /// same way.
    ///
    /// **A system message reaches this and shows nothing**, which is why the entry is never offered for one; the reason is written where that decision is taken, in
    /// `SingleDiscussionViewAppDataSource.whatTheMessageOffers(cellIdentifier:)`. The branch stays, so that a system message arriving here through some later route
    /// does nothing rather than something wrong.
    private func showWhatIsKnownAbout(_ message: PersistedMessage) {

        guard let viewController else { assertionFailure(); return }

        let infoViewController: UIViewController?
        if let sentMessage = message as? PersistedMessageSent {
            infoViewController = SentMessageInfosHostingViewController(messageSent: sentMessage, delegate: self)
        } else if let receivedMessage = message as? PersistedMessageReceived {
            infoViewController = ReceivedMessageInfosHostingViewController(messageReceived: receivedMessage)
        } else {
            infoViewController = nil
        }

        guard let infoViewController else { return }

        let nav = UINavigationController(rootViewController: infoViewController)
        if #unavailable(iOS 26) {
            // The appearance is left alone from iOS 26, exactly as the legacy screen leaves it.
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            nav.navigationBar.standardAppearance = appearance
            nav.navigationBar.scrollEdgeAppearance = appearance
        }
        viewController.present(nav, animated: true)

    }

}


// MARK: - SentMessageInfosHostingViewControllerDelegate

extension SwiftUISingleDiscussionMessagePresenter: SentMessageInfosHostingViewControllerDelegate {

    /// The info screen of a sent message asks for this as it appears: return receipts that arrived while the message was not on screen are stored, and opening its
    /// details is the moment to make sense of them. Forwarded unchanged, as the legacy controller forwards it.
    func userWantsToProcessReceiptsStoredForLater(_ vc: SentMessageInfosHostingViewController, ownedCryptoId: ObvCryptoId, returnReceiptElements: Set<ObvReturnReceiptElements>) async {
        guard let viewController, let delegate else { assertionFailure(); return }
        await delegate.userWantsToProcessReceiptsStoredForLater(viewController, ownedCryptoId: ownedCryptoId, returnReceiptElements: returnReceiptElements)
    }

}


// MARK: - Reactions

extension SwiftUISingleDiscussionMessagePresenter {

    /// Opens the full emoji picker, as the legacy `userWantsToReactToMessage(messageID:)` does — a medium sheet on iOS, a navigation controller under Catalyst.
    ///
    /// The three guards are legacy's own and are kept even though the entry is only offered when they hold: the menu was drawn from a state that may have changed
    /// while it was up, and *may I react to this* is the one question here whose answer moving means writing a reaction the sender forbade.
    ///
    /// **This is one half of Step 20b.** The other is the quick bar of favourite emojis, which is 22a and is drawn in 21b's overlay.
    private func offerTheEmojiPicker(for message: PersistedMessage) {

        guard let viewController else { assertionFailure(); return }
        guard let ownedCryptoId = message.discussion?.ownedIdentity?.cryptoId else { return }
        guard !message.isWiped else { return }
        guard (try? message.ownedIdentityIsAllowedToSetReaction) == true else { return }

        let messageObjectID = message.typedObjectID
        let selectedEmoji = message.reactionFromOwnedIdentity()?.emoji

        let model = EmojiPickerViewModel(selectedEmoji: selectedEmoji) { [weak self] emoji in
            guard let self else { return }
            Task { [weak self] in
                guard let self, let delegate = self.delegate, let viewController = self.viewController else { return }
                try? await delegate.userWantsToUpdateReaction(viewController, ownedCryptoId: ownedCryptoId, messageObjectID: messageObjectID, newEmoji: emoji)
            }
        }

        let vc = EmojiPickerHostingViewController(model: model)

        if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
            viewController.present(UINavigationController(rootViewController: vc), animated: true)
        } else {
            if let sheet = vc.sheetPresentationController {
                sheet.detents = [.medium()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 30.0
            }
            viewController.present(vc, animated: true)
        }

    }


    /// Sets or clears the reader's own reaction. Called with `nil` by the "Delete my reaction" entry, which is the only caller today — the picker above sets its own.
    private func updateTheReaction(of message: PersistedMessage, to newEmoji: String?) async {
        guard let viewController, let delegate else { assertionFailure(); return }
        guard let ownedCryptoId = message.discussion?.ownedIdentity?.cryptoId else { assertionFailure(); return }
        try? await delegate.userWantsToUpdateReaction(viewController, ownedCryptoId: ownedCryptoId, messageObjectID: message.typedObjectID, newEmoji: newEmoji)
    }

}


// MARK: - Copying, sharing and saving

extension SwiftUISingleDiscussionMessagePresenter {

    /// Puts the body of a message on the pasteboard.
    ///
    /// The *body*, and not what the bubble drew: legacy reads `cell.textToCopy`, which is the message's `textBody` when the text bubble is showing and the emoji-only
    /// view's text when that is what was drawn instead — both of them the body, arrived at through the view. There is no cell to ask here, and no need for one.
    private func copyTheText(of message: PersistedMessage) {
        guard let textBody = message.textBody, !textBody.isEmpty else { return }
        UIPasteboard.general.string = textBody
    }


    /// Shares a message's attachments through the system's activity sheet: the photographs alone, or everything attached.
    ///
    /// **The hardlinks are made here, and this is the split the whole screen is built on.** The menu was drawn from *counts*; the item providers — one hardlink per
    /// file, asked of `HardLinksToFylesManager` — are work, and are done only once an entry has been chosen. Legacy can read them straight off the cell because its
    /// cell has been caching hardlinks for everything on screen all along.
    private func shareTheAttachments(of message: PersistedMessage, imagesOnly: Bool) async {

        guard let viewController else { assertionFailure(); return }

        let joins = Self.attachmentsThatCanBeSharedOrSaved(of: message, imagesOnly: imagesOnly)
        guard !joins.isEmpty else { return }

        let itemProviders = await Self.hardlinks(for: joins).compactMap { $0?.activityItemProvider }
        guard !itemProviders.isEmpty else { return }

        // Taken before presenting, while the message is certainly still there. Sendable, so the completion handler may carry them off the main actor.
        let joinsToReportAsOpened = Self.receivedJoinsToReportAsOpened(of: message)

        let activityViewController = UIActivityViewController(activityItems: itemProviders, applicationActivities: nil)
        // The whole screen rather than the cell: legacy anchors the popover to the cell it was pressed on, and there is no such view here. On the iPhone it changes
        // nothing at all, the sheet coming up from the bottom either way.
        activityViewController.popoverPresentationController?.sourceView = viewController.view
        activityViewController.completionWithItemsHandler = { _, completed, _, activityError in
            guard completed, activityError == nil else { return }
            // Sharing a received attachment is opening it, which is what sends its sender the receipt they are owed. The same notification the legacy screen posts.
            for joinID in joinsToReportAsOpened {
                ObvMessengerInternalNotification.userHasOpenedAReceivedAttachment(receivedFyleJoinID: joinID).postOnDispatchQueue()
            }
        }

        viewController.present(activityViewController, animated: true)

    }


    /// Writes a message's attachments wherever the reader chooses, through the document picker — "Save to Files" on iOS, a save panel under Catalyst.
    ///
    /// Everything attached, never the photographs alone: legacy offers one Save entry and hands it `hardlinkURLsForAllAttachments`.
    private func saveTheAttachments(of message: PersistedMessage) async {

        guard let viewController else { assertionFailure(); return }

        let joins = Self.attachmentsThatCanBeSharedOrSaved(of: message, imagesOnly: false)
        guard !joins.isEmpty else { return }

        let hardlinkURLs = await Self.hardlinks(for: joins).compactMap { $0?.hardlinkURL }
        guard !hardlinkURLs.isEmpty else { return }

        let picker = UIDocumentPickerViewController(forExporting: hardlinkURLs, asCopy: true)
        picker.shouldShowFileExtensions = true
        viewController.present(picker, animated: true)

    }


    /// The attachments of a message that can be shared or saved: everything but a link preview, and only what is on the device.
    ///
    /// **The same rule as the one that counted them** for the menu — `SingleDiscussionViewAppDataSource.numberOfSharableAttachments(of:imagesOnly:)`, which is where
    /// the departure from legacy's "has a cached hardlink" is written down. It matters that the two agree: an entry saying "Share 3 photos" that then shares two is
    /// worse than an entry that was never offered.
    private static func attachmentsThatCanBeSharedOrSaved(of message: PersistedMessage, imagesOnly: Bool) -> [FyleMessageJoinWithStatus] {
        guard let joins = message.fyleMessageJoinWithStatus else { return [] }
        return joins.filter { join in
            guard !join.isPreviewType else { return false }
            guard join.fyle?.fileExistsOnDisk == true else { return false }
            return imagesOnly ? join.isImageType : true
        }
    }


    /// A hardlink per attachment, all of them asked for at once.
    ///
    /// `requestAllHardLinksToFyles` rather than a request per file, because that is the shape `HardLinksToFylesManager` offers for exactly this and it answers once
    /// rather than *n* times. The result is positional and may hold nils — a file that has gone since it was counted — which is why every caller compacts it.
    private static func hardlinks(for joins: [FyleMessageJoinWithStatus]) async -> [HardLinkToFyle?] {
        let fyleElements = joins.compactMap { $0.fyleElement }
        guard !fyleElements.isEmpty else { return [] }
        return await withCheckedContinuation { (continuation: CheckedContinuation<[HardLinkToFyle?], Never>) in
            HardLinksToFylesNotifications.requestAllHardLinksToFyles(fyleElements: fyleElements) { hardlinks in
                continuation.resume(returning: hardlinks)
            }.postOnDispatchQueue()
        }
    }


    /// Which of a message's attachments count as *opened* once it has been shared — all of them, when the message was received, and none when it was sent.
    ///
    /// Every join of the received message and not only the ones shared, as legacy's `postUserHasOpenedAReceivedAttachmentNotification(for:)` does.
    private static func receivedJoinsToReportAsOpened(of message: PersistedMessage) -> [TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>] {
        guard let receivedMessage = message as? PersistedMessageReceived else { return [] }
        return receivedMessage.fyleMessageJoinWithStatuses.map { $0.typedObjectID }
    }

}


// MARK: - Replying

extension SwiftUISingleDiscussionMessagePresenter {

    /// Makes the composition bar reply to this message.
    ///
    /// **The quote is read from the draft.** `ComposeViewAppDataSource` streams the draft's `replyTo`, so the bar follows rather than being told.
    ///
    /// **`hasReplyViewDisplayedAbove` is a display mode of the quote panel**, not bookkeeping for asking a cell for a view. While it is true,
    /// `ComposeReplyToView` hides the quote's body *and* its thumbnail, each on a quarter-second ease-in-out — so the panel reads "Replying to Alice Office"
    /// while the message itself is on screen beside the bar, and unfolds to show the quoted text once it has gone.
    ///
    /// What the bar *does* have to be told is Step 60's fact — that a copy of the message is being held above it — and that goes through
    /// `SingleDiscussionViewActions.aMessageIsShownBesideTheCompositionBar(discussionIdentifier:isShown:)`, not through here.
    private func replyTo(_ message: PersistedMessage) async {
        guard let viewController, let delegate else { assertionFailure(); return }
        // Legacy takes the draft from the cell; the message's own discussion is the same draft, and is the one this screen composes into.
        guard let draftObjectID = message.discussion?.draft.typedObjectID else { assertionFailure(); return }
        try? await delegate.userWantsToReplyToMessage(viewController, messageObjectID: message.typedObjectID, draftObjectID: draftObjectID)
    }

}


// MARK: - Editing

extension SwiftUISingleDiscussionMessagePresenter {

    /// Offers to change the body of a message the reader sent, in whichever editor the version of iOS has.
    ///
    /// Two editors, as on the legacy screen: `BodyEditView` from iOS 26, which edits an `AttributedString` and reports through a delegate, and
    /// `BodyEditViewControllerLegacy` below it, which edits plain text and reports through two closures. Only the second sends the edit itself — the first sends it
    /// from ``userWantsToSendEditedMessage(_:newBody:messageIdentifier:)`` below.
    private func offerToEditTheBodyOf(_ message: PersistedMessage) {

        guard let viewController else { assertionFailure(); return }
        guard let sentMessage = message as? PersistedMessageSent else { assertionFailure(); return }

        if #available(iOS 26, *) {

            guard let messageIdentifier: ObvMessageAppIdentifier = try? sentMessage.messageAppIdentifier else { assertionFailure(); return }
            let vc = BodyEditViewController(currentBody: sentMessage.attributedBodyForMessageEdition, messageIdentifier: messageIdentifier, delegate: self)
            viewController.present(vc, animated: true)

        } else {

            let ownedCryptoId = viewController.currentOwnedCryptoId
            let currentTextBody = sentMessage.textBody
            let sentMessageObjectID = sentMessage.typedObjectID
            let vc = BodyEditViewControllerLegacy(currentBody: currentTextBody) { [weak self] in
                self?.viewController?.presentedViewController?.dismiss(animated: true)
            } send: { [weak self] newTextBody in
                self?.viewController?.presentedViewController?.dismiss(animated: true) {
                    // An edit that changes nothing is not an edit, and sending it would mark the message edited for everyone.
                    guard newTextBody != currentTextBody else { return }
                    ObvMessengerInternalNotification.userWantsToSendEditedVersionOfSentMessage(
                        ownedCryptoId: ownedCryptoId,
                        sentMessageObjectID: sentMessageObjectID,
                        newTextBody: AttributedString(newTextBody ?? ""))
                    .postOnDispatchQueue()
                }
            }
            viewController.present(vc, animated: true)

        }

    }

}


// MARK: - BodyEditViewDelegate

@available(iOS 26.0, *)
extension SwiftUISingleDiscussionMessagePresenter: BodyEditViewDelegate {

    /// The iOS 26 editor reporting a new body. Transcribed from the legacy conformance, notification for notification.
    func userWantsToSendEditedMessage(_ view: BodyEditView, newBody: AttributedString?, messageIdentifier: ObvAppTypes.ObvMessageAppIdentifier) async {
        guard let viewController else { assertionFailure(); return }
        viewController.presentedViewController?.dismiss(animated: true)
        guard let message = try? PersistedMessage.getMessage(messageAppIdentifier: messageIdentifier, within: ObvStack.shared.viewContext) as? PersistedMessageSent else { assertionFailure(); return }
        ObvMessengerInternalNotification.userWantsToSendEditedVersionOfSentMessage(
            ownedCryptoId: viewController.currentOwnedCryptoId,
            sentMessageObjectID: message.typedObjectID,
            newTextBody: newBody ?? AttributedString())
        .postOnDispatchQueue()
    }


    func userWantsToCancelMessageEdition(_ view: BodyEditView) async {
        viewController?.presentedViewController?.dismiss(animated: true)
    }

}


// MARK: - Forwarding

extension SwiftUISingleDiscussionMessagePresenter {

    /// Forwards these messages, once the reader has said where to.
    ///
    /// **One route for one message and for a whole selection**, which is what made this worth restructuring rather than adding to. A message's own context menu
    /// hands in one; ``SwiftUISingleDiscussionActions/userWantsToForwardMessages(discussionIdentifier:cellIdentifiers:)`` hands in what the reader ticked. The
    /// question put to them is identical, and so is everything after it.
    ///
    /// **The messages arrive already in the order they must be sent in.** A selection is a set of ticks and has no order a recipient would recognise; putting them
    /// in one is the caller's job, that being the only place that can read the discussion's own ordering.
    ///
    /// **`false` means the reader backed out, and a failure throws.** The two must not share an answer: backing out is an ordinary outcome after which nothing
    /// has happened and the caller keeps its selection, where a failure may have sent *some* of the messages already — the coordinator throws on the first
    /// operation that cancels, after the ones before it have gone. A reader told nothing in that case would forward again and duplicate what arrived. So a
    /// thrown error is what puts the alert up, and it is the only thing that does.
    ///
    /// - Returns: whether the reader chose anywhere to send them. `false` only when they backed out of the chooser.
    func forward(_ messages: [PersistedMessage]) async throws -> Bool {

        guard let viewController, let delegate else { assertionFailure(); throw ObvError.theDelegateIsNotSet }

        // **Every message must be held by a main-queue context.** That we are on the main thread is settled by isolation; which queue owns these objects is not,
        // and nothing in the signature says. A nil context is a message that has gone, which is an ordinary race; a context of the wrong kind is a programming
        // error, and the only one of the two worth asserting.
        for message in messages {
            guard let context = message.managedObjectContext else { throw ObvError.theMessagesAreNoLongerThere }
            guard context.concurrencyType == .mainQueueConcurrencyType else { assertionFailure(); throw ObvError.theMessagesBelongToAnotherQueue }
        }

        guard let firstMessage = messages.first else { throw ObvError.theMessagesAreNoLongerThere }
        guard let ownedCryptoId = firstMessage.discussion?.ownedIdentity?.cryptoId else { throw ObvError.theMessagesAreNoLongerThere }

        // **Everything is read off the messages before the chooser goes up, and nothing of them crosses the wait.** A chooser can stand there for as long as the
        // reader likes, and a managed object read on the far side of it may have been deleted from another device in the meantime — so what survives the
        // suspension is identifiers, which are values.
        let identifiersOfMessagesToForward = messages.compactMap { try? $0.messageAppIdentifier }
        guard identifiersOfMessagesToForward.count == messages.count else { assertionFailure(); throw ObvError.theMessagesAreNoLongerThere }
        // Where they are being forwarded *from*, which is only wanted at the very end and is read here for the same reason.
        let origin = try? firstMessage.discussion?.discussionIdentifier

        let chosenDiscussions = await asksWhereTheyShouldGo(ownedCryptoId: ownedCryptoId)
        guard !chosenDiscussions.isEmpty else { return false }

        let identifiersOfDiscussions: Set<ObvDiscussionIdentifier> = Set(chosenDiscussions.compactMap { discussionID in
            guard let discussion = try? PersistedDiscussion.get(objectID: discussionID.objectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return nil }
            return try? discussion.discussionIdentifier
        })
        guard !identifiersOfDiscussions.isEmpty else { assertionFailure(); throw ObvError.theDiscussionsAreNoLongerThere }

        // **Rethrown rather than swallowed.** This is where a partial forward becomes visible: the coordinator sends message by message and throws on the first
        // that refuses, so the ones before it have already arrived. Answering `false` here would tell the caller *the reader changed their mind*, and a reader
        // who is told nothing will send the whole selection again.
        try await delegate.userWantsToForwardMessages(viewController,
                                                      identifiersOfMessagesToForward: identifiersOfMessagesToForward,
                                                      identifiersOfDiscussionsWhereMessagesShouldBeForwarded: identifiersOfDiscussions)

        // Follows them, if they all went to one place — legacy's rule, unchanged by there being several of them: where they went is a fact about the destination
        // and not about how many were sent.
        if identifiersOfDiscussions.count == 1, let destination = identifiersOfDiscussions.first {
            navigateIfAppropriate(to: destination, afterForwardingFrom: origin)
        }

        return true

    }


    /// Forwards one message, chosen from its own context menu.
    ///
    /// **The menu has nowhere to report a failure**, there being no state on the screen for it — the plural path has one, and this is the older half of the
    /// feature, which has always logged and asserted rather than telling the reader. Transcribed from the legacy screen, which does the same. What matters is
    /// that the failure is not silently turned into *the reader changed their mind*: see ``forward(_:)``.
    private func forwardFromTheMenu(_ message: PersistedMessage) async {
        do {
            _ = try await forward([message])
        } catch {
            Self.logger.fault("Could not forward message: \(error.localizedDescription, privacy: .public)")
            assertionFailure()
        }
    }


    /// Puts the chooser up and waits for the reader to answer it.
    ///
    /// **Suspends on a continuation held by this object**, `NewDiscussionsSelectionViewController` answering through a delegate rather than returning anything.
    /// See ``whereTheMessagesShouldGo`` for why exactly one resume is the whole of the care this needs, and for the third way out that neither of the obvious two
    /// covers.
    ///
    /// **This object becomes the sheet's `presentationController` delegate**, which is that third way out: a sheet pulled down calls neither the accept nor the
    /// Cancel path, and without it a reader who dismissed the chooser by hand would leave a task waiting for ever and a selection mode with a disabled menu.
    ///
    /// - Returns: the discussions chosen, or an empty array if the reader backed out by any of the three routes.
    private func asksWhereTheyShouldGo(ownedCryptoId: ObvCryptoId) async -> [TypeSafeManagedObjectID<PersistedDiscussion>] {

        guard let viewController else { assertionFailure(); return [] }

        // A chooser already up. It cannot happen from the reader's side — the menu declines while a forward is under way and a context menu cannot be opened over
        // a presented sheet — and resuming the old continuation here rather than replacing it silently is what keeps that true rather than merely likely.
        guard whereTheMessagesShouldGo == nil else { assertionFailure(); return [] }

        let viewModel = NewDiscussionsSelectionViewController.ViewModel(
            viewContext: ObvStack.shared.viewContext,
            preselectedDiscussions: [],
            ownedCryptoId: ownedCryptoId,
            restrictToActiveDiscussions: true,
            attachSearchControllerToParent: false,
            buttonTitle: CommonString.Word.Forward,
            buttonSystemIcon: .arrowshapeTurnUpForwardFill)
        let vc = NewDiscussionsSelectionViewController(viewModel: viewModel, delegate: self)

        // **Answered in the dismissal's completion and not beside it**, exactly as the accept path is. Resuming while the sheet is still animating out lets the
        // caller finish, and the screen re-enable its menu, inside the ~350ms the dismissal takes — whereupon a second Forward would ask to present over a
        // presentation still in flight. UIKit drops that one silently, so no answer would ever come back and the mode would be left with a menu that never
        // answers again.
        vc.whatCancelDoes = { [weak self] in
            guard let presented = self?.viewController?.presentedViewController else {
                self?.theReaderHasChosen([])
                return
            }
            presented.dismiss(animated: true) { [weak self] in
                self?.theReaderHasChosen([])
            }
        }

        let nav = ObvNavigationController(rootViewController: vc)
        // **The third way out, watched by an object of its own.** `UIAdaptivePresentationControllerDelegate` refines `NSObjectProtocol`, which a plain Swift
        // class cannot conform to — and making this whole presenter an `NSObject` to gain one callback would be a change to its identity for the sake of a
        // detail. So a small `NSObject` watches for it and says so. It is held here because `presentationController.delegate` is **weak**: an adapter created
        // inline would be released before the reader ever touched the sheet, and the callback would simply never come.
        let noticesADismissalByHand = ADismissalByHand { [weak self] in self?.theReaderHasChosen([]) }
        self.noticesADismissalByHand = noticesADismissalByHand
        nav.presentationController?.delegate = noticesADismissalByHand

        return await withCheckedContinuation { continuation in
            self.whereTheMessagesShouldGo = continuation
            viewController.present(nav, animated: true)
        }

    }


    /// The one place the chooser's answer is delivered, whichever of the three ways out produced it.
    ///
    /// Nils the continuation as it resumes it, so that a second way out arriving afterwards does nothing at all rather than crashing.
    private func theReaderHasChosen(_ discussions: [TypeSafeManagedObjectID<PersistedDiscussion>]) {
        guard let continuation = whereTheMessagesShouldGo else { return }
        whereTheMessagesShouldGo = nil
        noticesADismissalByHand = nil
        continuation.resume(returning: discussions)
    }


    /// Takes the reader to the discussion the messages were forwarded to, unless that is the discussion they are already in.
    ///
    /// Through the deep link the legacy screen uses, which is what knows how to reach a discussion from anywhere.
    private func navigateIfAppropriate(to destination: ObvDiscussionIdentifier, afterForwardingFrom origin: ObvDiscussionIdentifier?) {
        guard destination != origin else { return }
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: .singleDiscussion(discussionIdentifier: destination))
            .postOnDispatchQueue()
    }

}


// MARK: - NewDiscussionsSelectionViewControllerDelegate

/// `@preconcurrency` because `NewDiscussionsSelectionViewControllerDelegate` promises nothing about isolation while this class is main-actor bound — the same
/// reason ``SwiftUISingleDiscussionAttachmentPresenter`` needs it for `QLPreviewControllerDelegate`. Without it, the conformance is a warning today and an error
/// under the Swift 6 language mode. The legacy screen does not need it only because a `UIViewController` is main-actor by inference.
extension SwiftUISingleDiscussionMessagePresenter: @preconcurrency NewDiscussionsSelectionViewControllerDelegate {

    func userAcceptedlistOfSelectedDiscussions(_ listOfSelectedDiscussions: [TypeSafeManagedObjectID<PersistedDiscussion>], in newDiscussionsSelectionViewController: UIViewController) {
        newDiscussionsSelectionViewController.dismiss(animated: true) { [weak self] in
            self?.theReaderHasChosen(listOfSelectedDiscussions)
        }
    }

}


// MARK: - Noticing a sheet the reader pulled down

/// **The third way out of a presented sheet**, and the one that fires neither an accept nor a Cancel: the reader dragging it down. Without it, backing out that
/// way would leave the task that is waiting for an answer suspended for ever — a forward that never returns, and a selection mode whose menu never answers again.
///
/// **A small object rather than a conformance on the presenter**, because `UIAdaptivePresentationControllerDelegate` refines `NSObjectProtocol` and a plain Swift
/// class cannot conform to it. Making the presenter an `NSObject` for one callback would change what that type *is* to gain a detail.
///
/// It must be **held** by whoever installs it: `UIPresentationController.delegate` is weak.
extension SwiftUISingleDiscussionMessagePresenter {

    enum ObvError: Error {
        /// Nothing to forward a request to. It cannot happen while the screen is up, this being set as the screen is built.
        case theDelegateIsNotSet
        /// Every message that was chosen has gone — deleted from another device, or wiped as it expired — between the choosing and the sending.
        case theMessagesAreNoLongerThere
        /// The discussions the reader picked could not be read back. A discussion can be deleted while the chooser stands open.
        case theDiscussionsAreNoLongerThere
        /// A message was handed in that some context other than a main-queue one holds, which this — being on the main actor — may not read. A programming
        /// error rather than anything the reader can cause, and refused rather than read anyway.
        case theMessagesBelongToAnotherQueue
    }

}


private final class ADismissalByHand: NSObject, UIAdaptivePresentationControllerDelegate {

    private let itWasDismissed: () -> Void

    init(_ itWasDismissed: @escaping () -> Void) {
        self.itWasDismissed = itWasDismissed
        super.init()
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        itWasDismissed()
    }

}


// MARK: - Calling back, and deleting

extension SwiftUISingleDiscussionMessagePresenter {

    /// Calls back from a call log, which is the one entry only a system message ever offers.
    ///
    /// One contact is called directly and several are offered the chooser, which is the same shape as calling from the navigation bar — but it is transcribed rather
    /// than shared, because this reads *who was on the call* while that reads who the discussion is with, and the two are not the same set.
    private func callBackFrom(_ message: PersistedMessage) {

        guard let systemMessage = message as? PersistedMessageSystem else { assertionFailure(); return }
        guard let item = systemMessage.optionalCallLogItem else { return }
        let groupId = item.groupIdentifier

        let contactCryptoIds = item.logContacts.compactMap { try? $0.contactIdentity?.cryptoId }
        let ownedCryptoIds = item.logContacts.compactMap { $0.contactIdentity?.ownedIdentity?.cryptoId }
        guard ownedCryptoIds.count == 1, let ownedCryptoId = ownedCryptoIds.first else { assertionFailure(); return }

        if contactCryptoIds.count == 1 {
            ObvMessengerInternalNotification.userWantsToCallOrUpdateCallCapabilityButWeShouldCheckSheIsAllowedTo(
                ownedCryptoId: ownedCryptoId,
                contactCryptoIds: Set(contactCryptoIds),
                groupId: groupId,
                startCallIntent: nil)
            .postOnDispatchQueue()
        } else {
            ObvMessengerInternalNotification.userWantsToSelectAndCallContacts(
                ownedCryptoId: ownedCryptoId,
                contactCryptoIds: Set(contactCryptoIds),
                groupId: groupId)
            .postOnDispatchQueue()
        }

    }


    /// Deletes a message, asking first which kind of deletion is meant.
    ///
    /// The kinds on offer are `deletionTypesThatCanBeMadeAvailableForThisMessage`, which simulates each deletion on a child of the view context — the reason the
    /// whole answer to *what does this message offer* is computed at press time and on the main thread.
    ///
    /// A **wiped** message skips the question, as on the legacy screen: there is nothing left of it anywhere but on this device, so the only meaningful deletion is
    /// chosen for the reader.
    private func offerToDelete(_ message: PersistedMessage) {

        guard let viewController else { assertionFailure(); return }
        guard let ownedCryptoId = message.discussion?.ownedIdentity?.cryptoId else { assertionFailure(); return }

        if message.isWiped {
            deleteMessage(objectID: message.objectID, ownedCryptoId: ownedCryptoId, deletionType: .fromThisDeviceOnly)
            return
        }

        viewController.present(deletionAlert(for: message, ownedCryptoId: ownedCryptoId), animated: true)

    }


    /// The question asked before a message is deleted: what it is about to take with it, and which kinds of deletion are open.
    ///
    /// Wording and structure are the legacy screen's, and the strings are literally its own — `NewSingleDiscussionViewController.Strings` — so that the two screens
    /// cannot come to say different things about the same act.
    ///
    /// **Nothing of the message survives into the buttons but its object ID.** An action sheet can stand there for as long as the reader likes, and the message may
    /// be deleted from another device while it does; a button holding the managed object would then read a deleted object to find out who owns it. Legacy avoids
    /// this the same way, by carrying the object ID through and re-reading nothing.
    private func deletionAlert(for message: PersistedMessage, ownedCryptoId: ObvCryptoId) -> UIAlertController {

        let objectID = message.objectID
        let ownedIdentityHasAnotherReachableDevice = message.discussion?.ownedIdentity?.hasAnotherDeviceWhichIsReachable ?? false
        let multipleContacts = Self.discussionHasMultipleContacts(message.discussion)
        let numberOfAttachedFyles = message.fyleMessageJoinWithStatus?.filter({ !$0.isWiped }).count ?? 0

        let title = numberOfAttachedFyles > 0 ? NewSingleDiscussionViewController.Strings.deleteMessageAndAttachmentsTitle : NewSingleDiscussionViewController.Strings.deleteMessageTitle
        let alert = UIAlertController(title: title,
                                      message: NewSingleDiscussionViewController.Strings.deleteMessageAndAttachmentsMessage(numberOfAttachedFyles),
                                      preferredStyle: .actionSheet)

        for deletionType in message.deletionTypesThatCanBeMadeAvailableForThisMessage.sorted() {
            let buttonTitle = CommonString.AlertButton.deletionActionTitle(for: deletionType,
                                                                          ownedIdentityHasHasAnotherReachableDevice: ownedIdentityHasAnotherReachableDevice,
                                                                          multipleContacts: multipleContacts)
            alert.addAction(UIAlertAction(title: buttonTitle, style: .destructive) { [weak self] _ in
                self?.deleteMessage(objectID: objectID, ownedCryptoId: ownedCryptoId, deletionType: deletionType)
            })
        }

        alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))

        // The screen rather than the cell, as for the activity sheet above: there is no cell here to anchor a popover to.
        alert.popoverPresentationController?.sourceView = viewController?.view

        return alert

    }


    /// Asks for the deletion, through the notification the legacy screen posts. A message already gone is the coordinator's business to notice, not this screen's.
    private func deleteMessage(objectID: NSManagedObjectID, ownedCryptoId: ObvCryptoId, deletionType: DeletionType) {
        ObvMessengerInternalNotification.userRequestedDeletionOfPersistedMessage(
            ownedCryptoId: ownedCryptoId,
            persistedMessageObjectID: objectID,
            deletionType: deletionType)
        .postOnDispatchQueue()
    }


    /// Whether a discussion is with more than one person, which changes what "delete for everyone" is called.
    private static func discussionHasMultipleContacts(_ discussion: PersistedDiscussion?) -> Bool {
        guard let discussion else { assertionFailure(); return false }
        do {
            switch try discussion.kind {
            case .oneToOne:
                return false
            case .groupV1(withContactGroup: let group):
                guard let group else { assertionFailure(); return false }
                return group.contactIdentities.count > 1
            case .groupV2(withGroup: let group):
                guard let group else { assertionFailure(); return false }
                return group.otherMembers.count > 1
            }
        } catch {
            assertionFailure()
            // The cautious answer: a title that speaks of several contacts is harmless where there is one, and the reverse is not.
            return true
        }
    }

}


// MARK: - The sheet listing who reacted to a message

extension SwiftUISingleDiscussionMessagePresenter {

    /// Shows who reacted to a message, and with what, the reader having tapped the chip of reactions under it.
    ///
    /// The sheet, its detents and its grabber are the legacy screen's `userTappedOnReactionView`, unchanged: a medium or large
    /// sheet on iOS, a plain presentation under Catalyst where there are no detents. The navigation controller is not
    /// decoration — the sheet pushes a picker of its own, and it holds the *Done* button that answers
    /// ``userWantsToDismissObvMessageReactionsViewController(_:)``.
    ///
    /// Asked with the identifier the chip already carried, so nothing is looked up here to open it.
    func showWhoReacted(to messageIdentifier: ObvMessageReactionsViewModel.MessageIdentifier) async {

        guard let viewController else { assertionFailure(); return }

        let vc = ObvMessageReactionsViewController(messageIdentifier: messageIdentifier,
                                                  dataSource: messageReactionsViewDataSource,
                                                  avatarViewDataSource: avatarViewDataSource,
                                                  delegate: self)
        let nav = UINavigationController(rootViewController: vc)

        if !ObvMessengerConstants.targetEnvironmentIsMacCatalyst, let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 30.0
        }

        viewController.present(nav, animated: true)

    }

}


// MARK: - Implementing ObvMessageReactionsViewControllerDelegate

extension SwiftUISingleDiscussionMessagePresenter: ObvMessageReactionsViewControllerDelegate {

    /// The reader took their own reaction back, from the sheet rather than from the context menu.
    ///
    /// Named by the **reaction**, which is the only thing the sheet knows — so the message it belongs to is read here, and it
    /// is the message that the engine is then told about. The haptic is why this does not go through the same private helper
    /// as the context menu's *Delete my reaction*: what the reader feels depends on whether the request threw, and that
    /// helper swallows the error.
    func userWantsToRemoveReaction(_ vc: ObvMessageReactionsViewController, reactionIdentifier: ObvMessageReactionsViewModel.ReactionIdentifier) async throws {

        guard let viewController, let delegate else { assertionFailure(); return }

        switch reactionIdentifier {

        case .forPreviews:
            assertionFailure("A preview's identifier cannot reach the app")
            return

        case .objectID(let objectID):
            let reaction = try PersistedMessageReactionSent.get(with: TypeSafeManagedObjectID<PersistedMessageReactionSent>(objectID: objectID), within: ObvStack.shared.viewContext)
            guard let reaction else { assertionFailure(); return }
            // Not an assertion failure: a reaction whose message or discussion has gone in the meantime is a race, not a bug.
            guard let ownedCryptoId = reaction.message?.discussion?.ownedIdentity?.cryptoId else { return }
            guard let messageObjectID: TypeSafeManagedObjectID<PersistedMessage> = reaction.message?.typedObjectID else { return }
            do {
                try await delegate.userWantsToUpdateReaction(viewController, ownedCryptoId: ownedCryptoId, messageObjectID: messageObjectID, newEmoji: nil)
                notificationGenerator.notificationOccurred(.success)
            } catch {
                notificationGenerator.notificationOccurred(.error)
            }

        }

    }


    /// The reader kept an emoji they met in the sheet, which goes to the **front** of their favourites, as on the legacy screen.
    func userWantsToAddReactionToFavorites(_ vc: ObvMessageReactionsViewController, emoji: Character) async throws {
        ObvMessengerSettings.Emoji.preferredEmojisList.insert(String(emoji), at: 0)
        notificationGenerator.notificationOccurred(.success)
    }


    func userWantsToRemoveReactionFromFavorites(_ vc: ObvMessageReactionsViewController, emoji: Character) async throws {
        ObvMessengerSettings.Emoji.preferredEmojisList.removeAll { $0 == String(emoji) }
        notificationGenerator.notificationOccurred(.success)
    }


    /// Dismisses **the navigation controller** the sheet was put in, and not the sheet itself: dismissing the child of a
    /// presented navigation controller does nothing at all.
    func userWantsToDismissObvMessageReactionsViewController(_ vc: ObvMessageReactionsViewController) {
        (vc.navigationController ?? vc).dismiss(animated: true)
    }

}
