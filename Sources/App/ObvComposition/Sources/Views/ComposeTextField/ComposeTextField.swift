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

/// The keys the text editors report: the arrows, which move through the mention suggestions. Return never comes this way — a key that produces a
/// character is claimed by text input, and the discussion screens take it with a `UIKeyCommand`, see `ComposeView.SharedState.returnWasPressed(with:)`.
public enum KeyboardActionType {
    case up
    case down
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


/// A weak box for the underlying `UITextView`, so a SwiftUI `@State` can hold a reference to it — set from `introspect`, read on clear — without
/// retaining it.
@MainActor
final class WeakTextView {
    weak var view: UITextView?
}


public struct ComposeTextField: View {
    
    private let sharedState: ComposeTextField.SharedState
    private let keyboardAction: (KeyboardActionType) -> KeyboardResult

    let pasteDelegate: TextViewPasteDelegate

    /// The height the text needs, as the `UITextView` behind the editor measures it. Nil until it has been measured once.
    ///
    /// A `TextEditor` reports the height of a *single line* until that text view has laid its text out, which is one layout pass too late. Measured on
    /// entering a discussion with a four-line draft, the field was 26.29pt tall on the first pass **every** time, and was corrected only when something
    /// else happened to invalidate the layout: at 153ms in one visit, at 967ms in another, and not until the bar was tapped 10.6s later in a third. The
    /// legacy screen converges because `ComposeViewHostingController.viewDidLayoutSubviews` invalidates its intrinsic content size on every pass — which is
    /// exactly the resize seen during its entering animation — and a SwiftUI host gives no such nudge.
    ///
    /// So the text view is asked directly. It has already computed those metrics; re-deriving them in SwiftUI does not work, as a hidden `Text` measured
    /// 14pt against the editor's 26.29pt for a single line.
    @State private var heightNeededByTheTextView: CGFloat?

    init(sharedState: ComposeTextField.SharedState,
         keyboardAction: @escaping (KeyboardActionType) -> KeyboardResult) {
        self.sharedState = sharedState
        self.keyboardAction = keyboardAction
        self.pasteDelegate = TextViewPasteDelegate(sharedState: sharedState)
    }


    /// Applied as a *floor*, and never as a fixed height: once the text view has laid out its text, the editor sizes itself correctly and must keep
    /// governing — this measurement can lag it by an edit, as it is taken while SwiftUI is updating the text view.
    private func measureHeightNeeded(of textView: UITextView) {
        // A zero width yields an enormous height, and the first call can arrive before the text view has been laid out at all.
        guard textView.bounds.width > 0 else { return }
        let sizeThatFits = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
        let heightNeeded = min(max(sizeThatFits.height, LineLimit.defaultLineHeight), LineLimit.toMaxHeight)
        guard abs((heightNeededByTheTextView ?? -1) - heightNeeded) > 0.5 else { return }
        // This runs while the representable behind the editor is being updated, where writing state is not allowed. Deferred by one turn of the main queue,
        // and with animations disabled: the first frame is then one line tall and the second is right, which is a great deal better than the wait it
        // replaces, and imperceptible as long as it is not animated.
        Task { @MainActor in
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                heightNeededByTheTextView = heightNeeded
            }
        }
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
        // **The editor has no find of its own.** A `TextEditor` enables UIKit's find interaction on its text view, and a text view with it answers ⌘F itself
        // while it is the first responder: with the caret in this bar, ⌘F opened a *Done / Find* panel over the draft, in the bar's place, finding nothing —
        // measured on Catalyst on 2026-10-02 — where with the caret anywhere else the key climbed the responder chain to the discussion's own search. On a
        // discussion screen ⌘F means that search, so the editor declines, and the key climbs from here too.
        .findDisabled(true)
        .introspect(.textEditor, on: .iOS(.v16, .v17, .v18, .v26, .v27)) { textView in

            if textView.pasteDelegate == nil || !(textView.pasteDelegate is TextViewPasteDelegate) {
                // Create and set a custom paste delegate
                textView.pasteDelegate = pasteDelegate
            }

            // Read by the discussion screen to decide whether its Return key commands apply, see `ComposeView.SharedState.isTheEditorTheFirstResponder`.
            if sharedState.textView !== textView {
                sharedState.textView = textView
            }

            measureHeightNeeded(of: textView)

        }
        .frame(minHeight: heightNeededByTheTextView)
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
    
