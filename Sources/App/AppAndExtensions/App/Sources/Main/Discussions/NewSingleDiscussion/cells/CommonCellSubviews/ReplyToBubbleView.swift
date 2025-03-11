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
import QuickLookThumbnailing
import ObvUICoreData


@available(iOS 14.0, *)
final class ReplyToBubbleView: ViewForOlvidStack, ViewWithMaskedCorners, ViewWithExpirationIndicator, UIViewWithTappableStuff {
    
    override var isPopable: Bool { return false }
    
    enum Configuration: Equatable, Hashable {
        case loading
        case messageWasDeleted
        case remotelyWiped(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, deleterName: String?, bodyColor: UIColor, name: String?, nameColor: UIColor?, lineColor: UIColor?, bubbleColor: UIColor?, showThumbnail: Bool, hardlink: HardLinkToFyle?, thumbnail: UIImage?)
        case loaded(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, body: String?, bodyColor: UIColor, name: String?, nameColor: UIColor?, lineColor: UIColor?, bubbleColor: UIColor?, showThumbnail: Bool, hardlink: HardLinkToFyle?, thumbnail: UIImage?)
        
        var messageObjectID: NSManagedObjectID? {
            switch self {
            case .loading, .messageWasDeleted:
                return nil
            case .loaded(messageObjectID: let messageObjectID, body: _, bodyColor: _, name: _, nameColor: _, lineColor: _, bubbleColor: _, showThumbnail: _, hardlink: _, thumbnail: _):
                return messageObjectID.objectID
            case .remotelyWiped(messageObjectID: let messageObjectID, deleterName: _, bodyColor: _, name: _, nameColor: _, lineColor: _, bubbleColor: _, showThumbnail: _, hardlink: _, thumbnail: _):
                return messageObjectID.objectID
            }
        }
        
        func replaceHardLink(with hardlink: HardLinkToFyle) -> Configuration {
            switch self {
            case .loading, .messageWasDeleted, .remotelyWiped:
                assertionFailure()
                return self
            case .loaded(messageObjectID: let messageObjectID, body: let body, bodyColor: let bodyColor, name: let name, nameColor: let nameColor, lineColor: let lineColor, bubbleColor: let bubbleColor, showThumbnail: let showThumbnail, hardlink: let previousHardlink, thumbnail: let thumbnail):
                assert(previousHardlink == nil)
                assert(showThumbnail)
                return .loaded(
                    messageObjectID: messageObjectID,
                    body: body,
                    bodyColor: bodyColor,
                    name: name,
                    nameColor: nameColor,
                    lineColor: lineColor,
                    bubbleColor: bubbleColor,
                    showThumbnail: showThumbnail,
                    hardlink: hardlink,
                    thumbnail: thumbnail)
            }
        }
        
        func replaceThumbnail(with thumbnail: UIImage) -> Configuration {
            switch self {
            case .loading, .messageWasDeleted, .remotelyWiped:
                assertionFailure()
                return self
            case .loaded(messageObjectID: let messageObjectID, body: let body, bodyColor: let bodyColor, name: let name, nameColor: let nameColor, lineColor: let lineColor, bubbleColor: let bubbleColor, showThumbnail: let showThumbnail, hardlink: let hardlink, thumbnail: let previousThumbnail):
                assert(previousThumbnail == nil)
                return .loaded(
                    messageObjectID: messageObjectID,
                    body: body,
                    bodyColor: bodyColor,
                    name: name,
                    nameColor: nameColor,
                    lineColor: lineColor,
                    bubbleColor: bubbleColor,
                    showThumbnail: showThumbnail,
                    hardlink: hardlink,
                    thumbnail: thumbnail)
            }
        }

    }
    
    private var currentConfiguration: Configuration?
    
    func configure(with newConfiguration: Configuration) {
        guard self.currentConfiguration != newConfiguration else { return }
        self.currentConfiguration = newConfiguration
        refresh()
    }
    
    
    private var constraintsToActivate = Set<NSLayoutConstraint>()
    private var constraintsToDeactivate = Set<NSLayoutConstraint>()
    
