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

@preconcurrency import Foundation
import SwiftUI
import ObvSettings
import Combine
import ObvAppTypes
import UniformTypeIdentifiers
import AVFoundation
import OSLog
import ObvAppCoreConstants
import ObvSystemIcon
import ObvTypes
import ObvDesignSystem


extension ComposeView {
    
    /// State shared among the main view and the subviews of the composition view.
    ///
    /// Public, as the owner of a ``ComposeView`` embedded in a SwiftUI hierarchy has to create it and keep it alive, exactly as
    /// `ComposeViewHostingController` does. Its members remain internal: a host is not expected to reach into this state, only to hold it.
    @MainActor
    public final class SharedState: ObservableObject {

        private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: SharedState.self))

        public init(discussionIdentifier: ObvDiscussionIdentifier,
                    initialBody: AttributedString?,
                    containerURLforTempFiles: URL,
                    initialParameters: ComposeViewParameters) {
            
            self.discussionIdentifier = discussionIdentifier
            self.containerURLforTempFiles = containerURLforTempFiles
            self.parameters = initialParameters
            self.textFieldSharedState = .init(discussionIdentifier: discussionIdentifier,
                                              initialBody: initialBody,
                                              initialSendMessageShortcutType: initialParameters.sendMessageShortcutType)
            self.mentionViewSharedState = .init(discussionIdentifier: discussionIdentifier)
            
            self.mentionViewSharedState.globalSharedState = self
            self.textFieldSharedState.globalSharedState = self

            // Same source of truth as on every later change of text (see `onTextChangeInTextEditor`), so that a draft carried over from a previous visit
            // is reflected on the first frame rather than after the text editor has appeared.
            self.isTextEditorEmpty = (self.textFieldSharedState.computeAttributedStringFromCurrentTextInTextEditor() == nil)

        }
        
        deinit {
            debugPrint("Deinit")
        }

        let discussionIdentifier: ObvDiscussionIdentifier

        
        let globalCornerRadius: CGFloat = 20.0
        
        
        /// What this state asks to have done on the user's behalf: saving the draft, sending it, adding attachments to it.
        ///
        /// **Weak, and deliberately so.** This was a `SharedStateDelegate` implemented by `ComposeView`, which meant this long-lived object stored a *copy
        /// of a view struct* — and a `ComposeView` holds this state back through its `@ObservedObject`. The two retained each other, so no shared state was
        /// ever deallocated on either discussion screen, taking with it both child shared states, their Combine subscriptions, and the actions object of a
        /// screen already popped. `ComposeViewActions` is `AnyObject`, and its instance is owned by the host — a `private let` on both
        /// `ComposeViewHostingController` and `SwiftUISingleDiscussionViewController` — so weak is sound as well as sufficient.
        private weak var actions: (any ComposeViewActions)?

        func setActions(to newActions: any ComposeViewActions) {
            self.actions = newActions
        }
        
        /// Allows to disable many parts of the compose view interface.
        @Published private(set) var isCurrentlySendingMessage = false
        
        
        private func setIsCurrentlySendingMessage(_ newValue: Bool) {
            self.isCurrentlySendingMessage = newValue
            self.textFieldSharedState.isPreventingEdition = self.isPreventingEdition
        }
        
        
        /// Allows the discussion view controller to disable the composition interface when it is loading something (e.g., while performing a drag and drop of a new attachment).
        @Published private(set) var isDiscussionViewPreventingEdition = false
        
        /// For now, this is only used when the user types a memoji in the text editor: in that case, we strip the memoji from the `AttributedString` and add its image as an attachment.
        /// During the process, `isLocallyAddingAttachment` is set to true.
        @Published private var isLocallyAddingAttachment = false
        
        /// How far the loading of the attachments being added has got, or nil when nothing is being loaded.
        ///
        /// **Only the loading**, which is measured to be very nearly all of the wait: on a 160 MB clip the system took 59.4 s to hand the
        /// file over, against 108 ms for everything this app then does with it. The bar is shut to editing for other reasons too —
        /// sending, most of all — and those have no fraction to show and go on showing a spinner.
        @Published private(set) var attachmentsLoadingFractionCompleted: Double?

        /// Set by whatever is loading attachments into this draft. See ``attachmentsLoadingFractionCompleted``.
        public func setAttachmentsLoadingFractionCompleted(_ fractionCompleted: Double?) {
            guard self.attachmentsLoadingFractionCompleted != fractionCompleted else { return }
            self.attachmentsLoadingFractionCompleted = fractionCompleted
        }

        /// How far the exports of the draft's videos have got, or nil when none is running.
        ///
        /// Read while a send waits for them: the tiles stay on screen and the editor shows this fraction, where it would otherwise show a
        /// spinner over an empty row for as long as the exports take.
        @Published private(set) var fractionOfTheVideosBeingPrepared: Double?

        func setFractionOfTheVideosBeingPrepared(_ fractionCompleted: Double?) {
            guard self.fractionOfTheVideosBeingPrepared != fractionCompleted else { return }
            self.fractionOfTheVideosBeingPrepared = fractionCompleted
        }

        /// This is used to disable various parts of the compose view.
        ///
        /// We do not disable all the views at once as disabling the TextEditor dismisses the keyboard and shows it a few milliseconds later,
        /// causing a bad user experience.
        var isPreventingEdition: Bool { isCurrentlySendingMessage || isDiscussionViewPreventingEdition || isLocallyAddingAttachment }
        
        
        /// Public because a screen that **owns** this shared state has no hosting controller to be called on: the legacy screen reaches the same method through
        /// `ComposeViewHostingController.isDiscussionViewPreventingEdition`, and the SwiftUI one holds this object itself. Step 19b, item 13.
        public func setIsDiscussionViewPreventingEdition(_ isLoading: Bool) {
            guard self.isDiscussionViewPreventingEdition != isLoading else { return }
            withAnimation {
                self.isDiscussionViewPreventingEdition = isLoading
                self.textFieldSharedState.isPreventingEdition = self.isPreventingEdition
            }
        }
        
        
        @Published var showNoRecordPermissionAlert: Bool = false
        
        
        @Published private(set) var hasReplyViewDisplayedAbove = false
        
        
        /// **Public** since 2026-08-27, Step 60: the SwiftUI discussion screen builds `ComposeView` directly rather than through
        /// `ComposeViewHostingController`, so it reaches this state object itself where the legacy screen reaches the controller's `hasReplyViewDisplayedAbove`.
        /// The property stays `private(set)`; only this setter is exposed, the animation being part of what it means to set it.
        public func setHasReplyViewDisplayedAbove(to newValue: Bool) {
            guard self.hasReplyViewDisplayedAbove != newValue else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                self.hasReplyViewDisplayedAbove = newValue
            }
        }
                  
        
        private let containerURLforTempFiles: URL
        
        
        enum AudioRecorderState {
            case notRecording
            case longPressing
            case isRecording
            case recorded
        }
        
        
        @Published private(set) var recordingState: AudioRecorderState = .notRecording
        
        
        func setAudioRecorderState(to newValue: AudioRecorderState) {
            guard self.recordingState != newValue else { return }
            self.recordingState = newValue
        }

        
        private let dateFormatter: DateFormatter = {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd HH-mm-ss"
            return df
        }()
        
        
        @Published private(set) var mentionViewSharedState: ComposeMentionsView.SharedState
        private(set) var textFieldSharedState: ComposeTextField.SharedState
        
        
        /// Allows to transfer the user decision about suggested mentions back to the view allowing to input text.
        private var continuationForMentions: CheckedContinuation<ComposeTextField.SharedState.UserDecisionOnNewMentionString, Never>?
                
        
        @Published private(set) var isTextEditorEmpty = true
                
        
        fileprivate func onTextChangeInTextEditor(_ newText: AttributedString?) {
            // Saves the current version of the body to database
            Task {
                do {
                    try await actions?.composeViewHasChangedTextAndMentions(self, discussionIdentifier: discussionIdentifier, attributedText: newText ?? AttributedString())
                } catch {
                    assertionFailure()
                }
            }
            // Avoid publishing changes from within view updates
            Task { @MainActor in
                self.isTextEditorEmpty = (newText == nil)
            }
        }
        
        
        /// Set once at initialization, we expect the `ComposeView` to subscribe to a stream using the `ComposeViewParametersDataSource`
        /// and to update this value as required.
        @Published private(set) var parameters: ComposeViewParameters

        
        func onNewComposeViewParameters(_ newParameters: ComposeViewParameters) {
            self.parameters = newParameters
            self.textFieldSharedState.onNewSendMessageShortcutType(newParameters.sendMessageShortcutType)
        }
        
        
        /// Pastes provided text into the editor (e.g., the URL string after adding its preview as an attachment).
        ///
        /// This is used, e.g., when the user pastes an URL using the paste button of the compose view. In that case, the compose
        /// view requests to add attachments to the draft. An URL preview is added as an attachment, and the URL (as a String) is reported back
        /// here, so as to paste it in the `TextEditor`.
        /// Public for the same reason as ``setIsDiscussionViewPreventingEdition(_:)``: whoever owns this bar puts text back into it directly, rather than through a
        /// controller. What is pasted comes from ``ComposeViewActions/userWantsToAddAttachmentsToDraft(_:discussionIdentifier:itemProviders:)``, or from a screen
        /// that handed item providers over itself — the photo library, a scan, a file.
        public func pasteTextIntoTextEditor(_ textToPaste: AttributedString) {
            self.textFieldSharedState.pasteTextIntoTextEditor(textToPaste)
        }
        
        
        private var draftHasAttachments: Bool = false
        
        /// This is called by the compose view. The `draftHasAttachments` is only used when the user requests the sending of the draft, to ensure there is something to send.
        func setDraftHasAttachments(to newValue: Bool) {
            guard self.draftHasAttachments != newValue else { return }
            self.draftHasAttachments = newValue
        }


        private var draftQuotesAMessage: Bool = false

        /// Called by the compose view on every change of whether the draft quotes a message it replies to. See ``theDraftQuotesAMessage``.
        func setDraftQuotesAMessage(to newValue: Bool) {
            guard self.draftQuotesAMessage != newValue else { return }
            self.draftQuotesAMessage = newValue
        }

        /// Whether the draft quotes a message it replies to, as the bar currently shows it.
        ///
        /// Read by the discussion screen to order what Esc does when it has nothing of its own to dismiss: the quote goes first, and only when there is none does
        /// the caret leave the editor. The removal itself cannot say whether it removed anything, a quote being a fact of the draft rather than of this object.
        public var theDraftQuotesAMessage: Bool {
            draftQuotesAMessage
        }


        /// Takes the caret out of the editor, and the mention suggestions with it, and answers whether there was a caret to take.
        ///
        /// Asked by the discussion screen when the reader says they have finished typing — Esc with nothing left to dismiss, or on a Mac a click on the messages.
        /// Resigning the text view is what SwiftUI's own focus follows, so the editor's `@FocusState` goes false with it and nothing else has to be told.
        ///
        /// **The suggestions are dismissed here because nothing else would.** They follow the mention string the editor last reported, and the editor reports it on
        /// a change of *selection*; losing focus changes no selection, so with `@ali` under the caret the list stayed up after the resign and Esc read as having done
        /// nothing — measured on Catalyst on 2026-10-02, the resign itself having succeeded. The request left waiting is resumed as well, as it is when the bar goes
        /// away. The next click in the editor moves the selection and asks again.
        @discardableResult
        public func stopEditing() -> Bool {
            guard let textView = textFieldSharedState.textView, textView.isFirstResponder else { return false }
            let resigned = textView.resignFirstResponder()
            dismissTheMentionSuggestions()
            return resigned
        }


        /// Puts the caret in the editor, at the end of whatever is already there, unless it is there already, and answers whether it did.
        ///
        /// Asked by the discussion screen when the reader starts a reply: the quote has just gone into the bar, and what comes next is typing, so the bar is
        /// made ready for it rather than waiting for a tap. **At the end, on every platform**: the editors move the caret to the end themselves when they gain
        /// focus on a phone or a tablet, where a click on a Mac places it and so they leave it alone there; a focus given by code has no click to honour, so
        /// the end is right on a Mac too, and saying it through the text view's own selection is what every editor follows.
        @discardableResult
        public func startEditing() -> Bool {
            guard let textView = textFieldSharedState.textView, !textView.isFirstResponder else { return false }
            guard textView.becomeFirstResponder() else { return false }
            textView.selectedTextRange = textView.textRange(from: textView.endOfDocument, to: textView.endOfDocument)
            return true
        }


        /// Whether the list of mention suggestions is on screen: a model has arrived and it has something in it.
        ///
        /// Read by the discussion screen to put the suggestions first in what Esc dismisses, before the reply quote and before the caret. "An `@` is under the
        /// caret" would not do, a string with no match drawing nothing, and an Esc that dismissed nothing visible would read as having done nothing.
        public var theMentionSuggestionsAreShowing: Bool {
            !(mentionViewSharedState.streamedModel?.mentions.isEmpty ?? true)
        }


        /// Takes the mention suggestions off the screen and leaves the caret where it is.
        ///
        /// The request left waiting is resumed as well, as it is when the bar goes away. The suggestions follow the mention string the editor reports on a change
        /// of selection, so the next keystroke or click asks again, which is what a reader who went on typing the name would expect.
        public func dismissTheMentionSuggestions() {
            resumeAnyPendingMentionRequest()
            mentionViewSharedState.setCurrentMentionString(nil)
        }


        /// True from the end of a successful send that carried attachments until the draft's attachments next change.
        ///
        /// The send returns before the model saying the draft is empty arrives, so the tiles of what was just sent would otherwise be
        /// drawn again for a few frames between the two. Set in the same turn as the send ends, so there is no frame between them.
        @Published private(set) var theSentAttachmentsAreStillListed = false

        /// Called by the compose view on every change of the draft's attachments.
        func draftAttachmentsDidChange() {
            guard theSentAttachmentsAreStillListed else { return }
            theSentAttachmentsAreStillListed = false
        }


        /// Whether there is nothing to send: no text, and no attachment.
        var isMessageEmpty: Bool {
            isTextEditorEmpty && !draftHasAttachments
        }


        /// Handles the keys the text editors report: the arrows, moving through the mention suggestions. The Return keys come through
        /// ``returnWasPressed(with:)`` instead, from the discussion screens' key commands.
        ///
        /// Lives here, and not on the view, because the handlers of `onKeyPress` outlive the view that installs them: a closure implemented on the view
        /// captured the view itself — hence this state and the actions object — for good. See `ComposeView.keyboardAction`.
        func handleKeyboardAction(action: KeyboardActionType) -> KeyboardResult {
            switch action {

            case .up:
                return suggestPreviousMentionIfAppropriate()

            case .down:
                return suggestNextMentionIfAppropriate()

            }
        }

        
        /// What Return was pressed with. The three combinations a discussion screen vends a `UIKeyCommand` for.
        public enum ReturnKeyModifiers: Sendable, Equatable {
            case none
            case shift
            case command
        }


        /// Whether the text editor of this bar is the first responder.
        ///
        /// A discussion screen takes the Return keys with `UIKeyCommand`s carrying `wantsPriorityOverSystemBehavior`, which take Return from every
        /// text input on the screen, its search field included. The screen refuses them in `canPerformAction` unless this is true. UIKit asks about
        /// eighteen times per press, so this is one read of the text view the editor introspects and nothing more.
        public var isTheEditorTheFirstResponder: Bool {
            textFieldSharedState.textView?.isFirstResponder ?? false
        }


        /// Return was pressed in the editor, with these modifiers: accepts the mention being chosen, sends the draft, or inserts a newline, as the
        /// send preference says.
        ///
        /// Called by the discussion screens from the key commands they vend, which is the only way a hardware Return reaches this bar: SwiftUI's
        /// `onKeyPress` and `keyboardShortcut` never see ↩ or ⇧↩ in a focused `TextEditor`, text input claiming the key first, and a priority
        /// `UIKeyCommand` is what takes it back. The command leaves the text untouched, so the newline is inserted here when the key means one.
        ///
        /// A plain Return accepts the mention being chosen whatever the preference, as it does when typed on screen. Under *Enter sends*, ⇧↩ and ⌘↩
        /// insert a newline; under *⌘↩ sends*, ↩ inserts a newline and ⇧↩ sends as ⌘↩ does. The iPad's on-screen Return produces no command and so
        /// inserts a newline whatever the preference, as the iPhone's does.
        public func returnWasPressed(with modifiers: ReturnKeyModifiers) {

            // The editor is dimmed and the send button disabled while a send or a load is under way; Return does nothing then either.
            guard !isPreventingEdition else { return }

            if modifiers == .none {
                switch acceptCurrentlySelectedMentionIfAppropriate() {
                case .handled:
                    return
                case .ignored:
                    break
                }
            }

            let sends: Bool
            switch (parameters.sendMessageShortcutType, modifiers) {
            case (.enter, .none):
                sends = true
            case (.enter, .shift), (.enter, .command):
                sends = false
            case (.commandEnter, .none):
                sends = false
            case (.commandEnter, .shift), (.commandEnter, .command):
                sends = true
            }

            if sends {
                // The same read the send makes, and not `isMessageEmpty`: that one follows the text a turn late, and a second Return straight after a send
                // arrived in the gap, with the editor already cleared and the flag not yet told.
                let thereIsSomethingToSend = (computeAttributedStringFromCurrentTextInTextEditor()?.characters.isEmpty == false) || draftHasAttachments
                guard thereIsSomethingToSend else { return }
                do { try userWantsToSendDraft(request: .currentDraft) } catch { assertionFailure(error.localizedDescription) }
            } else {
                pasteTextIntoTextEditor(AttributedString("\n"))
            }

        }


        @available(iOS 18.0, *)
        fileprivate func userTypedAdaptiveImageGlyphAttributeInTextEditor(_ glyph: AttributedString.AdaptiveImageGlyph) {
            isLocallyAddingAttachment = true
            Task {
                defer { isLocallyAddingAttachment = false }
                let itemProvider: NSItemProvider
                if AttributedString.AdaptiveImageGlyph.contentType == .heic {
                    guard let pngData: Data = convertHEICToPNG(heicData: glyph.imageContent) else { assertionFailure(); return }
                    itemProvider = NSItemProvider(item: pngData as NSData, typeIdentifier: UTType.png.identifier)
                } else {
                    itemProvider = NSItemProvider(item: glyph.imageContent as NSData, typeIdentifier: AttributedString.AdaptiveImageGlyph.contentType.identifier)
                }
                try await addToDraftAndPasteBackWhateverWasText([itemProvider])
            }
        }
        
        
        fileprivate func userTypedStickerInTextEditor(_ stickerImage: UIImage) {
            isLocallyAddingAttachment = true
            Task {
                defer { isLocallyAddingAttachment = false }
                guard let pngData = stickerImage.pngData() else { assertionFailure(); return }
                let itemProvider = NSItemProvider(item: pngData as NSData, typeIdentifier: UTType.png.identifier)
                try await addToDraftAndPasteBackWhateverWasText([itemProvider])
            }
        }
        
        
        /// Whatever the reader has dropped on this discussion — a file out of Finder, a photograph, a link — on its way to the draft.
        ///
        /// **The fourth way content reaches the bar, and it goes the same way as the other three**: pasted, typed as a Genmoji, sent as a
        /// sticker, and now dropped. What each item *becomes* — an attachment, text in the editor, or both, as a link is — is decided by the
        /// one operation they all end in. See ``addToDraftAndPasteBackWhateverWasText(_:)``.
        ///
        /// `isLocallyAddingAttachment` is what closes the bar to editing while a large file is copied out of another application's storage,
        /// and it is the same flag the other three set. The legacy screen arranges that by hand for its own drop, through
        /// `isDiscussionViewPreventingEdition`.
        ///
        /// **`public`, and not named for the bar**, unlike its `fileprivate` neighbours: a drop is answered wherever the reader lets go, and
        /// there are now two such places. Over the bar it is answered in `ComposeView` in another file — see `TakesWhateverIsDroppedOnTheBar`.
        /// Over the **messages** of the SwiftUI screen it can only be answered on the `List`'s own collection view, which is neither this
        /// module's nor even SwiftUI's to answer for, so it arrives here from the app — see `TakesWhateverIsDroppedOnTheMessages`. Both drops
        /// mean the same thing and must not drift apart, which is what one entry point is for.
        public func itemsWereDropped(_ itemProviders: [NSItemProvider]) {
            guard !itemProviders.isEmpty else { return }
            isLocallyAddingAttachment = true
            Task {
                defer { isLocallyAddingAttachment = false }
                try await addToDraftAndPasteBackWhateverWasText(itemProviders)
            }
        }


        /// Called when the user pastes content into the text editor via UITextPasteDelegate
        /// This method receives the NSItemProvider directly and adds it as an attachment
        fileprivate func userPastedItemProvider(_ itemProvider: NSItemProvider) {
            isLocallyAddingAttachment = true
            Task {
                defer { isLocallyAddingAttachment = false }
                try await addToDraftAndPasteBackWhateverWasText([itemProvider])
            }
        }


        /// Hands item providers over to be added to the draft, and puts back into the editor whatever came back as text.
        ///
        /// **The one place that closes the loop**, so that the three ways content reaches the bar — pasted, typed as a
        /// Genmoji, or a sticker — cannot disagree about what happens to the text half of the answer. What comes back is
        /// usually nothing: most of what is handed over is attached and writes no text. A pasted link is the case that is
        /// not — it is attached as a preview *and* leaves its URL where the reader was typing.
        ///
        /// The legacy screen closes the same loop from the outside, by calling `pasteTextIntoTextEditor` on this bar's
        /// hosting controller once its own delegate has answered. That is what having the answer come back as a value
        /// replaces: a screen that owns this shared state has no controller to be called on.
        private func addToDraftAndPasteBackWhateverWasText(_ itemProviders: [NSItemProvider]) async throws {
            guard let textsToPaste = try await actions?.userWantsToAddAttachmentsToDraft(self, discussionIdentifier: discussionIdentifier, itemProviders: itemProviders) else { return }
            for textToPaste in textsToPaste {
                pasteTextIntoTextEditor(AttributedString(textToPaste.textToPaste))
            }
        }
        
    }
    
}


