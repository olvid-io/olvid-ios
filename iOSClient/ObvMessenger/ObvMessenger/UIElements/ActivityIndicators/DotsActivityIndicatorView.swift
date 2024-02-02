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


class DotsActivityIndicatorView: UIView, ActivityIndicator {

    private let padding: CGFloat = 0.0
    private var _isAnimating: Bool
    var isAnimating: Bool {
        return _isAnimating
    }
    
    override init(frame: CGRect) {
        self._isAnimating = false
        super.init(frame: frame)
        self.translatesAutoresizingMaskIntoConstraints = false
        isHidden = true
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    func startAnimating() {
        guard !isAnimating else { return }
        isHidden = false
        _isAnimating = true
        layer.speed = 1
        setUpAnimation()
    }
    
    
    func stopAnimating() {
        guard isAnimating else { return }
        isHidden = true
        _isAnimating = false
        layer.sublayers?.removeAll()
    }
    
    
    private final func setUpAnimation() {
        self.layoutIfNeeded()
        
        setUpAnimation(in: layer, color: AppTheme.shared.colorScheme.secondary)
    }
    
    
    func setUpAnimation(in layer: CALayer, color: UIColor) {
        let totalDuration: CFTimeInterval = 1.05
        let beginTime = CACurrentMediaTime()
        let beginTimes = [0, 0.2, 0.4]
        
        // Scale animation X
        let scaleAnimationX = CAKeyframeAnimation(keyPath: "transform.scale.x")
        scaleAnimationX.duration = 0.66
        scaleAnimationX.keyTimes = [0, 0.45, 0.9]
        scaleAnimationX.values = [1, 2, 1]

        // Scale animation Y
        let scaleAnimationY = CAKeyframeAnimation(keyPath: "transform.scale.y")
        scaleAnimationY.duration = 0.66
        scaleAnimationY.keyTimes = [0.1, 0.55, 1.0]
        scaleAnimationY.values = [1, 2, 1]

        // Animation
        let animation = CAAnimationGroup()
        
        animation.animations = [scaleAnimationX, scaleAnimationY]
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = totalDuration
        animation.repeatCount = HUGE
        animation.isRemovedOnCompletion = false
        
        // Draw balls
        for i in 0 ..< 3 {
            let size = CGSize(width: layer.bounds.size.width / 7, height: layer.bounds.size.height / 7)
            let circle = NVActivityIndicatorShape.circle.layerWith(size: size, color: color)
            let frame = CGRect(x: 0.5*size.width + 2.5*CGFloat(i)*size.width,
                               y: (layer.bounds.size.height - size.height) / 2,
                               width: size.width,
                               height: size.height)
            
            animation.beginTime = beginTime + beginTimes[i]
            circle.frame = frame
            circle.opacity = 1.0
            circle.add(animation, forKey: "animation")
            layer.addSublayer(circle)
        }
    }

}
