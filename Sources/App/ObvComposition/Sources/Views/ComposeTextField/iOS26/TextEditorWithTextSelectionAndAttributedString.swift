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

import SwiftUI
import ObvSettings
import OSLog
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

// MARK: - TextEditorWithTextSelectionAndAttributedString on iOS 26

@available(iOS 26.0, *)
struct TextEditorWithTextSelectionAndAttributedString: View {
    
    @ObservedObject var sharedState: ComposeTextField.SharedState
    private let keyboardAction: (KeyboardActionType) -> KeyboardResult

    @State private var text: AttributedString
    @State private var selection = AttributedTextSelection()

    init(sharedState: ComposeTextField.SharedState,
         keyboardAction: @escaping (KeyboardActionType) -> KeyboardResult) {
        self.sharedState = sharedState
        self.keyboardAction = keyboardAction
        // Seeding the text here, rather than from `.onAppear`, is what makes this editor measure itself *with* its text on the very first layout pass.
        // Filled afterwards, it was laid out empty first, and showed a phantom empty line — and, on a SwiftUI host, the change of height reached the
        // screen as an unwanted animation while the discussion was being pushed. `ComposeViewHostingController` hides both, as its
        // `viewDidLayoutSubviews` invalidates the intrinsic content size on every pass; a SwiftUI host gives no such nudge.
        //
        // Reading the initial body is a pure read, so constructing this view without ever installing its state loses nothing, and `@State` guarantees the
        // seed is used once and never clobbers what the user has typed since.
        _text = State(initialValue: sharedState.initialBodyForTextEditor ?? "")
    }
    

