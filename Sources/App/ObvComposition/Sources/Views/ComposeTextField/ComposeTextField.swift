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
import ObvAppTypes
import ObvSettings

public enum KeyboardActionType {
    case up
    case down
    case enter
}

public enum KeyboardResult {
    case ignored
    case handled
    
    @available(iOS 17.0, *)
    public var toKeyPress: KeyPress.Result {
        switch self {
        case .ignored:
            return .ignored
        case .handled:
            return .handled
        }
    }
}


public struct ComposeTextField: View {
    
    private let sharedState: ComposeTextField.SharedState
    private let keyboardAction: (KeyboardActionType) -> KeyboardResult

    let pasteDelegate: TextViewPasteDelegate
    
    init(sharedState: ComposeTextField.SharedState,
         keyboardAction: @escaping (KeyboardActionType) -> KeyboardResult) {
        self.sharedState = sharedState
        self.keyboardAction = keyboardAction
        self.pasteDelegate = TextViewPasteDelegate(sharedState: sharedState)
    }
    
    @ViewBuilder
    public var body: some View {
        Group {
            if #available(iOS 26.0, *) { /// This version can change caret position and colorize text of the input.
                
                TextEditorWithTextSelectionAndAttributedString(
                    sharedState: sharedState,
                    keyboardAction: keyboardAction)
                .padding(.top, 6.0)
                
            } else if #available(iOS 18.0, *) {
                
                TextEditorWithTextSelection(
                    sharedState: sharedState,
                    keyboardAction: keyboardAction)
                .padding(.top, 6.0)
                
            } else { /// This version can do....nothing particular.
                
                LegacyTextEditor(
                    sharedState: sharedState,
                    keyboardAction: keyboardAction)
                
            }
        }
        .introspect(.textEditor, on: .iOS(.v16, .v17, .v18, .v26)) { textView in
            
            if textView.pasteDelegate == nil || !(textView.pasteDelegate is TextViewPasteDelegate) {
                // Create and set a custom paste delegate
                textView.pasteDelegate = pasteDelegate
            }
            
        }
    }
}




// MARK: - TextEditorWithTextSelection on iOS 18

/// Text editor used on iOS 18.
///
/// Before iOS 26, the native SwiftUI TextEditor does not support attributed strings, which makes it more difficult to handle mentions. This editor
/// provides a "best effort" to handle mentions. These mentions are not emphasized visually, and their range is kept in an array, thus separated from
/// the text shown. When sending the message, we use a minimal technique to create an AttributedString from the String shown in the TextEditor and
/// the mentions kept for later.
@available(iOS, introduced: 18.0, deprecated: 26.0, message: "Use TextEditorWithTextSelectionAndAttributedString on iOS 26")
public struct TextEditorWithTextSelection: View {
    
    private let sharedState: ComposeTextField.SharedState
    private let keyboardAction: (KeyboardActionType) -> KeyboardResult

    @State private var text: String = ""
    @State private var selection: TextSelection?

    @State private var discardNextNewLine = true
    
    init(sharedState: ComposeTextField.SharedState,
         keyboardAction: @escaping (KeyboardActionType) -> KeyboardResult) {
        self.sharedState = sharedState
        self.keyboardAction = keyboardAction
    }
        
    
    /// This method is called whenever the text changes. On Catalyst and iPad, removes newline insertions (when appropriate)
    /// and handles Enter/Command+Enter actions.
    ///
    /// Invoked from `onChange(of: text)`, this method compares the previous and new plain
    /// text values and detects whether the only change is exactly one newline character
    /// insertion. If so, it decides whether to keep or discard that newline and whether to
    /// trigger an action (send message or insert mention) based on the user's configured
    /// send shortcut.
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
    /// - Detection uses `String.hasExactlyOneNewLineInsertionOnCatalystOrIPad`.
    /// - The helper `discardNewLineInsertion(oldValue:offset:)` restores the old text and
    ///   places the insertion point at the appropriate character offset.

