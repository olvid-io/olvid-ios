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

import ObvUI
import UIKit
import ObvDesignSystem


final class ObvTextField: UITextField {
    
    let lineWidth: CGFloat = 2.0
    let lineBottomInset: CGFloat = 5.0 // Must be larger than lineWidth
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)

        let path = UIBezierPath()
        path.lineWidth = lineWidth
        path.move(to: CGPoint(x: 0, y: bounds.height - lineWidth))
        path.addLine(to: CGPoint(x: bounds.width, y: bounds.height - lineWidth))
        layer.masksToBounds = false
        AppTheme.shared.colorScheme.secondary.setStroke()
        path.stroke()
    }
    
    override func textRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.inset(by: UIEdgeInsets.init(top: 0, left: 0, bottom: lineBottomInset, right: 0))
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.inset(by: UIEdgeInsets.init(top: 0, left: 0, bottom: lineBottomInset, right: 0))
    }

    override func clearButtonRect(forBounds bounds: CGRect) -> CGRect {
        let originalRect = super.clearButtonRect(forBounds: bounds)
        let newOrigin = CGPoint(x: originalRect.origin.x, y: originalRect.origin.y - lineBottomInset/2)
        return CGRect(origin: newOrigin, size: originalRect.size)
    }
}
