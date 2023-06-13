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


import MobileCoreServices
import LinkPresentation
import ObvUI
import ObvUICoreData
import UIKit


class MessageCollectionViewCell: UICollectionViewCell {
    
    weak var delegate: MessageCollectionViewCellDelegate?
        
    let initialFrameWidth: CGFloat
    
    let mainStackView = UIStackView()
    let roundedRectView = ObvRoundedRectView()
    let roundedRectStackView = UIStackView()
    let bodyTextViewPaddingView = UIView()
    let bodyTextView = UITextView()
    let dateLabel = UILabel()
    let replyToRoundedRectView = ObvRoundedRectView()
    let replyToRoundedRectContentView = UIView()
    let replyToStackView = UIStackView()
    let replyToLabel = UILabelWithLineFragmentPadding()
    let replyToTextView = UITextView()
    let replyToFylesLabel = UILabelWithLineFragmentPadding()
    let fyleRoundedRectView = ObvRoundedRectView()
    var roundedRectStackViewWidthConstraintWhenShowingFyles: NSLayoutConstraint!
    var collectionOfFylesView: CollectionOfFylesView!
    let collectionOfFylesViewTopPadding = UIView()
    var linkView: UIView?
    let linkViewConstant: CGFloat = 250
    let messageEditedStatusImageView = UIImageView()
    let bottomStackView = UIStackView()

    // For ephemeral message, displays an image and a countdown in the top left or right corner
    let countdownStack = UIStackView()
    let countdownImageViewReadOnce = UIImageView()
    let countdownImageViewExpiration = UIImageView()
    let countdownImageViewVisibility = UIImageView()
    let countdownLabel = UILabel()
    let countdownColorReadOnce = UIColor.red
    let countdownColorExpiration = UIColor.gray
    let countdownColorVisibility = UIColor.orange


    // Views for displaying ephemerality parameters
    let containerViewForEphemeralInfos = UIView()
    let vStackForEphemeralConfig = UIStackView()
    let hStackForEphemeralConfig = UIStackView()
    static let expirationFontTextStyle = UIFont.TextStyle.footnote
    let limitedVisibilityStack = UIStackView()
    let limitedExistenceStack = UIStackView()
    let readOnceStack = UIStackView()
    static let tapToReadColor = AppTheme.shared.colorScheme.tapToRead

    static let durationFormatter = DurationFormatter()

    let numberOfColumnsForMultipleImages = 2 // Settting this to 3 does not work yet
    
    private static let defaultBodyFont = UIFont.preferredFont(forTextStyle: .callout)
    private static let emojiBodyFont: UIFont = UIFont.systemFont(ofSize: 50.0)
    private static let maxNumberOfLargeEmojis = 3

    var message: PersistedMessage?
    var repliedMessage: PersistedMessage?
    var attachments = [FyleMessageJoinWithStatus]()
    
    private static let counterOfLayoutIfNeededCallsInitialValue = 10
    private var counterOfLayoutIfNeededCalls = MessageCollectionViewCell.counterOfLayoutIfNeededCallsInitialValue
    