    /// This method is called whenever the text changes. On macOS (Catalyst), it potentially filters out newline insertions and handles any appropriate action
    /// that should be triggered by the Enter key.
    /// On other platforms, this is a no-op.
    ///
    /// This method compares the old and new text values:
    /// - If a single newline was added AND `discardNextNewLine` is `true`: removes the newline
    /// - If a newline was intentionally added (via `insertNewLineOnCmdEnterOnCatalystIfAppropriate(_:)`):
    ///   keeps the newline and resets `discardNextNewLine` to `true`
    ///
    /// The principles are very similar to those in `TextEditorWithTextSelectionAndAttributedStringAlternative`, so any change made here should be considered
    /// in `TextEditorWithTextSelectionAndAttributedStringAlternative` as well.
    private func discardNewLineInsertionAndHandleEnterKeyboardActionIfAppropriateOnCatalystAndIPad(_ oldValue: String, _ newValue: String) {

        switch newValue.hasExactlyOneNewLineInsertionOnCatalystOrIPad(comparedTo: oldValue) {

        case .no:

            return

        case  .yes(offset: let offset):
            
            switch sharedState.sendMessageShortcutType {
                
            case .enter:
                
                // The keyboard shortcut to send the message is Enter. If the new line was inserted intentionally
                // (via `insertNewLineOnCmdEnterOnCatalystIfAppropriate(_:)`), we do nothing (excepte resetting discardNextNewLine).
                // Otherwise, we discard the new line and request the handling of the action. This will either insert a mention,
                // send the message, or do nothing.
                
                if discardNextNewLine {
                    discardNewLineInsertion(oldValue: oldValue, offset: offset)
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
                    discardNewLineInsertion(oldValue: oldValue, offset: offset)
                }
                
            }
 
        }

    }
    
    
    /// Helper method for `discardNewLineInsertionAndHandleEnterKeyboardActionIfAppropriateOnCatalyst`
    ///
    /// This helper restores the old text and places the insertion point at the appropriate character offset.
    private func discardNewLineInsertion(oldValue: String, offset: Int) {
        self.selection = nil // Required to prevent an out-of-bounds crash on the next line
        self.text = oldValue
        let newInsertionPoint = self.text.index(self.text.startIndex, offsetBy: offset, limitedBy: offset >= 0 ? self.text.endIndex : self.text.startIndex)
        self.selection = .init(insertionPoint: newInsertionPoint ?? self.text.endIndex)
    }
    
    
    /// This method is called whenever the text changes. The new text is sent to the shared state, allowing for other
    /// views to be updated accordingly (e.g., for the send button to appear).
    private func shareTextWithSharedState(_ oldValue: String, _ newValue: String) {
        self.sharedState.onTextChangeInTextEditor(.string(newValue))
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
            guard let selection, let index = selection.indexOfInsertionPoint else { return .ignored }
            guard text.startIndex <= index, index <= text.endIndex else { assertionFailure(); return .ignored }
            discardNextNewLine = false
            self.text.insert("\n", at: index)
            self.selection = .init(insertionPoint: self.text.index(index, offsetBy: 1))
            return .handled

        case .commandEnter:
            do { try sharedState.userWantsToSendDraft(currentTextInTextEditor: .string(self.text)) } catch { assertionFailure() }
            return .handled

        }

    }
    
    
    /// This method is called whenever the text selection changes. It handles the mention insertion process from end-to-end.
    ///
    /// If the new text selection is an insertion point, this method search for the last mention before it, and transmit it to the shared state.
    /// Eventually, this will give a chance to the mention view to show new mention suggestions and, for user, to choose one. In return,
    /// we (very asynchronouly) receive the user decision. When they choose a mention in the list, this method replaces the "mention string"
    /// (typed by the user) by the full mention title.
    ///
    /// Since the `TextEditor` used does not support `AttributedString`, we store the mentionned identity in a table instead
    /// of attaching it to the `AttributedString` like we do on iOS 26.
    private func onSelectionChange(_ oldValue: TextSelection?, _ newValue: TextSelection?) {
        
        guard let newValue, let index = newValue.indexOfInsertionPoint else { return }
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
            
            guard (selectionOnMentionRequest?.indexOfInsertionPoint, textOnMentionRequest) == (self.selection?.indexOfInsertionPoint, self.text) else { return }
            let userDecision = await sharedState.userTypedMentionStringInTextEditor(mentionString)
            guard (selectionOnMentionRequest?.indexOfInsertionPoint, textOnMentionRequest) == (self.selection?.indexOfInsertionPoint, self.text) else { return }

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
                guard let selection, let index = selection.indexOfInsertionPoint else { return }
                guard self.text.startIndex < index, index <= self.text.endIndex else { assertionFailure(); return }
                guard let mentionString = self.text.lastMentionString(before: index) else { return }
                guard let rangeOfMentionString = self.text.rangeOfLastMentionString(before: index) else { return }
                
                let mentionTitle = composeMentionSuggestionModel.title.trimmingWhitespacesAndNewlines()
                guard !mentionTitle.isEmpty else { return }
                let stringToInsert = "@" + mentionTitle
                
                guard rangeOfMentionString.lowerBound >= self.text.startIndex && rangeOfMentionString.upperBound <= self.text.endIndex else { assertionFailure(); return }
                self.selection = nil
                self.text.replaceSubrange(rangeOfMentionString, with: stringToInsert)
                self.selection = .init(insertionPoint: self.text.index(index, offsetBy: max(0, stringToInsert.count-mentionString.count), limitedBy: self.text.endIndex) ?? self.text.endIndex)
                
                // Add a space after the current insertion point if appropriate

                if let indexOfInsertionPoint = self.selection?.indexOfInsertionPoint {
                    let isSpaceAdded = self.text.insertSpaceIfNeeded(at: indexOfInsertionPoint)
                    if isSpaceAdded {
                        self.selection = .init(insertionPoint: self.text.index(after: indexOfInsertionPoint))
                    }
                }
                
                // Since the TextEditor does not support AttributedStrings, we simply store the mention for later.
                
                do {
                    let startIndexOfMention = rangeOfMentionString.lowerBound
                    let endIndexOfMention = self.text.index(startIndexOfMention, offsetBy: stringToInsert.count, limitedBy: self.text.endIndex) ?? self.text.endIndex
                    let rangeOfMention = startIndexOfMention..<endIndexOfMention
                    let mentionedCryptoId = composeMentionSuggestionModel.mentionedCryptoId
                    let mentionTitle = composeMentionSuggestionModel.title
                    sharedState.onNewInsertedMentionInTheTextEditor(mentionRangeInCurrentText: rangeOfMention, mention: (mentionedCryptoId, mentionTitle))
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
            self.selection = nil
            self.text = ""
            self.discardNextNewLine = true
        }
    }
    
    
    private func setInitialBodyTextIfNecessary() {
        if let initialBody = self.sharedState.consumeInitialBody() {
            self.text = String(initialBody.characters[...])
            // For now, mentions are lost
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
    private func onChangeOfTextToPaste(_ oldValue: String?, _ newValue: String?) {
        
        // Eventually, we want the string to paste of the shared state to be reset
        
        defer { sharedState.resetTextToPasteIntoTextEditor() }
        
        // Ensure there is a string to paste
        
        guard let newValue, !newValue.isEmpty else { return }
        
        // Insert the new string
        
        if let selection, let insertionRange = selection.indices.selectionRangeOrFirstRangeOfMultiSelection {
            
            // We replace the range with the new string and update the selection to match the pasted string:
            // if the previous selection was an insertion point, we place the new selection at the end of the pasted
            // string. If the previous selection was a range, we select the pasted text.
            
            self.text.replaceSubrange(insertionRange, with: newValue)
            if selection.isInsertion {
                self.selection = .init(insertionPoint: self.text.index(insertionRange.lowerBound, offsetBy: newValue.count))
            } else {
                self.selection = .init(range: insertionRange.lowerBound..<self.text.index(insertionRange.lowerBound, offsetBy: newValue.count))
            }
            
        } else {
            
            // We have no range to replace (no insertion point either), we paste the new value at the end of the current text
            
            self.text += newValue
            self.selection = .init(insertionPoint: self.text.endIndex)
            
        }
        
    }

    
    @ViewBuilder
    public var body: some View {
        TextEditor(text: sharedState.isPreventingEdition ? .constant("") : $text, selection: sharedState.isPreventingEdition ? .constant(nil) : $selection)
            .autocorrectionObv(autocorrection: sharedState.autocorrection, spellChecking: .yes)
            .textEditorStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: text, discardNewLineInsertionAndHandleEnterKeyboardActionIfAppropriateOnCatalystAndIPad)
            .onChange(of: text, shareTextWithSharedState)
            .onChange(of: selection, onSelectionChange)
            .onChange(of: sharedState.textToPaste, onChangeOfTextToPaste)
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
            .isHidden(self.isFocused || !self.text.isEmpty)
    }

}


