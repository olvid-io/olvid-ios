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
import ObvTypes
import ObvEngine
import StoreKit
import os.log
import CoreData
import ObvUICoreData


protocol SingleOwnedIdentityFlowViewControllerDelegate: AnyObject, StoreKitDelegate {
    func userWantsToDismissSingleOwnedIdentityFlowViewController(_ viewController: SingleOwnedIdentityFlowViewController)
    func userWantsToAddNewDevice(_ viewController: SingleOwnedIdentityFlowViewController, ownedCryptoId: ObvCryptoId) async
}


enum StoreKitDelegatePurchaseResult {
    case purchaseSucceeded(serverVerificationResult: ObvAppStoreReceipt.VerificationStatus)
    case userCancelled
    case pending
}

protocol StoreKitDelegate: AnyObject {
    func userRequestedListOfSKProducts() async throws -> [Product]
    func userWantsToBuy(_ product: Product) async throws -> StoreKitDelegatePurchaseResult
    func userWantsToRestorePurchases() async throws
}


final class SingleOwnedIdentityFlowViewController: UIHostingController<SingleOwnedIdentityView>, HiddenProfilePasswordChooserViewControllerDelegate, OwnedIdentityDetailedInfosViewDelegate, SingleOwnedIdentityViewActionsDelegate, OwnedDevicesListViewActionsDelegate, PermuteDeviceExpirationHostingViewControllerDelegate, ChooseDeviceToReactivateHostingViewControllerDelegate {
        
    let ownedIdentity: PersistedObvOwnedIdentity
    let ownedCryptoId: ObvCryptoId
    let obvEngine: ObvEngine
    weak var delegate: SingleOwnedIdentityFlowViewControllerDelegate?
    private var editedOwnedIdentity: SingleIdentity?
    private var apiKeyStatusAndExpiry: APIKeyStatusAndExpiry
    private let actions: SingleOwnedIdentityViewActions
    private var rightBarButtonItem: UIBarButtonItem?
    private var legacyConfigureNavigationBarAndObserveNotificationsNeedsToBeCalled = true
    