    override init(frame: CGRect) {
        self.initialFrameWidth = frame.size.width
        super.init(frame: frame)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// The `FyleMessageJoinWithStatus` items, ordered as displayed to the user
    var fyleMessagesJoinWithStatus: [FyleMessageJoinWithStatus]? {
        guard let collectionOfFylesView = self.collectionOfFylesView else { return nil }
        return collectionOfFylesView.fyleMessagesJoinWithStatus
    }
    
    var imageAttachments: [FyleMessageJoinWithStatus]? {
        guard let collectionOfFylesView = self.collectionOfFylesView else { return nil }
        return collectionOfFylesView.imageAttachments.map({$0.attachment})
    }
    
    var itemProvidersForImages: [UIActivityItemProvider]? {
        return nil // Just to conform to CellWithMessage, not used by the old discussion screen (`imageAttachments` is used instead).
    }
    
    var itemProvidersForAllAttachments: [UIActivityItemProvider]? {
        return nil // Just to conform to CellWithMessage, not used by the old discussion screen (`fyleMessagesJoinWithStatus` is used instead).
    }

    
    func setup() {
        
        self.clipsToBounds = false
        self.autoresizesSubviews = true
        
        mainStackView.accessibilityIdentifier = "mainStackView"
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        mainStackView.axis = .vertical
        mainStackView.spacing = 2.0
        self.addSubview(mainStackView)
        
        roundedRectView.accessibilityIdentifier = "roundedRectView"
        roundedRectView.translatesAutoresizingMaskIntoConstraints = false
        mainStackView.addArrangedSubview(roundedRectView)
        
        bottomStackView.accessibilityIdentifier = "bottomStackView"
        bottomStackView.axis = .horizontal
        bottomStackView.spacing = 4.0
        mainStackView.addArrangedSubview(bottomStackView)
        
        dateLabel.accessibilityIdentifier = "dateLabel"
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        dateLabel.textColor = AppTheme.shared.colorScheme.cellDate

        messageEditedStatusImageView.accessibilityIdentifier = "messageEditedStatusImageView"
        messageEditedStatusImageView.tintColor = dateLabel.textColor
        
        let configuration = UIImage.SymbolConfiguration(textStyle: UIFont.TextStyle.footnote, scale: .small)
        messageEditedStatusImageView.image = UIImage(systemName: "pencil.circle.fill", withConfiguration: configuration)
        
        roundedRectStackView.accessibilityIdentifier = "roundedRectStackView"
        roundedRectStackView.translatesAutoresizingMaskIntoConstraints = false
        roundedRectStackView.axis = .vertical
        roundedRectStackView.alignment = .fill
        roundedRectStackView.spacing = 0.0
        roundedRectView.addSubview(roundedRectStackView)
        
        replyToRoundedRectView.accessibilityIdentifier = "replyToRoundedRectView"
        replyToRoundedRectView.translatesAutoresizingMaskIntoConstraints = false
        replyToRoundedRectView.clipsToBounds = true
        
        replyToRoundedRectContentView.accessibilityIdentifier = "replyToRoundedRectContentView"
        replyToRoundedRectContentView.translatesAutoresizingMaskIntoConstraints = false
        replyToRoundedRectView.addSubview(replyToRoundedRectContentView)
        
        replyToStackView.accessibilityIdentifier = "replyToStackView"
        replyToStackView.translatesAutoresizingMaskIntoConstraints = false
        replyToStackView.axis = .vertical
        replyToStackView.spacing = 4.0
        replyToRoundedRectContentView.addSubview(replyToStackView)
        
        replyToLabel.accessibilityIdentifier = "replyToLabel"
        replyToLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        replyToStackView.addArrangedSubview(replyToLabel)
        
        replyToTextView.accessibilityIdentifier = "replyToTextView"
        replyToTextView.translatesAutoresizingMaskIntoConstraints = false
        replyToTextView.isScrollEnabled = false
        replyToTextView.backgroundColor = .clear
        replyToTextView.textContainerInset = .zero
        replyToTextView.isEditable = false
        replyToTextView.dataDetectorTypes = .all
        replyToTextView.textContainer.maximumNumberOfLines = 3
        replyToTextView.textContainer.lineBreakMode = .byTruncatingTail
        replyToTextView.delegate = self
        
        // Remove all the gesture recognizers on the body text view, except the link tap gesture recognizer
        for recognizer in replyToTextView.gestureRecognizers! {
            if let name = recognizer.name, name == "UITextInteractionNameLinkTap" {
                continue
            } else {
                recognizer.isEnabled = false
            }
        }
        replyToStackView.addArrangedSubview(replyToTextView)
        
        replyToFylesLabel.accessibilityIdentifier = "replyToFylesLabel"
        replyToFylesLabel.translatesAutoresizingMaskIntoConstraints = false
        replyToFylesLabel.textColor = AppTheme.shared.colorScheme.secondaryLabel
        replyToFylesLabel.font = MessageCollectionViewCell.defaultBodyFont
        replyToStackView.addArrangedSubview(replyToFylesLabel)
        
        bodyTextViewPaddingView.accessibilityIdentifier = "bodyTextViewPaddingView"
        bodyTextViewPaddingView.translatesAutoresizingMaskIntoConstraints = false
        bodyTextViewPaddingView.backgroundColor = .clear
        roundedRectStackView.addArrangedSubview(bodyTextViewPaddingView)
        
        bodyTextView.accessibilityIdentifier = "bodyTextView"
        bodyTextView.translatesAutoresizingMaskIntoConstraints = false
        bodyTextView.isScrollEnabled = false
        bodyTextView.textContainerInset = .zero
        bodyTextView.isEditable = false
        bodyTextView.dataDetectorTypes = .all
        bodyTextView.delegate = self
        // Remove all the gesture recognizers on the body text view, except the link tap gesture recognizer
        for recognizer in bodyTextView.gestureRecognizers! {
            if let name = recognizer.name, name == "UITextInteractionNameLinkTap" {
                continue
            } else {
                recognizer.isEnabled = false
            }
        }
        bodyTextView.backgroundColor = .clear
        bodyTextViewPaddingView.addSubview(bodyTextView)
        
        dateLabel.accessibilityIdentifier = "dateLabel"
        dateLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        dateLabel.textColor = AppTheme.shared.colorScheme.cellDate

        fyleRoundedRectView.accessibilityIdentifier = "fyleRoundedRectView"
        fyleRoundedRectView.translatesAutoresizingMaskIntoConstraints = false
        fyleRoundedRectView.backgroundColor = AppTheme.shared.colorScheme.surfaceLight
        
        collectionOfFylesViewTopPadding.accessibilityIdentifier = "collectionOfFylesViewTopPadding"
        collectionOfFylesViewTopPadding.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure the horizontal stack view with informations about ephemeral settings of the message
        
        containerViewForEphemeralInfos.translatesAutoresizingMaskIntoConstraints = false
        containerViewForEphemeralInfos.accessibilityIdentifier = "vStackPaddingView"
        
        vStackForEphemeralConfig.translatesAutoresizingMaskIntoConstraints = false
        vStackForEphemeralConfig.accessibilityIdentifier = "vStackForEphemeralConfig"
        vStackForEphemeralConfig.axis = .vertical
        vStackForEphemeralConfig.distribution = .fill
        vStackForEphemeralConfig.alignment = .center
        containerViewForEphemeralInfos.addSubview(vStackForEphemeralConfig)

        hStackForEphemeralConfig.translatesAutoresizingMaskIntoConstraints = false
        hStackForEphemeralConfig.accessibilityIdentifier = "hStackForEphemeralConfig"
        hStackForEphemeralConfig.axis = .horizontal
        hStackForEphemeralConfig.spacing = 8.0
        hStackForEphemeralConfig.distribution = .fillProportionally
        hStackForEphemeralConfig.alignment = .firstBaseline
        hStackForEphemeralConfig.backgroundColor = .clear
        vStackForEphemeralConfig.addArrangedSubview(hStackForEphemeralConfig)
        
        // Configure the image view that can be inserted in the hStackForEphemeralConfig in case the message is read once
        
        do {
            countdownImageViewReadOnce.translatesAutoresizingMaskIntoConstraints = false
            countdownImageViewReadOnce.accessibilityIdentifier = "countdownImageViewReadOnce"
            let configuration = UIImage.SymbolConfiguration(textStyle: MessageCollectionViewCell.expirationFontTextStyle)
            let image = UIImage(systemName: "flame.fill", withConfiguration: configuration)
            countdownImageViewReadOnce.image = image
            countdownImageViewReadOnce.tintColor = countdownColorReadOnce
            countdownImageViewReadOnce.contentMode = .scaleAspectFit
            countdownImageViewReadOnce.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        }
        
        do {
            countdownImageViewExpiration.translatesAutoresizingMaskIntoConstraints = false
            countdownImageViewExpiration.accessibilityIdentifier = "countdownImageViewExpiration"
            let configuration = UIImage.SymbolConfiguration(textStyle: MessageCollectionViewCell.expirationFontTextStyle)
            let image = UIImage(systemName: "timer", withConfiguration: configuration)
            countdownImageViewExpiration.image = image
            countdownImageViewExpiration.tintColor = countdownColorExpiration
            countdownImageViewExpiration.contentMode = .scaleAspectFit
            countdownImageViewExpiration.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        }

        do {
            countdownImageViewVisibility.translatesAutoresizingMaskIntoConstraints = false
            countdownImageViewVisibility.accessibilityIdentifier = "countdownImageViewVisibility"
            let configuration = UIImage.SymbolConfiguration(textStyle: MessageCollectionViewCell.expirationFontTextStyle)
            let image = UIImage(systemName: "eyes", withConfiguration: configuration)
            countdownImageViewVisibility.image = image
            countdownImageViewVisibility.tintColor = countdownColorVisibility
            countdownImageViewVisibility.contentMode = .scaleAspectFit
            countdownImageViewVisibility.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        }

        // Configure the countdown label
        
        do {
            countdownLabel.translatesAutoresizingMaskIntoConstraints = false
            countdownLabel.accessibilityIdentifier = "countdownLabel"
            countdownLabel.font = UIFont.preferredFont(forTextStyle: MessageCollectionViewCell.expirationFontTextStyle)
        }
        
        // Configure the stack to show for messages with limited visibility
        
        do {
            limitedVisibilityStack.translatesAutoresizingMaskIntoConstraints = false
            limitedVisibilityStack.accessibilityIdentifier = "limitedVisibilityStack"
            limitedVisibilityStack.axis = .horizontal
            limitedVisibilityStack.alignment = .firstBaseline
            limitedVisibilityStack.spacing = 4.0

            let imageLimitedVisibility = UIImageView()
            imageLimitedVisibility.translatesAutoresizingMaskIntoConstraints = false
            imageLimitedVisibility.accessibilityIdentifier = "imageLimitedVisibility"
            let configuration = UIImage.SymbolConfiguration(textStyle: MessageCollectionViewCell.expirationFontTextStyle)
            let image = UIImage(systemName: "eyes", withConfiguration: configuration)
            imageLimitedVisibility.image = image
            imageLimitedVisibility.tintColor = .orange
            imageLimitedVisibility.contentMode = .scaleAspectFit
            limitedVisibilityStack.addArrangedSubview(imageLimitedVisibility)
            
            let labelLimitedVisibility = UILabel()
            labelLimitedVisibility.translatesAutoresizingMaskIntoConstraints = false
            labelLimitedVisibility.accessibilityIdentifier = "labelLimitedVisibility"
            labelLimitedVisibility.textColor = .orange
            labelLimitedVisibility.font = UIFont.preferredFont(forTextStyle: MessageCollectionViewCell.expirationFontTextStyle)
            limitedVisibilityStack.addArrangedSubview(labelLimitedVisibility)
        }
        
        do {
            limitedExistenceStack.translatesAutoresizingMaskIntoConstraints = false
            limitedExistenceStack.accessibilityIdentifier = "limitedExistenceStack"
            limitedExistenceStack.axis = .horizontal
            limitedExistenceStack.alignment = .firstBaseline
            limitedExistenceStack.spacing = 4.0
            
            let imageLimitedExistence = UIImageView()
            imageLimitedExistence.translatesAutoresizingMaskIntoConstraints = false
            imageLimitedExistence.accessibilityIdentifier = "imageLimitedExistence"
            let configuration = UIImage.SymbolConfiguration(textStyle: MessageCollectionViewCell.expirationFontTextStyle)
            let image = UIImage(systemName: "timer", withConfiguration: configuration)
            imageLimitedExistence.image = image
            imageLimitedExistence.tintColor = .systemGray
            imageLimitedExistence.contentMode = .scaleAspectFit
            limitedExistenceStack.addArrangedSubview(imageLimitedExistence)

            let labelLimitedExistence = UILabel()
            labelLimitedExistence.translatesAutoresizingMaskIntoConstraints = false
            labelLimitedExistence.accessibilityIdentifier = "labelLimitedExistence"
            labelLimitedExistence.textColor = .systemGray
            labelLimitedExistence.font = UIFont.preferredFont(forTextStyle: MessageCollectionViewCell.expirationFontTextStyle)
            limitedExistenceStack.addArrangedSubview(labelLimitedExistence)
        }

        do {
            readOnceStack.translatesAutoresizingMaskIntoConstraints = false
            readOnceStack.accessibilityIdentifier = "readOnceStack"
            readOnceStack.axis = .horizontal
            readOnceStack.alignment = .firstBaseline
            readOnceStack.spacing = 4.0

            let imageReadOnce = UIImageView()
            imageReadOnce.translatesAutoresizingMaskIntoConstraints = false
            imageReadOnce.accessibilityIdentifier = "imageReadOnce"
            let configuration = UIImage.SymbolConfiguration(textStyle: MessageCollectionViewCell.expirationFontTextStyle)
            let image = UIImage(systemName: "flame.fill", withConfiguration: configuration)
            imageReadOnce.image = image
            imageReadOnce.tintColor = .red
            imageReadOnce.contentMode = .scaleAspectFit
            readOnceStack.addArrangedSubview(imageReadOnce)

            let labelReadOnce = UILabel()
            labelReadOnce.translatesAutoresizingMaskIntoConstraints = false
            labelReadOnce.accessibilityIdentifier = "labelReadOnce"
            labelReadOnce.textColor = .red
            labelReadOnce.font = UIFont.preferredFont(forTextStyle: MessageCollectionViewCell.expirationFontTextStyle)
            labelReadOnce.text = NSLocalizedString("READ_ONCE_LABEL", comment: "")
            labelReadOnce.textAlignment = .center
            readOnceStack.addArrangedSubview(labelReadOnce)
        }
        
        // Setup the countdown to be shown for certain ephemeral messages in the top left or right corner
        
        countdownStack.translatesAutoresizingMaskIntoConstraints = false
        countdownStack.accessibilityIdentifier = "countdownStack"
        countdownStack.axis = .vertical
        countdownStack.distribution = .fill
        // The countdownStack.alignment value is set in subclasses
        countdownStack.spacing = 2.0
        
        setupConstraints()
    }
    
    
    private func setupConstraints() {
                
        let constraints = [
            mainStackView.topAnchor.constraint(equalTo: self.topAnchor),
            mainStackView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            roundedRectStackView.topAnchor.constraint(equalTo: roundedRectView.topAnchor, constant: 4.0),
            roundedRectStackView.trailingAnchor.constraint(equalTo: roundedRectView.trailingAnchor, constant: -4.0),
            roundedRectStackView.bottomAnchor.constraint(equalTo: roundedRectView.bottomAnchor, constant: -4.0),
            roundedRectStackView.leadingAnchor.constraint(equalTo: roundedRectView.leadingAnchor, constant: 4.0),
            replyToRoundedRectView.topAnchor.constraint(equalTo: replyToRoundedRectContentView.topAnchor, constant: 0),
            replyToRoundedRectView.trailingAnchor.constraint(equalTo: replyToRoundedRectContentView.trailingAnchor, constant: 0),
            replyToRoundedRectView.bottomAnchor.constraint(equalTo: replyToRoundedRectContentView.bottomAnchor, constant: 0),
            replyToRoundedRectView.leadingAnchor.constraint(equalTo: replyToRoundedRectContentView.leadingAnchor, constant: -4.0),
            replyToStackView.topAnchor.constraint(equalTo: replyToRoundedRectContentView.topAnchor, constant: 8.0),
            replyToStackView.trailingAnchor.constraint(equalTo: replyToRoundedRectContentView.trailingAnchor, constant: -8.0),
            replyToStackView.bottomAnchor.constraint(equalTo: replyToRoundedRectContentView.bottomAnchor, constant: -8.0),
            replyToStackView.leadingAnchor.constraint(equalTo: replyToRoundedRectContentView.leadingAnchor, constant: 8.0),
            bodyTextView.topAnchor.constraint(equalTo: bodyTextViewPaddingView.topAnchor, constant: 4.0),
            bodyTextView.trailingAnchor.constraint(equalTo: bodyTextViewPaddingView.trailingAnchor, constant: -4.0),
            bodyTextView.bottomAnchor.constraint(equalTo: bodyTextViewPaddingView.bottomAnchor, constant: -4.0),
            bodyTextView.leadingAnchor.constraint(equalTo: bodyTextViewPaddingView.leadingAnchor, constant: 4.0),
            roundedRectStackView.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor, multiplier: 0.8),
            collectionOfFylesViewTopPadding.heightAnchor.constraint(equalToConstant: 6.0),
            containerViewForEphemeralInfos.topAnchor.constraint(equalTo: vStackForEphemeralConfig.topAnchor, constant: -4.0),
            containerViewForEphemeralInfos.rightAnchor.constraint(equalTo: vStackForEphemeralConfig.rightAnchor, constant: 4.0),
            containerViewForEphemeralInfos.bottomAnchor.constraint(equalTo: vStackForEphemeralConfig.bottomAnchor),
            containerViewForEphemeralInfos.leftAnchor.constraint(equalTo: vStackForEphemeralConfig.leftAnchor, constant: -8.0),
        ]
        NSLayoutConstraint.activate(constraints)
        
        self.roundedRectStackViewWidthConstraintWhenShowingFyles = roundedRectStackView.widthAnchor.constraint(equalTo: self.widthAnchor, multiplier: 0.8)
        
        bodyTextView.setContentCompressionResistancePriority(.required, for: .horizontal)
        replyToTextView.setContentCompressionResistancePriority(.required, for: .horizontal)
        replyToLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        replyToFylesLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        
    }

    
    override func layoutSubviews() {
        super.layoutSubviews()
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        message = nil
        repliedMessage = nil
        attachments.removeAll()
        bodyTextView.text = nil
        bodyTextView.font = MessageCollectionViewCell.defaultBodyFont
        dateLabel.text = nil
        prepareReplyToForReuse()
        roundedRectStackView.removeArrangedSubview(replyToRoundedRectView)
        replyToRoundedRectView.removeFromSuperview()
        bodyTextView.isHidden = true
        bodyTextViewPaddingView.isHidden = true
        fyleRoundedRectView.removeFromSuperview()
        roundedRectStackViewWidthConstraintWhenShowingFyles.isActive = false
        collectionOfFylesViewTopPadding.removeFromSuperview()
        collectionOfFylesView?.removeFromSuperview()
        collectionOfFylesView = nil
        linkView?.removeFromSuperview()
        linkView = nil
        while let view = hStackForEphemeralConfig.arrangedSubviews.first {
            hStackForEphemeralConfig.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        roundedRectStackView.removeArrangedSubview(containerViewForEphemeralInfos)
        containerViewForEphemeralInfos.removeFromSuperview()
        removeCountdownStack()
        messageEditedStatusImageView.isHidden = true
        counterOfLayoutIfNeededCalls = MessageCollectionViewCell.counterOfLayoutIfNeededCallsInitialValue
        resetCounterOfLayoutIfNeededCalls()
    }
    
    
    private func resetCounterOfLayoutIfNeededCalls() {
        counterOfLayoutIfNeededCalls = MessageCollectionViewCell.counterOfLayoutIfNeededCallsInitialValue
    }

    enum MessageElement {
        case text(_ text: String)
        case onlyAttachments(count: Int)
        case wiped
        case remoteWiped
        case tapToRead

        var text: String? {
            switch self {
            case .text(let text): return text
            case .wiped: return NSLocalizedString("WIPED_MESSAGE", comment: "")
            case .remoteWiped: return NSLocalizedString("REMOTE_WIPED_MESSAGE", comment: "")
            case .tapToRead: return NSLocalizedString("TAP_TO_READ", comment: "")
            case .onlyAttachments: return nil
            }
        }

        /// This is used in ComposeMessageView#loadReplyTo to give information about the message to reply
        var replyToDescription: String {
            switch self {
            case .text(let text): return text
            case .wiped: return NSLocalizedString("WIPED_MESSAGE", comment: "")
            case .remoteWiped: return NSLocalizedString("REMOTE_WIPED_MESSAGE", comment: "")
            case .tapToRead: return NSLocalizedString("TAP_TO_READ", comment: "")
            case .onlyAttachments(count: let count):
                return PersistedMessage.Strings.countAttachments(count)
            }
        }

        var font: UIFont {
            switch self {
            case .text(let text):
                if text.count <= maxNumberOfLargeEmojis, text.containsOnlyEmoji {
                    return emojiBodyFont
                } else {
                    return defaultBodyFont
                }
            case .wiped, .remoteWiped, .onlyAttachments:
                let descriptor = defaultBodyFont.fontDescriptor.withSymbolicTraits(.traitItalic) ?? defaultBodyFont.fontDescriptor
                return UIFont(descriptor: descriptor, size: 0)
            case .tapToRead:
                let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: expirationFontTextStyle)
                return UIFont(descriptor: descriptor, size: 0)
            }
        }

        var centered: Bool {
            switch self {
            case .tapToRead: return true
            default: return false
            }
        }
    }

