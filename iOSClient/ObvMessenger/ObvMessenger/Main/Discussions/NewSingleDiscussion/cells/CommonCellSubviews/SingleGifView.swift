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
import LinkPresentation


@available(iOS 14.0, *)
final class SingleGifView: ViewForOlvidStack, ViewWithMaskedCorners, ViewWithExpirationIndicator, UIViewWithTappableStuff {
    
    private var currentConfiguration: SingleImageView.Configuration?
    private var currentSetImageURL: URL?

    
    func setConfiguration(_ newConfiguration: SingleImageView.Configuration) {
        guard self.currentConfiguration != newConfiguration else { return }
        self.currentConfiguration = newConfiguration
        refresh()
    }


    private var constraintsToActivate = Set<NSLayoutConstraint>()
    private var constraintsToDeactivate = Set<NSLayoutConstraint>()

    private func refresh() {
        currentRefreshId = UUID()
        switch currentConfiguration {
        case .uploadableOrUploading(hardlink: let hardlink, thumbnail: _, progress: let progress):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.uploadableOrUploading(progress: progress))
            tapToReadView.messageObjectID = nil
            setGifURL(hardlink?.hardlinkURL)
            bubble.backgroundColor = .clear
        case .downloadable(receivedJoinObjectID: let receivedJoinObjectID, progress: let progress, downsizedThumbnail: _):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.downloadable(receivedJoinObjectID: receivedJoinObjectID, progress: progress))
            tapToReadView.messageObjectID = nil
            removeImageURL()
            bubble.backgroundColor = .systemFill
        case .downloading(receivedJoinObjectID: let receivedJoinObjectID, progress: let progress, downsizedThumbnail: _):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.downloading(receivedJoinObjectID: receivedJoinObjectID, progress: progress))
            tapToReadView.messageObjectID = nil
            removeImageURL()
            bubble.backgroundColor = .systemFill
        case .completeButReadRequiresUserInteraction(messageObjectID: let messageObjectID):
            tapToReadView.isHidden = false
            fyleProgressView.setConfiguration(.complete)
            tapToReadView.messageObjectID = messageObjectID
            removeImageURL()
            bubble.backgroundColor = .systemFill
        case .complete(downsizedThumbnail: _, hardlink: let hardlink, thumbnail: _):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.complete)
            setGifURL(hardlink?.hardlinkURL)
            tapToReadView.messageObjectID = nil
            bubble.backgroundColor = .clear
        case .cancelledByServer:
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.cancelled)
            tapToReadView.messageObjectID = nil
            removeImageURL()
            bubble.backgroundColor = .systemFill
        case .none:
            assertionFailure()
        }
    }

    
    private func removeImageURL() {
        currentSetImageURL = nil
        imageView.image = nil
        setupWidthAndHeightConstraints(width: MessageCellConstants.defaultGifViewSize.width, height: MessageCellConstants.defaultGifViewSize.height)
    }

        
    private func setGifURL(_ url: URL?) {
        let localRefreshId = self.currentRefreshId
        currentGifURL = url
        guard let url = url else {
            imageView.image = nil
            return
        }
        guard let image = UIImage(contentsOfFile: url.path) else { assertionFailure(); return }
        setupWidthAndHeightConstraints(width: imageMaxSize * min(1, CGFloat(image.size.width) / CGFloat(image.size.height)),
                                       height: imageMaxSize * min(1, CGFloat(image.size.height) / CGFloat(image.size.width)))
        CGAnimateImageAtURLWithBlock(url as CFURL, nil) { [weak self] (someInt, cgImage, stopAnimation) in
            guard let _self = self else {
                stopAnimation.pointee = true
                return
            }
            guard _self.currentRefreshId == localRefreshId else {
                stopAnimation.pointee = true
                return
            }
            guard _self.currentGifURL == url else {
                stopAnimation.pointee = true
                return
            }
            _self.imageView.image = UIImage(cgImage: cgImage)
        }
    }

    
    var maskedCorner: UIRectCorner {
        get { bubble.maskedCorner }
        set { bubble.maskedCorner = newValue }
    }

    
    init(expirationIndicatorSide side: ExpirationIndicatorView.Side) {
        self.expirationIndicatorSide = side
        super.init(frame: .zero)
        setupInternalViews()
    }
    

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    private var currentRefreshId = UUID()
    private var currentGifURL: URL?
    private let bubble = BubbleView()
    private let imageMaxSize = CGFloat(241)
    private let imageView = UIImageView()
    private let tapToReadView = TapToReadView(showText: false)
    private let fyleProgressView = FyleProgressView()

    private var gifWidthConstraint: NSLayoutConstraint?
    private var gifHeightConstraint: NSLayoutConstraint?
    private var gifConstraintsNeedsToBeComputed = true

    let expirationIndicator = ExpirationIndicatorView()
    let expirationIndicatorSide: ExpirationIndicatorView.Side

    
    func tappedStuff(tapGestureRecognizer: UITapGestureRecognizer, acceptTapOutsideBounds: Bool) -> TappedStuffForCell? {
        let viewsWithTappableStuff = [tapToReadView, fyleProgressView].filter({ $0.isHidden == false }) as [UIViewWithTappableStuff]
        let view = viewsWithTappableStuff.first(where: { $0.tappedStuff(tapGestureRecognizer: tapGestureRecognizer) != nil })
        return view?.tappedStuff(tapGestureRecognizer: tapGestureRecognizer)
    }

    
    private func setupInternalViews() {
                        
        addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.backgroundColor = .systemFill

        addSubview(expirationIndicator)
        expirationIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        bubble.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(tapToReadView)
        tapToReadView.translatesAutoresizingMaskIntoConstraints = false
        tapToReadView.isUserInteractionEnabled = true

        addSubview(fyleProgressView)
        fyleProgressView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            
            bubble.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            bubble.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: self.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            
            imageView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: bubble.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
            
            tapToReadView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            tapToReadView.centerYAnchor.constraint(equalTo: self.centerYAnchor),

            fyleProgressView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            fyleProgressView.centerYAnchor.constraint(equalTo: self.centerYAnchor),

        ])
        
        initialSetupWidthAndHeightConstraints(width: MessageCellConstants.defaultGifViewSize.width, height: MessageCellConstants.defaultGifViewSize.height)

        setupConstraintsForExpirationIndicator(gap: MessageCellConstants.gapBetweenExpirationViewAndBubble)
        
    }

    
    private func initialSetupWidthAndHeightConstraints(width: CGFloat, height: CGFloat) {
        
        assert(self.gifWidthConstraint == nil)
        gifWidthConstraint = bubble.widthAnchor.constraint(equalToConstant: width)
        gifWidthConstraint!.priority -= 1
        
        assert(self.gifHeightConstraint == nil)
        gifHeightConstraint = bubble.heightAnchor.constraint(equalToConstant: height)
        gifHeightConstraint!.priority -= 1
        
        NSLayoutConstraint.activate([gifWidthConstraint!, gifHeightConstraint!])
    }
    
    
    private func setupWidthAndHeightConstraints(width: CGFloat, height: CGFloat) {
        
        guard let gifWidthConstraint = self.gifWidthConstraint else { assertionFailure(); return }
        guard let gifHeightConstraint = self.gifHeightConstraint else { assertionFailure(); return }
        
        if gifWidthConstraint.constant != width {
            gifWidthConstraint.constant = width
            setNeedsUpdateConstraints()
        }
        
        if gifHeightConstraint.constant != height {
            gifHeightConstraint.constant = height
            setNeedsUpdateConstraints()
        }
        
    }
    
}
