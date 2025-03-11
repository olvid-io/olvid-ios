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
import CoreData
import ObvUICoreData


final class AttachmentsView: ViewForOlvidStack, ViewWithMaskedCorners, ViewWithExpirationIndicator, UIViewWithTappableStuff, ViewShowingHardLinks {
    

    private var currentConfigurations = [SingleAttachmentView.Configuration]()

    
    func setConfiguration(_ newConfigurations: [SingleAttachmentView.Configuration]) {
        guard self.currentConfigurations != newConfigurations else { return }
        self.currentConfigurations = newConfigurations
        refresh()
    }
    
    
    func getAllShownHardLink() -> [(hardlink: HardLinkToFyle, viewShowingHardLink: UIView)] {
        guard showInStack else { return [] }
        var hardlinks = [(hardlink: HardLinkToFyle, viewShowingHardLink: UIView)]()
        for view in mainStack.arrangedSubviews {
            if let attachmentView = view as? SingleAttachmentView {
                hardlinks.append(contentsOf: attachmentView.getAllShownHardLink())
            } else {
                assertionFailure()
            }
        }
        return hardlinks
    }
    
    
    private func refresh() {
        
        // Reset all existing single attachment views and make sure there are enough views to handle all the urls
        prepareSingleAttachmentViews(count: currentConfigurations.count)

        for (index, configuration) in currentConfigurations.enumerated() {
            refresh(atIndex: index, withConfiguration: configuration)
        }

    }
    
    
    private func refresh(atIndex index: Int, withConfiguration configuration: SingleAttachmentView.Configuration) {
        
        guard index < mainStack.arrangedSubviews.count else { assertionFailure(); return }
        guard let singleAttachmentView = mainStack.arrangedSubviews[index] as? SingleAttachmentView else { assertionFailure(); return }
                
        singleAttachmentView.refresh(withConfiguration: configuration)
        
    }
        
    var maskedCorner: UIRectCorner {
        get { bubble.maskedCorner }
        set { bubble.maskedCorner = newValue }
    }

    
    private var currentURLs = [URL]()
    private let mainStack = OlvidVerticalStackView(gap: 1, side: .bothSides, debugName: "Attachments view main stack view", showInStack: true)
    private let bubble = BubbleView()
    let expirationIndicator = ExpirationIndicatorView()
    let expirationIndicatorSide: ExpirationIndicatorView.Side

    private var singleAttachmentViews: [SingleAttachmentView] {
        mainStack.arrangedSubviews.compactMap({ $0 as? SingleAttachmentView })
    }

    private func prepareSingleAttachmentViews(count: Int) {
        // Make sure there are enough horizontal pair of images views
        let numberOfSingleAttachmentViewsToAdd = max(0, count - singleAttachmentViews.count)
        for _ in 0..<numberOfSingleAttachmentViewsToAdd {
            let view = SingleAttachmentView()
            view.translatesAutoresizingMaskIntoConstraints = false
            mainStack.addArrangedSubview(view)
        }
        // Show only the required attachment views
        for index in 0..<singleAttachmentViews.count {
            singleAttachmentViews[index].showInStack = (index < count)
            singleAttachmentViews[index].reset()
        }
    }
    
    
    init(expirationIndicatorSide side: ExpirationIndicatorView.Side) {
        self.expirationIndicatorSide = side
        super.init(frame: .zero)
        setupInternalViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    func tappedStuff(tapGestureRecognizer: UITapGestureRecognizer, acceptTapOutsideBounds: Bool) -> TappedStuffForCell? {
        let subviewsWithTappableStuff = self.mainStack.arrangedSubviews.filter({ $0.showInStack }).compactMap({ $0 as? UIViewWithTappableStuff })
        let view = subviewsWithTappableStuff.first(where: { $0.tappedStuff(tapGestureRecognizer: tapGestureRecognizer) != nil })
        return view?.tappedStuff(tapGestureRecognizer: tapGestureRecognizer)
    }
    
    
    private func setupInternalViews() {
        
        addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(expirationIndicator)
        expirationIndicator.translatesAutoresizingMaskIntoConstraints = false

        bubble.addSubview(mainStack)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: self.topAnchor),
            bubble.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            bubble.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            bubble.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            mainStack.topAnchor.constraint(equalTo: bubble.topAnchor),
            mainStack.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
            mainStack.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
        ])
        
        do {
            let widthContraints = [
                mainStack.widthAnchor.constraint(equalToConstant: 1),
            ]
            widthContraints.forEach({ $0.priority = .defaultLow })
            NSLayoutConstraint.activate(widthContraints)
        }
        
        setupConstraintsForExpirationIndicator(gap: MessageCellConstants.gapBetweenExpirationViewAndBubble)

    }
}



