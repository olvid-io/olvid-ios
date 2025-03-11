/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvPlatformBase
import ObvUI
import ObvUICoreData


protocol TextBubbleDelegate: AnyObject {
    
    var gestureThatLinkTapShouldRequireToFail: UIGestureRecognizer? { get }

    /// Delegation method called whenever a user taps on a user mention within the text
    /// - Parameters:
    ///   - textBubble: An instance of ``TextBubble``.
    ///   - mentionableIdentity: An instance of ``ObvMentionableIdentityAttribute.Value`` that the user tapped.
    func textBubble(_ textBubble: TextBubble, userDidTapOn mentionableIdentity: ObvMentionableIdentityAttribute.Value) async
    
    
    /// Called whenever an URL is interacted with in the ``TextBubble``.
    func textView(_ textBubble: TextBubble, shouldInteractWith URL: URL, interaction: UITextItemInteraction) -> Bool
    
}

/// This view displays the `text` in a bubble. Both the text and bubble color can be specified.
final class TextBubble: ViewForOlvidStack, ViewWithMaskedCorners, ViewWithExpirationIndicator {
        
    
    struct Configuration: Equatable, Hashable {
        enum Kind {
            case sent
            case received
        }
        let kind: Kind
        let attributedText: AttributedString
        let dataDetectorMatches: [ObvDiscussionDataDetected]
        let searchedTextToHighlight: String?
    }
    
    override var isPopable: Bool {
        if let textBubbleText = textToCopy, !textBubbleText.isEmpty {
            return showInStack
        }
        return false
    }
    
    private var currentConfiguration: Configuration?
    
    
    func apply(_ newConfiguration: Configuration) {

        guard currentConfiguration != newConfiguration else { return }
        currentConfiguration = newConfiguration

        let styleAttributedString = newConfiguration.attributedText
            .withStyleAttributes(textColor: textColor, messageDirection: newConfiguration.kind, dataDetectorMatches: newConfiguration.dataDetectorMatches)
            .withHighlightedSearchedText(newConfiguration.searchedTextToHighlight)
        
        let nsAttributedText = (try? NSAttributedString(styleAttributedString, including: \.olvidApp)) ?? NSAttributedString(styleAttributedString)
        
        if self.textView.attributedText != nsAttributedText {
            self.textView.attributedText = nsAttributedText
        }

        // Make sure the tap on links do not interfere with the double tap in the discussion
        // Note that the first time this code is executed, the delegate is nil.
        // But this code will be called again before the cell is actually displayed.
        if let gesture = delegate?.gestureThatLinkTapShouldRequireToFail {
            linkTapGestureOnTextView?.require(toFail: gesture)
        }
    }
    

    var maskedCorner: UIRectCorner {
        get { bubble.maskedCorner }
        set {
            guard bubble.maskedCorner != newValue else { return }
            bubble.maskedCorner = newValue
        }
    }
    

    var textToCopy: String? {
        textView.text
    }


    private let textView = UITextView()
    private let bubble = BubbleView()
    let expirationIndicator = ExpirationIndicatorView()
    let expirationIndicatorSide: ExpirationIndicatorView.Side
    let textColor: UIColor
    let font: UIFont
    
    weak var delegate: TextBubbleDelegate?


    init(expirationIndicatorSide side: ExpirationIndicatorView.Side, bubbleColor: UIColor, textColor: UIColor) {
        
        self.expirationIndicatorSide = side
        self.textColor = textColor
        self.font = UIFont.preferredFont(forTextStyle: .body)
        
        super.init(frame: .zero)
        
        textView.delegate = self
        
        setupInternalViews(bubbleColor: bubbleColor, textColor: textColor)
        
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

    
    private func setupInternalViews(bubbleColor: UIColor, textColor: UIColor) {

        addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.backgroundColor = bubbleColor

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
        textView.textColor = textColor
        textView.linkTextAttributes = [:] // Do not specify any attributes for link, let the attributed string decide

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

    }

}


// MARK: - UITextViewDelegate

extension TextBubble: UITextViewDelegate {
    
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        guard let delegate else { assertionFailure(); return false }
        if let mention = textView.attributedText.findFirstMention(in: characterRange) {
            Task { await delegate.textBubble(self, userDidTapOn: mention) }
            return false
        } else {
            return delegate.textView(self, shouldInteractWith: URL, interaction: interaction)
        }
    }
        
}


