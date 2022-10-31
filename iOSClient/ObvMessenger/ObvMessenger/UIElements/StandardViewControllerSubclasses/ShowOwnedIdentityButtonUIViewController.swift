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
import ObvEngine
import os.log
import ObvTypes

class ShowOwnedIdentityButtonUIViewController: UIViewController {
    
    let ownedCryptoId: ObvCryptoId
    let log: OSLog
    private let titleLabel = UILabel()

    private var viewDidLoadWasCalled = false
    private var barButtonItemToShowInsteadOfOwnedIdentityButton: UIBarButtonItem? = nil
    
    init(ownedCryptoId: ObvCryptoId, logCategory: String) {
        self.ownedCryptoId = ownedCryptoId
        self.log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: logCategory)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setTitle(_ title: String?) {
        self.titleLabel.text = title
        self.navigationItem.title = title
    }
    
    func replaceOwnedIdentityButton(byIcon icon: ObvSystemIcon, target: Any, action: Selector) {
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let image = UIImage(systemIcon: icon, withConfiguration: symbolConfiguration)
        let barButtonItem = UIBarButtonItem(image: image, style: .plain, target: target, action: action)
        barButtonItem.tintColor = AppTheme.shared.colorScheme.olvidLight
        barButtonItemToShowInsteadOfOwnedIdentityButton = barButtonItem
        if viewDidLoadWasCalled {
            self.navigationItem.leftBarButtonItem = barButtonItem
        }
    }
    
    
    private func makeOwnedIdentityButton() -> UIBarButtonItem {
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let image = UIImage(systemIcon: .personCropCircle, withConfiguration: symbolConfiguration)
        let barButtonItem = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(ownedCircledInitialsBarButtonItemWasTapped))
        barButtonItem.tintColor = AppTheme.shared.colorScheme.olvidLight
        return barButtonItem
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        viewDidLoadWasCalled = true
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 20.0, weight: .heavy)
        titleLabel.text = self.navigationItem.title
        self.navigationItem.titleView = titleLabel
        if let appearance = self.navigationController?.navigationBar.standardAppearance.copy() {
            appearance.configureWithTransparentBackground()
            appearance.shadowColor = .clear
            appearance.backgroundEffect = UIBlurEffect(style: .regular)
            navigationItem.standardAppearance = appearance
        }

        let barButtonItem = barButtonItemToShowInsteadOfOwnedIdentityButton ?? makeOwnedIdentityButton()
        self.navigationItem.leftBarButtonItem = barButtonItem

    }
    
    @objc func ownedCircledInitialsBarButtonItemWasTapped() {
        assert(Thread.isMainThread)
        guard let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
        let deepLink = ObvDeepLink.myId(ownedIdentityURI: ownedIdentity.objectID.uriRepresentation())
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
            .postOnDispatchQueue()
    }

}