// MARK: - Legacy TextField on iOS 17

@available(iOS, introduced: 16.0, deprecated: 18.0, message: "Use TextEditorWithTextSelection on iOS 18")
private struct LegacyTextEditor: View {
    
    private let sharedState: ComposeTextField.SharedState
    private let keyboardAction: (KeyboardActionType) -> KeyboardResult

    @State private var text: String = ""
    
    init(sharedState: ComposeTextField.SharedState,
         keyboardAction: @escaping (KeyboardActionType) -> KeyboardResult) {
        self.sharedState = sharedState
        self.keyboardAction = keyboardAction
    }

    
    /// This method is called whenever the text changes. The new text is sent to the shared state, allowing for other
    /// views to be updated accordingly (e.g., for the send button to appear).
    private func shareTextWithSharedState(_ newValue: String) {
        self.sharedState.onTextChangeInTextEditor(.string(newValue))
    }

    
    /// Start listening to a stream of events indicating that this view should reset all its internal states.
    /// This happens when the user sends the message by interacting with another view of the composition view
    /// (typically, by tapping the send button).
    private func onTaskForClearingInput() async {
        let stream = sharedState.getAsyncStreamOfClearInputRequests()
        for await _ in stream {
            self.text = ""
        }
    }
    
    
    private func setInitialBodyTextIfNecessary() {
        if let initialBody = self.sharedState.consumeInitialBody() {
            self.text = String(initialBody.characters[...])
            // For now, mentions are lost
        }
    }

    
    @FocusState private var isFocused: Bool
    

