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


final class ObvTextHUD: ObvHUDView {

    private let uiLabel = UILabel()
    
    var text: String? {
        get {
            return uiLabel.text
        }
        set {
            uiLabel.text = newValue?.trimmingCharacters(in: .whitespaces)
            uiLabel.numberOfLines = newValue?.components(separatedBy: .whitespaces).count ?? 1
            self.setNeedsLayout()
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        if uiLabel.superview == nil {
            addSubview(uiLabel)
            
            uiLabel.translatesAutoresizingMaskIntoConstraints = false
            uiLabel.textColor = appTheme.colorScheme.secondaryLabel
            uiLabel.backgroundColor = .clear
            uiLabel.font = UIFont.preferredFont(forTextStyle: .largeTitle)
            uiLabel.textAlignment = .center
            uiLabel.adjustsFontSizeToFitWidth = true
            
            let constraints = [
                uiLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
                uiLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                uiLabel.widthAnchor.constraint(equalTo: self.widthAnchor, multiplier: 0.8),
                uiLabel.heightAnchor.constraint(equalTo: self.heightAnchor, multiplier: 0.8),
            ]
            NSLayoutConstraint.activate(constraints)
            
        }
    }
    
}
