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

class MessageSystemCollectionViewCell: UICollectionViewCell {
    
    static let identifier = "MessageSystemCollectionViewCell"
    
    let label = UILabel()
    let mainStack = UIStackView()
    let roundedView = ObvRoundedRectView()
    let roundedViewPadding: CGFloat = 8

    let hStackForEphemeralConfig = UIStackView()
    let readOnceStack = UIStackView()
    let limitedVisibilityStack = UIStackView()
    let limitedExistenceStack = UIStackView()
    let expirationFontTextStyle = UIFont.TextStyle.footnote
    let nonEphemeralLabel = UILabel()

    private(set) var messageSystem: PersistedMessageSystem?

    var messageSystemCategory: PersistedMessageSystem.Category? {
        messageSystem?.category
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setup() {
        
        self.clipsToBounds = true
        self.autoresizesSubviews = true
        
        roundedView.translatesAutoresizingMaskIntoConstraints = false
        roundedView.accessibilityIdentifier = "roundedView"
        roundedView.backgroundColor = appTheme.colorScheme.quaternarySystemFill
        self.addSubview(roundedView)
        
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.accessibilityIdentifier = "vStackForEphemeralConfig"
        mainStack.axis = .vertical
        mainStack.alignment = .center
        mainStack.spacing = 4.0
        roundedView.addSubview(mainStack)
        
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityIdentifier = "label"
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.textColor = AppTheme.shared.colorScheme.label
        label.textAlignment = .center
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        mainStack.addArrangedSubview(label)
        
        hStackForEphemeralConfig.translatesAutoresizingMaskIntoConstraints = false
        hStackForEphemeralConfig.accessibilityIdentifier = "hStackForEphemeralConfig"
        hStackForEphemeralConfig.axis = .horizontal
        hStackForEphemeralConfig.spacing = 12.0
        
        // Configure the stack containing a symbol and the text for the read once configuration
        
        do {
            readOnceStack.translatesAutoresizingMaskIntoConstraints = false
            readOnceStack.accessibilityIdentifier = "readOnceStack"
            readOnceStack.axis = .horizontal
            readOnceStack.alignment = .firstBaseline
            readOnceStack.spacing = 4.0
            
            if #available(iOS 13, *) {
                let imageViewReadOnce = UIImageView()
                imageViewReadOnce.translatesAutoresizingMaskIntoConstraints = false
                imageViewReadOnce.accessibilityIdentifier = "imageViewReadOnce"
                let configuration = UIImage.SymbolConfiguration(textStyle: expirationFontTextStyle)
                let image = UIImage(systemName: "flame.fill", withConfiguration: configuration)
                imageViewReadOnce.image = image
                imageViewReadOnce.tintColor = .red
                readOnceStack.addArrangedSubview(imageViewReadOnce)
            }
            
            let labelReadOnce = UILabel()
            labelReadOnce.translatesAutoresizingMaskIntoConstraints = false
            labelReadOnce.accessibilityIdentifier = "labelReadOnce"
            labelReadOnce.text = NSLocalizedString("READ_ONCE_LABEL", comment: "")
            labelReadOnce.textColor = .red
            labelReadOnce.font = UIFont.preferredFont(forTextStyle: expirationFontTextStyle)
            readOnceStack.addArrangedSubview(labelReadOnce)
        }
        
        // Configure the stack containing a symbol and the text for the limited visibility setting
        
        do {
            limitedVisibilityStack.translatesAutoresizingMaskIntoConstraints = false
            limitedVisibilityStack.accessibilityIdentifier = "limitedVisibilityStack"
            limitedVisibilityStack.axis = .horizontal
            limitedVisibilityStack.alignment = .firstBaseline
            limitedVisibilityStack.spacing = 4.0
            
            if #available(iOS 13, *) {
                let imageLimitedVisibility = UIImageView()
                imageLimitedVisibility.translatesAutoresizingMaskIntoConstraints = false
                imageLimitedVisibility.accessibilityIdentifier = "imageLimitedVisibility"
                let configuration = UIImage.SymbolConfiguration(textStyle: expirationFontTextStyle)
                let image = UIImage(systemName: "eyes", withConfiguration: configuration)
                imageLimitedVisibility.image = image
                imageLimitedVisibility.tintColor = .orange
                limitedVisibilityStack.addArrangedSubview(imageLimitedVisibility)
            }
            
            let labelLimitedVisibility = UILabel()
            labelLimitedVisibility.translatesAutoresizingMaskIntoConstraints = false
            labelLimitedVisibility.accessibilityIdentifier = "labelLimitedVisibility"
            labelLimitedVisibility.textColor = .orange
            labelLimitedVisibility.font = UIFont.preferredFont(forTextStyle: expirationFontTextStyle)
            limitedVisibilityStack.addArrangedSubview(labelLimitedVisibility)
        }