    /// Called each time the shared state's `attributedTextToPaste` is updated.
    ///
    /// This is used, e.g., when the user pastes an URL using the paste button of the compose view. In that case, the compose
    /// view requests to add attachments to the draft. An URL preview is added as an attachment, and the URL (as a String) is reported back
    /// here.
    private func onChangeOfTextToPaste(newValue: String?) {
        
        // Eventually, we want the string to paste of the shared state to be reset
        
        defer { sharedState.resetTextToPasteIntoTextEditor() }
        // Ensure there is a string to paste
        
        guard let newValue, !newValue.isEmpty else { return }
        
        // Insert the new string at the end of the current text
        
        self.text += newValue
        
    }

    
    var body: some View {
        TextEditor(text: sharedState.isPreventingEdition ? .constant("") : $text)
            .autocorrectionObv(autocorrection: sharedState.autocorrection, spellChecking: .yes)
            .scrollContentBackground(.hidden)
            .onChange(of: text, perform: shareTextWithSharedState)
            .onChange(of: sharedState.textToPaste, perform: onChangeOfTextToPaste)
            .task(onTaskForClearingInput)
            .onAppear(perform: setInitialBodyTextIfNecessary)
            .frame(minHeight: ComposeTextField.LineLimit.defaultLineHeight, maxHeight: ComposeTextField.LineLimit.toMaxHeight)
            .focused($isFocused)
            .overlay(alignment: .leading, content: { overlay })
    }
    
    
    @ViewBuilder
    private var overlay: some View {
        Text(verbatim: "Aa")
            .foregroundStyle(.secondary)
            .allowsHitTesting(false)
            .isHidden(self.isFocused || !self.text.isEmpty)
    }

}


// MARK: - Private helpers

extension String {
    
    enum HasExactlyOneNewLineInsertion {
        case no
        case yes(offset: Int)
    }
    