extension ComposeView.SharedState {

    /// This method is called when the user presses the up/down arrows while mention suggestions are shown. It allows to navigate through them.
    func suggestNextMentionIfAppropriate() -> KeyboardResult {
        self.mentionViewSharedState.suggestNextMentionIfAppropriate()
    }
    
    /// This method is called when the user presses the up/down arrows while mention suggestions are shown. It allows to navigate through them.
    func suggestPreviousMentionIfAppropriate() -> KeyboardResult {
        self.mentionViewSharedState.suggestPreviousMentionIfAppropriate()
    }
    
    func acceptCurrentlySelectedMentionIfAppropriate() -> KeyboardResult {
        self.mentionViewSharedState.acceptCurrentlySelectedMentionIfAppropriate()
    }
    
}


// MARK: - Errors

extension ComposeView.SharedState {
    
    enum ObvError: Error {
        case actionsAreNil
    }
    
}

// MARK: - Sending a draft

extension ComposeView.SharedState {
    
    enum SendRequest {
        case specificAttributedText(attributedText: AttributedString)
        case currentDraft
        case audioMessage
    }
    
    func userWantsToSendDraft(request: SendRequest) throws {
        guard let actions else { assertionFailure(); throw ObvError.actionsAreNil }
        Task {
            // We set isLocallyPreventingEdition from within the task to avoid publishing changes from within view updates
            self.setIsCurrentlySendingMessage(true)
            defer { self.setIsCurrentlySendingMessage(false) }
            do {
                // **The input is emptied before the send, and an attempt to empty it after was withdrawn on 2026-08-27.** What it was for: a send
                // whose save is lost to a merge conflict takes what the reader typed with it, the bar going empty with no message and, in a release
                // build, nothing said. Deferring this call fixed that for nothing — the editor keeps its text in its own `@State`, so *not* clearing
                // it is already the restore, no channel required.
                //
                // **What it broke, and the mistake is worth more than the idea.** The blanking on tapping send really is not this call — two of the
                // three editors swap their binding to `.constant("")` while `isPreventingEdition` holds — but the text is not the only thing reading
                // what this clears. `ComposeView.isMessageEmpty` reads `isTextEditorEmpty`, and it decides **which button is shown** (the waveform
                // against the send arrow) and whether the **emoji shortcut** is there; a voice message's recorder panel goes on
                // `recordingState`, cleared here too. None of those is hidden by a binding swap, so deferring this left the waveform button and the
                // emoji returning when the message existed rather than on the tap. Noticed by a reader within minutes of the build.
                //
                // The lesson is the one this plan keeps re-learning: a list of what a change touches cannot be known to be complete. Three consumers
                // of one cleared property, and the reasoning covered one of them.
                //
                // **What is still owed.** A failed send still empties the bar. The text is not lost — the draft in the store keeps it, the failed
                // save having rolled back the body write too, and `initialBody` seeds the editor from it on next entering the discussion — but the
                // reader is not told and does not see it until then. The proper fix is the restore this shortcut avoided: the clear stream
                // (``getAsyncStreamOfClearInputRequests()``, an `AsyncStream<Void>`) generalised to carry *what the editor should show*, `nil`
                // meaning empty, which is one channel rather than a parallel path — and it must restore `currentMentionsInTextEditor` as well, whose
                // `Range<String.Index>` keys index a string it would have to rebuild. Made much rarer meanwhile by the send being retried when its
                // save is lost, see `PersistedDiscussionsUpdatesCoordinator.createsTheMessageFromTheDraft(draftObjectID:textBody:)`.
                switch request {
                case .audioMessage:
                    self.clearInput()
                    try await actions.userWantsToSendDraft(self, discussionIdentifier: discussionIdentifier, attributedText: "")
                case .specificAttributedText(let attributedText):
                    self.clearInput()
                    try await actions.userWantsToSendDraft(self, discussionIdentifier: discussionIdentifier, attributedText: attributedText)
                case .currentDraft:
                    let attributedText = self.computeAttributedStringFromCurrentTextInTextEditor() ?? AttributedString()
                    guard !attributedText.characters.isEmpty || draftHasAttachments else { return }
                    self.clearInput()
                    try await actions.userWantsToSendDraft(self, discussionIdentifier: discussionIdentifier, attributedText: attributedText)
                }
                // Before the `defer` above ends the send, in the same turn. `draftHasAttachments` is false when the model saying the draft is
                // empty has already arrived, and there is then nothing left to hide.
                if draftHasAttachments {
                    theSentAttachmentsAreStillListed = true
                }
            } catch {
                // Reported as well as asserted, an `assertionFailure` saying nothing in the build this matters in. Kept from the withdrawn attempt:
                // it is the half of *silently* that does not depend on when the input is emptied.
                Self.logger.fault("The draft could not be sent, and the composition bar has already been emptied: \(error.localizedDescription)")
                assertionFailure(error.localizedDescription)
            }
        }
    }

    
    /// Called by the compose view when the user requests the sending of the current draft (e.g., by tapping the "send" button).
    private func computeAttributedStringFromCurrentTextInTextEditor() -> AttributedString? {
        return self.textFieldSharedState.computeAttributedStringFromCurrentTextInTextEditor()
    }

