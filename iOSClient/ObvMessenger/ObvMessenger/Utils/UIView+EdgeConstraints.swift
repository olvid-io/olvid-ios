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

extension UIView {
    
    func pinAllSidesToSides(of otherView: UIView) {
        
        let top = self.topAnchor.constraint(equalTo: otherView.topAnchor)
        let trailing = self.trailingAnchor.constraint(equalTo: otherView.trailingAnchor)
        let bottom = self.bottomAnchor.constraint(equalTo: otherView.bottomAnchor)
        let leading = self.leadingAnchor.constraint(equalTo: otherView.leadingAnchor)
        
        _ = [top, trailing, bottom, leading].map { $0.isActive = true }
        
    }
    
    
    func pinAllSidesToSides(of otherView: UIView, sideConstants: CGFloat) {
        
        let top = self.topAnchor.constraint(equalTo: otherView.topAnchor)
        let trailing = self.trailingAnchor.constraint(equalTo: otherView.trailingAnchor, constant: sideConstants)
        let bottom = self.bottomAnchor.constraint(equalTo: otherView.bottomAnchor)
        let leading = self.leadingAnchor.constraint(equalTo: otherView.leadingAnchor, constant: -sideConstants)
        
        _ = [top, trailing, bottom, leading].map { $0.isActive = true }
        
    }
}
