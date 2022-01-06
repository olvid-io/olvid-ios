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

class ObvCardCollectionViewCell: UICollectionViewCell {

    static let cornerRadius: CGFloat = 8.0
    
    override func layoutSubviews() {
        super.layoutSubviews()

        layer.cornerRadius = ObvCardCollectionViewCell.cornerRadius

        let shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: ObvCardCollectionViewCell.cornerRadius)
        layer.masksToBounds = false
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 1.0
        layer.shadowOffset = CGSize(width: 0.0, height: 1.0)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowPath = shadowPath.cgPath
    }
    
}
