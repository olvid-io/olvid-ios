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

import Foundation
import ObvAppTypes
import ObvComposition
// For `WhatTheCompositionBarAsks`, the channel this tells that the reply has been dropped.
import ObvSingleDiscussion
import ObvTypes
import ObvUICoreData


/// Implements the actions of the composition bar of the SwiftUI single discussion screen.
///
/// This is a class of its own, and not the view controller of the screen, on purpose: a `ComposeView` and its subviews hold their actions **strongly**,
/// and SwiftUI retains the view tree, so a controller implementing them would be retained by the very view hierarchy it owns. Holding the controller
/// weakly here is what keeps that cycle from forming, which is also why `ComposeViewHostingController` proxies the actions of the legacy screen.
///
/// The whole of `ComposeViewActions` is implemented. What needs a view controller to show something is done by
/// ``SwiftUISingleDiscussionComposeActionPresenter``; what only needs a word with the flow controller is done here.
@MainActor
final class SwiftUISingleDiscussionComposeActions {

    private let draftObjectID: TypeSafeManagedObjectID<PersistedDraft>

    /// Weak, see the note on this class. Also the sender expected by ``SingleDiscussionViewControllerDelegate``.
    ///
    /// Handed on to the presenter, which needs something to present from and must not be told separately: two places to set one controller is one place to forget.
    weak var viewController: (any SomeSingleDiscussionViewController)? {
        didSet { presenter.viewController = viewController }
    }

    /// Weak as well: this is the flow controller, which owns the navigation stack this screen sits in.
    ///
    /// Handed on to the presenter for the same reason the controller is: what the `+` menu asks for ends at this delegate.
    weak var delegate: (any SingleDiscussionViewControllerDelegate)? {
        didSet { presenter.delegate = delegate }
    }

    /// The composition bar's own state, set by the controller that owns both. Handed on to the presenter, which is what says the bar may not be edited while
    /// something is loading and what puts back whatever turned out to be text.
    weak var composeViewSharedState: ComposeView.SharedState? {
        didSet { presenter.composeViewSharedState = composeViewSharedState }
    }

    /// How the screen is told the reply being answered has gone. Set by the controller that owns both.
    ///
    /// **Strong, where its three neighbours above are weak, and the difference is not an oversight.** Those are the view controller, the flow controller and the
    /// bar's shared state — objects that own this one, directly or through what owns it, so a strong reference back would close a cycle. This is a channel: it
    /// holds a continuation and nothing else, refers to nobody, and cannot be part of a cycle whoever points at it.
    var compositionBar: WhatTheCompositionBarAsks?

    /// Presents what the `+` menu asks for and answers the UIKit delegates that come with it — see ``SwiftUISingleDiscussionComposeActionPresenter``.
    private let presenter: SwiftUISingleDiscussionComposeActionPresenter

    init(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        self.draftObjectID = draftObjectID
        self.presenter = .init(draftObjectID: draftObjectID)
    }

    /// A file dropped onto this discussion from another device, forwarded to the presenter as everything else is.
    ///
    /// **Not part of `ComposeViewActions`**, and that is the point of it being here: the bar did not ask for this. UIKit hands the file to the view controller, which
    /// knows nothing about drafts, and the only thing on this side that knows how to put a file into one is the presenter. See
    /// ``SwiftUISingleDiscussionComposeActionPresenter/aFileArrivedFromAnotherDevice(at:)``.
    func aFileArrivedFromAnotherDevice(at url: URL) {
        presenter.aFileArrivedFromAnotherDevice(at: url)
    }

}


// MARK: - ComposeViewActions

extension SwiftUISingleDiscussionComposeActions: ComposeViewActions {

