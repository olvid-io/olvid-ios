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

class OwnedIdentityIsNotActiveViewController: UIViewController {

    @IBOutlet weak var explanationBodyLabel: UILabel!
    @IBOutlet weak var whatToDoLabel: UILabel!
    @IBOutlet weak var whatToDoBodyLabel: UILabel!
    @IBOutlet weak var reactivateButton: UIButton!
    
    private var notificationTokens = [NSObjectProtocol]()

    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationController?.navigationBar.prefersLargeTitles = true
        self.title = Strings.title
        let closeButton = UIBarButtonItem.forClosing(target: self, action: #selector(dismissPresentedViewController))
        self.navigationItem.setLeftBarButton(closeButton, animated: false)

        explanationBodyLabel.text = Strings.explanationBody
        whatToDoLabel.text = Strings.whatToDo
        whatToDoBodyLabel.text = Strings.whatToDoBody
        reactivateButton.setTitle(Strings.reactivateIdentity, for: .normal)
        
        // Always dismiss this view controller if the identity is reactivated
        notificationTokens.append(ObvMessengerCoreDataNotification.observeOwnedIdentityWasReactivated(queue: OperationQueue.main, block: { [weak self] (_) in
            self?.dismissPresentedViewController()
        }))
        
    }

    @objc private func dismissPresentedViewController() {
        self.navigationController?.dismiss(animated: true)
    }

    @IBAction func reactivateButtonTapped(_ sender: Any) {
        ObvPushNotificationManager.shared.doKickOtherDevicesOnNextRegister()
        ObvPushNotificationManager.shared.tryToRegisterToPushNotifications()
    }
    
}


// MARK: Localized Strings

extension OwnedIdentityIsNotActiveViewController {
    
    private struct Strings {
        static let title = NSLocalizedString("Oups...", comment: "Title displayed on the VC shown when an owned identity is deactivated")
        static let explanationBody = NSLocalizedString("Your identity is deactivated on this device since it is active on another device. This tipically happens when you restore a backup on a device: this deactivates your previous device.", comment: "Explanation shown on the VC shown when an owned identity is deactivated")
        static let whatToDo = NSLocalizedString("What can I do?", comment: "Subtitle shown on the VC shown when an owned identity is deactivated")
        static let whatToDoBody = NSLocalizedString("You can still access your old discussions on this device, but you cannot send nor receive new messages. If you want to do so, you can tap on Reactivate this device. Please note that this will deactivate your other device.", comment: "Body text shown on the VC shown when an owned identity is deactivated")
        static let reactivateIdentity = NSLocalizedString("Reactivate my identity on this device", comment: "Button title")
    }
    
}
