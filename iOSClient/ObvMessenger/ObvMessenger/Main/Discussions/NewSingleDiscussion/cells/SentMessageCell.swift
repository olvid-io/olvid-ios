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
import UniformTypeIdentifiers
import LinkPresentation
import CoreData
import os.log
import ObvUI
import ObvUICoreData


@available(iOS 14.0, *)
final class SentMessageCell: UICollectionViewCell, CellWithMessage, MessageCellShowingHardLinks, UIViewWithTappableStuff, CellWithPersistedMessageSent {
        
    private(set) var message: PersistedMessageSent?
    private(set) var draftObjectID: TypeSafeManagedObjectID<PersistedDraft>?
    private var indexPath: IndexPath?

    var messageSent: PersistedMessageSent? { message }

    weak var cacheDelegate: DiscussionCacheDelegate?
    weak var cellReconfigurator: CellReconfigurator?
    weak var textBubbleDelegate: TextBubbleDelegate?

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "SentMessageCell")

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.automaticallyUpdatesContentConfiguration = false
        backgroundColor = AppTheme.shared.colorScheme.discussionScreenBackground
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

    func updateWith(message: PersistedMessageSent, indexPath: IndexPath, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, cacheDelegate: DiscussionCacheDelegate?, cellReconfigurator: CellReconfigurator?, textBubbleDelegate: TextBubbleDelegate?) {
        assert(cacheDelegate != nil)
        self.message = message
        self.indexPath = indexPath
        self.draftObjectID = draftObjectID
        self.setNeedsUpdateConfiguration()
        self.cacheDelegate = cacheDelegate
        self.cellReconfigurator = cellReconfigurator
        self.textBubbleDelegate = textBubbleDelegate
    }
    
    
    func getAllShownHardLink() -> [(hardlink: HardLinkToFyle, viewShowingHardLink: UIView)] {
        var hardlinks = [(HardLinkToFyle, UIView)]()
        guard let contentView = self.contentView as? SentMessageCellContentView else { assertionFailure(); return [] }
        hardlinks.append(contentsOf: contentView.singleImageView.getAllShownHardLink())
        hardlinks.append(contentsOf: contentView.multipleImagesView.getAllShownHardLink())
        hardlinks.append(contentsOf: contentView.attachmentsView.getAllShownHardLink())
        hardlinks.append(contentsOf: contentView.audioPlayerView.getAllShownHardLink())
        return hardlinks
    }
    
    override func updateConfiguration(using state: UICellConfigurationState) {
        // 2022-06-20: Commented out during the change of the startup process.
        // X       guard AppStateManager.shared.currentState.isInitializedAndActive else {
        // X           // This prevents a crash when the user hits the home button while in the discussion.
        // X           // In that case, for some reason, this method is called and crashes because we cannot fetch faulted values once not active.
        // X           // Note that we *cannot* call setNeedsUpdateConfiguration() here, as this creates a deadlock.
        // X           return
        // X       }
        guard let message = self.message else { assertionFailure(); return }
        guard message.managedObjectContext != nil else { return } // Happens if the message has recently been deleted. Going further would crash the app.
        var content = SentMessageCellCustomContentConfiguration().updated(for: state)

        content.draftObjectID = draftObjectID
        content.messageObjectID = message.typedObjectID

        do {
            let messageObjectID = message.typedObjectID.downcast
            cacheDelegate?.requestAllHardlinksForMessage(with: messageObjectID) { [weak self] needsUpdateConfiguration in
                guard needsUpdateConfiguration && messageObjectID == self?.message?.typedObjectID.downcast else { return }
                self?.setNeedsUpdateConfiguration()
            }
        }

        content.date = message.timestamp
        content.showEditedStatus = message.isEdited
        content.readOnce = message.readOnce && !message.isWiped
        content.scheduledExistenceDestructionDate = message.expirationForSentLimitedExistence?.expirationDate
        content.scheduledVisibilityDestructionDate = message.expirationForSentLimitedVisibility?.expirationDate

        // Configure the text body (determine whether we should use data detection on the text view)
        
        content.textBubbleConfiguration = nil
        if let text = message.textBody, !message.isWiped {
            if let dataDetected = cacheDelegate?.getCachedDataDetection(text: text) {
                content.textBubbleConfiguration = TextBubble.Configuration(kind: .sent,
                                                                           text: text,
                                                                           dataDetectorTypes: dataDetected,
                                                                           mentionedUsers: message.mentions.mentionableIdentityTypesFromRange_WARNING_VIEW_CONTEXT)
            } else {
                content.textBubbleConfiguration = TextBubble.Configuration(kind: .sent,
                                                                           text: text,
                                                                           dataDetectorTypes: [],
                                                                           mentionedUsers: message.mentions.mentionableIdentityTypesFromRange_WARNING_VIEW_CONTEXT)
                cacheDelegate?.requestDataDetection(text: text) { [weak self] dataDetected in
                    assert(Thread.isMainThread)
                    guard dataDetected else { return }
                    self?.setNeedsUpdateConfiguration()
                }
            }
        }
        
        // Look for an https URL within the text
        
        content.singleLinkConfiguration = nil
        let doFetchContentRichURLsMetadataSetting = message.discussion.localConfiguration.doFetchContentRichURLsMetadata ?? ObvMessengerSettings.Discussions.doFetchContentRichURLsMetadata
        switch doFetchContentRichURLsMetadataSetting {
        case .never:
            break
        case .always, .withinSentMessagesOnly:
            if let text = message.textBody, !message.isWiped, let linkURL = cacheDelegate?.getFirstHttpsURL(text: text) {
                switch CachedLPMetadataProvider.shared.getCachedMetada(for: linkURL) {
                case .metadataCached(metadata: let metadata):
                    content.singleLinkConfiguration = .metadataAvailable(url: linkURL, metadata: metadata)
                case .siteDoesNotProvideMetada, .failureOccuredWhenFetchingOrCachingMetadata:
                    content.singleLinkConfiguration = .metadataRetrievalFailed
                case .metadaNotCachedYet:
                    content.singleLinkConfiguration = .metadataNotYetAvailable(url: linkURL)
                    CachedLPMetadataProvider.shared.fetchAndCacheMetadata(for: linkURL) { [weak self] in
                        self?.setNeedsUpdateConfiguration()
                    }
                }
            }
        }

        // Wiped view configuration
        
        if message.isLocallyWiped {
            content.wipedViewConfiguration = .locallyWiped
        } else if message.isRemoteWiped {
            if let ownedCryptoId = message.discussion.ownedIdentity?.cryptoId,
               let deleterCryptoId = message.deleterCryptoId,
               let contact = try? PersistedObvContactIdentity.get(contactCryptoId: deleterCryptoId, ownedIdentityCryptoId: ownedCryptoId, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) {
                content.wipedViewConfiguration = .remotelyWiped(deleterName: contact.customOrShortDisplayName)
            } else {
                content.wipedViewConfiguration = .remotelyWiped(deleterName: nil)
            }
        } else {
            content.wipedViewConfiguration = nil
        }
        
        // Configure images (single image, multiple image and/or gif)
        
        var imageAttachments = message.isWiped ? [] : message.fyleMessageJoinWithStatusesOfImageType
        let gifAttachment = imageAttachments.first(where: { $0.uti == UTType.gif.identifier })
        imageAttachments.removeAll(where: { $0 == gifAttachment })

        switch imageAttachments.count {
        case 0:
            content.singleImageViewConfiguration = nil
            content.multipleImagesViewConfiguration.removeAll()
        case 1:
            let size = CGSize(width: SingleImageView.imageSize, height: SingleImageView.imageSize)
            content.singleImageViewConfiguration = singleImageViewConfigurationForImageAttachment(imageAttachments.first!, size: size, requiresCellSizing: false)
            content.multipleImagesViewConfiguration.removeAll()
        default:
            content.singleImageViewConfiguration = nil
            let smallImageSize = CGSize(width: MultipleImagesView.smallImageSize, height: MultipleImagesView.smallImageSize)
            let wideImageSize = CGSize(width: MultipleImagesView.wideImageWidth, height: MultipleImagesView.smallImageSize)
            if imageAttachments.count.isMultiple(of: 2) {
                content.multipleImagesViewConfiguration = imageAttachments.map({ singleImageViewConfigurationForImageAttachment($0, size: smallImageSize, requiresCellSizing: false) })
            } else {
                let smallImageAttachments = imageAttachments[0..<imageAttachments.count-1]
                let wideImageAttachment = imageAttachments.last!
                var configurations = smallImageAttachments.map({ singleImageViewConfigurationForImageAttachment($0, size: smallImageSize, requiresCellSizing: false) })
                configurations.append(singleImageViewConfigurationForImageAttachment(wideImageAttachment, size: wideImageSize, requiresCellSizing: false))
                content.multipleImagesViewConfiguration = configurations
            }
        }
        
        if let gifAttachment = gifAttachment {
            let size = CGSize(width: SingleImageView.imageSize, height: SingleImageView.imageSize)
            content.singleGifViewConfiguration = singleImageViewConfigurationForImageAttachment(gifAttachment, size: size, requiresCellSizing: true)
        } else {
            content.singleGifViewConfiguration = nil
        }

        var otherAttachments = message.fyleMessageJoinWithStatusesOfOtherTypes

        var audioAttachments = message.isWiped ? [] : message.fyleMessageJoinWithStatusesOfAudioType
        if let firstAudioAttachment = audioAttachments.first {
            content.audioPlayerConfiguration = attachmentViewConfigurationForAttachment(firstAudioAttachment)
            audioAttachments.removeAll(where: { $0 == firstAudioAttachment })
        } else {
            content.audioPlayerConfiguration = nil
        }

        // We choose to show audioPlayer only for the first audio song.
        otherAttachments += audioAttachments

        content.multipleAttachmentsViewConfiguration = message.isWiped ? [] : otherAttachments.map({ attachmentViewConfigurationForAttachment($0) })

        // Configure the rest
        
        content.status = message.status
        content.reactionAndCounts = ReactionAndCount.of(reactions: message.reactions)

        // Configure the reply-to
        
        content.replyToBubbleViewConfiguration = cacheDelegate?.requestReplyToBubbleViewConfiguration(message: message) { [weak self] in
            self?.setNeedsUpdateConfiguration()
        }

        content.isReplyToActionAvailable = message.replyToActionCanBeMadeAvailable
        content.forwarded = message.forwarded
        
        if self.contentConfiguration as? SentMessageCellCustomContentConfiguration != content {
            self.contentConfiguration = content
        }

        registerDelegate()

        startAnimating()

    }
    
    
    private func registerDelegate() {
        guard let contentView = self.contentView as? SentMessageCellContentView else { assertionFailure(); return }
        contentView.textBubble.delegate = textBubbleDelegate
    }

    
    private func singleImageViewConfigurationForImageAttachment(_ imageAttachment: SentFyleMessageJoinWithStatus, size: CGSize, requiresCellSizing: Bool) -> SingleImageView.Configuration {
        let imageAttachmentObjectID = (imageAttachment as FyleMessageJoinWithStatus).typedObjectID
        let hardlink = cacheDelegate?.getCachedHardlinkForFyleMessageJoinWithStatus(with: imageAttachmentObjectID)
        let config: SingleImageView.Configuration
        switch imageAttachment.status {
        case .uploading, .uploadable:
            assert(cacheDelegate != nil)
            if let hardlink = hardlink {
                if let image = cacheDelegate?.getCachedImageForHardlink(hardlink: hardlink, size: size) {
                    config = .uploadableOrUploading(hardlink: hardlink, thumbnail: image, progress: imageAttachment.progressObject)
                } else {
                    config = .uploadableOrUploading(hardlink: hardlink, thumbnail: nil, progress: imageAttachment.progressObject)
                    Task {
                        do {
                            try await cacheDelegate?.requestImageForHardlink(hardlink: hardlink, size: size)
                            if requiresCellSizing {
                                cellReconfigurator?.cellNeedsToBeReconfiguredAndResized(messageID: imageAttachment.sentMessage.typedObjectID.downcast)
                            } else {
                                setNeedsUpdateConfiguration()
                            }
                        } catch {
                            os_log("The request image for hardlink to fyle %{public}@ failed: %{public}@", log: Self.log, type: .error, hardlink.fyleURL.lastPathComponent, error.localizedDescription)
                        }
                    }
                }
            } else {
                config = .uploadableOrUploading(hardlink: nil, thumbnail: nil, progress: imageAttachment.progressObject)
            }
        case .complete:
            if let hardlink = hardlink {
                if let image = cacheDelegate?.getCachedImageForHardlink(hardlink: hardlink, size: size) {
                    config = .complete(downsizedThumbnail: nil, hardlink: hardlink, thumbnail: image)
                } else {
                    config = .complete(downsizedThumbnail: nil, hardlink: hardlink, thumbnail: nil)
                    Task {
                        do {
                            try await cacheDelegate?.requestImageForHardlink(hardlink: hardlink, size: size)
                            if requiresCellSizing {
                                cellReconfigurator?.cellNeedsToBeReconfiguredAndResized(messageID: imageAttachment.sentMessage.typedObjectID.downcast)
                            } else {
                                setNeedsUpdateConfiguration()
                            }
                        } catch {
                            os_log("The request image for hardlink to fyle %{public}@ failed: %{public}@", log: Self.log, type: .error, hardlink.fyleURL.lastPathComponent, error.localizedDescription)
                        }
                    }
                }
            } else {
                config = .complete(downsizedThumbnail: nil, hardlink: nil, thumbnail: nil)
            }
        }
        return config
    }

    
    private func attachmentViewConfigurationForAttachment(_ attachment: SentFyleMessageJoinWithStatus) -> AttachmentsView.Configuration {
        let attachmentObjectID = (attachment as FyleMessageJoinWithStatus).typedObjectID
        let hardlink = cacheDelegate?.getCachedHardlinkForFyleMessageJoinWithStatus(with: attachmentObjectID)
        let config: AttachmentsView.Configuration
        let size = CGSize(width: MessageCellConstants.attachmentIconSize, height: MessageCellConstants.attachmentIconSize)
        switch attachment.status {
        case .uploading, .uploadable:
            if let hardlink = hardlink {
                if let image = cacheDelegate?.getCachedImageForHardlink(hardlink: hardlink, size: size) {
                    config = .uploadableOrUploading(hardlink: hardlink, thumbnail: image, fileSize: Int(attachment.totalByteCount), uti: attachment.uti, filename: attachment.fileName, progress: attachment.progressObject)
                } else {
                    config = .uploadableOrUploading(hardlink: hardlink, thumbnail: nil, fileSize: Int(attachment.totalByteCount), uti: attachment.uti, filename: attachment.fileName, progress: attachment.progressObject)
                    Task {
                        do {
                            try await cacheDelegate?.requestImageForHardlink(hardlink: hardlink, size: size)
                            setNeedsUpdateConfiguration()
                        } catch {
                            os_log("The request image for hardlink to fyle %{public}@ failed: %{public}@", log: Self.log, type: .error, hardlink.fyleURL.lastPathComponent, error.localizedDescription)
                        }
                    }
                }
            } else {
                config = .uploadableOrUploading(hardlink: nil, thumbnail: nil, fileSize: Int(attachment.totalByteCount), uti: attachment.uti, filename: attachment.fileName, progress: attachment.progressObject)
            }
            
        case .complete:
            if let hardlink = hardlink {
                if let image = cacheDelegate?.getCachedImageForHardlink(hardlink: hardlink, size: size) {
                    config = .complete(hardlink: hardlink, thumbnail: image, fileSize: Int(attachment.totalByteCount), uti: attachment.uti, filename: attachment.fileName, wasOpened: nil)
                } else {
                    config = .complete(hardlink: hardlink, thumbnail: nil, fileSize: Int(attachment.totalByteCount), uti: attachment.uti, filename: attachment.fileName, wasOpened: nil)
                    Task {
                        do {
                            try await cacheDelegate?.requestImageForHardlink(hardlink: hardlink, size: size)
                            setNeedsUpdateConfiguration()
                        } catch {
                            os_log("The request image for hardlink to fyle %{public}@ failed: %{public}@", log: Self.log, type: .error, hardlink.fyleURL.lastPathComponent, error.localizedDescription)
                        }
                    }
                }
            } else {
                config = .complete(hardlink: nil, thumbnail: nil, fileSize: Int(attachment.totalByteCount), uti: attachment.uti, filename: attachment.fileName, wasOpened: nil)
            }
        }
        return config
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        (contentView as? SentMessageCellContentView)?.prepareForReuse()
    }

    
    func refreshCellCountdown() {
        (contentView as? SentMessageCellContentView)?.refreshCellCountdown()
    }
 
    
    func tappedStuff(tapGestureRecognizer: UITapGestureRecognizer, acceptTapOutsideBounds: Bool) -> TappedStuffForCell? {
        guard let contentViewWithTappableStuff = contentView as? UIViewWithTappableStuff else { assertionFailure(); return nil }
        return contentViewWithTappableStuff.tappedStuff(tapGestureRecognizer: tapGestureRecognizer)
    }
    
    
    private func startAnimating() {
        (contentView as? SentMessageCellContentView)?.startAnimating()
    }
    
}