// MARK: - Helpers for styling the attributed text displayed by the TextBubble

private extension AttributedString {
    
    /// When the user performs a search in the discussion view, we want to highlight the searched term in the `TextBubble`. This helper method allows to do just that.
    func withHighlightedSearchedText(_ searchedTextToHighlight: String?) -> AttributedString {
        guard let searchedTextToHighlight else { return self }
        guard let rangeToHighlight = self.range(of: searchedTextToHighlight, options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil) else { return self }
        var container = AttributeContainer()
        container.backgroundColor = .systemYellow
        container[keyPath: \.uiKit.foregroundColor] = .black
        var mutableSelf = self
        mutableSelf[rangeToHighlight].mergeAttributes(container)
        return mutableSelf
    }
    
    
    /// The method to call to add all the style attributes to the attributed string displayed in the ``TextBubble``.
    ///
    /// Note that we give a style for links before giving a style for mentions: mentions will be links and will have a style different from the other "standard" links.
    func withStyleAttributes(textColor: UIColor, messageDirection: TextBubble.Configuration.Kind, dataDetectorMatches: [ObvDiscussionDataDetected]) -> AttributedString {
        self.withStyleForEssentialAttributes(textColor: textColor)
            .withStyleForInlinePresentationIntents()
            .withStyleForDataDetected(dataDetectorMatches: dataDetectorMatches, textColor: textColor, messageDirection: messageDirection)
            .withStyleForLinks(textColor: textColor, messageDirection: messageDirection)
            .withStyleForMentions(textColor: textColor, messageDirection: messageDirection)
            .withStyleForListPresentationIntents()
            .withStyleForNonListPresentationIntents()
    }
    
    
    private func withStyleForEssentialAttributes(textColor: UIColor) -> AttributedString {
        var source = self
        source.font = UIFont.preferredFont(forTextStyle: .body)
        source.uiKit.foregroundColor = textColor
        return source
    }
    
    
    private func withStyleForInlinePresentationIntents() -> AttributedString {
        return self.replacingAttributes(attributeContainerForInlinePresentationIntent, with: attributeContainerForInlinePresentationIntent)
    }
    
    
    private func withStyleForLinks(textColor: UIColor, messageDirection: TextBubble.Configuration.Kind) -> AttributedString {
        var source = self
        for (link, range) in source.runs[\.link] {
            guard link != nil else { continue }
            switch messageDirection {
            case .sent:
                source[range].uiKit.foregroundColor = textColor
                source[range].uiKit.underlineColor = textColor
            case .received:
                source[range].uiKit.foregroundColor = .systemBlue
                source[range].uiKit.underlineColor = .systemBlue
            }
            source[range].uiKit.underlineStyle = .single
        }
        return source
    }
    
    
    private func withStyleForDataDetected(dataDetectorMatches: [ObvDiscussionDataDetected], textColor: UIColor, messageDirection: TextBubble.Configuration.Kind) -> AttributedString {
        guard let source = try? NSMutableAttributedString(self, including: \.olvidApp) else { assertionFailure(); return self }
        for match in dataDetectorMatches {
            source.addAttribute(.link, value: match.link, range: match.range)
        }
        return (try? AttributedString(source, including: \.olvidApp)) ?? self // Don't loose any existing attribute
    }
    
    
    /// In addition to give a style to the attributed string, this method also turns mentions into links. This allows the user to tap on them.
    /// The ``TextBubble`` will catch the tap in the ``TextBubble.textView(_:shouldInteractWith:in:interaction:)`` method.
    ///
    /// Note that all the links created must be distinct for this method to work.
    private func withStyleForMentions(textColor: UIColor, messageDirection: TextBubble.Configuration.Kind) -> AttributedString {
        var source = self
        let font: UIFont = .bold(forTextStyle: .body)
        for (counter, (mention, range)) in source.runs[\.mention].enumerated() {
            guard mention != nil else { continue }
            source[range].uiKit.font = font
            switch messageDirection {
            case .sent:
                source[range].uiKit.foregroundColor = textColor
                source[range].uiKit.underlineColor = textColor
            case .received:
                source[range].uiKit.foregroundColor = .systemBlue
                source[range].uiKit.underlineColor = .systemBlue
            }
            var urlComponents = URLComponents()
            urlComponents.scheme = "mention"
            urlComponents.host = "\(counter)"
            assert(urlComponents.url != nil)
            source[range].link = urlComponents.url // Fake URL, allowing the mention to be tapped like a link
        }
        return source
    }

    
    private enum ListIntentType: Hashable {
        case unorderedList(identity: Int)
        case orderedList(identity: Int)
        var identity: Int {
            switch self {
            case .unorderedList(let identity),
                    .orderedList(let identity):
                return identity
            }
        }
    }
    
    
    /// Leverages `NSTextList` to apply appropriate paragraph styles to the sorted and unsorted list presentation intents of the `AttributedString`.
    private func withStyleForListPresentationIntents() -> AttributedString {
        
        var source = self
        
        // Create one NSTextList for each unorderedList/orderedList presentation intent found in the AttributedString.
        // We store these NSTextList instances in a dictionary indexed by the intent's identity, which will allow to find
        // the corresponding NSTextList later.
        
        // Note the special treatment for ordered lists under iOS 16+, where we try to make sure we respect the ordinal chosen by the user.
        // We try to be "smart" about this:
        // - if the numbering specified by the user is a 1., we do nothing
        // - otherwise, we use the number she specified.
        // This allows a user to type a list as
        //
        // 1. item 1
        // 1. item 2
        //
        // and to obtain a result similar to
        //
        // 1. item 1
        // 2. item 2
        //
        // while allowing the user to type
        //
        // 1. item 1
        // some paragraph
        // 2. item 2
        //
        // and to obtain and result that displays the specified list numbers instead of
        //
        // 1. item 1
        // some paragraph
        // 1. item 2
        
        var listsForIntentIdentity = [ListIntentType: NSTextList]()

        for (intentAttribute, _) in source.runs[\.presentationIntent] {
        
            guard let intentAttribute else { continue }
            
            for intentType in intentAttribute.components {
                switch intentType.kind {
                case .unorderedList:
                    if listsForIntentIdentity[.unorderedList(identity: intentType.identity)] == nil {
                        listsForIntentIdentity[.unorderedList(identity: intentType.identity)] = NSTextList(markerFormat: .circle, options: 0)
                    }
                case .orderedList:
                    if listsForIntentIdentity[.orderedList(identity: intentType.identity)] == nil {
                        if #available(iOS 16, *) {
                            if let ordinal = intentAttribute.components.extractFirstListItemOrdinal(), ordinal != 1 {
                                listsForIntentIdentity[.orderedList(identity: intentType.identity)] = NSTextList(markerFormat: NSTextList.MarkerFormat(rawValue: "{decimal}."), startingItemNumber: ordinal)
                            } else {
                                listsForIntentIdentity[.orderedList(identity: intentType.identity)] = NSTextList(markerFormat: NSTextList.MarkerFormat(rawValue: "{decimal}."), options: 0)
                            }
                        } else {
                            listsForIntentIdentity[.orderedList(identity: intentType.identity)] = NSTextList(markerFormat: NSTextList.MarkerFormat(rawValue: "{decimal}."), options: 0)
                        }
                    }
                default:
                    break
                }
            }
            
        }

