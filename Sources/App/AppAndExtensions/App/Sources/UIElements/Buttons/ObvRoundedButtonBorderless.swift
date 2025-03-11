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

import Foundation
import ObvUI
import ObvDesignSystem


final class ObvRoundedButtonBorderless: ObvRoundedButton {
    
    internal override func setup() {
        layer.cornerRadius = frame.size.height / 2.0
        resetBackgroundColor()
        // self.adjustsImageWhenHighlighted = false
    }

    
    internal override func resetBackgroundColor() {
        self.backgroundColor = .clear
        if isEnabled && (isHighlighted || isSelected) {
            self.backgroundColor = AppTheme.shared.colorScheme.buttonDisabled
        }
    }
    
    
    override func resetTintColor() {
        if !isEnabled {
            self.tintColor = AppTheme.shared.colorScheme.buttonDisabled
        } else {
            if isHighlighted || isSelected {
                self.tintColor = AppTheme.shared.colorScheme.secondaryLabel
            } else {
                self.tintColor = AppTheme.shared.colorScheme.tertiaryLabel
            }
        }
        
    }
    
}
