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


extension UIViewController: ObvCanShowHUD {
    
    func showHUD(type: ObvHUDType, completionHandler: (() -> Void)? = nil) {
        assert(Thread.isMainThread)

        hideHUD()
        
        let feedbackOnDisplay: Bool
        
        let hudView: ObvHUDView
        switch type {
        case .checkmark:
            hudView = ObvIconHUD()
            (hudView as? ObvIconHUD)?.icon = .checkmarkCircle
            feedbackOnDisplay = true
        case .xmark:
            hudView = ObvIconHUD()
            (hudView as? ObvIconHUD)?.icon = .xmarkCircle
            feedbackOnDisplay = true
        case .spinner:
            hudView = ObvLoadingHUD()
            feedbackOnDisplay = false
        case .progress(progress: let progress):
            hudView = ObvLoadingHUD()
            (hudView as? ObvLoadingHUD)?.progress = progress
            feedbackOnDisplay = false
        case .text(text: let text):
            hudView = ObvTextHUD()
            (hudView as? ObvTextHUD)?.text = text
            feedbackOnDisplay = false
        case .icon(systemIcon: let systemIcon, feedbackOnDisplay: let _feedbackOnDisplay):
            hudView = ObvIconHUD()
            (hudView as? ObvIconHUD)?.icon = systemIcon
            feedbackOnDisplay = _feedbackOnDisplay
        }

        hudView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
        hudView.alpha = 0
        view.addSubview(hudView)

        hudView.translatesAutoresizingMaskIntoConstraints = false
        hudView.widthAnchor.constraint(equalToConstant: 150).isActive = true
        hudView.heightAnchor.constraint(equalToConstant: 150).isActive = true
        hudView.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        hudView.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        
        let animator = UIViewPropertyAnimator(duration: 0.5, dampingRatio: 0.7)
        
        animator.addAnimations {
            hudView.alpha = 1
            hudView.transform = CGAffineTransform.identity
        }

        animator.addCompletion { (_) in
            completionHandler?()
        }
        
        animator.startAnimation()

        if feedbackOnDisplay {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
        
    }
    
    
    func hudIsShown() -> Bool {
        for subview in view.subviews {
            if subview is ObvHUDView {
                return true
            }
        }
        return false
    }
    
    private func findAllHUDs() -> [ObvHUDView] {
        assert(Thread.isMainThread)
        let huds = view.subviews.compactMap({ $0 as? ObvHUDView })
        return huds
    }

    
    func hideHUD() {
        let hudViews = findAllHUDs()
        guard !hudViews.isEmpty else { return }
        
        let animator = UIViewPropertyAnimator(duration: 0.5, dampingRatio: 0.7)
        
        for hudView in hudViews {
            
            animator.addAnimations {
                hudView.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
                hudView.alpha = 0
            }
            
            animator.addCompletion { (_) in
                hudView.removeFromSuperview()
            }
            
        }

        animator.startAnimation()
    }
    
}
