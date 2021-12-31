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

class TextFieldBackgroundView: UIView {

    private let cornerRadius: CGFloat = 9.5
    private var shapeLayer: CAShapeLayer!
    
    var fillColor: UIColor = AppTheme.shared.colorScheme.secondarySystemBackground
    var strokeColor: UIColor = AppTheme.shared.colorScheme.secondarySystemBackground
    
    override func layoutSubviews() {
        super.layoutSubviews()

        shapeLayer?.removeFromSuperlayer()
        shapeLayer = CAShapeLayer()
        shapeLayer.fillColor = self.fillColor.cgColor
        shapeLayer.strokeColor = self.strokeColor.cgColor
        shapeLayer.lineWidth = 1.0
        if #available(iOS 12, *) {
            shapeLayer.path = CGPath(roundedRect: self.bounds,
                                     cornerWidth: 2*cornerRadius,
                                     cornerHeight: 2*cornerRadius,
                                     transform: nil)
        } else {
            // Prevent a crash due to an assertion in CoreGraphics/Paths/CGPath.cc that checks that (corner_height >= 0 && 2 * corner_height <= CGRectGetHeight(rect))
            shapeLayer.path = CGPath(roundedRect: self.bounds,
                                     cornerWidth: min(2*cornerRadius, self.bounds.width),
                                     cornerHeight: min(2*cornerRadius, self.bounds.height),
                                     transform: nil)
        }
        self.layer.addSublayer(shapeLayer)
        
    }

}