// MARK: - SingleAttachmentView

final class SingleAttachmentView: ViewForOlvidStack, UIViewWithTappableStuff, ViewShowingHardLinks {
    
    enum Configuration: Equatable, Hashable {
        // For sent attachments
        case uploadableOrUploading(hardlink: HardLinkToFyle?, thumbnail: UIImage?, fileSize: Int, uti: String, filename: String?, progress: Progress)
        // For received attachments
        case downloadable(receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>, progress: Progress, fileSize: Int, uti: String, filename: String?)
        case downloading(receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>, progress: Progress, fileSize: Int, uti: String, filename: String?)
        case completeButReadRequiresUserInteraction(messageObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>, fileSize: Int, uti: String)
        case cancelledByServer(fileSize: Int, uti: String, filename: String?)
        // For received attachments sent from other owned device
        case downloadableSent(sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>, progress: Progress, fileSize: Int, uti: String, filename: String?)
        case downloadingSent(sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>, progress: Progress, fileSize: Int, uti: String, filename: String?)
        // For both
        case complete(hardlink: HardLinkToFyle?, thumbnail: UIImage?, fileSize: Int, uti: String, filename: String?, wasOpened: Bool?)
        
        var hardlink: HardLinkToFyle? {
            switch self {
            case .complete(hardlink: let hardlink, thumbnail: _, fileSize: _, uti: _, filename: _, wasOpened: _),
                 .uploadableOrUploading(hardlink: let hardlink, thumbnail: _, fileSize: _, uti: _, filename: _, progress: _):
                return hardlink
            case .downloadable, .downloading, .completeButReadRequiresUserInteraction, .cancelledByServer, .downloadableSent, .downloadingSent:
                return nil
            }
        }
    }

    
    private let imageView = UIImageViewForHardLink()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let labelsBackgroundView = UIView()
    private let tapToReadView = TapToReadView(showText: false)
    private let fyleProgressView = FyleProgressView()

