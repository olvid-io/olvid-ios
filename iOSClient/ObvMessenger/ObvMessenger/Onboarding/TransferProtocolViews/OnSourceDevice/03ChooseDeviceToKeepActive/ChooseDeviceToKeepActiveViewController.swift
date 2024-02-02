/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import StoreKit
import ObvTypes
import ObvCrypto
import Contacts


protocol ChooseDeviceToKeepActiveViewControllerDelegate: AnyObject, SubscriptionPlansViewActionsProtocol {
    func userChoseDeviceToKeepActive(controller: ChooseDeviceToKeepActiveViewController, ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, enteredSAS: ObvOwnedIdentityTransferSas, ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult, currentDeviceIdentifier: Data, targetDeviceName: String, deviceToKeepActive: ObvOwnedDeviceDiscoveryResult.Device?, protocolInstanceUID: UID) async
    func userDidCancelOwnedIdentityTransferProtocol(controller: ChooseDeviceToKeepActiveViewController) async
    func refreshDeviceDiscovery(controller: ChooseDeviceToKeepActiveViewController, for ownedCryptoId: ObvCryptoId) async throws -> ObvOwnedDeviceDiscoveryResult
}


final class ChooseDeviceToKeepActiveViewController: UIHostingController<ChooseDeviceToKeepActiveView<ChooseDeviceToKeepActiveViewModel>>, ChooseDeviceToKeepActiveViewActionsProtocol {
    
    private weak var delegate: ChooseDeviceToKeepActiveViewControllerDelegate?
    
    init(model: ChooseDeviceToKeepActiveViewModel, delegate: ChooseDeviceToKeepActiveViewControllerDelegate) {
        let actions = ChooseDeviceToKeepActiveViewActions()
        let view = ChooseDeviceToKeepActiveView(actions: actions, model: model)
        super.init(rootView: view)
        self.delegate = delegate
        actions.delegate = self
    }
    
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground
        configureNavigation(animated: false)
    }

    
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        configureNavigation(animated: animated)
    }


    private func configureNavigation(animated: Bool) {
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelButtonTapped))
    }

    
    @objc
    private func cancelButtonTapped() {
        Task { [weak self] in
            guard let self else { return }
            await delegate?.userDidCancelOwnedIdentityTransferProtocol(controller: self)
        }
    }

    
    // ChooseDeviceToKeepActiveViewActionsProtocol
    
    func userChoseDeviceToKeepActive(ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, enteredSAS: ObvOwnedIdentityTransferSas, ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult, currentDeviceIdentifier: Data, targetDeviceName: String, deviceToKeepActive: ObvOwnedDeviceDiscoveryResult.Device?, protocolInstanceUID: UID) async {
        await delegate?.userChoseDeviceToKeepActive(
            controller: self,
            ownedCryptoId: ownedCryptoId,
            ownedDetails: ownedDetails,
            enteredSAS: enteredSAS,
            ownedDeviceDiscoveryResult: ownedDeviceDiscoveryResult,
            currentDeviceIdentifier: currentDeviceIdentifier,
            targetDeviceName: targetDeviceName,
            deviceToKeepActive: deviceToKeepActive,
            protocolInstanceUID: protocolInstanceUID)
    }
    
    
    // SubscriptionPlansViewActionsProtocol (required for ChooseDeviceToKeepActiveViewActionsProtocol)

    func fetchSubscriptionPlans(for ownedCryptoId: ObvCryptoId, alsoFetchFreePlan: Bool) async throws -> (freePlanIsAvailable: Bool, products: [Product]) {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.fetchSubscriptionPlans(for: ownedCryptoId, alsoFetchFreePlan: alsoFetchFreePlan)
    }
    
    
    func userWantsToStartFreeTrialNow(ownedCryptoId: ObvCryptoId) async throws -> APIKeyElements {
        assertionFailure("Not expected to be called here. The subscription view shall only show plans allowing to subscribe to multidevice")
        throw ObvError.cannotStartFreeTrialDuringOnboarding
    }
    
    
    func userWantsToBuy(_ product: Product) async throws -> StoreKitDelegatePurchaseResult {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.userWantsToBuy(product)
    }
    
    
    func userWantsToRestorePurchases() async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await delegate.userWantsToRestorePurchases()
    }
    
    
    func refreshDeviceDiscovery(for ownedCryptoId: ObvCryptoId) async throws -> ObvOwnedDeviceDiscoveryResult {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.refreshDeviceDiscovery(controller: self, for: ownedCryptoId)
    }

    enum ObvError: Error {
        case delegateIsNil
        case cannotStartFreeTrialDuringOnboarding
    }
    
}


private final class ChooseDeviceToKeepActiveViewActions: ChooseDeviceToKeepActiveViewActionsProtocol {
    
    weak var delegate: ChooseDeviceToKeepActiveViewActionsProtocol?
    
    func userChoseDeviceToKeepActive(ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, enteredSAS: ObvOwnedIdentityTransferSas, ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult, currentDeviceIdentifier: Data, targetDeviceName: String, deviceToKeepActive: ObvOwnedDeviceDiscoveryResult.Device?, protocolInstanceUID: UID) async {
        await delegate?.userChoseDeviceToKeepActive(
            ownedCryptoId: ownedCryptoId,
            ownedDetails: ownedDetails,
            enteredSAS: enteredSAS,
            ownedDeviceDiscoveryResult: ownedDeviceDiscoveryResult,
            currentDeviceIdentifier: currentDeviceIdentifier,
            targetDeviceName: targetDeviceName,
            deviceToKeepActive: deviceToKeepActive,
            protocolInstanceUID: protocolInstanceUID)
    }

    
    // SubscriptionPlansViewActionsProtocol (required for ChooseDeviceToKeepActiveViewActionsProtocol)
    
    func fetchSubscriptionPlans(for ownedCryptoId: ObvCryptoId, alsoFetchFreePlan: Bool) async throws -> (freePlanIsAvailable: Bool, products: [Product]) {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.fetchSubscriptionPlans(for: ownedCryptoId, alsoFetchFreePlan: alsoFetchFreePlan)
    }
    
    func userWantsToStartFreeTrialNow(ownedCryptoId: ObvCryptoId) async throws -> APIKeyElements {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.userWantsToStartFreeTrialNow(ownedCryptoId: ownedCryptoId)
    }
    
    
    func userWantsToBuy(_ product: Product) async throws -> StoreKitDelegatePurchaseResult {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.userWantsToBuy(product)
    }
    
    
    func userWantsToRestorePurchases() async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await delegate.userWantsToRestorePurchases()
    }
    
    
    func refreshDeviceDiscovery(for ownedCryptoId: ObvCryptoId) async throws -> ObvOwnedDeviceDiscoveryResult {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.refreshDeviceDiscovery(for: ownedCryptoId)
    }

    enum ObvError: Error {
        case delegateIsNil
    }
}
