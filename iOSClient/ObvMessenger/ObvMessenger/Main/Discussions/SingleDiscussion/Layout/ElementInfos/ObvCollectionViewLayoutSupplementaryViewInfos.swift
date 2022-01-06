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

struct ObvCollectionViewLayoutSupplementaryViewInfos {
    
    let frameInSection: CGRect
    
    /// Return the frame of the item in the collection view
    ///
    /// - Parameter sectionInfos: The section infos of the section containing this item
    /// - Returns: The frame of this item in the collection view
    func getFrame(using sectionInfos: ObvCollectionViewLayoutSectionInfos) -> CGRect {
        let origin = CGPoint(x: sectionInfos.frame.origin.x + frameInSection.origin.x,
                             y: sectionInfos.frame.origin.y + frameInSection.origin.y)
        let size = frameInSection.size
        let frame = CGRect(origin: origin, size: size)
        return frame
    }
    
}