    /// The recommended size to use when requesting a thumbnail image. The image view size will probably be less than this requested size.
    static let sizeForRequestingThumbnail = CGSize(width: 100, height: 100)
    
    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }

    func reset() {
        if self.titleLabel.text != nil {
            self.titleLabel.text = nil
        }
        if self.subtitleLabel.text != nil {
            self.subtitleLabel.text = nil
        }
        self.imageView.reset()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    

    func tappedStuff(tapGestureRecognizer: UITapGestureRecognizer, acceptTapOutsideBounds: Bool) -> TappedStuffForCell? {
        guard acceptTapOutsideBounds || self.bounds.contains(tapGestureRecognizer.location(in: self)) else { return nil }
        if !tapToReadView.isHidden {
            return tapToReadView.tappedStuff(tapGestureRecognizer: tapGestureRecognizer)
        } else {
            guard self.bounds.contains(tapGestureRecognizer.location(in: self)) else { return nil }
            let views = [fyleProgressView, imageView] as [UIViewWithTappableStuff]
            let view = views.first(where: { $0.tappedStuff(tapGestureRecognizer: tapGestureRecognizer, acceptTapOutsideBounds: true) != nil })
            return view?.tappedStuff(tapGestureRecognizer: tapGestureRecognizer, acceptTapOutsideBounds: true)
        }
    }


    private func setupInternalViews() {
        
        clipsToBounds = true
        backgroundColor = .secondarySystemFill
        
        addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.clipsToBounds = true
        
        addSubview(labelsBackgroundView)
        labelsBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        labelsBackgroundView.clipsToBounds = true

        labelsBackgroundView.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.adjustsFontForContentSizeCategory = true

        labelsBackgroundView.addSubview(subtitleLabel)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.adjustsFontForContentSizeCategory = true

        imageView.addSubview(fyleProgressView)
        fyleProgressView.translatesAutoresizingMaskIntoConstraints = false
        
        imageView.addSubview(tapToReadView)
        tapToReadView.translatesAutoresizingMaskIntoConstraints = false
        tapToReadView.tapToReadLabelTextColor = .label

        NSLayoutConstraint.activate([
            
            imageView.topAnchor.constraint(equalTo: self.topAnchor),
            imageView.trailingAnchor.constraint(equalTo: labelsBackgroundView.leadingAnchor, constant: -16),
            imageView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            
            imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor),
            
            labelsBackgroundView.topAnchor.constraint(equalTo: self.topAnchor, constant: 16),
            labelsBackgroundView.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -16),
            labelsBackgroundView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -16),
            
            titleLabel.topAnchor.constraint(equalTo: labelsBackgroundView.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: labelsBackgroundView.leadingAnchor),
            
            titleLabel.bottomAnchor.constraint(equalTo: subtitleLabel.topAnchor, constant: -4),

            subtitleLabel.bottomAnchor.constraint(equalTo: labelsBackgroundView.bottomAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: labelsBackgroundView.leadingAnchor),

            fyleProgressView.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            fyleProgressView.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),

            tapToReadView.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            tapToReadView.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),

        ])
        
        let sizeConstraints = [
            tapToReadView.widthAnchor.constraint(equalToConstant: MessageCellConstants.attachmentIconSize),
            tapToReadView.heightAnchor.constraint(equalToConstant: MessageCellConstants.attachmentIconSize),
            self.widthAnchor.constraint(equalToConstant: MessageCellConstants.singleAttachmentViewWidth),
        ]
        NSLayoutConstraint.activate(sizeConstraints)
        
        // The following constraints allow to make sure that the labels don't extend behond their container (the labelsBackgroundView).
        // We need to set their compression resistance to low, as we don't want their intrinsic content size to define their width if it is too large.
        
        let labelWidthConstraints = [
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: labelsBackgroundView.widthAnchor),
            subtitleLabel.widthAnchor.constraint(lessThanOrEqualTo: labelsBackgroundView.widthAnchor),
        ]
        labelWidthConstraints.forEach({ $0.isActive = true })
        
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        // We want the labels to define the height of the view. We set their hugging priority to high, so that the final height of the view is as small as possible
        // while respecting all the other constraints. We also must set the compression resistance of the image view to low, in order to make sure
        // that the intrinsinc content size of the view (which will be the size of the requested thumbnail) won't impact the height of the whole view.
        
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
        subtitleLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
        
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        
    }
    
    
    fileprivate func refresh(withConfiguration configuration: Configuration) {
        switch configuration {
        case .uploadableOrUploading(hardlink: let hardlink, thumbnail: let thumbnail, fileSize: let fileSize, uti: let uti, filename: let filename, progress: let progress):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.uploadableOrUploading(progress: progress))
            tapToReadView.messageObjectID = nil
            if let hardlink = hardlink {
                imageView.setHardlink(newHardlink: hardlink, withImage: thumbnail)
            } else {
                imageView.reset()
            }
            if let url = hardlink?.hardlinkURL {
                setTitleOnSubtitleView(url: url)
                setSubtitleOnSubtitleView(url: url)
            } else {
                setTitleOnSubtitleView(filename: filename)
                setSubtitleOnSubtitleView(fileSize: fileSize, uti: uti)
            }
        case .downloadable(receivedJoinObjectID: let receivedJoinObjectID, progress: let progress, fileSize: let fileSize, uti: let uti, filename: let filename):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.downloadable(receivedJoinObjectID: receivedJoinObjectID, progress: progress))
            tapToReadView.messageObjectID = nil
            imageView.reset()
            setTitleOnSubtitleView(filename: filename)
            setSubtitleOnSubtitleView(fileSize: fileSize, uti: uti)
        case .downloadableSent(sentJoinObjectID: let sentJoinObjectID, progress: let progress, fileSize: let fileSize, uti: let uti, filename: let filename):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.downloadableSent(sentJoinObjectID: sentJoinObjectID, progress: progress))
            tapToReadView.messageObjectID = nil
            imageView.reset()
            setTitleOnSubtitleView(filename: filename)
            setSubtitleOnSubtitleView(fileSize: fileSize, uti: uti)
        case .downloading(receivedJoinObjectID: let receivedJoinObjectID, progress: let progress, fileSize: let fileSize, uti: let uti, filename: let filename):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.downloading(receivedJoinObjectID: receivedJoinObjectID, progress: progress))
            tapToReadView.messageObjectID = nil
            imageView.reset()
            setTitleOnSubtitleView(filename: filename)
            setSubtitleOnSubtitleView(fileSize: fileSize, uti: uti)
        case .downloadingSent(sentJoinObjectID: let sentJoinObjectID, progress: let progress, fileSize: let fileSize, uti: let uti, filename: let filename):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.downloadingSent(sentJoinObjectID: sentJoinObjectID, progress: progress))
            tapToReadView.messageObjectID = nil
            imageView.reset()
            setTitleOnSubtitleView(filename: filename)
            setSubtitleOnSubtitleView(fileSize: fileSize, uti: uti)
        case .completeButReadRequiresUserInteraction(messageObjectID: let messageObjectID, fileSize: let fileSize, uti: let uti):
            tapToReadView.isHidden = false
            fyleProgressView.setConfiguration(.complete)
            tapToReadView.messageObjectID = messageObjectID
            imageView.reset()
            setTitleOnSubtitleView(filename: nil)
            setSubtitleOnSubtitleView(fileSize: fileSize, uti: uti)
        case .complete(hardlink: let hardlink, thumbnail: let thumbnail, fileSize: let fileSize, uti: let uti, filename: let filename, wasOpened: _):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.complete)
            tapToReadView.messageObjectID = nil
            if let hardlink = hardlink {
                imageView.setHardlink(newHardlink: hardlink, withImage: thumbnail)
            } else {
                imageView.reset()
            }
            if let url = hardlink?.hardlinkURL {
                setTitleOnSubtitleView(url: url)
                setSubtitleOnSubtitleView(url: url)
            } else {
                setTitleOnSubtitleView(filename: filename)
                setSubtitleOnSubtitleView(fileSize: fileSize, uti: uti)
            }
        case .cancelledByServer(fileSize: let fileSize, uti: let uti, filename: let filename):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.cancelled)
            tapToReadView.messageObjectID = nil
            imageView.reset()
            setTitleOnSubtitleView(filename: filename)
            setSubtitleOnSubtitleView(fileSize: fileSize, uti: uti)
        }

    }

    
    private func setSubtitleOnSubtitleView(url: URL) {
        var fileSize = 0
        if let resources = try? url.resourceValues(forKeys: [.fileSizeKey]) {
            fileSize = resources.fileSize!
        }
        let uti = UTType(filenameExtension: url.pathExtension)?.identifier ?? ""
        setSubtitleOnSubtitleView(fileSize: fileSize, uti: uti)
    }

    
    private func setSubtitleOnSubtitleView(fileSize: Int, uti: String) {
        var subtitleElements = [String]()
        subtitleElements.append(Int64(fileSize).formatted(.byteCount(style: .file, allowedUnits: .all, spellsOutZero: true, includesActualByteCount: false)))
        if let uti = UTType(uti), let type = uti.localizedDescription {
            subtitleElements.append(type)
        }
        let subtitleText = subtitleElements.joined(separator: " - ")
        if subtitleLabel.text != subtitleText {
            subtitleLabel.text = subtitleText
        }
    }

    
    private func setTitleOnSubtitleView(url: URL) {
        let filename = url.lastPathComponent
        setTitleOnSubtitleView(filename: filename)
    }
    
    
    private func setTitleOnSubtitleView(filename: String?) {
        guard titleLabel.text != filename else { return }
        titleLabel.text = filename
    }

    
    func getAllShownHardLink() -> [(hardlink: HardLinkToFyle, viewShowingHardLink: UIView)] {
        guard showInStack else { return [] }
        if let hardlink = imageView.hardlink {
            return [(hardlink, imageView)]
        } else {
            return []
        }
    }

}