    private func clearInput() {
        self.recordingState = .notRecording
        self.textFieldSharedState.clearInput()
        self.mentionViewSharedState.clearInput()
    }

}


extension ComposeView.SharedState: @MainActor ObvAudioRecorderDelegate {
    
    public func recordingHasFailed() {
        self.recordingState = .notRecording
    }
    
    
    func startRecording() {
        let containerURLforTempFiles = self.containerURLforTempFiles
        ObvAudioRecorder.shared.delegate = self
        
        guard let fileExtention = UTType.m4a.preferredFilenameExtension else { assertionFailure(); return }
        let name = "Recording @ \(self.dateFormatter.string(from: Date()))"
        let tempFileName = [name, fileExtention].joined(separator: ".")
        let url = containerURLforTempFiles.appendingPathComponent(tempFileName)
        
        let settings: [String: Int] = [
            AVFormatIDKey as String: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey as String: 44_100,
            AVEncoderBitRateKey as String: 48_000,
            AVNumberOfChannelsKey as String: 1,
            AVEncoderAudioQualityKey as String: Int(AVAudioQuality.high.rawValue)
        ]

        print("[debug] start recording at \(url)")
        ObvAudioRecorder.shared.startRecording(url: url, settings: settings) { result in
            switch result {
            case .success:
                Self.logger.info("🎤 Start Recording")
                return
            case .failure(let error):
                switch error {
                case .recordingInProgress:
                    assertionFailure()
                    self.recordingState = .notRecording
                case .noRecordPermission:()
                    self.showNoRecordPermissionAlert = true
                    self.recordingState = .notRecording
                case .audioSessionError(let error):
                    Self.logger.fault("🎤 Failed to record: audio session error \(error.localizedDescription, privacy: .public)")
                    assertionFailure()
                    self.recordingState = .notRecording
                case .audioRecorderError(let error):
                    Self.logger.fault("🎤 Failed to record: audio recorder error \(error.localizedDescription, privacy: .public)")
                    assertionFailure()
                    self.recordingState = .notRecording
                }
                return
            }
        }
    }
    
