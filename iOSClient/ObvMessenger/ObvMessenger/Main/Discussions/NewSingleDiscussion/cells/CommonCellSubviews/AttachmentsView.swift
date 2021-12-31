/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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


@available(iOS 14.0, *)
final class AttachmentsView: ViewForOlvidStack, ViewWithMaskedCorners, ViewWithExpirationIndicator, ViewShowingHardLinks, UIGestureRecognizerDelegate {
    
    enum Configuration: Equatable, Hashable {
        // For sent attachments
        case uploadableOrUploading(hardlink: HardLinkToFyle?, thumbnail: UIImage?, fileSize: Int, uti: String, filename: String?, progress: Progress?)
        // For received attachments
        case downloadableOrDownloading(progress: Progress?, fileSize: Int, uti: String, filename: String?)
        case completeButReadRequiresUserInteraction(messageObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>, fileSize: Int, uti: String)
        case cancelledByServer(fileSize: Int, uti: String, filename: String?)
        // For both
        case complete(hardlink: HardLinkToFyle?, thumbnail: UIImage?, fileSize: Int, uti: String, filename: String?)
        
        var hardlink: HardLinkToFyle? {
            switch self {
            case .complete(hardlink: let hardlink, thumbnail: _, fileSize: _, uti: _, filename: _),
                 .uploadableOrUploading(hardlink: let hardlink, thumbnail: _, fileSize: _, uti: _, filename: _, progress: _):
                return hardlink
            case .downloadableOrDownloading, .completeButReadRequiresUserInteraction, .cancelledByServer:
                return nil
            }
        }
    }

