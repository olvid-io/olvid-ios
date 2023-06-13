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
import UniformTypeIdentifiers


@available(iOS 14.0, *)
final class SingleGifView: ViewForOlvidStack, ViewWithMaskedCorners, ViewWithExpirationIndicator, UIViewWithTappableStuff {
    

    private var currentConfiguration: SingleImageView.Configuration?

    
    func setConfiguration(_ newConfiguration: SingleImageView.Configuration) {
        guard self.currentConfiguration != newConfiguration else { return }
        self.currentConfiguration = newConfiguration
        refresh()
    }

    
    func startAnimating() {
        // Calling imageView.startAnimating() does not always work here, for some reason.
        // We force the animation by reseting the imageView.image completly
        if let image = imageView.image {
            imageView.image = nil
            imageView.image = image
            imageView.alpha = 1.0
        }
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
        currentGifURL = nil
        imageView.image = nil
        imageView.alpha = 0.0
        setupWidthAndHeightConstraints(width: MessageCellConstants.defaultGifViewSize.width, height: MessageCellConstants.defaultGifViewSize.height)
    }

        
    private func setGifURL(_ url: URL?) {
        guard let url else {
            return
        }
        if currentGifURL != url {
            removeImageURL()
        }
        let localRefreshId = self.currentRefreshId
        currentGifURL = url
        if ProcessInfo.processInfo.isOperatingSystemAtLeast(.init(majorVersion: 16, minorVersion: 4, patchVersion: 0)) {
            animateGif(localRefreshId: localRefreshId)
        } else {
            legacyAnimateGif(localRefreshId: localRefreshId)
        }
    }
    
    
    /// This method animates the gif at the `currentGifURL`.
    /// This method crashes under iOS 16.4.
    @available(iOS, deprecated: 16.4, message: "Use animateGif instead")
    private func legacyAnimateGif(localRefreshId: UUID) {
        guard let url = currentGifURL else { return }
        guard let image = UIImage(contentsOfFile: url.path) else { assertionFailure(); return }
        setupWidthAndHeightConstraints(width: Self.imageMaxSize * min(1, CGFloat(image.size.width) / CGFloat(image.size.height)),
                                       height: Self.imageMaxSize * min(1, CGFloat(image.size.height) / CGFloat(image.size.width)))
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
            self?.imageView.alpha = 1.0
        }
    }
    
    
    /// This method animates the gif at the `currentGifURL`.
    /// It is used as a replacement of ``func legacyAnimateGif(localRefreshId: UUID)`` as this legacy method crashes under iOS 16.4.
    private func animateGif(localRefreshId: UUID) {
        guard let url = currentGifURL else { return }
        guard let imageSourceOptions = [kCGImageSourceTypeIdentifierHint: UTType.gif.identifier] as? CFDictionary,
              let cgImageSource = CGImageSourceCreateWithURL(url as CFURL, imageSourceOptions),
              let cgImageSourceProperties = CGImageSourceCopyProperties(cgImageSource, nil) as? Dictionary<CFString, Any>,
              let gifProperties = cgImageSourceProperties[kCGImagePropertyGIFDictionary] as? Dictionary<CFString, Any>,
              let canvasPixelWidth = gifProperties[kCGImagePropertyGIFCanvasPixelWidth] as? NSNumber,
              let canvasPixelHeight = gifProperties[kCGImagePropertyGIFCanvasPixelHeight] as? NSNumber
        else {
            assertionFailure()
            return
        }
        setupWidthAndHeightConstraints(width: Self.imageMaxSize * min(1, CGFloat(truncating: canvasPixelWidth) / CGFloat(truncating: canvasPixelHeight)),
                                       height: Self.imageMaxSize * min(1, CGFloat(truncating: canvasPixelHeight) / CGFloat(truncating: canvasPixelWidth)))
        Task.detached(priority: .userInitiated) { [weak self] in
            let cgImageSourceCount = CGImageSourceGetCount(cgImageSource)
            let thmbnailOptions = [kCGImageSourceThumbnailMaxPixelSize: Self.imageMaxSize as NSNumber, kCGImageSourceCreateThumbnailFromImageIfAbsent: kCFBooleanTrue] as CFDictionary
            let cgImages = (0..<cgImageSourceCount).compactMap { CGImageSourceCreateThumbnailAtIndex(cgImageSource, $0, thmbnailOptions) }
            let images = cgImages.map { UIImage(cgImage: $0) }
            guard let gifFrameInfoArray = gifProperties[kCGImagePropertyGIFFrameInfoArray] as? [Dictionary<CFString, Any>],
                  let gifDelayTimes = gifFrameInfoArray.map({ ($0[kCGImagePropertyGIFDelayTime] ) }) as? [NSNumber]
            else {
                assertionFailure()
                return
            }
            let duration = gifDelayTimes.map({ $0.doubleValue }).reduce(0, +)
            let animatedImage: UIImage?
            if #available(iOS 15.0, *) {
                animatedImage = await UIImage.animatedImage(with: images, duration: duration)?.byPreparingForDisplay()
            } else {
                animatedImage = UIImage.animatedImage(with: images, duration: duration)
            }
            DispatchQueue.main.async { [weak self] in
                guard localRefreshId == self?.currentRefreshId else { return }
                self?.imageView.image = animatedImage
                UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.2, delay: 0) { [weak self] in
                    guard localRefreshId == self?.currentRefreshId else { return }
                    self?.imageView.alpha = 1.0
                }
            }
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
    private static let imageMaxSize = CGFloat(241)
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
        imageView.alpha = 0

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
