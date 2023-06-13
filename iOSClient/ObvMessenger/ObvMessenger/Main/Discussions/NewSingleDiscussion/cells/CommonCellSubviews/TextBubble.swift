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
import Platform_Base
import ObvUI
import ObvUICoreData
import Discussions_Mentions_TextBubbleBuilder

protocol TextBubbleDelegate: AnyObject {
    
    var gestureThatLinkTapShouldRequireToFail: UIGestureRecognizer? { get }

    /// Delegation method called whenever a user taps on a user mention within the text
    /// - Parameters:
    ///   - textBubble: An instance of ``TextBubble``
    ///   - mentionableIdentity: An instance of ``MentionableIdentity`` that the user tapped
    func textBubble(_ textBubble: TextBubble, userDidTapOn mentionableIdentity: MentionableIdentity)
    
}

/// This view displays the `text` in a bubble. Both the text and bubble color can be specified.
final class TextBubble: ViewForOlvidStack, ViewWithMaskedCorners, ViewWithExpirationIndicator {
        
    struct Configuration: Equatable, Hashable {
        /// Denotes the kind of a bubble this represents
        ///
        /// - `sent`: A message the user sent
        /// - `received`: A message the user received
        enum Kind {
            /// A message the user sent
            case sent

            /// A message the user received
            case received
        }

        let kind: Kind
        let text: String?
        let dataDetectorTypes: UIDataDetectorTypes
        let mentionedUsers: MentionableIdentityTypes.MentionableIdentityFromRange
        /// This item exists to provide an abstract container for our `Hashable` conformance since `mentionedUsers` is not directly hashable. As a workaround, `AnyHashable` is used to provide `Hashable` conformance
        private let mappedMentionedUsers: [Range<String.Index>: AnyHashable]

        init(kind: TextBubble.Configuration.Kind, text: String? = nil, dataDetectorTypes: UIDataDetectorTypes, mentionedUsers: MentionableIdentityTypes.MentionableIdentityFromRange) {
            self.kind = kind
            self.text = text
            self.dataDetectorTypes = dataDetectorTypes
            self.mentionedUsers = mentionedUsers

            mappedMentionedUsers = mentionedUsers.reduce(into: [:]) { accumulator, item in
                accumulator[item.key] = AnyHashable(item.value)
            }
        }

        static func == (lhs: TextBubble.Configuration, rhs: TextBubble.Configuration) -> Bool {
            guard lhs.kind == rhs.kind else {
                return false
            }

            guard lhs.text == rhs.text else {
                return false
            }

            guard lhs.dataDetectorTypes == rhs.dataDetectorTypes else {
                return false
            }

            guard lhs.mappedMentionedUsers == rhs.mappedMentionedUsers else {
                return false
            }

            return true
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(kind)
            hasher.combine(text)
            hasher.combine(dataDetectorTypes)
            hasher.combine(mappedMentionedUsers)
        }
    }
    
    private var currentConfiguration: Configuration?
    
    func apply(_ newConfiguration: Configuration) {
        guard currentConfiguration != newConfiguration else { return }
        currentConfiguration = newConfiguration
        if self.textView.dataDetectorTypes != newConfiguration.dataDetectorTypes {
            self.textView.dataDetectorTypes = newConfiguration.dataDetectorTypes
        }

        if let text = newConfiguration.text {
            let attributedString = MentionsTextBubbleAttributedStringBuilder.generateAttributedString(from: text,
                                                                                                      messageKind: .init(newConfiguration.kind),
                                                                                                      mentionedUsers: newConfiguration.mentionedUsers,
                                                                                                      baseAttributes: [.font: font,
                                                                                                                       .foregroundColor: textColor])

            textView.attributedText = attributedString
        }
        
        // Make sure the tap on links do not interfere with the double tap in the discussion
        // Note that the first time this code is executed, the delegate is nil.
        // But this code will be called again before the cell is actually displayed.
        if let gesture = delegate?.gestureThatLinkTapShouldRequireToFail {
            linkTapGestureOnTextView?.require(toFail: gesture)
        }
    }
    
    private(set) var text: String? {
        get { textView.text }
        set {
            guard textView.text != newValue else { return }
            textView.text = newValue
        }
    }
    
    private var bubbleColor: UIColor? {
        get { bubble.backgroundColor }
        set {
            guard bubble.backgroundColor != newValue else { return }
            bubble.backgroundColor = newValue
        }
    }
    
    var maskedCorner: UIRectCorner {
        get { bubble.maskedCorner }
        set {
            guard bubble.maskedCorner != newValue else { return }
            bubble.maskedCorner = newValue
        }
    }
    
    private var textAlignment: NSTextAlignment {
        get { textView.textAlignment }
        set {
            guard textView.textAlignment != newValue else { return }
            textView.textAlignment = newValue
        }
    }
    