    static func extractMessageElements(from message: PersistedMessage) -> MessageElement? {
        if let messageSent = message as? PersistedMessageSent, messageSent.isLocallyWiped {
            return .wiped
        } else if message.isRemoteWiped {
            return .remoteWiped
        } else if let receivedMessage = message as? PersistedMessageReceived, receivedMessage.readingRequiresUserAction {
            return .tapToRead
        } else {
            if let textBody = message.textBody, !textBody.isEmpty {
                return .text(textBody)
            } else if let fyleMessageJoinWithStatus = message.fyleMessageJoinWithStatus,
                      !fyleMessageJoinWithStatus.isEmpty {
                return .onlyAttachments(count: fyleMessageJoinWithStatus.count)
            } else {
                /// No text, no attachements -> should not happend
                return nil
            }
        }
    }
    
    
    private func prepareReplyToForReuse() {
        replyToLabel.text = nil
        replyToLabel.textColor = .clear
        replyToTextView.text = nil
        replyToTextView.font = MessageCollectionViewCell.defaultBodyFont
        replyToTextView.isHidden = true
        replyToFylesLabel.text = nil
        replyToFylesLabel.isHidden = true
        replyToRoundedRectView.backgroundColor = AppTheme.shared.colorScheme.receivedCellReplyToBackground
    }
    
    
    