    /// Observed, as the iOS 26 editor's is: a newline inserted on behalf of a Return key command arrives through `textToPaste`, and nothing else on
    /// the screen changes with it — where a pasted link is followed by a change of the bar's state that happened to redraw this editor.
    @ObservedObject private var sharedState: ComposeTextField.SharedState
    private let keyboardAction: (KeyboardActionType) -> KeyboardResult

    @State private var text: String
    @State private var selection: TextSelection?

    /// Holds the underlying `UITextView` so the clear can resync its input delegate. See ``onTaskForClearingInput()``: emptying the text through the
    /// SwiftUI binding leaves the text view not rendering the first following keystroke on iOS 18, until its input context is told to re-read.
    @State private var underlyingTextView = WeakTextView()

    init(sharedState: ComposeTextField.SharedState,
         keyboardAction: @escaping (KeyboardActionType) -> KeyboardResult) {
        self.sharedState = sharedState
        self.keyboardAction = keyboardAction
        // Seeded here rather than from `.onAppear`, so that this editor is measured *with* its text on the very first layout pass — see
        // `TextEditorWithTextSelectionAndAttributedString.init` for what being filled afterwards costs. Mentions are lost, as they are anyway in this
        // editor, which holds a plain `String`.
        _text = State(initialValue: sharedState.initialBodyForTextEditor.map { String($0.characters[...]) } ?? "")
    }


    /// This method is called whenever the text changes. The new text is sent to the shared state, allowing for other
    /// views to be updated accordingly (e.g., for the send button to appear).
    private func shareTextWithSharedState(_ oldValue: String, _ newValue: String) {
        self.sharedState.onTextChangeInTextEditor(.string(newValue))
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
            // **Never feed the focused editor a nil selection.** The primary source of that on iOS 18 is the `.constant(nil)` selection binding during a
            // send — see the `TextEditor` in `body`. This is the second source: leaving the selection nil *here* would do the same. Every other site
            // (mention insert, paste) already ends on a valid insertion point, and so does the iOS 26 editor's own clear — which never
            // wedged. Mirror it: a valid insertion point before and after the text is emptied.
            self.selection = .init(insertionPoint: self.text.startIndex)
            self.text = ""
            self.selection = .init(insertionPoint: self.text.startIndex)
            // **Resync the text input system once the emptied text has settled.** Emptying the text through the SwiftUI binding leaves the underlying
            // `UITextView` with the new content but a stale input context, so on iOS 18 the first following keystroke updates `$text` yet paints no
            // glyph until the second. Telling the input delegate the document and selection changed makes it re-read, so the next keystroke renders —
            // *without* touching first responder. A full resign+become also fixed it but dismissed the keyboard and dragged the transcript with it, far
            // worse than the one-glyph lag. These are pure notifications: no focus change, no content change, no scroll — worst case they simply do not
            // help. Not needed on iOS 26, whose attributed editor renders the first keystroke without this.
            Task { @MainActor in
                guard self.isFocused, let tv = self.underlyingTextView.view, tv.isFirstResponder else { return }
                tv.inputDelegate?.textDidChange(tv)
                tv.inputDelegate?.selectionDidChange(tv)
            }
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
        // **Neither binding may be swapped on iOS 18**, and the two failures are why. Swapping *selection* to `.constant(nil)` — the original code, on
        // every send as `isPreventingEdition` flips — feeds a focused `TextEditor` a nil selection and kills its input session: you can type and pick
        // QuickType suggestions but nothing reaches `$text` until a focus cycle rebuilds it. Swapping *text* to `.constant("")` while selection stays on
        // `$selection` then crashes instead: the caret still holds an index into the *old* text, and resolving it against the empty constant is a String
        // index out of bounds in `_toUTF16Offsets`. So bind both to state and never swap — text and selection then always agree (no crash) and the
        // selection is never nilled under the focused editor (no wedge). The "busy" state during a send or a load is already shown by ComposeView: the
        // field dims to 0.1 opacity, a spinner overlays it, and the send button is disabled. (The iOS 26 attributed editor tolerates the text swap; the
        // String-based iOS 18 one does not.)
        TextEditor(text: $text, selection: $selection)
            .autocorrectionObv(autocorrection: sharedState.autocorrection, spellChecking: .yes)
            .textEditorStyle(.plain)
            .scrollContentBackground(.hidden)
            .introspect(.textEditor, on: .iOS(.v18)) { self.underlyingTextView.view = $0 }
            .onChange(of: text, shareTextWithSharedState)
            .onChange(of: selection, onSelectionChange)
            .onChange(of: sharedState.textToPaste, onChangeOfTextToPaste)
            .task(onTaskForClearingInput)
            // `keyboardAction` is captured *by value*, and not read from `self`. Read from `self`, these closures capture this whole view — and so its
            // `sharedState` — and SwiftUI keeps the handlers of `onKeyPress` alive well past the life of the view that installed them. Seen in a memory
            // graph: an array of `KeyPress.Handler` holding a closure whose capture held a `ComposeTextField.SharedState` that should have been gone.
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
            .isHidden(self.isFocused || !self.text.isEmpty)
    }

}


// MARK: - Legacy TextField on iOS 17

@available(iOS, introduced: 16.0, deprecated: 18.0, message: "Use TextEditorWithTextSelection on iOS 18")
private struct LegacyTextEditor: View {
    
