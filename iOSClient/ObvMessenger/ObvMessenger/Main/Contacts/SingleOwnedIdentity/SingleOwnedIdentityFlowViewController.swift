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
import os.log
import CoreData
import ObvUICoreData


protocol SingleOwnedIdentityFlowViewControllerDelegate: AnyObject {
    func userWantsToDismissSingleOwnedIdentityFlowViewController(_ viewController: SingleOwnedIdentityFlowViewController)
}


final class SingleOwnedIdentityFlowViewController: UIHostingController<SingleOwnedIdentityView>, SingleOwnedIdentityViewModelDelegate, HiddenProfilePasswordChooserViewControllerDelegate, OwnedIdentityDetailedInfosViewDelegate {

    let ownedIdentity: PersistedObvOwnedIdentity
    let ownedCryptoId: ObvCryptoId
    let obvEngine: ObvEngine
    weak var delegate: SingleOwnedIdentityFlowViewControllerDelegate?
    private var editedOwnedIdentity: SingleIdentity?
    private var availableSubscriptionPlans: AvailableSubscriptionPlans?
    private var apiKeyStatusAndExpiry: APIKeyStatusAndExpiry
    private let model: SingleOwnedIdentityViewModel
    private var rightBarButtonItem: UIBarButtonItem?
    private var legacyConfigureNavigationBarAndObserveNotificationsNeedsToBeCalled = true
    