    func prepare(with message: PersistedMessage, attachments: [FyleMessageJoinWithStatus], withDateFormatter dateFormatter: DateFormatter, hideProgresses: Bool) {
        
        resetCounterOfLayoutIfNeededCalls()
        
        self.message = message
        self.attachments = attachments

        refreshBody(with: message)
        
        dateLabel.text = dateFormatter.string(from: message.timestamp)
        refreshReplyTo(with: message)
        
        refreshEditedStatus()
        
        if !attachments.isEmpty {
            insertCollectionOfFylesViewForShowingAttachments(hideProgresses: hideProgresses)
        }
        
        // Display any preview link
        let doFetchContentRichURLsMetadataSetting = message.discussion.localConfiguration.doFetchContentRichURLsMetadata ?? ObvMessengerSettings.Discussions.doFetchContentRichURLsMetadata
        let doFetchContentRichURLsMetadata: Bool
        switch doFetchContentRichURLsMetadataSetting {
        case .never: doFetchContentRichURLsMetadata = false
        case .withinSentMessagesOnly: doFetchContentRichURLsMetadata = message is PersistedMessageSent
        case .always: doFetchContentRichURLsMetadata = true
        }
        if doFetchContentRichURLsMetadata {
            if let urls = message.textBody?.extractURLs(),
               !urls.isEmpty {
                // Fetch the metadata
                let firstURL = urls.first!
                switch CachedLPMetadataProvider.shared.getCachedMetada(for: firstURL) {
                case .metadataCached(metadata: let metadata):
                    displayLinkMetadata(metadata, for: message, animate: false)
                case .siteDoesNotProvideMetada, .failureOccuredWhenFetchingOrCachingMetadata:
                    break
                case .metadaNotCachedYet:
                    CachedLPMetadataProvider.shared.fetchAndCacheMetadata(for: firstURL) { [weak self] in
                        guard let _self = self else { return }
                        guard self?.message == message else { return }
                        self?.delegate?.reloadCell(_self)
                    }
                }
            }
        }
        
        // If the message is ephemeral, show appropriate information
        refreshEphemeralInformation(with: message)

        // 2020-12-11: The following line was removed to prevent a freeze
        // 2020-12-23: This line was commented out to try to solve the "empty cell" issue. For now, no more freeze.
        // 2020-01-10: It appears that the following line does lead to occasion freezes. We should do something about this.
        if counterOfLayoutIfNeededCalls > 0 {
            counterOfLayoutIfNeededCalls -= 1
            self.layoutIfNeeded()
        }
    }

    
    private func refreshEditedStatus() {
        guard let message = self.message else { return }
        messageEditedStatusImageView.isHidden = !message.isEdited
    }
    
    
    private func insertCollectionOfFylesViewForShowingAttachments(hideProgresses: Bool) {
        let allAttachmentsAreWiped = attachments.allSatisfy { $0.isWiped }
        guard !allAttachmentsAreWiped else { return }
        roundedRectStackViewWidthConstraintWhenShowingFyles.isActive = true
        assert(collectionOfFylesView == nil)
        self.collectionOfFylesView = CollectionOfFylesView(attachments: attachments, hideProgresses: hideProgresses)
        if !roundedRectStackView.arrangedSubviews.filter({ !$0.isHidden }).isEmpty {
            roundedRectStackView.addArrangedSubview(collectionOfFylesViewTopPadding)
        }
        roundedRectStackView.addArrangedSubview(collectionOfFylesView)
    }
    
    
    func refreshReplyTo(with message: PersistedMessage) {
        resetCounterOfLayoutIfNeededCalls()
        switch message.genericRepliesTo {
        case .none:
            self.repliedMessage = nil
        case .notAvailableYet:
            if roundedRectStackView.subviews.filter({ $0.accessibilityIdentifier == "replyToRoundedRectView" }).isEmpty {
                roundedRectStackView.insertArrangedSubview(replyToRoundedRectView, at: max(0, roundedRectStackView.arrangedSubviews.count-1))
            }
            prepareReplyToForReuse()
            replyToTextView.isHidden = false
            replyToTextView.text = Strings.replyToMessageUnavailable
        case .available(message: let repliedMessage):
            self.repliedMessage = repliedMessage
            // Make sure we do *not* insert the replyToRoundedRectView twice
            // If there already is a replyToRoundedRectView, we asssume it contains the appropriate values, so we return immediately
            guard roundedRectStackView.subviews.filter({ $0.accessibilityIdentifier == "replyToRoundedRectView" }).isEmpty else { return }
            // We can insert the replyToRoundedRectView and configure it
            roundedRectStackView.insertArrangedSubview(replyToRoundedRectView, at: max(0, roundedRectStackView.arrangedSubviews.count-1))
            if let repliedMessageElement = MessageCollectionViewCell.extractMessageElements(from: repliedMessage),
               let text = repliedMessageElement.text {
                replyToTextView.isHidden = false
                replyToTextView.text = text
                replyToTextView.font = repliedMessageElement.font
                if repliedMessageElement.centered {
                    replyToTextView.textAlignment = .center
                }
            }
            if let rcvMsg = repliedMessage as? PersistedMessageReceived {
                if let rcvMsgContactIdentity = rcvMsg.contactIdentity {
                    replyToLabel.text = rcvMsgContactIdentity.customDisplayName ?? rcvMsgContactIdentity.identityCoreDetails?.getDisplayNameWithStyle(.firstNameThenLastName) ?? rcvMsgContactIdentity.fullDisplayName
                } else {
                    replyToLabel.text = CommonString.deletedContact
                }
                replyToLabel.textColor = rcvMsg.contactIdentity?.cryptoId.colors.text ?? appTheme.colorScheme.secondaryLabel
                if !rcvMsg.fyleMessageJoinWithStatuses.isEmpty {
                    let numberOfAttachments = rcvMsg.fyleMessageJoinWithStatuses.count
                    replyToFylesLabel.isHidden = false
                    replyToFylesLabel.text = Strings.seeAttachments(numberOfAttachments)
                }
            } else if let sntMsg = repliedMessage as? PersistedMessageSent {
                replyToLabel.text = sntMsg.discussion.ownedIdentity?.identityCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
                replyToLabel.textColor = sntMsg.discussion.ownedIdentity?.cryptoId.colors.text
                if !sntMsg.fyleMessageJoinWithStatuses.isEmpty {
                    let numberOfAttachments = sntMsg.fyleMessageJoinWithStatuses.count
                    replyToFylesLabel.isHidden = false
                    replyToFylesLabel.text = Strings.seeAttachments(numberOfAttachments)
                }
            }
            replyToRoundedRectView.backgroundColor = replyToLabel.textColor
        case .deleted:
            if roundedRectStackView.subviews.filter({ $0.accessibilityIdentifier == "replyToRoundedRectView" }).isEmpty {
                roundedRectStackView.insertArrangedSubview(replyToRoundedRectView, at: max(0, roundedRectStackView.arrangedSubviews.count-1))
            }
            prepareReplyToForReuse()
            replyToTextView.isHidden = false
            replyToTextView.text = Strings.replyToMessageWasDeleted
        }
    }
    
    
    private func refreshBody(with message: PersistedMessage) {
        guard !message.isWiped && !message.isDeleted else { return }
        if let messageElement = MessageCollectionViewCell.extractMessageElements(from: message),
           let text = messageElement.text {
            bodyTextView.text = text
            bodyTextView.font = messageElement.font
            if messageElement.centered {
                bodyTextView.textAlignment = .center
            }
            bodyTextViewPaddingView.isHidden = false
            bodyTextView.isHidden = false
        } else {
            bodyTextView.text = nil
            bodyTextViewPaddingView.isHidden = true
            bodyTextView.isHidden = true
        }
        bodyTextView.layoutIfNeeded()
    }

