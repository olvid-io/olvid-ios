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

final class SentMessageInfosViewController: UIViewController {

    var sentMessage: PersistedMessageSent!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = Strings.title
        
        let closeButton = UIBarButtonItem.forClosing(target: self, action: #selector(dismissPresentedViewController))
        self.navigationItem.setLeftBarButton(closeButton, animated: false)
        
        // Configure sub view controllers
        
        guard let infoVC = SentMessageInfosHostingViewController(messageSent: sentMessage) else {
            assertionFailure()
            return
        }
        
        // Configure subviews
        
        infoVC.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(infoVC.view)

        infoVC.willMove(toParent: self)
        self.addChild(infoVC)
        
        // Configure constraints
        
        infoVC.view.sizeToFit()
        
        let constraints = [
            self.view.safeAreaLayoutGuide.topAnchor.constraint(equalTo: infoVC.view.topAnchor),
            self.view.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: infoVC.view.trailingAnchor),
            self.view.safeAreaLayoutGuide.leadingAnchor.constraint(equalTo: infoVC.view.leadingAnchor),
            self.view.bottomAnchor.constraint(equalTo: infoVC.view.bottomAnchor),
        ]
        NSLayoutConstraint.activate(constraints)
        
    }
    
    
    @objc
    private func dismissPresentedViewController() {

        if let presentationController = self.navigationController?.presentationController,
           let presentationControllerDelegate = presentationController.delegate {
            presentationControllerDelegate.presentationControllerWillDismiss?(presentationController)
            self.dismiss(animated: true) {
                presentationControllerDelegate.presentationControllerDidDismiss?(presentationController)
            }
        } else {
            self.dismiss(animated: true)
        }
        
    }

    struct Strings {
        static let title = NSLocalizedString("Message Info", comment: "Title of the screen displaying informations about a specific message within a discussion")
    }
}