    private var notificationTokens = [NSObjectProtocol]()
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "SingleOwnedIdentityFlowViewController")

    init(ownedIdentity: PersistedObvOwnedIdentity, obvEngine: ObvEngine) {
        assert(Thread.isMainThread)
        assert(ownedIdentity.managedObjectContext == ObvStack.shared.viewContext)
        self.ownedIdentity = ownedIdentity
        self.ownedCryptoId = ownedIdentity.cryptoId
        self.obvEngine = obvEngine
        self.apiKeyStatusAndExpiry = APIKeyStatusAndExpiry(ownedIdentity: ownedIdentity)
        
        let singleIdentity = SingleIdentity(ownedIdentity: ownedIdentity)
        let model = SingleOwnedIdentityViewModel()
        let view = SingleOwnedIdentityView(singleIdentity: singleIdentity,
                                           apiKeyStatusAndExpiry: apiKeyStatusAndExpiry,
                                           dismissAction: model.dismiss,
                                           editOwnedIdentityAction: model.userWantsToEditOwnedIdentity,
                                           subscriptionPlanAction: model.userWantsToSeeSubscriptionPlans,
                                           refreshStatusAction: model.userWantsToRefreshSubscriptionStatus)
        self.model = model
        super.init(rootView: view)
        self.model.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 14, *) {
            configureNavigationBarAndObserveNotifications()
        } else {
            // ViewDidLoad is not called under iOS 13 (for some reason).
            // We call legacyConfigureNavigationBarAndObserveNotifications() in viewWillAppear()
        }
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if #available(iOS 14, *) {
            // We alread called configureNavigationBarAndObserveNotifications() in viewDidLoad
        } else {
            legacyConfigureNavigationBarAndObserveNotifications()
        }
    }
    
    @available(iOS 14, *)
    private func configureNavigationBarAndObserveNotifications() {
        title = NSLocalizedString("My Id", comment: "")
        
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let ellipsisImage = UIImage(systemIcon: .ellipsisCircle, withConfiguration: symbolConfiguration)
        rightBarButtonItem = UIBarButtonItem(title: "", image: ellipsisImage, menu: provideMenu())
        navigationItem.rightBarButtonItem = rightBarButtonItem
        
        observeNotifications()
    }
    
    
    @available(iOS, introduced: 13, deprecated: 14, message: "Use configureNavigationBarAndObserveNotifications() instead. Remove the legacyConfigureNavigationBarAndObserveNotificationsNeedsToBeCalled variable")
    private func legacyConfigureNavigationBarAndObserveNotifications() {
        guard legacyConfigureNavigationBarAndObserveNotificationsNeedsToBeCalled else { return }
        defer { legacyConfigureNavigationBarAndObserveNotificationsNeedsToBeCalled = false }
        title = NSLocalizedString("My Id", comment: "")
        
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let ellipsisImage = UIImage(systemIcon: .ellipsisCircle, withConfiguration: symbolConfiguration)
        rightBarButtonItem = UIBarButtonItem(image: ellipsisImage, style: UIBarButtonItem.Style.plain, target: self, action: #selector(ellipsisButtonTapped))
        navigationItem.rightBarButtonItem = rightBarButtonItem
        
        observeNotifications()
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
            alert.addAction(UIAlertAction(title: Strings.AtLeastOneUnhiddenProfileMustExistAlert.actionCreateNewProfile, style: .default) { [weak self] _ in
                self?.dismiss(animated: true)
                ObvMessengerInternalNotification.userWantsToCreateNewOwnedIdentity
                    .postOnDispatchQueue()
            })
            alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
            present(alert, animated: true)
            return
        }
        
        let vc = HiddenProfilePasswordChooserViewController(ownedCryptoId: ownedCryptoId, delegate: self)
        vc.modalPresentationStyle = .popover
        if let popover = vc.popoverPresentationController {
            if #available(iOS 15, *) {
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
            }
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
        if #available(iOS 14, *) {
            rightBarButtonItem?.menu = provideMenu()
        }
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
    
        
    nonisolated
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
    
    
    nonisolated
    private func userWantsToStartFreeTrialNow() {
        do {
            try obvEngine.queryServerForFreeTrial(for: ownedIdentity.cryptoId, retrieveAPIKey: true)
        } catch {
            assertionFailure()
        }
    }
    
    
    nonisolated
    private func userWantsToFallbackOnFreeVersion() {
        guard let hardcodedAPIKey = ObvMessengerConstants.hardcodedAPIKey else {
            assertionFailure()
            return
        }
        ObvMessengerInternalNotification.userRequestedNewAPIKeyActivation(ownedCryptoId: ownedCryptoId, apiKey: hardcodedAPIKey)
            .postOnDispatchQueue()
    }
    
    
    nonisolated
    private func userWantsToBuySKProductNow(_ product: SKProduct) {
        SubscriptionNotification.userRequestedToBuySKProduct(skProduct: product)
            .postOnDispatchQueue()
    }
    
    
    nonisolated
    private func userWantsToRestorePurchases() {
        SubscriptionNotification.userRequestedToRestoreAppStorePurchases
            .postOnDispatchQueue()
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

        DispatchQueue(label: "Queue for calling updatePublishedIdentityDetailsOfOwnedIdentity").async {
            do {
                let newDetails = ObvIdentityDetails(coreDetails: newCoreIdentityDetails, photoURL: newProfilPictureURL)
                try obvEngine.updatePublishedIdentityDetailsOfOwnedIdentity(with: ownedCryptoId, with: newDetails)
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.showHUD(type: .text(text: "Failed"))
                    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { self?.hideHUD() }
                }
                return
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.showHUD(type: .checkmark)
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { self?.hideHUD() }
            }
        }
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
    
    
    // MARK: - SingleOwnedIdentityViewModelDelegate
    
    @MainActor
    func dismiss() async {
        delegate?.userWantsToDismissSingleOwnedIdentityFlowViewController(self)
    }
    
    
    @MainActor
    func userWantsToEditOwnedIdentity() async {
        assert(Thread.isMainThread)
        // We are about to show a ViewController allowing to edit the owned identity.
        // We load a new instance of the PersistedObvOwnedIdentity in a child view context: we want to prevent the view to be refreshed while the user is editing it.
        // Not doing so would reset the edited text field if a message is received in the mean time (since this refreshes the view context).
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
    func userWantsToRefreshSubscriptionStatus() async {
        let ownedCryptoId = self.ownedCryptoId
        DispatchQueue(label: "Queue for refreshing API permissions").async { [weak self] in
            try? self?.obvEngine.refreshAPIPermissions(for: ownedCryptoId)
        }
    }
    
    
    @MainActor
    func userWantsToSeeSubscriptionPlans() async {
        self.availableSubscriptionPlans = AvailableSubscriptionPlans(ownedCryptoId: ownedIdentity.cryptoId,
                                                                     fetchSubscriptionPlanAction: fetchSubscriptionPlanAction,
                                                                     userWantsToStartFreeTrialNow: userWantsToStartFreeTrialNow,
                                                                     userWantsToFallbackOnFreeVersion: userWantsToFallbackOnFreeVersion,
                                                                     userWantsToBuy: userWantsToBuySKProductNow,
                                                                     userWantsToRestorePurchases: userWantsToRestorePurchases)
        let view = AvailableSubscriptionPlansView(plans: availableSubscriptionPlans!,
                                                  dismissAction: { [weak self] in Task { self?.dismiss(animated: true) } })
        let vc = UIHostingController(rootView: view)
        self.present(vc, animated: true)
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
            static let actionCreateNewProfile = NSLocalizedString("CREATE_NEW_OWNED_IDENTITY", comment: "")
        }
        struct AlertForEditingNickname {
            static let title = NSLocalizedString("ALERT_FOR_EDITING_NICKNAME_TITLE", comment: "")
            static let message = NSLocalizedString("ALERT_FOR_EDITING_NICKNAME_MESSAGE", comment: "")
        }
    }
    
}


fileprivate protocol SingleOwnedIdentityViewModelDelegate: AnyObject {
    func dismiss() async
    func userWantsToEditOwnedIdentity() async
    func userWantsToSeeSubscriptionPlans() async
    func userWantsToRefreshSubscriptionStatus() async
}


fileprivate final class SingleOwnedIdentityViewModel {
    
    weak var delegate: SingleOwnedIdentityViewModelDelegate?
    
    func dismiss() {
        Task { await delegate?.dismiss() }
    }
    
    func userWantsToEditOwnedIdentity() {
        Task { await delegate?.userWantsToEditOwnedIdentity() }
    }

    func userWantsToSeeSubscriptionPlans() {
        Task { await delegate?.userWantsToSeeSubscriptionPlans() }
    }
    
    func userWantsToRefreshSubscriptionStatus() {
        Task { await delegate?.userWantsToRefreshSubscriptionStatus() }
    }

}
