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

class ObvRoundedButton: UIButton {

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    internal func setup() {
        self.setTitleColor(AppTheme.shared.colorScheme.secondaryLabel, for: .normal)
        self.setTitleColor(AppTheme.shared.colorScheme.quaternaryLabel, for: .disabled)
        layer.cornerRadius = frame.size.height / 2.0
        resetBackgroundColor()
        resetTintColor()
        self.tintColor = AppTheme.shared.colorScheme.secondaryLabel
        self.adjustsImageWhenHighlighted = false
    }

    
    override var isEnabled: Bool {
        get { return super.isEnabled }
        set { super.isEnabled = newValue; resetBackgroundColor(); resetTintColor() }
    }

    override var isSelected: Bool {
        get { return super.isSelected }
        set { super.isSelected = newValue; resetBackgroundColor(); resetTintColor() }
    }

    override var isHighlighted: Bool {
        get { return super.isHighlighted }
        set { super.isHighlighted = newValue; resetBackgroundColor(); resetTintColor() }
    }

    internal func resetBackgroundColor() {
        if !isEnabled {
            self.backgroundColor = AppTheme.shared.colorScheme.obvYellow
        } else {
            if isHighlighted || isSelected {
                self.backgroundColor = AppTheme.shared.colorScheme.obvYellow
            } else {
                self.backgroundColor = AppTheme.shared.colorScheme.obvYellow
            }
        }
    }

    internal func resetTintColor() {}

}
