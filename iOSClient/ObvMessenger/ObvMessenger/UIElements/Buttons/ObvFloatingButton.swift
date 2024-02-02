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


final class ObvFloatingButton: UIButton {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    private func setup() {
        self.setTitleColor(.white, for: .normal)
        self.setTitleColor(.white, for: .disabled)
        self.backgroundColor = .clear
        resetShadowPath()
        self.tintColor = .white
        // self.adjustsImageWhenHighlighted = false
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        let circle = UIBezierPath(ovalIn: self.bounds)
        AppTheme.shared.colorScheme.secondary.setFill()
        circle.fill()
    }
    
    override var isEnabled: Bool {
        get {
            return super.isEnabled
        }
        set {
            super.isEnabled = newValue
            resetShadowPath()
            resetTintColor()
        }
    }

    override var isSelected: Bool {
        get {
            return super.isSelected
        }
        set {
            super.isSelected = newValue
            resetShadowPath()
            resetTintColor()
        }
    }
    
    override var isHighlighted: Bool {
        get {
            return super.isHighlighted
        }
        set {
            super.isHighlighted = newValue
            resetShadowPath()
            resetTintColor()
        }
    }
    
    private func resetShadowPath() {

        let shadowPath = UIBezierPath(ovalIn: self.bounds)
        self.layer.masksToBounds = false
        self.layer.shadowColor = UIColor.black.cgColor
        self.layer.shadowPath = shadowPath.cgPath
        layer.shadowOpacity = 0.3

        if state == .highlighted || state == .selected {
            layer.shadowRadius = 3.0
            layer.shadowOffset = CGSize(width: 0.0, height: 3.0)
        } else { // Normal
            layer.shadowRadius = 5.0
            layer.shadowOffset = CGSize(width: 0.0, height: 7.0)
        }
        
    }
    
    private func resetTintColor() {
        if !isEnabled {
            self.tintColor = .white
        } else {
            if isHighlighted || isSelected {
                self.tintColor = .white
            } else {
                self.tintColor = .white
            }
        }
    }

}
