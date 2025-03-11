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
 *  but WITHOUT ANY WARRANTY without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation
import UIKit

protocol ExtractedContextMenuViews {
    
    // Root view containing all the native menu views.
    var windowRootView: UIView? { get }
    
    // Root view containing the menu preview views
    var previewRootView: UIView? { get }
    
    // View containing both the menu preview main view and the list items main view
    var sharedRootView: UIView? { get }
    
    // View containing the list items views.
    var listRootView: UIView? { get }
    
    // View used to draw shadow
    var shadowView: UIView? { get }
}


extension ExtractedContextMenuViews {
    
    var hasMenuItems: Bool {
        self.listRootView != nil
    }
}