        // Configure the stack containing a symbol and the text for the limited existence setting
        
        do {
            limitedExistenceStack.translatesAutoresizingMaskIntoConstraints = false
            limitedExistenceStack.accessibilityIdentifier = "limitedExistenceStack"
            limitedExistenceStack.axis = .horizontal
            limitedExistenceStack.alignment = .firstBaseline
            limitedExistenceStack.spacing = 4.0
            
            if #available(iOS 13, *) {
                let imageLimitedExistence = UIImageView()
                imageLimitedExistence.translatesAutoresizingMaskIntoConstraints = false
                imageLimitedExistence.accessibilityIdentifier = "imageLimitedExistence"
                let configuration = UIImage.SymbolConfiguration(textStyle: expirationFontTextStyle)
                let image = UIImage(systemName: "timer", withConfiguration: configuration)
                imageLimitedExistence.image = image
                imageLimitedExistence.tintColor = .systemGray
                limitedExistenceStack.addArrangedSubview(imageLimitedExistence)
            }
            
            let labelLimitedExistence = UILabel()
            labelLimitedExistence.translatesAutoresizingMaskIntoConstraints = false
            labelLimitedExistence.accessibilityIdentifier = "labelLimitedExistence"
            labelLimitedExistence.textColor = .systemGray
            labelLimitedExistence.font = UIFont.preferredFont(forTextStyle: expirationFontTextStyle)
            limitedExistenceStack.addArrangedSubview(labelLimitedExistence)
        }

        // Configure the label to display when there is no ephemeral setting

        do {
            nonEphemeralLabel.translatesAutoresizingMaskIntoConstraints = false
            nonEphemeralLabel.accessibilityIdentifier = "nonEphemeralLabel"
            nonEphemeralLabel.textColor = .systemGray
            let descriptor = UIFont.preferredFont(forTextStyle: expirationFontTextStyle).fontDescriptor
            let preferredDescriptor = descriptor.withSymbolicTraits(.traitItalic) ?? descriptor
            nonEphemeralLabel.font = UIFont(descriptor: preferredDescriptor, size: 0)
            nonEphemeralLabel.text = NSLocalizedString("NON_EPHEMERAL_MESSAGES_LABEL", comment: "")
        }
        
        setupConstraints()
    }
    
    
    private func setupConstraints() {
        let constraints = [
            roundedView.topAnchor.constraint(equalTo: self.topAnchor),
            roundedView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            roundedView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            mainStack.topAnchor.constraint(equalTo: roundedView.topAnchor, constant: roundedViewPadding),
            mainStack.bottomAnchor.constraint(equalTo: roundedView.bottomAnchor, constant: -roundedViewPadding),
            mainStack.trailingAnchor.constraint(equalTo: roundedView.trailingAnchor, constant: -roundedViewPadding),
            mainStack.leadingAnchor.constraint(equalTo: roundedView.leadingAnchor, constant: roundedViewPadding),
        ]
        NSLayoutConstraint.activate(constraints)
    }
    
    
    override func prepareForReuse() {
        super.prepareForReuse()
        messageSystem = nil
        roundedView.backgroundColor = appTheme.colorScheme.quaternarySystemFill
        self.label.textAlignment = .center
        label.textColor = AppTheme.shared.colorScheme.label
        while mainStack.arrangedSubviews.count > 1 {
            let last = mainStack.arrangedSubviews.last!
            mainStack.removeArrangedSubview(last)
            last.removeFromSuperview()
        }
        while let view = hStackForEphemeralConfig.arrangedSubviews.last {
            hStackForEphemeralConfig.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }


    func prepare(with message: PersistedMessageSystem) {
        
        messageSystem = message
        
        switch message.category {
        case .contactJoinedGroup, .contactLeftGroup, .contactWasDeleted, .contactRevokedByIdentityProvider:
            self.label.text = message.textBody?.localizedUppercase
        case .discussionIsEndToEndEncrypted:
            self.label.text = message.textBody
            self.label.textAlignment = .natural
            roundedView.backgroundColor = AppTheme.shared.colorScheme.green
            label.textColor = .white
        case .numberOfNewMessages:
            self.label.text = message.textBody?.localizedUppercase
            roundedView.backgroundColor = AppTheme.appleBadgeRedColor
            label.textColor = .white
        case .callLogItem:
            self.label.text = message.textBody?.localizedUppercase
        case .updatedDiscussionSharedSettings:
            self.label.text = message.textBody?.localizedUppercase
            if let expirationJSON = message.expirationJSON {
                var addHStackForEphemeralConfig = false
                if expirationJSON.readOnce {
                    hStackForEphemeralConfig.addArrangedSubview(readOnceStack)
                    addHStackForEphemeralConfig = true
                }
                if let timeInterval = expirationJSON.visibilityDuration, let duration = DurationOption(rawValue: Int(timeInterval)) {
                    (limitedVisibilityStack.arrangedSubviews.last as? UILabel)?.text = duration.description
                    hStackForEphemeralConfig.addArrangedSubview(limitedVisibilityStack)
                    addHStackForEphemeralConfig = true
                }
                if let timeInterval = expirationJSON.existenceDuration, let duration = DurationOption(rawValue: Int(timeInterval)) {
                    (limitedExistenceStack.arrangedSubviews.last as? UILabel)?.text = duration.description
                    hStackForEphemeralConfig.addArrangedSubview(limitedExistenceStack)
                    addHStackForEphemeralConfig = true
                }
                if addHStackForEphemeralConfig {
                    mainStack.addArrangedSubview(hStackForEphemeralConfig)
                } else {
                    mainStack.addArrangedSubview(nonEphemeralLabel)
                }
            } else {
                mainStack.addArrangedSubview(nonEphemeralLabel)
            }
        case .discussionWasRemotelyWiped:
            self.label.text = message.textBody?.localizedUppercase
        }
        
    }
    
}