    private var notificationTokens = [NSObjectProtocol]()
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "SingleOwnedIdentityFlowViewController")

    init(ownedIdentity: PersistedObvOwnedIdentity, obvEngine: ObvEngine, delegate: SingleOwnedIdentityFlowViewControllerDelegate?) {
        assert(Thread.isMainThread)
        assert(ownedIdentity.managedObjectContext == ObvStack.shared.viewContext)
        self.ownedIdentity = ownedIdentity
        self.ownedCryptoId = ownedIdentity.cryptoId
        self.obvEngine = obvEngine
        self.apiKeyStatusAndExpiry = APIKeyStatusAndExpiry(ownedIdentity: ownedIdentity)
        
        let actions = SingleOwnedIdentityViewActions()
        let view = SingleOwnedIdentityView(ownedIdentity: ownedIdentity,
                                           apiKeyStatusAndExpiry: apiKeyStatusAndExpiry,
                                           actions: actions)
        self.actions = actions
        super.init(rootView: view)
        self.actions.delegate = self
        self.delegate = delegate
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationBarAndObserveNotifications()
    }
    
    
    private func configureNavigationBarAndObserveNotifications() {
        title = NSLocalizedString("My Id", comment: "")
        
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let ellipsisImage = UIImage(systemIcon: .ellipsisCircle, withConfiguration: symbolConfiguration)
        rightBarButtonItem = UIBarButtonItem(title: "", image: ellipsisImage, menu: provideMenu())
        navigationItem.rightBarButtonItem = rightBarButtonItem
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(userWantsToDismissSingleOwnedIdentityFlowViewController))
        
        observeNotifications()
    }
    
    
    @objc
    private func userWantsToDismissSingleOwnedIdentityFlowViewController() {
        assert(delegate != nil)
        delegate?.userWantsToDismissSingleOwnedIdentityFlowViewController(self)
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // This will allow to ask the engine to perform an owned device discovery
        ObvMessengerInternalNotification.singleOwnedIdentityFlowViewControllerDidAppear(ownedCryptoId: ownedCryptoId)
            .postOnDispatchQueue()
        
    }
    
    private func observeNotifications() {
        notificationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeFailedToHideOwnedIdentity { [weak self] ownedCryptoId in
                Task { await self?.processFailedToHideOwnedIdentity(ownedCryptoId: ownedCryptoId) }
            },
            ObvMessengerCoreDataNotification.observeOwnedIdentityHiddenStatusChanged { [weak self] ownedCryptoId, isHidden in
                Task { await self?.processOwnedIdentityHiddenStatusChanged(ownedCryptoId: ownedCryptoId, isHidden: isHidden) }
            },
        ])
    }
    
    
    @MainActor
    private func processOwnedIdentityHiddenStatusChanged(ownedCryptoId: ObvCryptoId, isHidden: Bool) async {
        guard ownedCryptoId == self.ownedCryptoId else { return }
        updateMenu()
        if isHidden {
            showHUD(type: .icon(systemIcon: .eyeSlash, feedbackOnDisplay: true))
        } else {
            showHUD(type: .icon(systemIcon: .eye, feedbackOnDisplay: true))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { [weak self] in self?.hideHUD() }
    }
    

    @MainActor
    private func processFailedToHideOwnedIdentity(ownedCryptoId: ObvCryptoId) async {
        guard self.ownedCryptoId == ownedCryptoId else { return }
        let alert = UIAlertController(title: Strings.FailedToHideOwnedIdentityAlert.title,
                                      message: Strings.FailedToHideOwnedIdentityAlert.message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
        present(alert, animated: true)
    }
    
    
    @objc private func userWantsToHideThisOwnedIdentity() {
        assert(Thread.isMainThread)
        
        let nonHiddenOwnedIdentities: [PersistedObvOwnedIdentity]
        do {
            nonHiddenOwnedIdentities = try PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: ObvStack.shared.viewContext)
        } catch {
            os_log("Could not get owned identity: %{public}@", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
        
        guard nonHiddenOwnedIdentities.first(where: { $0.cryptoId == ownedCryptoId }) != nil else { assertionFailure(); return }
        
        guard nonHiddenOwnedIdentities.count > 1 else {
            let alert = UIAlertController(
                title: Strings.AtLeastOneUnhiddenProfileMustExistAlert.title,
                message: Strings.AtLeastOneUnhiddenProfileMustExistAlert.message,
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Strings.AtLeastOneUnhiddenProfileMustExistAlert.actionAddProfile, style: .default) { [weak self] _ in
                self?.dismiss(animated: true)
                ObvMessengerInternalNotification.userWantsToAddOwnedProfile
                    .postOnDispatchQueue()
            })
            alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
            present(alert, animated: true)
            return
        }
        
        let vc = HiddenProfilePasswordChooserViewController(ownedCryptoId: ownedCryptoId, delegate: self)
        vc.modalPresentationStyle = .popover
        if let popover = vc.popoverPresentationController {
            let sheet = popover.adaptiveSheetPresentationController
            if #available(iOS 16, *) {
                sheet.detents = [.custom(resolver: { context in
                    switch context.containerTraitCollection.preferredContentSizeCategory {
                    case .extraSmall, .small: return 450
                    case .medium: return 500
                    case .large: return 550
                    default: return 600
                    }
                }), .large()]
            } else {
                sheet.detents = [.medium(), .large()]
            }
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 16.0
            assert(rightBarButtonItem != nil)
            if #available(iOS 16, *) {
                popover.sourceItem = rightBarButtonItem
            } else {
                popover.barButtonItem = rightBarButtonItem
            }
        }
        present(vc, animated: true)

    }

    
    private func userWantsToUnhideThisOwnedIdentity() {
        assert(Thread.isMainThread)
        let ownedCryptoId = self.ownedCryptoId
        let alert = UIAlertController(title: Strings.UnhideOwnedIdentityAlert.title,
                                      message: Strings.UnhideOwnedIdentityAlert.message,
                                      preferredStyleForTraitCollection: .current)
        alert.addAction(UIAlertAction(title: Strings.UnhideOwnedIdentityAlert.actionStayHidden, style: .cancel))
        alert.addAction(UIAlertAction(title: Strings.UnhideOwnedIdentityAlert.actionUnhide, style: .default) { _ in
            ObvMessengerInternalNotification.userWantsToUnhideOwnedIdentity(ownedCryptoId: ownedCryptoId)
                .postOnDispatchQueue()
        })
        present(alert, animated: true)
    }

    
    private func updateMenu() {
        rightBarButtonItem?.menu = provideMenu()
    }
    
    
    private func userWantsToSeeOwnedIdentityDetails() {
        assert(Thread.isMainThread)
        guard let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
        let view = OwnedIdentityDetailedInfosView(ownedIdentity: ownedIdentity, delegate: self)
        let vc = UIHostingController(rootView: view)
        present(vc, animated: true)
    }
    
    
    func provideMenu() -> UIMenu {
        var menuElements = [UIMenuElement]()
        do {
            if let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) {
                ObvStack.shared.viewContext.refresh(ownedIdentity, mergeChanges: true)
                let action: UIAction
                if ownedIdentity.isHidden {
                    action = UIAction(title: Strings.unhideThisProfile,
                                      image: UIImage(systemIcon: .eye)) { [weak self] _ in
                        self?.userWantsToUnhideThisOwnedIdentity()
                    }
                } else {
                    action = UIAction(title: Strings.hideThisProfile,
                                      image: UIImage(systemIcon: .eyeSlash)) { [weak self] _ in
                        self?.userWantsToHideThisOwnedIdentity()
                    }
                }
                menuElements.append(action)
            }
        } catch {
            assertionFailure()
            // Continue anyway
        }
        let showDetailsAction = UIAction(title: Strings.showOwnedIdentityDetails,
                                         image: UIImage(systemIcon: .personCropCircleBadgeQuestionmark)) { [weak self] _ in
            self?.userWantsToSeeOwnedIdentityDetails()
        }
        let editNicknameAction = UIAction(title: Strings.editOwnedIdentityNickname,
                                          image: UIImage(systemIcon: .ellipsisRectangle)) { [weak self] _ in
            Task { await self?.showAlertForEditingCustomDisplayName() }
        }
        menuElements.append(showDetailsAction)
        menuElements.append(editNicknameAction)
        let menu = UIMenu(title: "", children: menuElements)
        return menu
    }
    
    
    @available(iOS, introduced: 13.0, deprecated: 14.0, message: "Used because iOS 13 does not support UIMenu on UIBarButtonItem")
    @objc private func ellipsisButtonTapped() {
        assert(Thread.isMainThread)
        let alert = UIAlertController(title: CommonString.Word.Advanced, message: nil, preferredStyle: UIDevice.current.actionSheetIfPhoneAndAlertOtherwise)
        if let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) {
            if ownedIdentity.isHidden {
                alert.addAction(UIAlertAction(title: Strings.unhideThisProfile, style: .default, handler: { [weak self] _ in self?.userWantsToUnhideThisOwnedIdentity() }))
            } else {
                alert.addAction(UIAlertAction(title: Strings.hideThisProfile, style: .default, handler: { [weak self] _ in self?.userWantsToHideThisOwnedIdentity() }))
            }
        }
        alert.addAction(UIAlertAction(title: Strings.showOwnedIdentityDetails, style: .default, handler: { [weak self] _ in self?.userWantsToSeeOwnedIdentityDetails() }))
        alert.addAction(UIAlertAction(title: Strings.editOwnedIdentityNickname, style: .default, handler: { [weak self] _ in Task { await self?.showAlertForEditingCustomDisplayName() } }))
        alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
        present(alert, animated: true)
    }

    
    
    @MainActor private func showAlertForEditingCustomDisplayName() async {
        let ownedCryptoId = self.ownedCryptoId
        let currentDisplayName: String?
        do {
            let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext)
            currentDisplayName = ownedIdentity?.customDisplayName
        } catch {
            assertionFailure() // In production, continue anyway
            currentDisplayName = nil
        }
        let alert = UIAlertController(title: Strings.AlertForEditingNickname.title,
                                      message: Strings.AlertForEditingNickname.message,
                                      preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = currentDisplayName
            textField.clearButtonMode = .always
        }
        alert.addAction(.init(title: CommonString.Word.Cancel, style: .cancel))
        alert.addAction(.init(title: CommonString.Word.Save, style: .default, handler: { [unowned alert] _ in
            guard let textField = alert.textFields?.first else { assertionFailure(); return }
            let newCustomDisplayName = textField.text?.trimmingWhitespacesAndNewlines()
            ObvMessengerInternalNotification.userWantsToUpdateOwnedCustomDisplayName(ownedCryptoId: ownedCryptoId, newCustomDisplayName: newCustomDisplayName)
                .postOnDispatchQueue()
        }))
        present(alert, animated: true)
    }
    
    
    @objc private func dismissPresentedViewController() {
        dismiss(animated: true)
    }
    
        
    @MainActor
    private func userWantsToPublishEditedOwnedIdentity() async {
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

        do {
            let newDetails = ObvIdentityDetails(coreDetails: newCoreIdentityDetails, photoURL: newProfilPictureURL)
            try await obvEngine.updatePublishedIdentityDetailsOfOwnedIdentity(with: ownedCryptoId, with: newDetails)
            showHUD(type: .checkmark)
        } catch {
            showHUD(type: .text(text: "Failed"))
        }

        try? await Task.sleep(seconds: 2)
        hideHUD()

    }
    
    
    @MainActor
    private func userWantsToUnbindFromKeycloakServer(ownedCryptoId: ObvCryptoId) async {
        assert(Thread.isMainThread)
        showHUD(type: .spinner)
        dismissPresentedViewController()
        self.editedOwnedIdentity = nil

        ObvMessengerInternalNotification.userWantsToUnbindOwnedIdentityFromKeycloak(ownedCryptoId: ownedCryptoId) { success in
            DispatchQueue.main.async { [weak self] in
                self?.showHUD(type: success ? .checkmark : .text(text: "Failed"))
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { self?.hideHUD() }
            }
        }.postOnDispatchQueue()
    }
    
    
    @MainActor
    private func userWantsToDismissEditSingleIdentityView() async {
        self.editedOwnedIdentity = nil
        dismiss(animated: true)
    }

    
}


