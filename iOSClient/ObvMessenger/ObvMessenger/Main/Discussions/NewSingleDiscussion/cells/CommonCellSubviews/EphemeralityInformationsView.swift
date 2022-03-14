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




final class EphemeralityInformationsView: ViewForOlvidStack {
    
    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }
        
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func hide() {
        self.configure(readOnce: false, visibilityDuration: nil)
    }
    
    func configure(readOnce: Bool, visibilityDuration: TimeInterval?) {
        var showInUpperStack = readOnce
        readOnceLabel.showInStack = readOnce
        if let visibilityDuration = visibilityDuration {
            visibilityLabel.showInStack = true
            visibilityLabel.text = durationFormatter.string(from: visibilityDuration)
            showInUpperStack = true
        } else {
            visibilityLabel.showInStack = false
        }
        self.showInStack = showInUpperStack
    }
    
    private let durationFormatter = DurationFormatter()

    private let backgroundBubble = UIView()
    private let bubble = UIView()
    private let stack = OlvidHorizontalStackView(gap: 8.0, side: .bothSides, debugName: "Horizontal stack for EphemeralityInformationsView", showInStack: true)
    private let readOnceLabel = ImageAndLabelView(imageSystemIcon: .flameFill, showLabel: false)
    private let visibilityLabel = ImageAndLabelView(imageSystemIcon: .eyes, showLabel: true)

    
    private func setupInternalViews() {
        
        addSubview(backgroundBubble)
        backgroundBubble.translatesAutoresizingMaskIntoConstraints = false
        backgroundBubble.backgroundColor = .systemBackground
        backgroundBubble.layer.cornerRadius = MessageCellConstants.cornerRadiusForInformationsViews
        
        backgroundBubble.addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.backgroundColor = .systemFill // UIColor(named: "ReceivedMessageOverlay")
        bubble.layer.cornerRadius = MessageCellConstants.cornerRadiusForInformationsViews

        bubble.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(readOnceLabel)
        readOnceLabel.translatesAutoresizingMaskIntoConstraints = false
        
        stack.addArrangedSubview(visibilityLabel)
        visibilityLabel.translatesAutoresizingMaskIntoConstraints = false
                
        let constraints = [
            backgroundBubble.topAnchor.constraint(equalTo: self.topAnchor, constant: -12),
            backgroundBubble.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            backgroundBubble.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            backgroundBubble.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 4),
            bubble.topAnchor.constraint(equalTo: backgroundBubble.topAnchor, constant: 2),
            bubble.trailingAnchor.constraint(equalTo: backgroundBubble.trailingAnchor, constant: -2),
            bubble.bottomAnchor.constraint(equalTo: backgroundBubble.bottomAnchor, constant: -2),
            bubble.leadingAnchor.constraint(equalTo: backgroundBubble.leadingAnchor, constant: 2),
            stack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -6),
            stack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 6),
        ]
        NSLayoutConstraint.activate(constraints)

    }
    
}




final fileprivate class ImageAndLabelView: ViewForOlvidStack {
    
    private let label = UILabel()
    private let imageView = UIImageView()
    private let imageSystemIcon: ObvSystemIcon
    private let showLabel: Bool
    
    var text: String? {
        get { label.text }
        set { label.text = newValue }
    }
    
    init(imageSystemIcon: ObvSystemIcon, showLabel: Bool) {
        self.imageSystemIcon = imageSystemIcon
        self.showLabel = showLabel
        super.init(frame: .zero)
        setupInternalViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var imageViewTrailingAnchor: NSLayoutConstraint?
    
    private func setupInternalViews() {
        
        addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let symbolConfiguration = UIImage.SymbolConfiguration(font: UIFont.preferredFont(forTextStyle: .caption1))
        let image = UIImage(systemIcon: imageSystemIcon, withConfiguration: symbolConfiguration)
        imageView.image = image
        imageView.tintColor = .secondaryLabel
        imageView.contentMode = .scaleAspectFill
        
        if showLabel {
            addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = UIFont.preferredFont(forTextStyle: .caption1)
            label.textColor = .secondaryLabel
        }
        
        if showLabel {
            
            let constraints = [
                imageView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                imageView.trailingAnchor.constraint(equalTo: label.leadingAnchor, constant: -2.0),
                imageView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                
                label.topAnchor.constraint(equalTo: self.topAnchor),
                label.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                label.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            ]
            NSLayoutConstraint.activate(constraints)
            
        } else {
            
            let constraints = [
                imageView.topAnchor.constraint(equalTo: self.topAnchor),
                imageView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
                imageView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            ]
            NSLayoutConstraint.activate(constraints)

            
        }
        
    }
}
