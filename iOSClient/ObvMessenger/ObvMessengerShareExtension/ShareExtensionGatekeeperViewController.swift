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

@objc(ShareExtensionGatekeeperViewController)
final class ShareExtensionGatekeeperViewController: UIViewController {

    private static var _localAuthenticationVC: LocalAuthenticationViewController?
    private static let _localAuthenticationVCQueue = DispatchQueue.init(label: "io.olvid.obvoperation.internal")
    var localAuthenticationVC: LocalAuthenticationViewController {
        ShareExtensionGatekeeperViewController._localAuthenticationVCQueue.sync {
            if let _localAuthenticationVC = ShareExtensionGatekeeperViewController._localAuthenticationVC {
                return _localAuthenticationVC
            }
            let vc = LocalAuthenticationViewController()
            vc.usedByShareExtension = true
            ShareExtensionGatekeeperViewController._localAuthenticationVC = vc
            return vc
        }
    }
    
    private var mainShareVC: MainShareViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if ObvMessengerSettings.Privacy.lockScreen {
            localAuthenticationVC.delegate = self
            self.displayContentController(content: localAuthenticationVC)
        } else {
            mainShareVC = MainShareViewController()
            mainShareVC!.parentExtensionContext = self.extensionContext!
            mainShareVC!.delegate = self
            self.displayContentController(content: mainShareVC!)
        }
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // If we are displaying the LocalAuthenticationViewController, we try to authenticate automatically
        (children.first as? LocalAuthenticationViewController)?.performLocalAuthentication()
        
    }

}


extension ShareExtensionGatekeeperViewController: LocalAuthenticationViewControllerDelegate {
    
    func userWillTryToAuthenticate() {}
    func userDidTryToAuthenticated() {}
    
    func userLocalAuthenticationDidSucceedOrWasNotRequired() {
        assert(Thread.isMainThread)
        
        guard mainShareVC == nil else { return }
        
        mainShareVC = MainShareViewController()
        mainShareVC!.parentExtensionContext = self.extensionContext!
        mainShareVC!.delegate = self
        
        mainShareVC!.view.alpha = 0
        displayContentController(content: mainShareVC!)
        
        UIView.animate(withDuration: 0.3, animations: { [weak self] in
            self?.mainShareVC!.view.alpha = 1
        }, completion: { [weak self] (_) in
            guard let _self = self else { return }
            _self.dismissContentController(content: _self.localAuthenticationVC)
        })
        
    }
    
}


extension ShareExtensionGatekeeperViewController: MainShareViewControllerDelegate {
    
    func animateOutAndExit() {
        ObvMessengerInternalNotification.shareExtensionExtensionContextWillCompleteRequest
            .postOnDispatchQueue()
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
    
}
