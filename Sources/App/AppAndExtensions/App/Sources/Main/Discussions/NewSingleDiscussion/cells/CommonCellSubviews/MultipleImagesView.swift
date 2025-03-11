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

@available(iOS 14.0, *)
final class MultipleImagesView: ViewForOlvidStack, ViewWithMaskedCorners, ViewWithExpirationIndicator, ViewShowingHardLinks, UIViewWithTappableStuff {
    
    private var currentConfigurations = [SingleImageView.Configuration]()
    
    
    func setConfiguration(_ newConfigurations: [SingleImageView.Configuration]) {
        guard self.currentConfigurations != newConfigurations else { return }
        self.currentConfigurations = newConfigurations
        refresh()
    }

    private var currentRefreshId = UUID()
    
    func getAllShownHardLink() -> [(hardlink: HardLinkToFyle, viewShowingHardLink: UIView)] {
        guard showInStack else { return [] }
        var hardlinks = [(hardlink: HardLinkToFyle, viewShowingHardLink: UIView)]()
        for view in mainStackView.arrangedSubviews {
            guard view.showInStack else { continue }
            if let pairOfImagesView = view as? HorizontalPairOfImagesView {
                for imageView in [pairOfImagesView.lImageView, pairOfImagesView.rImageView] {
                    if let hardlink = imageView.hardlink {
                        hardlinks.append((hardlink, imageView))
                    }
                }
            } else if let wideImageView = view as? UIImageViewForHardLinkForOlvidStack {
                if let hardlink = wideImageView.hardlink {
                    hardlinks.append((hardlink, wideImageView))
                }
            } else {
                assertionFailure()
            }
        }
        return hardlinks
    }