        // We scan all the unorderedList/orderedList presentation intents a second time.
        // To each intent's range, we associate a list of NSTextList corresponding to that range.
        // The order in the list is important: from outermost to innermost (see `https://developer.apple.com/documentation/uikit/nstextlist`).
        // Note that this is exactly the reverse order in which we ordered the lists in listsForIntentIdentity (we take care of that when setting
        // the `textLists` on the paragraph styles).
        
        var rangesAndLists = [(intentRange: Range<AttributedString.Index>, lists: [NSTextList])]()
        
        for (intentAttribute, intentRange) in source.runs[\.presentationIntent] {
        
            guard let intentAttribute else { continue }
            
            var lists = [NSTextList]()
                        
            for intentType in intentAttribute.components {
                switch intentType.kind {
                case .unorderedList:
                    lists.append(listsForIntentIdentity[.unorderedList(identity: intentType.identity)]!)
                case .orderedList:
                    lists.append(listsForIntentIdentity[.orderedList(identity: intentType.identity)]!)
                default:
                    break
                }
            }
            
            rangesAndLists.append((intentRange, lists))
            
        }

        // Finally, we update the paragraph style of each range by simply specifying all the NSTextList
        // corresponding to each range. TextKit2 does the actual layout.
        
        for (intentRange, textLists) in rangesAndLists {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.textLists = textLists.reversed()
            source[intentRange][keyPath: \.paragraphStyle] = paragraphStyle
        }
        
