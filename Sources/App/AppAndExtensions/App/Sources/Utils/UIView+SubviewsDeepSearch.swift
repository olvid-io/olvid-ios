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

extension UIView {
    
    func deepSearchSubView<T>(ofClass subviewClass: T.Type) -> T? {
        for subview in self.subviews {
            if let appropriateSubview = subview as? T {
                return appropriateSubview
            } else {
                if let appropriateSubview = subview.deepSearchSubView(ofClass: subviewClass) {
                    return appropriateSubview
                }
            }
        }
        return nil
    }
 
    func deepSearchAllSubview<T>(ofClass subviewClass: T.Type) -> [T] {
        var subviews = [T]()
        for view in self.subviews {
            if let v = view as? T {
                subviews.append(v)
            }
            subviews.append(contentsOf: view.deepSearchAllSubview(ofClass: subviewClass))
        }
        return subviews
    }
    
}