    /// The reader sent what they had written.
    ///
    /// **Sending is the third place the reply quote is dropped, and the screen has to be told about it like the other two** — added 2026-08-28, found by the
    /// reader on a Mac. A send consumes the whole draft, the quote included, so the bar stops showing the quotation on its own and the *next* message is
    /// correctly not a reply; but since Step 60 the screen is holding a message of its own beside the bar, and nothing here said so. What that looked like was a
    /// message left hanging over a discussion that stayed blurred, still claiming to be answered, while the reader went on sending messages that answered
    /// nothing.
    ///
    /// It is the same regression as the quote's own close button, one call site over. Legacy has **four** `hideReplyViewIfNeeded` call sites in
    /// `NewSingleDiscussionViewController` — Esc, the close button, `viewWillDisappear`, and this one at `userWantsToSendDraft` — and each is a thing a screen
    /// assembled by hand does in passing and a screen assembled from a framework has to be told to do.
    ///
    /// **After the send, not before, and that is the whole of the failure case.** A send that throws leaves the quote on the draft, so the message must stay
    /// beside the bar with something still to answer — and a save lost to a cross-process conflict is retried rather than abandoned, so a message put back here
    /// would be put back on a reply that is about to be sent after all. Legacy's order, for the same reason.
    ///
    /// Said **unconditionally**, whether or not a message is down: the invariant is *no quote, no message beside the bar*, and whether one is down is a fact of
    /// the screen rather than of this object, whose consumer opens with a guard that makes it a no-op.
    ///
    /// **A different call from the close button's, and it says *what happened* rather than *what to do***: a send is
    /// ``ObvSingleDiscussion.WhatTheCompositionBarAsks/theReplyBeingAnsweredWasSent()`` where the reader taking the quote away is
    /// ``ObvSingleDiscussion.WhatTheCompositionBarAsks/theReplyBeingAnsweredWasDropped()``. The screen makes the two look different — the copy fades where it
    /// sits rather than flying home, there being nothing to give back once the reply has become a message — but that is the screen's conclusion to draw from
    /// what happened, and not this object's to ask for.
    func userWantsToSendDraft(_ sharedState: ComposeView.SharedState, discussionIdentifier: ObvDiscussionIdentifier, attributedText: AttributedString) async throws {
        guard let viewController, let delegate else { assertionFailure(); return }
        try await delegate.userWantsToSendDraft(viewController, draftObjectID: draftObjectID, textBody: attributedText)
        compositionBar?.theReplyBeingAnsweredWasSent()
    }


    func composeViewHasChangedTextAndMentions(_ sharedState: ComposeView.SharedState, discussionIdentifier: ObvDiscussionIdentifier, attributedText: AttributedString) async throws {
        guard let viewController, let delegate else { assertionFailure(); return }
        try await delegate.userWantsToUpdateDraftBodyAndMentions(viewController, draftObjectID: draftObjectID, body: attributedText)
    }

    /// One of the `+` card's entries.
    func actionTapped(_ view: ComposeView, for action: ComposeViewParameters.Action, discussionIdentifier: ObvDiscussionIdentifier, contactIdentifier: ObvContactIdentifier?) async throws {
        switch action {

        case .chooseImageFromLibrary:
            presenter.showThePhotoLibrary()

        case .choseFile:
            presenter.showsTheFileBrowser()

        case .scanDocument:
            presenter.showsTheDocumentScanner()

        case .shootPhotoOrMovie:
            presenter.showsTheCamera()

        case .oneTimeEphemeralMessage:
            presenter.showsHowLongThisMessageWillLast()

        case .pasteContent:
            presenter.pastesWhateverIsOnThePasteboard()

        case .composeMessageSettings:
            presenter.showsTheSettingsOfTheComposeBar()

        // The three that only need a word with the flow controller, which owns the navigation this screen sits in.

        case .introduceThisContact:
            // Nothing to open for a discussion that is not with one contact. The bar does not offer the action there, so this is a guard rather than a case.
            guard let contactIdentifier else { return }
            guard let viewController, let delegate else { assertionFailure(); return }
            delegate.userWantsToDisplayContactIntroductionScreen(viewController, contactIdentifier: contactIdentifier)

        case .shareLocation:
            guard let viewController, let delegate else { assertionFailure(); return }
            try await delegate.userWantsToShowMapToSendOrShareLocationContinuously(viewController, discussionIdentifier: discussionIdentifier)

        case .createPoll:
            guard let viewController, let delegate else { assertionFailure(); return }
            try await delegate.userWantsToCreatePoll(viewController, discussionIdentifier: discussionIdentifier)

        }
    }