    func stopRecording() -> URL? {
        guard ObvAudioRecorder.shared.isRecording else { return nil }
        
        
        let url: URL
        do {
            url = try ObvAudioRecorder.shared.stopRecording()
            
            return url
        } catch {
            Self.logger.fault("🎤 Failed to record: \(error.localizedDescription, privacy: .public)")
            
            ObvAudioRecorder.shared.cancelRecording()
            recordingState = .notRecording
            return nil
        }
        
    }
}

// MARK: - Handling the communication between the text field and the mentions view

extension ComposeView.SharedState {
    
    fileprivate func userTypedMentionStringInTextEditor(_ newMentionString: String?) async -> ComposeTextField.SharedState.UserDecisionOnNewMentionString {
        return await withCheckedContinuation { (continuation: CheckedContinuation<ComposeTextField.SharedState.UserDecisionOnNewMentionString, Never>) in
            continuationForMentions?.resume(returning: .doNothing)
            continuationForMentions = continuation
            self.mentionViewSharedState.setCurrentMentionString(newMentionString)
        }
    }

    /// Called when the user selects a mention in the mentions view
    fileprivate func onMentionSelectedByUser(_ mention: ComposeMentionSuggestionModel) {
        guard let continuationForMentions else { assertionFailure(); return }
        continuationForMentions.resume(returning: .insertMention(mention))
        self.continuationForMentions = nil
    }