// MARK: - HiddenProfilePasswordChooserViewControllerDelegate

extension SingleOwnedIdentityFlowViewController {
    
    @MainActor func userCancelledHiddenProfilePasswordChooserViewController() async {
        presentedViewController?.dismiss(animated: true)
    }
    
    
    @MainActor func userChosePasswordForHidingOwnedIdentity(_ ownedCryptoId: ObvCryptoId, password: String) async {
        presentedViewController?.dismiss(animated: true) {
            ObvMessengerInternalNotification.userWantsToHideOwnedIdentity(ownedCryptoId: ownedCryptoId, password: password)
                .postOnDispatchQueue()
        }
    }

}


// MARK: - OwnedIdentityDetailedInfosViewDelegate

extension SingleOwnedIdentityFlowViewController {
    
    @MainActor func userWantsToDismissOwnedIdentityDetailedInfosView() async {
        presentedViewController?.dismiss(animated: true)
    }
 
    func getKeycloakAPIKey(ownedCryptoId: ObvCryptoId) async throws -> UUID? {
        return try await obvEngine.getKeycloakAPIKey(ownedCryptoId: ownedCryptoId)
    }
    
}


// MARK: - OwnedDevicesListViewActionsDelegate

extension SingleOwnedIdentityFlowViewController {
    
