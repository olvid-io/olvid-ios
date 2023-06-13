/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import MobileCoreServices
import OSLog
import Platform_Base
import Discussions_Mentions_AutoGrowingTextView_TextViewDelegateProxy
#if DEBUG
import UniformTypeIdentifiers
#endif
import Platform_UIKit_Additions
import ObvUICoreData
import Components_TextInputShortcutsResultView

/// Represents all types related to ``AutoGrowingTextView``
enum AutoGrowingTextViewTypes {
    /// Represents the available shortcuts
    ///
    /// - mention: `A user mention, prefixed with `@``
    enum TextShortcut {
        /// A user mention, prefixed with `@`
        case mention
    }

    /// Types used in conjunction with ``AutoGrowingTextViewDelegate``
    enum DelegateTypes {
        /// Possible actions
        ///
        /// - keyboardPerformReturn: The user wants to send the given text
        enum Action {
            /// The user wants to send the given text
            case keyboardPerformReturn
        }
    }
}

/// Protocol denoting available methods for `AutoGrowingTextView`
protocol AutoGrowingTextViewDelegate: AnyObject {
    func userPastedItemProviders(in autoGrowingTextView: AutoGrowingTextView, itemProviders: [NSItemProvider])

    /// Method is called whenever the user requested a given action
    /// - Parameters:
    ///   - textView: The text view that this applies to
    ///   - action: The action to perform
    func autoGrowingTextView(_ textView: AutoGrowingTextView, perform action: AutoGrowingTextViewTypes.DelegateTypes.Action)

    func autogrowingTextViewUserClearedShortcut(_ textView: AutoGrowingTextView)

    func autogrowingTextView(_ textView: AutoGrowingTextView, userEnteredShortcut shortcut: AutoGrowingTextViewTypes.TextShortcut, result: String, within range: NSRange)
}


// MARK: - AutoGrowingTextView

