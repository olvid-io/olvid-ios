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
import os.log


@available(iOS 14.0, *)
final class SystemMessageCell: UICollectionViewCell, CellWithMessage, UIViewWithTappableStuff {
    
    private(set) var message: PersistedMessageSystem?
    private var indexPath = IndexPath(item: 0, section: 0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.automaticallyUpdatesContentConfiguration = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let newSize = systemLayoutSizeFitting(
            layoutAttributes.frame.size,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        var newFrame = layoutAttributes.frame
        newFrame.size = newSize
        // We *must* create new layout attributes, otherwise, if the computed frame happens to be identical to the default one, the `shouldInvalidateLayout` method of the collection view layout is not called.
        let newLayoutAttributes = UICollectionViewLayoutAttributes(forCellWith: layoutAttributes.indexPath)
        newLayoutAttributes.frame = newFrame
        return newLayoutAttributes
    }

    private let durationFormatter = DurationFormatter()
        
    func updateWith(message: PersistedMessageSystem, indexPath: IndexPath) {
        self.message = message
        self.indexPath = indexPath
        self.setNeedsUpdateConfiguration()
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        guard AppStateManager.shared.currentState.isInitializedAndActive else {
            // This prevents a crash when the user hits the home button while in the discussion.
            // In that case, for some reason, this method is called and crashes because we cannot fetch faulted values once not active.
            // Note that we *cannot* call setNeedsUpdateConfiguration() here, as this creates a deadlock.
            return
        }
        guard let message = self.message else { assertionFailure(); return }
        guard message.managedObjectContext != nil else { return } // Happens if the message has recently been deleted. Going further would crash the app.
        var content = SystemMessageCellCustomContentConfiguration().updated(for: state)
        content.body = message.textBodyWithoutTimestamp
        content.textColor = .white
        content.date = message.timestamp
        content.subBody = nil
        switch message.category {
        case .contactRevokedByIdentityProvider:
            content.backgroundColor = appTheme.colorScheme.red
        case .contactJoinedGroup, .notPartOfTheGroupAnymore, .rejoinedGroup:
            content.backgroundColor = appTheme.colorScheme.green
        case .contactLeftGroup:
            content.backgroundColor = appTheme.colorScheme.green
        case .numberOfNewMessages:
            content.backgroundColor = .red
            content.date = nil
        case .discussionIsEndToEndEncrypted:
            content.backgroundColor = appTheme.colorScheme.green
            content.date = nil
        case .contactWasDeleted:
            content.backgroundColor = appTheme.colorScheme.green
        case .contactIsOneToOneAgain:
            content.backgroundColor = appTheme.colorScheme.green
        case .callLogItem:
            content.backgroundColor = appTheme.colorScheme.purple
        case .updatedDiscussionSharedSettings:
            content.backgroundColor = appTheme.colorScheme.orange
            if let expirationJSON = message.expirationJSON {
                let symbolConfiguration = UIImage.SymbolConfiguration(textStyle: SystemMessageCellContentView.secondLabelTextStyle)
                var subLabels = [NSAttributedString]()
                if expirationJSON.readOnce {
                    let attachment = NSTextAttachment()
                    attachment.image = UIImage(systemIcon: .flameFill, withConfiguration: symbolConfiguration)?.withTintColor(content.textColor)
                    let subLabel = NSMutableAttributedString(attachment: attachment)
                    subLabels.append(subLabel)
                }
                if let visibilityDuration = expirationJSON.visibilityDuration {
                    let attachment = NSTextAttachment()
                    attachment.image = UIImage(systemIcon: .eyes, withConfiguration: symbolConfiguration)?.withTintColor(content.textColor)
                    let subLabel = NSMutableAttributedString(attachment: attachment)
                    subLabel.append(NSAttributedString(string: " "))
                    subLabel.append(NSAttributedString(string: durationFormatter.string(from: visibilityDuration) ?? ""))
                    subLabels.append(subLabel)
                }
                if let existenceDuration = expirationJSON.existenceDuration {
                    let attachment = NSTextAttachment()
                    attachment.image = UIImage(systemIcon: .timer, withConfiguration: symbolConfiguration)?.withTintColor(content.textColor)
                    let subLabel = NSMutableAttributedString(attachment: attachment)
                    subLabel.append(NSAttributedString(string: " "))
                    subLabel.append(NSAttributedString(string: durationFormatter.string(from: existenceDuration) ?? ""))
                    subLabels.append(subLabel)
                }
                content.subBody = subLabels.joined(separator: "    ")
            } else {
                content.subBody = nil
            }
        case .discussionWasRemotelyWiped:
            content.backgroundColor = appTheme.colorScheme.orange
        }
        self.contentConfiguration = content
    }
    

    func tappedStuff(tapGestureRecognizer: UITapGestureRecognizer, acceptTapOutsideBounds: Bool) -> TappedStuffForCell? {
        guard !self.isHidden else { return nil }
        guard self.bounds.contains(tapGestureRecognizer.location(in: self)) else { return nil }
        guard let category = message?.category else { assertionFailure(); return nil }
        switch category {
        case .updatedDiscussionSharedSettings:
            return .systemCellShowingUpdatedDiscussionSharedSettings
        case .callLogItem:
            guard let callLogItem = message?.optionalCallLogItem else { assertionFailure(); return nil }
            guard let callReportKind = callLogItem.callReportKind else { assertionFailure(); return nil }
            switch callReportKind {
            case .rejectedIncomingCallBecauseOfDeniedRecordPermission:
                return .systemCellShowingCallLogItemRejectedIncomingCallBecauseOfDeniedRecordPermission
            default:
                return nil
            }
        case .contactJoinedGroup,
                .contactLeftGroup,
                .numberOfNewMessages,
                .discussionIsEndToEndEncrypted,
                .contactWasDeleted,
                .discussionWasRemotelyWiped,
                .contactRevokedByIdentityProvider,
                .notPartOfTheGroupAnymore,
                .rejoinedGroup,
                .contactIsOneToOneAgain:
            return nil
        }
    }
    
}


// MARK: - Implementing CellWithMessage

@available(iOS 14.0, *)
extension SystemMessageCell {
    
