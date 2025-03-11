/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import QuickLookThumbnailing


final class SinglePDFView: ViewForOlvidStack, ViewWithMaskedCorners, ViewWithExpirationIndicator, ViewShowingHardLinks, UIViewWithTappableStuff {

    private var currentConfiguration: SingleAttachmentView.Configuration?

    func setConfiguration(_ newConfiguration: SingleAttachmentView.Configuration) {
        guard self.currentConfiguration != newConfiguration else { return }
        self.currentConfiguration = newConfiguration
        refresh(with: newConfiguration)
    }

    
    func getAllShownHardLink() -> [(hardlink: HardLinkToFyle, viewShowingHardLink: UIView)] {
        if let hardlink = imageView.hardlink {
            return [(hardlink, imageView)]
        } else {
            return []
        }
    }

    
    private func refresh(with configuration: SingleAttachmentView.Configuration) {
        heightConstraintOnImageView?.constant = Self.singlePDFPreviewMaxHeight // Might be reset if there is a thumbnail to set
        switch configuration {
        case .uploadableOrUploading(hardlink: let hardlink, thumbnail: let thumbnail, fileSize: let fileSize, uti: let uti, filename: let filename, progress: let progress):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.uploadableOrUploading(progress: progress))
            tapToReadView.messageObjectID = nil
            if let hardlink = hardlink {
                setHardlinkOnImageView(hardlink: hardlink, thumbnail: thumbnail)
            } else {
                imageView.reset()
            }
            if let url = hardlink?.hardlinkURL {
                setTitleOnSubtitleView(titleLabel, url: url)
                setSubtitleOnSubtitleView(subtitleLabel, url: url)
            } else {
                setTitleOnSubtitleView(titleLabel, filename: filename)
                setSubtitleOnSubtitleView(subtitleLabel, fileSize: fileSize, uti: uti)
            }
        case .downloadable(receivedJoinObjectID: let receivedJoinObjectID, progress: let progress, fileSize: let fileSize, uti: let uti, filename: let filename):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.downloadable(receivedJoinObjectID: receivedJoinObjectID, progress: progress))
            tapToReadView.messageObjectID = nil
            imageView.reset()
            setTitleOnSubtitleView(titleLabel, filename: filename)
            setSubtitleOnSubtitleView(subtitleLabel, fileSize: fileSize, uti: uti)
        case .downloadableSent(sentJoinObjectID: let sentJoinObjectID, progress: let progress, fileSize: let fileSize, uti: let uti, filename: let filename):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.downloadableSent(sentJoinObjectID: sentJoinObjectID, progress: progress))
            tapToReadView.messageObjectID = nil
            imageView.reset()
            setTitleOnSubtitleView(titleLabel, filename: filename)
            setSubtitleOnSubtitleView(subtitleLabel, fileSize: fileSize, uti: uti)
        case .downloading(receivedJoinObjectID: let receivedJoinObjectID, progress: let progress, fileSize: let fileSize, uti: let uti, filename: let filename):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.downloading(receivedJoinObjectID: receivedJoinObjectID, progress: progress))
            tapToReadView.messageObjectID = nil
            imageView.reset()
            setTitleOnSubtitleView(titleLabel, filename: filename)
            setSubtitleOnSubtitleView(subtitleLabel, fileSize: fileSize, uti: uti)
        case .downloadingSent(sentJoinObjectID: let sentJoinObjectID, progress: let progress, fileSize: let fileSize, uti: let uti, filename: let filename):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.downloadingSent(sentJoinObjectID: sentJoinObjectID, progress: progress))
            tapToReadView.messageObjectID = nil
            imageView.reset()
            setTitleOnSubtitleView(titleLabel, filename: filename)
            setSubtitleOnSubtitleView(subtitleLabel, fileSize: fileSize, uti: uti)
        case .completeButReadRequiresUserInteraction(messageObjectID: let messageObjectID, fileSize: let fileSize, uti: let uti):
            tapToReadView.isHidden = false
            fyleProgressView.setConfiguration(.complete)
            tapToReadView.messageObjectID = messageObjectID
            imageView.reset()
            setTitleOnSubtitleView(titleLabel, filename: nil)
            setSubtitleOnSubtitleView(subtitleLabel, fileSize: fileSize, uti: uti)
        case .complete(hardlink: let hardlink, thumbnail: let thumbnail, fileSize: let fileSize, uti: let uti, filename: let filename, wasOpened: _):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.complete)
            tapToReadView.messageObjectID = nil
            if let hardlink = hardlink {
                setHardlinkOnImageView(hardlink: hardlink, thumbnail: thumbnail)
            } else {
                imageView.reset()
            }
            if let url = hardlink?.hardlinkURL {
                setTitleOnSubtitleView(titleLabel, url: url)
                setSubtitleOnSubtitleView(subtitleLabel, url: url)
            } else {
                setTitleOnSubtitleView(titleLabel, filename: filename)
                setSubtitleOnSubtitleView(subtitleLabel, fileSize: fileSize, uti: uti)
            }
        case .cancelledByServer(fileSize: let fileSize, uti: let uti, filename: let filename):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.cancelled)
            tapToReadView.messageObjectID = nil
            imageView.reset()
            setTitleOnSubtitleView(titleLabel, filename: filename)
            setSubtitleOnSubtitleView(subtitleLabel, fileSize: fileSize, uti: uti)
        }

    }
    
    
    private func setHardlinkOnImageView(hardlink: HardLinkToFyle, thumbnail: UIImage?) {
        imageView.setHardlink(newHardlink: hardlink, withImage: thumbnail)
        if let thumbnail {
            assert(thumbnail.size.height <= Self.singlePDFPreviewMaxHeight)
            heightConstraintOnImageView?.constant = thumbnail.size.height
        } else {
            heightConstraintOnImageView?.constant = Self.singlePDFPreviewMaxHeight
        }
    }
    
    
    private func setTitleOnSubtitleView(_ titleView: UILabel, url: URL) {
        let filename = url.lastPathComponent
        setTitleOnSubtitleView(titleView, filename: filename)
    }
    
    
    private func setTitleOnSubtitleView(_ titleView: UILabel, filename: String?) {
        guard titleView.text != filename else { return }
        titleView.text = filename
    }

    
    private func setSubtitleOnSubtitleView(_ subtitleView: UILabel, url: URL) {
        var fileSize = 0
        if let resources = try? url.resourceValues(forKeys: [.fileSizeKey]) {
            fileSize = resources.fileSize!
        }
        let uti = UTType(filenameExtension: url.pathExtension)?.identifier ?? ""
        setSubtitleOnSubtitleView(subtitleView, fileSize: fileSize, uti: uti)
    }
    
    
    private func setSubtitleOnSubtitleView(_ subtitleView: UILabel, fileSize: Int, uti: String) {
        var subtitleElements = [String]()
        subtitleElements.append(Int64(fileSize).formatted(.byteCount(style: .file, allowedUnits: .all, spellsOutZero: true, includesActualByteCount: false)))
        if let uti = UTType(uti), let type = uti.localizedDescription {
            subtitleElements.append(type)
        }
        let subtitleText = subtitleElements.joined(separator: " - ")
        if subtitleView.text != subtitleText {
            subtitleView.text = subtitleText
        }
    }

    
    var maskedCorner: UIRectCorner {
        get { bubble.maskedCorner }
        set {
            bubble.maskedCorner = newValue
            resetMaskedCornerForBubbleStrokeForImageView()
        }
    }
    
    
    /// Whener the masked corners of this view are set, we reset the top masked corners of the "inner" bubble view that the contains the thumbnail
    /// to make sure the "stroke" effect around the image has the correct look.
    private func resetMaskedCornerForBubbleStrokeForImageView() {
        var maskedCornerForBubbleStrokeForImageView: UIRectCorner = []
        if maskedCorner.contains(.topLeft) { maskedCornerForBubbleStrokeForImageView.insert(.topLeft) }
        if maskedCorner.contains(.topRight) { maskedCornerForBubbleStrokeForImageView.insert(.topRight) }
        bubbleStrokeForImageView.maskedCorner = maskedCornerForBubbleStrokeForImageView
    }


    private static let imageBorderWidth: CGFloat = 1.0
    private let bubble = BubbleView()
    let expirationIndicator = ExpirationIndicatorView()
    let expirationIndicatorSide: ExpirationIndicatorView.Side
    private let fyleProgressView = FyleProgressView()
    private let bubbleStrokeForImageView = BubbleView(smallCornerRadius: MessageCellConstants.BubbleView.smallCornerRadius-imageBorderWidth, 
                                                      largeCornerRadius: MessageCellConstants.BubbleView.largeCornerRadius-imageBorderWidth,
                                                      neverRoundedCorners: [.bottomLeft, .bottomRight])
    private let imageView = UIImageViewForHardLink()
    private let tapToReadView = TapToReadView(showText: false)
    private let labelsStackBackgroundView = UIView()
    private let labelsStack = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    
    
    private var heightConstraintOnImageView: NSLayoutConstraint?

    
    static let singlePDFViewWidth = CGFloat(280)
    static let singlePDFPreviewMaxHeight = CGFloat(192)

    
    init(expirationIndicatorSide side: ExpirationIndicatorView.Side) {
        self.expirationIndicatorSide = side
        super.init(frame: .zero)
        setupInternalViews()
    }
    

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    func tappedStuff(tapGestureRecognizer: UITapGestureRecognizer, acceptTapOutsideBounds: Bool) -> TappedStuffForCell? {
        if !fyleProgressView.isHidden && fyleProgressView.tappedStuff(tapGestureRecognizer: tapGestureRecognizer, acceptTapOutsideBounds: true) != nil {
            return fyleProgressView.tappedStuff(tapGestureRecognizer: tapGestureRecognizer, acceptTapOutsideBounds: true)
        } else if !tapToReadView.isHidden && tapToReadView.tappedStuff(tapGestureRecognizer: tapGestureRecognizer, acceptTapOutsideBounds: true) != nil {
            return tapToReadView.tappedStuff(tapGestureRecognizer: tapGestureRecognizer, acceptTapOutsideBounds: true)
        } else {
            return imageView.tappedStuff(tapGestureRecognizer: tapGestureRecognizer)
        }
  }

    
    private func setupInternalViews() {
        
        addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.backgroundColor = .secondarySystemFill

        addSubview(expirationIndicator)
        expirationIndicator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(fyleProgressView)
        fyleProgressView.translatesAutoresizingMaskIntoConstraints = false

        bubble.addSubview(bubbleStrokeForImageView)
        bubbleStrokeForImageView.translatesAutoresizingMaskIntoConstraints = false
        
        bubbleStrokeForImageView.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .tertiarySystemFill

        bubble.addSubview(labelsStackBackgroundView)
        labelsStackBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        
        labelsStackBackgroundView.addSubview(labelsStack)
        labelsStack.translatesAutoresizingMaskIntoConstraints = false
        labelsStack.axis = .vertical
        labelsStack.spacing = 4
        
        labelsStack.addArrangedSubview(titleLabel)
        titleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true

        labelsStack.addArrangedSubview(subtitleLabel)
        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1
        subtitleLabel.adjustsFontForContentSizeCategory = true

        addSubview(tapToReadView)
        tapToReadView.translatesAutoresizingMaskIntoConstraints = false
        tapToReadView.tapToReadLabelTextColor = .label

        NSLayoutConstraint.activate([
            
            bubble.topAnchor.constraint(equalTo: self.topAnchor),
            bubble.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            bubble.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            bubble.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            
            bubbleStrokeForImageView.topAnchor.constraint(equalTo: bubble.topAnchor, constant: Self.imageBorderWidth),
            bubbleStrokeForImageView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -Self.imageBorderWidth),
            bubbleStrokeForImageView.bottomAnchor.constraint(equalTo: labelsStackBackgroundView.topAnchor),
            bubbleStrokeForImageView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: Self.imageBorderWidth),
            
            imageView.topAnchor.constraint(equalTo: bubbleStrokeForImageView.topAnchor),
            imageView.trailingAnchor.constraint(equalTo: bubbleStrokeForImageView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bubbleStrokeForImageView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: bubbleStrokeForImageView.leadingAnchor),
            
            fyleProgressView.centerXAnchor.constraint(equalTo: self.imageView.centerXAnchor),
            fyleProgressView.centerYAnchor.constraint(equalTo: self.imageView.centerYAnchor),
            
            tapToReadView.topAnchor.constraint(equalTo: self.topAnchor),
            tapToReadView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            tapToReadView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            tapToReadView.leadingAnchor.constraint(equalTo: self.leadingAnchor),

            labelsStackBackgroundView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
            labelsStackBackgroundView.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
            labelsStackBackgroundView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
            
            labelsStackBackgroundView.topAnchor.constraint(equalTo: labelsStack.topAnchor, constant: -8),
            labelsStackBackgroundView.trailingAnchor.constraint(equalTo: labelsStack.trailingAnchor, constant: 16),
            labelsStackBackgroundView.bottomAnchor.constraint(equalTo: labelsStack.bottomAnchor, constant: 8),
            labelsStackBackgroundView.leadingAnchor.constraint(equalTo: labelsStack.leadingAnchor, constant: -16),

        ])

        heightConstraintOnImageView = imageView.heightAnchor.constraint(equalToConstant: Self.singlePDFPreviewMaxHeight) // Reset whenever a thumbnail is set
        heightConstraintOnImageView?.isActive = true
        
        let sizeConstraints = [
            bubble.widthAnchor.constraint(equalToConstant: Self.singlePDFViewWidth),
        ]
        sizeConstraints.forEach { $0.priority -= 1 }
        NSLayoutConstraint.activate(sizeConstraints)

        setupConstraintsForExpirationIndicator(gap: MessageCellConstants.gapBetweenExpirationViewAndBubble)

    }
    
}
