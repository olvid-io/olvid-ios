/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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

public protocol ObvImageEditorViewControllerDelegate: AnyObject {
    func userCancelledImageEdition(_ imageEditor: ObvImageEditorViewController) async
    func userConfirmedImageEdition(_ imageEditor: ObvImageEditorViewController, image: UIImage) async
}


public final class ObvImageEditorViewController: UIViewController, UIScrollViewDelegate {
    
    private let originalImage: UIImage
    private let imageViewContainer = ObvImageViewContainer()
    private let scrollView = UIScrollView()
    private let loadingView = LoadingView()
    private let cropView = UIView()
    private let alphaView = AlphaView()
    private let showZoomButtons: Bool
    private let maxReturnedImageSize: (width: Int, height: Int)? // In pixels

    private var imageViewTopAnchorConstraint: NSLayoutConstraint!
    private var imageViewTrailingAnchorConstraint: NSLayoutConstraint!
    private var imageViewBottomAnchorConstraint: NSLayoutConstraint!
    private var imageViewLeadingAnchorConstraint: NSLayoutConstraint!

    weak var delegate: ObvImageEditorViewControllerDelegate?
    
    public init(originalImage: UIImage, showZoomButtons: Bool, maxReturnedImageSize: (width: Int, height: Int)?, delegate: ObvImageEditorViewControllerDelegate) {
        self.originalImage = originalImage
        self.showZoomButtons = showZoomButtons
        self.maxReturnedImageSize = maxReturnedImageSize
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }
    
