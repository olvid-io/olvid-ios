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
import os.log
import UserNotifications
import ObvEngine
import ObvTypes
import MobileCoreServices
import CloudKit
import AppAuth
import SwiftUI
import OlvidUtils
import AVFoundation

class OnboardingFlowViewController: UIViewController, OlvidURLHandler, ObvErrorMaker {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: OnboardingFlowViewController.self))
    static let errorDomain = "OnboardingFlowViewController"

    private let obvEngine: ObvEngine

    private var notificationCenterTokens = [NSObjectProtocol]()
    private var flowNavigationController: UINavigationController?
    private var photoURL: URL? = nil
    private var keycloakState: ObvKeycloakState?
    @Atomic var allCloudOperationsAreCancelled: Bool = false

    weak var delegate: OnboardingFlowViewControllerDelegate?
    private weak var appBackupDelegate: AppBackupDelegate?

    // MARK: - Initializers

    init(obvEngine: ObvEngine, appBackupDelegate: AppBackupDelegate?) {
        self.obvEngine = obvEngine
        self.appBackupDelegate = appBackupDelegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("die") }

    deinit {
        notificationCenterTokens.forEach {
            NotificationCenter.default.removeObserver($0)
        }
    }

    // MARK: - Computed properties

    /// Certain Olvid URLs cannot be used until the user has created her owned identity.
    /// Yet, these values are typically set when the new user scans (or tap) a deep link during the onboarding process.
    /// We keep the last scanned (or tapped) one here until an owned identity is created.
    private var externalOlvidURL: OlvidURL? {
        didSet {
            externalOlvidURLIsAvailable()
        }
    }

    private var externalKeycloakConfig: KeycloakConfiguration? {
        didSet {
            newKeycloakConfigIsAvailable()
        }
    }

    /// Only set when dealing with an *unmanaged* identity creation
    private var unmanagedIdentityDetails: ObvIdentityCoreDetails? = nil

    /// Only set when dealing with an *unmanaged* identity creation
    private var serverAndAPIKey: ServerAndAPIKey? {
        didSet {
            guard self.serverAndAPIKey != nil else { return }
            newServerAndAPIKeyIsAvailable()
        }
    }

    /// This is set after a user authenticates on a keycloak server. This server returns signed details as well as a information indicating whether
    /// revocation is possible. At that point, if there is a previous identity in the signed details and revocation is not allowed, creating a new identity
    /// won't be possible.
    /// Note that these signed details contains a server and API key.
    private var keycloakDetails: (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff)? {
        didSet {
            guard self.keycloakDetails != nil else { return }
            self.newKeycloakDetailsAvailable()
        }
    }
}


// MARK: - View controller lifecycle

extension OnboardingFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if ObvMessengerSettings.MDM.isConfiguredFromMDM,
           let mdmConfigurationURI = ObvMessengerSettings.MDM.Configuration.uri,
           let olvidURL = OlvidURL(urlRepresentation: mdmConfigurationURI) {
            Task { await NewAppStateManager.shared.handleOlvidURL(olvidURL) }
        } else if let hardcodedAPIKey = ObvMessengerConstants.hardcodedAPIKey {
            self.serverAndAPIKey = ServerAndAPIKey(server: ObvMessengerConstants.serverURL, apiKey: hardcodedAPIKey)
        } else {
            let welcomeScreenVC = WelcomeScreenHostingController(delegate: self)
            flowNavigationController = ObvNavigationController(rootViewController: welcomeScreenVC)
            flowNavigationController!.setNavigationBarHidden(false, animated: false)
            flowNavigationController!.navigationBar.prefersLargeTitles = true
            displayContentController(content: flowNavigationController!)
        }
        
    }
}


// MARK: - Validators

extension OnboardingFlowViewController {

    // Called whenever a new keycloak configuration is available
    private func newKeycloakDetailsAvailable() {
        
        guard let keycloakDetails = self.keycloakDetails else { assertionFailure(); return }
        let singleIdentity = SingleIdentity(keycloakDetails: keycloakDetails)
        
        let completionHandlerOnSave = { [weak self] (identityDetails: ObvIdentityCoreDetails, photoURL: URL?) in
            guard let keycloakCoreDetails = try? keycloakDetails.keycloakUserDetailsAndStuff.getObvIdentityCoreDetails() else { assertionFailure(); return }
            assert(keycloakCoreDetails == identityDetails)
            self?.unmanagedIdentityDetails = nil
            self?.photoURL = photoURL
            self?.tryToCreateOwnedIdentity()
        }

        let displayNameChooserView = DisplayNameChooserView(singleIdentity: singleIdentity, completionHandlerOnSave: completionHandlerOnSave)
        let displayNameChooserVC = UIHostingController(rootView: displayNameChooserView)
        displayNameChooserVC.title = CommonString.Title.myId
        DispatchQueue.main.async { [weak self] in
            self?.flowNavigationController?.pushViewController(displayNameChooserVC, animated: true)
            self?.flowNavigationController!.setNavigationBarHidden(false, animated: true)
        }
    }
    
