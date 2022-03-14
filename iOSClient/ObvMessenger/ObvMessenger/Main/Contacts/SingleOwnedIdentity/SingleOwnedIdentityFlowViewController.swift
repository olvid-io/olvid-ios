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
import SwiftUI
import ObvTypes
import ObvEngine
import StoreKit

protocol SingleOwnedIdentityFlowViewControllerDelegate: AnyObject {
    
    func userWantsToDismissSingleOwnedIdentityFlowViewController()
    
}


class SingleOwnedIdentityFlowViewController: UIViewController {

    let ownedIdentity: PersistedObvOwnedIdentity
    let ownedCryptoId: ObvCryptoId
    weak var delegate: SingleOwnedIdentityFlowViewControllerDelegate?
    private var editedOwnedIdentity: SingleIdentity?
    private var availableSubscriptionPlans: AvailableSubscriptionPlans?
    private var apiKeyStatusAndExpiry: APIKeyStatusAndExpiry
    
    init(ownedIdentity: PersistedObvOwnedIdentity) {
        assert(Thread.isMainThread)
        assert(ownedIdentity.managedObjectContext == ObvStack.shared.viewContext)
        self.ownedIdentity = ownedIdentity
        self.ownedCryptoId = ownedIdentity.cryptoId
        self.apiKeyStatusAndExpiry = APIKeyStatusAndExpiry(ownedIdentity: ownedIdentity)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let singleIdentity = SingleIdentity(ownedIdentity: ownedIdentity)
        let view = SingleOwnedIdentityView(singleIdentity: singleIdentity,
                                           apiKeyStatusAndExpiry: apiKeyStatusAndExpiry,
                                           dismissAction: dismiss,
                                           editOwnedIdentityAction: userWantsToEditOwnedIdentity,
                                           subscriptionPlanAction: userWantsToSeeSubscriptionPlans,
                                           refreshStatusAction: userWantsToRefreshSubscriptionStatus)
        let hostViewController = UIHostingController(rootView: view)
        
        hostViewController.willMove(toParent: self)
        self.addChild(hostViewController)
        hostViewController.didMove(toParent: self)
        
        hostViewController.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(hostViewController.view)
        self.view.pinAllSidesToSides(of: hostViewController.view)
        
    }

    private func dismiss() {
        delegate?.userWantsToDismissSingleOwnedIdentityFlowViewController()
    }
    
    
    @objc private func dismissPresentedViewController() {
        dismiss(animated: true)
    }
    
    
    private func userWantsToEditOwnedIdentity() {
        assert(Thread.isMainThread)
        editedOwnedIdentity = SingleIdentity(ownedIdentity: ownedIdentity, editionMode: .picture)
        let view = EditSingleOwnedIdentityNavigationView(editionType: .edition, singleIdentity: editedOwnedIdentity!, userConfirmedPublishAction: userWantsToPublishEditedOwnedIdentity, dismissAction: userWantsToDismissEditSingleIdentityView)
        let vc = UIHostingController(rootView: view)
        present(vc, animated: true)
    }
    
    
    private func userWantsToRefreshSubscriptionStatus() {
        let ownedCryptoId = self.ownedCryptoId
        DispatchQueue(label: "Queue for refreshing API permissions").async { [weak self] in
            try? self?.obvEngine.refreshAPIPermissions(for: ownedCryptoId)
        }
    }
    
    
    private func userWantsToSeeSubscriptionPlans() {
        self.availableSubscriptionPlans = AvailableSubscriptionPlans(ownedCryptoId: ownedIdentity.cryptoId, fetchSubscriptionPlanAction: fetchSubscriptionPlanAction, userWantsToStartFreeTrialNow: userWantsToStartFreeTrialNow, userWantsToFallbackOnFreeVersion: userWantsToFallbackOnFreeVersion, userWantsToBuy: userWantsToBuySKProductNow, userWantsToRestorePurchases: userWantsToRestorePurchases)
        let view = AvailableSubscriptionPlansView(plans: availableSubscriptionPlans!, dismissAction: dismissPresentedViewController)
        let vc = UIHostingController(rootView: view)
        self.present(vc, animated: true)
    }
    
    private func fetchSubscriptionPlanAction() {
        // Step 1: Ask the engine (i.e., Olvid's server) whether a free trial is still available for this identity
        do {
            try obvEngine.queryServerForFreeTrial(for: ownedCryptoId, retrieveAPIKey: false)
        } catch {
            assertionFailure()
        }
        // Step 2: As StoreKit about available products
        SubscriptionNotification.userRequestedListOfSKProducts
            .postOnDispatchQueue()
    }
    
    private func userWantsToStartFreeTrialNow() {
        do {
            try obvEngine.queryServerForFreeTrial(for: ownedIdentity.cryptoId, retrieveAPIKey: true)
        } catch {
            assertionFailure()
        }
    }
    
    private func userWantsToFallbackOnFreeVersion() {
        guard let hardcodedAPIKey = ObvMessengerConstants.hardcodedAPIKey else {
            assertionFailure()
            return
        }
        ObvMessengerInternalNotification.userRequestedNewAPIKeyActivation(ownedCryptoId: ownedCryptoId, apiKey: hardcodedAPIKey)
            .postOnDispatchQueue()
    }
    
    private func userWantsToBuySKProductNow(_ product: SKProduct) {
        SubscriptionNotification.userRequestedToBuySKProduct(skProduct: product)
            .postOnDispatchQueue()
    }
    
    private func userWantsToRestorePurchases() {
        SubscriptionNotification.userRequestedToRestoreAppStorePurchases
            .postOnDispatchQueue()
    }
    
    private func userWantsToPublishEditedOwnedIdentity() {
        assert(Thread.isMainThread)
        showHUD(type: .spinner)
        dismissPresentedViewController()
        guard let editedOwnedIdentity = self.editedOwnedIdentity else { assertionFailure(); hideHUD(); return }
        self.editedOwnedIdentity = nil

        let newCoreIdentityDetails: ObvIdentityCoreDetails
        if editedOwnedIdentity.isKeycloakManaged {
            guard let obvOwnedIdentity = try? obvEngine.getOwnedIdentity(with: ownedCryptoId) else { assertionFailure(); hideHUD(); return }
            newCoreIdentityDetails = obvOwnedIdentity.publishedIdentityDetails.coreDetails // Not really new, but we cannot change them since they are managed
        } else {
            guard editedOwnedIdentity.isValid, let _newCoreIdentityDetails = editedOwnedIdentity.unmanagedIdentityDetails else { assertionFailure(); hideHUD(); return }
            newCoreIdentityDetails = _newCoreIdentityDetails
        }
        let newProfilPictureURL = editedOwnedIdentity.photoURL

        let ownedCryptoId = ownedIdentity.cryptoId
        let obvEngine = self.obvEngine

        DispatchQueue(label: "Queue for publishing new owned Id").async { [weak self] in
            do {
                let newDetails = ObvIdentityDetails(coreDetails: newCoreIdentityDetails,
                                                    photoURL: newProfilPictureURL)
                try obvEngine.updatePublishedIdentityDetailsOfOwnedIdentity(with: ownedCryptoId, with: newDetails)
            } catch {
                DispatchQueue.main.async {
                    self?.showHUD(type: .text(text: "Failed"))
                    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { self?.hideHUD() }
                }
                return
            }

            DispatchQueue.main.sync {
                self?.showHUD(type: .checkmark)
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { self?.hideHUD() }
            }
            
        }

    }
    
    
    private func userWantsToDismissEditSingleIdentityView() {
        self.editedOwnedIdentity = nil
        dismiss(animated: true)
    }

}