    /// Resumes the mention request left waiting, if any, and must be called when the composition view goes away.
    ///
    /// ``userTypedMentionStringInTextEditor(_:)`` is called by the text editors on *every* change of the text selection — every caret move — and each call
    /// resumes the previous continuation and stores a new one. So one is always left suspended, and a suspended `async` method keeps its `self` alive: this
    /// state, and with it both child shared states. Nothing resumed that last one, which is why no `ComposeView.SharedState` was ever deallocated on either
    /// discussion screen. In a memory graph it shows up as a "closure context (unknown layout)" holding the state.
    func resumeAnyPendingMentionRequest() {
        guard let continuationForMentions else { return }
        self.continuationForMentions = nil
        continuationForMentions.resume(returning: .doNothing)
    }
    
}


extension ComposeTextField {
    
    @MainActor
    final class SharedState: ObservableObject {

        fileprivate weak var globalSharedState: ComposeView.SharedState?

        let discussionIdentifier: ObvDiscussionIdentifier
        private let initialBody: AttributedString? // Value of the body when entering the discussion
        @Published fileprivate(set) var isPreventingEdition: Bool = false
        
        /// Observe changes to the global autocorrection setting
        @Published var autocorrection: ObvTextAutocorrectionType = ObvMessengerSettings.Discussions.autocorrectionType
        