final class AutoGrowingTextView: UITextViewFixed {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: AutoGrowingTextView.self))

    private var heightConstraint: NSLayoutConstraint!
    private var maxHeightConstraint: NSLayoutConstraint!

    private let sizingTextView = UITextViewFixed()

    weak var autoGrowingTextViewDelegate: AutoGrowingTextViewDelegate?

    /// Helper instance of `UIKeyCommand` when using the combo cmd + return
    private lazy var returnKeyCommand = UIKeyCommand(input: "\r",
                                                     modifierFlags: .command,
                                                     action: #selector(handleKeyCommand))..{
        $0.title = NSLocalizedString("Send", comment: "Send word, capitalized")

        if #available(iOS 15.0, *) {
            $0.wantsPriorityOverSystemBehavior = true
        }
    }

    private var __userIsEnteringAShortcut = false

    override var keyCommands: [UIKeyCommand]? {
        guard let superValue = super.keyCommands else {
            return [returnKeyCommand]
        }

        return superValue + [returnKeyCommand]
    }

    var maxHeight: CGFloat {
        get { maxHeightConstraint.constant }
        set {
            guard maxHeight != newValue else { return }
            maxHeightConstraint.constant = newValue
            invalidateIntrinsicContentSize()
            setNeedsLayout()
        }
    }

    private let defaultTypingAttributes: [NSAttributedString.Key: Any]

    /// This helper attribute is used to determine if we need to invalid our intrinsic content size, this corresponds to the last width used for calculating the intrinsic content size
    private var cachedWidth: CGFloat = -1

    override var attributedText: NSAttributedString! {
        get {
            return super.attributedText
        }

        set {
            super.attributedText = newValue

            if newValue == nil { // reset our text, post sending a message
                font = defaultTypingAttributes[.font] as? UIFont

                textColor = defaultTypingAttributes[.foregroundColor] as? UIColor
            }
        }
    }

    override var selectedRange: NSRange {
        get {
            return super.selectedRange
        }

        set {
            super.selectedRange = _updateSelectedTextRange(super.selectedRange, newValue)
        }
    }

    override var selectedTextRange: UITextRange? {
        get {
            return super.selectedTextRange
        }

        set {
            let _oldValue = super.selectedTextRange

            let _newResult = _updateSelectedTextRange(super.selectedTextRange, newValue)

            guard _oldValue != _newResult else {
                return
            }

            super.selectedTextRange = _newResult

            _updateShortcutMatchingState()
        }
    }

    private var _proxyDelegate: TextViewDelegateProxy?

    override weak var delegate: UITextViewDelegate? {
        get {
            return _proxyDelegate
        }

        set {
            guard let newValue else {
                _proxyDelegate = nil

                return
            }

            _proxyDelegate = _configureNewDelegate(newValue)
        }
    }

    init(defaultTypingAttributes: [NSAttributedString.Key: Any]) {
        self.defaultTypingAttributes = defaultTypingAttributes

        super.init()

        typingAttributes = defaultTypingAttributes

        sizingTextView.typingAttributes = defaultTypingAttributes

        self.isScrollEnabled = true
        
        self.maxHeightConstraint = self.heightAnchor.constraint(lessThanOrEqualToConstant: 150)
        self.maxHeightConstraint.priority = .required
        self.maxHeightConstraint.isActive = true
        self.heightConstraint = self.heightAnchor.constraint(equalToConstant: 100)
        self.heightConstraint.priority = .required
        self.heightConstraint.isActive = true

        NotificationCenter.default.addObserver(self, selector: #selector(_innerTextContentsDidChange), name: UITextView.textDidChangeNotification, object: self)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        let attributedString: NSAttributedString

        if textStorage.length == 0 {
            attributedString = .init(string: " ",
                                     attributes: defaultTypingAttributes)
        } else {
            attributedString = textStorage
        }

        sizingTextView.text = text
        sizingTextView.font = font // we also need to specify the font here since we're using dynamic type…
        sizingTextView.attributedText = attributedString
        sizingTextView.textStorage.beginEditing()
        sizingTextView.textStorage.setAttributedString(attributedString)
        sizingTextView.textStorage.endEditing()
        sizingTextView.setNeedsLayout()
        sizingTextView.layoutIfNeeded()

        return sizingTextView.sizeThatFits(CGSize(width: self.bounds.width, height: .greatestFiniteMagnitude))
    }

    private func _configureNewDelegate(_ delegate: UITextViewDelegate) -> TextViewDelegateProxy {
        let proxy = TextViewDelegateProxy(textView: self, with: delegate)

        super.delegate = proxy

        return proxy
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()

        let newHeight = min(maxHeight, intrinsicContentSize.height)
        if heightConstraint.constant != newHeight {
            heightConstraint.constant = newHeight
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        if cachedWidth != bounds.width {
            invalidateIntrinsicContentSize()

            cachedWidth = bounds.width
        }
    }

    /// Convenience method that resets the typing attributes to `defaultTypingAttributes` that was defined in ``init(defaultTypingAttributes:)``
    internal func resetTypingAttributesToDefaults() {
        typingAttributes = defaultTypingAttributes
    }


    @objc
    private func handleKeyCommand(_ command: UIKeyCommand) {
        if command == returnKeyCommand {
            guard isActuallyEditable else {
                return
            }

            guard let autoGrowingTextViewDelegate = autoGrowingTextViewDelegate else {
                os_log("🎤 we're missing our delegate", log: log, type: .fault)
                return
            }

            autoGrowingTextViewDelegate.autoGrowingTextView(self, perform: .keyboardPerformReturn)
        }
    }

    
    private func _fetchExistingMentionRanges() -> Set<NSRange> {
        var ranges: Set<NSRange> = []

        textStorage.enumerateAttributes(in: textStorage.fullNSRange,
                                        options: []) { attributes, range, _ in
            if attributes[.mentionableIdentity] != nil {
                ranges.insert(range)
            }
        }

        return ranges
    }

    
    private func _updateShortcutMatchingState() {
        guard let autoGrowingTextViewDelegate else {
            return
        }

        let result = olvid_lookup(for: ["@"],
                                  excludedRanges: _fetchExistingMentionRanges())

        if let result {
            __userIsEnteringAShortcut = true

            autoGrowingTextViewDelegate.autogrowingTextView(self,
                                                            userEnteredShortcut: .mention,
                                                            result: result.word,
                                                            within: .init(result.range,
                                                                          in: text))
        } else {
            if __userIsEnteringAShortcut {
                __userIsEnteringAShortcut = false

                autoGrowingTextViewDelegate.autogrowingTextViewUserClearedShortcut(self)
            }
        }
    }
    

    /// Given a ``TextShortcutItem`` (typically, a mention chosen by the user in the list of possible mentions), this method updates the textStore to reflect the user choice by inserting the shortcut item at the location of the selected range.
    @available(iOS 14.0, *)
    func apply(_ shortcut: TextInputShortcutsResultView.TextShortcutItem) {
        let originalCaretRange = selectedRange

        // Make sure the insertion point of the shortcut is included in the textStorage full range
        guard textStorage.fullNSRange.intersection(shortcut.range) != nil else {
            return
        }

        textStorage.beginEditing()

        textStorage.replaceCharacters(in: shortcut.range, with: shortcut.value)

        textStorage.endEditing()

        resetTypingAttributesToDefaults()

        selectedRange = selectedRange..{
            $0.location = originalCaretRange.location + shortcut.value.length
            $0.length = 0
        }

        textStorage.replaceCharacters(in: selectedRange, with: .init(string: " ", attributes: defaultTypingAttributes))

        selectedRange = selectedRange..{
            $0.location += 1
        }

        resetTypingAttributesToDefaults()

        invalidateIntrinsicContentSize()
        setNeedsLayout()
        layoutIfNeeded()

        delegate?.textViewDidChange?(self) // since we're manually updating the attributes here, the `UITextViewDelegate.textViewDidChange(_:)` wont get called
    }

    
    /// Prevents the selection of only part of a mention. Leverages ``AutoGrowingTextView._updateSelectedTextRange(_:_:)`` for the heavy lifting.
    private func _updateSelectedTextRange(_ oldValue: UITextRange?, _ newValue: UITextRange?) -> UITextRange? {
        guard let oldValue,
              let newValue else {
            return newValue
        }

        let oldNSRange = NSRange(location: offset(from: beginningOfDocument, to: oldValue.start), length: offset(from: oldValue.start, to: oldValue.end))

        let newNSRange = NSRange(location: offset(from: beginningOfDocument, to: newValue.start), length: offset(from: newValue.start, to: newValue.end))

        let resultNSRange = _updateSelectedTextRange(oldNSRange, newNSRange)

        guard let resultStart = position(from: beginningOfDocument, offset: resultNSRange.location) else {
            return newValue
        }

        guard let resultEnd = position(from: resultStart, offset: resultNSRange.length) else {
            return newValue
        }

        guard let range = textRange(from: resultStart, to: resultEnd) else {
            return newValue
        }

        return range
    }

    
    /// Prevents the selection of only part of a mention.
    private func _updateSelectedTextRange(_ oldValue: NSRange, _ newValue: NSRange) -> NSRange {
        enum Direction {
            case left
            case right
        }

        guard oldValue != newValue else { //nothing changed
            return newValue
        }

        guard (newValue.location + newValue.length) < textStorage.length else {
            return newValue
        }

        let direction: Direction

        if oldValue.location == newValue.location { //stationary location, maybe the selection range is changing
            if oldValue.length < newValue.length {
                direction = .right
            } else {
                direction = .left
            }
        } else {
            if oldValue.location < newValue.location {
                direction = .right
            } else {
                direction = .left
            }
        }

        var effectiveRange = NSRange(location: 0, length: 0)

        guard let _ = textStorage.attribute(.mentionableIdentity,
                                            at: newValue.location,
                                            longestEffectiveRange: &effectiveRange,
                                            in: textStorage.fullNSRange) as? MentionableIdentity else {
            return newValue
        }

        let returnValue = effectiveRange..{
            switch direction {
            case .left:
                if $0 == oldValue {
                    $0.length = 0
                }

            case .right:
                if $0 == oldValue {
                    $0.location = effectiveRange.location + effectiveRange.length

                    $0.length = 0
                }
            }
        }

        return returnValue
    }


    /// Prior to replacing text, this method is called to give us a chance to accept or reject the edits. We return `true` to accept the edits, `fase` otherwise.
    ///
    /// If the super implementation considers that the edits should be discarded, we discard them. Otherwise we return the value of ``func _shouldChangeText(in range: NSRange, replacementText text: String) -> Bool``.
    /// NOTE: Due to a bug (?), this method is never called (as of iOS 16.4.1). We have a special workaround (using ``OLVIDAutoGrowingTextViewTextViewDelegateProxy``) allowing us to be our own delegate, in addition to the ``NewComposeMessageView``.
    override func shouldChangeText(in range: UITextRange, replacementText text: String) -> Bool {
        
        guard super.shouldChangeText(in: range, replacementText: text) else {
            return false
        }

        guard !range.isEmpty else {
            return true
        }

        let convertedRange = NSRange(location: offset(from: beginningOfDocument, to: range.start), length: offset(from: range.start, to: range.end))

        return _shouldChangeText(in: convertedRange, replacementText: text)
    }

    
    /// Prior to replacing text, this private method is called to give us a chance to accept or reject the edits. We return `true` to accept the edits, `fase` otherwise.
    ///
    ///
    private func _shouldChangeText(in range: NSRange, replacementText text: String) -> Bool {
        
        if range == textStorage.fullNSRange {
            // We are replacing the whole content of the textStorage (which is possibly empty) by some replacement text
            resetTypingAttributesToDefaults()
            return true
        }

        // Return early when we are not adding a mention
        guard range.location < textStorage.length else {
            return true
        }

        /// Returns the range of the mention at the given location, if there is one.
        func mentionEffectiveRange(at location: Int) -> NSRange? {
            var effectiveRange = NSRange(location: 0, length: 0)
            guard textStorage.attribute(.mentionableIdentity,
                                        at: location,
                                        longestEffectiveRange: &effectiveRange,
                                        in: textStorage.fullNSRange) as? MentionableIdentity != nil else {
                return nil
            }
            return effectiveRange
        }

        guard let mentionEffectiveRange = mentionEffectiveRange(at: range.location) else {

            // There is no mention at the given location.

            if range.location > 0 && mentionEffectiveRange(at: range.location - 1) != nil {
                // There is amention location-1: we reset the attributes (to make sure the inserted text won't look like a mention).
                // We then insert the text ourselves and return false.
                resetTypingAttributesToDefaults()
                textStorage.replaceCharacters(in: range,
                                              with: .init(string: text,
                                                          attributes: defaultTypingAttributes))
                return false
            }

            return true
        }
        
        // There is a mention at the specified location

        if range.location == mentionEffectiveRange.location {
            // We are inserting text right before the mention, we should reset the typicing attributes
            resetTypingAttributesToDefaults()
            return true
        }

        // Make sure we are not selecting only part of the mention
        selectedRange = mentionEffectiveRange

        defer {
            _updateShortcutMatchingState()
        }

        // Returning false here prevents text insertion in the middle of a mention.
        return false
    }
    
    
    /// Clears the text, reset the attributes to the default values.
    internal func resetTextInput() {
        textStorage.replaceCharacters(in: textStorage.fullNSRange,
                                      with: NSAttributedString(string: "", attributes: defaultTypingAttributes))
        resetTypingAttributesToDefaults()
        _updateShortcutMatchingState()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
        layoutIfNeeded()
        delegate?.textViewDidChange?(self)
    }

}

private extension AutoGrowingTextView {
    @objc
    func _innerTextContentsDidChange() {
        invalidateIntrinsicContentSize()
    }
}


extension AutoGrowingTextView: UITextViewDelegate {
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        return _shouldChangeText(in: range, replacementText: text)
    }

    func textViewDidChange(_ textView: UITextView) {
        _updateShortcutMatchingState()
    }
}

