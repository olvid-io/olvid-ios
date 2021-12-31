/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
    
    init(ownedCryptoId: ObvCryptoId, logCategory: String) {
        self.ownedCryptoId = ownedCryptoId
        self.log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: logCategory)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var title: String? {
        get {
            return super.title
        }
        set {
            titleLabel.text = newValue
            super.title = newValue
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 20.0, weight: .heavy)
        titleLabel.text = self.title
        self.navigationItem.titleView = titleLabel
        if #available(iOS 13, *) {
            if let appearance = self.navigationController?.navigationBar.standardAppearance.copy() {
                appearance.configureWithTransparentBackground()
                appearance.shadowColor = .clear
                appearance.backgroundEffect = UIBlurEffect(style: .regular)
                navigationItem.standardAppearance = appearance
            }
        }

        let barButtonItem: UIBarButtonItem
        if #available(iOS 13, *) {
            let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
            let image = UIImage(systemName: "person.crop.circle", withConfiguration: symbolConfiguration)
            barButtonItem = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(ownedCircledInitialsBarButtonItemWasTapped))
        } else {
            barButtonItem = UIBarButtonItem(title: NSLocalizedString("My Id", comment: ""), style: .done, target: self, action: #selector(ownedCircledInitialsBarButtonItemWasTapped))
        }
        barButtonItem.tintColor = AppTheme.shared.colorScheme.olvidLight
        self.navigationItem.leftBarButtonItem = barButtonItem

    }
    
    @objc func ownedCircledInitialsBarButtonItemWasTapped() {
        assert(Thread.isMainThread)
        guard let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
        if #available(iOS 13, *) {
            let deepLink = ObvDeepLink.myId(ownedIdentityURI: ownedIdentity.objectID.uriRepresentation())
            ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                .postOnDispatchQueue()
        } else {
            let vc = SingleIdentityViewController(persistedObvOwnedIdentity: ownedIdentity)
            vc.delegate = self
            let closeButton = BlockBarButtonItem.forClosing { [weak self] in self?.presentedViewController?.dismiss(animated: true) }
            vc.navigationItem.setLeftBarButton(closeButton, animated: false)
            let nav = UINavigationController(rootViewController: vc)
            present(nav, animated: true)
        }
    }

}


// Should only be used under iOS12 or less
extension ShowOwnedIdentityButtonUIViewController: SingleOwnedIdentityViewControllerDelegate {

    func editOwnedPublishedIdentityDetails() {
        
        if #available(iOS 13, *) {
            assertionFailure()
        }
        
        guard let obvOwnedIdentity = try? obvEngine.getOwnedIdentity(with: ownedCryptoId) else { return }
        
        assert(obvOwnedIdentity.signedUserDetails == nil)
        assert(!obvOwnedIdentity.isKeycloakManaged)

        let details = obvOwnedIdentity.publishedIdentityDetails.coreDetails
        let displaynameMaker = DisplaynameStruct(firstName: details.firstName,
                                                 lastName: details.lastName,
                                                 company: details.company,
                                                 position: details.position,
                                                 photoURL: obvOwnedIdentity.publishedIdentityDetails.photoURL)
        let displayNameChooserViewController = DisplayNameChooserViewController(displaynameMaker: displaynameMaker,
                                                                                completionHandlerOnSave: userWantsToSaveOwnedIdentityDetails,
                                                                                serverAndAPIKey: nil)
        
        let nav = ObvNavigationController(rootViewController: displayNameChooserViewController)
        displayNameChooserViewController.navigationItem.leftBarButtonItem = UIBarButtonItem.forClosing(target: self, action: #selector(dismissDisplayNameChooserViewController))
        if let presentedVC = self.presentedViewController {
            presentedVC.present(nav, animated: true)
        } else {
            self.present(nav, animated: true)
        }
        
    }
    
    
    private func userWantsToSaveOwnedIdentityDetails(displaynameMaker: DisplaynameStruct) {
        defer { dismissDisplayNameChooserViewController() }
        guard displaynameMaker.isValid, let newCoreIdentityDetails = displaynameMaker.identityDetails else { return }
        
        do {
            let obvOwnedIdentity = try obvEngine.getOwnedIdentity(with: ownedCryptoId)
            let publishedDetails = obvOwnedIdentity.publishedIdentityDetails
            let newDetails = ObvIdentityDetails(coreDetails: newCoreIdentityDetails,
                                                photoURL: publishedDetails.photoURL)
            try obvEngine.updatePublishedIdentityDetailsOfOwnedIdentity(with: ownedCryptoId, with: newDetails)
        } catch {
            os_log("Could not update owned identity latest details", log: log, type: .error)
        }
        
    }
    
    
    @objc private func dismissDisplayNameChooserViewController() {
        presentedViewController?.view.endEditing(true)
        presentedViewController?.dismiss(animated: true)
    }
    
}
