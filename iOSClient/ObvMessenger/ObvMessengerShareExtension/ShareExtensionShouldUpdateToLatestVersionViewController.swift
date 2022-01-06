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


protocol ShareExtensionShouldUpdateToLatestVersionViewControllerDelegate: AnyObject {
    func animateOutAndExit()
}

final class ShareExtensionShouldUpdateToLatestVersionViewController: UIViewController {
    
    private let label = UILabel()
    private let okButton = UIButton(type: .custom)
    
    var delegate: ShareExtensionShouldUpdateToLatestVersionViewControllerDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        if #available(iOS 13, *) {
            view.backgroundColor = .systemBackground
        }
        
        view.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.preferredFont(forTextStyle: .headline)
        label.numberOfLines = 0
        label.textAlignment = .center
        if #available(iOS 13, *) {
            label.textColor = .label
        }

        view.addSubview(okButton)
        okButton.translatesAutoresizingMaskIntoConstraints = false
        okButton.setTitle(CommonString.Word.Ok, for: .normal)
        okButton.layer.cornerRadius = 16
        okButton.layer.masksToBounds = true
        okButton.contentEdgeInsets = UIEdgeInsets(top: 16, left: 32, bottom: 16, right: 32)
        if #available(iOS 13, *) {
            okButton.backgroundColor = AppTheme.shared.colorScheme.olvidLight
        }
        okButton.addTarget(self, action: #selector(okOlvidButtonTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
            
            okButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            okButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
        
        label.text = NSLocalizedString("PLEASE_UPDATE_OLVID_FROM_MAIN_APP", comment: "")
        
    }
    
    @objc func okOlvidButtonTapped() {
        delegate?.animateOutAndExit()
    }
    
}