    var persistedMessage: PersistedMessage? { message }
    
    var persistedMessageObjectID: TypeSafeManagedObjectID<PersistedMessage>? { persistedMessage?.typedObjectID }
    var persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>? { nil }
    var viewForTargetedPreview: UIView { self.contentView }

    var textToCopy: String? { nil }

    var fyleMessagesJoinWithStatus: [FyleMessageJoinWithStatus]? { nil }
    var imageAttachments: [FyleMessageJoinWithStatus]? { nil } // Legacy, replaced by itemProvidersForImages
    var itemProvidersForImages: [UIActivityItemProvider]? { nil }
    var itemProvidersForAllAttachments: [UIActivityItemProvider]? { nil }

    var infoViewController: UIViewController? {
        guard message?.infoActionCanBeMadeAvailable == true else { return nil }
        if let item = message?.optionalCallLogItem {
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

}



@available(iOS 14.0, *)
fileprivate struct SystemMessageCellCustomContentConfiguration: UIContentConfiguration, Hashable {

    var body: String?
    var icon: ObvSystemIcon?
    var backgroundColor = UIColor.red
    var textColor = UIColor.white
    var date: Date?
    var subBody: NSAttributedString?

    var category: Category?
    
    func makeContentView() -> UIView & UIContentView {
        return SystemMessageCellContentView(configuration: self)
    }

    func updated(for state: UIConfigurationState) -> Self {
        return self
    }

}


@available(iOS 14.0, *)
private final class SystemMessageCellContentView: UIView, UIContentView {
    
    private let mainStack = OlvidVerticalStackView(gap: MessageCellConstants.mainStackGap,
                                                   side: .trailing,
                                                   debugName: "System Message Cell Main Olvid Stack",
                                                   showInStack: true)
    private let subStack = OlvidVerticalStackView(gap: MessageCellConstants.mainStackGap,
                                                  side: .bothSides,
                                                  debugName: "System Message Cell Sub Olvid Stack",
                                                  showInStack: true)
    private let bubbleView = BubbleView()
    private let firstlabel = UILabelForOlvidStack()
    private let secondLabel = UILabelForOlvidStack()
    private let dateView = SystemMessageDateView()

    private var appliedConfiguration: SystemMessageCellCustomContentConfiguration!

    init(configuration: SystemMessageCellCustomContentConfiguration) {
        super.init(frame: .zero)
        setupInternalViews()
        self.configuration = configuration
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var configuration: UIContentConfiguration {
        get { appliedConfiguration }
        set {
            guard let newConfig = newValue as? SystemMessageCellCustomContentConfiguration else { return }
            let currentConfig = appliedConfiguration
            apply(currentConfig: currentConfig, newConfig: newConfig)
            appliedConfiguration = newConfig
        }
    }

    fileprivate static let secondLabelTextStyle = UIFont.TextStyle.callout
    
    private func setupInternalViews() {

        addSubview(mainStack)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        
        mainStack.addArrangedSubview(bubbleView)
        bubbleView.translatesAutoresizingMaskIntoConstraints = false

        mainStack.addArrangedSubview(dateView)

        bubbleView.addSubview(subStack)
        subStack.translatesAutoresizingMaskIntoConstraints = false
        
        subStack.addArrangedSubview(firstlabel)
        firstlabel.textAlignment = .center
        firstlabel.numberOfLines = 0
        firstlabel.font = UIFont.preferredFont(forTextStyle: .body)
        firstlabel.adjustsFontForContentSizeCategory = true

        subStack.addArrangedSubview(secondLabel)
        secondLabel.textAlignment = .center
        secondLabel.numberOfLines = 0
        secondLabel.font = UIFont.preferredFont(forTextStyle: SystemMessageCellContentView.secondLabelTextStyle)
        secondLabel.adjustsFontForContentSizeCategory = true
        
        let verticalInset = MessageCellConstants.bubbleVerticalInset
        let horizontalInsets = MessageCellConstants.bubbleHorizontalInsets

        let constraints = [
            mainStack.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            mainStack.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor, multiplier: 0.8),
            mainStack.topAnchor.constraint(equalTo: self.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            
            subStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: verticalInset),
            subStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -horizontalInsets),
            subStack.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -verticalInset),
            subStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: horizontalInsets),
        ]
        NSLayoutConstraint.activate(constraints)
        
