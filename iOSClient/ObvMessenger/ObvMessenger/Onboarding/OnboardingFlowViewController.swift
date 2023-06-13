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
import ObvEngine
import ObvTypes
import AppAuth
import OlvidUtils
import AVFoundation
import ObvUICoreData


final class OnboardingFlowViewController: UIViewController, OlvidURLHandler, ObvErrorMaker, WelcomeScreenHostingControllerDelegate, DisplayNameChooserViewControllerDelegate, OwnedIdentityGeneratedHostingControllerDelegate, IdentityProviderValidationHostingViewControllerDelegate, ScannerHostingViewDelegate, IdentityProviderManualConfigurationHostingViewDelegate, BackupRestoreViewHostingControllerDelegate, BackupKeyTesterDelegate, BackupRestoringWaitingScreenViewControllerDelegate {

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: OnboardingFlowViewController.self))
    static let errorDomain = "OnboardingFlowViewController"

    private let obvEngine: ObvEngine

    private var flowNavigationController: UINavigationController?
    private var internalState = OnboardingState.initial(externalOlvidURL: nil)

    private weak var appBackupDelegate: AppBackupDelegate?

    weak var delegate: OnboardingFlowViewControllerDelegate?
    
    private var ownedCryptoIdGeneratedOrRestoredDuringOnboarding: ObvCryptoId?

    // MARK: - Init and deinit

    init(obvEngine: ObvEngine, appBackupDelegate: AppBackupDelegate?) {
        self.obvEngine = obvEngine
        self.appBackupDelegate = appBackupDelegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("die") }

    deinit {
        debugPrint("OnboardingFlowViewController deinit")
    }
    
}


// MARK: - View controller lifecycle