    func hasExactlyOneNewLineInsertion(comparedTo other: String) -> HasExactlyOneNewLineInsertion {
        guard self.count == other.count + 1 else { return .no }
        let differences = self.difference(from: other)
        guard differences.count == 1, let insertion = differences.insertions.first else { return .no }
        switch insertion {
        case .remove:
            return .no
        case .insert(offset: let offset, element: let element, associatedWith: _):
            return element.isNewline ? .yes(offset: offset) : .no
        }
    }
    
    
    @MainActor
    func hasExactlyOneNewLineInsertionOnCatalystOrIPad(comparedTo other: String) -> HasExactlyOneNewLineInsertion {
        #if targetEnvironment(macCatalyst)
        return self.hasExactlyOneNewLineInsertion(comparedTo: other)
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            return self.hasExactlyOneNewLineInsertion(comparedTo: other)
        } else {
            return .no
        }
        #endif
    }
    
    
    func wordBefore(index: String.Index) -> String? {
        guard index >= self.startIndex, index <= self.endIndex else { return nil }
        var result = ""
        var currentIndex = self.index(before: index)
        while currentIndex >= self.startIndex {
            currentIndex = self.index(before: currentIndex)
            let char = self[currentIndex]
            if char.isWhitespace {
                return result.isEmpty ? nil : result
            } else {
                result.insert(char, at: result.startIndex)
            }
        }
        return result.isEmpty ? nil : result
    }
    
}



@available(iOS 17.0, *)
extension KeyPress {
    
    @MainActor
    var isCommandPlusEnterOnCatalystOrIPad: Bool {
        #if targetEnvironment(macCatalyst)
        return self.key == .return && self.modifiers == [.command]
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            return self.key == .return && self.modifiers == [.command]
        } else {
            return false
        }
        #endif
    }
    
}


@available(iOS 18.0, *)
extension TextSelection {
    
    /// Returns the insertion point of this text selection if it is a (single) selection.
    ///
    /// This method returns `nil` in case of a multiSelection.
    var indexOfInsertionPoint: String.Index? {
        guard self.isInsertion else { return nil }
        switch self.indices {
        case .multiSelection:
            return nil
        case .selection(let range):
            assert(range.lowerBound == range.upperBound)
            let index = range.lowerBound
            return index
        @unknown default:
            assertionFailure("There is a new case to handle")
            return nil
        }
    }
    
}


extension String {
    
    /// Returns the last mention string before the given index, if one exists.
    ///
    /// A mention string starts with `@` followed by zero or more alphanumeric characters
    /// (e.g., `@alice`, `@user123`). The mention must be either:
    /// - Preceded by whitespace (space, newline, tab, etc.)
    /// - At the start of the string
    ///
    /// - Parameter index: The position to search backward from
    /// - Returns: The mention string (including `@`), or `nil` if none exists
    ///
    /// **Examples:**
    /// - `"Hello @alice"` at end index → `"@alice"`
    /// - `"@bob"` at end index → `"@bob"`
    /// - `"bob@alice"` at any valid index → `nil` (no whitespace before `@`)
    /// - `"@bob "` at end index → `nil` (space immediately before index)
    func lastMentionString(before index: String.Index) -> String? {
        
        guard !self.isEmpty else {
            // If the string is empty, it cannot contain a mention string
            return nil
        }
        
        guard index > self.startIndex else {
            // If the index points to the first character, there cannot be a mention string before it.
            return nil
        }
        
        guard index <= self.endIndex else {
            // If index > self.endIndex, the caller made a programmatic error. Note that, since we do not
            // include the character at `index`, it is acceptable to have index == self.endIndex
            assertionFailure()
            return nil
        }
        
        // Extract the prefix of the string, up to (but excluding `index`)
        guard let lastIncludedIndex = self.index(index, offsetBy: -1, limitedBy: self.startIndex) else { return nil }
        let prefix = self.prefix(through: lastIncludedIndex)
        
        guard let indexOfLastAt = prefix.lastIndex(where: { $0 == "@" }) else {
            // The prefix does not contain any '@', it cannot contain a mention string
            return nil
        }
        
        // Extract the candidate suffix of the prefix. This suffix starts with '@'.
        let candidate = prefix[indexOfLastAt...]
        
        
        // Ensure the candidate is located at the beginning of the original string or is preceeded by a space (or new line)
        guard indexOfLastAt == self.startIndex || (indexOfLastAt > self.startIndex && self[self.index(before: indexOfLastAt)].isWhitespace) else {
            return nil
        }
        
        // Ensure all the characters of the candidate are acceptable (i.e., are alphanumeric or '@')
        let acceptedCharacterSet = CharacterSet.alphanumerics.union(.init(charactersIn: "@"))
        guard candidate.unicodeScalars.allSatisfy({ acceptedCharacterSet.contains($0) }) else { return nil }
        
        // If we reach this point, the candidate is accepted
        return String(candidate)
        
    }
    
    
    func rangeOfLastMentionString(before index: String.Index) -> Range<String.Index>? {
        guard let mentionString = self.lastMentionString(before: index) else { return nil }
        return self.range(of: mentionString, options: [.backwards], range: self.startIndex..<index, locale: nil)
    }
    
    
    mutating func insertSpaceIfNeeded(at index: String.Index) -> Bool {
        guard index >= self.startIndex, index <= self.endIndex else { assertionFailure(); return false }
        if index == self.endIndex {
            self.append(" ")
            return true
        } else if !self[index].isWhitespace {
            self.insert(" ", at: index)
            return true
        } else {
            return false
        }
    }
    
}


