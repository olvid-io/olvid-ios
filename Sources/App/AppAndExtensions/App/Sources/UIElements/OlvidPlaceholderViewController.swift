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
import ObvPlatformBase

internal final class OlvidPlaceholderViewController: UIViewController {
    
    
    private enum Constants {
        static let backgroundColor = UIColor.secondarySystemBackground
    }

    
    private let logoImageView: UIImageView = {
        let imageView = UIImageView(image: .init(named: "placeholder/logo"))
        imageView.backgroundColor = Constants.backgroundColor
        imageView.tintColor = .tertiarySystemFill
        imageView.isOpaque = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.isOpaque = true
        view.backgroundColor = Constants.backgroundColor
        view.addSubview(logoImageView)
        setupConstraints()
        
        // We set the titleView to hide the navigation title (that we need to set to display a proper title for the button shown in the menu displayed when performing a long press on the back button of the discussion navigation stack)
        self.navigationItem.titleView = UIView()
        self.navigationItem.title = NSLocalizedString("DISMISS_ALL_DISCUSSIONS", comment: "Title of the menu button shown when performing a long press on the back button of the discussion navigation under macOS")
        
    }

    
    private func setupConstraints() {
        
        let viewsDictionary = ["logoImageView": logoImageView]

        NSLayoutConstraint.activate(NSLayoutConstraint.constraints(withVisualFormat: "H:|-(>=0)-[logoImageView]-(>=0)-|",
                                                                   options: [],
                                                                   metrics: nil,
                                                                   views: viewsDictionary))

        NSLayoutConstraint.activate(NSLayoutConstraint.constraints(withVisualFormat: "V:|-(>=0)-[logoImageView]-(>=0)-|",
                                                                   options: [],
                                                                   metrics: nil,
                                                                   views: viewsDictionary))

        NSLayoutConstraint(item: logoImageView,
                           attribute: .centerX,
                           relatedBy: .equal,
                           toItem: view,
                           attribute: .centerX,
                           multiplier: 1,
                           constant: 0).isActive = true

        NSLayoutConstraint(item: logoImageView,
                           attribute: .centerY,
                           relatedBy: .equal,
                           toItem: view,
                           attribute: .centerY,
                           multiplier: 1,
                           constant: 0).isActive = true
    }
    
}
