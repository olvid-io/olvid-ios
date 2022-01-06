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

class OnboardingFlowViewController: UIViewController, OlvidURLHandler {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))

    weak var delegate: OnboardingFlowViewControllerDelegate?
    private var notificationCenterTokens = [NSObjectProtocol]()
    private var flowNavigationController: UINavigationController?
    
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

    private static let errorDomain = "OnboardingFlowViewController"
    private static func makeError(message: String) -> Error { NSError(domain: OnboardingFlowViewController.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { OnboardingFlowViewController.makeError(message: message) }

    /// These is only set when dealing with an *unmanaged* identity creation
    private var unmanagedIdentityDetails: ObvIdentityCoreDetails? = nil
    private var serverAndAPIKey: ServerAndAPIKey? {
        didSet {
            guard self.serverAndAPIKey != nil else { return }
            newServerAndAPIKeyIsAvailable()
        }
    }
    
    private var photoURL: URL? = nil

    /// This is set after a user authenticates on a keycloak server. This server returns signed details as well as a information indicating whether
    /// revocation is possible. At that point, if there is a previous identity in the signed details and revocation is not allowed, creating a new identity
    /// won't be possible.
    /// Note that these signed details contains a server and API key.
    private var keycloakDetails: (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff)? {
        didSet {
            guard self.keycloakDetails != nil else { return }
            if #available(iOS 13, *) {
                self.newKeycloakDetailsAvailable()
            } else {
                assertionFailure()
            }
        }
    }
    
    private var keycloakState: ObvKeycloakState?

    // MARK: - Initializers
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }
    
    
    required init?(coder aDecoder: NSCoder) { fatalError("die") }

    
    deinit {
        notificationCenterTokens.forEach {
            NotificationCenter.default.removeObserver($0)
        }
    }
    
}


// MARK: - View controller lifecycle

