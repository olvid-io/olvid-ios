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

/// All custom `UINavigationController` implementing `ObvFlowController` leverage this class to animate the floating "Add a contact" button, available on iOS18+.
@MainActor
final class FloatingButtonAnimator: NSObject, UINavigationControllerDelegate {
    
    private weak var floatingButton: UIButton?
    
    init(floatingButton: UIButton? = nil) {
        super.init()
        self.floatingButton = floatingButton
    }
    
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        guard let floatingButton else { return }
        if navigationController.viewControllers.first == viewController {
            // Show the button
            if let transitionCoordinator = viewController.transitionCoordinator {
                if #available(iOS 17, *) {
                    let transitionDuration = transitionCoordinator.transitionDuration
                    UIView.animate(springDuration: transitionDuration, bounce: 0.25) {
                        floatingButton.transform = CGAffineTransform.identity
                    } completion: { _ in
                        floatingButton.transform = CGAffineTransform.identity
                    }
                } else {
                    transitionCoordinator.animate { _ in
                        floatingButton.transform = CGAffineTransform.identity
                    }
                }

            } else {
                floatingButton.transform = CGAffineTransform.identity
            }
        } else {
            // Hide the button
            if let transitionCoordinator = viewController.transitionCoordinator {
                transitionCoordinator.animate { _ in
                    floatingButton.transform = CGAffineTransform(scaleX: 0, y: 0)
                }
            } else {
                floatingButton.transform = CGAffineTransform(scaleX: 0, y: 0)
            }
        }
    }
        
}