        /// Allows to observe changes made to settings
        private var cancellables = Set<AnyCancellable>()
        
        init(discussionIdentifier: ObvDiscussionIdentifier,
             initialBody: AttributedString?,
             initialSendMessageShortcutType: ComposeViewParameters.SendMessageShortcutType) {
            self.discussionIdentifier = discussionIdentifier
            self.initialBody = initialBody
            self.sendMessageShortcutType = initialSendMessageShortcutType
            // A draft carried over from a previous visit is text in the editor from the very first frame: the send button must be shown right away, and
            // sending without touching the text must send that draft and not nothing. The notifying `onTextChangeInTextEditor` cannot be used here, as it
            // requires a `globalSharedState` that is only wired after this init returns.
            if let initialBody {
                let trimmed = initialBody.trimmingWhitespacesAndNewlines()
                self.currentTextInTextEditor = trimmed.characters.isEmpty ? nil : .attributedString(trimmed)
            }

            // Observe changes to the global autocorrection setting
            ObvMessengerSettingsObservableObject.shared.$autocorrectionType
                .receive(on: DispatchQueue.main)
                .sink { [weak self] newValue in
                    self?.autocorrection = newValue
                }
                .store(in: &cancellables)
        }

        private var currentTextInTextEditor: StringOrAttributedString? = nil
        private var currentMentionsInTextEditor = [Range<String.Index> : (mentionedCryptoId: ObvCryptoId, title: String)]() // Only used when the TextEditor does not support AttributedString (like on iOS 18)
        fileprivate(set) var sendMessageShortcutType: ComposeViewParameters.SendMessageShortcutType
        