extension OnboardingFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if let hardcodedAPIKey = ObvMessengerConstants.hardcodedAPIKey {
            self.serverAndAPIKey = ServerAndAPIKey(server: ObvMessengerConstants.serverURL, apiKey: hardcodedAPIKey)
        } else {
            let welcomeScreenVC: UIViewController
            if #available(iOS 13, *) {
                welcomeScreenVC = WelcomeScreenHostingController(delegate: self)
            } else {
                welcomeScreenVC = WelcomeScreenViewController()
                (welcomeScreenVC as? WelcomeScreenViewController)?.delegate = self
            }
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
    @available(iOS 13, *)
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
        displayNameChooserVC.title = DisplayNameChooserViewController.Strings.titleMyId
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

            let welcomeScreenVC: UIViewController
            if #available(iOS 13, *) {
                welcomeScreenVC = WelcomeScreenHostingController(delegate: self)
            } else {
                welcomeScreenVC = WelcomeScreenViewController()
                (welcomeScreenVC as? WelcomeScreenViewController)?.delegate = self
            }
            flowNavigationController = ObvNavigationController(rootViewController: welcomeScreenVC)
            flowNavigationController!.setNavigationBarHidden(false, animated: false)
            flowNavigationController!.navigationBar.prefersLargeTitles = true

            DispatchQueue.main.async { [weak self] in
                guard let _self = self else { return }
                _self.displayContentController(content: _self.flowNavigationController!)
            }

        case is QRCodeScannerViewController,
             is WelcomeScreenViewController:

            let displayNameChooserVC: UIViewController
            if #available(iOS 13.0, *) {
                let singleIdentity: SingleIdentity
                if serverAndAPIKey != ObvMessengerConstants.defaultServerAndAPIKey {
                    singleIdentity = SingleIdentity(serverAndAPIKeyToShow: serverAndAPIKey, identityDetails: unmanagedIdentityDetails)
                } else {
                    singleIdentity = SingleIdentity(serverAndAPIKeyToShow: nil, identityDetails: self.unmanagedIdentityDetails)
                }
                let displayNameChooserView = DisplayNameChooserView(singleIdentity: singleIdentity, completionHandlerOnSave: completionHandlerOnSave)
                displayNameChooserVC = UIHostingController(rootView: displayNameChooserView)
                displayNameChooserVC.title = DisplayNameChooserViewController.Strings.titleMyId
            } else {
                let completionHandlerOnSave: (DisplaynameStruct) -> Void = {
                    if let identityDetails = $0.identityDetails {
                        completionHandlerOnSave(identityDetails, $0.photoURL)
                    }
                }
                displayNameChooserVC = DisplayNameChooserViewController(
                    displaynameMaker: DisplaynameStruct(),
                    completionHandlerOnSave: completionHandlerOnSave,
                    serverAndAPIKey: serverAndAPIKey)
            }
            DispatchQueue.main.async { [weak self] in
                self?.flowNavigationController?.pushViewController(displayNameChooserVC, animated: true)
                self?.flowNavigationController!.setNavigationBarHidden(false, animated: true)
            }

        default:
            if #available(iOS 13, *) {
                if currentVC is WelcomeScreenHostingController  || currentVC is IdentityProviderManualConfigurationHostingView {
                    
                    let singleIdentity: SingleIdentity
                    if serverAndAPIKey != ObvMessengerConstants.defaultServerAndAPIKey {
                        singleIdentity = SingleIdentity(serverAndAPIKeyToShow: serverAndAPIKey, identityDetails: self.unmanagedIdentityDetails)
                    } else {
                        singleIdentity = SingleIdentity(serverAndAPIKeyToShow: nil, identityDetails: self.unmanagedIdentityDetails)
                    }
                    let displayNameChooserView = DisplayNameChooserView(singleIdentity: singleIdentity, completionHandlerOnSave: completionHandlerOnSave)
                    let displayNameChooserVC = UIHostingController(rootView: displayNameChooserView)
                    displayNameChooserVC.title = DisplayNameChooserViewController.Strings.titleMyId
                    DispatchQueue.main.async { [weak self] in
                        self?.flowNavigationController?.pushViewController(displayNameChooserVC, animated: true)
                        self?.flowNavigationController!.setNavigationBarHidden(false, animated: true)
                    }
                    
                }
            }
            
        }
    }
    

    
    private func tryToCreateOwnedIdentity() {

        // We expect exactly one of identityDetails/serverAndAPIKey or keycloakDetails to be non nil at this point
        assert(Bool.xor(self.unmanagedIdentityDetails != nil && self.serverAndAPIKey != nil, self.keycloakDetails != nil))
        
        if let keycloakDetails = self.keycloakDetails {
            
            assert(keycloakState != nil)
            
            // We are dealing with an identity server. If there was no previous olvid identity for this user, then we can safely generate a new one. If there was a previous identity, we must make sure that the server allows revocation before trying to create a new identity.

            guard keycloakDetails.keycloakUserDetailsAndStuff.identity == nil || keycloakDetails.keycloakServerRevocationsAndStuff.revocationAllowed else {
                // If this happens, there is an UI bug.
                assertionFailure()
                return
            }
            
            DispatchQueue(label: "OwnedIdentityGeneration").async { [weak self] in
                guard let _self = self else { return }
                // The following call discards the signed details. This is intentional. The reason is that these signed details, if they exist, contain an old identity that will be revoked. We do not want to store this identity.
                guard let coreDetails = try? keycloakDetails.keycloakUserDetailsAndStuff.signedUserDetails.userDetails.getCoreDetails() else {
                    assertionFailure()
                    return
                }
                let currentDetails = ObvIdentityDetails(coreDetails: coreDetails, photoURL: _self.photoURL)
                guard let hardcodedAPIKey = ObvMessengerConstants.hardcodedAPIKey else { assertionFailure(); return }
                
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

    /// Called after a backup is successfully restored. In that case, we know that app database is already in
    /// sync with the one within the engine.
    /// We get a "random" owned identity from the app database to finalize the onboarding.
    private func ownedIdentityRestoredFromBackupRestore() {
        transitionToNotificationsSubscriberScreen()
    }
    
    
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
                            throw _self.makeError(message: "Could not recover owned identity within the app")
                        }
                        
                        if persistedOwnedIdentity.isKeycloakManaged {
                            KeycloakManager.shared.registerKeycloakManagedOwnedIdentity(ownedCryptoId: ownedCryptoIdentity, firstKeycloakBinding: true)
                            KeycloakManager.shared.uploadOwnIdentity(ownedCryptoId: ownedCryptoIdentity) { result in
                                DispatchQueue.main.async { [weak self] in
                                    switch result {
                                    case .failure:
                                        let alert = UIAlertController(title: Strings.dialogTitleIdentityProviderError,
                                                                      message: Strings.dialogMessageFailedToUploadIdentityToKeycloak,
                                                                      preferredStyle: .alert)
                                        alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
                                        self?.present(alert, animated: true)
                                    case .success:
                                        break
                                    }
                                }
                            }
                        }
                        
                        _self.transitionToNotificationsSubscriberScreen()
                        
                    } catch {
                        os_log("Could not recover owned identity within the app: %{public}@", log: log, type: .fault, error.localizedDescription)
                        assertionFailure()
                    }
                    
                }
                
            }
            
        }.postOnDispatchQueue()
        
    }
    
    
    private func transitionToNotificationsSubscriberScreen() {
        
        // Transition to the next UIViewController
        DispatchQueue.main.async { [weak self] in
            if #available(iOS 13, *) {
                let vc = UserNotificationsSubscriberHostingController(subscribeToLocalNotificationsAction: { [weak self] in
                    self?.subscribeToLocalNotifications()
                })
                vc.navigationItem.setHidesBackButton(true, animated: false)
                vc.navigationController?.setNavigationBarHidden(true, animated: false)
                self?.flowNavigationController?.pushViewController(vc, animated: true)
            } else {
                let localNotificationsSubscriberVC = LocalNotificationsSubscriberViewController()
                localNotificationsSubscriberVC.delegate = self
                localNotificationsSubscriberVC.title = Strings.localNotificationsSubscriberVCTitle
                localNotificationsSubscriberVC.navigationItem.setHidesBackButton(true, animated: false)
                self?.flowNavigationController?.pushViewController(localNotificationsSubscriberVC, animated: true)
            }
        }

    }
    
    
    private func newKeycloakConfigIsAvailable() {
        assert(Thread.isMainThread)
        guard let flowNavigationController = self.flowNavigationController else { assertionFailure(); return }
        // If we are not currently showing the appropriate VC to display the new external keycloak config, we reset the navigation stack
        guard let externalKeycloakConfig = self.externalKeycloakConfig else { return }
        if #available(iOS 13, *) {
            let identityProviderValidationHostingViewController = IdentityProviderValidationHostingViewController(keycloakConfig: externalKeycloakConfig, delegate: self)
            if flowNavigationController.viewControllers.first(where: { $0 is IdentityProviderValidationHostingViewController }) != nil {
                guard let welcomeScreenVC = flowNavigationController.viewControllers.first as? WelcomeScreenHostingController else { assertionFailure(); return }
                flowNavigationController.setViewControllers([welcomeScreenVC, identityProviderValidationHostingViewController], animated: true)
            } else {
                flowNavigationController.pushViewController(identityProviderValidationHostingViewController, animated: true)
            }
        }

    }
    
    
    private func externalOlvidURLIsAvailable() {
        let appropriateChildrenVC = flowNavigationController?.children.compactMap({ $0 as? CanShowInformationAboutExternalOlvidURL }) ?? []
        appropriateChildrenVC.forEach { vc in
            vc.showInformationAboutOlvidURL(externalOlvidURL)
        }
    }
    
}