    /// This method is called whenever the text changes. The new text is sent to the shared state, allowing for other
    /// views to be updated accordingly (e.g., for the send button to appear).
    private func shareTextWithSharedState(_ oldValue: AttributedString, _ newValue: AttributedString) {
        
        // Prevent processing stale "newValue" data: if self.text changed between the onChange trigger
        // and now, exit early. The new self.text value will trigger another onChange call.
        guard self.text == newValue else { return }

        self.sharedState.onTextChangeInTextEditor(.attributedString(newValue))
        
    }

    
    /// This method is called whenever the text changes. It ensures atomic removal of entire mentions.
    ///
    /// If a partial mention is deleted (e.g., a single character at the end of a mention),
    /// it removes the **entire mention**.
    ///
    /// - **Assumption**:
    ///   Relies on `onChangeOfAttributedTextSelection(...)` to pre-filter cases,
    ///   so only single-character deletions at mention end are handled here.
    private func preventPartialMentionDeletionOnChangeOfText(_ oldValue: AttributedString, _ newValue: AttributedString) {
        
        // Prevent processing stale "newValue" data: if self.text changed between the onChange trigger
        // and now, exit early. The new self.text value will trigger another onChange call.
        guard self.text == newValue else { return }
        
        if let (fixedText, fixedInsertionIndex) = newValue.fixingPartialMentionDeletionCompared(to: oldValue) {
            self.text = fixedText
            self.selection = .init(insertionPoint: fixedInsertionIndex)
        }
    }

    
    /// The user might insert memojis in the `TextEditor`. When this happens, we removes the inserted memoji from the text, and
    /// request the insertion of a png representation of this memoji as an attachment.
    private func filterOutAdaptiveImageGlyph(_ oldValue: AttributedString, _ newValue: AttributedString) {
        
        // Prevent processing stale "newValue" data: if self.text changed between the onChange trigger
        // and now, exit early. The new self.text value will trigger another onChange call.
        guard self.text == newValue else { return }

        guard !oldValue.hasAdaptiveImageGlyphRuns && newValue.hasAdaptiveImageGlyphRuns else { return }
        
        for (glyph, range) in newValue.runs[\.adaptiveImageGlyph].reversed() {
            guard let glyph else { continue }
            sharedState.userTypedAdaptiveImageGlyphAttributeInTextEditor(glyph)
            var rangeOfGlyph = range
            self.text.transform(updating: &rangeOfGlyph) { textToTransform in
                textToTransform.replaceSubrange(range, with: AttributedString())
            }
            self.selection = .init(insertionPoint: rangeOfGlyph.upperBound)

        }
    }
    
    
    /// The user might insert stickers in the `TextEditor`. When this happens, we removes the inserted sticker from the text, and
    /// request the insertion of a png representation of this sticker as an attachment.
    private func filterOutStickers(_ oldValue: AttributedString, _ newValue: AttributedString) {
        #if canImport(UIKit)
        
        // Prevent processing stale "newValue" data: if self.text changed between the onChange trigger
        // and now, exit early. The new self.text value will trigger another onChange call.
        guard self.text == newValue else { return }

        guard !oldValue.hasTextAttachmentsRuns && newValue.hasTextAttachmentsRuns else { return }
        for (value, range) in newValue.runs[\.attachment].reversed() {
            guard let stickerImage = value?.image else { continue }
            sharedState.userTypedStickerInTextEditor(stickerImage)
            var rangeOfSticker = range
            self.text.transform(updating: &rangeOfSticker) { textToTransform in
                textToTransform.replaceSubrange(range, with: AttributedString())
            }
            self.selection = .init(insertionPoint: rangeOfSticker.upperBound)
        }
        #endif
    }
    
    
    /// This method is called whenever the text selection changes. It handles the mention insertion process from end-to-end.
    /// Eventually, it also adjusts the text selection to ensure that mentions are always fully selected, whether the user moves the cursor or selects a range of text.
    ///
    /// If the new text selection is an insertion point, this method search for the last mention before it, and transmit it to the shared state.
    /// Eventually, this will give a chance to the mention view to show new mention suggestions and, for user, to choose one. In return,
    /// we (very asynchronouly) receive the user decision. When they choose a mention in the list, this method replaces the "mention string"
    /// (typed by the user) by the full mention title.
    private func onSelectionChange(_ oldValue: AttributedTextSelection, _ newValue: AttributedTextSelection) {
        
        // At the end, always adjust the text selection to ensure that mentions are always fully selected
        defer {
            self.selection = self.text.adjustSelectionForMentions(self.selection)
        }
        
        // The rest of this method deals with mention insertion
        
        guard let index = newValue.indexOfInsertionPoint(in: self.text) else { return }
        guard index <= self.text.endIndex else { return }
        
        // Search for the last mention string before the current insertion point.
        // Note that, most of the time, the returned mentionString is nil
        
        let mentionString = self.text.lastMentionString(before: index)
        
        // Whatever the mentionString value (nil or not), send this value to the shared state.
        // In return, we will eventually receive the user decision about what we should do:
        // - do nothing
        // - insert a new mention in the text, in which case we replace the mention string by the full mention title.
        
        let selectionOnMentionRequest = self.selection
        let textOnMentionRequest = self.text
        Task {

            // We ensure that the current state (e.g., self.text) is coherent with the state at the moment
            // the request was made. We also do this once the userTypedMentionStringInTextEditor call returns
            // as this method is highly asynchronous (it awaits the user choice of the mention in the mention view).
            
            guard (textOnMentionRequest, selectionOnMentionRequest.indexOfInsertionPoint(in: self.text)) == (self.text, self.selection.indexOfInsertionPoint(in: self.text)) else { return }
            let userDecision = await sharedState.userTypedMentionStringInTextEditor(mentionString)
            guard (textOnMentionRequest, selectionOnMentionRequest.indexOfInsertionPoint(in: self.text)) == (self.text, self.selection.indexOfInsertionPoint(in: self.text)) else { return }

            // If we reach this point, we have to process the user decision. In case they decide to insert a mention
            // we make a few sanity check and replace the "mention string" type by user (to search for the appropriate
            // mention) by the full "title" of the chosen mention. We also store the range and mention for later.
            // This may allow, when sending the message, to construct an AttributedString with appropriate mention
            // attributes. This is required as the native SwiftUI TextEditor does not support AttributedString under
            // iOS 18.
            
            switch userDecision {
                
            case .doNothing:
                return
                
            case .insertMention(let composeMentionSuggestionModel):
                                
                guard let index = selection.indexOfInsertionPoint(in: self.text) else { return }
                guard self.text.startIndex < index, index <= self.text.endIndex else { assertionFailure(); return }
                guard let rangeOfMentionString = self.text.rangeOfLastMentionString(before: index) else { return }
                
                let mentionTitle = composeMentionSuggestionModel.title.trimmingWhitespacesAndNewlines()
                guard !mentionTitle.isEmpty else { return }
                var stringToInsert = AttributedString("@" + mentionTitle)
                stringToInsert.mention = .init(cryptoId: composeMentionSuggestionModel.mentionedCryptoId)

                // We replace the mentionString (which range is rangeOfMentionString) by the title of the
                // mention. We use a technique shown in https://developer.apple.com/videos/play/wwdc2025/280?time=1184
                // to obtain the range of the full mention after the replacement. The range will be stored in rangeOfMention
                
                var rangeOfMention = rangeOfMentionString
                self.text.transform(updating: &rangeOfMention) { textToTransform in
                    textToTransform.replaceSubrange(rangeOfMentionString, with: stringToInsert)
                }
                
                // Now rangeOfMention is the range of the full mention. We place the selection (insertion point) at the end of it.
                
                self.selection = .init(insertionPoint: rangeOfMention.upperBound)
                                                
                // Add a space after the current insertion point if appropriate

                if let indexOfInsertionPoint = self.selection.indexOfInsertionPoint(in: self.text) {
                    let isSpaceAdded = self.text.insertSpaceIfNeeded(at: indexOfInsertionPoint)
                    if isSpaceAdded {
                        self.selection = .init(insertionPoint: self.text.index(afterCharacter: indexOfInsertionPoint))
                    }
                }
                
            }
        }
        
    }

    
    /// Start listening to a stream of events indicating that this view should reset all its internal states.
    /// This happens when the user sends the message by interacting with another view of the composition view
    /// (typically, by tapping the send button).
    private func onTaskForClearingInput() async {
        let stream = sharedState.getAsyncStreamOfClearInputRequests()
        for await _ in stream {
            self.selection = .init(insertionPoint: self.text.startIndex)
            self.text = ""
            self.selection = .init(insertionPoint: self.text.startIndex)
        }
    }

    