    /// Observed for the same reason as in `TextEditorWithTextSelection`.
    @ObservedObject private var sharedState: ComposeTextField.SharedState
    private let keyboardAction: (KeyboardActionType) -> KeyboardResult

    @State private var text: String

    init(sharedState: ComposeTextField.SharedState,
         keyboardAction: @escaping (KeyboardActionType) -> KeyboardResult) {
        self.sharedState = sharedState
        self.keyboardAction = keyboardAction
        // Seeded here rather than from `.onAppear`, see `TextEditorWithTextSelectionAndAttributedString.init`. Mentions are lost, as they are anyway in
        // this editor, which holds a plain `String`.
        _text = State(initialValue: sharedState.initialBodyForTextEditor.map { String($0.characters[...]) } ?? "")
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

        // This editor has no selection binding, but the `UITextView` behind it is known, and `insertText` puts the string at its caret, replacing a
        // selection if there is one, and reports the change through the delegate the `TextEditor` already listens to. That matters for a newline
        // inserted on behalf of a Return key: appended, it lands after the last word whatever the caret was doing. Appending is kept for the
        // moment before the text view has been introspected, and while edition is prevented: the editor is then bound to a constant empty
        // string, so the text view holds nothing and an insert into it is discarded when the draft is restored, where `text` keeps the draft
        // throughout. The lock is lifted in the same turn as the paste on every current path, but that is one deferred completion away.

        if let textView = sharedState.textView, !sharedState.isPreventingEdition {
            textView.insertText(newValue)
        } else {
            self.text += newValue
        }

    }

    
    var body: some View {
        TextEditor(text: sharedState.isPreventingEdition ? .constant("") : $text)
            .autocorrectionObv(autocorrection: sharedState.autocorrection, spellChecking: .yes)
            .scrollContentBackground(.hidden)
            .onChange(of: text, perform: shareTextWithSharedState)
            .onChange(of: sharedState.textToPaste, perform: onChangeOfTextToPaste)
            .task(onTaskForClearingInput)
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