    deinit {
        debugPrint("ObvImageEditorViewController deinit")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    // MARK: View controller lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        // Prevents the interactive dismissal of the view controller while it is onscreen
        //self.isModalInPresentation = true
        
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(scrollView)
        scrollView.backgroundColor = .black
        scrollView.contentInsetAdjustmentBehavior = .never
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: self.view.topAnchor),
            scrollView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
        ])
        
        alphaView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(alphaView)
        NSLayoutConstraint.activate([
            alphaView.topAnchor.constraint(equalTo: self.view.topAnchor),
            alphaView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            alphaView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            alphaView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
        ])
        
        cropView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(cropView)
        cropView.isUserInteractionEnabled = false
        NSLayoutConstraint.activate([
            cropView.topAnchor.constraint(equalTo: alphaView.centerView.topAnchor),
            cropView.trailingAnchor.constraint(equalTo: alphaView.centerView.trailingAnchor),
            cropView.bottomAnchor.constraint(equalTo: alphaView.centerView.bottomAnchor),
            cropView.leadingAnchor.constraint(equalTo: alphaView.centerView.leadingAnchor),
        ])
        
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(loadingView)
        
        NSLayoutConstraint.activate([
            loadingView.topAnchor.constraint(equalTo: self.view.topAnchor),
            loadingView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
            loadingView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            loadingView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
        ])

        imageViewContainer.image = originalImage
        imageViewContainer.translatesAutoresizingMaskIntoConstraints = false
        imageViewContainer.contentMode = .scaleAspectFit
        scrollView.addSubview(imageViewContainer)
        
        imageViewTopAnchorConstraint = imageViewContainer.topAnchor.constraint(equalTo: scrollView.topAnchor)
        imageViewTrailingAnchorConstraint = imageViewContainer.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor)
        imageViewBottomAnchorConstraint = imageViewContainer.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor)
        imageViewLeadingAnchorConstraint = imageViewContainer.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor)

        NSLayoutConstraint.activate([
            imageViewTopAnchorConstraint,
            imageViewTrailingAnchorConstraint,
            imageViewBottomAnchorConstraint,
            imageViewLeadingAnchorConstraint,
        ])

        scrollView.delegate = self
        
        scrollView.minimumZoomScale = 0.01
        scrollView.maximumZoomScale = 10
        
        // Configure the buttons
        
        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.buttonSize = .large
        buttonConfiguration.cornerStyle = .capsule
        
        let cancelButton = UIButton(type: .system, primaryAction: UIAction(handler: { [weak self] _ in
            Task { [weak self] in await self?.userTappedTheCancelButton() }
        }))
        cancelButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        buttonConfiguration.baseBackgroundColor = .systemRed
        cancelButton.configuration = buttonConfiguration
        self.view.addSubview(cancelButton)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 50),
            cancelButton.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: -50),
        ])

        let okButton = UIButton(type: .system, primaryAction: UIAction(handler: { [weak self] _ in
            Task { [weak self] in await self?.userTappedTheOkButton() }
        }))
        okButton.setImage(UIImage(systemName: "checkmark"), for: .normal)
        buttonConfiguration.baseBackgroundColor = .systemGreen
        okButton.configuration = buttonConfiguration
        self.view.addSubview(okButton)
        okButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            okButton.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -50),
            okButton.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: -50),
        ])

        // Configure the zoom buttons
        
        if showZoomButtons {
            
            let stack = UIStackView()
            self.view.addSubview(stack)
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.axis = .horizontal
            stack.distribution = .fillEqually
            stack.spacing = 12
            
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 50),
                stack.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -50),
            ])
            
            var configuration = UIButton.Configuration.filled()
            configuration.buttonSize = .small
            configuration.cornerStyle = .capsule
            configuration.baseBackgroundColor = .systemGray

            let minusButton = UIButton(type: .system, primaryAction: UIAction(handler: { [weak self] _ in
                self?.userTappedZoomButtonMinus()
            }))
            minusButton.configuration = configuration
            minusButton.setImage(UIImage(systemName: "minus.magnifyingglass"), for: .normal)
            stack.addArrangedSubview(minusButton)

            let plusButton = UIButton(type: .system, primaryAction: UIAction(handler: { [weak self] _ in
                self?.userTappedZoomButtonPlus()
            }))
            plusButton.configuration = configuration
            plusButton.setImage(UIImage(systemName: "plus.magnifyingglass"), for: .normal)
            stack.addArrangedSubview(plusButton)

        }
        
    }
    

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        recomputeMinimumZoomScale()
        resetImageContainerPadding()
        
    }
    
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        recomputeMinimumZoomScale()
        scrollView.zoomScale = scrollView.minimumZoomScale
        resetImageContainerPadding()
        recenterImageIfAppropriate()

        removeLoadingViewIfRequired()
        
    }
    
    
    // MARK: Buttons actions
    
    private func userTappedTheCancelButton() async {
        await delegate?.userCancelledImageEdition(self)
    }
    
    
    private func userTappedTheOkButton() async {
        guard let croppedImage = await cropImage() else { assertionFailure(); return }
        await delegate?.userConfirmedImageEdition(self, image: croppedImage)
    }
    
    
    @MainActor
    private func cropImage() async -> UIImage? {
        guard let originalCGImage = originalImage.cgImage?.toUpOrientation(from: originalImage.imageOrientation) else { assertionFailure(); return nil }
        let cropSize = CGSize(
            width: cropView.bounds.width / scrollView.zoomScale,
            height: cropView.bounds.height / scrollView.zoomScale)
        let cropOrigin = CGPoint(
            x: scrollView.contentOffset.x / scrollView.zoomScale,
            y: scrollView.contentOffset.y / scrollView.zoomScale)
        let cropRect = CGRect(
            origin: cropOrigin,
            size: cropSize)
        guard let croppedCGImage = originalCGImage.cropping(to: cropRect) else { return nil }
        let croppedImage = UIImage(cgImage: croppedCGImage)
        let resizedImage: UIImage
        if let maxReturnedImageSize {
            resizedImage = Self.resizeImage(croppedImage, maxSize: maxReturnedImageSize) ?? croppedImage
        } else {
            resizedImage = croppedImage
        }
        debugPrint(resizedImage)
        return resizedImage
    }
    
    
    private static func resizeImage(_ image: UIImage, maxSize: (width: Int, height: Int)) -> UIImage? {

        guard let cgImage = image.cgImage?.toUpOrientation(from: image.imageOrientation) else { assertionFailure(); return nil }

        let ratio = min(Double(maxSize.width) / Double(cgImage.width), Double(maxSize.height) / Double(cgImage.height))
        guard ratio < 1 else { return image }

        let width = Int(ceil(Double(cgImage.width) * ratio))
        let height = Int(ceil(Double(cgImage.height) * ratio))
        
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: cgImage.bitsPerComponent,
            bytesPerRow: 0,
            space: cgImage.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: cgImage.bitmapInfo.rawValue)
        context?.interpolationQuality = .high
        context?.draw(cgImage, in: CGRect(origin: .zero, size: .init(width: width, height: height)))

        guard let scaledImage = context?.makeImage() else { return nil }

        return UIImage(cgImage: scaledImage, scale: 1.0, orientation: image.imageOrientation)
        
    }
    
    

    
    private func userTappedZoomButtonPlus() {
        let newZoomScale = scrollView.zoomScale * 1.1
        scrollView.zoomScale = min(scrollView.maximumZoomScale, newZoomScale)
    }

    
    private func userTappedZoomButtonMinus() {
        let newZoomScale = scrollView.zoomScale * 0.9
        scrollView.zoomScale = max(scrollView.minimumZoomScale, newZoomScale)
    }

    
    // MARK: UIScrollViewDelegate
    
    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageViewContainer
    }
    

    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        resetImageContainerPadding()
    }
    
    
    // MARK: Helper methods
    
    
    private func resetImageContainerPadding() {
        imageViewContainer.resetPadding(
            viewBounds: self.view.bounds,
            cropViewFrame: cropView.frame,
            scrollViewZoomScale: scrollView.zoomScale)
    }
    
    

    /// Makes sure the image is always centered, even it is zoomed out
    private func recenterImageIfAppropriate() {
        let offsetX = max((imageViewContainer.intrinsicContentSize.width * scrollView.zoomScale - scrollView.bounds.width) / 2.0, 0)
        let offsetY = max((imageViewContainer.intrinsicContentSize.height * scrollView.zoomScale - scrollView.bounds.height) / 2.0, 0)
        let newContentOffset = CGPoint(x: offsetX, y: offsetY)
        scrollView.setContentOffset(newContentOffset, animated: false)
    }
    
    
    private func removeLoadingViewIfRequired() {
        guard loadingView.superview != nil else { return }
        UIViewPropertyAnimator.runningPropertyAnimator(
            withDuration: 0.2,
            delay: 0.0,
            animations: { [weak self] in
                self?.loadingView.alpha = 0.0
            },
            completion: { [weak self] _ in
                self?.loadingView.removeFromSuperview()
            })
    }
    
    
    private func recomputeMinimumZoomScale() {
        let minimumZoomScaleFromWidth: CGFloat = cropView.bounds.size.width / originalImage.size.width
        let minimumZoomScaleFromHeight: CGFloat = cropView.bounds.size.height / originalImage.size.height
        let newMinimumZoomScale = max(minimumZoomScaleFromWidth, minimumZoomScaleFromHeight)
        if scrollView.minimumZoomScale != newMinimumZoomScale {
            scrollView.minimumZoomScale = newMinimumZoomScale
            scrollView.zoomScale = max(scrollView.zoomScale, scrollView.minimumZoomScale)
        }
    }

}