    /// Works around a SwiftUI limitation on iOS 26 / Mac Catalyst: when the user copies (Cmd+C) from the
    /// attributed-string `TextEditor`, SwiftUI writes only its private `com.apple.SwiftUI.AttributedString`
    /// pasteboard flavor and omits `public.utf8-plain-text`. As a result, pasting into any non-SwiftUI app
    /// (TextEdit, Terminal, browsers, …) produces nothing.
    ///
    /// While this editor is focused, we observe pasteboard changes and, whenever an item carries the SwiftUI
    /// flavor but no plain-text flavor, we add a plain-text representation derived from the current selection
    /// (mentions render as their `@Title`). The original SwiftUI flavor is preserved, so pasting back into a
    /// SwiftUI text field keeps round-tripping. The added plain text makes the second pass a no-op, so there
    /// is no notification feedback loop.
    private func addPlainTextFlavorToCopiesIfNeeded() async {
        #if canImport(UIKit)
        let pasteboard = UIPasteboard.general
        let swiftUITypeIdentifier = "com.apple.SwiftUI.AttributedString"
        let plainTextTypeIdentifier = UTType.utf8PlainText.identifier

        for await _ in NotificationCenter.default.notifications(named: UIPasteboard.changedNotification) {

            // Only fix copies that originate from this (focused) compose field, so we never overwrite a copy
            // made elsewhere in the app with our selection's text.
            guard isFocused else { continue }

            // Non-prompting presence checks (these never trigger the iOS "Allow Paste?" authorization,
            // unlike reading item content): only proceed when the pasteboard carries our private SwiftUI
            // flavor and is missing plain text. This avoids reading foreign item content, and short-circuits
            // unrelated changes as well as our own second pass (after we have added plain text).
            guard pasteboard.contains(pasteboardTypes: [swiftUITypeIdentifier]),
                  !pasteboard.contains(pasteboardTypes: [plainTextTypeIdentifier]) else { continue }

            // Recover the plain text that was copied, from the current selection (unchanged by a copy).
            let plainText: String
            switch self.selection.indices(in: self.text) {
            case .insertionPoint:
                continue // nothing selected, so nothing was copied from here
            case .ranges(let rangeSet):
                plainText = rangeSet.ranges.map { String(self.text[$0].characters) }.joined()
            }
            guard !plainText.isEmpty else { continue }

            // Add a plain-text representation to every item that has the SwiftUI flavor but lacks plain text.
            var items = pasteboard.items
            var didAddPlainText = false
            for index in items.indices where items[index][swiftUITypeIdentifier] != nil && items[index][plainTextTypeIdentifier] == nil {
                items[index][plainTextTypeIdentifier] = Data(plainText.utf8)
                didAddPlainText = true
            }
            guard didAddPlainText else { continue }
            pasteboard.items = items
        }
        #endif
    }
    
    @FocusState private var isFocused: Bool
    