    private func refreshEphemeralInformation(with message: PersistedMessage) {
        var addContainerViewForEphemeralInfos = false
        guard !message.isWiped && !message.isDeleted else { return }
        if case .tapToRead = MessageCollectionViewCell.extractMessageElements(from: message) {
            if message.readOnce {
                hStackForEphemeralConfig.addArrangedSubview(readOnceStack)
                addContainerViewForEphemeralInfos = true
            }
            if let timeInterval = message.visibilityDuration, let duration = DurationOption(rawValue: Int(timeInterval)) {
                (limitedVisibilityStack.arrangedSubviews.last as? UILabel)?.text = duration.description
                hStackForEphemeralConfig.addArrangedSubview(limitedVisibilityStack)
                addContainerViewForEphemeralInfos = true
            }
            assert(addContainerViewForEphemeralInfos) /// guarantees that tap to read must shows an additional information.
        }
        if addContainerViewForEphemeralInfos {
            roundedRectStackView.addArrangedSubview(containerViewForEphemeralInfos)
        } else {
            roundedRectStackView.removeArrangedSubview(containerViewForEphemeralInfos)
            containerViewForEphemeralInfos.removeFromSuperview()
        }
    }
    
    func refresh() {
        guard let message = self.message else { return }
        resetCounterOfLayoutIfNeededCalls()
        refreshReplyTo(with: message)
        refreshBody(with: message)
        refreshEphemeralInformation(with: message)
        if let collectionOfFylesView = self.collectionOfFylesView {
            collectionOfFylesView.refresh()
        } else if !attachments.isEmpty {
            // This happens when the messages was obtained through a user notification. In that case, the attachments are initially nil.
            // When the message is eventually downloaded from the server, we get the attachments that we update here (note that the attachments were set in the refresh method of MessageReceivedCollectionViewCell).
            insertCollectionOfFylesViewForShowingAttachments(hideProgresses: false)
        }
        refreshCellCountdown()
        refreshEditedStatus()
    }
    
    
    func refreshCellCountdown() {
        (self as? MessageReceivedCollectionViewCell)?.refreshMessageReceivedCellCountdown()
        (self as? MessageSentCollectionViewCell)?.refreshMessageReceivedCellCountdown()
    }
    
    
    