        return source
        
    }
    
    
    private func withStyleForNonListPresentationIntents() -> AttributedString {
        
        var source = self
        
        for (intentAttribute, intentRange) in source.runs[\.presentationIntent] {
            
            guard let intentAttribute else { continue }

            for itentType in intentAttribute.components {
                
                switch itentType.kind {
                    
                case .header(level: let level):
                    let fontDescriptor = Self.fontDescriptorForTitle(level: level)
                    source[intentRange].font = UIFont(descriptor: fontDescriptor, size: 0.0)
                    switch level {
                    case 1:
                        source[intentRange][keyPath: \.paragraphStyle] = paragraphStyleForHeaderLevel1
                    case 2:
                        source[intentRange][keyPath: \.paragraphStyle] = paragraphStyleForHeaderLevel2
                    default:
                        source[intentRange][keyPath: \.paragraphStyle] = paragraphStyleForHeaderLevel3
                    }

                default:
                    break

                }

            }
                        
        }

        return source
        
    }
    

    /// The ``AttributeContainer`` used to give a style to the inline attributes (`.emphasized`, `.stronglyEmphasized`, etc.) of attributed text displayed by this view.
    private var attributeContainerForInlinePresentationIntent: AttributeContainer {
        
        var attributeContainer = AttributeContainer()
        
        let inlineIntentsToStyle: [InlinePresentationIntent] = [.emphasized, .stronglyEmphasized, .strikethrough]

        for inlineIntent in inlineIntentsToStyle {
            
            attributeContainer.inlinePresentationIntent = inlineIntent

            switch inlineIntent {
            case .emphasized:
                attributeContainer.font = .italic(forTextStyle: .body)
            case .stronglyEmphasized:
                attributeContainer.font = .bold(forTextStyle: .body)
            case .strikethrough:
                attributeContainer.strikethroughStyle = .single
            default:
                assertionFailure("We should style this InlinePresentationIntent as it is part of inlineIntentsToStyle")
            }
            
        }

        return attributeContainer
        
    }

    
    private static func fontDescriptorForTitle(level: Int) -> UIFontDescriptor {
        switch level {
        case 1:
            return .preferredFontDescriptor(withTextStyle: .title2).withSymbolicTraits(.traitBold) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title2)
        case 2:
            return .preferredFontDescriptor(withTextStyle: .title3).withSymbolicTraits(.traitBold) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title3)
        case 3:
            return .preferredFontDescriptor(withTextStyle: .subheadline).withSymbolicTraits(.traitBold) ?? UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
        default:
            return .preferredFontDescriptor(withTextStyle: .subheadline)
        }
    }

    
    private var paragraphStyleForHeaderLevel1: NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        let pointSize = Self.fontDescriptorForTitle(level: 1).pointSize
        paragraphStyle.paragraphSpacingBefore = pointSize * 1.0
        return paragraphStyle
    }

    
    private var paragraphStyleForHeaderLevel2: NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        let pointSize = Self.fontDescriptorForTitle(level: 2).pointSize
        paragraphStyle.paragraphSpacingBefore = pointSize * 0.75
        return paragraphStyle
    }

    
    private var paragraphStyleForHeaderLevel3: NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        let pointSize = Self.fontDescriptorForTitle(level: 3).pointSize
        paragraphStyle.paragraphSpacingBefore = pointSize * 0.5
        return paragraphStyle
    }

}


// MARK: - Finding a mention in an NSAttributedString

private extension NSAttributedString {
    
    func findFirstMention(in characterRange: NSRange) -> ObvMentionableIdentityAttribute.Value? {
        
        var mentionFound: ObvMentionableIdentityAttribute.Value?
        
        self.enumerateAttributes(in: characterRange) { attributes, range, _ in
            if let mention = attributes[.mention] as? ObvMentionableIdentityAttribute.Value {
                mentionFound = mention
                return
            }
        }

        return mentionFound
        
    }
    
}


private extension [PresentationIntent.IntentType] {
    
    func extractFirstListItemOrdinal() -> Int? {
        for intentType in self {
            switch intentType.kind {
            case .listItem(ordinal: let ordinal):
                return ordinal
            default:
                continue
            }
        }
        return nil
    }
    
}