extension OnboardingFlowViewController: LocalNotificationsSubscriberViewControllerDelegate {
    
    func subscribeToLocalNotifications() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] (granted, error) in
            
            guard let _self = self else { return }
            
            guard error == nil else {
                os_log("Could not request authorization for notifications: %@", log: _self.log, type: .error, error!.localizedDescription)
                return
            }
            
            DispatchQueue.main.async {
                if #available(iOS 13, *) {
                    let vc = OwnedIdentityGeneratedHostingController(startUsingOlvidAction: { [weak self] in self?.startUsingOlvid() })
                    _self.flowNavigationController?.pushViewController(vc, animated: true)
                } else {
                    _self.startUsingOlvid()
                }
            }
        }
        
    }

}


extension OnboardingFlowViewController: OwnedIdentityGeneratedViewControllerDelegate {
    
    func startUsingOlvid() {
        delegate?.onboardingIsFinished(olvidURLScannedDuringOnboarding: externalOlvidURL)
    }

}


extension OnboardingFlowViewController: WelcomeScrenViewControllerDelegate, WelcomeScreenHostingControllerDelegate {
    
    /// Call from the first view controller (`WelcomeScreenHostingController`) when the user chooses to scan a QR code.
    @available(iOS 13, *)
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
        if #available(iOS 13, *) {
            let vc = BackupRestoreViewHostingController()
            vc.delegate = self
            flowNavigationController?.pushViewController(vc, animated: true)
            flowNavigationController!.setNavigationBarHidden(false, animated: true)
        } else {
            let backupRestoreVC = BackupRestoreViewController()
            backupRestoreVC.delegate = self
            flowNavigationController?.pushViewController(backupRestoreVC, animated: true)
            flowNavigationController!.setNavigationBarHidden(false, animated: true)
        }
    }
    
    
    private func userWantsToPasteConfigurationURL() {
        guard let pastedString = UIPasteboard.general.string,
              let url = URL(string: pastedString),
              let olvidURL = OlvidURL(urlRepresentation: url) else {
            ObvMessengerInternalNotification.pastedStringIsNotValidOlvidURL
                .postOnDispatchQueue()
            return
        }
        AppStateManager.shared.handleOlvidURL(olvidURL)
    }
    
    
    private func userChooseToUseManualIdentityProvider() {
        assert(Thread.isMainThread)
        if #available(iOS 13, *) {
            let vc = IdentityProviderManualConfigurationHostingView(delegate: self)
            flowNavigationController?.pushViewController(vc, animated: true)
            flowNavigationController!.setNavigationBarHidden(false, animated: true)
        } else {
            assertionFailure()
        }
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