    private func refresh() {
        guard let config = self.currentConfiguration else { assertionFailure(); return }
        
        switch config {
        case .loading:
            bodyLabel.text = Self.Strings.replyToMessageUnavailable
            bodyLabel.textColor = UIColor.secondaryLabel
            bodyLabel.showInStack = true
            nameLabel.text = nil
            nameLabel.textColor = .white
            nameLabel.showInStack = false
            line.backgroundColor = .systemFill
            bubble.backgroundColor = appTheme.colorScheme.newReceivedCellReplyToBackground
            imageView.reset()
            imageView.showInStack = false
        case .messageWasDeleted:
            bodyLabel.text = Self.Strings.replyToMessageWasDeleted
            bodyLabel.textColor = UIColor.secondaryLabel
            bodyLabel.showInStack = true
            nameLabel.text = nil
            nameLabel.textColor = .white
            nameLabel.showInStack = false
            line.backgroundColor = .systemFill
            bubble.backgroundColor = appTheme.colorScheme.newReceivedCellReplyToBackground
            imageView.reset()
            imageView.showInStack = false
        case .remotelyWiped(messageObjectID: _, deleterName: let deleterName, bodyColor: let bodyColor, name: let name, nameColor: let nameColor, lineColor: let lineColor, bubbleColor: let bubbleColor, showThumbnail: let showThumbnail, hardlink: let hardlink, thumbnail: let thumbnail):
            let body = Strings.remotelyWiped(deleterName: deleterName)
            if bodyLabel.text != body {
                bodyLabel.text = body
            }
            bodyLabel.textColor = bodyColor
            bodyLabel.showInStack = (bodyLabel.text != nil)
            if nameLabel.text != name {
                nameLabel.text = name
            }
            nameLabel.textColor = nameColor ?? .white
            nameLabel.showInStack = true
            line.backgroundColor = lineColor ?? .systemFill
            bubble.backgroundColor = bubbleColor ?? appTheme.colorScheme.newReceivedCellReplyToBackground
            if showThumbnail {
                imageView.backgroundColor = appTheme.colorScheme.systemFill
                imageView.showInStack = true
                if let hardlink = hardlink {
                    imageView.setHardlink(newHardlink: hardlink, withImage: thumbnail)
                } else {
                    imageView.reset()
                }
            } else {
                imageView.showInStack = false
            }
        case .loaded(messageObjectID: _, body: let body, bodyColor: let bodyColor, name: let name, nameColor: let nameColor, lineColor: let lineColor, bubbleColor: let bubbleColor, showThumbnail: let showThumbnail, hardlink: let hardlink, thumbnail: let thumbnail):
            if bodyLabel.text != body {
                bodyLabel.text = body
            }
            bodyLabel.textColor = bodyColor
            bodyLabel.showInStack = (bodyLabel.text != nil)
            if nameLabel.text != name {
                nameLabel.text = name
            }
            nameLabel.textColor = nameColor ?? .white
            nameLabel.showInStack = true
            line.backgroundColor = lineColor ?? .systemFill
            bubble.backgroundColor = bubbleColor ?? appTheme.colorScheme.newReceivedCellReplyToBackground
            if showThumbnail {
                imageView.backgroundColor = appTheme.colorScheme.systemFill
                imageView.showInStack = true
                if let hardlink = hardlink {
                    imageView.setHardlink(newHardlink: hardlink, withImage: thumbnail)
                } else {
                    imageView.reset()
                }
            } else {
                imageView.showInStack = false
            }
        }
        
        // Whatever the config, find the appropriate font size
        
        if let text = bodyLabel.text, text.containsOnlyEmoji == true, text.count < 4 {
            bodyLabel.font = UIFont.systemFont(ofSize: 40.0)
        } else {
            bodyLabel.font = UIFont.italic(forTextStyle: .body)
        }

        setNeedsLayout()
        
    }

    
    /// Implementing `UIViewWithThumbnailsForUTI`
    var imageForUTI = [String: UIImage]()
    
    private var currentSetImageURL: URL?
    private let bubble = BubbleView()
    private let mainStack = OlvidVerticalStackView(gap: 4.0, side: .leading, debugName: "ReplyToBubbleViewStack", showInStack: true)
    private let horizontalStack = OlvidHorizontalStackView(gap: 8.0, side: .top, debugName: "Horizontal stack of ReplyToBubbleView", showInStack: true)
    private let line = UIView()
    private let nameLabel = NameLabel()
    private let bodyLabel = UILabelForOlvidStack()
    private let imageView = UIImageViewForHardLinkForOlvidStack()
    let expirationIndicator = ExpirationIndicatorView()
    let expirationIndicatorSide: ExpirationIndicatorView.Side
    
    var replyToMessageObjectID: NSManagedObjectID? {
        currentConfiguration?.messageObjectID
    }
    
    init(expirationIndicatorSide side: ExpirationIndicatorView.Side) {
        self.expirationIndicatorSide = side
        super.init(frame: .zero)
        setupInternalViews()
    }
    