    // Called whenever a new configuration is set
    private func newServerAndAPIKeyIsAvailable() {
        
        guard let serverAndAPIKey = self.serverAndAPIKey else { return }

        let completionHandlerOnSave = { [weak self] (identityDetails: ObvIdentityCoreDetails, photoURL: URL?) in
            self?.unmanagedIdentityDetails = identityDetails
            self?.photoURL = photoURL
            self?.tryToCreateOwnedIdentity()
        }
        
        let currentVC = flowNavigationController?.children.last
        switch currentVC {
        case nil:

            let welcomeScreenVC = WelcomeScreenHostingController(delegate: self)
            flowNavigationController = ObvNavigationController(rootViewController: welcomeScreenVC)
            flowNavigationController!.setNavigationBarHidden(false, animated: false)
            flowNavigationController!.navigationBar.prefersLargeTitles = true

            DispatchQueue.main.async { [weak self] in
                guard let _self = self else { return }
                _self.displayContentController(content: _self.flowNavigationController!)
            }

        default:
            if currentVC is WelcomeScreenHostingController  || currentVC is IdentityProviderManualConfigurationHostingView {
                
                let singleIdentity: SingleIdentity
                if serverAndAPIKey != ObvMessengerConstants.defaultServerAndAPIKey {
                    singleIdentity = SingleIdentity(serverAndAPIKeyToShow: serverAndAPIKey, identityDetails: self.unmanagedIdentityDetails)
                } else {
                    singleIdentity = SingleIdentity(serverAndAPIKeyToShow: nil, identityDetails: self.unmanagedIdentityDetails)
                }
                let displayNameChooserView = DisplayNameChooserView(singleIdentity: singleIdentity, completionHandlerOnSave: completionHandlerOnSave)
                let displayNameChooserVC = UIHostingController(rootView: displayNameChooserView)
                displayNameChooserVC.title = CommonString.Title.myId
                DispatchQueue.main.async { [weak self] in
                    self?.flowNavigationController?.pushViewController(displayNameChooserVC, animated: true)
                    self?.flowNavigationController!.setNavigationBarHidden(false, animated: true)
                }
                
            }
            
        }
    }
    

    
    private func tryToCreateOwnedIdentity() {

        // We expect exactly one of identityDetails/serverAndAPIKey or keycloakDetails to be non nil at this point
        assert(Bool.xor(self.unmanagedIdentityDetails != nil && self.serverAndAPIKey != nil, self.keycloakDetails != nil))
        
        if let keycloakDetails = self.keycloakDetails {
        
            showHUD(type: .spinner)

            assert(keycloakState != nil)
            
            // We are dealing with an identity server. If there was no previous olvid identity for this user, then we can safely generate a new one. If there was a previous identity, we must make sure that the server allows revocation before trying to create a new identity.

            guard keycloakDetails.keycloakUserDetailsAndStuff.identity == nil || keycloakDetails.keycloakServerRevocationsAndStuff.revocationAllowed else {
                // If this happens, there is an UI bug.
                assertionFailure()
                hideHUD()
                return
            }
            
            DispatchQueue(label: "OwnedIdentityGeneration").async { [weak self] in
                guard let _self = self else { return }
                // The following call discards the signed details. This is intentional. The reason is that these signed details, if they exist, contain an old identity that will be revoked. We do not want to store this identity.
                guard let coreDetails = try? keycloakDetails.keycloakUserDetailsAndStuff.signedUserDetails.userDetails.getCoreDetails() else {
                    assertionFailure()
                    self?.hideHUD()
                    return
                }
                let currentDetails = ObvIdentityDetails(coreDetails: coreDetails, photoURL: _self.photoURL)
                guard let hardcodedAPIKey = ObvMessengerConstants.hardcodedAPIKey else { self?.hideHUD(); assertionFailure(); return }
                
                do {
                    try _self.obvEngine.generateOwnedIdentity(withApiKey: keycloakDetails.keycloakUserDetailsAndStuff.apiKey ?? hardcodedAPIKey,
                                                              onServerURL: keycloakDetails.keycloakUserDetailsAndStuff.server,
                                                              with: currentDetails,
                                                              keycloakState: _self.keycloakState) { result in
                        switch result {
                        case .failure(let error):
                            os_log("Could not generate owned identity: %{public}@", log: _self.log, type: .fault, error.localizedDescription)
                            assertionFailure()
                            return
                        case .success(let ownedCryptoId):
                            self?.ownedIdentityCreatedDuringOnboarding(ownedCryptoIdentity: ownedCryptoId)
                        }
                    }
                } catch {
                    os_log("Could not generate owned identity: %{public}@", log: _self.log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    return
                }
                
            }
            
        } else if let identityDetails = self.unmanagedIdentityDetails, let serverAndAPIKey = self.serverAndAPIKey {
            
            assert(keycloakState == nil)
            
            DispatchQueue(label: "OwnedIdentityGeneration").async { [weak self] in
                guard let _self = self else { return }
                let currentDetails = ObvIdentityDetails(coreDetails: identityDetails, photoURL: _self.photoURL)
                
                do {
                    try _self.obvEngine.generateOwnedIdentity(withApiKey: serverAndAPIKey.apiKey,
                                                              onServerURL: serverAndAPIKey.server,
                                                              with: currentDetails,
                                                              keycloakState: nil) { result in
                        switch result {
                        case .failure(let error):
                            os_log("Could not generate owned identity: %{public}@", log: _self.log, type: .fault, error.localizedDescription)
                            assertionFailure()
                            return
                        case .success(let ownedCryptoId):
                            self?.ownedIdentityCreatedDuringOnboarding(ownedCryptoIdentity: ownedCryptoId)
                        }
                    }
                } catch {
                    os_log("Could not generate owned identity: %{public}@", log: _self.log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    return
                }

            }
            
        } else {
            assertionFailure()
        }
        

    }
    
}

// MARK: - Observing notifications

extension OnboardingFlowViewController {
    
    /// Called just after the creation of the first owned identity during a "standard" onboarding, without backup restore.
    /// At this point, the app database is not in sync with the engine. So we sync it and proceed with the onboarding.
    private func ownedIdentityCreatedDuringOnboarding(ownedCryptoIdentity: ObvCryptoId) {
        
        let log = self.log
        
        ObvMessengerInternalNotification.requestSyncAppDatabasesWithEngine { result in
            
            switch result {
                
            case .failure(let error):
                
                os_log("Could not sync app database with engine database: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
                
            case .success:
                
                ObvStack.shared.performBackgroundTask { [weak self] context in
                    
                    guard let _self = self else { return }
                    
                    do {
                        
                        guard let persistedOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoIdentity, within: context) else {
                            throw Self.makeError(message: "Could not recover owned identity within the app")
                        }
                        
                        let isKeycloakManaged = persistedOwnedIdentity.isKeycloakManaged
                        
                        DispatchQueue.main.async {
                            
                            if isKeycloakManaged {
                                
                                Task {
                                    assert(Thread.isMainThread)
                                    await KeycloakManagerSingleton.shared.registerKeycloakManagedOwnedIdentity(ownedCryptoId: ownedCryptoIdentity, firstKeycloakBinding: true)
                                    do {
                                        try await KeycloakManagerSingleton.shared.uploadOwnIdentity(ownedCryptoId: ownedCryptoIdentity)
                                    } catch {
                                        let alert = UIAlertController(title: Strings.dialogTitleIdentityProviderError,
                                                                      message: Strings.dialogMessageFailedToUploadIdentityToKeycloak,
                                                                      preferredStyle: .alert)
                                        alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
                                        self?.present(alert, animated: true)
                                        return
                                    }
                                    _self.transitionToNotificationsSubscriberScreen()
                                }
                                
                            } else {
                                
                                _self.transitionToNotificationsSubscriberScreen()
                                
                            }
                            
                        }
                        
                    } catch {
                        os_log("Could not recover owned identity within the app: %{public}@", log: log, type: .fault, error.localizedDescription)
                        assertionFailure()
                    }
                    
                }
                
            }
            
        }.postOnDispatchQueue()
        
    }
    
    
    @MainActor
    private func transitionToNotificationsSubscriberScreen() {
        hideHUD()
        // Transition to the next UIViewController
        let vc = AutorisationRequesterHostingController(autorisationCategory: .localNotifications, delegate: self)
        flowNavigationController?.pushViewController(vc, animated: true)
        vc.navigationItem.setHidesBackButton(true, animated: false)
        vc.navigationController?.setNavigationBarHidden(true, animated: false)
    }
    
    @MainActor
    private func transitionToRecordPermissionRequesterScreen() {
        hideHUD()
        // Transition to the next UIViewController
        let vc = AutorisationRequesterHostingController(autorisationCategory: .recordPermission, delegate: self)
        vc.navigationItem.setHidesBackButton(true, animated: false)
        vc.navigationController?.setNavigationBarHidden(true, animated: false)
        flowNavigationController?.pushViewController(vc, animated: true)
    }
    
    @MainActor
    private func transitionToOwnedIdentityGeneratedHostingController() {
        hideHUD()
        // Transition to the next UIViewController
        let vc = OwnedIdentityGeneratedHostingController(startUsingOlvidAction: { [weak self] in self?.startUsingOlvid() })
        vc.navigationItem.setHidesBackButton(true, animated: false)
        vc.navigationController?.setNavigationBarHidden(true, animated: false)
        flowNavigationController?.pushViewController(vc, animated: true)
    }

    private func newKeycloakConfigIsAvailable() {
        assert(Thread.isMainThread)

        guard let externalKeycloakConfig = self.externalKeycloakConfig else { return }

        if let flowNavigationController = self.flowNavigationController {
            
            // If we are not currently showing the appropriate VC to display the new external keycloak config, we reset the navigation stack
            let identityProviderValidationHostingViewController = IdentityProviderValidationHostingViewController(keycloakConfig: externalKeycloakConfig, isConfiguredFromMDM: false, delegate: self)
            if flowNavigationController.viewControllers.first(where: { $0 is IdentityProviderValidationHostingViewController }) != nil {
                guard let welcomeScreenVC = flowNavigationController.viewControllers.first as? WelcomeScreenHostingController else { assertionFailure(); return }
                flowNavigationController.setViewControllers([welcomeScreenVC, identityProviderValidationHostingViewController], animated: true)
            } else {
                flowNavigationController.pushViewController(identityProviderValidationHostingViewController, animated: true)
            }
            
        } else {
            
            // This happens when the Keycloak configuration comes from an MDM. In that case, the flow is no set yet. We set is now.
                let identityProviderValidationHostingViewController = IdentityProviderValidationHostingViewController(keycloakConfig: externalKeycloakConfig, isConfiguredFromMDM: true, delegate: self)
                flowNavigationController = ObvNavigationController(rootViewController: identityProviderValidationHostingViewController)
                flowNavigationController!.setNavigationBarHidden(false, animated: false)
                flowNavigationController!.navigationBar.prefersLargeTitles = true
                displayContentController(content: flowNavigationController!)
            
        }

    }
    
    
    private func externalOlvidURLIsAvailable() {
        let appropriateChildrenVC = flowNavigationController?.children.compactMap({ $0 as? CanShowInformationAboutExternalOlvidURL }) ?? []
        appropriateChildrenVC.forEach { vc in
            vc.showInformationAboutOlvidURL(externalOlvidURL)
        }
    }
    
}


extension OnboardingFlowViewController: AutorisationRequesterHostingControllerDelegate {
    
    @MainActor
    func requestAutorisation(now: Bool, for autorisationCategory: AutorisationRequesterHostingController.AutorisationCategory) async {
        assert(Thread.isMainThread)
        switch autorisationCategory {
        case .localNotifications:
            if now {
                let center = UNUserNotificationCenter.current()
                do {
                    try await center.requestAuthorization(options: [.alert, .sound, .badge])
                } catch {
                    os_log("Could not request authorization for notifications: %@", log: log, type: .error, error.localizedDescription)
                }
            }
            transitionToRecordPermissionRequesterScreen()
        case .recordPermission:
            if now {
                let granted = await AVAudioSession.sharedInstance().requestRecordPermission()
                os_log("User granted access to audio: %@", log: log, type: .error, String(describing: granted))
            }
            transitionToOwnedIdentityGeneratedHostingController()
        }
    }

}


extension OnboardingFlowViewController {
    
    func startUsingOlvid() {
        delegate?.onboardingIsFinished(olvidURLScannedDuringOnboarding: externalOlvidURL)
    }

}


extension OnboardingFlowViewController: WelcomeScreenHostingControllerDelegate {
    
    /// Call from the first view controller (`WelcomeScreenHostingController`) when the user chooses to scan a QR code.
    func userWantsWantsToScanQRCode() {
        assert(Thread.isMainThread)
        let vc = ScannerHostingView(buttonType: .back, delegate: self)
        let nav = UINavigationController(rootViewController: vc)
        // Configure the ScannerHostingView properly for the navigation controller
        vc.title = NSLocalizedString("CONFIGURATION_SCAN", comment: "")
        if #available(iOS 14, *) {
            let ellipsisButton = getConfiguredEllipsisCircleRightBarButtonItem()
            vc.navigationItem.rightBarButtonItem = ellipsisButton
        } else {
            let ellipsisButton = getConfiguredEllipsisCircleRightBarButtonItem(selector: #selector(ellipsisButtonTappedOnScannerHostingView))
            vc.navigationItem.rightBarButtonItem = ellipsisButton
        }
        flowNavigationController?.present(nav, animated: true)
    }
    
    
    func userWantsToClearExternalOlvidURL() {
        self.externalOlvidURL = nil
    }
    
    
    @available(iOS, introduced: 14.0)
    private func getConfiguredEllipsisCircleRightBarButtonItem() -> UIBarButtonItem {
        let menuElements: [UIMenuElement] = [
            UIAction(title: Strings.pasteConfigurationLink,
                     image: UIImage(systemIcon: .docOnClipboardFill)) { [weak self] _ in
                self?.presentedViewController?.dismiss(animated: true) {
                    self?.userWantsToPasteConfigurationURL()
                }
            },
            UIAction(title: Strings.manualConfiguration,
                     image: UIImage(systemIcon: .serverRack)) { [weak self] _ in
                self?.presentedViewController?.dismiss(animated: true) {
                    self?.userChooseToUseManualIdentityProvider()
                }
            },
        ]
        let menu = UIMenu(title: "", children: menuElements)
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let ellipsisImage = UIImage(systemIcon: .ellipsisCircle, withConfiguration: symbolConfiguration)
        let ellipsisButton = UIBarButtonItem(
            title: "Menu",
            image: ellipsisImage,
            primaryAction: nil,
            menu: menu)
        return ellipsisButton
    }
    
    
    @available(iOS, introduced: 13.0, deprecated: 14.0, message: "Used because iOS 13 does not support UIMenu on UIBarButtonItem")
    func getConfiguredEllipsisCircleRightBarButtonItem(selector: Selector) -> UIBarButtonItem {
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let ellipsisImage = UIImage(systemIcon: .ellipsisCircle, withConfiguration: symbolConfiguration)
        let ellipsisButton = UIBarButtonItem(image: ellipsisImage, style: UIBarButtonItem.Style.plain, target: self, action: selector)
        return ellipsisButton
    }


    @available(iOS, introduced: 13.0, deprecated: 14.0, message: "Used because iOS 13 does not support UIMenu on UIBarButtonItem")
    @objc private func ellipsisButtonTappedOnScannerHostingView() {
        userWantsWantsToSeeAdvancedOptions()
    }

    
    func userWantsToContinueAsNewUser() {
        assert(Thread.isMainThread)
        newServerAndAPIKeyIsAvailable()
    }
    
    func userWantsToRestoreBackup() {
        let vc = BackupRestoreViewHostingController()
        vc.delegate = self
        flowNavigationController?.pushViewController(vc, animated: true)
        flowNavigationController?.setNavigationBarHidden(false, animated: true)
    }
    
    
    private func userWantsToPasteConfigurationURL() {
        guard let pastedString = UIPasteboard.general.string,
              let url = URL(string: pastedString),
              let olvidURL = OlvidURL(urlRepresentation: url) else {
            ObvMessengerInternalNotification.pastedStringIsNotValidOlvidURL
                .postOnDispatchQueue()
            return
        }
        Task { await NewAppStateManager.shared.handleOlvidURL(olvidURL) }
    }
    
    
    private func userChooseToUseManualIdentityProvider() {
        assert(Thread.isMainThread)
        let vc = IdentityProviderManualConfigurationHostingView(delegate: self)
        flowNavigationController?.pushViewController(vc, animated: true)
        flowNavigationController!.setNavigationBarHidden(false, animated: true)
    }

    
    @available(iOS, introduced: 13.0, deprecated: 14.0, message: "Used because iOS 13 does not support UIMenu on UIBarButtonItem")
    func userWantsWantsToSeeAdvancedOptions() {
        assert(Thread.isMainThread)
        let alert = UIAlertController(title: CommonString.Word.Advanced, message: nil, preferredStyle: UIDevice.current.actionSheetIfPhoneAndAlertOtherwise)
        alert.addAction(UIAlertAction(title: Strings.pasteLink, style: .default, handler: { [weak self] _ in self?.userWantsToPasteConfigurationURL() }))
        alert.addAction(UIAlertAction(title: Strings.manualConfiguration, style: .default, handler: { [weak self] _ in self?.userChooseToUseManualIdentityProvider() }))
        alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
        present(alert, animated: true)
    }
    
}



// MARK: - IdentityProviderManualConfigurationHostingViewDelegate

extension OnboardingFlowViewController: IdentityProviderManualConfigurationHostingViewDelegate {
    
    func userWantsToValidateManualKeycloakConfiguration(keycloakConfig: KeycloakConfiguration) {
        self.externalKeycloakConfig = keycloakConfig
    }
    
}



// MARK: - IdentityProviderValidationHostingViewControllerDelegate

extension OnboardingFlowViewController: IdentityProviderValidationHostingViewControllerDelegate {
    
    func newKeycloakState(_ keycloakState: ObvKeycloakState) {
        self.keycloakState = keycloakState
    }
    
    func newKeycloakUserDetailsAndStuff(_ keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff) {
        assert(keycloakState != nil) // We expect this to be set at this point
        self.unmanagedIdentityDetails = nil
        self.serverAndAPIKey = nil
        self.keycloakDetails = (keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff)
    }

}



// MARK: - BackupRestoreViewHostingControllerDelegate

extension OnboardingFlowViewController: BackupRestoreViewHostingControllerDelegate {

    func cancelAllCloudOperations() {
        self.allCloudOperationsAreCancelled = true
    }

    func userWantToRestoreBackupFromCloud() async {
        self.allCloudOperationsAreCancelled = false
        guard let backupRestoreViewHostingController = flowNavigationController?.viewControllers.last as? BackupRestoreViewHostingController else {
            assertionFailure()
            return
        }
        let log = self.log
        let container = CKContainer(identifier: ObvMessengerConstants.iCloudContainerIdentifierForEngineBackup)
        do {
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                os_log("The iCloud account isn't available. We cannot restore an uploaded backup.", log: log, type: .fault)
                backupRestoreViewHostingController.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .icloudAccountStatusIsNotAvailable)
                return
            }

            // The iCloud service is available. Look for backups to restore.
            // This iterator only fetches the deviceIdentifierForVendor to load records efficiently.
            let iterator = CloudKitBackupRecordIterator(identifierForVendor: nil,
                                                        resultsLimit: nil,
                                                        desiredKeys: [.deviceIdentifierForVendor])
            // The already seen devices, since we show the latest record by device.
            var seenDevices = Set<UUID>()
            try await withThrowingTaskGroup(of: Void.self) { group in
                for try await records in iterator {
                    guard !allCloudOperationsAreCancelled else { break }
                    for recordWithoutData in records {
                        guard !allCloudOperationsAreCancelled else { break }
                        guard let deviceIdentifierForVendor = recordWithoutData.deviceIdentifierForVendor else {
                            continue
                        }
                        guard !seenDevices.contains(deviceIdentifierForVendor) else {
                            // We have already seen this record.
                            continue
                        }
                        // 'record' should be the latest record for the device 'deviceIdentifierForVendor'
                        seenDevices.insert(deviceIdentifierForVendor)
                        // Launch a task that fetches all the data of the latest record
                        group.addTask {
                            let iteratorWithData = CloudKitBackupRecordIterator(identifierForVendor: deviceIdentifierForVendor,
                                                                                resultsLimit: 1,
                                                                                desiredKeys: nil)
                            guard await !self.allCloudOperationsAreCancelled else { return  }
                            guard let recordWithData = try? await iteratorWithData.next()?.first else {
                                await backupRestoreViewHostingController.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .couldNotRetrieveEncryptedBackupFile)
                                return
                            }
                            guard await !self.allCloudOperationsAreCancelled else { return }
                            guard let asset = recordWithData[.encryptedBackupFile] as? CKAsset,
                                  let url = asset.fileURL else {
                                await backupRestoreViewHostingController.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .couldNotRetrieveEncryptedBackupFile)
                                return
                            }
                            guard await !self.allCloudOperationsAreCancelled else { return }
                            guard let creationDate = recordWithData.creationDate else {
                                await backupRestoreViewHostingController.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .couldNotRetrieveCreationDate)
                                return
                            }
                            guard await !self.allCloudOperationsAreCancelled else { return }
                            guard let deviceName = recordWithData[.deviceName] as? String else {
                                await backupRestoreViewHostingController.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .couldNotRetrieveDeviceName)
                                return
                            }
                            guard await !self.allCloudOperationsAreCancelled else { return }
                            let info = BackupInfo(fileUrl: url, deviceName: deviceName, creationDate: creationDate)
                            DispatchQueue.main.async {
                                backupRestoreViewHostingController.addNewSelectableBackups([info])
                            }
                        }
                    }
                }
            }
            backupRestoreViewHostingController.noMoreCloudBackupToFetch()
        } catch {
            backupRestoreViewHostingController.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .couldNotRetrieveEncryptedBackupFile)
            return
        }
    }
    
    func userWantsToRestoreBackupFromFile() {
        // We do *not* specify ObvUTIUtils.kUTTypeOlvidBackup here. It does not work under Google Drive.
        // And it never works within the simulator.
        let documentTypes = [kUTTypeItem] as [String] // 2020-03-13 Custom UTIs do not work in the simulator
        let documentPicker = UIDocumentPickerViewController(documentTypes: documentTypes, in: .import)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true)
    }
    
    
    func proceedWithBackupFile(atUrl url: URL) {
        assert(Thread.isMainThread)
        let vc = BackupKeyVerifierViewHostingController(obvEngine: obvEngine, backupFileURL: url, dismissAction: {}, dismissThenGenerateNewBackupKeyAction: {})
        vc.delegate = self
        flowNavigationController?.pushViewController(vc, animated: true)
    }
    
}


