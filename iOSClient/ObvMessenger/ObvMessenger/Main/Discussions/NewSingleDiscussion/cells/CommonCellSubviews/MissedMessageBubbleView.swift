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

/// This view displays the count of missed message.
final class MissedMessageBubble: ViewForOlvidStack, ViewWithMaskedCorners, UIViewWithTappableStuff {

    struct Configuration: Equatable, Hashable {
        let missedMessageCount: Int
    }

    private var currentConfiguration: Configuration?

    func apply(_ newConfiguration: Configuration) {
        guard currentConfiguration != newConfiguration else { return }
        currentConfiguration = newConfiguration
        assert(newConfiguration.missedMessageCount > 0)
        let missedMessageText = String.localizedStringWithFormat(NSLocalizedString("missed messages count", comment: ""), newConfiguration.missedMessageCount)
        if self.text != missedMessageText {
            self.text = missedMessageText
        }
    }

    private(set) var text: String? {
        get { label.text }
        set {
            guard label.text != newValue else { return }
            label.text = newValue
        }
    }

    var maskedCorner: UIRectCorner {
        get { bubble.maskedCorner }
        set {
            guard bubble.maskedCorner != newValue else { return }
            bubble.maskedCorner = newValue
        }
    }

    private let label = UITextView()
    private let bubble = BubbleView()
    private let imageView = UIImageView()

    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }


    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    func tappedStuff(tapGestureRecognizer: UITapGestureRecognizer, acceptTapOutsideBounds: Bool) -> TappedStuffForCell? {
        guard self.bounds.contains(tapGestureRecognizer.location(in: self)) else { return nil }
        guard !self.isHidden && self.showInStack else { return nil }
        return .missedMessageBubble
    }
    
    
    private func setupInternalViews() {

        addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.backgroundColor = AppTheme.shared.colorScheme.newReceivedCellBackground.withAlphaComponent(0.5)
        
        bubble.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        if let newDescriptor = label.font?.fontDescriptor.withSymbolicTraits(.traitItalic) {
            label.font = UIFont(descriptor: newDescriptor, size: 0) // 0 means keep existing size
        }
        label.isScrollEnabled = false
        label.backgroundColor = .clear
        label.textContainerInset = UIEdgeInsets.zero
        label.isEditable = false
        label.textColor = UIColor.label.withAlphaComponent(0.5)
        label.isUserInteractionEnabled = false
        
        bubble.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(textStyle: .footnote)
        imageView.image = UIImage(systemIcon: .handTap, withConfiguration: config)
        imageView.tintColor = UIColor.label.withAlphaComponent(0.5)

        let verticalInset = MessageCellConstants.bubbleVerticalInset
        let horizontalInsets = MessageCellConstants.bubbleHorizontalInsets

        let constraints = [
            
            bubble.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            bubble.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: self.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: horizontalInsets),
            label.trailingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: -horizontalInsets/2),
            label.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),

            imageView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -horizontalInsets),
            imageView.firstBaselineAnchor.constraint(equalTo: label.lastBaselineAnchor),
            imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor),
            
            bubble.heightAnchor.constraint(greaterThanOrEqualTo: label.heightAnchor, constant: 2*verticalInset),
            bubble.heightAnchor.constraint(greaterThanOrEqualTo: imageView.heightAnchor, constant: 2*verticalInset),

        ]
        NSLayoutConstraint.activate(constraints)

    }

}