    var maskedCorner: UIRectCorner {
        get { bubble.maskedCorner }
        set { bubble.maskedCorner = newValue }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    func tappedStuff(tapGestureRecognizer: UITapGestureRecognizer, acceptTapOutsideBounds: Bool) -> TappedStuffForCell? {
        guard !self.isHidden && self.showInStack else { return nil }
        guard self.bounds.contains(tapGestureRecognizer.location(in: self)) else { return nil }
        guard let replyToMessageObjectID = replyToMessageObjectID else { return nil }
        return .replyTo(replyToMessageObjectID: replyToMessageObjectID)
    }
    
    
    private func setupInternalViews() {
        
        addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.backgroundColor = .systemFill
        
        addSubview(expirationIndicator)
        expirationIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        bubble.addSubview(line)
        line.translatesAutoresizingMaskIntoConstraints = false
        line.backgroundColor = .red
        
        bubble.addSubview(mainStack)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        
        mainStack.addArrangedSubview(nameLabel)
        nameLabel.textColor = .red
        nameLabel.text = nil
        
        mainStack.addArrangedSubview(horizontalStack)
        horizontalStack.translatesAutoresizingMaskIntoConstraints = false
        horizontalStack.clipsToBounds = true
        
        horizontalStack.addArrangedSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.layer.cornerRadius = 8.0
        imageView.clipsToBounds = true

        horizontalStack.addArrangedSubview(bodyLabel)
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.numberOfLines = 2
        bodyLabel.adjustsFontForContentSizeCategory = true

        let verticalInset = MessageCellConstants.bubbleVerticalInset
        let horizontalInsets = MessageCellConstants.bubbleHorizontalInsets
        let replyToLineWidth = MessageCellConstants.replyToLineWidth

        let constraints = [
            
            bubble.topAnchor.constraint(equalTo: self.topAnchor),
            bubble.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            bubble.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            bubble.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            
            mainStack.topAnchor.constraint(equalTo: bubble.topAnchor, constant: verticalInset),
            mainStack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -horizontalInsets),
            mainStack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -verticalInset),
            mainStack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: horizontalInsets),
            
            line.topAnchor.constraint(equalTo: bubble.topAnchor),
            line.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
            line.widthAnchor.constraint(equalToConstant: replyToLineWidth),
            
            imageView.widthAnchor.constraint(equalToConstant: MessageCellConstants.replyToImageSize),
            imageView.heightAnchor.constraint(equalToConstant: MessageCellConstants.replyToImageSize),

        ]
        
        NSLayoutConstraint.activate(constraints)
        
        // Width constraints for the main stack:
        // Less that a certain size (mandatory), but expands as much as possible to show the name, thumbnail, and body.
        // And larger than a (small) constant (mandatory)
        mainStack.widthAnchor.constraint(lessThanOrEqualToConstant: MessageCellConstants.bubbleMaxWidth).isActive = true
        mainStack.widthAnchor.constraint(greaterThanOrEqualToConstant: MessageCellConstants.replyToBubbleMinWidth).isActive = true
        let mainStackHorizontalConstraints = [
            mainStack.widthAnchor.constraint(greaterThanOrEqualTo: nameLabel.widthAnchor),
            mainStack.widthAnchor.constraint(greaterThanOrEqualTo: bodyLabel.widthAnchor),
        ]
        mainStackHorizontalConstraints.forEach({ $0.priority -= 1 })
        NSLayoutConstraint.activate(mainStackHorizontalConstraints)

        // Setup minimal constrains
        
        let minimalConstraints = [
            self.widthAnchor.constraint(equalToConstant: 1),
            self.heightAnchor.constraint(equalToConstant: 1),
        ]
        minimalConstraints.forEach({ $0.priority = .defaultLow })
        NSLayoutConstraint.activate(minimalConstraints)
        
        setupConstraintsForExpirationIndicator(gap: MessageCellConstants.gapBetweenExpirationViewAndBubble)

        nameLabel.isUserInteractionEnabled = false
        mainStack.isUserInteractionEnabled = false
    }
  
    
    private struct Strings {
        
        static func remotelyWiped(deleterName: String?) -> String {
            if let deleterName {
                return String.localizedStringWithFormat(NSLocalizedString("WIPED_MESSAGE_BY_%@", comment: ""), deleterName)
            } else {
                return NSLocalizedString("Remotely wiped", comment: "")
            }
        }

        static let replyToMessageWasDeleted = NSLocalizedString("Deleted message", comment: "Body displayed when a reply-to message was deleted.")
        
        static let replyToMessageUnavailable = NSLocalizedString("UNAVAILABLE_MESSAGE", comment: "Body displayed when a reply-to message cannot be found.")

    }

}


private final class NameLabel: ViewForOlvidStack {
    
    private let label = UILabel()
    
    var text: String? {
        get { label.text }
        set { label.text = newValue }
    }
    
    var textColor: UIColor? {
        get { label.textColor }
        set { label.textColor = newValue }
    }
    
    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }
    

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    
    func setupInternalViews() {
        
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.textColor = .red
        label.text = nil
        label.font = MessageCellConstants.fontForContactName

        let constraints = [
            label.topAnchor.constraint(equalTo: self.topAnchor),
            label.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            label.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor),
        ]
        NSLayoutConstraint.activate(constraints)

        label.setContentCompressionResistancePriority(.required, for: .vertical)
        self.setContentCompressionResistancePriority(.required, for: .vertical)

    }

}
