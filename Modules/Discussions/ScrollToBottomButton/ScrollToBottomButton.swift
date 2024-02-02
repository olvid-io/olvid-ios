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
import UI_SystemIcon
import UI_SystemIcon_UIKit
import Combine

/// A custom subclass of `UIButton` for a "scroll to bottom" button.
/// This button binds itself to a given instance of `UIScrollView`, a given [vertical] offset threshold (``verticalVisibilityThreshold``)
/// The button is conditionally enabled via ``isTrackingEnabled``, defaults to `false`
/// The button's visibility is animated. If ``isTrackingEnabled`` is set to `false`, the button is always hidden
///
/// - Remark: ``isTrackingEnabled`` has been used over `UIControl.isEnabled` for better clarity and the possibility to [easierly] use a Combine publisher
///
/// - Important: Thanks to 􀫊's love of easy designated initializers, the only designated initializer for this subclass of UIButton is ``init(observing:initialVerticalVisibilityThreshold:)``. Others are not marked as unavailable, but actually are.
public final class ScrollToBottomButton: UIButton {
    
    private enum Constants {
        static let size = CGSize(width: 48,
                                 height: 48)
    }

    /// The scroll view that this class hooks itself onto, done via KVO
    private let scrollView: UIScrollView

    /// The vertical offset to conditionally show ourself
    @Published
    public var verticalVisibilityThreshold: CGFloat

    /// Master control if the button is visible and tracking is enabled
    @Published
    public var isTrackingEnabled: Bool

    private weak var backgroundLayer: CAShapeLayer!

    private weak var highlightOverlayLayer: CAShapeLayer!

    private var disposables: Set<AnyCancellable>

    public override var isHighlighted: Bool {
        didSet {
            CATransaction.begin()

            CATransaction.setDisableActions(true)

            highlightOverlayLayer.isHidden = !isHighlighted

            CATransaction.commit()
        }
    }

    /// Designated initializer to setup this button and tracking
    /// - Parameters:
    ///   - scrollView: Which scroll view to track
    ///   - initialVerticalVisibilityThreshold: The initial threshold for the visibility of the button
    public init(observing scrollView: UIScrollView, initialVerticalVisibilityThreshold: CGFloat) {
        isTrackingEnabled = false

        self.scrollView = scrollView

        verticalVisibilityThreshold = initialVerticalVisibilityThreshold

        disposables = []

        super.init(frame: .zero)

        Publishers.CombineLatest3($isTrackingEnabled,
                                  scrollView.publisher(for: \.contentOffset, options: .new),
                                  $verticalVisibilityThreshold)
        .filter(\.0) // dont emit downstream if tracking isn't enabled
        .map { _, contentOffset, verticalVisibilityThreshold -> (CGFloat, CGFloat) in
            return (contentOffset.y, verticalVisibilityThreshold)
        }
        .map(>)
        .sink { [weak self] isHidden in
            guard let self else {
                return
            }

            self._updateVisibility(isHidden: isHidden)
        }
        .store(in: &disposables)

        _setupSubview()
    }

    @available(*, unavailable)
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func _setupSubview() {
        translatesAutoresizingMaskIntoConstraints = false

        backgroundColor = .clear

        isOpaque = false

        alpha = 0 // start hidden

        tintColor = .label

        setImage(.init(systemIcon: .arrowDown), for: .normal)

        addTarget(self, action: #selector(_scrollToBottomAction), for: .primaryActionTriggered)

        let circlePathBaseRect = CGRect(origin: .zero,
                                        size: Constants.size)

        isPointerInteractionEnabled = true
        
        pointerStyleProvider = { button, proposedEffect, proposedShape -> UIPointerStyle? in
            let targetedPreview = proposedEffect.preview
            
            let convertedRect = button.convert(circlePathBaseRect, to: targetedPreview.target.container)
            
            let bezier = UIBezierPath(ovalIn: convertedRect)
            
            return .init(effect: .highlight(targetedPreview),
                         shape: .path(bezier))
        }

        let circlePath = UIBezierPath(ovalIn: circlePathBaseRect)

        let highlightOverlayLayer: CAShapeLayer = {
            let layer = CAShapeLayer()

            layer.frame = bounds

            layer.path = circlePath.cgPath

            layer.fillColor = UIColor.systemFill.cgColor

            layer.strokeColor = UIColor.systemFill.cgColor

            layer.backgroundColor = UIColor.clear.cgColor

            layer.isOpaque = false

            layer.isHidden = true

            return layer
        }()

        let backgroundLayer: CAShapeLayer = {
            let layer = CAShapeLayer()

            layer.frame = bounds

            layer.path = circlePath.cgPath

            layer.fillColor = UIColor.systemBackground.cgColor

            layer.strokeColor = UIColor.systemBackground.cgColor

            layer.backgroundColor = UIColor.clear.cgColor

            layer.isOpaque = false

            layer.shadowPath = circlePath.cgPath

            layer.shadowColor = UIColor.label.withAlphaComponent(0.12).cgColor

            layer.shadowRadius = 16

            layer.shadowOpacity = 1

            layer.shadowOffset = .init(width: 0,
                                       height: 8)

            layer.zPosition = -1

            return layer
        }()

        layer.addSublayer(backgroundLayer)

        layer.addSublayer(highlightOverlayLayer)

        self.backgroundLayer = backgroundLayer

        self.highlightOverlayLayer = highlightOverlayLayer

        _setupConstraints()
    }

    private func _setupConstraints() {
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Constants.size.width),
            heightAnchor.constraint(equalToConstant: Constants.size.height)
        ])
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else {
            return
        }

        CATransaction.begin()

        CATransaction.setDisableActions(true)

        highlightOverlayLayer.fillColor = UIColor.systemFill.cgColor

        highlightOverlayLayer.strokeColor = UIColor.systemFill.cgColor

        highlightOverlayLayer.backgroundColor = UIColor.clear.cgColor

        backgroundLayer.fillColor = UIColor.systemBackground.cgColor

        backgroundLayer.strokeColor = UIColor.systemBackground.cgColor

        backgroundLayer.backgroundColor = UIColor.clear.cgColor

        backgroundLayer.shadowColor = UIColor.label.withAlphaComponent(0.12).cgColor

        CATransaction.commit()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()

        CATransaction.setDisableActions(true)

        backgroundLayer.frame = bounds

        highlightOverlayLayer.frame = bounds

        let path = UIBezierPath(ovalIn: .init(origin: .zero,
                                          size: Constants.size))

        backgroundLayer.path = path.cgPath

        backgroundLayer.shadowPath = path.cgPath

        highlightOverlayLayer.path = path.cgPath

        highlightOverlayLayer.shadowPath = path.cgPath

        CATransaction.commit()
    }

    @objc
    private func _scrollToBottomAction() {
        let verticalContentOffset = scrollView.contentSize.height - scrollView.frame.height - scrollView.adjustedContentInset.top + scrollView.adjustedContentInset.bottom

        scrollView.setContentOffset(.init(x: 0,
                                          y: verticalContentOffset),
                                    animated: true)
    }

    private func _updateVisibility(isHidden: Bool) {
        UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.2,
                                                       delay: 0) {
            if isHidden {
                self.alpha = 0
            } else {
                self.alpha = 1
            }
        }
    }
}
