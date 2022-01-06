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

class ObvRoundedRectView: UIView {

    static let defaultCornerRadius: CGFloat = 8.0
    var cornerRadius: CGFloat = ObvRoundedRectView.defaultCornerRadius
    var withShadow = false
    var strokeColor: UIColor?
    private var strokeLayer: CAShapeLayer?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        layer.cornerRadius = cornerRadius
        
        if withShadow {
            let shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
            layer.masksToBounds = false
            layer.shadowOpacity = 0.1
            layer.shadowOffset = CGSize(width: 0.0, height: 1.0)
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowPath = shadowPath.cgPath
        }
        
        if let strokeColor = self.strokeColor {
            self.strokeLayer?.removeFromSuperlayer()
            self.strokeLayer = CAShapeLayer()
            let strokePath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius)
            self.strokeLayer!.fillColor = nil
            self.strokeLayer!.path = strokePath.cgPath
            self.strokeLayer!.strokeColor = strokeColor.cgColor
            self.strokeLayer!.lineWidth = 1
            layer.addSublayer(self.strokeLayer!)
        }
    }

}
