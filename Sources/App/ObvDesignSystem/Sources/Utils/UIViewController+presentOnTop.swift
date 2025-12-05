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


public extension UIViewController {
    
    func presentOnTop(_ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
        var presentingViewController = self
        while let presentedViewController = presentingViewController.presentedViewController, !presentedViewController.isBeingDismissed {
            presentingViewController = presentedViewController
        }
        presentingViewController.present(viewControllerToPresent, animated: animated, completion: completion)
    }
    
    
    func presentOnTopAndAwaitCompletion(_ viewControllerToPresent: UIViewController, animated: Bool) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.presentOnTop(viewControllerToPresent, animated: animated) {
                continuation.resume()
            }
        }
    }
    
    
    /// If `self` is presenting a stack of view controllers, this method calls `dismiss(animated flag: Bool, completion: (() -> Void)? = nil)`
    /// on the one at the top of the stack.
    func dismissTopPresentedViewController(animated: Bool, completion: (() -> Void)? = nil) {
        var presentedViewController: UIViewController? = self.presentedViewController
        while let vc = presentedViewController?.presentedViewController {
            presentedViewController = vc
        }
        guard let presentedViewController else { return }
        presentedViewController.dismiss(animated: animated, completion: completion)
    }
 
    
    func dismissTopPresentedViewControllerAndAwaitCompletion(animated: Bool) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.dismissTopPresentedViewController(animated: animated) {
                continuation.resume()
            }
        }
    }
    
}
