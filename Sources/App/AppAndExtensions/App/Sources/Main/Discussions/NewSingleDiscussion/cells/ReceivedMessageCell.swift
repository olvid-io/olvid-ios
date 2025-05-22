/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvUI
import ObvUICoreData
//import UI_CircledInitialsView_CircledInitialsConfiguration
import ObvUIObvCircledInitials
import LinkPresentation
import ObvEncoder
import ObvUIObvCircledInitials
import ObvSettings
import ObvDesignSystem
import ObvAppCoreConstants


final class ReceivedMessageCell: UICollectionViewCell, CellWithMessage, MessageCellShowingHardLinks, UIViewWithTappableStuff, CellWithPersistedMessageReceived {
    
    private(set) var message: PersistedMessageReceived?
    private var draftObjectID: TypeSafeManagedObjectID<PersistedDraft>?
    private var indexPath = IndexPath(item: 0, section: 0)
    private var previousMessageIsFromSameContact = false
    private var searchedTextToHighlight: String?
    
    var messageReceived: PersistedMessageReceived? { message }
    
    weak var cacheDelegate: DiscussionCacheDelegate?
    weak var shortcutMenuDelegate: CellMessageShortcutMenuDelegate?
    weak var cellReconfigurator: CellReconfigurator?
    weak var textBubbleDelegate: TextBubbleDelegate?
    weak var audioPlayerViewDelegate: AudioPlayerViewDelegate?
    weak var locationViewDelegate: LocationViewDelegate?
    weak var replyToDelegate: CellReplyToDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.automaticallyUpdatesContentConfiguration = false
        backgroundColor = AppTheme.shared.colorScheme.discussionScreenBackground
        
        //On Catalyst, we're adding an hover gesture recognizer
        if ObvMessengerConstants.targetEnvironmentIsMacCatalyst {
            let hoverGestureRecognizer = UIHoverGestureRecognizer(target: self, action: #selector(hovering(_:)))
            self.addGestureRecognizer(hoverGestureRecognizer)
        }
    }
    
