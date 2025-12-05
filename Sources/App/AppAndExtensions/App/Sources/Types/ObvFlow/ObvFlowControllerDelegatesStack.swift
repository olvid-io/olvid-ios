/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OlvidUtils


/// A stack of delegates for `UINavigationController` instances conforming to `ObvFlowController` (e.g., `DiscussionsFlowViewController`).
/// This allows multiple objects to subscribe to `UINavigationControllerDelegate` callbacks.
///
/// Originally, this was mandatory to support two delegates:
/// - `OlvidUserActivitySingleton` (now managed at the `MainFlowViewController` and `ObvFlowController` levels since version 4.0)
/// - `FloatingButtonAnimator` (used to animate the floating button during push/pop transitions on iOS 18+)
///
/// **Note:**
/// The `FloatingButtonAnimator`  will likely be removed in future versions as Olvid transitions to a full SwiftUI architecture.
/// This stack is retained for now.
@MainActor
final class ObvFlowControllerDelegatesStack: NSObject, UINavigationControllerDelegate {
    
    private var delegates = [Weak<UINavigationControllerDelegate>]()
    
    func addDelegate(_ newDelegate: UINavigationControllerDelegate) {
        self.delegates.append(.init(newDelegate))
    }
    
    // UINavigationController: Responding to a view controller being shown
    
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        delegates.forEach { delegate in
            delegate.value?.navigationController?(navigationController, willShow: viewController, animated: animated)
        }
    }
    
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        delegates.forEach { delegate in
            delegate.value?.navigationController?(navigationController, didShow: viewController, animated: animated)
        }
    }
    
    // UINavigationController: Supporting custom transition animations

    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation, from fromVC: UIViewController, to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        return delegates.first?.value?.navigationController?(navigationController, animationControllerFor: operation, from: fromVC, to: toVC)
    }
    
    func navigationController(_ navigationController: UINavigationController, interactionControllerFor animationController: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)? {
        return delegates.first?.value?.navigationController?(navigationController, interactionControllerFor: animationController)
    }
        
}