    /// Called when the focus of the `TextEditor` changes. When it gains focus (i.e., when
    /// the user taps on it to start editing text, we move the cursort (i.e., selection) to the end
    /// of the text. We do it only on iOS and iPadOS, we it is much harder to get the initial cursor
    /// position right for the user.
    private func onFocusChange(_ oldValue: Bool, newValue: Bool) {
        #if !targetEnvironment(macCatalyst)
        guard !oldValue && newValue else { return }
        self.selection = .init(insertionPoint: self.text.endIndex)
        #endif
    }
    
    
    /// Called each time the shared state's `attributedTextToPaste` is updated.
    ///
    /// This is used, e.g., when the user pastes an URL using the paste button of the compose view. In that case, the compose
    /// view requests to add attachments to the draft. An URL preview is added as an attachment, and the URL (as a String) is reported back
    /// here.
    private func onChangeOfTextToPaste(_ oldValue: AttributedString?, _ newValue: AttributedString?) {
        
        // Eventually, we want the string to paste of the shared state to be reset
        
        defer { sharedState.resetTextToPasteIntoTextEditor() }
        
        // Ensure there is a string to paste
        
        guard let newValue, !newValue.characters.isEmpty else { return }
        
        switch self.selection.indices(in: self.text) {
            
        case .insertionPoint(let indexOfInsertionPoint):
            
            // We paste the string at the insertion point and put the insertion point at the end of the pasted string
            
            self.text.insert(newValue, at: indexOfInsertionPoint)
            let newInsertionPoint = self.text.index(indexOfInsertionPoint, offsetByCharacters: newValue.characters.count)
            self.selection = .init(insertionPoint: newInsertionPoint)
            
        case .ranges(let rangeSet):
            
            if let firstRange = rangeSet.ranges.first {
                
                // We replace the current selection with the string to paste and update the selection.
                // We use a technique shown in https://developer.apple.com/videos/play/wwdc2025/280?time=1184
                
                var rangeToUpdate = firstRange
                self.text.transform(updating: &rangeToUpdate) { textToTransform in
                    textToTransform.replaceSubrange(firstRange, with: newValue)
                }
                self.selection = .init(range: rangeToUpdate)
                
            } else {

                // Fallback: paste the string at the end
                
                self.text.append(newValue)
                self.selection = .init(insertionPoint: self.text.endIndex)
                
            }
        }
    }
    
    
    public var body: some View {
        TextEditor(text: sharedState.isPreventingEdition ? .constant("") : $text, selection: $selection)
            .autocorrectionObv(autocorrection: sharedState.autocorrection, spellChecking: .yes)
            .textInputFormattingControlVisibility(.hidden, for: .all)
            .attributedTextFormattingDefinition(ComposeMentionTextFormattingDefinition())
            .textEditorStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: text, preventPartialMentionDeletionOnChangeOfText)
            .onChange(of: text, shareTextWithSharedState)
            .onChange(of: text, filterOutAdaptiveImageGlyph)
            .onChange(of: text, filterOutStickers)
            .onChange(of: selection, onSelectionChange)
            .onChange(of: sharedState.attributedTextToPaste, onChangeOfTextToPaste)
            .task(onTaskForClearingInput)
            .task(addPlainTextFlavorToCopiesIfNeeded)
            // Captured *by value*, see the same two lines in `TextEditorWithTextSelection`.
            .onKeyPress(.downArrow) { [keyboardAction] in keyboardAction(.down).toKeyPress }
            .onKeyPress(.upArrow) { [keyboardAction] in keyboardAction(.up).toKeyPress }
            .frame(minHeight: ComposeTextField.LineLimit.defaultLineHeight, maxHeight: ComposeTextField.LineLimit.toMaxHeight)
            .focused($isFocused)
            .onChange(of: isFocused, onFocusChange)
            .overlay(alignment: .leading, content: { overlay })
    }
    
    
    @ViewBuilder
    private var overlay: some View {
        Text(verbatim: "Aa")
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
            .isHidden(self.isFocused || !self.text.characters.isEmpty)
    }
    
}


@available(iOS 18.0, *)
private extension AttributedString {

    var hasAdaptiveImageGlyphRuns: Bool {
        !self.runs[\.adaptiveImageGlyph].filter({ $0.0 != nil }).isEmpty
    }

    var hasTextAttachmentsRuns: Bool {
        !self.runs[\.attachment].filter({ $0.0 != nil }).isEmpty
    }

}