    private let textView = UITextView()
    private let bubble = BubbleView()
    let expirationIndicator = ExpirationIndicatorView()
    let expirationIndicatorSide: ExpirationIndicatorView.Side
    let textColor: UIColor
    let font: UIFont
    
    weak var delegate: TextBubbleDelegate?

    private lazy var userMentionTapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(_handleOpenUserProfileTapGestureRecognizer))..{
        $0.delegate = self
    }

    init(expirationIndicatorSide side: ExpirationIndicatorView.Side, bubbleColor: UIColor, textColor: UIColor) {
        self.expirationIndicatorSide = side
        self.textColor = textColor
        font = UIFont.preferredFont(forTextStyle: .body)
        super.init(frame: .zero)
        self.bubbleColor = bubbleColor
        textView.textColor = textColor
        textView.linkTextAttributes = [.foregroundColor: textColor,
                                       .underlineStyle: NSUnderlineStyle.single.rawValue,
                                       .underlineColor: textColor]

        setupInternalViews()
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    private var doubleTapGesturesOnTextView: [UITapGestureRecognizer] {
        (textView.gestureRecognizers ?? []).compactMap { $0 as? UITapGestureRecognizer }.filter({ $0.numberOfTapsRequired == 2 })
    }

    
    private var singeTapGesturesOnTextView: [UITapGestureRecognizer] {
        (textView.gestureRecognizers ?? []).compactMap { $0 as? UITapGestureRecognizer }.filter({ $0.numberOfTapsRequired == 1 })
    }
    
    
    private var linkTapGestureOnTextView: UITapGestureRecognizer? {
        singeTapGesturesOnTextView.first(where: { $0.name == "UITextInteractionNameLinkTap" })
    }

    
    private func setupInternalViews() {

        addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(expirationIndicator)
        expirationIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        bubble.addSubview(textView)
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets.zero
        textView.isEditable = false
        textView.isSelectable = true // Must be set to `true` for the data detector to work
        textView.adjustsFontForContentSizeCategory = true
        // Since we need to set isSelectable to true, and since we have a double tap on the cell for reactions, we disable tap gestures on the text, except the one for tapping links.
        doubleTapGesturesOnTextView.forEach({ $0.isEnabled = false })
        singeTapGesturesOnTextView.forEach({ $0.isEnabled = false })
        linkTapGestureOnTextView?.isEnabled = true

        let verticalInset = MessageCellConstants.bubbleVerticalInset
        let horizontalInsets = MessageCellConstants.bubbleHorizontalInsets
        
        let constraints = [
            bubble.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            bubble.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: self.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: horizontalInsets),
            textView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -horizontalInsets),
            textView.topAnchor.constraint(equalTo: bubble.topAnchor, constant: verticalInset),
            textView.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -verticalInset),
            textView.widthAnchor.constraint(equalTo: bubble.widthAnchor, constant: -horizontalInsets * 2),
        ]
        
        constraints.forEach { $0.priority -= 1 }
        NSLayoutConstraint.activate(constraints)
        
        textView.setContentCompressionResistancePriority(.required, for: .vertical)

        setupConstraintsForExpirationIndicator(gap: MessageCellConstants.gapBetweenExpirationViewAndBubble)

        textView.addGestureRecognizer(userMentionTapGestureRecognizer)
    }

    @objc
    private func _handleOpenUserProfileTapGestureRecognizer(_ tapGestureRecognizer: UITapGestureRecognizer) {
        guard tapGestureRecognizer.state == .ended else {
            return
        }

        let mentionableIdentity = textView.userIdentity(for: tapGestureRecognizer.location(in: textView))!

        delegate?.textBubble(self, userDidTapOn: mentionableIdentity)
    }
}

extension UIDataDetectorTypes: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.rawValue)
    }
    
}

extension TextBubble: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === userMentionTapGestureRecognizer else {
            assertionFailure("unknown gesture recognizer; returning true")
            return true
        }

        return textView.userIdentity(for: touch.location(in: textView)) != nil
    }
}

private extension UITextView {
    func userIdentity(for point: CGPoint) -> MentionableIdentity? {
        return _textkit1_userIdentity(for: point)
    }

    @available(iOS, deprecated: 15, message: "Please remove me and use the TextKit 2 implementation")
    private func _textkit1_userIdentity(for point: CGPoint) -> MentionableIdentity? {
        let glyphIndex = layoutManager.glyphIndex(for: point, in: textContainer)

        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

        guard characterIndex < textStorage.length else {
            assert(false, "we're out of bounds")

            return nil
        }

        return textStorage.attribute(.mentionableIdentity, at: characterIndex, effectiveRange: nil) as? MentionableIdentity
    }
}

private extension MentionsTextBubbleAttributedStringBuilder.MessageKind {
    init(_ messageKind: TextBubble.Configuration.Kind) {
        switch messageKind {
        case .sent:
            self = .sent

        case .received:
            self = .received
        }
    }
}