@available(iOS 13, *)
extension OnboardingFlowViewController: IdentityProviderManualConfigurationHostingViewDelegate {
    
    func userWantsToValidateManualKeycloakConfiguration(keycloakConfig: KeycloakConfiguration) {
        self.externalKeycloakConfig = keycloakConfig
    }
    
}



// MARK: - IdentityProviderValidationHostingViewControllerDelegate

@available(iOS 13, *)
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

@available(iOS 13, *)
extension OnboardingFlowViewController: BackupRestoreViewHostingControllerDelegate {
 
    @available(iOS 13, *)
    func userWantToRestoreBackupFromCloud() {
        guard let backupRestoreViewHostingController = flowNavigationController?.viewControllers.last as? BackupRestoreViewHostingController else {
            assertionFailure()
            return
        }
        let log = self.log
        let container = CKContainer(identifier: ObvMessengerConstants.iCloudContainerIdentifierForEngineBackup)
        container.accountStatus { (accountStatus, error) in
            guard accountStatus == .available else {
                os_log("The iCloud account isn't available. We cannot perform restore backup.", log: log, type: .fault)
                backupRestoreViewHostingController.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .icloudAccountStatusIsNotAvailable)
                return
            }
            // The iCloud service is available. Look for a backup to restore
            let predicate = NSPredicate(value: true)
            let query = CKQuery(recordType: AppBackupCoordinator.recordType, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let queryOp = CKQueryOperation(query: query)
            queryOp.resultsLimit = 1
            queryOp.recordFetchedBlock = { record in
                guard let asset = record["encryptedBackupFile"] as? CKAsset else {
                    backupRestoreViewHostingController.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .couldNotRetrieveEncryptedBackupFile)
                    return
                }
                guard let url = asset.fileURL else {
                    backupRestoreViewHostingController.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .couldNotRetrieveEncryptedBackupFile)
                    return
                }
                guard let creationDate = record.creationDate else {
                    backupRestoreViewHostingController.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .couldNotRetrieveCreationDate)
                    return
                }
                DispatchQueue.main.async {
                    backupRestoreViewHostingController.backupFileSelected(atURL: url, creationDate: creationDate)
                }
            }
            queryOp.queryCompletionBlock = { (cursor, error) in
                guard error == nil else {
                    backupRestoreViewHostingController.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .iCloudError(description: error!.localizedDescription))
                    return
                }
                if cursor == nil {
                    backupRestoreViewHostingController.noMoreCloudBackupToFetch()
                }
            }
            container.privateCloudDatabase.add(queryOp)
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
    
    
    @available(iOS 13, *)
    func proceedWithBackupFile(atUrl url: URL) {
        // For iOS 13+ only
        assert(Thread.isMainThread)
        let vc = BackupKeyVerifierViewHostingController(obvEngine: obvEngine, backupFileURL: url, dismissAction: {}, dismissThenGenerateNewBackupKeyAction: {})
        vc.delegate = self
        flowNavigationController?.pushViewController(vc, animated: true)
    }
    
}