// MARK: - LoadingView

private final class LoadingView: UIView {
    
    convenience init() {
        self.init(frame: .zero)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        let activityIndicatorView = UIActivityIndicatorView(style: .large)
        activityIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        activityIndicatorView.startAnimating()
        activityIndicatorView.color = .white
        self.addSubview(activityIndicatorView)
        NSLayoutConstraint.activate([
            activityIndicatorView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            activityIndicatorView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}



// MARK: - ImageViewContainer

private final class ObvImageViewContainer: UIView {

    private let imageView = UIImageView()

    private lazy var topPadding: NSLayoutConstraint = { imageView.topAnchor.constraint(equalTo: self.topAnchor) }()
    private lazy var trailingPadding: NSLayoutConstraint = { imageView.trailingAnchor.constraint(equalTo: self.trailingAnchor) }()
    private lazy var bottomPadding: NSLayoutConstraint = { imageView.bottomAnchor.constraint(equalTo: self.bottomAnchor) }()
    private lazy var leadingPadding: NSLayoutConstraint = { imageView.leadingAnchor.constraint(equalTo: self.leadingAnchor) }()

    var image: UIImage? {
        get { imageView.image }
        set { imageView.image = newValue }
    }
    
    convenience init() {
        self.init(frame: .zero)
        setupViews()
    }
    
    func resetPadding(viewBounds: CGRect, cropViewFrame: CGRect, scrollViewZoomScale: CGFloat) {
        topPadding.constant = cropViewFrame.origin.y / scrollViewZoomScale
        leadingPadding.constant = cropViewFrame.origin.x / scrollViewZoomScale
        trailingPadding.constant = -max(0, (viewBounds.width - (cropViewFrame.origin.x + cropViewFrame.width)) / scrollViewZoomScale)
        bottomPadding.constant = -max(0, (viewBounds.height - (cropViewFrame.origin.y + cropViewFrame.height)) / scrollViewZoomScale)
    }
    
    private func setupViews() {
        backgroundColor = .black
        self.imageView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.imageView)
        NSLayoutConstraint.activate([topPadding, trailingPadding, bottomPadding, leadingPadding])
    }
    
    override var intrinsicContentSize: CGSize {
        return .init(
            width: abs(leadingPadding.constant) + imageView.intrinsicContentSize.width + abs(trailingPadding.constant),
            height: abs(topPadding.constant) + imageView.intrinsicContentSize.height + abs(bottomPadding.constant))
    }
    
}



// MARK: - CropView

private final class AlphaView: UIView {
    
    private static let alphaComponent: CGFloat = 0.5
    private static let centerViewSideSize: CGFloat = 300.0

    let centerView = UIView()
    
    convenience init() {
        self.init(frame: .zero)
        setupViews()
    }

    private func setupViews() {

        self.isUserInteractionEnabled = false
        
        let topView = UIView()
        self.addSubview(topView)
        topView.translatesAutoresizingMaskIntoConstraints = false
        topView.backgroundColor = .black.withAlphaComponent(Self.alphaComponent)

        let trailingView = UIView()
        self.addSubview(trailingView)
        trailingView.translatesAutoresizingMaskIntoConstraints = false
        trailingView.backgroundColor = .black.withAlphaComponent(Self.alphaComponent)

        let bottomView = UIView()
        self.addSubview(bottomView)
        bottomView.translatesAutoresizingMaskIntoConstraints = false
        bottomView.backgroundColor = .black.withAlphaComponent(Self.alphaComponent)

        let leadingView = UIView()
        self.addSubview(leadingView)
        leadingView.translatesAutoresizingMaskIntoConstraints = false
        leadingView.backgroundColor = .black.withAlphaComponent(Self.alphaComponent)

        self.addSubview(centerView)
        centerView.translatesAutoresizingMaskIntoConstraints = false
        
        let circleView = UIView()
        centerView.addSubview(circleView)
        circleView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            
            centerView.widthAnchor.constraint(equalToConstant: Self.centerViewSideSize),
            centerView.heightAnchor.constraint(equalToConstant: Self.centerViewSideSize),
            centerView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            centerView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            
            topView.topAnchor.constraint(equalTo: self.topAnchor),
            topView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            topView.bottomAnchor.constraint(equalTo: centerView.topAnchor),
            topView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            
            trailingView.topAnchor.constraint(equalTo: topView.bottomAnchor),
            trailingView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            trailingView.bottomAnchor.constraint(equalTo: bottomView.topAnchor),
            trailingView.leadingAnchor.constraint(equalTo: centerView.trailingAnchor),
            
            bottomView.topAnchor.constraint(equalTo: centerView.bottomAnchor),
            bottomView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            bottomView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            bottomView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            
            leadingView.topAnchor.constraint(equalTo: topView.bottomAnchor),
            leadingView.trailingAnchor.constraint(equalTo: centerView.leadingAnchor),
            leadingView.bottomAnchor.constraint(equalTo: bottomView.topAnchor),
            leadingView.leadingAnchor.constraint(equalTo: self.leadingAnchor),

            circleView.topAnchor.constraint(equalTo: centerView.topAnchor),
            circleView.trailingAnchor.constraint(equalTo: centerView.trailingAnchor),
            circleView.bottomAnchor.constraint(equalTo: centerView.bottomAnchor),
            circleView.leadingAnchor.constraint(equalTo: centerView.leadingAnchor),

        ])

        // Add white border
        
        centerView.layer.borderWidth = 0.5
        centerView.layer.borderColor = CGColor(gray: 1, alpha: 1)
        
        circleView.layer.borderWidth = 0.5
        circleView.layer.borderColor = CGColor(gray: 1, alpha: 1)
        circleView.layer.cornerRadius = Self.centerViewSideSize / 2

    }
    
}


