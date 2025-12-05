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

import Foundation
import SwiftUI

public class Toaster {
    
    // Because we are adding toat to the Key window, we do NOT want to add hostingController as a child because the parent controller is nil for the window.
    @MainActor
    public static func showToast(toast: Toast, onCancelTap: (() -> Void)? = nil) {
        
        guard let keyWindow = UIApplication.shared.firstKeyWindow else { return }
        
        let toastDuration = toast.duration
        let animationDuration: Double = 0.25
        
        var toastHostingVC: UIHostingController<ToastView>?
        
        let dismissToast: () -> Void = {
            UIView.animate(withDuration: animationDuration, animations: {
                toastHostingVC?.view.alpha = 0.0
            }, completion: { _ in
                toastHostingVC?.view.removeFromSuperview()
            })
        }
        
        let onTap: (() -> Void)?
        
        if let onCancelTap {
            onTap = {
                onCancelTap()
                dismissToast()
            }
        } else {
            onTap = nil
        }
        
        let toastView = ToastView(style: toast.style,
                                  message: toast.message,
                                  width:toast.width,
                                  onCancelTapped: onTap,
                                  onCloseTapped: {
            dismissToast()
        })
        
        toastHostingVC = UIHostingController(rootView: toastView)
        
        guard let toastHostingViewController = toastHostingVC else { return }
        
        toastHostingViewController.view.alpha = 0
        
        toastHostingViewController.view.backgroundColor = .clear
        
        toastHostingViewController.view.isUserInteractionEnabled = true
        
        toastHostingViewController.view.translatesAutoresizingMaskIntoConstraints = false
        
        keyWindow.addSubview(toastHostingViewController.view)
        
        var constraints: [NSLayoutConstraint] = [
            toastHostingViewController.view.topAnchor.constraint(equalTo: keyWindow.safeAreaLayoutGuide.topAnchor, constant: 16.0),
            toastHostingViewController.view.centerXAnchor.constraint(equalTo: keyWindow.centerXAnchor),
            toastHostingViewController.view.leadingAnchor.constraint(greaterThanOrEqualTo: keyWindow.safeAreaLayoutGuide.leadingAnchor, constant: 8.0),
            toastHostingViewController.view.trailingAnchor.constraint(lessThanOrEqualTo: keyWindow.safeAreaLayoutGuide.trailingAnchor, constant: -8.0)
        ]
        
        if toast.width != .infinity {
            constraints.append(toastHostingViewController.view.widthAnchor.constraint(equalToConstant: toast.width))
        }
        
        NSLayoutConstraint.activate(constraints)
        
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        UIView.animate(withDuration: animationDuration) {
            toastHostingViewController.view.alpha = 1.0
        }
        
        guard toastDuration > 0 else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + toastDuration + animationDuration) {
            if toastHostingVC != nil {
                dismissToast()
            }
        }
    }
    
}