extension OnboardingFlowViewController: BackupRestoreViewControllerDelegate {
    
    func userWantsToRestoreBackupFromFileLegacy() {
        // We do *not* specify ObvUTIUtils.kUTTypeOlvidBackup here. It does not work under Google Drive.
        // And it never works within the simulator.
        let documentTypes = [kUTTypeItem] as [String] // 2020-03-13 Custom UTIs do not work in the simulator
        let documentPicker = UIDocumentPickerViewController(documentTypes: documentTypes, in: .import)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true)
    }
 
    
    func userWantToRestoreBackupFromCloudLegacy() {
        guard let backupRestoreViewController = flowNavigationController?.viewControllers.last as? BackupRestoreViewController else {
            assertionFailure()
            return
        }
        let log = self.log
        let container = CKContainer(identifier: ObvMessengerConstants.iCloudContainerIdentifierForEngineBackup)
        container.accountStatus { (accountStatus, error) in
            guard accountStatus == .available else {
                os_log("The iCloud account isn't available. We cannot perform restore backup.", log: log, type: .fault)
                backupRestoreViewController.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .icloudAccountStatusIsNotAvailable)
                return
            }
            // - iCloud is available. Look for a backup to restore
            let predicate = NSPredicate(value: true)
            let query = CKQuery(recordType: AppBackupCoordinator.recordType, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let queryOp = CKQueryOperation(query: query)
            queryOp.resultsLimit = 1
            queryOp.recordFetchedBlock = { record in
                guard let asset = record["encryptedBackupFile"] as? CKAsset else {
                    backupRestoreViewController.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .couldNotRetrieveEncryptedBackupFile)
                    return
                }
                guard let url = asset.fileURL else {
                    backupRestoreViewController.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .couldNotRetrieveEncryptedBackupFile)
                    return
                }
                guard let creationDate = record.creationDate else {
                    backupRestoreViewController.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .couldNotRetrieveCreationDate)
                    return
                }
                DispatchQueue.main.async {
                    backupRestoreViewController.backupFileSelected(atURL: url, creationDate: creationDate)
                }
            }
            queryOp.queryCompletionBlock = { (cursor, error) in
                guard error == nil else {
                    backupRestoreViewController.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .iCloudError(description: error!.localizedDescription))
                    return
                }
                if cursor == nil {
                    backupRestoreViewController.noMoreCloudBackupToFetch()
                }
            }
            container.privateCloudDatabase.add(queryOp)
        }

    }
    
    
    private func debugCustomUTIs() {
        let pathExt = "olvidbackup"
        if let utiArray = UTTypeCreateAllIdentifiersForTag(kUTTagClassFilenameExtension, pathExt as NSString, nil)?.takeRetainedValue() as? [String] {
            print("Have UTIs for .\(pathExt):")
            for uti in utiArray {
                if let dict = UTTypeCopyDeclaration(uti as NSString)?.takeUnretainedValue() as? [String: Any] {
                    print("\(uti) = \(dict)")
                }
            }
        }
    }
    
    
    func proceedWithBackupFileLegacy(atUrl url: URL) {
        assert(Thread.isMainThread)
        if #available(iOS 13, *) {
            assertionFailure()
        } else {
            let backupKeyVerifierVC = BackupKeyVerifierViewController()
            backupKeyVerifierVC.backupFileURL = url
            backupKeyVerifierVC.delegate = self
            flowNavigationController?.pushViewController(backupKeyVerifierVC, animated: true)
        }
    }
    
}

