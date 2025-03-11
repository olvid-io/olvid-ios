/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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

/// UIView subclass that auto-hides when user taps on it.
/// It makes it possible to hide the reactions context menu when user clicks outside of it.
final class HidableView: UIView {

    public var animateOnHide: Bool = true
    public var onCompletion: (() -> ())?
    public var executeOnAnimation: (() -> ())?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    func addBlurEffect(alpha: CGFloat) {
        guard subviews.first(where: { $0 is UIVisualEffectView }) == nil else { return }
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)
        blurEffectView.alpha = alpha
        blurEffectView.isUserInteractionEnabled = false
        blurEffectView.frame = self.bounds
        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.addSubview(blurEffectView)
    }

    
    func setBlurEffectAlpha(to alpha: CGFloat) {
        guard let visualEffectView = subviews.first(where: { $0 is UIVisualEffectView }) else { return }
        visualEffectView.alpha = alpha
    }
    
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            if touch.view == self {
                hide()
            }
        }
    }
    
    
    public func hide() {
        UIViewPropertyAnimator.runningPropertyAnimator(withDuration: animateOnHide ? 0.2 : 0.0, delay: 0) { [weak self] in
            self?.executeOnAnimation?()
            self?.alpha = 0.0
        } completion: { [weak self] _ in
            self?.removeFromSuperview()
            self?.onCompletion?()
        }
    }
}
