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

/// Internal subclass belonging to the `Discussions_AttachmentsDropView` module; do not use me
final class _AttachmentsTargetDropZoneView: UIView {
    
    private enum Constants {
        static let marchingAntsAnimationKey = "io.olvid.messenger.discussions.attachemnts-drop-view-private.attachements-target-drop-zone-view.marching-ants-animation-key"

        static let lineDashPattern: [CGFloat] = [6, 8]
    }

    private weak var marchingAntsLayer: CAShapeLayer!

    private weak var stackView: UIStackView!

    private weak var dropImageView: UIImageView!

    private weak var dropLabel: UILabel!

    override init(frame: CGRect) {
        super.init(frame: frame)

        _setupViews()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func _createShape() -> CGPath {
        let bezier = UIBezierPath(roundedRect: bounds,
                                  cornerRadius: 20)

        return bezier.cgPath
    }

    private func _setupViews() {
        let marchingAntsLayer = CAShapeLayer()

        marchingAntsLayer.path = _createShape()

        marchingAntsLayer.lineWidth = 3

        marchingAntsLayer.frame = bounds

        marchingAntsLayer.backgroundColor = UIColor.clear.cgColor

        marchingAntsLayer.fillColor = UIColor.secondarySystemBackground.withAlphaComponent(0.7).cgColor

        marchingAntsLayer.strokeColor = UIColor.secondaryLabel.cgColor

        marchingAntsLayer.lineDashPhase = 0

        marchingAntsLayer.lineDashPattern = Constants.lineDashPattern as [NSNumber]

        let textStyle: UIFont.TextStyle = .headline

        let dropImageView = UIImageView(image: .init(systemIcon: .rectangleDashedAndPaperclip))

        dropImageView.isAccessibilityElement = false

        dropImageView.preferredSymbolConfiguration = .init(textStyle: textStyle, scale: .large)

        dropImageView.tintColor = .secondaryLabel

        dropImageView.translatesAutoresizingMaskIntoConstraints = false

        let dropLabel = UILabel()

        dropLabel.adjustsFontForContentSizeCategory = true

        dropLabel.font = UIFont.preferredFont(forTextStyle: textStyle)

        dropLabel.textColor = .secondaryLabel

        dropLabel.text = DiscussionsAttachmentsDropViewStrings.AttachmentsTargetDropZoneView.DropLabel.text

        dropLabel.textAlignment = .center

        dropLabel.translatesAutoresizingMaskIntoConstraints = false

        let stackView = UIStackView(arrangedSubviews: [dropImageView, dropLabel])

        stackView.spacing = UIStackView.spacingUseSystem

        stackView.axis = .vertical

        stackView.alignment = .center

        stackView.distribution = .fill

        stackView.translatesAutoresizingMaskIntoConstraints = false

        backgroundColor = .clear

        layer.addSublayer(marchingAntsLayer)

        addSubview(stackView)

        self.marchingAntsLayer = marchingAntsLayer

        self.stackView = stackView

        self.dropImageView = dropImageView

        self.dropLabel = dropLabel

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()

        CATransaction.setDisableActions(true)

        marchingAntsLayer.frame = bounds

        marchingAntsLayer.path = _createShape()

        CATransaction.commit()
    }

    func startMarchingAntsAnimation() {
        guard marchingAntsLayer.animation(forKey: Constants.marchingAntsAnimationKey) == nil else {
            return
        }

        let animation = CABasicAnimation(keyPath: #keyPath(CAShapeLayer.lineDashPhase))

        animation.fromValue = 0

        animation.toValue = Constants.lineDashPattern.reduce(0, -)

        animation.duration = 0.5

        animation.repeatCount = .infinity

        marchingAntsLayer.add(animation, forKey: Constants.marchingAntsAnimationKey)
    }

    func stopMarchingAntsAnimation() {
        marchingAntsLayer.removeAnimation(forKey: Constants.marchingAntsAnimationKey)
    }
}