extension AttributedString {
    
    enum HasExactlyOneNewLineInsertion {
        case no
        case yes(offsetByCharacters: Int)
    }

    /// Determines if this attributed string differs from another by exactly one newline insertion.
    ///
    /// This method compares the attributed string with another and checks if the only difference
    /// is a single "\n" character present in this string but not in the other.
    ///
    /// - Parameter other: The attributed string to compare against, expected to be identical
    ///                    except for one missing newline character.
    ///
    /// - Returns: A `HasExactlyOneNewLineInsertion` enum value:
    ///   - `.no` if the strings differ in any way other than a single newline insertion
    ///   - `.yes(offsetByCharacters:)` if the only difference is exactly one "\n" character, with the
    ///     offsetByCharacters indicating the position of that newline in this string.
    ///
    /// If this method returns `.yes(offsetByCharacters:)`, the index of the '\n' character is
    /// `self.index(self.startIndex, offsetByCharacters: offsetByCharacters)`
    func hasExactlyOneNewLineInsertion(comparedTo other: AttributedString) -> HasExactlyOneNewLineInsertion {

        let selfChars = Array(self.characters)
        let otherChars = Array(other.characters)
        
        guard selfChars.count == otherChars.count + 1 else {
            return .no
        }

        // Find the position where the AttributedStrings differ
        
        let indexOfFirstDifference: Int? = (0..<otherChars.count).first(where: { selfChars[$0] != otherChars[$0] })
        
        // If we did not find a difference, check the last character of self
        
        guard let indexOfFirstDifference else {
            print("indexOfFirstDifference is nil")
            // Note that since selfChars.count == otherChars.count + 1, we know selfChars.count-1 >= 0
            return selfChars.last?.isNewline == true ? .yes(offsetByCharacters: selfChars.count-1) : .no
        }

        // We found a difference. Check that the remaining characters are equal
        
        if indexOfFirstDifference+1 < otherChars.count {
            guard (indexOfFirstDifference+1..<otherChars.count).allSatisfy({ selfChars[$0+1] == otherChars[$0] }) else {
                return .no
            }
        }
        
        // The only difference is at index indexOfFirstDifference. Check if its a "\n"
        
        guard selfChars[indexOfFirstDifference].isNewline else {
            return .no
        }

        // The only difference is indeed a new line. Turn the indexOfFirstDifference into and index in 'self'
        
        //let index = self.index(self.startIndex, offsetByCharacters: indexOfFirstDifference)
        return .yes(offsetByCharacters: indexOfFirstDifference)
        
    }

    
    @MainActor
    func hasExactlyOneNewLineInsertionOnCatalystOrIPad(comparedTo other: AttributedString) -> HasExactlyOneNewLineInsertion {
        #if targetEnvironment(macCatalyst)
        return self.hasExactlyOneNewLineInsertion(comparedTo: other)
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            return self.hasExactlyOneNewLineInsertion(comparedTo: other)
        } else {
            return .no
        }
        #endif
    }

}


@available(iOS 26.0, *)
extension AttributedTextSelection {
    
    /// Returns the insertion point of this text selection if it is a (single) selection.
    ///
    /// This method returns `nil` in case of a multiSelection.
    func indexOfInsertionPoint(in attributedString: AttributedString) -> AttributedString.Index? {
        switch self.indices(in: attributedString) {
        case .ranges:
            return nil
        case .insertionPoint(let index):
            return index
        }
    }
    
}


extension AttributedString {
    