    func userWantsToSearchForNewOwnedDevices(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        Task {
            do {
                try await obvEngine.performOwnedDeviceDiscovery(ownedCryptoId: ownedCryptoId)
            } catch {
                assertionFailure(error.localizedDescription)
            }
            DispatchQueue.main.async { [weak self] in
                self?.navigationController?.topViewController?.showHUD(type: .checkmark)
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { [weak self] in
                    self?.navigationController?.topViewController?.hideHUD()
                }
            }
        }
    }
    
    func userWantsToClearAllOtherOwnedDevices(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        // No need to require a confirmation, this confirmation was required in the SwiftUI OwnedDevicesListView.
        Task {
            do {
                try await obvEngine.deleteAllOtherOwnedDevicesAndChannelsThenPerformOwnedDeviceDiscovery(ownedCryptoId: ownedCryptoId)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
    func userWantsToRestartChannelCreationWithOtherOwnedDevice(ownedCryptoId: ObvTypes.ObvCryptoId, deviceIdentifier: Data) async {
        do {
            try await obvEngine.restartChannelEstablishmentProtocolsWithOwnedDevice(ownedCryptoId: ownedCryptoId, deviceIdentifier: deviceIdentifier)
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    @MainActor
    func userWantsToRenameOwnedDevice(ownedCryptoId: ObvTypes.ObvCryptoId, deviceIdentifier: Data) async {
        guard ownedIdentity.cryptoId == ownedCryptoId else { assertionFailure(); return }
        guard let ownedDevice = ownedIdentity.devices.first(where: { $0.identifier == deviceIdentifier }) else { assertionFailure(); return }
        let obvEngine = self.obvEngine
        let alert = UIAlertController(title: NSLocalizedString("CHOOSE_DEVICE_NAME", comment: ""), message: nil, preferredStyle: .alert)
        alert.addTextField { (textField) in
            textField.text = ownedDevice.name
        }
        alert.addAction(.init(title: CommonString.Word.Cancel, style: .cancel))
        alert.addAction(.init(title: CommonString.Word.Ok, style: .default) { [weak alert] _ in
            guard let ownedDeviceName = alert?.textFields?.first?.text else { assertionFailure(); return }
            Task {
                try? await obvEngine.requestChangeOfOwnedDeviceName(ownedCryptoId: ownedCryptoId, deviceIdentifier: deviceIdentifier, ownedDeviceName: ownedDeviceName)
            }
        })
        present(alert, animated: true)
    }


    @MainActor
    internal func userWantsToDeactivateOtherOwnedDevice(ownedCryptoId: ObvCryptoId, deviceIdentifier: Data) async {
        let obvEngine = self.obvEngine
        let alert = UIAlertController(title: NSLocalizedString("REMOVE_OWNED_DEVICE_ALERT_TITLE", comment: ""), message: nil, preferredStyle: .alert)
        alert.addAction(.init(title: CommonString.Word.Cancel, style: .cancel))
        alert.addAction(.init(title: CommonString.Word.Deactivate, style: .destructive) { _ in
            Task {
                try? await obvEngine.requestDeactivationOfOtherOwnedDevice(ownedCryptoId: ownedCryptoId, deviceIdentifier: deviceIdentifier)
            }
        })
        present(alert, animated: true)
    }


    @MainActor
    func userWantsToKeepThisDeviceActive(ownedCryptoId: ObvCryptoId, deviceIdentifier: Data) async {
        guard ownedCryptoId == ownedIdentity.cryptoId else { assertionFailure(); return }
        guard ownedIdentity.isActive else { assertionFailure(); return }

        // If the device is not active, this request makes no sense.
        
        guard ownedIdentity.isActive else { assertionFailure(); return }
        
        // If the device requested has no expiry, this request makes no sense.
        
        guard let deviceToKeepActive = ownedIdentity.devices.first(where: { $0.identifier == deviceIdentifier }) else { assertionFailure(); return }
        guard deviceToKeepActive.expirationDate != nil else { assertionFailure(); return }
        
        // We have two cases to consider: either the owned identity is allowed to have multiple devices, or not.
        
        if ownedIdentity.effectiveAPIPermissions.contains(.multidevice) {
            
            // Since the owned identity is allowed to have multiple devices, keeping this device active will have no impact on other devices.
            // Therefore, no need to alert the user, we can process the request immediately.
            Task {
                try? await obvEngine.requestSettingUnexpiringDevice(ownedCryptoId: ownedCryptoId, deviceIdentifier: deviceIdentifier)
            }
            
        } else {
            
            // Since the owned identity is not allowed to have multiple device, keeping this device active will necessarily transfer the expiration to the device that currently has no expiration.
            
            guard let deviceWithoutExpiration = ownedIdentity.devices.first(where: { $0.expirationDate == nil }) else {
                // We found no other device, which is unexpected. In production, we process the user request immediately.
                assertionFailure()
                Task {
                    try? await obvEngine.requestSettingUnexpiringDevice(ownedCryptoId: ownedCryptoId, deviceIdentifier: deviceIdentifier)
                }
                return
            }
            
            // If we reach this point, we alert the user, allowing her to decide whether she wants to indeed keep the device active (and add an expiration to the other device) or not.
            
            let model = PermuteDeviceExpirationViewModel(
                ownedCryptoId: ownedCryptoId,
                identifierOfDeviceToKeepActive: deviceToKeepActive.identifier,
                nameOfDeviceToKeepActive: deviceToKeepActive.name,
                identifierOfDeviceWithoutExpiration: deviceWithoutExpiration.identifier,
                nameOfDeviceWithoutExpiration: deviceWithoutExpiration.name)
            let vc = PermuteDeviceExpirationHostingViewController(model: model, delegate: self)
            
            if traitCollection.userInterfaceIdiom == .phone {
                vc.modalPresentationStyle = .popover
                if let popover = vc.popoverPresentationController {
                    let sheet = popover.adaptiveSheetPresentationController
                    sheet.detents = [.large()]
                    sheet.prefersGrabberVisible = true
                    sheet.preferredCornerRadius = 16.0
                    assert(rightBarButtonItem != nil)
                }
            } else {
                vc.modalPresentationStyle = .formSheet
            }
            present(vc, animated: true)

        }
        
    }
    
    
    @MainActor
    func userWantsToReactivateThisDevice(ownedCryptoId: ObvCryptoId) async {
        guard ownedIdentity.cryptoId == ownedCryptoId else { assertionFailure(); return }
        
        // If the device is active, this request makes no sense.
        
        guard !ownedIdentity.isActive else { assertionFailure(); return }
        
        // Get the required information about the current device
        
        guard let currentDeviceObj = ownedIdentity.devices
            .first(where: { $0.secureChannelStatus == .currentDevice }) else { assertionFailure(); return }
        let currentDevice = ChooseDeviceToReactivateViewModel.Device(deviceIdentifier: currentDeviceObj.deviceIdentifier, deviceName: currentDeviceObj.name, expirationDate: nil, latestRegistrationDate: nil)

        // Present the view controller
        
        let vc = ChooseDeviceToReactivateHostingViewController(model: .init(ownedCryptoId: ownedCryptoId, currentDeviceName: currentDevice.deviceName, currentDeviceIdentifier: currentDevice.deviceIdentifier), obvEngine: obvEngine, delegate: self)
        present(vc, animated: true)
        
    }
    

}


// MARK: - ChooseDeviceToReactivateHostingViewControllerDelegate

extension SingleOwnedIdentityFlowViewController {
    
    @MainActor
    func userWantsToDismissChooseDeviceToReactivateHostingViewController() async {
        if let vc = presentedViewController as? ChooseDeviceToReactivateHostingViewController {
            vc.dismiss(animated: true)
        }
    }
    
}


// MARK: - PermuteDeviceExpirationHostingViewControllerDelegate

extension SingleOwnedIdentityFlowViewController {
    
    @MainActor
    func userWantsToCancelAndDismissPermuteDeviceExpirationView() async {
        guard presentedViewController is PermuteDeviceExpirationHostingViewController else { assertionFailure(); return }
        presentedViewController?.dismiss(animated: true)
    }
    
    
    @MainActor
    func userWantsToSeeSubscriptionPlansFromPermuteDeviceExpirationView() async {
        guard presentedViewController is PermuteDeviceExpirationHostingViewController else { assertionFailure(); return }
        presentedViewController?.dismiss(animated: true) { [weak self] in
            Task { [weak self] in await self?.userWantsToSeeSubscriptionPlans() }
        }
    }
    
    
    @MainActor
    func userConfirmedFromPermuteDeviceExpirationView(ownedCryptoId: ObvCryptoId, identifierOfDeviceToKeepActive: Data, identifierOfDeviceWithoutExpiration: Data) async {
        guard presentedViewController is PermuteDeviceExpirationHostingViewController else { assertionFailure(); return }
        presentedViewController?.dismiss(animated: true) { [weak self] in
            Task { [weak self] in
                try? await self?.obvEngine.requestSettingUnexpiringDevice(ownedCryptoId: ownedCryptoId, deviceIdentifier: identifierOfDeviceToKeepActive)
            }
        }
    }

    
}


// MARK: - SingleOwnedIdentityViewActionsDelegate

extension SingleOwnedIdentityFlowViewController {
    
    /// We are about to show a ViewController allowing to edit the owned identity.
    /// We load a new instance of the PersistedObvOwnedIdentity in a child view context: we want to prevent the view to be refreshed while the user is editing it.
    /// Not doing so would reset the edited text field if a message is received in the mean time (since this refreshes the view context).
    @MainActor
    func userWantsToEditOwnedIdentity(ownedCryptoId: ObvCryptoId) async {
        guard ownedCryptoId == ownedIdentity.cryptoId else { assertionFailure(); return }
        let childViewContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        childViewContext.parent = ObvStack.shared.viewContext
        childViewContext.automaticallyMergesChangesFromParent = false
        guard let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedIdentity.cryptoId, within: childViewContext) else { assertionFailure(); return }
        editedOwnedIdentity = SingleIdentity(ownedIdentity: ownedIdentity)
        let view = EditSingleOwnedIdentityNavigationView(
            editionType: .edition,
            singleIdentity: editedOwnedIdentity!,
            userConfirmedPublishAction: { [weak self] in
                Task { await self?.userWantsToPublishEditedOwnedIdentity() }
            },
            userWantsToUnbindFromKeycloakServer: { [weak self] ownedCryptoId in
                Task { await self?.userWantsToUnbindFromKeycloakServer(ownedCryptoId: ownedCryptoId) }
            },
            dismissAction: { [weak self] in
                Task { await self?.userWantsToDismissEditSingleIdentityView() }
            })
        let vc = UIHostingController(rootView: view)
        present(vc, animated: true)
    }
    

    @MainActor
    func userWantsToSeeSubscriptionPlans() async {
        let model = SubscriptionPlansViewModel(
            ownedCryptoId: ownedIdentity.cryptoId,
            showFreePlanIfAvailable: true)
        let view = SubscriptionPlansView(model: model, actions: self, dismissActions: self)
        let vc = UIHostingController(rootView: view)
        self.present(vc, animated: true)
    }
    
    
    @MainActor
    func userWantsToRefreshSubscriptionStatus() async {
        let ownedCryptoId = self.ownedCryptoId
        showHUD(type: .spinner)
        do {
            _ = try await obvEngine.refreshAPIPermissions(of: ownedCryptoId)
            showHUD(type: .checkmark)
        } catch {
            showHUD(type: .xmark)
        }
        await suspendDuringTimeInterval(1.5)
        hideHUD()
    }

    
    // MARK: - OwnedDevicesCardViewActionsDelegate
    
    @MainActor
    func userWantsToNavigateToListOfContactDevicesView(ownedCryptoId: ObvCryptoId) async {
        
        guard self.ownedIdentity.cryptoId == ownedCryptoId else { assertionFailure(); return }
        
        let view = OwnedDevicesListView(
            model: ownedIdentity,
            actions: self)
        
        let vc = UIHostingController(rootView: view)
        navigationController?.pushViewController(vc, animated: true)

    }

    
    @MainActor
    func userWantsToAddNewDevice(ownedCryptoId: ObvCryptoId) async {
        guard self.ownedIdentity.cryptoId == ownedCryptoId else { assertionFailure(); return }
        await delegate?.userWantsToAddNewDevice(self, ownedCryptoId: ownedCryptoId)
    }
    
}


// MARK: - SubscriptionPlansViewActionsProtocol

extension SingleOwnedIdentityFlowViewController: SubscriptionPlansViewActionsProtocol {
    
    func fetchSubscriptionPlans(for ownedCryptoId: ObvCryptoId, alsoFetchFreePlan: Bool) async throws -> (freePlanIsAvailable: Bool, products: [Product]) {

        // Step 1: Ask the engine (i.e., Olvid's server) whether a free trial is still available for this identity
        let freePlanIsAvailable: Bool
        if alsoFetchFreePlan {
            freePlanIsAvailable = try await obvEngine.queryServerForFreeTrial(for: ownedCryptoId)
        } else {
            freePlanIsAvailable = false
        }

        // Step 2: As StoreKit about available products
        assert(delegate != nil)
        let products = try await delegate?.userRequestedListOfSKProducts() ?? []

        return (freePlanIsAvailable, products)
        
    }
    

    func userWantsToStartFreeTrialNow(ownedCryptoId: ObvCryptoId) async throws -> APIKeyElements {
        let newAPIKeyElements = try await obvEngine.startFreeTrial(for: ownedCryptoId)
        return newAPIKeyElements
    }


    func userWantsToBuy(_ product: Product) async throws -> StoreKitDelegatePurchaseResult {
        guard let delegate else { assertionFailure(); throw ObvError.theDelegateIsNil }
        return try await delegate.userWantsToBuy(product)
    }
    

    func userWantsToRestorePurchases() async throws {
        guard let delegate else { assertionFailure(); throw ObvError.theDelegateIsNil }
        return try await delegate.userWantsToRestorePurchases()
    }

}


// MARK: - SubscriptionPlansViewDismissActionsProtocol

extension SingleOwnedIdentityFlowViewController: SubscriptionPlansViewDismissActionsProtocol {
    
    @MainActor
    func userWantsToDismissSubscriptionPlansView() async {
        presentedViewController?.dismiss(animated: true)
    }
    
    
    @MainActor
    func dismissSubscriptionPlansViewAfterPurchaseWasMade() async {
        presentedViewController?.dismiss(animated: true)
    }
    
}

extension SingleOwnedIdentityFlowViewController {
    
    enum ObvError: Error {
        case theDelegateIsNil
    }
    
}


// MARK: - Strings

extension SingleOwnedIdentityFlowViewController {
    
    struct Strings {
        static let hideThisProfile = NSLocalizedString("HIDE_THIS_IDENTITY", comment: "")
        static let unhideThisProfile = NSLocalizedString("UNHIDE_THIS_IDENTITY", comment: "")
        static let showOwnedIdentityDetails = NSLocalizedString("SHOW_OWNED_IDENTITY_DETAILS", comment: "")
        static let editOwnedIdentityNickname = NSLocalizedString("EDIT_OWNED_IDENTITY_NICKNAME", comment: "")
        struct FailedToHideOwnedIdentityAlert {
            static let title = NSLocalizedString("FAILED_TO_HIDE_OWNED_ID_ALERT_TITLE", comment: "")
            static let message = NSLocalizedString("FAILED_TO_HIDE_OWNED_ID_ALERT_MESSAGE", comment: "")
        }
        struct UnhideOwnedIdentityAlert {
            static let title = NSLocalizedString("UNHIDE_OWNED_IDENTITY_ALERT_TITLE", comment: "")
            static let message = NSLocalizedString("UNHIDE_OWNED_IDENTITY_ALERT_MESSAGE", comment: "")
            static let actionStayHidden = NSLocalizedString("UNHIDE_OWNED_IDENTITY_ALERT_ACTION_STAY_HIDDEN", comment: "")
            static let actionUnhide = NSLocalizedString("UNHIDE_OWNED_IDENTITY_ALERT_ACTION_UNHIDE", comment: "")
        }
        struct AtLeastOneUnhiddenProfileMustExistAlert {
            static let title = NSLocalizedString("AT_LEAST_ONE_UNHIDDEN_PROFILE_MUST_EXIST_TITLE", comment: "")
            static let message = NSLocalizedString("AT_LEAST_ONE_UNHIDDEN_PROFILE_MUST_EXIST_MESSAGE", comment: "")
            static let actionAddProfile = NSLocalizedString("ADD_OWNED_IDENTITY", comment: "")
        }
        struct AlertForEditingNickname {
            static let title = NSLocalizedString("ALERT_FOR_EDITING_NICKNAME_TITLE", comment: "")
            static let message = NSLocalizedString("ALERT_FOR_EDITING_NICKNAME_MESSAGE", comment: "")
        }
    }
    
}




fileprivate final class SingleOwnedIdentityViewActions: SingleOwnedIdentityViewActionsDelegate {
    
    weak var delegate: SingleOwnedIdentityViewActionsDelegate?

    func userWantsToEditOwnedIdentity(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        await delegate?.userWantsToEditOwnedIdentity(ownedCryptoId: ownedCryptoId)
    }

    func userWantsToSeeSubscriptionPlans() async {
        await delegate?.userWantsToSeeSubscriptionPlans()
    }
    
    func userWantsToRefreshSubscriptionStatus() async {
        await delegate?.userWantsToRefreshSubscriptionStatus()
    }
    
    func userWantsToNavigateToListOfContactDevicesView(ownedCryptoId: ObvCryptoId) async {
        await delegate?.userWantsToNavigateToListOfContactDevicesView(ownedCryptoId: ownedCryptoId)
    }
    
    func userWantsToReactivateThisDevice(ownedCryptoId: ObvCryptoId) async {
        await delegate?.userWantsToReactivateThisDevice(ownedCryptoId: ownedCryptoId)
    }
    
    func userWantsToAddNewDevice(ownedCryptoId: ObvCryptoId) async {
        await delegate?.userWantsToAddNewDevice(ownedCryptoId: ownedCryptoId)
    }
}