fileprivate extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
            case .up: self = .up
            case .upMirrored: self = .upMirrored
            case .down: self = .down
            case .downMirrored: self = .downMirrored
            case .left: self = .left
            case .leftMirrored: self = .leftMirrored
            case .right: self = .right
            case .rightMirrored: self = .rightMirrored
        @unknown default:
            assertionFailure()
            self = .up
        }
    }
}


fileprivate extension UIImage.Orientation {
    init(_ cgOrientation: CGImagePropertyOrientation) {
        switch cgOrientation {
            case .up: self = .up
            case .upMirrored: self = .upMirrored
            case .down: self = .down
            case .downMirrored: self = .downMirrored
            case .left: self = .left
            case .leftMirrored: self = .leftMirrored
            case .right: self = .right
            case .rightMirrored: self = .rightMirrored
        }
    }
}


fileprivate extension CGImage {
    
    /// Assuming that the orientation of self is (the Core graphics equivalent of) `uiOrientation`, this method returns a `CGImage` obtained by transforming `self` to obtain an image if the `up` orientation.
    func toUpOrientation(from uiOrientation: UIImage.Orientation) -> CGImage? {
        
        guard uiOrientation != .up else { return self }

        let cgOrientation = CGImagePropertyOrientation(uiOrientation)
        let ciImage = CIImage(cgImage: self)
        let upCIImage = ciImage.oriented(cgOrientation)
        let ciContext = CIContext()
        let upCGImage = ciContext.createCGImage(upCIImage, from: upCIImage.extent)
        
        guard let upCGImage else { assertionFailure(); return nil }
        
        return upCGImage
        
    }

}