    /// Returns the last mention string before the given index, if one exists. The index must be
    /// a valid index for this `AttributedString` (in practice, the caller of this method must
    /// ensure the index has just been computed for this `AttributedString`)
    ///
    /// A mention string starts with `@` followed by zero or more alphanumeric characters
    /// (e.g., `@alice`, `@user123`). The mention must be either:
    /// - Preceded by whitespace (space, newline, tab, etc.)
    /// - At the start of the string
    ///
    /// - Parameter index: The position to search backward from
    /// - Returns: The mention string (including `@`), or `nil` if none exists
    ///
    /// **Examples:**
    /// - `"Hello @alice"` at end index → `"@alice"`
    /// - `"@bob"` at end index → `"@bob"`
    /// - `"bob@alice"` at any valid index → `nil` (no whitespace before `@`)
    /// - `"@bob "` at end index → `nil` (space immediately before index)
    func lastMentionString(before index: AttributedString.Index) -> String? {
        
        guard !self.characters.isEmpty else {
            // If the string is empty, it cannot contain a mention string
            return nil
        }
        
        guard index > self.startIndex else {
            // If the index points to the first character, there cannot be a mention string before it.
            return nil
        }
        
        guard index <= self.endIndex else {
            // If index > self.endIndex, the caller made a programmatic error. Note that, since we do not
            // include the character at `index`, it is acceptable to have index == self.endIndex
            assertionFailure()
            return nil
        }
        
        let string = String(self.characters[self.startIndex..<index])
        return string.lastMentionString(before: string.endIndex)
        
    }

    
    func rangeOfLastMentionString(before index: AttributedString.Index) -> Range<AttributedString.Index>? {
        guard let mentionString = self.lastMentionString(before: index) else { return nil }
        return self[self.startIndex..<index].range(of: mentionString, options: [.backwards], locale: nil)
    }

    
    mutating func insertSpaceIfNeeded(at index: AttributedString.Index) -> Bool {
        guard index >= self.startIndex, index <= self.endIndex else { assertionFailure(); return false }
        if index == self.endIndex {
            self.append(AttributedString(" "))
            return true
        } else if !self.characters[index].isWhitespace {
            self.insert(AttributedString(" "), at: index)
            return true
        } else {
            return false
        }
    }

}


@available(iOS 18.0, *)
extension TextSelection.Indices {
    
    var selectionRangeOrFirstRangeOfMultiSelection: Range<String.Index>? {
        switch self {
        case .selection(let range):
            return range
        case .multiSelection(let rangeSet):
            return rangeSet.ranges.first
        @unknown default:
            assertionFailure()
            return nil
        }
    }
    
}


// MARK: - Helper for TextEditor maximum height


extension ComposeTextField {
    
    @MainActor
    struct LineLimit {
        
        private static let macOS = 15
        private static let iOS = 8
        private static let iPadOS = 8
        
        // Default line height derived from system body font to cap TextEditor height
        static let defaultLineHeight: CGFloat = {
            #if canImport(UIKit)
            return UIFont.preferredFont(forTextStyle: .body).lineHeight
            #else
            return 23.0
            #endif
        }()
        
        static var toMaxHeight: CGFloat {
            let lineLimit: Int
            #if targetEnvironment(macCatalyst)
            lineLimit = Self.macOS
            #else
            lineLimit = UIDevice.current.userInterfaceIdiom == .pad ? Self.iPadOS : Self.iOS
            #endif
            return CGFloat(lineLimit) * defaultLineHeight
        }
    }
    
    
}

// MARK: - UITextPasteDelegate Implementation

#if canImport(UIKit)
import UniformTypeIdentifiers

@available(iOS 16.0, *)
final class TextViewPasteDelegate: NSObject, UITextPasteDelegate {
    
    weak var sharedState: ComposeTextField.SharedState?
    
    init(sharedState: ComposeTextField.SharedState?) {
        self.sharedState = sharedState
        super.init()
    }
    
    // Intercept each paste item and handle it based on its type
    func textPasteConfigurationSupporting(
        _ textPasteConfigurationSupporting: UITextPasteConfigurationSupporting,
        transform item: UITextPasteItem
    ) {
        let itemProvider = item.itemProvider
        
        // Block the default paste behavior (text insertion)
        item.setNoResult()
        
        // Send the item provider to shared state for attachment handling
        sharedState?.userPastedItemProvider(itemProvider)
    }
}
#endif

