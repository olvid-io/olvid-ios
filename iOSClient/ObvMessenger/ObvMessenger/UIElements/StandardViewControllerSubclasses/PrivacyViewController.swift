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

final class PrivacyViewController: UIViewController {

    private let imageView = UIImageView()
    
    override func viewDidLoad() {
        super.viewDidLoad()
                
        
        imageView.contentMode = .scaleAspectFit
        let olvidLogo = UIImage(named: "AppIconForLaunch")
        imageView.image = olvidLogo
        
        self.view.backgroundColor = AppTheme.shared.colorScheme.primary900
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        self.view.addSubview(imageView)
        
        let constraints = [
            imageView.centerYAnchor.constraint(equalTo: self.view.centerYAnchor, constant: -150),
            imageView.leftAnchor.constraint(equalTo: self.view.leftAnchor, constant: 48),
            imageView.rightAnchor.constraint(equalTo: self.view.rightAnchor, constant: -48),
        ]
        NSLayoutConstraint.activate(constraints)
        

    }

}
