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

class OverlayWindow: UIView {

    private var mainView: OverlayWindowView!
    
    override var canBecomeFirstResponder: Bool {
        return false
    }
    
    var maskLayerTopMargin: CGFloat? {
        didSet {
            mainView.maskLayerTopMargin = maskLayerTopMargin
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.layer.zPosition = CGFloat.greatestFiniteMagnitude - 1
        
        mainView = (Bundle.main.loadNibNamed(OverlayWindowView.nibName, owner: nil, options: nil)?.first! as! OverlayWindowView)
        mainView.translatesAutoresizingMaskIntoConstraints = false

        self.addSubview(mainView)
        self.pinAllSidesToSides(of: mainView)
        
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setHorizontalCenter(to center: CGFloat) {
        mainView.setHorizontalCenter(to: center)
    }
    
    func addView(_ view: UIView) {
        mainView.addView(view)
        self.setNeedsLayout()
    }
    
    func addAction(title: String, image: UIImage, _ callback: @escaping () -> Void) {
        mainView.addAction(title: title, image: image, callback: callback)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        
        guard let maskLayerTopMargin = self.maskLayerTopMargin else { return }
        
        let maskLayer = CAShapeLayer()
        maskLayer.frame = self.bounds
        var bounds = self.bounds
        bounds.origin = CGPoint(x: bounds.origin.x, y: bounds.origin.y + maskLayerTopMargin)
        maskLayer.path = UIBezierPath(rect: bounds).cgPath
        
        self.layer.mask = maskLayer
        
    }
    
}
