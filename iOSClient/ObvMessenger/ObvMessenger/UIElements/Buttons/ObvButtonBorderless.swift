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

class ObvButtonBorderless: ObvButton {
    
    internal override func setTitleColors() {
        self.setTitleColor(AppTheme.shared.colorScheme.secondaryLabel, for: .normal)
        self.setTitleColor(AppTheme.shared.colorScheme.tertiaryLabel, for: .highlighted)
        self.setTitleColor(AppTheme.shared.colorScheme.quaternaryLabel, for: .disabled)
    }

    internal override func resetColors() {
        self.tintColor = AppTheme.shared.colorScheme.secondary
        self.backgroundColor = .clear
        if isEnabled && (isHighlighted || isSelected) {
            self.backgroundColor = AppTheme.shared.colorScheme.secondarySystemFill
        }
    }

    internal override func resetShadowPath() {}

}