    private func displayLinkMetadata(_ metadata: LPLinkMetadata, for message: PersistedMessage, animate: Bool) {
        guard linkView == nil else { return }
        linkView = LPLinkView(metadata: metadata)
        if linkView?.traitCollection.userInterfaceStyle == .dark {
            if self is MessageReceivedCollectionViewCell {
                // Keep dark mode
            } else {
                linkView?.overrideUserInterfaceStyle = .light
            }
        } else {
            // Keep light mode
        }
        roundedRectStackView.addArrangedSubview(linkView!)
        linkView!.sizeToFit()
    }
    
    
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        
        // 2020-12-11: The following line was removed to prevent a freeze
        if counterOfLayoutIfNeededCalls > 0 {
            counterOfLayoutIfNeededCalls -= 1
            self.layoutIfNeeded()
        }

        var fittingSize = UIView.layoutFittingCompressedSize
        fittingSize.width = layoutAttributes.size.width
        let size = systemLayoutSizeFitting(fittingSize, withHorizontalFittingPriority: .defaultHigh, verticalFittingPriority: .defaultLow)
        var adjustedFrame = layoutAttributes.frame
        adjustedFrame.size.height = size.height
        layoutAttributes.frame = adjustedFrame
        
        return layoutAttributes
        
    }

    
    /// The received point shall be in the coordinate space of this cell
    private func fyleMessageJoinWithStatus(at point: CGPoint) -> FyleMessageJoinWithStatus? {
        guard let collectionOfFylesView = collectionOfFylesView else { return nil }
        let newPoint = convert(point, to: collectionOfFylesView)
        return collectionOfFylesView.fyleMessageJoinWithStatus(at: newPoint)
    }
    
    func indexOfFyleMessageJoinWithStatus(at point: CGPoint) -> Int? {
        guard let fyleMessageJoinWithStatus = fyleMessageJoinWithStatus(at: point) else { return nil }
        return self.fyleMessagesJoinWithStatus?.firstIndex(of: fyleMessageJoinWithStatus)
    }
    
    func thumbnailViewOfFyleMessageJoinWithStatus(_ attachment: FyleMessageJoinWithStatus) -> UIView? {
        return collectionOfFylesView?.thumbnailViewOfFyleMessageJoinWithStatus(attachment)
    }
    
    var countdownStackIsShown: Bool {
        roundedRectView.subviews.first(where: { $0 == countdownStack }) != nil
    }
    
}