// MARK: - Implementing CellWithMessage

@available(iOS 14.0, *)
extension SentMessageCell {
     
    var persistedMessage: PersistedMessage? { message }
    
    public var persistedMessageObjectID: TypeSafeManagedObjectID<PersistedMessage>? { persistedMessage?.typedObjectID }
    
    var persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>? { draftObjectID }

    var viewForTargetedPreview: UIView { self.contentView }
    
    var textToCopy: String? {
        guard let contentView = contentView as? SentMessageCellContentView else { assertionFailure(); return nil }
        let text: String
        if let textBubbleText = contentView.textBubble.text, !textBubbleText.isEmpty, contentView.textBubble.showInStack {
            text = textBubbleText
        } else if let emojiText = contentView.emojiOnlyBodyView.text, !emojiText.isEmpty, contentView.emojiOnlyBodyView.showInStack {
            text = emojiText
        } else {
            return nil
        }
        return text
    }
    
    var fyleMessagesJoinWithStatus: [FyleMessageJoinWithStatus]? { nil }
    
    var imageAttachments: [FyleMessageJoinWithStatus]? { nil }
    
    var itemProvidersForImages: [UIActivityItemProvider]? {
        message?.fyleMessageJoinWithStatusesOfImageType
            .compactMap({ cacheDelegate?.getCachedHardlinkForFyleMessageJoinWithStatus(with: ($0 as FyleMessageJoinWithStatus).typedObjectID) })
            .compactMap({ $0.activityItemProvider })
    }
    