        // This constraint prevents the app from crashing in case there is nothing to display within the cell
        do {
            let safeHeightConstraint = self.heightAnchor.constraint(equalToConstant: 0)
            safeHeightConstraint.priority = .defaultLow
            safeHeightConstraint.isActive = true
        }
        
        // Contraints with small priorty allowing to prevent ambiguous contraints issues
        do {
            let widthConstraints = [
                mainStack.widthAnchor.constraint(equalToConstant: 1),
                bubbleView.widthAnchor.constraint(equalToConstant: 1),
            ]
            widthConstraints.forEach({ $0.priority = .defaultLow })
            NSLayoutConstraint.activate(widthConstraints)
        }
    }
    
    
    private func apply(currentConfig: SystemMessageCellCustomContentConfiguration?, newConfig: SystemMessageCellCustomContentConfiguration) {

        bubbleView.backgroundColor = newConfig.backgroundColor
        firstlabel.textColor = newConfig.textColor
        if let body = newConfig.body, !body.isEmpty {
            if firstlabel.text != newConfig.body {
                firstlabel.text = newConfig.body
            }
            firstlabel.showInStack = true
        } else {
            firstlabel.showInStack = false
        }
        
        if let subBody = newConfig.subBody, subBody.length > 0 {
            if secondLabel.attributedText != newConfig.subBody {
                secondLabel.attributedText = newConfig.subBody
            }
            secondLabel.showInStack = true
            secondLabel.textColor = newConfig.textColor
        } else {
            secondLabel.showInStack = false
        }
        
        // Date
        
        if currentConfig == nil || currentConfig!.date != newConfig.date {
            if let date = newConfig.date {
                dateView.date = date
                dateView.showInStack = true
            } else {
                dateView.showInStack = false
            }
        }

    }
}


@available(iOS 14.0, *)
private class SystemMessageDateView: ViewForOlvidStack {
    
    var date = Date() {
        didSet {
            if oldValue != date {
                label.text = dateFormatter.string(from: date)
                setNeedsLayout()
            }
        }
    }
    
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.dateStyle = .none
        df.timeStyle = .short
        df.locale = Locale.current
        return df
    }()

    
    private let label = UILabel()
    
    
    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }
    

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    private func setupInternalViews() {
        
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .secondaryLabel
        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        label.textAlignment = .right
        
        let trailingPadding = CGFloat(4)
        let constraints = [
            label.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -trailingPadding),
            label.topAnchor.constraint(equalTo: self.topAnchor),
            label.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ]
        
        constraints.forEach { $0.priority -= 1 }
        NSLayoutConstraint.activate(constraints)

        label.setContentCompressionResistancePriority(.required, for: .vertical)

    }
}


fileprivate extension Sequence where Iterator.Element == NSAttributedString {
    
    func joined(separator _separator: String) -> NSAttributedString {
        let separator = NSAttributedString(string: _separator)
        return self.reduce(NSMutableAttributedString()) { result, string in
            if result.length > 0 {
                result.append(separator)
            }
            result.append(string)
            return result
        }
        
    }
        
}