extension MessageCollectionViewCell: UITextViewDelegate {
    
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {

        // If the URL is an invite or a configuration, we navigate to the deep link
        do {
            guard var urlComponents = URLComponents(url: URL, resolvingAgainstBaseURL: true) else { return false }
            urlComponents.scheme = "https"
            guard let newUrl = urlComponents.url else { return false }
            if let olvidURL = OlvidURL(urlRepresentation: newUrl) {
                Task { await NewAppStateManager.shared.handleOlvidURL(olvidURL) }
                return false
            }
        }

        // If we reach this point, the URL is not an Olvid URL
        if self is MessageSentCollectionViewCell && textView == self.bodyTextView {
            // In case the user tapped a link she sent, no need to ask for a confirmation
            return true
        }
        if URL.absoluteString.lowercased().starts(with: "http") || URL.absoluteString.lowercased().starts(with: "https") {
            delegate?.userSelectedURL(URL)
            return false
        } else {
            return true
        }
    }
    
}


// MARK: - Refreshing countdowns for ephemeral messages

extension MessageCollectionViewCell {

    // None of the methods/variables declared within this extension are expected to be called directely.
    // They are declared here so as to be used by both `MessageReceivedCollectionViewCell` and `MessageSentCollectionViewCell`

    /// Do not call this method directly. It is shared between `MessageReceivedCollectionViewCell` and `MessageSentCollectionViewCell`
    func removeCurrentCountdownImageView() {
        let imageViews = countdownStack.arrangedSubviews.filter({ $0 is UIImageView })
        for imageView in imageViews {
            countdownStack.removeArrangedSubview(imageView)
            imageView.removeFromSuperview()
        }
    }
    
    
    /// Do not call this method directly. It is shared between `MessageReceivedCollectionViewCell` and `MessageSentCollectionViewCell`
    func refreshCellCountdownForReadOnce() {
        replaceCountdownImageView(with: countdownImageViewReadOnce)
        countdownLabel.text = nil
    }

    
    /// Do not call this method directly. It is shared between `MessageReceivedCollectionViewCell` and `MessageSentCollectionViewCell`
    func replaceCountdownImageView(with imageView: UIImageView) {
        guard currentCountdownImageView != imageView else { return }
        removeCurrentCountdownImageView()
        countdownStack.insertArrangedSubview(imageView, at: 0)
    }

    
    var currentCountdownImageView: UIImageView? {
        countdownStack.arrangedSubviews.first as? UIImageView
    }
    
    
    /// Do not call this method directly. It is shared between `MessageReceivedCollectionViewCell` and `MessageSentCollectionViewCell`
    func refreshCellCount(expirationDate: Date, countdownImageView: UIImageView) {
        replaceCountdownImageView(with: countdownImageView)
        let duration = expirationDate.timeIntervalSinceNow
        countdownLabel.text = MessageCollectionViewCell.durationFormatter.string(from: duration)
        countdownLabel.textColor = countdownImageView.tintColor
    }


    func removeCountdownStack() {
        removeCurrentCountdownImageView()
        countdownStack.removeFromSuperview()
    }

}
