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


@available(iOS 13, *)
final class ObvCheckmarkHUD: ObvHUDView {
        
    let checkmarkView = UIImageView(image: UIImage(systemName: "checkmark.circle"))
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        if checkmarkView.superview == nil {
            addSubview(checkmarkView)
            
            checkmarkView.translatesAutoresizingMaskIntoConstraints = false
            checkmarkView.contentMode = .scaleAspectFit
            checkmarkView.tintColor = appTheme.colorScheme.secondaryLabel
            
            let constraints = [
                checkmarkView.centerXAnchor.constraint(equalTo: centerXAnchor),
                checkmarkView.centerYAnchor.constraint(equalTo: centerYAnchor),
                checkmarkView.widthAnchor.constraint(equalTo: self.widthAnchor, multiplier: 0.8),
                checkmarkView.heightAnchor.constraint(equalTo: self.heightAnchor, multiplier: 0.8),
            ]
            NSLayoutConstraint.activate(constraints)
            
        }
    }
    
}
