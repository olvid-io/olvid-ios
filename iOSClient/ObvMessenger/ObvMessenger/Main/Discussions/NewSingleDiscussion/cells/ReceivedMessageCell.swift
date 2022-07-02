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
import CoreData
import os.log


@available(iOS 14.0, *)
final class ReceivedMessageCell: UICollectionViewCell, CellWithMessage, CellShowingHardLinks {
    
    private(set) var message: PersistedMessageReceived?
    private var draftObjectID: TypeSafeManagedObjectID<PersistedDraft>?
    private var indexPath = IndexPath(item: 0, section: 0)
    private var previousMessageIsFromSameContact = false
    
    weak var viewShowingHardLinksDelegate: ViewShowingHardLinksDelegate?
    weak var viewDisplayingContactImageDelegate: ViewDisplayingContactImageDelegate?
    weak var cacheDelegate: DiscussionCacheDelegate?
    weak var reactionsDelegate: ReactionsDelegate?
    weak var cellReconfigurator: CellReconfigurator?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.automaticallyUpdatesContentConfiguration = false
        backgroundColor = AppTheme.shared.colorScheme.discussionScreenBackground
    }
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "ReceivedMessageCell")

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

        
    func updateWith(message: PersistedMessageReceived, indexPath: IndexPath, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, previousMessageIsFromSameContact: Bool, viewShowingHardLinksDelegate: ViewShowingHardLinksDelegate?, viewDisplayingContactImageDelegate: ViewDisplayingContactImageDelegate?, cacheDelegate: DiscussionCacheDelegate?, reactionsDelegate: ReactionsDelegate?, cellReconfigurator: CellReconfigurator?) {
        assert(viewShowingHardLinksDelegate != nil)
        assert(viewDisplayingContactImageDelegate != nil)
        assert(cacheDelegate != nil)
        self.message = message
        self.indexPath = indexPath
        self.draftObjectID = draftObjectID
        self.previousMessageIsFromSameContact = previousMessageIsFromSameContact
        self.setNeedsUpdateConfiguration()
        self.viewShowingHardLinksDelegate = viewShowingHardLinksDelegate
        self.viewDisplayingContactImageDelegate = viewDisplayingContactImageDelegate
        self.cacheDelegate = cacheDelegate
        self.reactionsDelegate = reactionsDelegate
        self.cellReconfigurator = cellReconfigurator
        requestProgressesForAttachmentsOfMessage(message: message)
    }
    
    
    private static var objectIDsOfMessagesForWhichProgressesWereRequested = Set<NSManagedObjectID>()
    
    
    private func requestProgressesForAttachmentsOfMessage(message: PersistedMessageReceived) {
        guard !ReceivedMessageCell.objectIDsOfMessagesForWhichProgressesWereRequested.contains(message.objectID) else { return }
        ReceivedMessageCell.objectIDsOfMessagesForWhichProgressesWereRequested.insert(message.objectID)
        let joinObjectIDs = message.fyleMessageJoinWithStatuses.filter({ $0.status == .downloadable || $0.status == .downloading }).compactMap({ $0.objectID })
        guard !joinObjectIDs.isEmpty else { return }
        ObvMessengerInternalNotification.aViewRequiresFyleMessageJoinWithStatusProgresses(objectIDs: joinObjectIDs)
            .postOnDispatchQueue()
    }

    
    func getAllShownHardLink() -> [(hardlink: HardLinkToFyle, viewShowingHardLink: UIView)] {
        var hardlinks = [(HardLinkToFyle, UIView)]()
        guard let contentView = self.contentView as? ReceivedMessageCellContentView else { assertionFailure(); return [] }
        hardlinks.append(contentsOf: contentView.singleImageView.getAllShownHardLink())
        hardlinks.append(contentsOf: contentView.multipleImagesView.getAllShownHardLink())
        hardlinks.append(contentsOf: contentView.attachmentsView.getAllShownHardLink())
        return hardlinks
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        guard let message = self.message else { assertionFailure(); return }
        guard message.managedObjectContext != nil else { return } // Happens if the message has recently been deleted. Going further would crash the app.
        var content = ReceivedMessageCellCustomContentConfiguration().updated(for: state)

        content.messageObjectID = message.typedObjectID
        content.draftObjectID = draftObjectID

        do {
            let messageObjectID = message.typedObjectID.downcast
            cacheDelegate?.requestAllHardlinksForMessage(with: messageObjectID) { [weak self] needsUpdateConfiguration in
                guard needsUpdateConfiguration && messageObjectID == self?.message?.typedObjectID.downcast else { return }
                self?.setNeedsUpdateConfiguration()
            }
        }

        content.alwaysHideContactPictureAndNameView = message.discussion is PersistedOneToOneDiscussion || message.discussion is PersistedDiscussionOneToOneLocked
        content.previousMessageIsFromSameContact = previousMessageIsFromSameContact
        
        content.date = message.timestamp
        content.showEditedStatus = (message.isWiped || message.readingRequiresUserAction) ? false : message.isEdited
        content.readingRequiresUserAction = message.readingRequiresUserAction
        content.readOnce = message.readOnce
        content.visibilityDuration = message.visibilityDuration
        content.scheduledExistenceDestructionDate = message.expirationForReceivedLimitedExistence?.expirationDate
        content.scheduledVisibilityDestructionDate = message.expirationForReceivedLimitedVisibility?.expirationDate
        content.hasBodyText = message.isWiped ? false : message.textBodyToSend?.isEmpty == false
        content.missedMessageConfiguration = message.missedMessageCount > 0 ? MissedMessageBubble.Configuration(missedMessageCount: message.missedMessageCount) : nil

        if let contact = message.contactIdentity {
            content.contactPictureAndNameViewConfiguration = ContactPictureAndNameView.Configuration(foregroundColor: contact.cryptoId.textColor,
                                                                                                     backgroundColor: contact.cryptoId.colors.background,
                                                                                                     icon: .person,
                                                                                                     contactName: contact.customOrFullDisplayName,
                                                                                                     stringForInitial: contact.customOrFullDisplayName,
                                                                                                     photoURL: contact.customPhotoURL ?? contact.photoURL,
                                                                                                     contactObjectID: contact.typedObjectID,
                                                                                                     showGreenShield: contact.isCertifiedByOwnKeycloak,
                                                                                                     showRedShield: !contact.isActive)
        } else {
            content.contactPictureAndNameViewConfiguration = ContactPictureAndNameView.Configuration(foregroundColor: AppTheme.shared.colorScheme.secondaryLabel,
                                                                                                     backgroundColor: AppTheme.shared.colorScheme.secondarySystemFill,
                                                                                                     icon: .personFillXmark,
                                                                                                     contactName: CommonString.deletedContact,
                                                                                                     stringForInitial: nil,
                                                                                                     photoURL: nil,
                                                                                                     contactObjectID: nil,
                                                                                                     showGreenShield: false,
                                                                                                     showRedShield: false)
        }
        
        if message.isLocallyWiped {
            content.wipedViewConfiguration = .locallyWiped
        } else if message.isRemoteWiped {
            content.wipedViewConfiguration = .remotelyWiped(deleterName: nil)
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

        // Configure other types of attachments
        
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
        
        if message.readingRequiresUserAction || message.isWiped {
            
            content.textBubbleConfiguration = nil
            content.singleLinkConfiguration = nil
            content.reactionAndCounts = []
            content.replyToBubbleViewConfiguration = nil

        } else {
            
            // Configure the text body (determine whether we should use data detection on the text view)
            
            content.textBubbleConfiguration = nil
            if let text = message.textBody, !message.isWiped {
                if let dataDetected = cacheDelegate?.getCachedDataDetection(text: text) {
                    content.textBubbleConfiguration = TextBubble.Configuration(text: text, dataDetectorTypes: dataDetected)
                } else {
                    content.textBubbleConfiguration = TextBubble.Configuration(text: text, dataDetectorTypes: [])
                    cacheDelegate?.requestDataDetection(text: text) { [weak self] dataDetected in
                        guard dataDetected else { return }
                        self?.setNeedsUpdateConfiguration()
                    }
                }
            }
            
            // Look for an https URL within the text
            
            content.singleLinkConfiguration = nil
            let doFetchContentRichURLsMetadataSetting = message.discussion.localConfiguration.doFetchContentRichURLsMetadata ?? ObvMessengerSettings.Discussions.doFetchContentRichURLsMetadata
            switch doFetchContentRichURLsMetadataSetting {
            case .never, .withinSentMessagesOnly:
                break
            case .always:
                if let text = message.textBody, !message.isWiped, let linkURL = cacheDelegate?.getFirstHttpsURL(text: text) {
                    content.singleLinkConfiguration = .metadataNotYetAvailable(url: linkURL)
                    CachedLPMetadataProvider.shared.getCachedOrStartFetchingMetadata(for: linkURL) { metadata in
                        content.singleLinkConfiguration = .metadataAvailable(url: linkURL, metadata: metadata)
                    } completionHandler: { [weak self] _, error in
                        assert(Thread.isMainThread)
                        guard error == nil else { return }
                        self?.setNeedsUpdateConfiguration()
                    }
                }
            }

            content.reactionAndCounts = ReactionAndCount.of(reactions: message.reactions)
                        
            // Configure the reply-to
            
            content.replyToBubbleViewConfiguration = cacheDelegate?.requestReplyToBubbleViewConfiguration(message: message) { [weak self] in
                self?.setNeedsUpdateConfiguration()
            }
            
        }
        
        content.isReplyToActionAvailable = self.isReplyToActionAvailable

        self.contentConfiguration = content
        registerDelegate()
    }
    
    
    private func registerDelegate() {
        guard let contentView = self.contentView as? ReceivedMessageCellContentView else { assertionFailure(); return }
        contentView.singleImageView.delegate = viewShowingHardLinksDelegate
        contentView.multipleImagesView.delegate = viewShowingHardLinksDelegate
        contentView.attachmentsView.delegate = viewShowingHardLinksDelegate
        contentView.contactPictureAndNameView.viewDisplayingContactImageDelegate = viewDisplayingContactImageDelegate
        contentView.multipleReactionsView.delegate = reactionsDelegate
        contentView.reactionsDelegate = reactionsDelegate
    }

    
    private func singleImageViewConfigurationForImageAttachment(_ imageAttachment: ReceivedFyleMessageJoinWithStatus, size: CGSize, requiresCellSizing: Bool) -> SingleImageView.Configuration {
        let imageAttachmentObjectID = (imageAttachment as FyleMessageJoinWithStatus).typedObjectID
        let hardlink = cacheDelegate?.getCachedHardlinkForFyleMessageJoinWithStatus(with: imageAttachmentObjectID)
        let config: SingleImageView.Configuration
        let message = imageAttachment.receivedMessage
        switch imageAttachment.status {
        case .downloadable, .downloading:
            if message.readingRequiresUserAction {
                config = .downloadableOrDownloading(progress: imageAttachment.progress, downsizedThumbnail: nil)
            } else if let downsizedThumbnail = cacheDelegate?.getCachedDownsizedThumbnail(objectID: imageAttachment.typedObjectID), !message.readingRequiresUserAction {
                config = .downloadableOrDownloading(progress: imageAttachment.progress, downsizedThumbnail: downsizedThumbnail)
            } else {
                config = .downloadableOrDownloading(progress: imageAttachment.progress, downsizedThumbnail: nil)
                if let data = imageAttachment.downsizedThumbnail {
                    cacheDelegate?.requestDownsizedThumbnail(objectID: imageAttachment.typedObjectID, data: data, completionWhenImageCached: { [weak self] result in
                        switch result {
                        case .failure:
                            break
                        case .success:
                            if requiresCellSizing {
                                self?.cellReconfigurator?.cellNeedsToBeReconfiguredAndResized(messageID: message.typedObjectID.downcast)
                            } else {
                                self?.setNeedsUpdateConfiguration()
                            }
                        }
                    })
                }
            }
        case .complete:
            if message.readingRequiresUserAction {
                config = .completeButReadRequiresUserInteraction(messageObjectID: message.typedObjectID)
            } else {
                if let hardlink = hardlink, hardlink.hardlinkURL != nil {
                    if let image = cacheDelegate?.getCachedImageForHardlink(hardlink: hardlink, size: size) {
                        cacheDelegate?.removeCachedDownsizedThumbnail(objectID: imageAttachment.typedObjectID)
                        config = .complete(downsizedThumbnail: nil, hardlink: hardlink, thumbnail: image)
                    } else {
                        let downsizedThumbnail = cacheDelegate?.getCachedDownsizedThumbnail(objectID: imageAttachment.typedObjectID)
                        config = .complete(downsizedThumbnail: downsizedThumbnail, hardlink: hardlink, thumbnail: nil)
                        Task {
                            do {
                                try await cacheDelegate?.requestImageForHardlink(hardlink: hardlink, size: size)
                                setNeedsUpdateConfiguration()
                            } catch {
                                os_log("The request for an image for the hardlink to fyle %{public}@ failed: %{public}@", log: Self.log, type: .error, hardlink.fyleURL.lastPathComponent, error.localizedDescription)
                            }
                        }
                    }
                } else if let downsizedThumbnail = cacheDelegate?.getCachedDownsizedThumbnail(objectID: imageAttachment.typedObjectID) {
                    config = .downloadableOrDownloading(progress: imageAttachment.progress, downsizedThumbnail: downsizedThumbnail)
                } else {
                    config = .downloadableOrDownloading(progress: imageAttachment.progress, downsizedThumbnail: nil)
                    if let data = imageAttachment.downsizedThumbnail {
                        cacheDelegate?.requestDownsizedThumbnail(objectID: imageAttachment.typedObjectID, data: data, completionWhenImageCached: { [weak self] result in
                            switch result {
                            case .failure:
                                break
                            case .success:
                                self?.setNeedsUpdateConfiguration()
                            }
                        })
                    }
                }
            }
        case .cancelledByServer:
            config = .cancelledByServer
        }
        return config
    }
    

    private func attachmentViewConfigurationForAttachment(_ attachment: ReceivedFyleMessageJoinWithStatus) -> AttachmentsView.Configuration {
        let message = attachment.receivedMessage
        let filename = message.readingRequiresUserAction ? nil : attachment.fileName
        let config: AttachmentsView.Configuration
        switch attachment.status {
        case .downloadable, .downloading:
            config = .downloadableOrDownloading(progress: attachment.progress, fileSize: Int(attachment.totalUnitCount), uti: attachment.uti, filename: filename)
        case .complete:
            if message.readingRequiresUserAction {
                config = .completeButReadRequiresUserInteraction(messageObjectID: message.typedObjectID, fileSize: Int(attachment.totalUnitCount), uti: attachment.uti)
            } else {
                let attachmentObjectID = (attachment as FyleMessageJoinWithStatus).typedObjectID
                let hardlink = cacheDelegate?.getCachedHardlinkForFyleMessageJoinWithStatus(with: attachmentObjectID)
                if let hardlink = hardlink {
                    let size = CGSize(width: MessageCellConstants.attachmentIconSize, height: MessageCellConstants.attachmentIconSize)
                    if let image = cacheDelegate?.getCachedImageForHardlink(hardlink: hardlink, size: size) {
                        config = .complete(hardlink: hardlink, thumbnail: image, fileSize: Int(attachment.totalUnitCount), uti: attachment.uti, filename: filename)
                    } else {
                        config = .complete(hardlink: hardlink, thumbnail: nil, fileSize: Int(attachment.totalUnitCount), uti: attachment.uti, filename: filename)
                        if hardlink.hardlinkURL == nil {
                            // This happens when the attachment was just downloaded and we need to "refresh" the cached hardlink
                            // We do nothing since the hardlink will soon be refreshed
                        } else {
                            Task {
                                do {
                                    try await cacheDelegate?.requestImageForHardlink(hardlink: hardlink, size: size)
                                    setNeedsUpdateConfiguration()
                                } catch {
                                    os_log("The request for an image for the hardlink to fyle %{public}@ failed: %{public}@", log: Self.log, type: .error, hardlink.fyleURL.lastPathComponent, error.localizedDescription)
                                }
                            }
                        }
                    }
                } else {
                    config = .downloadableOrDownloading(progress: attachment.progress, fileSize: Int(attachment.totalUnitCount), uti: attachment.uti, filename: filename)
                }
            }
        case .cancelledByServer:
            config = .cancelledByServer(fileSize: Int(attachment.totalUnitCount), uti: attachment.uti, filename: filename)
        }
        return config
    }

    
    private static func getReactionAndCounts(from string: String) -> [ReactionAndCount] {
        var reactionAndCounts = [ReactionAndCount]()
        let emojis = Set(string.map({ $0 })).sorted()
        for emoji in emojis {
            guard String(emoji).isSingleEmoji else { assertionFailure(); continue }
            let count = string.filter({ $0 == emoji }).count
            reactionAndCounts.append(ReactionAndCount(emoji: String(emoji), count: count))
        }
        return reactionAndCounts
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        (contentView as? ReceivedMessageCellContentView)?.prepareForReuse()
    }
    
    func refreshCellCountdown() {
        (contentView as? ReceivedMessageCellContentView)?.refreshCellCountdown()
    }

}


