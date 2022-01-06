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
import QuickLookThumbnailing
import CoreData


@available(iOS 14.0, *)
final class SingleImageView: ViewForOlvidStack, ViewWithMaskedCorners, ViewWithExpirationIndicator, ViewShowingHardLinks, UIGestureRecognizerDelegate {

    enum Configuration: Equatable, Hashable {
        // For sent attachments
        case uploadableOrUploading(hardlink: HardLinkToFyle?, thumbnail: UIImage?, progress: Progress?)
        // For received attachments
        case downloadableOrDownloading(progress: Progress?, downsizedThumbnail: UIImage?)
        case completeButReadRequiresUserInteraction(messageObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>)
        case cancelledByServer // Also used when there is an error with the Fyle URL
        // For both (downsizedThumbnail always nil for sent attachments)
        case complete(downsizedThumbnail: UIImage?, hardlink: HardLinkToFyle?, thumbnail: UIImage?)

        var hardlink: HardLinkToFyle? {
            switch self {
            case .complete(downsizedThumbnail: _, hardlink: let hardlink, thumbnail: _), .uploadableOrUploading(hardlink: let hardlink, thumbnail: _, progress: _):
                return hardlink
            case .downloadableOrDownloading, .completeButReadRequiresUserInteraction, .cancelledByServer:
                return nil
            }
        }
    }
    
    weak var delegate: ViewShowingHardLinksDelegate?

    func getAllShownHardLink() -> [(hardlink: HardLinkToFyle, viewShowingHardLink: UIView)] {
        guard self.showInStack else { return [] }
        if let hardlink = imageView.hardlink {
            return [(hardlink, imageView)]
        } else {
            return []
        }
    }
    
    private var currentConfiguration: Configuration?
    
    func setConfiguration(_ newConfiguration: SingleImageView.Configuration) {
        guard self.currentConfiguration != newConfiguration else { return }
        self.currentConfiguration = newConfiguration
        refresh()
    }
    