    /// The reader tapped one of the files already attached to the draft, to look at it.
    func userDidTapOnDraftFyleJoinWithHardLink(_ view: ComposeAttachmentsView, at index: Int) throws {
        try presenter.showsTheFileOfTheDraft(at: index)
    }

    /// A recording the reader has just finished, which becomes an attachment on the draft like any other file.
    ///
    /// The bar is closed to editing while the file is added, as it is for everything else that writes to the draft. See
    /// ``SwiftUISingleDiscussionComposeActionPresenter``.
    func userDidRecordAudio(at url: URL, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        guard let viewController, let delegate else { assertionFailure(); return }
        composeViewSharedState?.setIsDiscussionViewPreventingEdition(true)
        defer { composeViewSharedState?.setIsDiscussionViewPreventingEdition(false) }
        try await delegate.userWantsToAddAttachmentsToDraftFromURLs(viewController, draftObjectID: draftObjectID, urls: [url])
    }

    /// The reader no longer wants to answer the message quoted above the bar.
    ///
    /// **Two things happen, not one**: the quote comes off the draft, and the message Step 60 brought down beside the bar is put away. Doing only the first
    /// leaves a message hanging over a blurred discussion with nothing left to answer. Legacy does both from the one tap —
    /// `userWantstoRemoveReplyToMessage(_:discussionIdentifier:)` removes the quote and then calls `hideReplyViewIfNeeded(animated: true)`.
    ///
    /// **The draft first, then the message**, which is legacy's order and the order that reads correctly. The other way round, the screen finishes putting the
    /// message back, reports that nothing is held beside the bar, and the quote panel **unfolds** — its body and thumbnail fading in over a quarter second —
    /// only for the whole panel to vanish a moment later when the draft is finally cleared. Clearing the draft first takes the panel away while the message is
    /// still down, so nothing unfolds on its way out.
    func userWantstoRemoveReplyToMessage(_ view: ComposeReplyToView, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        guard let viewController, let delegate else { assertionFailure(); return }
        try await delegate.userWantsToRemoveReplyToMessage(viewController, draftObjectID: draftObjectID)
        compositionBar?.theReplyBeingAnsweredWasDropped()
    }


    /// **Takes the reply quote off the draft, asked by something that is not the bar**, where Esc means it.
    ///
    /// The same call the quote's own close button makes, so there is one way to drop a reply rather than two. It is asked **unconditionally**: whether a draft
    /// carries a quote is a fact of the draft rather than of this object, and the write is idempotent where it does not. What that costs is that Esc's last
    /// priority cannot report whether it did anything — see the note in `SingleDiscussionView.answersTheEscapeKey`, which is why legacy's *dismiss the top
    /// presented controller* is not layered after it on faith.
    ///
    /// **Not `assertionFailure` on a missing delegate**, unlike its neighbour above: this is reached by a key that may be pressed at any moment, including while
    /// the screen is being torn down, where the one above is reached by a button that cannot be tapped unless the bar is on screen.
    func theReplyDraftGoesAwayIfThereIsOne() async {
        guard let viewController, let delegate else { return }
        try? await delegate.userWantsToRemoveReplyToMessage(viewController, draftObjectID: draftObjectID)
        // **Said here as well as at the close button, and the invariant is what justifies it rather than a case that needs it**: no quote, no message beside the
        // bar. Esc cannot presently reach this with a message down — the screen's own Esc priority puts it back first, and a treatment already leaving takes a
        // second press — so today this is a no-op. Saying it at every place the quote is dropped keeps the invariant in one shape; leaving it out here would make
        // it depend on Esc's priority list, which is a thing that changes.
        compositionBar?.theReplyBeingAnsweredWasDropped()
    }

