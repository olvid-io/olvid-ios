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


/// This view is typically used as a "background" view in the message cells, e.g., behind the body of a message.
/// In order to display smooth rounded corners, we do not "simply" apply a corner radius but create a mask layer
/// from a rounded rectangle.
final class BubbleView: ViewForOlvidStack {

    private let largeCornerRadius: CGFloat
    private let smallCornerRadius: CGFloat
    private let neverRoundedCorners: UIRectCorner
    
    init(smallCornerRadius: CGFloat = MessageCellConstants.BubbleView.smallCornerRadius, largeCornerRadius: CGFloat = MessageCellConstants.BubbleView.largeCornerRadius, neverRoundedCorners: UIRectCorner = []) {
        self.smallCornerRadius = max(0, smallCornerRadius)
        self.largeCornerRadius = max(0, largeCornerRadius)
        self.neverRoundedCorners = neverRoundedCorners
        super.init(frame: .zero)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    

    var maskedCorner = UIRectCorner.allCorners {
        didSet {
            if oldValue != maskedCorner {
                maskCorners(in: bounds)
            }
        }
    }
    
    
    private lazy var maskLayer: CAShapeLayer = {
        self.layer.mask = $0
        return $0
    }(CAShapeLayer())

    
    override var bounds: CGRect {
        get { return super.bounds }
        set {
            super.bounds = newValue
            maskCorners(in: newValue)
        }
    }
    
    // Attribute to get precise path for corner
    private func layerPath(in bounds: CGRect) -> UIBezierPath {
        let maxX = bounds.maxX
        let maxY = bounds.maxY

        let topLeftRadius = neverRoundedCorners.contains(.topLeft) ? 0.0 : maskedCorner.contains(.topLeft) ? largeCornerRadius : smallCornerRadius
        let topRightRadius = neverRoundedCorners.contains(.topRight) ? 0.0 : maskedCorner.contains(.topRight) ? largeCornerRadius : smallCornerRadius
        let bottomRightRadius = neverRoundedCorners.contains(.bottomRight) ? 0.0 : maskedCorner.contains(.bottomRight) ? largeCornerRadius : smallCornerRadius
        let bottomLeftRadius = neverRoundedCorners.contains(.bottomLeft) ? 0.0 : maskedCorner.contains(.bottomLeft) ? largeCornerRadius : smallCornerRadius
        
        let path = UIBezierPath()
        path.move(to: CGPoint(x: topLeftRadius, y: 0))
        path.addLine(to: CGPoint(x: maxX - topRightRadius, y: 0))
        path.addArc(withCenter: CGPoint(x: maxX - topRightRadius, y: topRightRadius), radius: topRightRadius, startAngle: 3*CGFloat.pi/2, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: maxX, y: maxY - bottomRightRadius))
        path.addArc(withCenter: CGPoint(x: maxX - bottomRightRadius, y: maxY - bottomRightRadius), radius: bottomRightRadius, startAngle: 0, endAngle: CGFloat.pi/2, clockwise: true)
        path.addLine(to: CGPoint(x: bottomLeftRadius, y: maxY))
        path.addArc(withCenter: CGPoint(x: bottomLeftRadius, y: maxY - bottomLeftRadius), radius: bottomLeftRadius, startAngle: CGFloat.pi/2, endAngle: CGFloat.pi, clockwise: true)
        path.addLine(to: CGPoint(x: 0, y: topLeftRadius))
        path.addArc(withCenter: CGPoint(x: topLeftRadius, y: topLeftRadius), radius: topLeftRadius, startAngle: CGFloat.pi, endAngle: 3 * CGFloat.pi/2, clockwise: true)
        path.close()
        
        return path
    }
    
    private func maskCorners(in bounds: CGRect) {
        maskLayer.frame = bounds

        let path = layerPath(in: bounds)

        // If the bounds change is animated, copy the animation to mimic the timings
        if let animation = self.layer.animation(forKey: "bounds.size")?.copy() as? CABasicAnimation {
            animation.keyPath = "path"
            animation.fromValue = maskLayer.path
            animation.toValue = path
            maskLayer.path = path.cgPath
            maskLayer.add(animation, forKey: "path")
        } else {
            maskLayer.path = path.cgPath
        }
    }

}
