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


/// This view displays the `text` in a bubble. Both the text and bubble color can be specified.
final class TextBubble: ViewForOlvidStack, ViewWithMaskedCorners, ViewWithExpirationIndicator {
        
    struct Configuration: Equatable, Hashable {
        let text: String?
        let dataDetectorTypes: UIDataDetectorTypes
    }
    
    private var currentConfiguration: Configuration?
    
    func apply(_ newConfiguration: Configuration) {
        guard currentConfiguration != newConfiguration else { return }
        currentConfiguration = newConfiguration
        if self.label.dataDetectorTypes != newConfiguration.dataDetectorTypes {
            self.label.dataDetectorTypes = newConfiguration.dataDetectorTypes
        }
        if self.text != newConfiguration.text {
            self.text = newConfiguration.text
        }
    }
    
    private(set) var text: String? {
        get { label.text }
        set {
            guard label.text != newValue else { return }
            label.text = newValue
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
        get { label.textAlignment }
        set {
            guard label.textAlignment != newValue else { return }
            label.textAlignment = newValue
        }
    }
    
    private let label = UITextView()
    private let bubble = BubbleView()
    let expirationIndicator = ExpirationIndicatorView()
    let expirationIndicatorSide: ExpirationIndicatorView.Side
    
    init(expirationIndicatorSide side: ExpirationIndicatorView.Side, bubbleColor: UIColor, textColor: UIColor) {
        self.expirationIndicatorSide = side
        super.init(frame: .zero)
        self.bubbleColor = bubbleColor
        label.textColor = textColor
        label.linkTextAttributes = [NSAttributedString.Key.foregroundColor: textColor,
                                    NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue,
                                    NSAttributedString.Key.underlineColor: textColor]
        setupInternalViews()
    }
    

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    private func setupInternalViews() {

        addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(expirationIndicator)
        expirationIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        bubble.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.isScrollEnabled = false
        label.backgroundColor = .clear
        label.textContainerInset = UIEdgeInsets.zero
        label.isEditable = false
        label.isSelectable = false
        
        let verticalInset = MessageCellConstants.bubbleVerticalInset
        let horizontalInsets = MessageCellConstants.bubbleHorizontalInsets
        
        let constraints = [
            bubble.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            bubble.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: self.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: horizontalInsets),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -horizontalInsets),
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: verticalInset),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -verticalInset),
            label.widthAnchor.constraint(equalTo: bubble.widthAnchor, constant: -horizontalInsets * 2),
        ]
        
        constraints.forEach { $0.priority -= 1 }
        NSLayoutConstraint.activate(constraints)
        
        label.setContentCompressionResistancePriority(.required, for: .vertical)

        setupConstraintsForExpirationIndicator(gap: MessageCellConstants.gapBetweenExpirationViewAndBubble)

    }
    
}

extension UIDataDetectorTypes: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.rawValue)
    }
    
}