    // Mark: Hovering View for Mac Catalyst
    private var hoveringView: UIView?
    
    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "ReceivedMessageCell")

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

        
    func updateWith(message: PersistedMessageReceived, searchedTextToHighlight: String?, indexPath: IndexPath, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, previousMessageIsFromSameContact: Bool, cacheDelegate: DiscussionCacheDelegate?, cellReconfigurator: CellReconfigurator?, textBubbleDelegate: TextBubbleDelegate, audioPlayerViewDelegate: AudioPlayerViewDelegate?, shortcutMenuDelegate: CellMessageShortcutMenuDelegate?, replyToDelegate: CellReplyToDelegate, locationViewDelegate: LocationViewDelegate?) {
        assert(cacheDelegate != nil)
        self.message = message
        self.indexPath = indexPath
        self.draftObjectID = draftObjectID
        self.previousMessageIsFromSameContact = previousMessageIsFromSameContact
        self.setNeedsUpdateConfiguration()
        self.cacheDelegate = cacheDelegate
        self.cellReconfigurator = cellReconfigurator
        self.textBubbleDelegate = textBubbleDelegate
        self.audioPlayerViewDelegate = audioPlayerViewDelegate
        self.searchedTextToHighlight = searchedTextToHighlight
        self.shortcutMenuDelegate = shortcutMenuDelegate
        self.locationViewDelegate = locationViewDelegate
        self.replyToDelegate = replyToDelegate
    }
    
    
    func getAllShownHardLink() -> [(hardlink: HardLinkToFyle, viewShowingHardLink: UIView)] {
        var hardlinks = [(HardLinkToFyle, UIView)]()
        guard let contentView = self.contentView as? ReceivedMessageCellContentView else { assertionFailure(); return [] }
        hardlinks.append(contentsOf: contentView.singleImageView.getAllShownHardLink())
        hardlinks.append(contentsOf: contentView.multipleImagesView.getAllShownHardLink())
        hardlinks.append(contentsOf: contentView.attachmentsView.getAllShownHardLink())
        hardlinks.append(contentsOf: contentView.audioPlayerView.getAllShownHardLink())
        hardlinks.append(contentsOf: contentView.singlePDFView.getAllShownHardLink())
        return hardlinks
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        // 2022-06-20 We used to check here whether the app is initialized and active. The app should always be initialized at this point, but not necessarilly active..
        guard let message = self.message else { assertionFailure(); return }
        guard message.managedObjectContext != nil && !message.isDeleted else { return } // Happens if the message has recently been deleted. Going further would crash the app.
        guard let messageDiscussion = message.discussion, !messageDiscussion.isDeleted else { return }
        var content = ReceivedMessageCellCustomContentConfiguration().updated(for: state)

        content.messageObjectID = message.typedObjectID
        content.draftObjectID = draftObjectID

        do {
            let messageObjectID = message.typedObjectID.downcast
            printDebugLog2(message: message)
            cacheDelegate?.requestAllRelevantHardlinksForMessage(with: messageObjectID) { [weak self] needsUpdateConfiguration in
                self?.printDebugLog3(messageObjectID: messageObjectID, needsUpdateConfiguration: needsUpdateConfiguration)
                guard needsUpdateConfiguration && messageObjectID == self?.message?.typedObjectID.downcast else {
                    self?.printDebugLog4(messageObjectID: messageObjectID, willCallSetNeedsUpdateConfiguration: false)
                    return
                }
                self?.printDebugLog4(messageObjectID: messageObjectID, willCallSetNeedsUpdateConfiguration: true)
                self?.setNeedsUpdateConfiguration()
            }
        }

        switch try? message.discussion?.kind {
        case .oneToOne:
            content.alwaysHideContactPictureAndNameView = true
        case .groupV1, .groupV2, .none:
            content.alwaysHideContactPictureAndNameView = false
        }
        content.previousMessageIsFromSameContact = previousMessageIsFromSameContact
        
        content.date = message.timestamp
        content.showEditedStatus = (message.isWiped || message.readingRequiresUserAction || message.isLocationMessage) ? false : message.isEdited
        content.readingRequiresUserAction = message.readingRequiresUserAction
        content.readOnce = message.readOnce
        content.visibilityDuration = message.visibilityDuration
        content.scheduledExistenceDestructionDate = message.expirationForReceivedLimitedExistence?.expirationDate
        content.scheduledVisibilityDestructionDate = message.expirationForReceivedLimitedVisibility?.expirationDate
        content.hasBodyText = message.isWiped ? false : message.textBodyToSend?.isEmpty == false
        content.missedMessageConfiguration = message.missedMessageCount > 0 ? MissedMessageBubble.Configuration(missedMessageCount: message.missedMessageCount) : nil

        if let contact = message.contactIdentity {
            content.contactPictureAndNameViewConfiguration =
            ContactPictureAndNameView.Configuration(foregroundColor: contact.cryptoId.colors.text,
                                                    contactName: contact.nameForContactNameInGroupDiscussion,
                                                    contactObjectID: contact.typedObjectID,
                                                    circledInitialsConfiguration: contact.circledInitialsConfiguration)
        } else {
            content.contactPictureAndNameViewConfiguration =
            ContactPictureAndNameView.Configuration(foregroundColor: AppTheme.shared.colorScheme.secondaryLabel,
                                                    contactName: CommonString.deletedContact,
                                                    contactObjectID: nil,
                                                    circledInitialsConfiguration: .icon(.personFillXmark))
        }
        
        if message.isLocallyWiped {
            content.wipedViewConfiguration = .locallyWiped
        } else if message.isRemoteWiped {
            if let ownedCryptoId = message.discussion?.ownedIdentity?.cryptoId,
               let deleterCryptoId = message.deleterCryptoId,
               let contact = try? PersistedObvContactIdentity.get(contactCryptoId: deleterCryptoId, ownedIdentityCryptoId: ownedCryptoId, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) {
                content.wipedViewConfiguration = .remotelyWiped(deleterName: contact.customOrShortDisplayName)
            } else if let ownedCryptoId = message.discussion?.ownedIdentity?.cryptoId,
                      let deleterCryptoId = message.deleterCryptoId,
                      deleterCryptoId == ownedCryptoId {
                content.wipedViewConfiguration = .remotelyWiped(deleterName: CommonString.Word.You.lowercased())
            } else {
                content.wipedViewConfiguration = .remotelyWiped(deleterName: nil)
            }
        } else {
            content.wipedViewConfiguration = nil
        }
        content.forwarded = message.forwarded

        // Configure images (single image, multiple image and/or gif/webP)
        
        var imageAttachments = message.isWiped ? [] : message.fyleMessageJoinWithStatusesOfImageType
        let gifAttachment = imageAttachments.first(where: { $0.uti == UTType.gif.identifier }) ?? imageAttachments.first(where: { $0.uti == UTType.webP.identifier })
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
        
        // Configure the location View
        if message.isLocationMessage {
            let location = message.locationContinuousReceived ?? message.locationOneShotReceived
            let circledInitialsConfiguration = message.contactIdentity?.circledInitialsConfiguration
            let isSharingLocationExpired: Bool
            if message.locationOneShotReceived != nil {
                isSharingLocationExpired = false
            } else {
                isSharingLocationExpired = message.locationContinuousReceived?.isSharingLocationExpired ?? true // If nil, we know the sharing expired
            }
            let locationViewConfiguration = LocationView.Configuration(latitude: location?.latitude ?? 0,
                                                                       longitude: location?.longitude,
                                                                       address: location?.address,
                                                                       sharingType: try? location?.continuousOrOneShot,
                                                                       expirationDate: location?.sharingExpiration?.timeIntervalSince1970,
                                                                       isSharingLocationExpired: isSharingLocationExpired,
                                                                       userCircledInitialsConfiguration: circledInitialsConfiguration,
                                                                       userCanStopSharingLocation: false,
                                                                       sentFromAnotherDevice: false,
                                                                       messageObjectID: message.typedObjectID.downcast)
            content.locationViewConfiguration = locationViewConfiguration
        } else {
            content.locationViewConfiguration = nil
        }
        
        // Configure link-preview type of attachments

        var otherAttachments = message.fyleMessageJoinWithStatusesOfOtherTypes
        let previewAttachments = message.isWiped ? [] : message.fyleMessageJoinWithStatusesOfPreviewType
        let singlePreviewConfiguration: SinglePreviewView.Configuration?
        if let previewAttachment = previewAttachments.first {
            singlePreviewConfiguration = singlePreviewViewConfigurationForPreviewAttachment(previewAttachment)
        } else {
            singlePreviewConfiguration = nil
        }
        content.singlePreviewConfiguration = singlePreviewConfiguration

        // We remove the link-preview from the attachments

        otherAttachments = otherAttachments.filter { !previewAttachments.contains($0) }
        
        // Configure other types of attachments

        var audioAttachments = message.isWiped ? [] : message.fyleMessageJoinWithStatusesOfAudioType
        if let firstAudioAttachment = audioAttachments.first {
            content.audioPlayerConfiguration = attachmentViewConfigurationForAttachment(firstAudioAttachment)
            audioAttachments.removeAll(where: { $0 == firstAudioAttachment })
        } else {
            content.audioPlayerConfiguration = nil
        }

        // We choose to show audioPlayer only for the first audio song.
        
        otherAttachments += audioAttachments

        // The first pdf/docx/... attachment must have a large preview

        let fyleMessageJoinWithStatusesOfPDFOrOtherDocumentLikeType = message.isWiped ? nil : message.fyleMessageJoinWithStatusesOfPDFOrOtherDocumentLikeType.first
        if let fyleMessageJoinWithStatusesOfPDFOrOtherDocumentLikeType {
            content.singlePDFViewConfiguration = attachmentViewConfigurationForAttachment(fyleMessageJoinWithStatusesOfPDFOrOtherDocumentLikeType,
                                                                                          size: .cropBottom(mandatoryWidth: SinglePDFView.singlePDFViewWidth,
                                                                                                            maxHeight: SinglePDFView.singlePDFPreviewMaxHeight))
        } else {
            content.singlePDFViewConfiguration = nil
        }

        // Add the remaining attachments
        
        content.multipleAttachmentsViewConfiguration = message.isWiped ? [] : otherAttachments
            .filter({ $0 != fyleMessageJoinWithStatusesOfPDFOrOtherDocumentLikeType })
            .map({ attachmentViewConfigurationForAttachment($0, size: .full(minSize: SingleAttachmentView.sizeForRequestingThumbnail)) })
        
        // Configure the rest
        
        // if it is a location message, we only want to display location informations.
        if message.readingRequiresUserAction || message.isWiped {
            
            content.textBubbleConfiguration = nil
            content.singlePreviewConfiguration = nil
            content.reactionAndCounts = []
            content.replyToBubbleViewConfiguration = nil
            content.locationViewConfiguration = nil

        } else if message.isLocationMessage && content.locationViewConfiguration != nil {
            
            content.textBubbleConfiguration = nil
            content.singlePreviewConfiguration = nil
            content.replyToBubbleViewConfiguration = nil
            content.singleImageViewConfiguration = nil
            content.singleGifViewConfiguration = nil
            content.multipleImagesViewConfiguration = []
            content.multipleAttachmentsViewConfiguration = []
            content.audioPlayerConfiguration = nil
            content.wipedViewConfiguration = nil
            content.singlePreviewConfiguration = nil
            content.singlePDFViewConfiguration = nil
            content.reactionAndCounts = ReactionAndCount.of(reactions: message.reactions)
            
        } else {
            
            // Configure the text body (determine whether we should use data detection on the text view)
            
            content.textBubbleConfiguration = nil
            let previewURLToRemove = ObvMessengerSettings.Interface.hideTrailingURLInMessagesWhenPreviewIsAvailable ? singlePreviewConfiguration?.preview?.url : nil
            if let attributedTextBody = message.getDisplayableAttributedBody(removingTrailingURL: previewURLToRemove), !message.isWiped {
                
                let dataDetectorMatches = cacheDelegate?.getCachedDataDetection(attributedString: attributedTextBody)
                content.textBubbleConfiguration = TextBubble.Configuration(kind: .received,
                                                                           attributedText: attributedTextBody,
                                                                           dataDetectorMatches: dataDetectorMatches ?? [],
                                                                           searchedTextToHighlight: searchedTextToHighlight)
                if let cacheDelegate, dataDetectorMatches == nil {
                    cacheDelegate.requestDataDetection(attributedString: attributedTextBody) { [weak self] dataDetected in
                        guard dataDetected else { return }
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
        
        content.isReplyToActionAvailable = message.replyToActionCanBeMadeAvailable

        if self.contentConfiguration as? ReceivedMessageCellCustomContentConfiguration != content {
            self.contentConfiguration = content
        }
        registerDelegate()
    }
    
    
    private func registerDelegate() {
        guard let contentView = self.contentView as? ReceivedMessageCellContentView else { assertionFailure(); return }
        contentView.textBubble.delegate = textBubbleDelegate
        contentView.audioPlayerView.delegate = audioPlayerViewDelegate
        contentView.locationView.delegate = locationViewDelegate
        contentView.replyToDelegate = self.replyToDelegate
    }

    
    private func singleImageViewConfigurationForImageAttachment(_ imageAttachment: ReceivedFyleMessageJoinWithStatus, size: CGSize, requiresCellSizing: Bool) -> SingleImageView.Configuration {
        let imageAttachmentObjectID = (imageAttachment as FyleMessageJoinWithStatus).typedObjectID
        let hardlink = cacheDelegate?.getCachedHardlinkForFyleMessageJoinWithStatus(with: imageAttachmentObjectID)
        let config: SingleImageView.Configuration
        let message = imageAttachment.receivedMessage
        switch imageAttachment.status {
        case .downloadable, .downloading:
            if message.readingRequiresUserAction {
                if imageAttachment.status == .downloadable {
                    config = .downloadable(receivedJoinObjectID: imageAttachment.typedObjectID,
                                           progress: imageAttachment.progressObject,
                                           downsizedThumbnail: nil)
                } else {
                    config = .downloading(receivedJoinObjectID: imageAttachment.typedObjectID,
                                          progress: imageAttachment.progressObject,
                                          downsizedThumbnail: nil)
                }
            } else if let downsizedThumbnail = cacheDelegate?.getCachedDownsizedThumbnail(objectID: imageAttachment.typedObjectID.downcast), !message.readingRequiresUserAction {
                if imageAttachment.status == .downloadable {
                    config = .downloadable(receivedJoinObjectID: imageAttachment.typedObjectID,
                                           progress: imageAttachment.progressObject,
                                           downsizedThumbnail: downsizedThumbnail)
                } else {
                    config = .downloading(receivedJoinObjectID: imageAttachment.typedObjectID,
                                          progress: imageAttachment.progressObject,
                                          downsizedThumbnail: downsizedThumbnail)
                }
            } else {
                if imageAttachment.status == .downloadable {
                    config = .downloadable(receivedJoinObjectID: imageAttachment.typedObjectID,
                                           progress: imageAttachment.progressObject,
                                           downsizedThumbnail: nil)
                } else {
                    config = .downloading(receivedJoinObjectID: imageAttachment.typedObjectID,
                                          progress: imageAttachment.progressObject,
                                          downsizedThumbnail: nil)
                }
                if let data = imageAttachment.downsizedThumbnail {
                    cacheDelegate?.requestDownsizedThumbnail(objectID: imageAttachment.typedObjectID.downcast, data: data, completionWhenImageCached: { [weak self] result in
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
                printDebugLog(message: message, hardlink: hardlink)
                if let hardlink = hardlink, hardlink.hardlinkURL != nil {
                    if let image = cacheDelegate?.getCachedImageForHardlink(hardlink: hardlink, size: .full(minSize: size)) {
                        cacheDelegate?.removeCachedDownsizedThumbnail(objectID: imageAttachment.typedObjectID.downcast)
                        config = .complete(downsizedThumbnail: nil, hardlink: hardlink, thumbnail: image)
                    } else {
                        let downsizedThumbnail = cacheDelegate?.getCachedDownsizedThumbnail(objectID: imageAttachment.typedObjectID.downcast)
                        config = .complete(downsizedThumbnail: downsizedThumbnail, hardlink: hardlink, thumbnail: nil)
                        Task {
                            do {
                                try await cacheDelegate?.requestImageForHardlink(hardlink: hardlink, size: .full(minSize: sizeForUIDragItemPreview))
                                try await cacheDelegate?.requestImageForHardlink(hardlink: hardlink, size: .full(minSize: size))
                                setNeedsUpdateConfiguration()
                            } catch {
                                os_log("The request for an image for the hardlink to fyle %{public}@ failed: %{public}@", log: Self.log, type: .error, hardlink.fyleURL.lastPathComponent, error.localizedDescription)
                            }
                        }
                    }
                } else if let downsizedThumbnail = cacheDelegate?.getCachedDownsizedThumbnail(objectID: imageAttachment.typedObjectID.downcast) {
                    config = .downloading(receivedJoinObjectID: imageAttachment.typedObjectID,
                                          progress: imageAttachment.progressObject,
                                          downsizedThumbnail: downsizedThumbnail)
                } else {
                    config = .downloading(receivedJoinObjectID: imageAttachment.typedObjectID,
                                          progress: imageAttachment.progressObject,
                                          downsizedThumbnail: nil)
                    if let data = imageAttachment.downsizedThumbnail {
                        cacheDelegate?.requestDownsizedThumbnail(objectID: imageAttachment.typedObjectID.downcast, data: data, completionWhenImageCached: { [weak self] result in
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
    
    
    private func printDebugLog(message: PersistedMessageReceived, hardlink: HardLinkToFyle?) {
        let hardlinkIsNonNil = (hardlink != nil)
        let hardlinkURLIsNonNil = (hardlink?.hardlinkURL != nil)
        let fileIsAvailableOnDisk: Bool
        if let hardlinkURL = hardlink?.hardlinkURL {
            if FileManager.default.fileExists(atPath: hardlinkURL.path) {
                fileIsAvailableOnDisk = true
            } else {
                fileIsAvailableOnDisk = false
            }
        } else {
            fileIsAvailableOnDisk = false
        }
        os_log("🧷 [%{public}@][%{public}@] hardlinkIsNonNil=%{public}@ hardlinkURLIsNonNil=%{public}@ fileIsAvailableOnDisk=%{public}@", log: Self.log, type: .info, message.objectID.hashValue.description, String(message.textBody?.prefix(8) ?? "None"), hardlinkIsNonNil.description, hardlinkURLIsNonNil.description, fileIsAvailableOnDisk.description)

    }
    
    private func printDebugLog2(message: PersistedMessageReceived) {
        os_log("🧷 [%{public}@][%{public}@] Call to requestAllHardlinksForMessage", log: Self.log, type: .info, message.objectID.hashValue.description, String(message.textBody?.prefix(8) ?? "None"))
    }
    
    private func printDebugLog3(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, needsUpdateConfiguration: Bool) {
        os_log("🧷 [%{public}@] requestAllHardlinksForMessage completion needsUpdateConfiguration=%{public}@", log: Self.log, type: .info, messageObjectID.hashValue.description, needsUpdateConfiguration.description)
    }

    private func printDebugLog4(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, willCallSetNeedsUpdateConfiguration: Bool) {
        os_log("🧷 [%{public}@] requestAllHardlinksForMessage completion willCallSetNeedsUpdateConfiguration=%{public}@", log: Self.log, type: .info, messageObjectID.hashValue.description, willCallSetNeedsUpdateConfiguration.description)
    }

    private func attachmentViewConfigurationForAttachment(_ attachment: ReceivedFyleMessageJoinWithStatus, size: ObvDiscussionThumbnailSize = .full(minSize: CGSize(width: MessageCellConstants.attachmentIconSize, height: MessageCellConstants.attachmentIconSize))) -> SingleAttachmentView.Configuration {
        let message = attachment.receivedMessage
        let filename = message.readingRequiresUserAction ? nil : attachment.fileName
        let config: SingleAttachmentView.Configuration
        switch attachment.status {
        case .downloadable:
            config = .downloadable(receivedJoinObjectID: attachment.typedObjectID,
                                   progress: attachment.progressObject,
                                   fileSize: Int(attachment.totalByteCount),
                                   uti: attachment.uti,
                                   filename: filename)
        case .downloading:
            config = .downloading(receivedJoinObjectID: attachment.typedObjectID,
                                  progress: attachment.progressObject,
                                  fileSize: Int(attachment.totalByteCount),
                                  uti: attachment.uti,
                                  filename: filename)
        case .complete:
            if message.readingRequiresUserAction {
                config = .completeButReadRequiresUserInteraction(messageObjectID: message.typedObjectID, fileSize: Int(attachment.totalByteCount), uti: attachment.uti)
            } else {
                let attachmentObjectID = (attachment as FyleMessageJoinWithStatus).typedObjectID
                let hardlink = cacheDelegate?.getCachedHardlinkForFyleMessageJoinWithStatus(with: attachmentObjectID)
                if let hardlink = hardlink {
                    if let image = cacheDelegate?.getCachedImageForHardlink(hardlink: hardlink, size: size) {
                        config = .complete(hardlink: hardlink, thumbnail: image, fileSize: Int(attachment.totalByteCount), uti: attachment.uti, filename: filename, wasOpened: attachment.wasOpened)
                    } else {
                        config = .complete(hardlink: hardlink, thumbnail: nil, fileSize: Int(attachment.totalByteCount), uti: attachment.uti, filename: filename, wasOpened: attachment.wasOpened)
                        if hardlink.hardlinkURL == nil {
                            // This happens when the attachment was just downloaded and we need to "refresh" the cached hardlink
                            // We do nothing since the hardlink will soon be refreshed
                        } else {
                            let messageID = message.typedObjectID.downcast
                            Task { [weak self] in
                                guard let self else { return }
                                do {
                                    try await cacheDelegate?.requestImageForHardlink(hardlink: hardlink, size: .full(minSize: sizeForUIDragItemPreview))
                                    try await cacheDelegate?.requestImageForHardlink(hardlink: hardlink, size: size)
                                    switch size {
                                    case .full:
                                        setNeedsUpdateConfiguration()
                                    case .cropBottom:
                                        setNeedsUpdateConfiguration()
                                        cellReconfigurator?.cellNeedsToBeReconfiguredAndResized(messageID: messageID)
                                    }
                                } catch {
                                    os_log("The request for an image for the hardlink to fyle %{public}@ failed: %{public}@", log: Self.log, type: .error, hardlink.fyleURL.lastPathComponent, error.localizedDescription)
                                }
                            }
                        }
                    }
                } else {
                    config = .downloading(receivedJoinObjectID: attachment.typedObjectID,
                                          progress: attachment.progressObject,
                                          fileSize: Int(attachment.totalByteCount),
                                          uti: attachment.uti,
                                          filename: filename)
                }
            }
        case .cancelledByServer:
            config = .cancelledByServer(fileSize: Int(attachment.totalByteCount), uti: attachment.uti, filename: filename)
        }
        return config
    }
    
    private func singlePreviewViewConfigurationForPreviewAttachment(_ previewAttachment: ReceivedFyleMessageJoinWithStatus) -> SinglePreviewView.Configuration? {

        var config: SinglePreviewView.Configuration?
        let message = previewAttachment.receivedMessage
        let previousConfiguration: ReceivedMessageCellCustomContentConfiguration?
        
        // We check that the current cell has a configuration configured for the current message already.
        if let configuration = self.contentConfiguration as? ReceivedMessageCellCustomContentConfiguration,
            message.objectID == configuration.messageObjectID?.objectID {
            previousConfiguration = configuration
        } else {
            previousConfiguration = nil
        }
        
        guard let fallbackURL = URL(string: previewAttachment.fileName), let fyleURL = previewAttachment.fyle?.url, FileManager.default.fileExists(atPath: fyleURL.path) else {
            return nil
        }
                
        switch previewAttachment.status {
        case .downloading:
            config = .downloadingOrDecoding
        case .downloadable:
            config = .downloadable
        case .cancelledByServer:
            config = nil
        case .complete:
            if message.readingRequiresUserAction {
                config = .completeButReadRequiresUserInteraction
            }
            switch CachedObvLinkMetadataManager.shared.getCachedMetadata(for: fyleURL) {
            case let .metadataCached(preview):
                config = .complete(preview: preview)
                //MARK: UGLY - We should NOT reload the cell if we have a previous Configuration and it was already in a complete state
                if let singlePreviewConfiguration = previousConfiguration?.singlePreviewConfiguration, singlePreviewConfiguration.isComplete {
                } else {
                    Task { [weak self] in
                        self?.cellReconfigurator?.cellNeedsToBeReconfiguredAndResized(messageID: message.typedObjectID.downcast)
                    }
                }
            case .metadaNotCachedYet:
                config = .downloadingOrDecoding
                Task {
                    try? await CachedObvLinkMetadataManager.shared.decodeAndCacheMetadata(for: fyleURL, fallbackURL: fallbackURL)
                    await MainActor.run { [weak self] in
                        self?.setNeedsUpdateConfiguration()
                    }
                }
            case .failureOccuredWhenDecodingOrCachingMetadata:
                config = nil
            }
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

    
    func tappedStuff(tapGestureRecognizer: UITapGestureRecognizer, acceptTapOutsideBounds: Bool) -> TappedStuffForCell? {
        guard let contentViewWithTappableStuff = contentView as? UIViewWithTappableStuff else { assertionFailure(); return nil }
        return contentViewWithTappableStuff.tappedStuff(tapGestureRecognizer: tapGestureRecognizer)
    }

}

// MARK: - Implementing CellWithMessage

extension ReceivedMessageCell {
     
    var persistedMessage: PersistedMessage? { message }
    
    public var persistedMessageObjectID: TypeSafeManagedObjectID<PersistedMessage>? { persistedMessage?.typedObjectID }
    
    var persistedDraftObjectID: TypeSafeManagedObjectID<PersistedDraft>? { draftObjectID }

    var viewForTargetedPreview: UIView { self.contentView }
    
    var textToCopy: String? {
        guard let contentView = contentView as? ReceivedMessageCellContentView else { assertionFailure(); return nil }
        let text: String
        
        // We always check that the text bubble has something displayed after markdown parsing
        if let textToCopy = message?.textBody, let textBubbleText = contentView.textBubble.textToCopy, !textBubbleText.isEmpty, contentView.textBubble.showInStack {
            text = textToCopy
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
    
    var activityItemProvidersForAllAttachments: [UIActivityItemProvider]? {
        message?.sharableFyleMessageJoinWithStatuses
            .compactMap({ cacheDelegate?.getCachedHardlinkForFyleMessageJoinWithStatus(with: ($0 as FyleMessageJoinWithStatus).typedObjectID) })
            .compactMap({ $0.activityItemProvider })
    }
    
    var itemProvidersForAllAttachments: [NSItemProvider]? {
        message?.sharableFyleMessageJoinWithStatuses
            .compactMap({ cacheDelegate?.getCachedHardlinkForFyleMessageJoinWithStatus(with: ($0 as FyleMessageJoinWithStatus).typedObjectID) })
            .compactMap({ $0.itemProvider })
    }

    var uiDragItemsForAllAttachments: [UIDragItem]? {
        message?.sharableFyleMessageJoinWithStatuses
            .compactMap({ cacheDelegate?.getCachedHardlinkForFyleMessageJoinWithStatus(with: ($0 as FyleMessageJoinWithStatus).typedObjectID) })
            .compactMap({ $0 })
            .compactMap({ ($0, $0.uiDragItem) })
            .compactMap({ (hardLinkToFyle, uiDragItem) in
                if let image = cacheDelegate?.getCachedImageForHardlink(hardlink: hardLinkToFyle, size: .full(minSize: sizeForUIDragItemPreview)) {
                    uiDragItem?.previewProvider = {
                        UIDragPreview(view: UIImageView(image: image))
                    }
                }
                return uiDragItem
            })
    }

    var hardlinkURLsForAllAttachments: [URL]? {
        message?.fyleMessageJoinWithStatuses
            .filter({ !$0.isPreviewType })
            .compactMap({ cacheDelegate?.getCachedHardlinkForFyleMessageJoinWithStatus(with: ($0 as FyleMessageJoinWithStatus).typedObjectID) })
            .compactMap({ $0.hardlinkURL })
    }

    var infoViewController: UIViewController? {
        guard let message = message else { return nil }
        guard message.infoActionCanBeMadeAvailable == true else { return nil }
        let rcv = ReceivedMessageInfosHostingViewController(messageReceived: message)
        return rcv
    }

}

// Handle Hovering on Mac Catalyst
extension ReceivedMessageCell {
    
    @objc
    func hovering(_ recognizer: UIHoverGestureRecognizer) {
        switch recognizer.state {
        case .began:
            showHoverMenu()
        case .ended:
            hideHoverMenu()
        default:
            break
        }
    }
    
    private func showHoverMenu() {
        
        if hoveringView != nil {
            hoveringView?.removeFromSuperview()
            hoveringView = nil
        }
        
        guard let contentView = self.contentView as? ReceivedMessageCellContentView else { assertionFailure(); return }

        // Check if hovering view is needed (no reactions or options available for the message)
        guard let hoveringView = getHoveringMenuView() else { return }
        hoveringView.alpha = 0.0
        
        hoveringView.translatesAutoresizingMaskIntoConstraints = false
        
        self.contentView.addSubview(hoveringView)
        
        let constraints: [NSLayoutConstraint] = {
            var constraints: [NSLayoutConstraint] = []
            
            // Place the hoveringView at the trailing/middle of the popableSubview in the middle of the stack (excluding the last view, which corresponds to the date)
            
            let indexOfMidPopableSubview = max(0, (contentView.mainStack.popableSubviews.count-1) / 2)
            if indexOfMidPopableSubview < contentView.mainStack.popableSubviews.count, let midPopableSubview = contentView.mainStack.popableSubviews[safe: indexOfMidPopableSubview] {
                constraints += [ 
                    hoveringView.centerYAnchor.constraint(equalTo: midPopableSubview.centerYAnchor),
                    hoveringView.leadingAnchor.constraint(equalTo: midPopableSubview.trailingAnchor, constant: 10.0)
                ]
            } else {
                constraints += [ 
                    hoveringView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
                    hoveringView.leadingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 10.0),
                ]
            }

            // Height constraint
            
            constraints += [
                hoveringView.heightAnchor.constraint(equalToConstant: 30.0)
            ]
            
            return constraints
        }()
        
        NSLayoutConstraint.activate(constraints)
        
        self.hoveringView = hoveringView
        
        UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.15, delay: 0) {
            hoveringView.alpha = 1.0
        }
        
    }
    
    private func hideHoverMenu() {
        guard hoveringView != nil else { return }
        
        UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.15, delay: 0) { [weak self] in
            self?.hoveringView?.alpha = 0.0
        } completion: { [weak self] _ in
            self?.hoveringView?.removeFromSuperview()
            self?.hoveringView = nil
        }
        
    }
    
    private func getHoveringMenuView() -> UIView? {
        
        let buttonWidth: CGFloat = 30.0
        
        let hoveringView = UIView(frame: .zero)
        hoveringView.backgroundColor = .clear
        
        hoveringView.layer.cornerRadius = 6.0
        hoveringView.clipsToBounds = true
        
        hoveringView.layer.shadowRadius = 3.0
        hoveringView.layer.shadowOpacity = 0.6
        hoveringView.layer.shadowOffset = .zero
        hoveringView.layer.shadowColor = UIColor.darkGray.cgColor
        hoveringView.layer.masksToBounds = false
        
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 12.0, weight: .light)

        var menuButton: UIButton? = nil
        
        // We fetch the menu from the discussion, if there is no menu, we are not adding the button
        if let menu = self.shortcutMenuDelegate?.getMenuForCellWithMessage(cell: self) {
            let chevronDown = UIImage(systemIcon: .chevronDown, withConfiguration: symbolConfig)!
            let button = UIButton.systemButton(with: chevronDown, target: nil, action: nil)
            button.tintColor = UIColor.label
            button.translatesAutoresizingMaskIntoConstraints = false
            
            button.showsMenuAsPrimaryAction = true
            button.menu = menu
            button.backgroundColor = UIColor.secondarySystemGroupedBackground
            
            button.layer.cornerRadius = buttonWidth / 2.0
            button.clipsToBounds = true
            button.layer.shadowRadius = 8.0
            button.layer.shadowOpacity = 0.05
            button.layer.shadowOffset = .zero
            button.layer.shadowColor = UIColor.darkGray.cgColor
            button.layer.masksToBounds = false
            
            hoveringView.addSubview(button)
            
            menuButton = button
        }

        var reactionButton: UIButton? = nil
        
        // We check that we can react to the message. If not, we are not adding the button.
        if let persistedMessageObjectID = self.persistedMessageObjectID,
           let persistedMessage = try? PersistedMessage.get(with: persistedMessageObjectID, within: ObvStack.shared.viewContext),
           (try? persistedMessage.ownedIdentityIsAllowedToSetReaction) == true {
            
            let faceSmiling = UIImage(systemIcon: .faceSmiling, withConfiguration: symbolConfig)!
            let button = UIButton.systemButton(with: faceSmiling, target: self, action: #selector(showReactions(sender:)))
            button.tintColor = UIColor.label
            button.translatesAutoresizingMaskIntoConstraints = false

            button.backgroundColor = UIColor.secondarySystemGroupedBackground
            
            button.layer.cornerRadius = buttonWidth / 2.0
            button.clipsToBounds = true
            button.layer.shadowRadius = 8.0
            button.layer.shadowOpacity = 0.05
            button.layer.shadowOffset = .zero
            button.layer.shadowColor = UIColor.darkGray.cgColor
            button.layer.masksToBounds = false
            
            hoveringView.addSubview(button)
            
            reactionButton = button
        }
        
        
        // both buttons not available
        guard reactionButton != nil || menuButton != nil else { return nil }
        
        let constraints: [NSLayoutConstraint] = {
            var constraints: [NSLayoutConstraint] = []
            
            // Both buttons available
            if let optionButton = menuButton, let reactionButton = reactionButton {
                constraints += [
                    reactionButton.trailingAnchor.constraint(equalTo: hoveringView.trailingAnchor),
                    reactionButton.topAnchor.constraint(equalTo: hoveringView.topAnchor),
                    reactionButton.bottomAnchor.constraint(equalTo: hoveringView.bottomAnchor),
                    reactionButton.widthAnchor.constraint(equalToConstant: buttonWidth),

                    optionButton.leadingAnchor.constraint(equalTo: hoveringView.leadingAnchor),
                    optionButton.topAnchor.constraint(equalTo: hoveringView.topAnchor),
                    optionButton.bottomAnchor.constraint(equalTo: hoveringView.bottomAnchor),
                    optionButton.widthAnchor.constraint(equalToConstant: buttonWidth),
                    
                    optionButton.trailingAnchor.constraint(equalTo: reactionButton.leadingAnchor, constant: -10.0)
                ]
            } else if let reactionButton = reactionButton { // Only reaction button
                constraints += [
                    reactionButton.trailingAnchor.constraint(equalTo: hoveringView.trailingAnchor),
                    reactionButton.leadingAnchor.constraint(equalTo: hoveringView.leadingAnchor),
                    reactionButton.topAnchor.constraint(equalTo: hoveringView.topAnchor),
                    reactionButton.bottomAnchor.constraint(equalTo: hoveringView.bottomAnchor),
                    reactionButton.widthAnchor.constraint(equalToConstant: buttonWidth),
                ]
            } else if let optionButton = menuButton { // Only option button
                constraints += [
                    optionButton.trailingAnchor.constraint(equalTo: hoveringView.trailingAnchor),
                    optionButton.leadingAnchor.constraint(equalTo: hoveringView.leadingAnchor),
                    optionButton.topAnchor.constraint(equalTo: hoveringView.topAnchor),
                    optionButton.bottomAnchor.constraint(equalTo: hoveringView.bottomAnchor),
                    optionButton.widthAnchor.constraint(equalToConstant: buttonWidth),
                ]
            }
            
            return constraints
        }()
        
        NSLayoutConstraint.activate(constraints)
        
        return hoveringView
    }
    
    @objc
    private func showReactions(sender: UIButton) {
        shortcutMenuDelegate?.showContextReactionView(for: self, on: sender)
    }
}


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
    var locationViewConfiguration: LocationView.Configuration?
    var singleImageViewConfiguration: SingleImageView.Configuration?
    var singleGifViewConfiguration: SingleImageView.Configuration?
    var multipleImagesViewConfiguration = [SingleImageView.Configuration]()
    var multipleAttachmentsViewConfiguration = [SingleAttachmentView.Configuration]()
    var audioPlayerConfiguration: AudioPlayerView.Configuration?
    var wipedViewConfiguration: WipedView.Configuration?
    var contactPictureAndNameViewConfiguration: ContactPictureAndNameView.Configuration?
    var missedMessageConfiguration: MissedMessageBubble.Configuration?

    var textBubbleConfiguration: TextBubble.Configuration?
    var singlePreviewConfiguration: SinglePreviewView.Configuration?
    var singlePDFViewConfiguration: SingleAttachmentView.Configuration?
    var reactionAndCounts = [ReactionAndCount]()
    
    var replyToBubbleViewConfiguration: ReplyToBubbleView.Configuration?

    var isReplyToActionAvailable = false
    var alwaysHideContactPictureAndNameView = true
    var forwarded = false

    func makeContentView() -> UIView & UIContentView {
        return ReceivedMessageCellContentView(configuration: self)
    }

    func updated(for state: UIConfigurationState) -> Self {
        return self
    }

}


fileprivate final class ReceivedMessageCellContentView: UIView, UIContentView, UIGestureRecognizerDelegate, UIViewWithTappableStuff {
    
    fileprivate let mainStack = OlvidVerticalStackView(gap: MessageCellConstants.mainStackGap,
                                                       side: .leading,
                                                       debugName: "Received message cell main stack",
                                                       showInStack: true)
    private let tapToReadBubble = TapToReadBubble(expirationIndicatorSide: .trailing)
    fileprivate let contactPictureAndNameView = ContactPictureAndNameView()
    private var contactPictureAndNameViewZeroHeightConstraint: NSLayoutConstraint!
    fileprivate let textBubble = TextBubble(expirationIndicatorSide: .trailing, bubbleColor: AppTheme.shared.colorScheme.newReceivedCellBackground, textColor: UIColor.label)
    fileprivate let emojiOnlyBodyView = EmojiOnlyBodyView(expirationIndicatorSide: .trailing)
    private let singlePreviewView = SinglePreviewView(expirationIndicatorSide: .trailing)
    fileprivate let singlePDFView = SinglePDFView(expirationIndicatorSide: .trailing)
    private let dateView = ReceivedMessageDateView()
    fileprivate let singleImageView = SingleImageView(expirationIndicatorSide: .trailing)
    fileprivate let multipleImagesView = MultipleImagesView(expirationIndicatorSide: .trailing)
    private let singleGifView = SingleGifView(expirationIndicatorSide: .trailing)
    fileprivate let attachmentsView = AttachmentsView(expirationIndicatorSide: .trailing)
    fileprivate let multipleReactionsView = MultipleReactionsView()
    private let ephemeralityInformationsView = EphemeralityInformationsView()
    private let replyToBubbleView = ReplyToBubbleView(expirationIndicatorSide: .trailing)
    fileprivate let locationView = LocationView(expirationIndicatorSide: .trailing)
    private let wipedView = WipedView(expirationIndicatorSide: .trailing)
    private let backgroundView = ReceivedMessageCellBackgroundView()
    fileprivate let audioPlayerView = AudioPlayerView(expirationIndicatorSide: .trailing)
    private let bottomHorizontalStack = OlvidHorizontalStackView(gap: 4.0, side: .bothSides, debugName: "Date and reactions horizontal stack view", showInStack: true)
    fileprivate let missedMessageCountBubble = MissedMessageBubble()
    private let forwardView = ForwardView()
    weak var replyToDelegate: CellReplyToDelegate?

    private var appliedConfiguration: ReceivedMessageCellCustomContentConfiguration!

    private var messageObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>?
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
            guard let replyToDelegate = self.replyToDelegate else { assertionFailure(); return }
            Task {
                try? await replyToDelegate.userWantsToReplyToMessage(messageObjectID: messageObjectID.downcast, draftObjectID: draftObjectID)
            }
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


    func tappedStuff(tapGestureRecognizer: UITapGestureRecognizer, acceptTapOutsideBounds: Bool) -> TappedStuffForCell? {
        var subviewsWithTappableStuff = self.mainStack.arrangedSubviews.filter({ $0.showInStack }).compactMap({ $0 as? UIViewWithTappableStuff })
        subviewsWithTappableStuff += [multipleReactionsView].filter({ !$0.isHidden })
        if !missedMessageCountBubble.isHidden && missedMessageCountBubble.showInStack {
            subviewsWithTappableStuff += [missedMessageCountBubble]
        }
        if !contactPictureAndNameView.isHidden {
            subviewsWithTappableStuff += [contactPictureAndNameView]
        }
        let view = subviewsWithTappableStuff.first(where: { $0.tappedStuff(tapGestureRecognizer: tapGestureRecognizer) != nil })
        return view?.tappedStuff(tapGestureRecognizer: tapGestureRecognizer)
    }

    
    private var constraintsForAlwaysHidingContactPictureAndNameView = [NSLayoutConstraint]()
    private var constraintsForSometimesShowingContactPictureAndNameView = [NSLayoutConstraint]()

    
    private func setupInternalViews() {
        
        addSubview(backgroundView)
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.reset()

        addSubview(contactPictureAndNameView)
        contactPictureAndNameView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(mainStack)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        mainStack.addArrangedSubview(missedMessageCountBubble)

        mainStack.addArrangedSubview(forwardView)
        
        mainStack.addArrangedSubview(tapToReadBubble)
        tapToReadBubble.bubbleColor = appTheme.colorScheme.newReceivedCellBackground

        mainStack.addArrangedSubview(replyToBubbleView)
        
        mainStack.addArrangedSubview(textBubble)

        mainStack.addArrangedSubview(wipedView)
        wipedView.bubbleColor = appTheme.colorScheme.newReceivedCellBackground
        
        mainStack.addArrangedSubview(emojiOnlyBodyView)
        
        mainStack.addArrangedSubview(singlePreviewView)

        mainStack.addArrangedSubview(singleGifView)

        mainStack.addArrangedSubview(singleImageView)

        mainStack.addArrangedSubview(singlePDFView)

        mainStack.addArrangedSubview(multipleImagesView)
        
        mainStack.addArrangedSubview(locationView)
        
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
        
    }

    
    func prepareForReuse() {
        singlePreviewView.prepareForReuse()
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
            if let textBubbleConfiguration = newConfig.textBubbleConfiguration, !textBubbleConfiguration.attributedText.characters.isEmpty {
                let attributedText = textBubbleConfiguration.attributedText
                if attributedText.containsOnlyEmoji, attributedText.characters.count < 4 {
                    emojiOnlyBodyView.text = String(attributedText.characters)
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
      
        // Single preview View
        
        if newConfig.readingRequiresUserAction {
            singlePreviewView.showInStack = false
        } else if let singlePreviewConfiguration = newConfig.singlePreviewConfiguration {
            singlePreviewView.showInStack = true
            singlePreviewView.currentConfiguration = singlePreviewConfiguration
        } else {
            singlePreviewView.showInStack = false
        }
        
        // Location view
        if let locationViewConfiguration = newConfig.locationViewConfiguration {
            locationView.showInStack = true
            locationView.apply(locationViewConfiguration)
        } else {
            locationView.showInStack = false
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
        
        // Single PDF attachment
        
        if let singlePDFViewConfiguration = newConfig.singlePDFViewConfiguration {
            singlePDFView.showInStack = true
            singlePDFView.setConfiguration(singlePDFViewConfiguration)
        } else {
            singlePDFView.showInStack = false
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

        // Forward
        forwardView.showInStack = newConfig.forwarded
        
    }
    
}



private class ReceivedMessageDateView: ViewForOlvidStack {
    
    var date = Date() {
        didSet {
            if oldValue != date {
                label.text = date.formattedForOlvidMessage()
            }
        }
    }
    
    var showEditedStatus: Bool {
        get { editedStatusImageView.showInStack }
        set { editedStatusImageView.showInStack = newValue }
    }
    
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
        editedStatusImageView.image = UIImage(systemIcon: .pencil(.circleFill), withConfiguration: config)
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


fileprivate final class ContactPictureAndNameView: UIView, UIViewWithTappableStuff {
    
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
    
    struct Configuration: Hashable {
        let foregroundColor: UIColor
        let contactName: String
        let contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>?
        let circledInitialsConfiguration: CircledInitialsConfiguration
    }
    
    private var currentConfiguration: Configuration?
    
    func setConfiguration(_ newConfiguration: Configuration) {
        guard newConfiguration != currentConfiguration else { return }
        currentConfiguration = newConfiguration
        contactNameView.name = newConfiguration.contactName
        contactNameView.color = newConfiguration.foregroundColor
        circledInitialsView.configure(with: newConfiguration.circledInitialsConfiguration)
    }

    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }    

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func tappedStuff(tapGestureRecognizer: UITapGestureRecognizer, acceptTapOutsideBounds: Bool) -> TappedStuffForCell? {
        guard !self.isHidden else { return nil }
        guard self.bounds.contains(tapGestureRecognizer.location(in: self)) else { return nil }
        guard let contactObjectId = currentConfiguration?.contactObjectID else { assertionFailure(); return nil }
        return .circledInitials(contactObjectID: contactObjectId)
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

    }
    
}


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


// MARK: - CellReplyToDelegate

protocol CellReplyToDelegate: AnyObject {
    func userWantsToReplyToMessage(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws
}