// MARK: - ScannerHostingViewDelegate

@available(iOS 13, *)
extension OnboardingFlowViewController: ScannerHostingViewDelegate {
    
    func scannerViewActionButtonWasTapped() {
        flowNavigationController?.presentedViewController?.dismiss(animated: true)
    }
    
    
    func qrCodeWasScanned(olvidURL: OlvidURL) {
        flowNavigationController?.presentedViewController?.dismiss(animated: true)
        AppStateManager.shared.handleOlvidURL(olvidURL)
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
            
            DispatchQueue.main.async {
                if #available(iOS 13, *) {
                    (self?.flowNavigationController?.viewControllers.last as? BackupRestoreViewHostingController)?.backupFileSelected(atURL: tempBackupFileUrl)
                } else {
                    (self?.flowNavigationController?.viewControllers.last as? BackupRestoreViewController)?.backupFileSelected(atURL: tempBackupFileUrl)
                }
            }
        }
        
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        assert(Thread.isMainThread)
        if #available(iOS 13, *) {
            (flowNavigationController?.viewControllers.last as? BackupRestoreViewHostingController)?.userCanceledSelectionOfBackupFile()
        }
    }
    
}


extension OnboardingFlowViewController: BackupKeyVerifierViewControllerDelegate, BackupKeyTesterDelegate {
    
    func userWantsToRestoreBackupIdentifiedByRequestUuid(_ backupRequestUuid: UUID) {
        let log = self.log
        DispatchQueue.main.async { [weak self] in
            let backupRestoringWaitingScreenVC = BackupRestoringWaitingScreenViewController()
            backupRestoringWaitingScreenVC.delegate = self
            backupRestoringWaitingScreenVC.backupRequestUuid = backupRequestUuid
            self?.flowNavigationController?.pushViewController(backupRestoringWaitingScreenVC, animated: true)
            DispatchQueue(label: "Queue for restoring backup").async {
                do {
                    try self?.obvEngine.restoreFullBackup(backupRequestIdentifier: backupRequestUuid) { result in
                        switch result {
                        case .failure:
                            DispatchQueue.main.async {
                                backupRestoringWaitingScreenVC.setRestoreFailed()
                            }
                        case .success:
                            self?.ownedIdentityRestoredFromBackupRestore()
                            return
                        }
                    }
                } catch {
                    os_log("Could not restore full backup", log: log, type: .error)
                    DispatchQueue.main.async {
                        backupRestoringWaitingScreenVC.setRestoreFailed()
                    }
                }
            }
        }
    }
    
}


extension OnboardingFlowViewController: BackupRestoringWaitingScreenViewControllerDelegate {
    
    func userWantsToStartOnboardingFromScratch() {
        assert(Thread.current == Thread.main)
        flowNavigationController?.popToRootViewController(animated: true)
    }
    
}


// MARK: - OlvidURLHandler

extension OnboardingFlowViewController {
    
    
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
            _ = KeycloakManager.shared.resumeExternalUserAgentFlow(with: olvidURL.url)
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