// MARK: - ScannerHostingViewDelegate

extension OnboardingFlowViewController: ScannerHostingViewDelegate {
    
    func scannerViewActionButtonWasTapped() {
        flowNavigationController?.presentedViewController?.dismiss(animated: true)
    }
    
    
    func qrCodeWasScanned(olvidURL: OlvidURL) {
        flowNavigationController?.presentedViewController?.dismiss(animated: true)
        Task { await NewAppStateManager.shared.handleOlvidURL(olvidURL) }
    }

}


extension OnboardingFlowViewController: UIDocumentPickerDelegate {
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        
        let log = self.log
        
        DispatchQueue(label: "Queue for processing the backup file").async { [weak self] in
            
            guard urls.count == 1 else { return }
            let url = urls.first!
            
            let tempBackupFileUrl: URL
            do {
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                
                guard let fileUTI = ObvUTIUtils.utiOfFile(atURL: url) else {
                    os_log("Could not determine the UTI of the file at URL %{public}@", log: log, type: .fault, url.path)
                    return
                }
                
                guard ObvUTIUtils.uti(fileUTI, conformsTo: ObvUTIUtils.kUTTypeOlvidBackup) else {
                    os_log("The chosen file does not conform to the appropriate type. The file name shoud in with .olvidbackup", log: log, type: .error)
                    return
                }
                
                os_log("A file with an appropriate file extension was returned.", log: log, type: .info)
                            
                // We can copy the backup file at an appropriate location
                
                let tempDir = ObvMessengerConstants.containerURL.forTempFiles.appendingPathComponent("BackupFilesToRestore", isDirectory: true)
                do {
                    if FileManager.default.fileExists(atPath: tempDir.path) {
                        try FileManager.default.removeItem(at: tempDir) // Clean the directory
                    }
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
                } catch let error {
                    os_log("Could not create temporary directory: %{public}@", log: log, type: .fault, error.localizedDescription)
                    return
                }
                
                let fileName = url.lastPathComponent
                tempBackupFileUrl = tempDir.appendingPathComponent(fileName)
                
                debugPrint("Saving the file to \(tempBackupFileUrl.absoluteString)")
                
                do {
                    try FileManager.default.copyItem(at: url, to: tempBackupFileUrl)
                } catch let error {
                    os_log("Could not copy backup file to temp location: %{public}@", log: log, type: .error, error.localizedDescription)
                    return
                }
                
                // Check that the file can be read
                do {
                    _ = try Data(contentsOf: tempBackupFileUrl)
                } catch {
                    os_log("Could not read backup file: %{public}@", log: log, type: .error, error.localizedDescription)
                    return
                }
            }

            // If we reach this point, we can start processing the backup file located at tempBackupFileUrl
            let info = BackupInfo(fileUrl: tempBackupFileUrl, deviceName: nil, creationDate: nil)

            DispatchQueue.main.async {
                guard let backupRestoreViewHostingController = self?.flowNavigationController?.viewControllers.last as? BackupRestoreViewHostingController else { return }
                backupRestoreViewHostingController.addNewSelectableBackups([info])
            }
        }
        
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        assert(Thread.isMainThread)
        (flowNavigationController?.viewControllers.last as? BackupRestoreViewHostingController)?.userCanceledSelectionOfBackupFile()
    }
    
}