extension OnboardingFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        showFirstOnboardingScreen()
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task {
            await showNextOnboardingScreen(animated: true)
        }
    }
    
    /// Sets the appropriate internal state and show the most appropriate first view controller
    private func showFirstOnboardingScreen() {

        var noOwnedIdentityExist = true
        do {
            let ownedIdentities = try PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: ObvStack.shared.viewContext)
            noOwnedIdentityExist = ownedIdentities.isEmpty
        } catch {
            assertionFailure(error.localizedDescription)
            // Continue anyway
        }
        
        // If we find a keycloak configuration thanks to an MDM, we change the inital state.
        // We do *not* use the usual way to handle an Olvid URL so as to distinguish between a keycloak configuration obtained through an MDM, and one that was scanned.
        
        if noOwnedIdentityExist,
           ObvMessengerSettings.MDM.isConfiguredFromMDM,
           let mdmConfigurationURI = ObvMessengerSettings.MDM.Configuration.uri,
           let olvidURL = OlvidURL(urlRepresentation: mdmConfigurationURI) {
            switch olvidURL.category {
            case .configuration(serverAndAPIKey: _, betaConfiguration: _, keycloakConfig: let keycloakConfig):
                if let keycloakConfig {
                    let currentExternalOlvidURL = internalState.externalOlvidURL
                    internalState = .keycloakConfigAvailable(keycloakConfig: keycloakConfig, isConfiguredFromMDM: true, externalOlvidURL: currentExternalOlvidURL)
                }
            default:
                 break
            }
        } else if !noOwnedIdentityExist {
            internalState = .userWantsToChooseUnmanagedDetails(userIsCreatingHerFirstIdentity: false, externalOlvidURL: nil)
        }
        
        // Set an appropriate first view controller to show during onboarding
        
        switch internalState {
        case .keycloakConfigAvailable(let keycloakConfig, let isConfiguredFromMDM, _):
            let identityProviderValidationHostingViewController = IdentityProviderValidationHostingViewController(
                keycloakConfig: keycloakConfig,
                isConfiguredFromMDM: isConfiguredFromMDM,
                delegate: self)
            flowNavigationController = ObvNavigationController(rootViewController: identityProviderValidationHostingViewController)
            flowNavigationController!.setNavigationBarHidden(false, animated: false)
            flowNavigationController!.navigationBar.prefersLargeTitles = true
            displayContentController(content: flowNavigationController!)
        case .userWantsToChooseUnmanagedDetails(let userIsCreatingHerFirstIdentity, _):
            if !userIsCreatingHerFirstIdentity {
                let displayNameChooserVC = DisplayNameChooserViewController(delegate: self)
                flowNavigationController = ObvNavigationController(rootViewController: displayNameChooserVC)
                displayContentController(content: flowNavigationController!)
            } else {
                let welcomeScreenVC = WelcomeScreenHostingController(delegate: self)
                flowNavigationController = ObvNavigationController(rootViewController: welcomeScreenVC)
                flowNavigationController!.setNavigationBarHidden(false, animated: false)
                flowNavigationController!.navigationBar.prefersLargeTitles = true
                displayContentController(content: flowNavigationController!)
            }
        default:
            let welcomeScreenVC = WelcomeScreenHostingController(delegate: self)
            flowNavigationController = ObvNavigationController(rootViewController: welcomeScreenVC)
            flowNavigationController!.setNavigationBarHidden(false, animated: false)
            flowNavigationController!.navigationBar.prefersLargeTitles = true
            displayContentController(content: flowNavigationController!)
        }
                
    }

    
    @MainActor
    private func showNextOnboardingScreen(animated: Bool) async {
        
        if flowNavigationController == nil {
            assertionFailure()
            switch internalState {
            case .userWantsToChooseUnmanagedDetails(userIsCreatingHerFirstIdentity: let userIsCreatingHerFirstIdentity, externalOlvidURL: _):
                if !userIsCreatingHerFirstIdentity {
                    let displayNameChooserVC = DisplayNameChooserViewController(delegate: self)
                    flowNavigationController = ObvNavigationController(rootViewController: displayNameChooserVC)
                    displayContentController(content: flowNavigationController!)
                }
            default:
                break
            }
            if flowNavigationController == nil {
                let welcomeScreenVC = WelcomeScreenHostingController(delegate: self)
                flowNavigationController = ObvNavigationController(rootViewController: welcomeScreenVC)
                flowNavigationController!.setNavigationBarHidden(false, animated: false)
                flowNavigationController!.navigationBar.prefersLargeTitles = true
                displayContentController(content: flowNavigationController!)
            }
        }
        
        guard let flowNavigationController else { assertionFailure(); return }
        
        // We defer the internal state's external olvid URL transmission to the view controllers of the navigation until they are all set.
        
        defer {
            for vc in flowNavigationController.viewControllers.compactMap({ $0 as? CanShowInformationAboutExternalOlvidURL }) {
                vc.showInformationAboutOlvidURL(internalState.externalOlvidURL)
            }
        }
        
        // Setup the navigation view controllers given the current internal state

        switch internalState {
        case .initial:
            if let welcomeScreenVC = flowNavigationController.viewControllers.first(where: { $0 is WelcomeScreenHostingController }) {
                flowNavigationController.popToViewController(welcomeScreenVC, animated: animated)
                return
            } else {
                let welcomeScreenVC = WelcomeScreenHostingController(delegate: self)
                flowNavigationController.setViewControllers([welcomeScreenVC], animated: animated)
                return
            }
        case .userWantsToRestoreBackup:
            let backupRestoreViewVC = BackupRestoreViewHostingController(delegate: self)
            if flowNavigationController.viewControllers.count == 1 && (flowNavigationController.viewControllers.first is WelcomeScreenHostingController || flowNavigationController.viewControllers.first is IdentityProviderValidationHostingViewController) {
                flowNavigationController.pushViewController(backupRestoreViewVC, animated: animated)
                return
            } else {
                assertionFailure()
                let welcomeScreenVC = WelcomeScreenHostingController(delegate: self)
                flowNavigationController.setViewControllers([welcomeScreenVC, backupRestoreViewVC], animated: animated)
                return
            }
        case .userSelectedBackupFileToRestore(backupFileURL: let backupFileURL, _):
            let backupKeyVerifierViewHostingController = BackupKeyVerifierViewHostingController(obvEngine: obvEngine, backupFileURL: backupFileURL, dismissAction: {}, dismissThenGenerateNewBackupKeyAction: {})
            backupKeyVerifierViewHostingController.delegate = self
            if flowNavigationController.viewControllers.last is BackupRestoreViewHostingController {
                flowNavigationController.pushViewController(backupKeyVerifierViewHostingController, animated: animated)
                return
            } else {
                assertionFailure()
                let welcomeScreenVC = WelcomeScreenHostingController(delegate: self)
                flowNavigationController.setViewControllers([welcomeScreenVC, backupKeyVerifierViewHostingController], animated: animated)
                return
            }
        case .userWantsToRestoreBackupNow(backupRequestUuid: let backupRequestUuid, _):
            let backupRestoringWaitingScreenVC = BackupRestoringWaitingScreenHostingController(backupRequestUuid: backupRequestUuid, obvEngine: obvEngine)
            backupRestoringWaitingScreenVC.delegate = self
            assert(appBackupDelegate != nil)
            backupRestoringWaitingScreenVC.appBackupDelegate = appBackupDelegate
            if flowNavigationController.viewControllers.last is BackupKeyVerifierViewHostingController {
                flowNavigationController.pushViewController(backupRestoringWaitingScreenVC, animated: animated)
                return
            } else {
                assertionFailure()
                let welcomeScreenVC = WelcomeScreenHostingController(delegate: self)
                flowNavigationController.setViewControllers([welcomeScreenVC, backupRestoringWaitingScreenVC], animated: animated)
                return
            }
        case .userWantsToManuallyConfigureTheIdentityProvider:
            let identityProviderManualConfigurationHostingView = IdentityProviderManualConfigurationHostingView(delegate: self)
            if flowNavigationController.viewControllers.count == 1 && flowNavigationController.viewControllers.first is WelcomeScreenHostingController {
                flowNavigationController.pushViewController(identityProviderManualConfigurationHostingView, animated: animated)
                return
            } else {
                assertionFailure()
                let welcomeScreenVC = WelcomeScreenHostingController(delegate: self)
                flowNavigationController.setViewControllers([welcomeScreenVC, identityProviderManualConfigurationHostingView], animated: animated)
                return
            }
        case .userWantsToChooseUnmanagedDetails(userIsCreatingHerFirstIdentity: let userIsCreatingHerFirstIdentity, _):
            if userIsCreatingHerFirstIdentity {
                if flowNavigationController.viewControllers.count == 1 && flowNavigationController.viewControllers.first is WelcomeScreenHostingController {
                    let displayNameChooserVC = DisplayNameChooserViewController(delegate: self)
                    flowNavigationController.pushViewController(displayNameChooserVC, animated: animated)
                    return
                } else if flowNavigationController.viewControllers.last is DisplayNameChooserViewController {
                    // Nothing to do
                    return
                } else {
                    assertionFailure()
                    let welcomeScreenVC = WelcomeScreenHostingController(delegate: self)
                    let displayNameChooserVC = DisplayNameChooserViewController(delegate: self)
                    flowNavigationController.setViewControllers([welcomeScreenVC, displayNameChooserVC], animated: animated)
                    return
                }
            } else {
                if flowNavigationController.viewControllers.last is DisplayNameChooserViewController {
                    // Nothing to do
                    return
                } else {
                    assertionFailure()
                    let displayNameChooserVC = DisplayNameChooserViewController(delegate: self)
                    flowNavigationController.setViewControllers([displayNameChooserVC], animated: animated)
                    return
                }
            }
        case .keycloakConfigAvailable(keycloakConfig: let keycloakConfig, isConfiguredFromMDM: let isConfiguredFromMDM, _):
            let identityProviderValidationHostingViewController = IdentityProviderValidationHostingViewController(
                keycloakConfig: keycloakConfig,
                isConfiguredFromMDM: isConfiguredFromMDM,
                delegate: self)
            if isConfiguredFromMDM {
                if flowNavigationController.viewControllers.last is IdentityProviderValidationHostingViewController {
                    // Nothing left to do
                    return
                } else {
                    assertionFailure()
                    flowNavigationController.setViewControllers([identityProviderValidationHostingViewController], animated: animated)
                    flowNavigationController.setNavigationBarHidden(false, animated: false)
                    flowNavigationController.navigationBar.prefersLargeTitles = true
                    return
                }
            } else {
                if flowNavigationController.viewControllers.last is WelcomeScreenHostingController || flowNavigationController.viewControllers.last is IdentityProviderManualConfigurationHostingView {
                    flowNavigationController.pushViewController(identityProviderValidationHostingViewController, animated: animated)
                    return
                } else {
                    assertionFailure()
                    let welcomeScreenVC = WelcomeScreenHostingController(delegate: self)
                    flowNavigationController.setViewControllers([welcomeScreenVC, identityProviderValidationHostingViewController], animated: animated)
                    return
                }
            }
        case .keycloakUserDetailsAndStuffAvailable(let keycloakUserDetailsAndStuff, let keycloakServerRevocationsAndStuff, let keycloakState, _):
            if flowNavigationController.viewControllers.last is IdentityProviderValidationHostingViewController {
                let displayNameChooserVC = DisplayNameChooserViewController(keycloakDetails: (keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff), keycloakState: keycloakState, delegate: self)
                flowNavigationController.pushViewController(displayNameChooserVC, animated: animated)
                return
            } else {
                assertionFailure()
                let welcomeScreenVC = WelcomeScreenHostingController(delegate: self)
                let displayNameChooserVC = DisplayNameChooserViewController(keycloakDetails: (keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff), keycloakState: keycloakState, delegate: self)
                flowNavigationController.setViewControllers([welcomeScreenVC, displayNameChooserVC], animated: animated)
                return
            }
        case .shouldRequestPermission(category: let category, _):
            let vc = AutorisationRequesterHostingController(autorisationCategory: category, delegate: self)
            flowNavigationController.pushViewController(vc, animated: true)
            vc.navigationItem.setHidesBackButton(true, animated: false)
            vc.navigationController?.setNavigationBarHidden(true, animated: false)
        case .finalize:
            if flowNavigationController.viewControllers.last is OwnedIdentityGeneratedHostingController {
                // Nothing to do
            } else {
                let vc = OwnedIdentityGeneratedHostingController(delegate: self)
                vc.navigationItem.setHidesBackButton(true, animated: false)
                vc.navigationController?.setNavigationBarHidden(true, animated: false)
                flowNavigationController.pushViewController(vc, animated: true)
            }
        }
        
    }
    
}

