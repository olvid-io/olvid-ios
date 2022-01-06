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
import CoreData

@available(iOS 14.0, *)
final class TapToReadBubble: ViewForOlvidStack, ViewWithMaskedCorners, ViewWithExpirationIndicator {
    
    var tapToReadLabelTextColor: UIColor? {
        get { tapToReadLabel.textColor }
        set {
            tapToReadLabel.textColor = newValue
            icon.tintColor = newValue
        }
    }

    var bubbleColor: UIColor? {
        get { bubble.backgroundColor }
        set { bubble.backgroundColor = newValue }
    }
    
    
    var maskedCorner: UIRectCorner {
        get { bubble.maskedCorner }
        set { bubble.maskedCorner = newValue }
    }

    var messageObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>?
    
    private let icon = UIImageViewForOlvidStack()
    private let tapToReadLabel = UILabelForOlvidStack()
    private let bubble = BubbleView()
    let expirationIndicator = ExpirationIndicatorView()
    let expirationIndicatorSide: ExpirationIndicatorView.Side
    private let verticalStack = OlvidVerticalStackView(gap: 8.0, side: .leading, debugName: "Main vertical stack for TapToReadBubble view", showInStack: true)
    private let horizontalStack = OlvidHorizontalStackView(gap: 8.0, side: .bothSides, debugName: "First horizontal stack for TapToReadBubble view", showInStack: true)
    
    private let durationFormatter = DurationFormatter()

    init(expirationIndicatorSide side: ExpirationIndicatorView.Side) {
        self.expirationIndicatorSide = side
        super.init(frame: .zero)
        setupInternalViews()
        observeUserTaps()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupInternalViews() {
        
        addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false

        addSubview(expirationIndicator)
        expirationIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        bubble.addSubview(verticalStack)
        verticalStack.translatesAutoresizingMaskIntoConstraints = false
        
        verticalStack.addArrangedSubview(horizontalStack)
        horizontalStack.translatesAutoresizingMaskIntoConstraints = false
        
        horizontalStack.addArrangedSubview(icon)
        icon.translatesAutoresizingMaskIntoConstraints = false
        let configuration = UIImage.SymbolConfiguration(font: UIFont.preferredFont(forTextStyle: .body))
        let image = UIImage(systemIcon: .handTap, withConfiguration: configuration)
        icon.image = image
        icon.tintColor = .label
        
        horizontalStack.addArrangedSubview(tapToReadLabel)
        tapToReadLabel.translatesAutoresizingMaskIntoConstraints = false
        let systemFont = UIFont.preferredFont(forTextStyle: .body)
        if let descriptor = systemFont.fontDescriptor.withSymbolicTraits(.traitItalic) {
            tapToReadLabel.font = UIFont(descriptor: descriptor, size: 0)
        } else {
            tapToReadLabel.font = systemFont
        }
        tapToReadLabel.text = NSLocalizedString("Tap to see the message", comment: "")

        let verticalInset = CGFloat(10)
        let horizontalInsets = CGFloat(16)

        let constraints = [
            bubble.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            bubble.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: self.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: self.bottomAnchor),

            verticalStack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: verticalInset),
            verticalStack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -horizontalInsets),
            verticalStack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -verticalInset),
            verticalStack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: horizontalInsets),
            
            bubble.widthAnchor.constraint(greaterThanOrEqualTo: horizontalStack.widthAnchor, constant: 2*horizontalInsets),
        ]
        constraints.forEach { $0.priority -= 1 }
        NSLayoutConstraint.activate(constraints)
        
        // Contraints with small priorty allowing to prevent ambiguous contraints issues
        do {
            let widthConstraints = [
                verticalStack.widthAnchor.constraint(equalToConstant: 1),
                bubble.widthAnchor.constraint(equalToConstant: 1),
            ]
            widthConstraints.forEach({ $0.priority = .defaultLow })
            NSLayoutConstraint.activate(widthConstraints)
        }

        setupConstraintsForExpirationIndicator(gap: MessageCellConstants.gapBetweenExpirationViewAndBubble)
        
    }
    
    private func observeUserTaps() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(userDidTap))
        self.addGestureRecognizer(tap)
    }
    
    @objc func userDidTap() {
        guard let messageObjectID = self.messageObjectID else { assertionFailure(); return }
        ObvMessengerInternalNotification.userWantsToReadReceivedMessagesThatRequiresUserAction(persistedMessageObjectIDs: Set([messageObjectID]))
            .postOnDispatchQueue()
    }
}



@available(iOS 14.0, *)
final class TapToReadView: UIView {
    
    var tapToReadLabelTextColor: UIColor? {
        get { tapToReadLabel.textColor }
        set {
            tapToReadLabel.textColor = newValue
            icon.tintColor = newValue
        }
    }

    var messageObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>?
    
    private let icon = UIImageViewForOlvidStack()
    private let tapToReadLabel = UILabelForOlvidStack()
    private let horizontalStack = OlvidHorizontalStackView(gap: 2.0, side: .bothSides, debugName: "First horizontal stack for TapToReadView", showInStack: true)

    private let durationFormatter = DurationFormatter()
    private let showText: Bool

    init(showText: Bool = true) {
        self.showText = showText
        super.init(frame: .zero)
        setupInternalViews()
        observeUserTaps()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupInternalViews() {
        
        addSubview(horizontalStack)
        horizontalStack.translatesAutoresizingMaskIntoConstraints = false
        
        horizontalStack.addArrangedSubview(icon)
        icon.translatesAutoresizingMaskIntoConstraints = false
        let configuration = UIImage.SymbolConfiguration(font: UIFont.preferredFont(forTextStyle: .body))
        let image = UIImage(systemIcon: .handTap, withConfiguration: configuration)
        icon.image = image
        icon.tintColor = .white
        icon.contentMode = .center
        
        if showText {
            horizontalStack.addArrangedSubview(tapToReadLabel)
            tapToReadLabel.translatesAutoresizingMaskIntoConstraints = false
            let systemFont = UIFont.preferredFont(forTextStyle: .body)
            if let descriptor = systemFont.fontDescriptor.withSymbolicTraits(.traitItalic) {
                tapToReadLabel.font = UIFont(descriptor: descriptor, size: 0)
            } else {
                tapToReadLabel.font = systemFont
            }
            tapToReadLabel.text = NSLocalizedString("Tap to see the message", comment: "")
        }

        let constraints = [
            horizontalStack.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            horizontalStack.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            horizontalStack.topAnchor.constraint(equalTo: self.topAnchor),
            horizontalStack.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ]
        NSLayoutConstraint.activate(constraints)
        
    }
    
    private func observeUserTaps() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(userDidTap))
        self.addGestureRecognizer(tap)
    }
    
    @objc func userDidTap() {
        guard let messageObjectID = self.messageObjectID else { assertionFailure(); return }
        ObvMessengerInternalNotification.userWantsToReadReceivedMessagesThatRequiresUserAction(persistedMessageObjectIDs: Set([messageObjectID]))
            .postOnDispatchQueue()
    }

}