    private func refresh() {
        switch currentConfiguration {
        case .uploadableOrUploading(hardlink: let hardlink, thumbnail: let thumbnail, progress: let progress):
            tapToReadView.isHidden = true
            hidingView.isHidden = true
            fyleProgressView.setConfiguration(.uploadableOrUploading(progress: progress))
            tapToReadView.messageObjectID = nil
            if let hardlink = hardlink {
                imageView.setHardlink(newHardlink: hardlink, withImage: thumbnail)
            } else {
                imageView.reset()
            }
            bubble.backgroundColor = .clear
        case .downloadableOrDownloading(progress: let progress, downsizedThumbnail: let downsizedThumbnail):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.pausedOrDownloading(progress: progress))
            tapToReadView.messageObjectID = nil
            if let downsizedThumbnail = downsizedThumbnail {
                hidingView.isHidden = true
                imageView.setDownsizedThumbnail(withImage: downsizedThumbnail)
            } else {
                hidingView.isHidden = false
                imageView.reset()
            }
            bubble.backgroundColor = .systemFill
        case .completeButReadRequiresUserInteraction(messageObjectID: let messageObjectID):
            tapToReadView.isHidden = false
            hidingView.isHidden = false
            fyleProgressView.setConfiguration(.complete)
            tapToReadView.messageObjectID = messageObjectID
            imageView.reset()
            bubble.backgroundColor = .systemFill
        case .complete(downsizedThumbnail: let downsizedThumbnail, hardlink: let hardlink, thumbnail: let thumbnail):
            tapToReadView.isHidden = true
            hidingView.isHidden = true
            fyleProgressView.setConfiguration(.complete)
            if let hardlink = hardlink {
                imageView.setHardlink(newHardlink: hardlink, withImage: thumbnail ?? downsizedThumbnail)
            } else {
                imageView.reset()
            }
            tapToReadView.messageObjectID = nil
            bubble.backgroundColor = .clear
        case .cancelledByServer:
            tapToReadView.isHidden = true
            hidingView.isHidden = false
            fyleProgressView.setConfiguration(.cancelled)
            tapToReadView.messageObjectID = nil
            imageView.reset()
            bubble.backgroundColor = .systemFill
        case .none:
            assertionFailure()
        }
    }
    
    var maskedCorner: UIRectCorner {
        get { bubble.maskedCorner }
        set { bubble.maskedCorner = newValue }
    }

    private let imageView = UIImageViewForHardLink()
    let fyleProgressView = FyleProgressView()
    private let hidingView = UIView()
    private let tapToReadView = TapToReadView(showText: false)
    
    private let bubble = BubbleView()
    static let imageSize = CGFloat(200)
    let expirationIndicator = ExpirationIndicatorView()
    let expirationIndicatorSide: ExpirationIndicatorView.Side
    private var readingRequiresUserAction = false
    private var tapGesture: UITapGestureRecognizer?


    init(expirationIndicatorSide side: ExpirationIndicatorView.Side) {
        self.expirationIndicatorSide = side
        super.init(frame: .zero)
        setupInternalViews()
        setupTapGestureOnImageView()
    }
    

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    private func setupInternalViews() {
                        
        addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.backgroundColor = .systemFill
        
        addSubview(expirationIndicator)
        expirationIndicator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(fyleProgressView)
        fyleProgressView.translatesAutoresizingMaskIntoConstraints = false
        
        bubble.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
                
        bubble.addSubview(hidingView)
        hidingView.translatesAutoresizingMaskIntoConstraints = false
        hidingView.backgroundColor = .secondarySystemBackground
        
        hidingView.addSubview(tapToReadView)
        tapToReadView.translatesAutoresizingMaskIntoConstraints = false
        tapToReadView.tapToReadLabelTextColor = .label
        
        let constraints = [
            bubble.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            bubble.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: self.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: bubble.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
            fyleProgressView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            fyleProgressView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            
            hidingView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
            hidingView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
            hidingView.topAnchor.constraint(equalTo: bubble.topAnchor),
            hidingView.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
            
            hidingView.centerXAnchor.constraint(equalTo: tapToReadView.centerXAnchor),
            hidingView.centerYAnchor.constraint(equalTo: tapToReadView.centerYAnchor),
        ]
        constraints.forEach { $0.priority -= 1 }
        NSLayoutConstraint.activate(constraints)

        let sizeConstraints = [
            bubble.widthAnchor.constraint(equalToConstant: SingleImageView.imageSize),
            bubble.heightAnchor.constraint(equalToConstant: SingleImageView.imageSize),
            tapToReadView.widthAnchor.constraint(equalToConstant: SingleImageView.imageSize),
            tapToReadView.heightAnchor.constraint(equalToConstant: SingleImageView.imageSize),
        ]
        sizeConstraints.forEach { $0.priority -= 1 }
        NSLayoutConstraint.activate(sizeConstraints)

        setupConstraintsForExpirationIndicator(gap: MessageCellConstants.gapBetweenExpirationViewAndBubble)

    }
 
    
    private func setupTapGestureOnImageView() {
        tapGesture = UITapGestureRecognizer(target: self, action: #selector(imageViewWasTapped(sender:)))
        guard let tapGesture = tapGesture else {
            assertionFailure()
            return
        }
        tapGesture.delegate = self
        imageView.addGestureRecognizer(tapGesture)
        imageView.isUserInteractionEnabled = true
    }
    
    
    @objc private func imageViewWasTapped(sender: UIGestureRecognizer) {
        guard let imageViewForHardLink = sender.view as? UIImageViewForHardLink else { assertionFailure(); return }
        guard imageViewForHardLink == self.imageView else { assertionFailure(); return }
        guard let hardlink = imageViewForHardLink.hardlink else { return }
        assert(delegate != nil)
        delegate?.userDidTapOnFyleMessageJoinWithHardLink(hardlinkTapped: hardlink)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if tapGesture == gestureRecognizer,
           let otherTapGestureRecognizer = otherGestureRecognizer as? UITapGestureRecognizer,
           otherTapGestureRecognizer.numberOfTapsRequired == 2 {
            return true
        }
        return false
    }
}