// MARK: - DisplayNameChooserViewControllerDelegate

extension OnboardingFlowViewController {
    
    @MainActor
    func userDidSetUnmanagedDetails(ownedIdentityCoreDetails: ObvIdentityCoreDetails, photoURL: URL?) async {
        guard let serverAndAPIKey = ObvMessengerConstants.defaultServerAndAPIKey else { assertionFailure(); return }
        let currentDetails = ObvIdentityDetails(coreDetails: ownedIdentityCoreDetails, photoURL: photoURL)
        do {
            ownedCryptoIdGeneratedOrRestoredDuringOnboarding = try await obvEngine.generateOwnedIdentity(
                withApiKey: serverAndAPIKey.apiKey,
                onServerURL: serverAndAPIKey.server,
                with: currentDetails,
                keycloakState: nil)
        } catch {
            os_log("Could not generate owned identity: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
        do {
            try await requestSyncAppDatabasesWithEngine()
        } catch {
            os_log("Could not sync engine and app: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }

        await requestNextAutorisationPermissionAfterCreatingTheOwnedIdentity()
        
    }
    
    
    @MainActor
    private func requestNextAutorisationPermissionAfterCreatingTheOwnedIdentity() async {
        let currentExternalOlvidURL = internalState.externalOlvidURL
        if await requestingAutorisationIsNecessary(for: .localNotifications) {
            internalState = .shouldRequestPermission(category: .localNotifications, externalOlvidURL: currentExternalOlvidURL)
        } else if await requestingAutorisationIsNecessary(for: .recordPermission) {
            internalState = .shouldRequestPermission(category: .recordPermission, externalOlvidURL: currentExternalOlvidURL)
        } else {
            internalState = .finalize(externalOlvidURL: currentExternalOlvidURL)
        }
        await showNextOnboardingScreen(animated: true)
    }
    
    
    @MainActor
    func userDidAcceptedKeycloakDetails(keycloakDetails: (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff), keycloakState: ObvKeycloakState, photoURL: URL?) async {
        
        showHUD(type: .spinner)
        defer { hideHUD() }
        
        // We are dealing with an identity server. If there was no previous olvid identity for this user, then we can safely generate a new one. If there was a previous identity, we must make sure that the server allows revocation before trying to create a new identity.
        
        guard keycloakDetails.keycloakUserDetailsAndStuff.identity == nil || keycloakDetails.keycloakServerRevocationsAndStuff.revocationAllowed else {
            // If this happens, there is an UI bug.
            assertionFailure()
            return
        }
        
        // The following call discards the signed details. This is intentional. The reason is that these signed details, if they exist, contain an old identity that will be revoked. We do not want to store this identity.

        guard let coreDetails = try? keycloakDetails.keycloakUserDetailsAndStuff.signedUserDetails.userDetails.getCoreDetails() else {
            assertionFailure()
            return
        }
        
        // We use the hardcoded API here, it will be updated during the keycloak registration
        
        let currentDetails = ObvIdentityDetails(coreDetails: coreDetails, photoURL: photoURL)
        guard let apiKey = ObvMessengerConstants.hardcodedAPIKey else { hideHUD(); assertionFailure(); return }

        // Request the generation of the owned identity and sync it with the app
        
        let ownedCryptoIdentity: ObvCryptoId
        do {
            ownedCryptoIdentity = try await obvEngine.generateOwnedIdentity(withApiKey: apiKey,
                                                                            onServerURL: keycloakDetails.keycloakUserDetailsAndStuff.server,
                                                                            with: currentDetails,
                                                                            keycloakState: keycloakState)
            ownedCryptoIdGeneratedOrRestoredDuringOnboarding = ownedCryptoIdentity
        } catch {
            os_log("Could not generate owned identity: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
        
        do {
            try await requestSyncAppDatabasesWithEngine()
        } catch {
            os_log("Could not sync engine and app: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }

        // The owned identity is created, we register it with the keycloak manager
        
        await KeycloakManagerSingleton.shared.registerKeycloakManagedOwnedIdentity(ownedCryptoId: ownedCryptoIdentity, firstKeycloakBinding: true)
        do {
            try await KeycloakManagerSingleton.shared.uploadOwnIdentity(ownedCryptoId: ownedCryptoIdentity)
        } catch {
            let alert = UIAlertController(title: Strings.dialogTitleIdentityProviderError,
                                          message: Strings.dialogMessageFailedToUploadIdentityToKeycloak,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
            present(alert, animated: true)
            return
        }
        
        // We are done, we can proceed with the next screen
        
        await requestNextAutorisationPermissionAfterCreatingTheOwnedIdentity()
        
    }
    
    
    private func requestSyncAppDatabasesWithEngine() async throws {
        showHUD(type: .spinner)
        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            ObvMessengerInternalNotification.requestSyncAppDatabasesWithEngine { result in
                DispatchQueue.main.async {
                    self?.hideHUD()
                }
                switch result {
                case .failure(let error):
                    continuation.resume(throwing: error)
                case .success:
                    continuation.resume()
                }
            }.postOnDispatchQueue()
        }
    }
        
}


// MARK: - OwnedIdentityGeneratedHostingControllerDelegate

extension OnboardingFlowViewController {
    
    func userWantsToStartUsingOlvid() async {
        assert(ownedCryptoIdGeneratedOrRestoredDuringOnboarding != nil)
        await delegate?.onboardingIsFinished(ownedCryptoIdGeneratedDuringOnboarding: ownedCryptoIdGeneratedOrRestoredDuringOnboarding,
                                             olvidURLScannedDuringOnboarding: internalState.externalOlvidURL)
    }

}


// MARK: - AutorisationRequesterHostingControllerDelegate

extension OnboardingFlowViewController: AutorisationRequesterHostingControllerDelegate {

    @MainActor
    func requestAutorisation(now: Bool, for autorisationCategory: AutorisationRequesterHostingController.AutorisationCategory) async {
        assert(Thread.isMainThread)
        let currentExternalOlvidURL = internalState.externalOlvidURL
        switch autorisationCategory {
        case .localNotifications:
            if now {
                let center = UNUserNotificationCenter.current()
                do {
                    try await center.requestAuthorization(options: [.alert, .sound, .badge])
                } catch {
                    os_log("Could not request authorization for notifications: %@", log: Self.log, type: .error, error.localizedDescription)
                }
            }
            if await requestingAutorisationIsNecessary(for: .recordPermission) {
                internalState = .shouldRequestPermission(category: .recordPermission, externalOlvidURL: currentExternalOlvidURL)
            } else {
                internalState = .finalize(externalOlvidURL: currentExternalOlvidURL)
            }
        case .recordPermission:
            if now {
                let granted = await AVAudioSession.sharedInstance().requestRecordPermission()
                os_log("User granted access to audio: %@", log: Self.log, type: .error, String(describing: granted))
            }
            internalState = .finalize(externalOlvidURL: currentExternalOlvidURL)
        }
        await showNextOnboardingScreen(animated: true)
    }


    @MainActor
    private func requestingAutorisationIsNecessary(for autorisationCategory: AutorisationRequesterHostingController.AutorisationCategory) async -> Bool {
        switch autorisationCategory {
        case .localNotifications:
            let center = UNUserNotificationCenter.current()
            let authorizationStatus = await center.notificationSettings().authorizationStatus
            switch authorizationStatus {
            case .notDetermined, .provisional, .ephemeral:
                return true
            case .denied, .authorized:
                return false
            @unknown default:
                assertionFailure()
                return true
            }
        case .recordPermission:
            let recordPermission = AVAudioSession.sharedInstance().recordPermission
            switch recordPermission {
            case .undetermined:
                return true
            case .denied, .granted:
                return false
            @unknown default:
                return true
            }
        }
    }

}


// MARK: - WelcomeScreenHostingControllerDelegate

extension OnboardingFlowViewController {

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


    func userWantsToClearExternalOlvidURL() async {
        internalState = internalState.addingExternalOlvidURL(nil)
        await showNextOnboardingScreen(animated: true)
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
                    Task { await self?.userChooseToUseManualIdentityProvider() }
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
        assert(Thread.isMainThread)
        let alert = UIAlertController(title: CommonString.Word.Advanced, message: nil, preferredStyle: UIDevice.current.actionSheetIfPhoneAndAlertOtherwise)
        alert.addAction(UIAlertAction(title: Strings.pasteLink, style: .default, handler: { [weak self] _ in self?.userWantsToPasteConfigurationURL() }))
        alert.addAction(UIAlertAction(title: Strings.manualConfiguration, style: .default, handler: { [weak self] _ in Task { await self?.userChooseToUseManualIdentityProvider() } }))
        alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
        present(alert, animated: true)
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

    
    @MainActor
    func userWantsToContinueAsNewUser() async {
        var userIsCreatingHerFirstIdentity = true
        do {
            let ownedIdentities = try PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: ObvStack.shared.viewContext)
            userIsCreatingHerFirstIdentity = ownedIdentities.isEmpty
        } catch {
            assertionFailure(error.localizedDescription)
            // Continue anyway
        }
        let currentExternalOlvidURL = internalState.externalOlvidURL
        self.internalState = .userWantsToChooseUnmanagedDetails(userIsCreatingHerFirstIdentity: userIsCreatingHerFirstIdentity, externalOlvidURL: currentExternalOlvidURL)
        await showNextOnboardingScreen(animated: true)
    }

    
    @MainActor
    func userWantsToRestoreBackup() async {
        let currentExternalOlvidURL = internalState.externalOlvidURL
        internalState = .userWantsToRestoreBackup(externalOlvidURL: currentExternalOlvidURL)
        await showNextOnboardingScreen(animated: true)
    }


    @MainActor
    private func userChooseToUseManualIdentityProvider() async {
        let currentExternalOlvidURL = internalState.externalOlvidURL
        internalState = .userWantsToManuallyConfigureTheIdentityProvider(externalOlvidURL: currentExternalOlvidURL)
        await showNextOnboardingScreen(animated: true)
    }

}



// MARK: - IdentityProviderManualConfigurationHostingViewDelegate

extension OnboardingFlowViewController {

    @MainActor
    func userWantsToValidateManualKeycloakConfiguration(keycloakConfig: KeycloakConfiguration) async {
        let currentExternalOlvidURL = internalState.externalOlvidURL
        internalState = .keycloakConfigAvailable(keycloakConfig: keycloakConfig, isConfiguredFromMDM: false, externalOlvidURL: currentExternalOlvidURL)
        await showNextOnboardingScreen(animated: true)
    }

}



// MARK: - IdentityProviderValidationHostingViewControllerDelegate

extension OnboardingFlowViewController {
    
    func newKeycloakUserDetailsAndStuff(_ keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff, keycloakState: ObvKeycloakState) async {
        let currentExternalOlvidURL = internalState.externalOlvidURL
        internalState = .keycloakUserDetailsAndStuffAvailable(keycloakUserDetailsAndStuff: keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: keycloakServerRevocationsAndStuff, keycloakState: keycloakState, externalOlvidURL: currentExternalOlvidURL)
        await showNextOnboardingScreen(animated: true)
    }
    
}



// MARK: - BackupRestoreViewHostingControllerDelegate

extension OnboardingFlowViewController {

    @MainActor
    func proceedWithBackupFile(atUrl url: URL) async {
        assert(Thread.isMainThread)
        let currentExternalOlvidURL = internalState.externalOlvidURL
        internalState = .userSelectedBackupFileToRestore(backupFileURL: url, externalOlvidURL: currentExternalOlvidURL)
        await showNextOnboardingScreen(animated: true)
    }

}


// MARK: - ScannerHostingViewDelegate

extension OnboardingFlowViewController {

    func scannerViewActionButtonWasTapped() {
        flowNavigationController?.presentedViewController?.dismiss(animated: true)
    }


    func qrCodeWasScanned(olvidURL: OlvidURL) {
        flowNavigationController?.presentedViewController?.dismiss(animated: true)
        Task { await NewAppStateManager.shared.handleOlvidURL(olvidURL) }
    }

}


// MARK: - BackupKeyTesterDelegate

extension OnboardingFlowViewController {

    @MainActor
    func userWantsToRestoreBackupIdentifiedByRequestUuid(_ backupRequestUuid: UUID) async {
        let currentExternalOlvidURL = internalState.externalOlvidURL
        internalState = .userWantsToRestoreBackupNow(backupRequestUuid: backupRequestUuid, externalOlvidURL: currentExternalOlvidURL)
        await showNextOnboardingScreen(animated: true)
    }

}


// MARK: - BackupRestoringWaitingScreenViewControllerDelegate

extension OnboardingFlowViewController {

    @MainActor
    func userWantsToStartOnboardingFromScratch() async {
        assert(Thread.isMainThread)
        let currentExternalOlvidURL = internalState.externalOlvidURL
        internalState = .initial(externalOlvidURL: currentExternalOlvidURL)
        await showNextOnboardingScreen(animated: true)
    }
    
    
    /// Called after a backup is successfully restored. In that case, we know that app database is already in sync with the one within the engine.
    @MainActor
    func ownedIdentityRestoredFromBackupRestore() async {
        ownedCryptoIdGeneratedOrRestoredDuringOnboarding = await getRandomExistingNonHiddenOwnedCryptoId()
        assert(ownedCryptoIdGeneratedOrRestoredDuringOnboarding != nil)
        await requestNextAutorisationPermissionAfterCreatingTheOwnedIdentity()
    }

    
    @MainActor private func getRandomExistingNonHiddenOwnedCryptoId() async -> ObvCryptoId? {
        guard let ownedIdentities = try? PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: ObvStack.shared.viewContext) else { assertionFailure(); return nil }
        return ownedIdentities.first?.cryptoId
    }

}


// MARK: - OlvidURLHandler

extension OnboardingFlowViewController {
    
    @MainActor
    func handleOlvidURL(_ olvidURL: OlvidURL) {
        assert(Thread.isMainThread)
        let currentExternalOlvidURL = internalState.externalOlvidURL
        switch olvidURL.category {
        case .configuration(serverAndAPIKey: _, betaConfiguration: _, keycloakConfig: let _keycloakConfig):
            if let keycloakConfig = _keycloakConfig {
                internalState = .keycloakConfigAvailable(keycloakConfig: keycloakConfig, isConfiguredFromMDM: false, externalOlvidURL: currentExternalOlvidURL)
                Task { await showNextOnboardingScreen(animated: true) }
            } else {
                internalState = internalState.addingExternalOlvidURL(olvidURL)
                Task { await showNextOnboardingScreen(animated: true) }
            }
        case .invitation:
            internalState = internalState.addingExternalOlvidURL(olvidURL)
            Task { await showNextOnboardingScreen(animated: true) }
        case .mutualScan:
            assertionFailure("Cannot happen")
        case .openIdRedirect:
            Task {
                do {
                    _ = try await KeycloakManagerSingleton.shared.resumeExternalUserAgentFlow(with: olvidURL.url)
                    os_log("Successfully resumed the external user agent flow", log: Self.log, type: .info)
                } catch {
                    os_log("Failed to resume external user agent flow: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
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