extension OnboardingFlowViewController: BackupKeyTesterDelegate {

    @MainActor
    func userWantsToRestoreBackupIdentifiedByRequestUuid(_ backupRequestUuid: UUID) async {
        assert(Thread.isMainThread)
        let backupRestoringWaitingScreenVC = BackupRestoringWaitingScreenHostingController()
        backupRestoringWaitingScreenVC.delegate = self
        flowNavigationController?.pushViewController(backupRestoringWaitingScreenVC, animated: true)
        do {
            try await obvEngine.restoreFullBackup(backupRequestIdentifier: backupRequestUuid)
            backupRestoringWaitingScreenVC.setRestoreSucceeded()
        } catch {
            backupRestoringWaitingScreenVC.setRestoreFailed()
        }
    }
    
}


extension OnboardingFlowViewController: BackupRestoringWaitingScreenViewControllerDelegate {
    
    func userWantsToStartOnboardingFromScratch() {
        assert(Thread.isMainThread)
        flowNavigationController?.popToRootViewController(animated: true)
    }

    /// Activates automatic backups to iCloud.
    /// - Returns: `nil`if this method succeeds, or an error title and message if it fails.
    func userWantsToEnableAutomaticBackup() async -> (title: String, message: String)? {
        guard !ObvMessengerSettings.Backup.isAutomaticBackupEnabled else { return nil }

        // The user wants to activate automatic backup.
        // We must check whether it's possible.
        do {
            guard let accountStatus = try await appBackupDelegate?.getAccountStatus() else {
                return AppBackupManager.CKAccountStatusMessage(.noAccount)
            }
            if case .available = accountStatus {
                obvEngine.userJustActivatedAutomaticBackup()
                ObvMessengerSettings.Backup.isAutomaticBackupEnabled = true
                return nil
            } else {
                guard let titleAndMessage = AppBackupManager.CKAccountStatusMessage(accountStatus) else {
                    assertionFailure()
                    return AppBackupManager.CKAccountStatusMessage(.couldNotDetermine)
                }
                return titleAndMessage
            }
        } catch {
            return AppBackupManager.CKAccountStatusMessage(.noAccount)
        }
    }
    
