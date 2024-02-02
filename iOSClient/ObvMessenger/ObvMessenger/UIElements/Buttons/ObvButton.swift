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


/// When setting this class within a storyboard, the type should be set to "custom"
/// This is an old class. See `ObvImageButton` instead.
class ObvButton: UIButton {
    
    internal let sidePadding: CGFloat = 16.0
    internal let topPadding: CGFloat = 8.0
    internal let cornerRadius: CGFloat = 4.0
    
    // API
    var preferredBackgroundColor: UIColor? {
        didSet {
            resetColors()
        }
    }
    
    var preferredTitleColor: UIColor? {
        didSet {
            setTitleColors()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    
    private func setup() {
        self.layer.cornerRadius = self.cornerRadius
        // self.contentEdgeInsets = UIEdgeInsets(top: topPadding, left: sidePadding, bottom: topPadding, right: sidePadding)
        setTitle(self.title(for: .normal), for: .normal)
        setTitleColors()
        resetColors()
        resetShadowPath()
    }

    
    override func title(for state: UIControl.State) -> String? {
        let title = super.title(for: state)
        return title?.uppercased()
    }
    
    
    override func setTitle(_ title: String?, for state: UIControl.State) {
        super.setTitle(title?.uppercased(), for: state)
    }
    
    
    override var isSelected: Bool {
        get { return super.isSelected }
        set { super.isSelected = newValue; resetColors(); resetShadowPath() }
    }
    
    
    override var isEnabled: Bool {
        get { return super.isEnabled }
        set { super.isEnabled = newValue; resetColors(); resetShadowPath() }
    }
    
    
    override var isHighlighted: Bool {
        get { return super.isHighlighted }
        set { super.isHighlighted = newValue; resetColors(); resetShadowPath() }
    }

    
    internal func setTitleColors() {
        self.setTitleColor(preferredTitleColor ?? .white, for: .highlighted)
        self.setTitleColor(preferredTitleColor ?? .white, for: .normal)
        self.setTitleColor(AppTheme.shared.colorScheme.quaternaryLabel, for: .disabled)
    }

    
    internal func resetColors() {
        if !isEnabled {
            self.backgroundColor = AppTheme.shared.colorScheme.tertiarySystemBackground
        } else {
            if isHighlighted || isSelected {
                self.tintColor = .black
                self.backgroundColor = preferredBackgroundColor ?? AppTheme.shared.colorScheme.obvYellow
            } else {
                self.backgroundColor = preferredBackgroundColor ?? AppTheme.shared.colorScheme.obvYellow
            }
        }
    }

    
    internal func resetShadowPath() {
        
        if !isEnabled {
            self.layer.shadowColor = UIColor.clear.cgColor
        } else {
            self.layer.masksToBounds = false
            self.layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.3
            
            if state == .highlighted || state == .selected {
                layer.shadowRadius = 2.0
                layer.shadowOffset = CGSize(width: 0.0, height: 0.5)
            } else { // Normal
                layer.shadowRadius = 4.0
                layer.shadowOffset = CGSize(width: 0.0, height: 2.0)
            }
        }
        
    }

}