// MARK: - Implementing CellWithMessage

@available(iOS 14.0, *)
extension ReceivedMessageCell {
     
    var isCallActionAvailable: Bool { false }

    var persistedMessage: PersistedMessage? { message }
    
    var persistedMessageObjectID: TypeSafeManagedObjectID<PersistedMessage>? { persistedMessage?.typedObjectID }
    
    var persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>? { draftObjectID }

    var viewForTargetedPreview: UIView { self.contentView }
    
    var isCopyActionAvailable: Bool {
        guard let message = message else { assertionFailure(); return false }
        return !message.readOnce
    }
    
    var textViewToCopy: UITextView? { nil }
    
    var textToCopy: String? {
        guard let contentView = contentView as? ReceivedMessageCellContentView else { assertionFailure(); return nil }
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
    
    var isSharingActionAvailable: Bool {
        guard let receivedMessage = self.message else { return false }
        guard !receivedMessage.readOnce else { return false }
        if receivedMessage.isEphemeralMessage {
            return receivedMessage.status == .read
        } else {
            return true
        }
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
    
    var isReplyToActionAvailable: Bool {
        guard let receivedMessage = message else { return false }
        let discussion = receivedMessage.discussion
        guard !(discussion is PersistedDiscussionOneToOneLocked || discussion is PersistedDiscussionGroupLocked) else { return false }
        guard !receivedMessage.readingRequiresUserAction else { return false }
        if receivedMessage.readOnce {
            return receivedMessage.status == .read
        }
        return true
    }
    
    var isDeleteActionAvailable: Bool { true }
    
    var isEditBodyActionAvailable: Bool { false }
    
    var isInfoActionAvailable: Bool {
        guard let receivedMessage = message else { return false }
        return !receivedMessage.metadata.isEmpty
    }
    
    var infoViewController: UIViewController? {
        guard isInfoActionAvailable else { return nil }
        let rcv = ReceivedMessageInfosViewController()
        rcv.receivedMessage = message
        return rcv
    }

    var isDeleteOwnReactionActionAvailable: Bool {
        guard let message = message else { return false }
        return message.reactions.contains { $0 is PersistedMessageReactionSent }
    }
}



@available(iOS 14.0, *)
fileprivate struct ReceivedMessageCellCustomContentConfiguration: UIContentConfiguration, Hashable {
    
    var draftObjectID: TypeSafeManagedObjectID<PersistedDraft>?
    var messageObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>?

    var date = Date()
    var showEditedStatus = false
    var previousMessageIsFromSameContact = false
    var readingRequiresUserAction = false
    var readOnce = false
    var visibilityDuration: TimeInterval?
    var scheduledExistenceDestructionDate: Date?
    var scheduledVisibilityDestructionDate: Date?
    var hasBodyText = false
    var singleImageViewConfiguration: SingleImageView.Configuration?
    var singleGifViewConfiguration: SingleImageView.Configuration?
    var multipleImagesViewConfiguration = [SingleImageView.Configuration]()
    var multipleAttachmentsViewConfiguration = [AttachmentsView.Configuration]()
    var audioPlayerConfiguration: AudioPlayerView.Configuration?
    var wipedViewConfiguration: WipedView.Configuration?
    var contactPictureAndNameViewConfiguration: ContactPictureAndNameView.Configuration?
    var missedMessageConfiguration: MissedMessageBubble.Configuration?

    var textBubbleConfiguration: TextBubble.Configuration?
    var singleLinkConfiguration: SingleLinkView.Configuration?
    var reactionAndCounts = [ReactionAndCount]()
    
    var replyToBubbleViewConfiguration: ReplyToBubbleView.Configuration?

    var isReplyToActionAvailable = false
    var alwaysHideContactPictureAndNameView = true

    func makeContentView() -> UIView & UIContentView {
        return ReceivedMessageCellContentView(configuration: self)
    }

    func updated(for state: UIConfigurationState) -> Self {
        return self
    }

}


@available(iOS 14.0, *)
fileprivate final class ReceivedMessageCellContentView: UIView, UIContentView, UIGestureRecognizerDelegate {
    
    private let mainStack = OlvidVerticalStackView(gap: MessageCellConstants.mainStackGap,
                                                   side: .leading,
                                                   debugName: "Received message cell main stack",
                                                   showInStack: true)
    private let tapToReadBubble = TapToReadBubble(expirationIndicatorSide: .trailing)
    fileprivate let contactPictureAndNameView = ContactPictureAndNameView()
    private var contactPictureAndNameViewZeroHeightConstraint: NSLayoutConstraint!
    fileprivate let textBubble = TextBubble(expirationIndicatorSide: .trailing, bubbleColor: AppTheme.shared.colorScheme.newReceivedCellBackground, textColor: UIColor.label)
    fileprivate let emojiOnlyBodyView = EmojiOnlyBodyView(expirationIndicatorSide: .trailing)
    private let singleLinkView = SingleLinkView(expirationIndicatorSide: .trailing)
    private let dateView = ReceivedMessageDateView()
    fileprivate let singleImageView = SingleImageView(expirationIndicatorSide: .trailing)
    fileprivate let multipleImagesView = MultipleImagesView(expirationIndicatorSide: .trailing)
    private let singleGifView = SingleGifView(expirationIndicatorSide: .trailing)
    fileprivate let attachmentsView = AttachmentsView(expirationIndicatorSide: .trailing)
    fileprivate let multipleReactionsView = MultipleReactionsView()
    private let ephemeralityInformationsView = EphemeralityInformationsView()
    private let replyToBubbleView = ReplyToBubbleView(expirationIndicatorSide: .trailing)
    private let wipedView = WipedView(expirationIndicatorSide: .trailing)
    private let backgroundView = ReceivedMessageCellBackgroundView()
    private let audioPlayerView = AudioPlayerView(expirationIndicatorSide: .trailing)
    private let bottomHorizontalStack = OlvidHorizontalStackView(gap: 4.0, side: .bothSides, debugName: "Date and reactions horizontal stack view", showInStack: true)
    fileprivate let missedMessageCountBubble = MissedMessageBubble()

    private var appliedConfiguration: ReceivedMessageCellCustomContentConfiguration!

    private var messageObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>?
    private var draftObjectID: TypeSafeManagedObjectID<PersistedDraft>?

    fileprivate weak var reactionsDelegate: ReactionsDelegate?
    
    private var doubleTapGesture: UITapGestureRecognizer!

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

    private let contactPictureSize = MessageCellConstants.contactPictureSize
    private let gapBetweenContactPictureAndMessage = MessageCellConstants.gapBetweenContactPictureAndMessage

    init(configuration: ReceivedMessageCellCustomContentConfiguration) {
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
            guard let newConfig = newValue as? ReceivedMessageCellCustomContentConfiguration else { return }
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
            let currentTranslation = max(0, pan.translation(in: self).x)
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
        guard pan.velocity(in: pan.view).x > 0 else { return false }
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
                mainStack.frame = CGRect(x: max(frameBeforeDrag.minX, frameBeforeDrag.minX + translation.x),
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

    private var constraintsForAlwaysHidingContactPictureAndNameView = [NSLayoutConstraint]()
    private var constraintsForSometimesShowingContactPictureAndNameView = [NSLayoutConstraint]()

    private func setupInternalViews() {
        
        self.addDoubleTapGestureRecognizer()

        addSubview(backgroundView)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.reset()

        addSubview(contactPictureAndNameView)
        contactPictureAndNameView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(mainStack)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        mainStack.addArrangedSubview(missedMessageCountBubble)
        
        mainStack.addArrangedSubview(tapToReadBubble)
        tapToReadBubble.bubbleColor = appTheme.colorScheme.newReceivedCellBackground

        mainStack.addArrangedSubview(replyToBubbleView)
        
        mainStack.addArrangedSubview(textBubble)

        mainStack.addArrangedSubview(wipedView)
        wipedView.bubbleColor = appTheme.colorScheme.newReceivedCellBackground
        
        mainStack.addArrangedSubview(emojiOnlyBodyView)

        mainStack.addArrangedSubview(singleLinkView)

        mainStack.addArrangedSubview(singleGifView)

        mainStack.addArrangedSubview(singleImageView)

        mainStack.addArrangedSubview(multipleImagesView)
        
        mainStack.addArrangedSubview(attachmentsView)

        mainStack.addArrangedSubview(audioPlayerView)

        mainStack.addArrangedSubview(bottomHorizontalStack)
        
        bottomHorizontalStack.addArrangedSubview(dateView)
        
        bottomHorizontalStack.addArrangedSubview(ephemeralityInformationsView)

        NSLayoutConstraint.activate([
            
            backgroundView.topAnchor.constraint(equalTo: self.topAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            
            textBubble.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor, multiplier: 0.8),
            replyToBubbleView.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor, multiplier: 0.8),

        ])
        
        constraintsForSometimesShowingContactPictureAndNameView = [

            contactPictureAndNameView.topAnchor.constraint(equalTo: self.topAnchor),
            contactPictureAndNameView.bottomAnchor.constraint(equalTo: mainStack.topAnchor),
            contactPictureAndNameView.leadingAnchor.constraint(equalTo: self.leadingAnchor),

            mainStack.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            mainStack.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: contactPictureSize + gapBetweenContactPictureAndMessage),


        ]
        
        constraintsForAlwaysHidingContactPictureAndNameView = [
            
            mainStack.topAnchor.constraint(equalTo: self.topAnchor),
            mainStack.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            mainStack.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            
        ]
        
        NSLayoutConstraint.activate(constraintsForSometimesShowingContactPictureAndNameView) // May change at config time
        
        contactPictureAndNameViewZeroHeightConstraint = contactPictureAndNameView.heightAnchor.constraint(equalToConstant: 0)
        contactPictureAndNameViewZeroHeightConstraint.priority = .required

        // This constraint prevents the app from crashing in case there is nothing to display within the cell
        
        do {
            let safeHeightConstraint = self.heightAnchor.constraint(equalToConstant: 0)
            safeHeightConstraint.priority = .defaultLow
            safeHeightConstraint.isActive = true
        }

        // Last, we add the reaction view on top of everything and pin it to the bottom horizontal stack
        
        addSubview(multipleReactionsView)
        multipleReactionsView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            bottomHorizontalStack.trailingAnchor.constraint(equalTo: multipleReactionsView.leadingAnchor, constant: -8),
            bottomHorizontalStack.bottomAnchor.constraint(equalTo: multipleReactionsView.bottomAnchor, constant: -2),
        ])
        
        textBubble.linkTapGestureRequire(toFail: doubleTapGesture)

    }

    
    func prepareForReuse() {
        singleLinkView.prepareForReuse()
    }
    
    
    private func addDoubleTapGestureRecognizer() {
        self.doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(userDoubleTappedOnThisCell))
        self.doubleTapGesture!.numberOfTapsRequired = 2
        self.addGestureRecognizer(self.doubleTapGesture!)
    }


    @objc private func userDoubleTappedOnThisCell(sender: UITapGestureRecognizer) {
        guard let messageObjectID = messageObjectID else { return }
        self.reactionsDelegate?.userDoubleTappedOnMessage(messageID: messageObjectID.downcast)
    }
    
    
    override func updateConstraints() {
        contactPictureAndNameViewZeroHeightConstraint.isActive = contactPictureAndNameView.isHidden
        super.updateConstraints()
    }
    
    
    fileprivate func refreshCellCountdown() {
        let viewsThatCanShowExpirationIndicator = mainStack.shownArrangedSubviews.compactMap({ $0 as? ViewWithExpirationIndicator })
        viewsThatCanShowExpirationIndicator.forEach { $0.refreshCellCountdown() }
    }
    
    private func apply(currentConfig: ReceivedMessageCellCustomContentConfiguration?, newConfig: ReceivedMessageCellCustomContentConfiguration) {
                
        messageObjectID = newConfig.messageObjectID
        draftObjectID = newConfig.draftObjectID
        
        pan.isEnabled = newConfig.isReplyToActionAvailable

        // Contact picture and name view
        
        if newConfig.alwaysHideContactPictureAndNameView {
            
            NSLayoutConstraint.deactivate(constraintsForSometimesShowingContactPictureAndNameView)
            NSLayoutConstraint.activate(constraintsForAlwaysHidingContactPictureAndNameView)
            contactPictureAndNameView.isHidden = true
            
        } else {
            
            NSLayoutConstraint.deactivate(constraintsForAlwaysHidingContactPictureAndNameView)
            NSLayoutConstraint.activate(constraintsForSometimesShowingContactPictureAndNameView)
            
            if newConfig.previousMessageIsFromSameContact {
                contactPictureAndNameView.isHidden = true
            } else {
                if let config = newConfig.contactPictureAndNameViewConfiguration {
                    contactPictureAndNameView.isHidden = false
                    contactPictureAndNameView.setConfiguration(config)
                } else {
                    contactPictureAndNameView.isHidden = true
                }
            }

        }

        setNeedsUpdateConstraints()

        // Missing message bubble
        if let missedMessageConfiguration = newConfig.missedMessageConfiguration {
            missedMessageCountBubble.apply(missedMessageConfiguration)
            missedMessageCountBubble.showInStack = true
        } else {
            missedMessageCountBubble.showInStack = false
        }
        
        // Tap to read bubble
        
        if newConfig.readingRequiresUserAction && newConfig.hasBodyText {
            tapToReadBubble.showInStack = true
            tapToReadBubble.messageObjectID = newConfig.messageObjectID
        } else {
            tapToReadBubble.showInStack = false
        }

        // Reply-to view
        
        if newConfig.readingRequiresUserAction {
            replyToBubbleView.showInStack = false
        } else {
            if let replyToBubbleViewConfiguration = newConfig.replyToBubbleViewConfiguration {
                replyToBubbleView.configure(with: replyToBubbleViewConfiguration)
                replyToBubbleView.showInStack = true
            } else {
                replyToBubbleView.showInStack = false
            }
        }
        
        // Text bubble
        
        if newConfig.readingRequiresUserAction {
            textBubble.showInStack = false
            emojiOnlyBodyView.showInStack = false
        } else {
            if let textBubbleConfiguration = newConfig.textBubbleConfiguration, let text = textBubbleConfiguration.text, !text.isEmpty {
                if text.containsOnlyEmoji == true, text.count < 4 {
                    emojiOnlyBodyView.text = text
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
        }
        
        // Wiped view
        
        if let wipedViewConfiguration = newConfig.wipedViewConfiguration {
            wipedView.setConfiguration(wipedViewConfiguration)
            wipedView.showInStack = true
        } else {
            wipedView.showInStack = false
        }

        // Single link view
        
        if newConfig.readingRequiresUserAction {
            singleLinkView.showInStack = false
        } else if let singleLinkConfiguration = newConfig.singleLinkConfiguration {
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
            multipleImagesView.gestureRecognizersOnImageViewsRequire(toFail: doubleTapGesture)
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
        
        // Reactions

        /* To prevent an animation glitch when displaying the first reaction, we always show the reaction view
         * even if there is no emoji. In that case, we simply set its alpha to 0.0. When the first emoji is added,
         * we animate the alpha towards 1.0
         */
        
        if newConfig.readingRequiresUserAction {
            multipleReactionsView.isHidden = true
        } else {
            multipleReactionsView.isHidden = false
            if newConfig.reactionAndCounts.isEmpty {
                multipleReactionsView.setReactions(to: [ReactionAndCount(emoji: "", count: 1)], messageID: messageObjectID?.downcast)
                multipleReactionsView.alpha = 0.0
            } else {
                multipleReactionsView.setReactions(to: newConfig.reactionAndCounts, messageID: messageObjectID?.downcast)
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
        }
        
        // Date and show edit status
        
        if currentConfig == nil || currentConfig!.date != newConfig.date {
            dateView.date = newConfig.date
        }
        if currentConfig == nil || currentConfig!.showEditedStatus != newConfig.showEditedStatus {
            dateView.showEditedStatus = newConfig.showEditedStatus
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
            let topMaskedCorner: UIRectCorner = isFirstVisibleView ? [.topLeft, .topRight] : [.topRight]
            let bottomMaskedCorner: UIRectCorner = isLastVisibleView ? [.bottomRight, .bottomLeft] : [.bottomRight]
            view.maskedCorner = topMaskedCorner.union(bottomMaskedCorner)
        }
        
        // Expiration indicators
        
        let viewsThatCanShowExpirationIndicator = mainStack.shownArrangedSubviews.compactMap({ $0 as? ViewWithExpirationIndicator })
        viewsThatCanShowExpirationIndicator.first?.configure(readingRequiresUserAction: newConfig.readingRequiresUserAction,
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
        
        
        // Expiration informations
        
        if newConfig.readingRequiresUserAction {
            ephemeralityInformationsView.configure(readOnce: newConfig.readOnce, visibilityDuration: newConfig.visibilityDuration)
        } else {
            ephemeralityInformationsView.hide()
        }
        
    }
    
}



@available(iOS 14.0, *)
private class ReceivedMessageDateView: ViewForOlvidStack {
    
    var date = Date() {
        didSet {
            if oldValue != date {
                label.text = dateFormatter.string(from: date)
            }
        }
    }
    
    var showEditedStatus: Bool {
        get { editedStatusImageView.showInStack }
        set { editedStatusImageView.showInStack = newValue }
    }
    
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.dateStyle = .none
        df.timeStyle = .short
        df.locale = Locale.current
        return df
    }()

    
    private let stack = OlvidHorizontalStackView(gap: 6.0, side: .bothSides, debugName: "Received message status and date view stack view", showInStack: true)
    private let label = UILabelForOlvidStack()
    private let editedStatusImageView = UIImageViewForOlvidStack()
    
    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }
    

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    private func setupInternalViews() {
        
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(label)
        label.textColor = .secondaryLabel
        label.font = UIFont.preferredFont(forTextStyle: .caption1)
        label.numberOfLines = 0 // Important, otherwise the label does not defines its height

        stack.addArrangedSubview(editedStatusImageView)
        let config = UIImage.SymbolConfiguration(font: UIFont.preferredFont(forTextStyle: .caption1))
        editedStatusImageView.image = UIImage(systemIcon: .pencilCircleFill, withConfiguration: config)
        editedStatusImageView.contentMode = .scaleAspectFit
        editedStatusImageView.showInStack = false
        editedStatusImageView.tintColor = .secondaryLabel
        
        let leadingPadding = CGFloat(4)
        let constraints = [
            stack.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: leadingPadding),
            stack.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            stack.topAnchor.constraint(equalTo: self.topAnchor),
            stack.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ]
        
        NSLayoutConstraint.activate(constraints)

        let heightConstraint = self.heightAnchor.constraint(equalTo: label.heightAnchor)
        heightConstraint.priority = .defaultLow
        NSLayoutConstraint.activate([heightConstraint])

        
    }
}


@available(iOS 14.0, *)
fileprivate final class ContactPictureAndNameView: UIView {
    
    private let circledInitialsView = NewCircledInitialsView()
    private let contactNameView = ContactNameView()
    private let pictureNameGap = CGFloat(6)

    override var isHidden: Bool {
        get { super.isHidden }
        set {
            circledInitialsView.isHidden = newValue
            contactNameView.isHidden = newValue
            super.isHidden = newValue
        }
    }
    
    struct Configuration: Equatable, Hashable {
        let foregroundColor: UIColor
        let backgroundColor: UIColor
        let icon: ObvSystemIcon
        let contactName: String
        let stringForInitial: String?
        let photoURL: URL?
        let contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>?
        let showGreenShield: Bool
        let showRedShield: Bool
    }
    
    private var currentConfiguration: Configuration?
    weak var viewDisplayingContactImageDelegate: ViewDisplayingContactImageDelegate?
    
    func setConfiguration(_ newConfiguration: Configuration) {
        guard newConfiguration != currentConfiguration else { return }
        currentConfiguration = newConfiguration
        contactNameView.name = newConfiguration.contactName
        contactNameView.color = newConfiguration.foregroundColor
        circledInitialsView.configureWith(foregroundColor: newConfiguration.foregroundColor,
                                          backgroundColor: newConfiguration.backgroundColor,
                                          icon: newConfiguration.icon,
                                          stringForInitial: newConfiguration.stringForInitial,
                                          photoURL: newConfiguration.photoURL,
                                          showGreenShield: newConfiguration.showGreenShield,
                                          showRedShield: newConfiguration.showRedShield)
    }


    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }
    

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    private func setupInternalViews() {
        
        addSubview(circledInitialsView)
        circledInitialsView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(contactNameView)
        contactNameView.translatesAutoresizingMaskIntoConstraints = false
        
        let constraints = [
            circledInitialsView.topAnchor.constraint(equalTo: self.topAnchor),
            circledInitialsView.trailingAnchor.constraint(equalTo: contactNameView.leadingAnchor, constant: -pictureNameGap),
            circledInitialsView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            circledInitialsView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            contactNameView.topAnchor.constraint(equalTo: self.topAnchor),
            contactNameView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            contactNameView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ]
        constraints.forEach { $0.priority -= 1 }
        NSLayoutConstraint.activate(constraints)

        circledInitialsView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(circledInitialsViewWasTapped)))
        
    }
    
    
    @objc private func circledInitialsViewWasTapped() {
        guard let contactObjectId = currentConfiguration?.contactObjectID else { return }
        assert(viewDisplayingContactImageDelegate != nil)
        viewDisplayingContactImageDelegate?.userDidTapOnContactImage(contactObjectID: contactObjectId)
    }
    
}


@available(iOS 14.0, *)
fileprivate final class ReceivedMessageCellBackgroundView: UIView {

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
            imageView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: MessageCellConstants.contactPictureSize),
            imageView.centerYAnchor.constraint(equalTo: self.centerYAnchor, constant: MessageCellConstants.contactPictureSize/2 - 10), // We compensate the date height "by hand" with the -10
        ]
        constraints.forEach { $0.priority -= 1 }
        NSLayoutConstraint.activate(constraints)

    }

}