    /// Called after a backup is successfully restored. In that case, we know that app database is already in
    /// sync with the one within the engine.
    /// We get a "random" owned identity from the app database to finalize the onboarding.
    func ownedIdentityRestoredFromBackupRestore() {
        DispatchQueue.main.async {
            self.transitionToNotificationsSubscriberScreen()
        }
    }

}


// MARK: - OlvidURLHandler

extension OnboardingFlowViewController {
    
    @MainActor
    func handleOlvidURL(_ olvidURL: OlvidURL) {
        assert(Thread.isMainThread)
        switch olvidURL.category {
        case .configuration(serverAndAPIKey: _, betaConfiguration: _, keycloakConfig: let _keycloakConfig):
            if let keycloakConfig = _keycloakConfig {
                externalKeycloakConfig = keycloakConfig
            } else {
                externalOlvidURL = olvidURL
            }
        case .invitation(urlIdentity: _):
            externalOlvidURL = olvidURL
        case .mutualScan(mutualScanURL: _):
            assertionFailure("Cannot happen")
        case .openIdRedirect:
            Task {
                do {
                    _ = try await KeycloakManagerSingleton.shared.resumeExternalUserAgentFlow(with: olvidURL.url)
                    os_log("Successfully resumed the external user agent flow", log: log, type: .info)
                } catch {
                    os_log("Failed to resume external user agent flow: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    return
                }
            }
        }
    }
    
}


extension OnboardingFlowViewController {
    