    private var currentConfigurations = [Configuration]()

    
    func setConfiguration(_ newConfigurations: [AttachmentsView.Configuration]) {
        guard self.currentConfigurations != newConfigurations else { return }
        self.currentConfigurations = newConfigurations
        refresh()
    }
    
    
    private var currentRefreshId = UUID()
    
    
    weak var delegate: ViewShowingHardLinksDelegate?
    
    
    func getAllShownHardLink() -> [(hardlink: HardLinkToFyle, viewShowingHardLink: UIView)] {
        guard showInStack else { return [] }
        var hardlinks = [(hardlink: HardLinkToFyle, viewShowingHardLink: UIView)]()
        for view in mainStack.arrangedSubviews {
            if let attachmentView = view as? SingleAttachmentView {
                if let hardlink = attachmentView.imageView.hardlink {
                    hardlinks.append((hardlink, attachmentView.imageView))
                }
            } else {
                assertionFailure()
            }
        }
        return hardlinks
    }
    
    
    private func refresh() {
        
        currentRefreshId = UUID()
        
        // Reset all existing single attachment views and make sure there are enough views to handle all the urls
        prepareSingleAttachmentViews(count: currentConfigurations.count)

        for (index, configuration) in currentConfigurations.enumerated() {
            refresh(atIndex: index, withConfiguration: configuration)
        }

    }
    
    
    private func refresh(atIndex index: Int, withConfiguration configuration: Configuration) {
        
        guard index < mainStack.arrangedSubviews.count else { assertionFailure(); return }
        guard let singleAttachmentView = mainStack.arrangedSubviews[index] as? SingleAttachmentView else { assertionFailure(); return }
                
        let tapToReadView = singleAttachmentView.tapToReadView
        let fyleProgressView = singleAttachmentView.fyleProgressView
        let imageView = singleAttachmentView.imageView
        let titleView = singleAttachmentView.title
        let subtitleView = singleAttachmentView.subtitle
        
        refresh(tapToReadView: tapToReadView,
                fyleProgressView: fyleProgressView,
                imageView: imageView,
                titleView: titleView,
                subtitleView: subtitleView,
                withConfiguration: configuration)
        
    }

    
    private func refresh(tapToReadView: TapToReadView, fyleProgressView: FyleProgressView, imageView: UIImageViewForHardLink, titleView: UILabel, subtitleView: UILabel, withConfiguration configuration: Configuration) {
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
                setTitleOnSubtitleView(titleView, url: url)
                setSubtitleOnSubtitleView(subtitleView, url: url)
            } else {
                setTitleOnSubtitleView(titleView, filename: filename)
                setSubtitleOnSubtitleView(subtitleView, fileSize: fileSize, uti: uti)
            }
        case .downloadableOrDownloading(progress: let progress, fileSize: let fileSize, uti: let uti, filename: let filename):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.pausedOrDownloading(progress: progress))
            tapToReadView.messageObjectID = nil
            imageView.reset()
            setTitleOnSubtitleView(titleView, filename: filename)
            setSubtitleOnSubtitleView(subtitleView, fileSize: fileSize, uti: uti)
        case .completeButReadRequiresUserInteraction(messageObjectID: let messageObjectID, fileSize: let fileSize, uti: let uti):
            tapToReadView.isHidden = false
            fyleProgressView.setConfiguration(.complete)
            tapToReadView.messageObjectID = messageObjectID
            imageView.reset()
            setTitleOnSubtitleView(titleView, filename: nil)
            setSubtitleOnSubtitleView(subtitleView, fileSize: fileSize, uti: uti)
        case .complete(hardlink: let hardlink, thumbnail: let thumbnail, fileSize: let fileSize, uti: let uti, filename: let filename):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.complete)
            tapToReadView.messageObjectID = nil
            if let hardlink = hardlink {
                imageView.setHardlink(newHardlink: hardlink, withImage: thumbnail)
            } else {
                imageView.reset()
            }
            if let url = hardlink?.hardlinkURL {
                setTitleOnSubtitleView(titleView, url: url)
                setSubtitleOnSubtitleView(subtitleView, url: url)
            } else {
                setTitleOnSubtitleView(titleView, filename: filename)
                setSubtitleOnSubtitleView(subtitleView, fileSize: fileSize, uti: uti)
            }
        case .cancelledByServer(fileSize: let fileSize, uti: let uti, filename: let filename):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.cancelled)
            tapToReadView.messageObjectID = nil
            imageView.reset()
            setTitleOnSubtitleView(titleView, filename: filename)
            setSubtitleOnSubtitleView(subtitleView, fileSize: fileSize, uti: uti)
        }

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
        subtitleElements.append(byteCountFormatter.string(fromByteCount: Int64(fileSize)))
        if let uti = UTType(uti), let type = uti.localizedDescription {
            subtitleElements.append(type)
        }
        let subtitleText = subtitleElements.joined(separator: " - ")
        if subtitleView.text != subtitleText {
            subtitleView.text = subtitleText
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

        
    var maskedCorner: UIRectCorner {
        get { bubble.maskedCorner }
        set { bubble.maskedCorner = newValue }
    }

    
    private var requestId = UUID()
    private var currentURLs = [URL]()
    private let mainStack = OlvidVerticalStackView(gap: 1, side: .bothSides, debugName: "Attachments view main stack view", showInStack: true)
    private let bubble = BubbleView()
    private let byteCountFormatter = ByteCountFormatter()
    let expirationIndicator = ExpirationIndicatorView()
    let expirationIndicatorSide: ExpirationIndicatorView.Side
    private var tapGestures = [UITapGestureRecognizer]()

    private var singleAttachmentViews: [SingleAttachmentView] {
        mainStack.arrangedSubviews.compactMap({ $0 as? SingleAttachmentView })
    }

    private func prepareSingleAttachmentViews(count: Int) {
        // Make sure there are enough horizontal pair of images views
        let numberOfSingleAttachmentViewsToAdd = max(0, count - singleAttachmentViews.count)
        for _ in 0..<numberOfSingleAttachmentViewsToAdd {
            let view = SingleAttachmentView()
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(singleAttachmentViewWasTapped(sender:)))
            tapGesture.delegate = self
            tapGestures += [tapGesture]
            view.addGestureRecognizer(tapGesture)
            view.isUserInteractionEnabled = true
            view.translatesAutoresizingMaskIntoConstraints = false
            mainStack.addArrangedSubview(view)
        }
        // Show only the required attachment views
        for index in 0..<singleAttachmentViews.count {
            singleAttachmentViews[index].showInStack = (index < count)
            singleAttachmentViews[index].reset()
        }
    }
    
    
    @objc private func singleAttachmentViewWasTapped(sender: UITapGestureRecognizer) {
        assert(delegate != nil)
        guard let attachmentView = sender.view as? SingleAttachmentView else { assertionFailure(); return }
        let imageView = attachmentView.imageView
        guard let hardlink = imageView.hardlink else { return }
        delegate?.userDidTapOnFyleMessageJoinWithHardLink(hardlinkTapped: hardlink)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if tapGestures.contains(where: { $0 == gestureRecognizer }),
           let otherTapGestureRecognizer = otherGestureRecognizer as? UITapGestureRecognizer,
           otherTapGestureRecognizer.numberOfTapsRequired == 2 {
            return true
        }
        return false
    }
    
    
    init(expirationIndicatorSide side: ExpirationIndicatorView.Side) {
        self.expirationIndicatorSide = side
        super.init(frame: .zero)
        setupInternalViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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


@available(iOS 14.0, *)
fileprivate final class SingleAttachmentView: ViewForOlvidStack {
    
    fileprivate let imageView = UIImageViewForHardLink()
    fileprivate let title = UILabel()
    fileprivate let subtitle = UILabel()
    private let labelsBackground = UIView()
    fileprivate let tapToReadView = TapToReadView(showText: false)
    fileprivate let fyleProgressView = FyleProgressView()

    private let height = CGFloat(40)
    
    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }

    func reset() {
        if self.title.text != nil {
            self.title.text = nil
        }
        if self.subtitle.text != nil {
            self.subtitle.text = nil
        }
        self.imageView.reset()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupInternalViews() {
        
        clipsToBounds = true
        backgroundColor = .secondarySystemFill
        
        addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.clipsToBounds = true
        
        addSubview(labelsBackground)
        labelsBackground.translatesAutoresizingMaskIntoConstraints = false
        
        labelsBackground.addSubview(title)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = UIFont.preferredFont(forTextStyle: .caption1)
        title.textColor = .label
        
        labelsBackground.addSubview(subtitle)
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = UIFont.preferredFont(forTextStyle: .caption2)
        subtitle.textColor = .secondaryLabel

        addSubview(fyleProgressView)
        fyleProgressView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(tapToReadView)
        tapToReadView.translatesAutoresizingMaskIntoConstraints = false
        tapToReadView.tapToReadLabelTextColor = .label

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: self.topAnchor),
            imageView.trailingAnchor.constraint(equalTo: labelsBackground.leadingAnchor, constant: -CGFloat(4)),
            imageView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            labelsBackground.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            labelsBackground.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            title.topAnchor.constraint(equalTo: labelsBackground.topAnchor),
            title.trailingAnchor.constraint(equalTo: labelsBackground.trailingAnchor),
            title.bottomAnchor.constraint(equalTo: subtitle.topAnchor, constant: -CGFloat(2)),
            title.leadingAnchor.constraint(equalTo: labelsBackground.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: labelsBackground.trailingAnchor),
            subtitle.bottomAnchor.constraint(equalTo: labelsBackground.bottomAnchor),
            subtitle.leadingAnchor.constraint(equalTo: labelsBackground.leadingAnchor),
            
            fyleProgressView.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            fyleProgressView.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),

            tapToReadView.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            tapToReadView.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),

        ])
        
        let sizeConstraints = [
            imageView.widthAnchor.constraint(equalToConstant: MessageCellConstants.attachmentIconSize),
            imageView.heightAnchor.constraint(equalToConstant: MessageCellConstants.attachmentIconSize),
            tapToReadView.widthAnchor.constraint(equalToConstant: MessageCellConstants.attachmentIconSize),
            tapToReadView.heightAnchor.constraint(equalToConstant: MessageCellConstants.attachmentIconSize),
            self.widthAnchor.constraint(equalToConstant: MessageCellConstants.singleAttachmentViewWidth),
        ]
        NSLayoutConstraint.activate(sizeConstraints)

    }
    
}