// MARK: - Handle pasting of attachments for the draft

extension AutoGrowingTextView {
        
    /// Called when the user performs an action on the text view. If the action is a "paste" and the general pasteboard only contains items (i.e., attachments),
    /// we always accept to show the action. Otherwise, we let our superview decide. In the first case, we handle the actual pasting in the
    /// `override func paste(_ sender: Any?)`
    /// implemented bellow.
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        #if DEBUG
        if action == #selector(UIResponderStandardEditActions.copy(_:)) && hasText {
            return true
        }
        #endif
        if action == #selector(UIResponderStandardEditActions.paste(_:)) && !UIPasteboard.general.hasStrings && !UIPasteboard.general.itemProviders.isEmpty {
            return true
        } else {
            return super.canPerformAction(action, withSender: sender)
        }
    }

    /// When the user performs a "paste" action and the general pasteboard only contains items (i.e., attachments), we transfer the pasted items to our
    /// delegate. Otherwise, we let our superview handle the action.
    override func paste(_ sender: Any?) {
        assert(autoGrowingTextViewDelegate != nil)
        guard !UIPasteboard.general.itemProviders.isEmpty else { return }
        autoGrowingTextViewDelegate?.userPastedItemProviders(in: self, itemProviders: UIPasteboard.general.itemProviders)
    }

    #if DEBUG //allow copying the attributed text for debugging purposes; will need to be refactored to work with `AttributedString` and get a JSON representation, much better for debugging compared to RTF
    override func copy(_ sender: Any?) {
        guard #available(iOS 14, *) else {
            return
        }

        guard let rtfData = try? textStorage.data(from: selectedRange,
                                                  documentAttributes: [.characterEncoding: String.Encoding.utf8.rawValue as NSNumber,
                                                                       .documentType: NSAttributedString.DocumentType.rtf]) else {
            return
        }

        UIPasteboard.general.setItems([
            [UTType.rtf.identifier: rtfData],
            [UTType.utf8PlainText.identifier: textStorage.string.data(using: .utf8) ?? "<FAILED TO SERIALIZE>".data(using: .utf8)!],
            [UTType.utf16PlainText.identifier: textStorage.string.data(using: .utf16) ?? "<FAILED TO SERIALIZE>".data(using: .utf16)!]
        ])
    }
    #endif

}

private extension AutoGrowingTextView {
    typealias TextViewDelegateProxy = AutoGrowingTextViewTextViewDelegateProxy
}