        fileprivate func onNewSendMessageShortcutType(_ newSendMessageShortcutType: ComposeViewParameters.SendMessageShortcutType) {
            guard self.sendMessageShortcutType != newSendMessageShortcutType else { return }
            self.sendMessageShortcutType = newSendMessageShortcutType
        }
        
        /// The `UITextView` behind the editor, set by `ComposeTextField` each time it introspects it, and read to answer whether the editor is the
        /// first responder. Weak: the text view is SwiftUI's, and this state outlives any one of them.
        weak var textView: UITextView?

        enum UserDecisionOnNewMentionString {
            case doNothing
            case insertMention(ComposeMentionSuggestionModel)
        }
        
        /// Called by the text editor whenever it detects that the user input a new mention string (like "@alice") to look for.
        func userTypedMentionStringInTextEditor(_ newMentionString: String?) async -> UserDecisionOnNewMentionString {
            guard let globalSharedState else { assertionFailure(); return .doNothing }
            return await globalSharedState.userTypedMentionStringInTextEditor(newMentionString)
        }

        
        @available(iOS 18.0, *)
        func userTypedAdaptiveImageGlyphAttributeInTextEditor(_ glyph: AttributedString.AdaptiveImageGlyph) {
            globalSharedState?.userTypedAdaptiveImageGlyphAttributeInTextEditor(glyph)
        }
        
        func userTypedStickerInTextEditor(_ stickerImage: UIImage) {
            globalSharedState?.userTypedStickerInTextEditor(stickerImage)
        }
        
        /// Called when the user pastes content into the text editor
        func userPastedItemProvider(_ itemProvider: NSItemProvider) {
            globalSharedState?.userPastedItemProvider(itemProvider)
        }
        
        func onTextChangeInTextEditor(_ newText: StringOrAttributedString) {
            
            // Kept as typed, for an editor built again; what follows keeps a trimmed copy, for a send.

            self.latestTextInTextEditor = newText

            // Store the current text in the text editor
            
            switch newText {
            case .string(let string):
                if let trimmed = string.trimmingWhitespacesAndNewlines().mapToNilIfZeroLength() {
                    self.currentTextInTextEditor = .string(trimmed)
                } else {
                    self.currentTextInTextEditor = nil
                }
            case .attributedString(let attributedString):
                let trimmed = attributedString.trimmingWhitespacesAndNewlines()
                if !trimmed.characters.isEmpty {
                    self.currentTextInTextEditor = .attributedString(trimmed)
                } else {
                    self.currentTextInTextEditor = nil
                }
            }
            
            // If the text in the text editor is nil, there cannot be any mention in it
            
            if self.currentTextInTextEditor == nil {
                currentMentionsInTextEditor.removeAll()
            }
            
            // Allow other parts of the ComposeView to react to the change
            
            guard let globalSharedState else { assertionFailure(); return }
            
            globalSharedState.onTextChangeInTextEditor(self.computeAttributedStringFromCurrentTextInTextEditor())
            
        }
     
        
        func onNewInsertedMentionInTheTextEditor(mentionRangeInCurrentText: Range<String.Index>, mention: (mentionedCryptoId: ObvCryptoId, title: String)) {
            // When a new mention is inserted in the TextEditor, we remove any previous overlapping mention
            self.currentMentionsInTextEditor =  self.currentMentionsInTextEditor.filter { range, _ in !range.overlaps(mentionRangeInCurrentText) }
            self.currentMentionsInTextEditor[mentionRangeInCurrentText] = mention
        }
        
        
        fileprivate func clearInput() {
            self.latestTextInTextEditor = nil
            self.currentTextInTextEditor = nil
            self.currentMentionsInTextEditor.removeAll()
            guard let continuationOnClearInput else { assertionFailure(); return }
            continuationOnClearInput.yield()
        }
        
        private var continuationOnClearInput: AsyncStream<Void>.Continuation?
        
        func getAsyncStreamOfClearInputRequests() -> AsyncStream<Void> {
            return AsyncStream<Void> { (continuation: AsyncStream<Void>.Continuation) in
                continuationOnClearInput?.finish()
                continuationOnClearInput = continuation
            }
        }
        
        fileprivate func computeAttributedStringFromCurrentTextInTextEditor() -> AttributedString? {
            guard let currentTextInTextEditor else { return nil }
            switch currentTextInTextEditor {
            case .attributedString(let attributedString):
                return attributedString
            case .string(let string):
                var attributedText = AttributedString(string)
                for (rangeInString, mention) in currentMentionsInTextEditor {
                    guard let rangeInAttributedString = Range(rangeInString, in: attributedText) else { continue }
                    guard "@" + mention.title == String(attributedText[rangeInAttributedString].characters) else { continue }
                    attributedText[rangeInAttributedString].mention = .init(cryptoId: mention.mentionedCryptoId)
                }
                return attributedText
            }
        }
        
        /// What the editor last reported, exactly as typed, or nil once the input has been cleared. See ``initialBodyForTextEditor``.
        private var latestTextInTextEditor: StringOrAttributedString?