    struct Strings {
        
        static let qrCodeScannerTitle = NSLocalizedString("SCAN_QR_CODE_CONFIGURATION", comment: "View controller title")
        static let qrCodeScannerExplanation = NSLocalizedString("Please scan an Olvid configuation QR code.", comment: "")
        static let initialConfiguratorVCTitle = NSLocalizedString("Welcome", comment: "View controller title")
        static let localNotificationsSubscriberVCTitle = NSLocalizedString("Almost there!", comment: "View controller title")
        static let ownedIdentityGeneratedVCTitle = NSLocalizedString("Congratulations!", comment: "View controller title")
        
        struct NotServerConfigurationAlert {
            static let title = NSLocalizedString("Bad QR code", comment: "Alert title")
            static let message = NSLocalizedString("This QR code does not allow to configure Olvid. Please use an Olvid configuration QR code.", comment: "Alert message")
        }
        
        struct BadServer {
            static let title = NSLocalizedString("Bad server", comment: "Alert title")
            static let message = NSLocalizedString("The imported API Key seems to be for a different server.", comment: "Alert message")
        }
        
        static let pasteLink = NSLocalizedString("PASTE_CONFIGURATION_LINK", comment: "")
        static let enterAPIKey = NSLocalizedString("ENTER_API_KEY", comment: "")
        static let manualConfiguration = NSLocalizedString("MANUAL_CONFIGURATION", comment: "")

        static let dialogTitleIdentityProviderError = NSLocalizedString("DIALOG_TITLE_IDENTITY_PROVIDER_ERROR", comment: "")
        static let dialogMessageFailedToUploadIdentityToKeycloak = NSLocalizedString("DIALOG_MESSAGE_FAILED_TO_UPLOAD_IDENTITY_TO_KEYCLOAK", comment: "")

        static let pasteConfigurationLink = NSLocalizedString("PASTE_CONFIGURATION_LINK", comment: "")
        
    }
    
}


fileprivate extension Bool {
    
    static func xor(_ a: Bool, _ b: Bool) -> Bool {
        (a && !b) || (!a && b)
    }
    
}