    var itemProvidersForAllAttachments: [UIActivityItemProvider]? {
        message?.fyleMessageJoinWithStatuses
            .compactMap({ cacheDelegate?.getCachedHardlinkForFyleMessageJoinWithStatus(with: ($0 as FyleMessageJoinWithStatus).typedObjectID) })
            .compactMap({ $0.activityItemProvider })
    }
    
    var infoViewController: UIViewController? {
        guard let message = message else { return nil }
        guard message.infoActionCanBeMadeAvailable == true else { return nil }
        let rcv = SentMessageInfosHostingViewController(messageSent: message)
        return rcv
    }

}


// MARK: - SentMessageCellCustomContentConfiguration


@available(iOS 14.0, *)
fileprivate struct SentMessageCellCustomContentConfiguration: UIContentConfiguration, Hashable {
    
    var draftObjectID: TypeSafeManagedObjectID<PersistedDraft>?
    var messageObjectID: TypeSafeManagedObjectID<PersistedMessageSent>?

    var date = Date()
    var readOnce = false
    var wipedViewConfiguration: WipedView.Configuration?
    var showEditedStatus = false

    var scheduledExistenceDestructionDate: Date?
    var scheduledVisibilityDestructionDate: Date?
    var singleImageViewConfiguration: SingleImageView.Configuration?
    var singleGifViewConfiguration: SingleImageView.Configuration?
    var multipleImagesViewConfiguration = [SingleImageView.Configuration]()
    var multipleAttachmentsViewConfiguration = [AttachmentsView.Configuration]()
    var audioPlayerConfiguration: AudioPlayerView.Configuration?

    var textBubbleConfiguration: TextBubble.Configuration?
    var singleLinkConfiguration: SingleLinkView.Configuration?
    var status = PersistedMessageSent.MessageStatus.unprocessed
    var reactionAndCounts = [ReactionAndCount]()

    var replyToBubbleViewConfiguration: ReplyToBubbleView.Configuration?

    var isReplyToActionAvailable = false
    var forwarded = false

    func makeContentView() -> UIView & UIContentView {
        return SentMessageCellContentView(configuration: self)
    }

    func updated(for state: UIConfigurationState) -> Self {
        return self
    }

}