        /// What the text editor seeds itself with: the latest text it reported, or, before it has reported any, the body the discussion was entered with.
        ///
        /// Reading this is deliberately non-destructive, so that it can be read from the `init` of a text editor: the editor is then laid out with its
        /// text from the very first pass, instead of measuring itself empty and being filled afterwards. `@State` uses the value once per installation of
        /// the state, and **an editor is installed more than once in the life of this object**: a search replaces the composition bar for as long as it
        /// lasts, so SwiftUI discards the editor's state and builds the editor again when the bar returns. Seeded from the body the discussion was entered
        /// with, as this used to be, the editor came back without what had been typed since — the draft in the store had it, and nothing on screen did.
        var initialBodyForTextEditor: AttributedString? {
            switch latestTextInTextEditor {
            case .none:
                return initialBody
            case .string(let string):
                return AttributedString(string)
            case .attributedString(let attributedString):
                return attributedString
            }
        }
        
        @Published private(set) var attributedTextToPaste: AttributedString? = nil
        @Published private(set) var textToPaste: String? = nil
        
        /// Pastes provided text into the editor (e.g., the URL string after adding its preview as an attachment).
        ///
        /// This is used, e.g., when the user pastes an URL using the paste button of the compose view. In that case, the compose
        /// view requests to add attachments to the draft. An URL preview is added as an attachment, and the URL (as a String) is reported back
        /// here, so as to paste it in the `TextEditor`.
        fileprivate func pasteTextIntoTextEditor(_ newTextToPaste: AttributedString) {
            assert(attributedTextToPaste == nil)
            assert(textToPaste == nil)
            attributedTextToPaste = newTextToPaste
            textToPaste = String(newTextToPaste.characters[...])
        }
        
        func resetTextToPasteIntoTextEditor() {
            attributedTextToPaste = nil
            textToPaste = nil
        }
        
    }
    
}


// MARK: - Shared state for the ComposeMentionsView

extension ComposeMentionsView {
    
    @MainActor
    final class SharedState: ObservableObject {
        
        /// Expected to be set from the `ComposeMentionView`, while listening to the stream of its datasource.
        @Published private(set) var streamedModel: ComposeSuggestionsModel?
        @Published var currentStreamUUID: UUID?
        
        func setStreamedModel(to newStreamedModel: ComposeSuggestionsModel) {
            guard self.streamedModel != newStreamedModel else { return }
            if newStreamedModel.mentions.count > 0 {
                self.suggestionSelectedIndex = self.suggestionSelectedIndex % newStreamedModel.mentions.count
            } else {
                self.suggestionSelectedIndex = 0
            }
            self.streamedModel = newStreamedModel
        }
        
        @Published private(set) var suggestionSelectedIndex: Int = 0
        
        fileprivate weak var globalSharedState: ComposeView.SharedState?
        
        let discussionIdentifier: ObvDiscussionIdentifier
        
        init(discussionIdentifier: ObvDiscussionIdentifier) {
            self.discussionIdentifier = discussionIdentifier
        }
        
        @Published private(set) var currentMentionString: String?
        
        fileprivate func setCurrentMentionString(_ currentMentionString: String?) {
            self.currentMentionString = currentMentionString
        }
        
        func onMentionSelectedByUser(_ mention: ComposeMentionSuggestionModel) {
            globalSharedState?.onMentionSelectedByUser(mention)
        }
        
        fileprivate func suggestNextMentionIfAppropriate() -> KeyboardResult {
            guard let streamedModel else { assertionFailure(); return .ignored }
            guard streamedModel.mentions.count > 0 else { self.suggestionSelectedIndex = 0; return .ignored }
            // Avoid publishing changes from within view updates
            Task { self.suggestionSelectedIndex = (self.suggestionSelectedIndex + 1) % streamedModel.mentions.count }
            return .handled
        }
        
        fileprivate func suggestPreviousMentionIfAppropriate() -> KeyboardResult {
            guard let streamedModel else { assertionFailure(); return .ignored }
            guard streamedModel.mentions.count > 0 else { self.suggestionSelectedIndex = 0; return .ignored }
            // Avoid publishing changes from within view updates
            Task { self.suggestionSelectedIndex = (self.suggestionSelectedIndex - 1 + streamedModel.mentions.count) % streamedModel.mentions.count } // Note that adding streamedModel.mentions.count allows to have a positive value
            return .handled
        }
        
        fileprivate func acceptCurrentlySelectedMentionIfAppropriate() -> KeyboardResult {
            guard let streamedModel else { assertionFailure(); return .ignored }
            guard streamedModel.mentions.count > 0 else { self.suggestionSelectedIndex = 0; return .ignored }
            guard self.suggestionSelectedIndex >= 0 && self.suggestionSelectedIndex < streamedModel.mentions.count else { self.suggestionSelectedIndex = 0; return .ignored }
            let mention = streamedModel.mentions[self.suggestionSelectedIndex]
            self.onMentionSelectedByUser(mention)
            return .handled
        }
        
        fileprivate func clearInput() {
            self.suggestionSelectedIndex = 0
        }
        
    }
    
}


// MARK: - Private helpers

private func convertHEICToPNG(heicData: Data) -> Data? {
    
    guard let imageSource = CGImageSourceCreateWithData(heicData as CFData, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        return nil
    }
    
    let pngData = NSMutableData()
    guard let imageDestination = CGImageDestinationCreateWithData(
        pngData as CFMutableData,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        return nil
    }
    
    CGImageDestinationAddImage(imageDestination, cgImage, nil)
    
    guard CGImageDestinationFinalize(imageDestination) else {
        return nil
    }
    
    return pngData as Data
    
}
