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


final class OverlayActionView: UIView {
    
    static let nibName = "OverlayActionView"
    
    private var callback: (() -> Void)?
    var isTopActionView = false
    var isBottomActionView = false

    @IBOutlet weak var label: UILabel!
    @IBOutlet weak var imageView: UIImageView!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        backgroundColor = .white
        label.textColor = appTheme.colorScheme.primary700
        label.backgroundColor = .clear
        imageView.tintColor = appTheme.colorScheme.primary700
        self.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }
    
    @objc func tapped() {
        
        let animator = UIViewPropertyAnimator(duration: 0.2, curve: .easeInOut) { [weak self] in
            self?.backgroundColor = .lightGray
        }
        animator.addCompletion { [weak self] (_) in
            self?.callback?()
        }
        animator.startAnimation()
    }
    
    func addAction(title: String, image: UIImage, callback: @escaping () -> Void) {
        self.label.text = title
        self.imageView.image = image
        self.callback = callback
    }
 
    override func layoutSubviews() {
        super.layoutSubviews()
        
        guard isTopActionView || isBottomActionView else { return }
        
        let path: UIBezierPath
        let cornerRadii = CGSize(width: ObvRoundedRectView.defaultCornerRadius, height: ObvRoundedRectView.defaultCornerRadius)
        if isTopActionView {
            path = UIBezierPath(roundedRect: self.bounds, byRoundingCorners: [.topLeft, .topRight], cornerRadii: cornerRadii)
        } else if isBottomActionView {
            path = UIBezierPath(roundedRect: self.bounds, byRoundingCorners: [.bottomLeft, .bottomRight], cornerRadii: cornerRadii)
        } else {
            return
        }
        let maskLayer = CAShapeLayer()
        maskLayer.frame = self.bounds
        maskLayer.path = path.cgPath
        self.layer.mask = maskLayer

    }
}