    func userWantsToOpenEmojiPicker() {
        presenter.showsTheEmojiPickerForTheDefaultEmoji()
    }

    // **Three entry points, one answer.** The cross is drawn on an attachment tile, on a link preview, and on the bar itself, and the protocol names each of them
    // separately so that the caller can be identified — but what the reader asked for is the same in all three cases, so all three forward to one place, as the
    // legacy screen does.

    func userWantsToDeleteDraftAttachment(_ view: ComposeAttachmentView, attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws {
        try await removesTheDraftAttachment(attachmentIdentifier)
    }

    func userWantsToDeleteDraftAttachment(_ view: ComposeView, attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws {
        try await removesTheDraftAttachment(attachmentIdentifier)
    }

    func userWantsToDeleteDraftAttachment(_ view: ComposeLinkPreviewView, attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws {
        try await removesTheDraftAttachment(attachmentIdentifier)
    }


    /// Takes an attachment off the draft, which is a database operation and therefore the flow controller's to carry out.
    ///
    /// The identifier is unwrapped here rather than crossing the boundary as an object ID: `AttachmentIdentifier` is the composition bar's own vocabulary — one case
    /// today — and `TypeSafeManagedObjectID<PersistedDraftFyleJoin>` is what the delegate is keyed by. Nothing is fetched on the way; the operation reads the join.
    private func removesTheDraftAttachment(_ attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws {
        guard let viewController, let delegate else { assertionFailure(); return }
        let draftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>
        switch attachmentIdentifier {
        case .persistedDraftFyleJoinObjectID(let objectID):
            draftFyleJoinObjectID = .init(objectID: objectID)
        }
        try await delegate.userWantsToDeleteDraftAttachment(viewController, draftFyleJoinObjectID: draftFyleJoinObjectID)
    }


    /// The size this draft's photographs are to be sent at: recorded on the draft, so it is the flow controller's to carry out.
    func userWantsToChangeTheMediaFormatOfTheDraft(_ view: ComposeView, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, format: ObvMediaFormat) async throws {
        guard let viewController, let delegate else { assertionFailure(); return }
        try await delegate.userWantsToChangeTheMediaFormatOfTheDraft(viewController, draftObjectID: draftObjectID, format: format)
    }

    /// What the reader pasted, typed as a Genmoji or dropped in as a sticker: handed over whole, and whatever comes back as
    /// text is returned for the shared state to write into the editor.
    ///
    /// **Nothing is decided here, which is the point.** One operation on the app's side reads what it was given and decides,
    /// item by item, what becomes an attachment and what belongs in the text — a pasted link being both. This screen only
    /// carries the question there and the answer back.
    ///
    /// **`source: .paste` is a constant, exactly as it is on the legacy screen.** It is read in one branch of
    /// `LoadItemProviderHelper` and only to decide whether *text* arrives as a file: a drop attaches it, a paste inserts it.
    /// All three ways content reaches the bar are the reader putting it there, so all three are a paste, and the
    /// worry that this route needed to carry a `source` of its own was mistaken.
    func userWantsToAddAttachmentsToDraft(_ sharedState: ComposeView.SharedState, discussionIdentifier: ObvDiscussionIdentifier, itemProviders: [NSItemProvider]) async throws -> [TextToPasteIntoTheDraft] {
        guard let viewController, let delegate else { assertionFailure(); return [] }
        let loadedItemProvidersToPaste = try await delegate.userWantsToAddAttachmentsToDraft(viewController, draftObjectID: draftObjectID, itemProviders: itemProviders, source: .paste)
        return loadedItemProvidersToPaste.map(\.forTheComposeView)
    }

}