@available(iOS 14.0, *)
fileprivate final class SentMessageCellContentView: UIView, UIContentView, UIGestureRecognizerDelegate, UIViewWithTappableStuff {
    
    private let mainStack = OlvidVerticalStackView(gap: MessageCellConstants.mainStackGap,
                                                   side: .trailing,
                                                   debugName: "Sent Message Cell Main Olvid Stack",
                                                   showInStack: true)
    fileprivate let textBubble = TextBubble(expirationIndicatorSide: .leading, bubbleColor: AppTheme.shared.colorScheme.adaptiveOlvidBlue, textColor: .white)
    fileprivate let emojiOnlyBodyView = EmojiOnlyBodyView(expirationIndicatorSide: .leading)
    private let singleLinkView = SingleLinkView(expirationIndicatorSide: .leading)
    private let statusAndDateView = SentMessageStatusAndDateView()
    fileprivate let singleImageView = SingleImageView(expirationIndicatorSide: .leading)
    fileprivate let multipleImagesView = MultipleImagesView(expirationIndicatorSide: .leading)
    private let singleGifView = SingleGifView(expirationIndicatorSide: .leading)
    fileprivate let attachmentsView = AttachmentsView(expirationIndicatorSide: .leading)
    fileprivate let multipleReactionsView = MultipleReactionsView()
    private let replyToBubbleView = ReplyToBubbleView(expirationIndicatorSide: .leading)
    private let wipedView = WipedView(expirationIndicatorSide: .leading)
    private let backgroundView = SentMessageCellBackgroundView()
    fileprivate let audioPlayerView = AudioPlayerView(expirationIndicatorSide: .leading)
    private let forwardView = ForwardView()

    private var appliedConfiguration: SentMessageCellCustomContentConfiguration!

    private var messageObjectID: TypeSafeManagedObjectID<PersistedMessageSent>?
    private var draftObjectID: TypeSafeManagedObjectID<PersistedDraft>?

    // The following variables allow to handle the pan gesture allowing to answer a specific message
    private var frameBeforeDrag: CGRect?
    private var pan: UIPanGestureRecognizer!
    private var panLimitReached = false {
        didSet {
            if pan.state != .ended && oldValue != panLimitReached {
                feedbackGenerator.impactOccurred()
                feedbackGenerator.prepare()
            }
        }
    }
    private let panLimit = MessageCellConstants.panLimitForReplyingToMessage
    private let feedbackGenerator = UIImpactFeedbackGenerator()

    init(configuration: SentMessageCellCustomContentConfiguration) {
        super.init(frame: .zero)
        setupInternalViews()
        setupPanGestureRecognizer()
        self.configuration = configuration
    }
    
    private func setupPanGestureRecognizer() {
        self.pan = UIPanGestureRecognizer(target: self, action: #selector(userDidPan(_:)))
        self.pan.delegate = self
        self.addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var configuration: UIContentConfiguration {
        get { appliedConfiguration }
        set {
            guard let newConfig = newValue as? SentMessageCellCustomContentConfiguration else { return }
            let currentConfig = appliedConfiguration
            apply(currentConfig: currentConfig, newConfig: newConfig)
            appliedConfiguration = newConfig
        }
    }

    
    /// When the user begins a pan gesture, we call `setNeedsLayout` as this will allow to store the inital frame of the view being panned.
    /// Whenever the pan gesture changes, we call `setNeedsLayout` again which makes it possible to follow the pan translation and to move
    /// the view being panned. We also track whether the pan limit is reached or not. Finally, when the pan gesture ends, we make a last call
    /// to `setNeedsLayout` which will take care of putting the view back in place.
    @objc private func userDidPan(_ pan: UIPanGestureRecognizer) {
        if pan.state == .began {
            setNeedsLayout()
            feedbackGenerator.prepare()
        } else if pan.state == .changed {
            setNeedsLayout()
            let currentTranslation = max(0, abs(pan.translation(in: self).x))
            if currentTranslation > panLimit {
                self.panLimitReached = true
                self.backgroundView.animateGiven(panFractionCompleted: 1.0)
            } else {
                self.panLimitReached = false
                self.backgroundView.animateGiven(panFractionCompleted: currentTranslation / panLimit)
            }
        } else {
            setNeedsLayout()
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0, options: []) { [weak self] in
                self?.backgroundView.reset()
                self?.layoutIfNeeded()
            }
        }
        
        if pan.state == .ended, panLimitReached {
            pan.reset()
            panLimitReached = false
            guard let messageObjectID = self.messageObjectID, let draftObjectID = self.draftObjectID else { assertionFailure(); return }
            NewSingleDiscussionNotification.userWantsToReplyToMessage(messageObjectID: messageObjectID.downcast, draftObjectID: draftObjectID)
                .postOnDispatchQueue()
        }
    }
    
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false // Set to true to allow both pan of the cell and pan of the collection view at the same time
    }
    
    
    // The pan gesture should begin when the horizontal veolocity is larger than the vertical velocity.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard pan.velocity(in: pan.view).x < 0 else { return false }
        return abs((pan.velocity(in: pan.view)).x) > abs((pan.velocity(in: pan.view)).y)
    }

    
    // We override `layoutSubviews` to make it possible to "follow" the drag gesture translation.
    override func layoutSubviews() {
        super.layoutSubviews()
                
        if pan.state == .began {
            
            frameBeforeDrag = mainStack.frame
            
        } else if pan.state == .changed {
            
            if let frameBeforeDrag = self.frameBeforeDrag {
                let translation = pan.translation(in: self)
                mainStack.frame = CGRect(x: min(frameBeforeDrag.minX, frameBeforeDrag.minX + translation.x),
                                         y: frameBeforeDrag.minY,
                                         width: frameBeforeDrag.width,
                                         height: frameBeforeDrag.height)
            }
            
        } else if pan.state == .ended {
            
            if let frameBeforeDrag = self.frameBeforeDrag {
                mainStack.frame = frameBeforeDrag
                self.frameBeforeDrag = nil
            }
            
        }
    }
    
    
    func tappedStuff(tapGestureRecognizer: UITapGestureRecognizer, acceptTapOutsideBounds: Bool) -> TappedStuffForCell? {
        var subviewsWithTappableStuff = self.mainStack.arrangedSubviews.filter({ $0.showInStack }).compactMap({ $0 as? UIViewWithTappableStuff })
        subviewsWithTappableStuff += [multipleReactionsView].filter({ !$0.isHidden })
        let view = subviewsWithTappableStuff.first(where: { $0.tappedStuff(tapGestureRecognizer: tapGestureRecognizer) != nil })
        return view?.tappedStuff(tapGestureRecognizer: tapGestureRecognizer)
    }


    private func setupInternalViews() {

        addSubview(backgroundView)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.reset()
        
        addSubview(mainStack)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        
        mainStack.addArrangedSubview(forwardView)

        mainStack.addArrangedSubview(replyToBubbleView)

        mainStack.addArrangedSubview(textBubble)
        
        mainStack.addArrangedSubview(wipedView)
        wipedView.bubbleColor = appTheme.colorScheme.adaptiveOlvidBlue
        wipedView.textColor = .white

        mainStack.addArrangedSubview(emojiOnlyBodyView)
        
        mainStack.addArrangedSubview(singleLinkView)
        
        mainStack.addArrangedSubview(singleGifView)

        mainStack.addArrangedSubview(singleImageView)

        mainStack.addArrangedSubview(multipleImagesView)

        mainStack.addArrangedSubview(audioPlayerView)

        mainStack.addArrangedSubview(attachmentsView)

        mainStack.addArrangedSubview(statusAndDateView)


        NSLayoutConstraint.activate([
            
            backgroundView.topAnchor.constraint(equalTo: self.topAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: self.leadingAnchor),

            mainStack.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: self.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            
            textBubble.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor, multiplier: 0.8),
            replyToBubbleView.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor, multiplier: 0.8),
            audioPlayerView.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor, multiplier: 0.8),

        ])

        // This constraint prevents the app from crashing in case there is nothing to display within the cell

        do {
            let safeHeightConstraint = self.heightAnchor.constraint(equalToConstant: 0)
            safeHeightConstraint.priority = .defaultLow
            safeHeightConstraint.isActive = true
        }
        
        // Last, we add the reaction view on top of everything and pin it to the status and date view
        
        addSubview(multipleReactionsView)
        multipleReactionsView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            statusAndDateView.leadingAnchor.constraint(equalTo: multipleReactionsView.trailingAnchor, constant: 8),
            statusAndDateView.bottomAnchor.constraint(equalTo: multipleReactionsView.bottomAnchor, constant: -2),
        ])

    }

    
    func prepareForReuse() {
        singleLinkView.prepareForReuse()
    }

    fileprivate func startAnimating() {
        singleGifView.startAnimating()
    }

    fileprivate func refreshCellCountdown() {
        let viewsThatCanShowExpirationIndicator = mainStack.shownArrangedSubviews.compactMap({ $0 as? ViewWithExpirationIndicator })
        viewsThatCanShowExpirationIndicator.forEach { $0.refreshCellCountdown() }
    }


    private func apply(currentConfig: SentMessageCellCustomContentConfiguration?, newConfig: SentMessageCellCustomContentConfiguration) {
        
        messageObjectID = newConfig.messageObjectID
        draftObjectID = newConfig.draftObjectID

        pan.isEnabled = newConfig.isReplyToActionAvailable
        
        // Reply-to view
        
        replyToBubbleView.showInStack = false

        if let replyToBubbleViewConfiguration = newConfig.replyToBubbleViewConfiguration {
            replyToBubbleView.configure(with: replyToBubbleViewConfiguration)
            replyToBubbleView.showInStack = true
        } else {
            replyToBubbleView.showInStack = false
        }

        // Text bubble
        
        if let textBubbleConfiguration = newConfig.textBubbleConfiguration, let text = textBubbleConfiguration.text, !text.isEmpty {
            if text.containsOnlyEmoji == true, text.count < 4 {
                emojiOnlyBodyView.text = textBubbleConfiguration.text
                textBubble.showInStack = false
                emojiOnlyBodyView.showInStack = true
            } else {
                textBubble.apply(textBubbleConfiguration)
                textBubble.showInStack = true
                emojiOnlyBodyView.showInStack = false
            }
        } else {
            textBubble.showInStack = false
            emojiOnlyBodyView.showInStack = false
        }

        // Wiped view
        
        if let wipedViewConfiguration = newConfig.wipedViewConfiguration {
            wipedView.setConfiguration(wipedViewConfiguration)
            wipedView.showInStack = true
        } else {
            wipedView.showInStack = false
        }
        
        // Single link view
        
        if let singleLinkConfiguration = newConfig.singleLinkConfiguration {
            singleLinkView.showInStack = true
            singleLinkView.setConfiguration(newConfiguration: singleLinkConfiguration)
        } else {
            singleLinkView.showInStack = false
        }

        // Images

        if let singleImageViewConfiguration = newConfig.singleImageViewConfiguration {
            singleImageView.showInStack = true
            singleImageView.setConfiguration(singleImageViewConfiguration)
        } else {
            singleImageView.showInStack = false
        }
        
        if newConfig.multipleImagesViewConfiguration.isEmpty {
            multipleImagesView.showInStack = false
        } else {
            multipleImagesView.setConfiguration(newConfig.multipleImagesViewConfiguration)
            multipleImagesView.showInStack = true
        }

        // Gif

        if let singleGifViewConfiguration = newConfig.singleGifViewConfiguration {
            singleGifView.showInStack = true
            singleGifView.setConfiguration(singleGifViewConfiguration)
        } else {
            singleGifView.showInStack = false
        }

        // Non-image attachments
        
        if newConfig.multipleAttachmentsViewConfiguration.isEmpty {
            attachmentsView.showInStack = false
        } else {
            attachmentsView.setConfiguration(newConfig.multipleAttachmentsViewConfiguration)
            attachmentsView.showInStack = true
        }

        // Audio

        if let audioPlayerConfiguration = newConfig.audioPlayerConfiguration {
            audioPlayerView.showInStack = true
            audioPlayerView.configure(with: audioPlayerConfiguration)
        } else {
            audioPlayerView.showInStack = false
        }

        if newConfig.reactionAndCounts.isEmpty {
            multipleReactionsView.setReactions(to: [ReactionAndCount(emoji: "", count: 1)], messageObjectID: messageObjectID?.downcast)
            multipleReactionsView.alpha = 0.0
        } else {
            multipleReactionsView.setReactions(to: newConfig.reactionAndCounts, messageObjectID: messageObjectID?.downcast)
            // If the multipleReactionsView is not already shown, we show it and animate its alpha and size with a nice pop effect
            if multipleReactionsView.alpha == 0.0 {
                multipleReactionsView.transform = CGAffineTransform(scaleX: 0.0, y: 0.0)
                DispatchQueue.main.async {
                    UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0, options: []) { [weak self] in
                        guard self?.messageObjectID == newConfig.messageObjectID else { return }
                        self?.multipleReactionsView.alpha = 1.0
                        self?.multipleReactionsView.transform = .identity
                    }
                }
            }
        }


        // Date and status

        if currentConfig == nil || currentConfig!.date != newConfig.date {
            statusAndDateView.setDate(to: newConfig.date)
        }
        if currentConfig == nil || currentConfig!.status != newConfig.status || currentConfig!.showEditedStatus != newConfig.showEditedStatus {
            statusAndDateView.setStatus(to: newConfig.status, showEditedStatus: newConfig.showEditedStatus)
        }
                
        // Deal with masked corners
        
        let viewsToConsiderForRoundedCorners = mainStack.shownArrangedSubviews.compactMap({ $0 as? ViewWithMaskedCorners })
        for view in viewsToConsiderForRoundedCorners {
            guard view.showInStack else { continue }
            var viewsBefore = [ViewWithMaskedCorners]()
            var viewsAfter = [ViewWithMaskedCorners]()
            var viewWasPassed = false
            for otherView in viewsToConsiderForRoundedCorners {
                if view == otherView {
                    viewWasPassed = true
                } else if viewWasPassed {
                    viewsAfter.append(otherView)
                } else {
                    viewsBefore.append(otherView)
                }
            }
            let isFirstVisibleView = viewsBefore.isEmpty
            let isLastVisibleView = viewsAfter.isEmpty
            let topMaskedCorner: UIRectCorner = isFirstVisibleView ? [.topLeft, .topRight] : [.topLeft]
            let bottomMaskedCorner: UIRectCorner = isLastVisibleView ? [.bottomRight, .bottomLeft] : [.bottomLeft]
            view.maskedCorner = topMaskedCorner.union(bottomMaskedCorner)
        }
        
        // Expiration indicators
        
        let viewsThatCanShowExpirationIndicator = mainStack.shownArrangedSubviews.compactMap({ $0 as? ViewWithExpirationIndicator })
        viewsThatCanShowExpirationIndicator.first?.configure(readingRequiresUserAction: false,
                                                             readOnce: newConfig.readOnce,
                                                             scheduledVisibilityDestructionDate: newConfig.scheduledVisibilityDestructionDate,
                                                             scheduledExistenceDestructionDate: newConfig.scheduledExistenceDestructionDate)
        for view in viewsThatCanShowExpirationIndicator.dropFirst() {
            view.configure(readingRequiresUserAction: false,
                           readOnce: false,
                           scheduledVisibilityDestructionDate: nil,
                           scheduledExistenceDestructionDate: nil)
            view.hideExpirationIndicator()
        }

        // Forward
        forwardView.showInStack = newConfig.forwarded
    }

}



@available(iOS 14.0, *)
fileprivate final class SentMessageCellBackgroundView: UIView {

    private let imageView = UIImageView()

    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }


    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    func animateGiven(panFractionCompleted: CGFloat) {
        imageView.alpha = panFractionCompleted
        imageView.transform = .init(scaleX: panFractionCompleted, y: panFractionCompleted)
    }

    func reset() {
        imageView.alpha = 0.0
        imageView.transform = .identity
    }
    
    private func setupInternalViews() {

        addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        let configuration = UIImage.SymbolConfiguration(pointSize: 32)
        let image = UIImage(systemIcon: .arrowshapeTurnUpLeftCircleFill, withConfiguration: configuration)
        imageView.image = image
        imageView.tintColor = appTheme.colorScheme.adaptiveOlvidBlue

        let constraints = [
            imageView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),
            imageView.centerYAnchor.constraint(equalTo: self.centerYAnchor, constant: MessageCellConstants.contactPictureSize/2 - 10), // We compensate the date height "by hand" with the -10
        ]
        constraints.forEach { $0.priority -= 1 }
        NSLayoutConstraint.activate(constraints)

    }

}
