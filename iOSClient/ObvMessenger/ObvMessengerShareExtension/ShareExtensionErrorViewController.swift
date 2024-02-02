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

import ObvUI
import UIKit
import ObvUICoreData
import ObvDesignSystem


protocol ShareExtensionErrorViewControllerDelegate: AnyObject {
    func cancelRequest()
}


final class ShareExtensionErrorViewController: UIViewController {

    enum ShareExtensionError {
        case shouldUpdateToLatestVersion
        case shouldLaunchTheApp
    }

    private let label = UILabel()
    private let okButton = UIButton(type: .custom)

    var reason: ShareExtensionError = .shouldLaunchTheApp
    weak var delegate: ShareExtensionErrorViewControllerDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemBackground

        view.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .label

        view.addSubview(okButton)
        okButton.translatesAutoresizingMaskIntoConstraints = false
        okButton.setTitle(CommonString.Word.Ok, for: .normal)
        okButton.layer.cornerRadius = 16
        okButton.layer.masksToBounds = true
        // okButton.contentEdgeInsets = UIEdgeInsets(top: 16, left: 32, bottom: 16, right: 32)
        okButton.backgroundColor = AppTheme.shared.colorScheme.olvidLight
        okButton.addTarget(self, action: #selector(okOlvidButtonTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
            okButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            okButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])

        switch reason {
        case .shouldUpdateToLatestVersion:
            label.text = NSLocalizedString("PLEASE_UPDATE_OLVID_FROM_MAIN_APP", comment: "")
        case .shouldLaunchTheApp:
            label.text = NSLocalizedString("PLEASE_LAUNCH_OLVID_FROM_MAIN_APP", comment: "")
        }
    }

    @objc func okOlvidButtonTapped() {
        delegate?.cancelRequest()
    }

}
