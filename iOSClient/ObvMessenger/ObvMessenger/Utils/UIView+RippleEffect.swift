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

extension UIView {
    
    func applyRippleEffect(withColor color: UIColor) {
        
        let animationDuration: TimeInterval = 0.4

        let effectRect = CGRect(x: self.bounds.width/2, y: self.bounds.height/2, width: 1, height: 1)
        let clipView = UIView(frame: self.bounds)
        clipView.clipsToBounds = true
        clipView.layer.cornerRadius = self.layer.cornerRadius
        let rippleView = RippleView(frame: effectRect, backgroundColor: color)
        self.insertSubview(clipView, at: 0)
        clipView.addSubview(rippleView)
        
        let maxLength = max(self.bounds.width, self.bounds.height)
        let scaleAnimation = { rippleView.transform = CGAffineTransform(scaleX: maxLength*2, y: maxLength*2) }
        let fadeAnimation = { rippleView.alpha = 0.0 }
        
        let animator1 = UIViewPropertyAnimator(duration: animationDuration, curve: .linear)
        let animator2 = UIViewPropertyAnimator(duration: animationDuration, curve: .linear)
        animator1.addAnimations(scaleAnimation)
        animator2.addAnimations(fadeAnimation)
        animator2.addCompletion { (_) in clipView.removeFromSuperview() }
        animator1.startAnimation()
        animator2.startAnimation(afterDelay: animationDuration/2)
        
    }
    
}


private final class RippleView: UIView {
    
    init(frame: CGRect, backgroundColor: UIColor) {
        super.init(frame: frame)
        self.backgroundColor = backgroundColor
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func draw(_ rect: CGRect) {
        let maskPath = UIBezierPath(roundedRect: self.bounds, cornerRadius: self.bounds.width / 2)
        let maskLayer = CAShapeLayer()
        maskLayer.path = maskPath.cgPath
        layer.mask = maskLayer
    }
}