    private func refresh() {
        
        currentRefreshId = UUID()
        
        // Reset all existing image views and make sure there are enough views to handle all the urls
        prepareHorizontalPairOfImagesViews(count: currentConfigurations.count / 2)
        wideImageView.showInStack = (currentConfigurations.count & 1) == 1
        
        for (index, configuration) in currentConfigurations.enumerated() {
            if wideImageView.showInStack && index == currentConfigurations.count-1 {
                refreshWideImageView(withConfiguration: configuration)
            } else {
                refresh(atIndex: index, withConfiguration: configuration)
            }
        }

    }
    
    
    private func refreshWideImageView(withConfiguration configuration: SingleImageView.Configuration) {
  
        refresh(tapToReadView: wideTapToReadView,
                fyleProgressView: wideFyleProgressView,
                imageView: wideImageView.imageViewForHardLink,
                withConfiguration: configuration)

    }
    
    
    private func refresh(atIndex index: Int, withConfiguration configuration: SingleImageView.Configuration) {
        
        let row = index / 2
        
        guard row < mainStackView.arrangedSubviews.count else { assertionFailure(); return }
        guard let pairOfImageViews = mainStackView.arrangedSubviews[row] as? HorizontalPairOfImagesView else { assertionFailure(); return }
        
        let tapToReadView: TapToReadView
        let fyleProgressView: FyleProgressView
        let imageView: UIImageViewForHardLink
        if (index & 1) == 0 {
            tapToReadView = pairOfImageViews.lTapToReadView
            fyleProgressView = pairOfImageViews.lFyleProgressView
            imageView = pairOfImageViews.lImageView
        } else {
            tapToReadView = pairOfImageViews.rTapToReadView
            fyleProgressView = pairOfImageViews.rFyleProgressView
            imageView = pairOfImageViews.rImageView
        }

        refresh(tapToReadView: tapToReadView,
                fyleProgressView: fyleProgressView,
                imageView: imageView,
                withConfiguration: configuration)
        
    }
    
    
    private func refresh(tapToReadView: TapToReadView, fyleProgressView: FyleProgressView, imageView: UIImageViewForHardLink, withConfiguration configuration: SingleImageView.Configuration) {
        switch configuration {
        case .uploadableOrUploading(hardlink: let hardlink, thumbnail: let thumbnail, progress: let progress):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.uploadableOrUploading(progress: progress))
            tapToReadView.messageObjectID = nil
            if let hardlink = hardlink {
                imageView.setHardlink(newHardlink: hardlink, withImage: thumbnail)
            } else {
                imageView.reset()
            }
        case .downloadable(receivedJoinObjectID: let receivedJoinObjectID, progress: let progress, downsizedThumbnail: let downsizedThumbnail):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.downloadable(receivedJoinObjectID: receivedJoinObjectID, progress: progress))
            tapToReadView.messageObjectID = nil
            if let downsizedThumbnail = downsizedThumbnail {
                imageView.setDownsizedThumbnail(withImage: downsizedThumbnail)
            } else {
                imageView.reset()
            }
        case .downloadableSent(sentJoinObjectID: let sentJoinObjectID, progress: let progress, downsizedThumbnail: let downsizedThumbnail):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.downloadableSent(sentJoinObjectID: sentJoinObjectID, progress: progress))
            tapToReadView.messageObjectID = nil
            if let downsizedThumbnail = downsizedThumbnail {
                imageView.setDownsizedThumbnail(withImage: downsizedThumbnail)
            } else {
                imageView.reset()
            }
        case .downloading(receivedJoinObjectID: let receivedJoinObjectID, progress: let progress, downsizedThumbnail: let downsizedThumbnail):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.downloading(receivedJoinObjectID: receivedJoinObjectID, progress: progress))
            tapToReadView.messageObjectID = nil
            if let downsizedThumbnail = downsizedThumbnail {
                imageView.setDownsizedThumbnail(withImage: downsizedThumbnail)
            } else {
                imageView.reset()
            }
        case .downloadingSent(sentJoinObjectID: let sentJoinObjectID, progress: let progress, downsizedThumbnail: let downsizedThumbnail):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.downloadingSent(sentJoinObjectID: sentJoinObjectID, progress: progress))
            tapToReadView.messageObjectID = nil
            if let downsizedThumbnail = downsizedThumbnail {
                imageView.setDownsizedThumbnail(withImage: downsizedThumbnail)
            } else {
                imageView.reset()
            }
        case .completeButReadRequiresUserInteraction(messageObjectID: let messageObjectID):
            tapToReadView.isHidden = false
            fyleProgressView.setConfiguration(.complete)
            tapToReadView.messageObjectID = messageObjectID
            imageView.reset()
        case .complete(downsizedThumbnail: let downsizedThumbnail, hardlink: let hardlink, thumbnail: let thumbnail):
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.complete)
            tapToReadView.messageObjectID = nil
            if let hardlink = hardlink {
                imageView.setHardlink(newHardlink: hardlink, withImage: thumbnail ?? downsizedThumbnail)
            } else {
                imageView.reset()
            }
        case .cancelledByServer:
            tapToReadView.isHidden = true
            fyleProgressView.setConfiguration(.cancelled)
            tapToReadView.messageObjectID = nil
            imageView.reset()
        }
    }

    
    var maskedCorner: UIRectCorner {
        get { bubble.maskedCorner }
        set { bubble.maskedCorner = newValue }
    }

    
    private func prepareHorizontalPairOfImagesViews(count: Int) {
        // Make sure there are enough horizontal pair of images views
        let numberOfHorizontalPairOfImagesViewToAdd = max(0, count - horizontalPairOfImagesViews.count)
        for _ in 0..<numberOfHorizontalPairOfImagesViewToAdd {
            let view = HorizontalPairOfImagesView()
            view.lImageView.isUserInteractionEnabled = true
            view.rImageView.isUserInteractionEnabled = true
            mainStackView.insertArrangedSubview(view, at: 0)
        }
        
        for view in mainStackView.arrangedSubviews[0..<count] {
            assert(view is HorizontalPairOfImagesView)
            view.showInStack = true
        }
        
        for view in mainStackView.arrangedSubviews[count...] {
            view.showInStack = false
        }
        
    }
    

    private let bubble = BubbleView()
    static var smallImageSize: CGFloat { HorizontalPairOfImagesView.smallImageSize }
    static var wideImageWidth: CGFloat { 2*smallImageSize + spacing } // 2*120+1
    private static var spacing: CGFloat { HorizontalPairOfImagesView.spacing }
    private let mainStackView = OlvidVerticalStackView(gap: MultipleImagesView.spacing, side: .bothSides, debugName: "Multiple images main stack view", showInStack: true)
    private let wideImageView = UIImageViewForHardLinkForOlvidStack()
    private let wideTapToReadView = TapToReadView(showText: false)
    private let wideFyleProgressView = FyleProgressView()
    private var horizontalPairOfImagesViews: [HorizontalPairOfImagesView] {
        mainStackView.arrangedSubviews.compactMap({ $0 as? HorizontalPairOfImagesView })
    }
    let expirationIndicator = ExpirationIndicatorView()
    let expirationIndicatorSide: ExpirationIndicatorView.Side

    init(expirationIndicatorSide side: ExpirationIndicatorView.Side) {
        self.expirationIndicatorSide = side
        super.init(frame: .zero)
        setupInternalViews()
    }
    

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    func tappedStuff(tapGestureRecognizer: UITapGestureRecognizer, acceptTapOutsideBounds: Bool) -> TappedStuffForCell? {
        var viewsWithTappableStuff = [UIViewWithTappableStuff]()
        if wideImageView.showInStack {
            viewsWithTappableStuff += [wideFyleProgressView, wideTapToReadView, wideImageView].filter({ $0.isHidden == false })
        }
        viewsWithTappableStuff += horizontalPairOfImagesViews.filter({ $0.isHidden == false && $0.showInStack })
        let view = viewsWithTappableStuff.first(where: { $0.tappedStuff(tapGestureRecognizer: tapGestureRecognizer) != nil })
        return view?.tappedStuff(tapGestureRecognizer: tapGestureRecognizer)
    }

    
    private func setupInternalViews() {
                        
        addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        bubble.backgroundColor = nil

        addSubview(expirationIndicator)
        expirationIndicator.translatesAutoresizingMaskIntoConstraints = false

        bubble.addSubview(mainStackView)
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        
        mainStackView.addArrangedSubview(wideImageView)
        wideImageView.showInStack = false
        wideImageView.clipsToBounds = true
        wideImageView.contentMode = .scaleAspectFill
        wideImageView.backgroundColor = .systemFill

        wideImageView.addSubview(wideTapToReadView)
        wideTapToReadView.translatesAutoresizingMaskIntoConstraints = false
        wideImageView.isUserInteractionEnabled = true
        wideTapToReadView.tapToReadLabelTextColor = .label

        wideImageView.addSubview(wideFyleProgressView)
        wideFyleProgressView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            bubble.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            bubble.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: self.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            mainStackView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
            mainStackView.topAnchor.constraint(equalTo: bubble.topAnchor),
            mainStackView.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
            
            wideTapToReadView.centerXAnchor.constraint(equalTo: wideImageView.centerXAnchor),
            wideTapToReadView.centerYAnchor.constraint(equalTo: wideImageView.centerYAnchor),

            wideFyleProgressView.centerXAnchor.constraint(equalTo: wideImageView.centerXAnchor),
            wideFyleProgressView.centerYAnchor.constraint(equalTo: wideImageView.centerYAnchor),

        ])
        
        let sizeConstraints = [
            wideImageView.widthAnchor.constraint(equalToConstant: MultipleImagesView.wideImageWidth),
            wideImageView.heightAnchor.constraint(equalToConstant: MultipleImagesView.smallImageSize),
            wideTapToReadView.widthAnchor.constraint(equalToConstant: MultipleImagesView.wideImageWidth),
            wideTapToReadView.heightAnchor.constraint(equalToConstant: MultipleImagesView.smallImageSize),
        ]
        _ = sizeConstraints.map({ $0.priority -= 1 })
        NSLayoutConstraint.activate(sizeConstraints)
     
        // Contraints with small priorty allowing to prevent ambiguous contraints issues
        do {
            let widthConstraints = [
                mainStackView.widthAnchor.constraint(equalToConstant: 1),
                bubble.widthAnchor.constraint(equalToConstant: 1),
            ]
            widthConstraints.forEach({ $0.priority = .defaultLow })
            NSLayoutConstraint.activate(widthConstraints)
        }

        setupConstraintsForExpirationIndicator(gap: MessageCellConstants.gapBetweenExpirationViewAndBubble)

    }

}



