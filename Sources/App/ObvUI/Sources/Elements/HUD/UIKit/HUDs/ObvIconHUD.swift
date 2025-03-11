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
import ObvSystemIcon


final class ObvIconHUD: ObvHUDView {

    var icon: SystemIcon? {
        didSet {
            if let icon {
                imageView.image = UIImage(systemName: icon.name)
            } else {
                imageView.image = nil
            }
            self.setNeedsLayout()
        }
    }

    let imageView = UIImageView(image: nil)
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        if imageView.superview == nil {

            addSubview(imageView)            
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit
            imageView.tintColor = .secondaryLabel
            
            let constraints = [
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                imageView.widthAnchor.constraint(equalTo: self.widthAnchor, multiplier: 0.8),
                imageView.heightAnchor.constraint(equalTo: self.heightAnchor, multiplier: 0.8),
            ]
            NSLayoutConstraint.activate(constraints)
            
        }
    }
    
}
