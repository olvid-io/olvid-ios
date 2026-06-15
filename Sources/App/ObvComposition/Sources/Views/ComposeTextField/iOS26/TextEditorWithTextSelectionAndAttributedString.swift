/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
#if canImport(UIKit)
import UIKit
#endif

// MARK: - TextEditorWithTextSelectionAndAttributedString on iOS 26

@available(iOS 26.0, *)
struct TextEditorWithTextSelectionAndAttributedString: View {
    
    @ObservedObject var sharedState: ComposeTextField.SharedState
    private let keyboardAction: (KeyboardActionType) -> KeyboardResult

    @State private var text: AttributedString = ""
    @State private var selection = AttributedTextSelection()

    @State private var discardNextNewLine = true

    init(sharedState: ComposeTextField.SharedState,
         keyboardAction: @escaping (KeyboardActionType) -> KeyboardResult) {
        self.sharedState = sharedState
        self.keyboardAction = keyboardAction
    }
    

    /// On Catalyst and iPad, removes newline insertions (when appropriate) and handles Enter/Command+Enter actions.
    ///
    /// This method is invoked from `onChange(of: text)` and compares the previous and new
    /// attributed text values. It detects whether the only change is exactly one newline
    /// character insertion and, if so, decides whether to keep or discard that newline and
    /// whether to trigger an action (send message or insert mention) based on the user's preference
    /// for the send shortcut.
    ///
    /// Behavior by preference:
    /// - If the user chose "Enter" as a keyboard shortcut to send messages:
    ///   - If the newline was inserted by the user typing Enter, we discard it and call
    ///     `keyboardAction(.enter)`. If the newline was inserted
    ///     programmatically by `insertNewLineOnCmdEnterOnCatalystIfAppropriate(_:)`, we keep it
    ///     and reset `discardNextNewLine` to `true`.
    /// - If the user chose "Cmd+Enter" as a keyboard shortcut to send messages:
    ///   - Typing Enter should only be used to insert a mention (if applicable) or a new line. We call
    ///     `keyboardAction(.enter)`. If the action is handled (a mention was inserted), we
    ///     discard the just-inserted newline. If the action is ignored, we keep the newline
    ///     in the text.
    ///
    /// Notes:
    /// - The detection uses `AttributedString.hasExactlyOneNewLineInsertionOnCatalystOrIPad`.
    /// - The helper `discardNewLineInsertion(oldValue:offsetByCharacters:)` restores the old
    ///   text and places the insertion point at the appropriate character offset.
    private func discardNewLineInsertionAndHandleEnterKeyboardActionIfAppropriateOnCatalystAndIPad(_ oldValue: AttributedString, _ newValue: AttributedString) {

        // Prevent processing stale "newValue" data: if self.text changed between the onChange trigger
        // and now, exit early. The new self.text value will trigger another onChange call.
        guard self.text == newValue else { return }

        switch newValue.hasExactlyOneNewLineInsertionOnCatalystOrIPad(comparedTo: oldValue) {

        case .no:

            return

        case  .yes(offsetByCharacters: let offsetByCharacters):

            switch sharedState.sendMessageShortcutType {
                
            case .enter:
                
                // The keyboard shortcut to send the message is Enter. If the new line was inserted intentionally
                // (via `insertNewLineOnCmdEnterOnCatalystIfAppropriate(_:)`), we do nothing (except resetting discardNextNewLine).
                // Otherwise, we discard the new line and request the handling of the action. This will either insert a mention,
                // send the message, or do nothing.
                
                if discardNextNewLine {
                    discardNewLineInsertion(oldValue: oldValue, offsetByCharacters: offsetByCharacters)
                    _ = keyboardAction(.enter)
                } else {
                    discardNextNewLine = true
                }
                
            case .commandEnter:
                
                // The keyboard shortcut to send the message is Cmd+Enter so the only possibilty for the keyboard
                // action to be handled is the insertion of a mention. In that case, we want to remove the new line inserted
                // in the text field. If the keyboard action is ignored (meaning there was no mention to insert)
                // we keep the new line insertion.
                
                let result = keyboardAction(.enter)
                switch result {
                case .ignored:
                    break
                case .handled:
                    discardNewLineInsertion(oldValue: oldValue, offsetByCharacters: offsetByCharacters)
                }
                
            }

        }

    }

    
    /// Helper method for `discardNewLineInsertionAndHandleEnterKeyboardActionIfAppropriateOnCatalyst`
    ///
    /// This helper restores the old text and places the insertion point at the appropriate character offset.
    private func discardNewLineInsertion(oldValue: AttributedString, offsetByCharacters: Int) {
        let indexInOldString = oldValue.index(oldValue.startIndex, offsetByCharacters: min(max(0, offsetByCharacters), oldValue.characters.count))
        self.selection = .init(insertionPoint: indexInOldString)
        self.text = oldValue
    }

    
    /// This method is called whenever the text changes. The new text is sent to the shared state, allowing for other
    /// views to be updated accordingly (e.g., for the send button to appear).
    private func shareTextWithSharedState(_ oldValue: AttributedString, _ newValue: AttributedString) {
        
        // Prevent processing stale "newValue" data: if self.text changed between the onChange trigger
        // and now, exit early. The new self.text value will trigger another onChange call.
        guard self.text == newValue else { return }

        self.sharedState.onTextChangeInTextEditor(.attributedString(newValue))
        
    }

    
    /// This method is called whenever a key is pressed in the TextEditor.
    /// It handles Cmd+Enter on Catalyst and iPad to insert a newline or send the message.
    ///
    /// On Catalyst and iPad, when the user presses Command+Enter:
    /// - If `sendMessageShortcutType == .enter`, a newline is inserted at the current insertion point
    ///   and `discardNextNewLine` is set to `false` so that the newline is not removed by
    ///   `discardNewLineInsertionAndHandleEnterKeyboardActionIfAppropriateOnCatalystAndIPad(_:_:)`.
    /// - If `sendMessageShortcutType == .commandEnter`, the draft is sent immediately via
    ///   `sharedState.userWantsToSendDraft(...)`.
    ///
    /// For other platforms (e.g., iPhone) or other key presses, this is a no-op.
    ///
    /// This method relies on `KeyPress.isCommandPlusEnterOnCatalystOrIPad` to detect the key combo.
    private func insertNewLineOnCmdEnterOnCatalystAndIpadIfAppropriate(_ keyPress: KeyPress) -> KeyPress.Result {
        
        guard keyPress.isCommandPlusEnterOnCatalystOrIPad else { return .ignored }
        
        switch sharedState.sendMessageShortcutType {

        case .enter:
            guard let indexInText = selection.indexOfInsertionPoint(in: self.text) else { return .ignored }
            discardNextNewLine = false
            self.text.insert(AttributedString("\n"), at: indexInText)
            self.selection = .init(insertionPoint: self.text.index(indexInText, offsetByCharacters: 1))
            return .handled

        case .commandEnter:
            do { try sharedState.userWantsToSendDraft(currentTextInTextEditor: .attributedString(self.text)) } catch { assertionFailure() }
            return .handled

        }

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
        guard index <= self.text.endIndex else {
            // This happens when a new line is programmatically deleted in
            // discardNewLineInsertionAndHandleEnterKeyboardActionIfAppropriateOnCatalyst(_:_:)
            return
        }
        
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
            self.discardNextNewLine = true
        }
    }

    
    private func setInitialBodyTextIfNecessary() {
        if let initialBody = self.sharedState.consumeInitialBody() {
            self.text = initialBody
        }
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
            .onChange(of: text, discardNewLineInsertionAndHandleEnterKeyboardActionIfAppropriateOnCatalystAndIPad)
            .onChange(of: text, shareTextWithSharedState)
            .onChange(of: text, filterOutAdaptiveImageGlyph)
            .onChange(of: text, filterOutStickers)
            .onChange(of: selection, onSelectionChange)
            .onChange(of: sharedState.attributedTextToPaste, onChangeOfTextToPaste)
            .onKeyPress(action: insertNewLineOnCmdEnterOnCatalystAndIpadIfAppropriate)
            .task(onTaskForClearingInput)
            .onKeyPress(.downArrow) { keyboardAction(.down).toKeyPress }
            .onKeyPress(.upArrow) { keyboardAction(.up).toKeyPress }
            .onAppear(perform: setInitialBodyTextIfNecessary)
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