@available(iOS 14.0, *)
fileprivate class HorizontalPairOfImagesView: ViewForOlvidStack, UIViewWithTappableStuff {
    
    fileprivate let lTapToReadView = TapToReadView(showText: false)
    fileprivate let rTapToReadView = TapToReadView(showText: false)
    fileprivate let lFyleProgressView = FyleProgressView()
    fileprivate let rFyleProgressView = FyleProgressView()
    fileprivate let lImageView = UIImageViewForHardLink()
    fileprivate let rImageView = UIImageViewForHardLink()
    fileprivate static let smallImageSize = CGFloat(120)
    fileprivate static let spacing = CGFloat(1)

    init() {
        super.init(frame: .zero)
        setupInternalViews()
    }
    

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    func tappedStuff(tapGestureRecognizer: UITapGestureRecognizer, acceptTapOutsideBounds: Bool) -> TappedStuffForCell? {
        let viewsWithTappableStuff = [lFyleProgressView, rFyleProgressView, lTapToReadView, rTapToReadView, lImageView, rImageView].filter({ $0.isHidden == false }) as [UIViewWithTappableStuff]
        let view = viewsWithTappableStuff.first(where: { $0.tappedStuff(tapGestureRecognizer: tapGestureRecognizer) != nil })
        let tappedStuff = view?.tappedStuff(tapGestureRecognizer: tapGestureRecognizer)
        return tappedStuff
    }

    
    private func setupInternalViews() {
        
        addSubview(lImageView)
        lImageView.translatesAutoresizingMaskIntoConstraints = false
        lImageView.clipsToBounds = true
        lImageView.backgroundColor = .systemFill
        lImageView.accessibilityLabel = "lImageView"
        
        addSubview(rImageView)
        rImageView.translatesAutoresizingMaskIntoConstraints = false
        rImageView.clipsToBounds = true
        rImageView.backgroundColor = .systemFill
        rImageView.accessibilityLabel = "rImageView"

        addSubview(lTapToReadView)
        lTapToReadView.translatesAutoresizingMaskIntoConstraints = false
        lTapToReadView.tapToReadLabelTextColor = .label

        addSubview(rTapToReadView)
        rTapToReadView.translatesAutoresizingMaskIntoConstraints = false
        rTapToReadView.tapToReadLabelTextColor = .label
        
        addSubview(lFyleProgressView)
        lFyleProgressView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(rFyleProgressView)
        rFyleProgressView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            
            lImageView.topAnchor.constraint(equalTo: self.topAnchor),
            lImageView.trailingAnchor.constraint(equalTo: rImageView.leadingAnchor, constant: -HorizontalPairOfImagesView.spacing),
            lImageView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            lImageView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            
            rImageView.topAnchor.constraint(equalTo: self.topAnchor),
            rImageView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            rImageView.bottomAnchor.constraint(equalTo: self.bottomAnchor),

            lTapToReadView.centerXAnchor.constraint(equalTo: lImageView.centerXAnchor),
            lTapToReadView.centerYAnchor.constraint(equalTo: lImageView.centerYAnchor),

            rTapToReadView.centerXAnchor.constraint(equalTo: rImageView.centerXAnchor),
            rTapToReadView.centerYAnchor.constraint(equalTo: rImageView.centerYAnchor),

            lFyleProgressView.centerXAnchor.constraint(equalTo: lImageView.centerXAnchor),
            lFyleProgressView.centerYAnchor.constraint(equalTo: lImageView.centerYAnchor),

            rFyleProgressView.centerXAnchor.constraint(equalTo: rImageView.centerXAnchor),
            rFyleProgressView.centerYAnchor.constraint(equalTo: rImageView.centerYAnchor),

        ])

        let smallImageSize = HorizontalPairOfImagesView.smallImageSize
        let sizeConstraints = [
            lImageView.widthAnchor.constraint(equalToConstant: smallImageSize),
            lImageView.heightAnchor.constraint(equalToConstant: smallImageSize),
            rImageView.widthAnchor.constraint(equalToConstant: smallImageSize),
            rImageView.heightAnchor.constraint(equalToConstant: smallImageSize),
            
            lTapToReadView.widthAnchor.constraint(equalToConstant: smallImageSize),
            lTapToReadView.heightAnchor.constraint(equalToConstant: smallImageSize),
            rTapToReadView.widthAnchor.constraint(equalToConstant: smallImageSize),
            rTapToReadView.heightAnchor.constraint(equalToConstant: smallImageSize),
        ]
        _ = sizeConstraints.map({ $0.priority -= 1 })
        NSLayoutConstraint.activate(sizeConstraints)

    }
    
}
