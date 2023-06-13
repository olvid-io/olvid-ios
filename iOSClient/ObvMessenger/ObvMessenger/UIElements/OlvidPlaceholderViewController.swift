/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import Platform_Base

internal final class OlvidPlaceholderViewController: UIViewController {
    private enum Constants {
        static let backgroundColor = UIColor.secondarySystemBackground
    }

    private let logoImageView = UIImageView(image: .init(named: "placeholder/logo"))..{
        $0.backgroundColor = Constants.backgroundColor

        $0.tintColor = .tertiarySystemFill

        $0.isOpaque = true

        $0.translatesAutoresizingMaskIntoConstraints = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.isOpaque = true

        view.backgroundColor = Constants.backgroundColor

        view.addSubview(logoImageView)

        _setupConstraints()
    }

    private func _setupConstraints() {
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
