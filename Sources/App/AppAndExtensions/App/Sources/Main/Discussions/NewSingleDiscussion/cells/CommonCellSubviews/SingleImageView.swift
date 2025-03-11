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


@available(iOS 14.0, *)
final class SingleImageView: ViewForOlvidStack, ViewWithMaskedCorners, ViewWithExpirationIndicator, ViewShowingHardLinks, UIViewWithTappableStuff {

    enum Configuration: Equatable, Hashable {
        // For sent attachments
        case uploadableOrUploading(hardlink: HardLinkToFyle?, thumbnail: UIImage?, progress: Progress)
        // For received attachments
        case downloadable(receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>, progress: Progress, downsizedThumbnail: UIImage?)
        case downloading(receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>, progress: Progress, downsizedThumbnail: UIImage?)
        case completeButReadRequiresUserInteraction(messageObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>)
        case cancelledByServer // Also used when there is an error with the Fyle URL
        // For received attachments sent from other owned device
        case downloadableSent(sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>, progress: Progress, downsizedThumbnail: UIImage?)
        case downloadingSent(sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>, progress: Progress, downsizedThumbnail: UIImage?)
        // For both (downsizedThumbnail always nil for sent attachments)
        case complete(downsizedThumbnail: UIImage?, hardlink: HardLinkToFyle?, thumbnail: UIImage?)

        var hardlink: HardLinkToFyle? {
            switch self {
            case .complete(downsizedThumbnail: _, hardlink: let hardlink, thumbnail: _), .uploadableOrUploading(hardlink: let hardlink, thumbnail: _, progress: _):
                return hardlink
            case .downloadable, .downloading, .completeButReadRequiresUserInteraction, .cancelledByServer, .downloadableSent, .downloadingSent:
                return nil
            }
        }
    }
    
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
        case .downloadable(receivedJoinObjectID: let receivedJoinObjectID, progress: let progress, downsizedThumbnail: let downsizedThumbnail):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.downloadable(receivedJoinObjectID: receivedJoinObjectID, progress: progress))
            tapToReadView.messageObjectID = nil
            if let downsizedThumbnail = downsizedThumbnail {
                hidingView.isHidden = true
                imageView.setDownsizedThumbnail(withImage: downsizedThumbnail)
            } else {
                hidingView.isHidden = false
                imageView.reset()
            }
            bubble.backgroundColor = .systemFill
        case .downloadableSent(sentJoinObjectID: let sentJoinObjectID, progress: let progress, downsizedThumbnail: let downsizedThumbnail):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.downloadableSent(sentJoinObjectID: sentJoinObjectID, progress: progress))
            tapToReadView.messageObjectID = nil
            if let downsizedThumbnail = downsizedThumbnail {
                hidingView.isHidden = true
                imageView.setDownsizedThumbnail(withImage: downsizedThumbnail)
            } else {
                hidingView.isHidden = false
                imageView.reset()
            }
            bubble.backgroundColor = .systemFill
        case .downloading(receivedJoinObjectID: let receivedJoinObjectID, progress: let progress, downsizedThumbnail: let downsizedThumbnail):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.downloading(receivedJoinObjectID: receivedJoinObjectID, progress: progress))
            tapToReadView.messageObjectID = nil
            if let downsizedThumbnail = downsizedThumbnail {
                hidingView.isHidden = true
                imageView.setDownsizedThumbnail(withImage: downsizedThumbnail)
            } else {
                hidingView.isHidden = false
                imageView.reset()
            }
            bubble.backgroundColor = .systemFill
        case .downloadingSent(sentJoinObjectID: let sentJoinObjectID, progress: let progress, downsizedThumbnail: let downsizedThumbnail):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.downloadingSent(sentJoinObjectID: sentJoinObjectID, progress: progress))
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
            bubble.backgroundColor = .systemFill
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
 
}