extension MessageSystemCollectionViewCell {
    
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        
        self.label.preferredMaxLayoutWidth = layoutAttributes.size.width - 2*roundedViewPadding
        
        var fittingSize = UIView.layoutFittingCompressedSize
        fittingSize.width = layoutAttributes.size.width
        let size = systemLayoutSizeFitting(fittingSize, withHorizontalFittingPriority: .defaultHigh, verticalFittingPriority: .defaultLow)
        var adjustedFrame = layoutAttributes.frame
        adjustedFrame.size.height = size.height
        layoutAttributes.frame = adjustedFrame
        
        return layoutAttributes
        
    }
    
}


extension MessageSystemCollectionViewCell: CellWithMessage {
    
    var persistedMessage: PersistedMessage? { messageSystem }
    
    var persistedMessageObjectID: TypeSafeManagedObjectID<PersistedMessage>? {
        persistedMessage?.typedObjectID
    }
    
    var persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>? { nil } // Not used within the old discussion screen

    var viewForTargetedPreview: UIView { self.roundedView }
    
    var isCopyActionAvailable: Bool { false }
    var textViewToCopy: UITextView? { nil }
    var textToCopy: String? { nil }
    var isSharingActionAvailable: Bool { false }
    var fyleMessagesJoinWithStatus: [FyleMessageJoinWithStatus]? { nil }
    var imageAttachments: [FyleMessageJoinWithStatus]? { nil }
    var itemProvidersForImages: [UIActivityItemProvider]? { nil }
    var itemProvidersForAllAttachments: [UIActivityItemProvider]? { nil }
    var isReplyToActionAvailable: Bool { false }

    var isInfoActionAvailable: Bool { ObvMessengerConstants.developmentMode && self.messageSystemCategory == .callLogItem }
    var infoViewController: UIViewController? {
        guard isInfoActionAvailable else { return nil }
        if let item = messageSystem?.optionalCallLogItem {
            print("item.callReportKind = \(item.callReportKind.debugDescription)")
            print("item.unknownContactsCount = \(item.unknownContactsCount)")
            print("item.isIncoming = \(item.isIncoming)")

            var idx = 0
            for contact in item.logContacts {
                print("item.contact[\(idx)].callReportKind = \(contact.callReportKind)")
                print("item.contact[\(idx)].isCaller = \(contact.isCaller)")
                print("item.contact[\(idx)].contactIdentity = \(contact.contactIdentity == nil ? "nil" : "some")")
                idx += 1
            }
        }

        return nil
    }

    var isDeleteActionAvailable: Bool {
        switch self.messageSystemCategory {
            
        case .contactJoinedGroup,
                .contactLeftGroup,
                .contactWasDeleted,
                .callLogItem,
                .updatedDiscussionSharedSettings,
                .contactRevokedByIdentityProvider,
                .discussionWasRemotelyWiped:
            return true
        case .numberOfNewMessages,
                .discussionIsEndToEndEncrypted,
                .none:
            return false
        }
    }

    var isEditBodyActionAvailable: Bool { false }

    var isCallActionAvailable: Bool {
        guard self.messageSystemCategory == .callLogItem else { return false }
        guard let discussion = messageSystem?.discussion else { return false }
        return discussion.isCallAvailable
    }

    var isDeleteOwnReactionActionAvailable: Bool { false }

}
