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
import ObvUICoreData

/// Protocol used on Mac Catalyst to interact to the reaction context menu
protocol CellMessageShortcutMenuDelegate: AnyObject {

    /// Get the UIMenu object for the corresponding cell
    @MainActor func getMenuForCellWithMessage(cell: CellWithMessage) -> UIMenu?
    
    /// Method to call in order to display reaction context view, centered above the view (i.e. a control like UIButton) that triggered the call
    @MainActor func showContextReactionView(for cell: CellWithMessage, on view: UIView)

}
