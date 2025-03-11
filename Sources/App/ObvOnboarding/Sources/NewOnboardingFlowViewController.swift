/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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

import CoreData
import UIKit
import StoreKit
import os.log
import UniformTypeIdentifiers
import AVFoundation
import ObvTypes
import ObvJWS
import AppAuth
import ObvCrypto
import Contacts
import ObvAppCoreConstants
import ObvKeycloakManager
import ObvSubscription
import ObvAppTypes
import ObvScannerHostingView


public protocol NewOnboardingFlowViewControllerDelegate: AnyObject, SubscriptionPlansViewActionsProtocol {
    
    func onboardingIsFinished(onboardingFlow: NewOnboardingFlowViewController, ownedCryptoIdGeneratedDuringOnboarding: ObvCryptoId) async
    
    func onboardingNeedsToPreventPrivacyWindowSceneFromShowingOnNextWillResignActive(onboardingFlow: NewOnboardingFlowViewController) async
    
    func onboardingRequiresToSyncAppDatabasesWithEngine(onboardingFlow: NewOnboardingFlowViewController) async throws
    
    func onboardingRequiresToGenerateOwnedIdentity(onboardingFlow: NewOnboardingFlowViewController, identityDetails: ObvIdentityDetails, nameForCurrentDevice: String, keycloakState: ObvKeycloakState?, customServerAndAPIKey: ServerAndAPIKey?) async throws -> ObvCryptoId
    
    func onboardingRequiresAcceptableCharactersForBackupKeyString() async -> CharacterSet
    
    func onboardingRequiresToRecoverBackupFromEncryptedBackup(onboardingFlow: NewOnboardingFlowViewController, encryptedBackup: Data, backupKey: String) async throws -> (backupRequestIdentifier: UUID, backupDate: Date)
    
    /// Returns the CryptoId of the restore owned identity. When many identities were restored, only one is returned here
    func onboardingRequiresToRestoreBackup(onboardingFlow: NewOnboardingFlowViewController, backupRequestIdentifier: UUID) async throws -> ObvCryptoId
    
    func userWantsToEnableAutomaticBackup(onboardingFlow: NewOnboardingFlowViewController) async throws
    
    func onboardingRequiresToDiscoverKeycloakServer(onboardingFlow: NewOnboardingFlowViewController, keycloakServerURL: URL) async throws -> (jwks: ObvJWKSet, serviceConfig: OIDServiceConfiguration)
        
    func onboardingRequiresKeycloakAuthentication(onboardingFlow: NewOnboardingFlowViewController, keycloakConfiguration: ObvKeycloakConfiguration, keycloakServerKeyAndConfig: (jwks: ObvJWKSet, serviceConfig: OIDServiceConfiguration)) async throws -> (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff, keycloakState: ObvKeycloakState)
    
    func onboardingRequiresKeycloakToSyncAllManagedIdentities() async
    
    func onboardingRequiresToRegisterAndUploadOwnedIdentityToKeycloakServer(ownedCryptoId: ObvCryptoId) async throws
    
    /// Called when the first view of the owned identity transfer protocol flow is shown.
    /// - Parameters:
    ///   - onboardingFlow: The `NewOnboardingFlowViewController` instance calling this method.
    ///   - ownedCryptoId: The `ObvCryptoId` of the owned identity.
    ///   - onAvailableSessionNumber: A block called as soon as the session number is available. In practice, it is called by the engine as soon as the session number is available.
    ///   - onAvailableSASExpectedOnInput: A block called as soon as the SAS is available on this source device. The user on this source device will enter this SAS, we use the value received in this block to make sure it is correct before sending it back to the engine
    func onboardingRequiresToInitiateOwnedIdentityTransferProtocolOnSourceDevice(onboardingFlow: NewOnboardingFlowViewController, ownedCryptoId: ObvCryptoId, onAvailableSessionNumber: @MainActor @escaping (ObvOwnedIdentityTransferSessionNumber) -> Void, onAvailableSASExpectedOnInput: @MainActor @escaping (ObvOwnedIdentityTransferSas, String, UID) -> Void) async throws

    
    /// Called when the user tapped the cancel button while an owned identity transfer protocol is ongoing, or when the user simply closes the onboarding when it is presented
    /// - Parameter controller: The `NewOnboardingFlowViewController` instance calling this method.
    func userWantsToCloseOnboardingAndCancelAnyOwnedTransferProtocol(onboardingFlow: NewOnboardingFlowViewController) async

    func userWishesToFinalizeOwnedIdentityTransferFromSourceDevice(onboardingFlow: NewOnboardingFlowViewController, enteredSAS: ObvOwnedIdentityTransferSas, isTransferRestricted: Bool, deviceToKeepActive: UID?, ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID) async throws

    func onboardingRequiresToInitiateOwnedIdentityTransferProtocolOnTargetDevice(onboardingFlow: NewOnboardingFlowViewController, transferSessionNumber: ObvOwnedIdentityTransferSessionNumber, currentDeviceName: String, onIncorrectTransferSessionNumber: @escaping () -> Void, onAvailableSas: @escaping (UID, ObvOwnedIdentityTransferSas) -> Void) async throws

    
    /// This method gets called during the owned identity transfer flow, on the target device, when the SAS appears (which should be entered on the source device). We call this method to receive appropriate callbacks from the engine when, e.g., the source
    /// sync snapshot is received and processing, and when it is fully processed.
    /// - Parameters:
    ///   - onboardingFlow: The `NewOnboardingFlowViewController` instance calling this method.
    ///   - protocolInstanceUID: The identifier of the protocol running on this target device for transfering the owned identity.
    ///   - onSyncSnapshotReception: A block called by the engine when the snapshot is received from the source device.
    func onboardingIsShowingSasAndExpectingEndOfProtocol(onboardingFlow: NewOnboardingFlowViewController, protocolInstanceUID: UID, onSyncSnapshotReception: @escaping () -> Void, onSuccessfulTransfer: @escaping (ObvCryptoId, Error?) -> Void, onKeycloakAuthenticationNeeded: @escaping (ObvCryptoId, ObvKeycloakConfiguration, ObvKeycloakTransferProofElements) -> Void) async

    
    /// Called at then end of the owned identity transfer flow on this target device.
    /// - Parameters:
    ///   - onboardingFlow: The `NewOnboardingFlowViewController` instance calling this method.
    ///   - userWantsToAddAnotherProfile: `true` when the user wants to start a new flow allowing to add a new profile on this target device, `false` if she just want to dismiss the onboarding.
    func userWantsToDismissOnboardingAfterSuccessfulOwnedIdentityTransferOnThisTargetDevice(onboardingFlow: NewOnboardingFlowViewController, transferredOwnedCryptoId: ObvCryptoId, userWantsToAddAnotherProfile: Bool) async

    
    /// On the source device, when a correct SAS is entered by the user, we want to show a list of owned devices so as to let the user choose which one she wishes to keep active (in case she does not have a multidevice subscription) or just to inform here that a new device will be added.
    func onboardingRequiresToPerformOwnedDeviceDiscoveryNow(for ownedCryptoId: ObvCryptoId) async throws -> (ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult, currentDeviceIdentifier: Data)

    func userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(onboardingFlow: NewOnboardingFlowViewController, keycloakConfiguration: ObvKeycloakConfiguration, transferProofElements: ObvKeycloakTransferProofElements) async throws -> ObvKeycloakTransferProofAndAuthState

    func userProvidesProofOfAuthenticationOnKeycloakServer(onboardingFlow: NewOnboardingFlowViewController, ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID, proof: ObvTypes.ObvKeycloakTransferProofAndAuthState) async throws

    func handleOlvidURL(onboardingFlow: NewOnboardingFlowViewController, olvidURL: OlvidURL) async
    
    func userPastedStringWhichIsNotValidOlvidURL(onboardingFlow: NewOnboardingFlowViewController) async
    
}


/// Structure allowing to encapsulate type definitions
public struct Onboarding {

    /// This onboarding starts in one of these modes:
    /// - The `initialOnboarding` mode is used for the very first onboarding only. MDM configurations are considered in this mode only.
    /// - The `addNewDevice` mode is used when starting an owned identity transfer protocol on a source device (where the owned identity already exist).
    /// - The `addProfile` mode is used on a device where an owned identity already exist, but where the user wants to add an owned identity existing on another device. This thus starts the owned identity transfer protocol on the target device.
    public enum Mode {
        case initialOnboarding(mdmConfig: MDMConfiguration?)
        case addNewDevice(ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, isTransferRestricted: Bool)
        case addProfile
        
        var mdmConfigDuringInitialOnboarding: MDMConfiguration? {
            switch self {
            case .initialOnboarding(let mdmConfig):
                return mdmConfig
            case .addNewDevice, .addProfile:
                return nil
            }
        }
        
    }

    public struct MDMConfiguration {
        
        let keycloakConfiguration: ObvKeycloakConfigurationAndServer
        
        public init(keycloakConfiguration: ObvKeycloakConfigurationAndServer) {
            self.keycloakConfiguration = keycloakConfiguration
        }
        
    }

}


@MainActor
public final class NewOnboardingFlowViewController: UIViewController, NewWelcomeScreenViewControllerDelegate, NewUnmanagedDetailsChooserViewControllerDelegate, NewOwnedIdentityGeneratedViewControllerDelegate, UINavigationControllerDelegate, ChooseBetweenBackupRestoreAndAddThisDeviceViewControllerDelegate, ChooseBackupFileViewControllerDelegate, EnterBackupKeyViewControllerDelegate, WaitingForBackupRestoreViewControllerDelegate, ManagedDetailsViewerViewControllerDelegate, TransfertProtocolSourceCodeDisplayerViewControllerDelegate, AddProfileViewControllerDelegate, CurrentDeviceNameChooserViewControllerDelegate, TransfertProtocolTargetCodeFormViewControllerDelegate, InputSASOnSourceViewControllerDelegate, OwnedIdentityTransferSummaryViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    
    private var internalState = NewOnboardingState.initial
    
    private var flowNavigationController: UINavigationController?
    private var flowNavigationControllerWidthConstraint: NSLayoutConstraint?
    private var flowNavigationControllerHeightConstraint: NSLayoutConstraint?
    
    private static var log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: NewOnboardingFlowViewController.self))
    
    public weak var delegate: NewOnboardingFlowViewControllerDelegate?
    
    /// If, at any point during the onboarding, we receive an `OlvidURL` with a custom API Key and custom Server URL,
    /// we store the value here. At the time we request the generation of the owned identity, we pass this value to our delegate.
    private var customServerAndAPIKey: ServerAndAPIKey?
    
    private let mode: Onboarding.Mode
    
    private var profileKindOfCreatedOwnedIdentity: NewOnboardingState.ProfileKind? = nil
    
    private let directoryForTempFiles: URL
    
    public init(logSubsystem: String, directoryForTempFiles: URL, mode: Onboarding.Mode) {
        self.mode = mode
        self.directoryForTempFiles = directoryForTempFiles
        super.init(nibName: nil, bundle: nil)
        Self.log = OSLog(subsystem: logSubsystem, category: String(describing: NewOnboardingFlowViewController.self))
    }
    
    required init?(coder aDecoder: NSCoder) { fatalError("die") }
    
    private var requestKeycloakSyncOnDeinit = true
    
    deinit {
        if requestKeycloakSyncOnDeinit {
            guard let delegate else { return }
            Task {
                await delegate.onboardingRequiresKeycloakToSyncAllManagedIdentities()
            }
        }
        debugPrint("NewOnboardingFlowViewController deinit")
    }
    
    private var isTransferRestricted: Bool? {
        switch self.mode {
        case .addNewDevice(_, _, isTransferRestricted: let isTransferRestricted):
            return isTransferRestricted
        case .initialOnboarding,
                .addProfile:
            assertionFailure()
            return nil
        }
    }
    
    
    // MARK: - View controller lifecycle
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor(named: "OnboardingBackgroundColor")
        showFirstOnboardingScreen()
        self.presentationController?.delegate = self
    }
    
    
    /// Called by the `MetaFlowController` when an owned identity transfer protocol fails
    @MainActor
    public func anOwnedIdentityTransferProtocolFailed(ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID, error: Error) async {
        guard protocolInstanceUID == internalState.ownedIdentityTransferProtocolInstanceUID || internalState.userIsEnteringTransferCode else { assertionFailure(); return }
        internalState = .showOwnedIdentityTransferFailed(error: error)
        await showNextOnboardingScreen(animated: true)
    }
    
    
    private var defaultShowCloseButton: Bool {
        switch mode {
        case .initialOnboarding:
            return false
        case .addNewDevice, .addProfile:
            return true
        }
    }
    
    
    /// Sets the appropriate internal state and show the most appropriate first view controller
    private func showFirstOnboardingScreen() {
        
        // Set an appropriate first view controller to show during onboarding
        
        let rootViewController: UIViewController
        
        switch mode {
            
        case .initialOnboarding(mdmConfig: _):
            
            // Even when we have an MDM configuration, we show the standard Welcome screen.
            // If the user taps on the button allowing to create a new profile, we
            // apply the mdm configuration if there is one. Otherwise, we lead the user to the
            // screen allowing to freely choose her given name and family name.
            // See the delegate method lower in this file:
            // NewOnboardingFlowViewController.userWantsToLeaveWelcomeScreenAndHasNoOlvidProfileYet(controller:)
            
            rootViewController = NewWelcomeScreenViewController(delegate: self, showCloseButton: defaultShowCloseButton)
            
        case .addNewDevice(ownedCryptoId: let ownedCryptoId, ownedDetails: let ownedDetails, isTransferRestricted: let isTransferRestricted):
            
            if isTransferRestricted {
                // This only happens when the profile is keycloak managed.
                // The user will be unable to transfer their identity to a new device unless they can successfully authenticate with the Keycloak server
                // so we display a warning about this.
                rootViewController = ProtectedTransferWarningViewController(delegate: self)
            } else {
                rootViewController = TransfertProtocolSourceCodeDisplayerViewController(
                    model: .init(ownedCryptoId: ownedCryptoId, ownedDetails: ownedDetails),
                    delegate: self)
            }
            
        case .addProfile:
            
            rootViewController = AddProfileViewController(showCloseButton: defaultShowCloseButton, delegate: self)
            
        }
        
        flowNavigationController = UINavigationController(rootViewController: rootViewController)
        flowNavigationController!.delegate = self
        flowNavigationController!.setNavigationBarHidden(false, animated: false)
        flowNavigationController!.navigationBar.prefersLargeTitles = true
        displayFlowNavigationController(flowNavigationController!)
        
    }
    
    
    private func userDidCancelOwnedIdentityTransferProtocol() async {
        await delegate?.userWantsToCloseOnboardingAndCancelAnyOwnedTransferProtocol(onboardingFlow: self)
        switch mode {
        case .initialOnboarding:
            // Go back to the initial screen of the onboarding
            internalState = .initial
            await showNextOnboardingScreen(animated: true)
        case .addNewDevice, .addProfile:
            // This flow has been dismissed by the meta flow controller
            break
        }
    }
    
    
    private func showNextOnboardingScreen(animated: Bool) async {
        
        guard let flowNavigationController else { assertionFailure(); return }
        
        // Dismiss any presented view controller
        
        presentedViewController?.dismiss(animated: true)
        
        // Setup the navigation view controllers given the current internal state
        
        switch internalState {
        case .initial:
            if flowNavigationController.viewControllers.first is NewWelcomeScreenViewController {
                flowNavigationController.popToRootViewController(animated: true)
                return
            } else if !flowNavigationController.viewControllers.isEmpty {
                let newViewControllers: [UIViewController] = [NewWelcomeScreenViewController(delegate: self, showCloseButton: defaultShowCloseButton)] + flowNavigationController.viewControllers
                flowNavigationController.setViewControllers(newViewControllers, animated: false)
                flowNavigationController.popToRootViewController(animated: true)
            } else {
                let welcomeScreenVC = NewWelcomeScreenViewController(delegate: self, showCloseButton: defaultShowCloseButton)
                flowNavigationController.setViewControllers([welcomeScreenVC], animated: animated)
                return
            }
        case .userWantsToProceedWithAddingDevice(ownedCryptoId: let ownedCryptoId, ownedDetails: let ownedDetails):
            let vc = TransfertProtocolSourceCodeDisplayerViewController(
                model: .init(ownedCryptoId: ownedCryptoId, ownedDetails: ownedDetails),
                delegate: self)
            flowNavigationController.setViewControllers([vc], animated: animated)
            return
        case .userWantsToChooseUnmanagedDetails:
            if let displayNameChooserVC = flowNavigationController.viewControllers.first(where: { $0 is NewUnmanagedDetailsChooserViewController }) {
                flowNavigationController.popToViewController(displayNameChooserVC, animated: animated)
                return
            } else if let welcomeScreenVC = flowNavigationController.viewControllers.first as? NewWelcomeScreenViewController {
                let displayNameChooserVC = NewUnmanagedDetailsChooserViewController(
                    model: .init(showPositionAndOrganisation: false),
                    delegate: self,
                    showCloseButton: defaultShowCloseButton)
                flowNavigationController.setViewControllers([welcomeScreenVC, displayNameChooserVC], animated: animated)
                return
            } else  if let addProfileVC = flowNavigationController.viewControllers.first as? AddProfileViewController {
                let displayNameChooserVC = NewUnmanagedDetailsChooserViewController(
                    model: .init(showPositionAndOrganisation: false),
                    delegate: self,
                    showCloseButton: defaultShowCloseButton)
                flowNavigationController.setViewControllers([addProfileVC, displayNameChooserVC], animated: animated)
                return
            } else {
                let displayNameChooserVC = NewUnmanagedDetailsChooserViewController(
                    model: .init(showPositionAndOrganisation: false),
                    delegate: self,
                    showCloseButton: defaultShowCloseButton)
                flowNavigationController.setViewControllers([displayNameChooserVC], animated: animated)
                return
            }
        case .keycloakConfigAvailable(keycloakConfiguration: let keycloakConfiguration, isConfiguredFromMDM: let isConfiguredFromMDM):
            var viewControllers = [UIViewController]()
            let welcomeScreenVC = flowNavigationController.viewControllers.first(where: { $0 is NewWelcomeScreenViewController }) ?? NewWelcomeScreenViewController(delegate: self, showCloseButton: defaultShowCloseButton)
            viewControllers.append(welcomeScreenVC)
            if let manualVC = flowNavigationController.viewControllers.first(where: { $0 is NewIdentityProviderManualConfigurationViewController }) {
                viewControllers.append(manualVC)
            }
            let identityProviderValidationVC = IdentityProviderValidationViewController(
                model: .init(keycloakConfiguration: keycloakConfiguration,
                             isConfiguredFromMDM: isConfiguredFromMDM),
                delegate: self)
            viewControllers.append(identityProviderValidationVC)
            flowNavigationController.setViewControllers(viewControllers, animated: animated)
        case .keycloakUserDetailsAndStuffAvailable(let keycloakUserDetailsAndStuff, let keycloakServerRevocationsAndStuff, let keycloakState):
            let managedDetailsViewerVC = ManagedDetailsViewerViewController(
                model: .init(keycloakUserDetailsAndStuff: keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: keycloakServerRevocationsAndStuff),
                keycloakState: keycloakState,
                delegate: self)
            flowNavigationController.pushViewController(managedDetailsViewerVC, animated: true)
        case .userIndicatedSheHasAnExistingProfile:
            let welcomeScreenVC = flowNavigationController.viewControllers.first(where: { $0 is NewWelcomeScreenViewController }) ?? NewWelcomeScreenViewController(delegate: self, showCloseButton: defaultShowCloseButton)
            let chooseVC = flowNavigationController.viewControllers.first(where: { $0 is ChooseBetweenBackupRestoreAndAddThisDeviceViewController }) ?? ChooseBetweenBackupRestoreAndAddThisDeviceViewController(delegate: self)
            flowNavigationController.setViewControllers([welcomeScreenVC, chooseVC], animated: animated)
        case .userWantsToRestoreSomeBackup:
            let welcomeScreenVC = flowNavigationController.viewControllers.first(where: { $0 is NewWelcomeScreenViewController }) ?? NewWelcomeScreenViewController(delegate: self, showCloseButton: defaultShowCloseButton)
            let chooseVC = flowNavigationController.viewControllers.first(where: { $0 is ChooseBetweenBackupRestoreAndAddThisDeviceViewController }) ?? ChooseBetweenBackupRestoreAndAddThisDeviceViewController(delegate: self)
            let chooseBackupFileVC = flowNavigationController.viewControllers.first(where: { $0 is ChooseBackupFileViewController }) ?? ChooseBackupFileViewController(delegate: self)
            flowNavigationController.setViewControllers([welcomeScreenVC, chooseVC, chooseBackupFileVC], animated: animated)
        case .userWantsToRestoreThisEncryptedBackup(encryptedBackup: let encryptedBackup):
            guard let acceptableCharactersForBackupKeyString = await delegate?.onboardingRequiresAcceptableCharactersForBackupKeyString() else { assertionFailure(); return }
            let enterBackupKeyViewController = EnterBackupKeyViewController(
                model: .init(encryptedBackup: encryptedBackup,
                             acceptableCharactersForBackupKeyString: acceptableCharactersForBackupKeyString),
                delegate: self)
            flowNavigationController.pushViewController(enterBackupKeyViewController, animated: true)
        case .userWantsToRestoreThisDecryptedBackup(backupRequestIdentifier: let backupRequestIdentifier):
            let waitingForBackupRestoreVC = WaitingForBackupRestoreViewController(model: .init(backupRequestIdentifier: backupRequestIdentifier), delegate: self)
            // Don't allow the user to go back (and interface button allows to do so if the restore fails)
            flowNavigationController.setViewControllers([waitingForBackupRestoreVC], animated: true)
        case .shouldRequestPermission(profileKind: _, category: let category):
            let vc = NewAutorisationRequesterViewController(autorisationCategory: category, delegate: self)
            flowNavigationController.pushViewController(vc, animated: true)
            return
        case .finalize:
            if flowNavigationController.viewControllers.last is NewOwnedIdentityGeneratedViewController {
                // Nothing to do
            } else {
                let vc = NewOwnedIdentityGeneratedViewController(delegate: self)
                flowNavigationController.pushViewController(vc, animated: true)
            }
            return
        case .userWantsToChooseNameForCurrentDevice:
            let vc = CurrentDeviceNameChooserViewController(model: .init(defaultDeviceName: defaultNameForCurrentDevice), delegate: self, showCloseButton: defaultShowCloseButton)
            flowNavigationController.pushViewController(vc, animated: true)
        case .userWantsToEnterTransferCode(currentDeviceName: _):
            let vc = TransfertProtocolTargetCodeFormViewController(delegate: self)
            flowNavigationController.pushViewController(vc, animated: true)
        case .userWantsToDisplaySasOnThisTargetDevice(currentDeviceName: _, protocolInstanceUID: let protocolInstanceUID, sas: let sas):
            let vc = TransferProtocolTargetShowSasViewController(model: .init(protocolInstanceUID: protocolInstanceUID, sas: sas), delegate: self)
            flowNavigationController.setViewControllers([vc], animated: animated)
        case .successfulTransferWasPerfomed(transferredOwnedCryptoId: let transferredOwnedCryptoId, postTransferError: let postTransferError):
            let vc = SuccessfulTransferConfirmationViewController(model: .init(transferredOwnedCryptoId: transferredOwnedCryptoId, postTransferError: postTransferError), delegate: self)
            flowNavigationController.setViewControllers([vc], animated: animated)
        case .userMustEnterSASOnSourceDevice(sasExpectedOnInput: let sasExpectedOnInput, targetDeviceName: let targetDeviceName, ownedCryptoId: let ownedCryptoId, ownedDetails: let ownedDetails, protocolInstanceUID: let protocolInstanceUID):
            let vc = InputSASOnSourceViewController(model: .init(sasExpectedOnInput: sasExpectedOnInput, targetDeviceName: targetDeviceName, ownedCryptoId: ownedCryptoId, ownedDetails: ownedDetails, protocolInstanceUID: protocolInstanceUID), delegate: self)
            flowNavigationController.setViewControllers([vc], animated: animated)
        case .userMustChooseDeviceToKeepActiveOnSourceDevice(ownedCryptoId: let ownedCryptoId, ownedDetails: let ownedDetails, enteredSAS: let enteredSAS, ownedDeviceDiscoveryResult: let ownedDeviceDiscoveryResult, currentDeviceIdentifier: let currentDeviceIdentifier, targetDeviceName: let targetDeviceName, protocolInstanceUID: let protocolInstanceUID):
            let vc = ChooseDeviceToKeepActiveViewController(
                model: .init(ownedCryptoId: ownedCryptoId, ownedDetails: ownedDetails, enteredSAS: enteredSAS, ownedDeviceDiscoveryResult: ownedDeviceDiscoveryResult, currentDeviceIdentifier: currentDeviceIdentifier, targetDeviceName: targetDeviceName, protocolInstanceUID: protocolInstanceUID),
                delegate: self)
            flowNavigationController.setViewControllers([vc], animated: animated)
        case .finalOwnedIdentityTransferCheckOnSourceDevice(ownedCryptoId: let ownedCryptoId, ownedDetails: let ownedDetails, enteredSAS: let enteredSAS, ownedDeviceDiscoveryResult: let ownedDeviceDiscoveryResult, targetDeviceName: let targetDeviceName, protocolInstanceUID: let protocolInstanceUID, deviceToKeepActive: let deviceToKeepActive):
            guard let isTransferRestricted else { assertionFailure(); return }
            let vc = OwnedIdentityTransferSummaryViewController(
                model: .init(
                    ownedCryptoId: ownedCryptoId,
                    ownedDetails: ownedDetails,
                    enteredSAS: enteredSAS,
                    ownedDeviceDiscoveryResult: ownedDeviceDiscoveryResult,
                    targetDeviceName: targetDeviceName,
                    deviceToKeepActive: deviceToKeepActive,
                    protocolInstanceUID: protocolInstanceUID,
                    isTransferRestricted: isTransferRestricted),
                delegate: self)
            flowNavigationController.pushViewController(vc, animated: animated)
        case .showOwnedIdentityTransferFailed(error: let error):
            let welcomeScreenVC = flowNavigationController.viewControllers.first as? NewWelcomeScreenViewController ?? NewWelcomeScreenViewController(delegate: self, showCloseButton: defaultShowCloseButton)
            let failureVC = OwnedIdentityTransferFailureViewController(model: .init(error: error))
            flowNavigationController.setViewControllers([welcomeScreenVC, failureVC], animated: animated)
        case .userWantsToManuallyConfigureTheIdentityProvider:
            let welcomeScreenVC = flowNavigationController.viewControllers.first as? NewWelcomeScreenViewController ?? NewWelcomeScreenViewController(delegate: self, showCloseButton: defaultShowCloseButton)
            let manualVC = NewIdentityProviderManualConfigurationViewController(delegate: self)
            flowNavigationController.setViewControllers([welcomeScreenVC, manualVC], animated: animated)
        }
    }
    
    // MARK: - Adapting the size of the onboarding screens
    
    private func displayFlowNavigationController(_ flowNavigationController: UINavigationController) {
        assert(flowNavigationController == self.flowNavigationController)
        
        flowNavigationController.willMove(toParent: self)
        addChild(flowNavigationController)
        flowNavigationController.didMove(toParent: self)
        
        view.addSubview(flowNavigationController.view)
        
        // Under iPhone, we want the onboarding to be as large as possible.
        // This is not the case under iPad or Mac, during the first onboarding.
        // If this onboarding is presented (whatever the platform, we want maximum width)
        if traitCollection.userInterfaceIdiom == .phone || self.isBeingPresented {
            flowNavigationController.view.translatesAutoresizingMaskIntoConstraints = true
            flowNavigationController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            flowNavigationController.view.frame = view.bounds
        } else {
            flowNavigationController.view.translatesAutoresizingMaskIntoConstraints = false
            flowNavigationControllerWidthConstraint = flowNavigationController.view.widthAnchor.constraint(equalToConstant: 443)
            flowNavigationControllerHeightConstraint = flowNavigationController.view.heightAnchor.constraint(equalToConstant: 426)
            flowNavigationControllerWidthConstraint?.priority = .defaultHigh // less than the priority on the maximum width
            flowNavigationControllerHeightConstraint?.priority = .defaultHigh // less than the priority on the maximum height
            NSLayoutConstraint.activate([
                flowNavigationController.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                flowNavigationController.view.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                flowNavigationControllerWidthConstraint!,
                flowNavigationControllerHeightConstraint!,
                flowNavigationController.view.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor),
                flowNavigationController.view.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor),
            ])
            flowNavigationController.view.layer.cornerRadius = 12
            flowNavigationController.additionalSafeAreaInsets = .init(top: 20, left: 20, bottom: 40, right: 20)
        }
        
    }
    
    
    // MARK: - UIAdaptivePresentationControllerDelegate
    
    /// This `UIAdaptivePresentationControllerDelegate` delegate gets called when the user dismisses a presented onboarding flow.
    /// In case there was an onboarding flow, we ask our delegate to cancel it.
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let delegate else { return }
        let localSelf = self
        Task {
            await delegate.userWantsToCloseOnboardingAndCancelAnyOwnedTransferProtocol(onboardingFlow: localSelf)
        }
    }
    
    
    // MARK: - NewWelcomeScreenViewControllerDelegate
    
    func userWantsToCloseOnboarding(controller: NewWelcomeScreenViewController) async {
        await delegate?.userWantsToCloseOnboardingAndCancelAnyOwnedTransferProtocol(onboardingFlow: self)
    }
    
    
    func userWantsToLeaveWelcomeScreenAndHasNoOlvidProfileYet(controller: NewWelcomeScreenViewController) async {
        
        // In case we are performing the initial onboarding and there is an MDM configuration, we apply it.
        // Othersise, we send the user to the screen allowing her to choose her given name and family name.
        
        // If an owned identity has already been created, we skip entirely the flow
        if let profileKindOfCreatedOwnedIdentity {
            await requestNextAutorisationPermissionAfterCreatingTheOwnedIdentity(profileKind: profileKindOfCreatedOwnedIdentity)
        } else {
            if let mdmConfig = mode.mdmConfigDuringInitialOnboarding {
                self.internalState = .keycloakConfigAvailable(keycloakConfiguration: mdmConfig.keycloakConfiguration.keycloakConfiguration, isConfiguredFromMDM: true)
            } else {
                self.internalState = .userWantsToChooseUnmanagedDetails
            }
            
            await showNextOnboardingScreen(animated: true)
        }
    }
    
    
    func userWantsToLeaveWelcomeScreenAndHasAnOlvidProfile(controller: NewWelcomeScreenViewController) async {
        self.internalState = .userIndicatedSheHasAnExistingProfile
        await showNextOnboardingScreen(animated: true)
    }
    
    
    // MARK: - NewUnmanagedDetailsChooserViewControllerDelegate
    
    func userWantsToCloseOnboarding(controller: NewUnmanagedDetailsChooserViewController) async {
        await delegate?.userWantsToCloseOnboardingAndCancelAnyOwnedTransferProtocol(onboardingFlow: self)
    }
    
    
    func userDidChooseUnmanagedDetails(controller: NewUnmanagedDetailsChooserViewController, ownedIdentityCoreDetails: ObvIdentityCoreDetails, photo: UIImage?) async {
        
        guard let delegate else { assertionFailure(); return }
        
        // If the user chose a profile picture, save it to disk so that the engine can process it
        
        let photoURL: URL?
        if let photo, let jpegData = photo.jpegData(compressionQuality: 1.0) {
            let filename = [UUID().uuidString, UTType.jpeg.preferredFilenameExtension ?? "jpeg"].joined(separator: ".")
            let filepath = directoryForTempFiles.appendingPathComponent(filename)
            do {
                try jpegData.write(to: filepath)
                photoURL = filepath
            } catch {
                assertionFailure()
                photoURL = nil
            }
        } else {
            photoURL = nil
        }
        
        // Create the details to pass to the engine
        
        let currentDetails = ObvIdentityDetails(coreDetails: ownedIdentityCoreDetails, photoURL: photoURL)
        let ownedCryptoId: ObvCryptoId
        
        // Note that we could have let the user choose a name for her device. We decide not to, for now, and use the device model name
        
        do {
            ownedCryptoId = try await delegate.onboardingRequiresToGenerateOwnedIdentity(
                onboardingFlow: self,
                identityDetails: currentDetails,
                nameForCurrentDevice: defaultNameForCurrentDevice,
                keycloakState: nil,
                customServerAndAPIKey: customServerAndAPIKey)
        } catch {
            os_log("Could not generate owned identity: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
        
        do {
            try await delegate.onboardingRequiresToSyncAppDatabasesWithEngine(onboardingFlow: self)
        } catch {
            os_log("Could not sync engine and app: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
        
        // At the end, the engine will be managing the photo, we can delete the one we store in the temporary folder
        
        if let photoURL {
            try? FileManager.default.removeItem(at: photoURL)
        }
        
        // Transition to the next screen
        
        await requestNextAutorisationPermissionAfterCreatingTheOwnedIdentity(profileKind: .unmanaged(ownedCryptoId: ownedCryptoId))
        
    }
    
    
    func userIndicatedHerProfileIsManagedByOrganisation(controller: NewUnmanagedDetailsChooserViewController) async {
        await userIndicatedHerProfileIsManagedByOrganisation()
    }
    
}
 

// MARK: - NewAutorisationRequesterViewControllerDelegate

extension NewOnboardingFlowViewController: NewAutorisationRequesterViewControllerDelegate {
        
    public func requestAutorisation(autorisationRequester: NewAutorisationRequesterViewController, now: Bool, for autorisationCategory: NewAutorisationRequesterViewController.AutorisationCategory) async {
        guard let profileKind = internalState.profileKind else { assertionFailure(); return }
        await delegate?.onboardingNeedsToPreventPrivacyWindowSceneFromShowingOnNextWillResignActive(onboardingFlow: self)
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
                internalState = .shouldRequestPermission(profileKind: profileKind, category: .recordPermission)
            } else {
                internalState = determineLastInternalState(profileKind: profileKind)
            }
        case .recordPermission:
            if now {
                let granted = await AVAudioSession.sharedInstance().requestRecordPermission()
                os_log("User granted access to audio: %@", log: Self.log, type: .info, String(describing: granted))
            }
            internalState = determineLastInternalState(profileKind: profileKind)
        }
        await showNextOnboardingScreen(animated: true)
    }
    
    
    // MARK: - NewOwnedIdentityGeneratedViewControllerDelegate
    
    func userWantsToStartUsingOlvid(controller: NewOwnedIdentityGeneratedViewController) async {
        guard let ownedCryptoId = internalState.ownedCryptoId else { assertionFailure(); return }
        await delegate?.onboardingIsFinished(onboardingFlow: self, ownedCryptoIdGeneratedDuringOnboarding: ownedCryptoId)
        
    }
    
    
    // MARK: - UINavigationControllerDelegate
    
    public func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        
        guard let flowNavigationControllerWidthConstraint, let flowNavigationControllerHeightConstraint else { return }
        
        var isHeightIncreased = false
        var newSize: Size?
        
        enum Size {
            case small
            case normal
            case large
            
            var width: CGFloat {
                return 443
            }
            
            var height: CGFloat {
                switch self {
                case .small:
                    return 426
                case .normal:
                    return 700
                case .large:
                    return 800
                }
            }
        }
        
        switch viewController.self {
        case is NewUnmanagedDetailsChooserViewController:
            newSize = .normal
        case is NewAutorisationRequesterViewController:
            newSize = .normal
        case is ChooseBetweenBackupRestoreAndAddThisDeviceViewController:
            newSize = .normal
        case is ChooseBackupFileViewController:
            newSize = .large
        case is EnterBackupKeyViewController:
            newSize = .large
        case is WaitingForBackupRestoreViewController:
            newSize = .large
        case is NewOwnedIdentityGeneratedViewController:
            newSize = nil
        case is NewWelcomeScreenViewController:
            newSize = .small
        default:
            newSize = .large
        }
        
        if let newSize {
            
            if flowNavigationControllerWidthConstraint.constant != newSize.width {
                flowNavigationControllerWidthConstraint.constant = newSize.width
            }
            
            if flowNavigationControllerHeightConstraint.constant != newSize.height {
                isHeightIncreased = flowNavigationControllerHeightConstraint.constant < newSize.height
                flowNavigationControllerHeightConstraint.constant = newSize.height
            }
            
        }
        
        if animated && isHeightIncreased {
            UIView.animate(withDuration: 0.3) { [weak self] in
                self?.view.layoutIfNeeded()
            }
        }
        
    }
    
}
 

// MARK: - Implementing ProtectedTransferWarningViewControllerDelegate

extension NewOnboardingFlowViewController: ProtectedTransferWarningViewControllerDelegate {
    
    /// Called when a keycloak managed user is willing to add a device, but will need to authenticate on the target device as the keycloak enforces this
    func userWantsToProceedWithAddingDevice(controller: ProtectedTransferWarningViewController) async {
        switch mode {
        case .addNewDevice(ownedCryptoId: let ownedCryptoId, ownedDetails: let ownedDetails, isTransferRestricted: _):
            self.internalState = .userWantsToProceedWithAddingDevice(ownedCryptoId: ownedCryptoId, ownedDetails: ownedDetails)
            await showNextOnboardingScreen(animated: true)
        case .initialOnboarding,
                .addProfile:
            assertionFailure()
        }
    }
    
    
    func userWantsToCloseOnboarding(controller: ProtectedTransferWarningViewController) async {
        await delegate?.userWantsToCloseOnboardingAndCancelAnyOwnedTransferProtocol(onboardingFlow: self)
    }
    
}


extension NewOnboardingFlowViewController {
    
    // MARK: - ChooseBetweenBackupRestoreAndAddThisDeviceViewControllerDelegate
    
    func userWantsToRestoreBackup(controller: ChooseBetweenBackupRestoreAndAddThisDeviceViewController) async {
        self.internalState = .userWantsToRestoreSomeBackup
        await showNextOnboardingScreen(animated: true)
    }
    
    
    func userWantsToActivateHerProfileOnThisDevice(controller: ChooseBetweenBackupRestoreAndAddThisDeviceViewController) async {
        self.internalState = .userWantsToChooseNameForCurrentDevice
        await showNextOnboardingScreen(animated: true)
    }
    
    
    func userIndicatedHerProfileIsManagedByOrganisation(controller: ChooseBetweenBackupRestoreAndAddThisDeviceViewController) async {
        await userIndicatedHerProfileIsManagedByOrganisation()
    }
    
    
    // MARK: - ChooseBackupFileViewControllerDelegate
    
    func userWantsToProceedWithBackup(controller: ChooseBackupFileViewController, encryptedBackup: Data) async {
        self.internalState = .userWantsToRestoreThisEncryptedBackup(encryptedBackup: encryptedBackup)
        await showNextOnboardingScreen(animated: true)
    }
    
    
    // MARK: - EnterBackupKeyViewControllerDelegate
    
    func recoverBackupFromEncryptedBackup(controller: EnterBackupKeyViewController, encryptedBackup: Data, backupKey: String) async throws -> (backupRequestIdentifier: UUID, backupDate: Date) {
        guard let delegate else { assertionFailure(); throw ObvError.theDelegateIsNotSet }
        return try await delegate.onboardingRequiresToRecoverBackupFromEncryptedBackup(onboardingFlow: self, encryptedBackup: encryptedBackup, backupKey: backupKey)
    }
    
    
    func userWantsToRestoreBackup(controller: EnterBackupKeyViewController, backupRequestIdentifier: UUID) async throws {
        self.internalState = .userWantsToRestoreThisDecryptedBackup(backupRequestIdentifier: backupRequestIdentifier)
        await showNextOnboardingScreen(animated: true)
    }
    
    
    // MARK: - WaitingForBackupRestoreViewControllerDelegate
    
    /// Returns the CryptoId of the restore owned identity. When many identities were restored, only one is returned here
    func restoreBackupNow(controller: WaitingForBackupRestoreViewController, backupRequestIdentifier: UUID) async throws -> ObvCryptoId {
        guard let delegate else { throw ObvError.theDelegateIsNotSet }
        return try await delegate.onboardingRequiresToRestoreBackup(onboardingFlow: self, backupRequestIdentifier: backupRequestIdentifier)
    }
    
    
    func userWantsToEnableAutomaticBackup(controller: WaitingForBackupRestoreViewController) async throws {
        guard let delegate else { throw ObvError.theDelegateIsNotSet }
        try await delegate.userWantsToEnableAutomaticBackup(onboardingFlow: self)
    }
    
    
    func backupRestorationSucceeded(controller: WaitingForBackupRestoreViewController, restoredOwnedCryptoId: ObvCryptoId) async {
        await requestNextAutorisationPermissionAfterCreatingTheOwnedIdentity(profileKind: .backupRestored(ownedCryptoId: restoredOwnedCryptoId))
    }
    
    
    func backupRestorationFailed(controller: WaitingForBackupRestoreViewController) async {
        self.internalState = .userWantsToRestoreSomeBackup
        await showNextOnboardingScreen(animated: true)
    }
    
}


// MARK: - ObvScannerHostingViewDelegate

extension NewOnboardingFlowViewController: ObvScannerHostingViewDelegate {
        
    public func scannerViewActionButtonWasTapped() async {
        flowNavigationController?.presentedViewController?.dismiss(animated: true)
    }
    
    public func qrCodeWasScanned(olvidURL: OlvidURL) async {
        flowNavigationController?.presentedViewController?.dismiss(animated: true)
        await delegate?.handleOlvidURL(onboardingFlow: self, olvidURL: olvidURL)
    }
    
}


// MARK: - IdentityProviderValidationViewControllerDelegate

extension NewOnboardingFlowViewController: IdentityProviderValidationViewControllerDelegate {
    
    func discoverKeycloakServer(controller: IdentityProviderValidationViewController, keycloakServerURL: URL) async throws -> (jwks: ObvJWKSet, serviceConfig: OIDServiceConfiguration) {
        guard let delegate else { throw ObvError.theDelegateIsNotSet }
        return try await delegate.onboardingRequiresToDiscoverKeycloakServer(onboardingFlow: self, keycloakServerURL: keycloakServerURL)
    }
    
    
    func userWantsToAuthenticateOnKeycloakServer(controller: IdentityProviderValidationViewController, keycloakConfiguration: ObvKeycloakConfiguration, isConfiguredFromMDM: Bool, keycloakServerKeyAndConfig: (jwks: ObvJWKSet, serviceConfig: OIDServiceConfiguration)) async throws {
        guard let delegate else { throw ObvError.theDelegateIsNotSet }
        let (keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff, keycloakState) = try await delegate.onboardingRequiresKeycloakAuthentication(
            onboardingFlow: self,
            keycloakConfiguration: keycloakConfiguration,
            keycloakServerKeyAndConfig: keycloakServerKeyAndConfig)
        internalState = .keycloakUserDetailsAndStuffAvailable(keycloakUserDetailsAndStuff: keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: keycloakServerRevocationsAndStuff, keycloakState: keycloakState)
        await showNextOnboardingScreen(animated: true)
    }
    
    
    // MARK: - ManagedDetailsViewerViewControllerDelegate
    
    @MainActor
    func userWantsToCreateProfileWithDetailsFromIdentityProvider(controller: ManagedDetailsViewerViewController, keycloakDetails: (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff), keycloakState: ObvKeycloakState) async {
        
        guard let delegate else {
            assertionFailure()
            return
        }
        
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
        
        let currentDetails = ObvIdentityDetails(coreDetails: coreDetails, photoURL: nil)
        
        // Request the generation of the owned identity and sync it with the app
        
        let ownedCryptoId: ObvCryptoId
        do {
            ownedCryptoId = try await delegate.onboardingRequiresToGenerateOwnedIdentity(
                onboardingFlow: self,
                identityDetails: currentDetails,
                nameForCurrentDevice: defaultNameForCurrentDevice,
                keycloakState: keycloakState,
                customServerAndAPIKey: customServerAndAPIKey)
        } catch {
            os_log("Could not generate owned identity: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
        
        do {
            try await delegate.onboardingRequiresToSyncAppDatabasesWithEngine(onboardingFlow: self)
        } catch {
            os_log("Could not sync engine and app: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
        
        // The owned identity is created, we register it with the keycloak manager
        
        do {
            try await delegate.onboardingRequiresToRegisterAndUploadOwnedIdentityToKeycloakServer(ownedCryptoId: ownedCryptoId)
        } catch {
            let alert = UIAlertController(title: String(localizedInThisBundle: "DIALOG_TITLE_IDENTITY_PROVIDER_ERROR"),
                                          message: String(localizedInThisBundle: "DIALOG_MESSAGE_FAILED_TO_UPLOAD_IDENTITY_TO_KEYCLOAK"),
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Ok", style: .default))
            present(alert, animated: true)
            return
        }
        
        // We are done, we can proceed with the next screen
        
        await requestNextAutorisationPermissionAfterCreatingTheOwnedIdentity(profileKind: .keycloakManaged(ownedCryptoId: ownedCryptoId))
        
    }
    
    
    // MARK: - TransfertProtocolSourceCodeDisplayerViewControllerDelegate
    
    func userWantsToInitiateOwnedIdentityTransferProtocolOnSourceDevice(controller: TransfertProtocolSourceCodeDisplayerViewController, ownedCryptoId: ObvCryptoId, onAvailableSessionNumber: @MainActor @escaping (ObvOwnedIdentityTransferSessionNumber) -> Void, onAvailableSASExpectedOnInput: @MainActor @escaping (ObvOwnedIdentityTransferSas, String, UID) -> Void) async throws {
        try await delegate?.onboardingRequiresToInitiateOwnedIdentityTransferProtocolOnSourceDevice(
            onboardingFlow: self,
            ownedCryptoId: ownedCryptoId,
            onAvailableSessionNumber: onAvailableSessionNumber,
            onAvailableSASExpectedOnInput: onAvailableSASExpectedOnInput)
    }
    
    
    func userDidCancelOwnedIdentityTransferProtocol(controller: TransfertProtocolSourceCodeDisplayerViewController) async {
        await userDidCancelOwnedIdentityTransferProtocol()
    }
    
    
    func sasExpectedOnInputIsAvailable(controller: TransfertProtocolSourceCodeDisplayerViewController, sasExpectedOnInput: ObvOwnedIdentityTransferSas, targetDeviceName: String, ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, protocolInstanceUID: UID) async {
        self.internalState = .userMustEnterSASOnSourceDevice(
            sasExpectedOnInput: sasExpectedOnInput,
            targetDeviceName: targetDeviceName,
            ownedCryptoId: ownedCryptoId,
            ownedDetails: ownedDetails,
            protocolInstanceUID: protocolInstanceUID)
        await showNextOnboardingScreen(animated: true)
    }
    
    // MARK: - AddProfileViewControllerDelegate
    
    func userWantsToCloseOnboarding(controller: AddProfileViewController) async {
        await delegate?.userWantsToCloseOnboardingAndCancelAnyOwnedTransferProtocol(onboardingFlow: self)
    }
    
    
    func userWantsToCreateNewProfile(controller: AddProfileViewController) async {
        self.internalState = .userWantsToChooseUnmanagedDetails
        await showNextOnboardingScreen(animated: true)
    }
    
    
    func userWantsToImportProfileFromAnotherDevice(controller: AddProfileViewController) async {
        self.internalState = .userWantsToChooseNameForCurrentDevice
        await showNextOnboardingScreen(animated: true)
    }
    
    
    // MARK: - CurrentDeviceNameChooserViewControllerDelegate
    
    func userWantsToCloseOnboarding(controller: CurrentDeviceNameChooserViewController) async {
        await delegate?.userWantsToCloseOnboardingAndCancelAnyOwnedTransferProtocol(onboardingFlow: self)
    }
    
    
    func userDidChooseCurrentDeviceName(controller: CurrentDeviceNameChooserViewController, deviceName: String) async {
        self.internalState = .userWantsToEnterTransferCode(currentDeviceName: deviceName)
        await showNextOnboardingScreen(animated: true)
    }
    
    
    // MARK: - TransfertProtocolTargetCodeFormViewControllerDelegate
    
    func userEnteredTransferSessionNumberOnTargetDevice(controller: TransfertProtocolTargetCodeFormViewController, transferSessionNumber: ObvTypes.ObvOwnedIdentityTransferSessionNumber, onIncorrectTransferSessionNumber: @escaping () -> Void, onAvailableSas: @escaping (UID, ObvOwnedIdentityTransferSas) -> Void) async throws {
        guard let currentDeviceName = internalState.currentDeviceName else { assertionFailure(); return }
        try await delegate?.onboardingRequiresToInitiateOwnedIdentityTransferProtocolOnTargetDevice(
            onboardingFlow: self,
            transferSessionNumber: transferSessionNumber,
            currentDeviceName: currentDeviceName,
            onIncorrectTransferSessionNumber: onIncorrectTransferSessionNumber,
            onAvailableSas: onAvailableSas)
    }
    
    
    /// Called when the user entered a correct session number on the target device, and after the protocol managed to exchanged the appropriate data with the source device in order to compute a SAS to show on this target device.
    func sasIsAvailable(controller: TransfertProtocolTargetCodeFormViewController, protocolInstanceUID: UID, sas: ObvOwnedIdentityTransferSas) async {
        guard let currentDeviceName = internalState.currentDeviceName else { assertionFailure("We expect to be in the userWantsToEnterTransferCode that contains a device name"); return }
        self.internalState = .userWantsToDisplaySasOnThisTargetDevice(currentDeviceName: currentDeviceName, protocolInstanceUID: protocolInstanceUID, sas: sas)
        await showNextOnboardingScreen(animated: true)
    }
    
}
 

// MARK: - TransferProtocolTargetShowSasViewControllerDelegate

extension NewOnboardingFlowViewController: TransferProtocolTargetShowSasViewControllerDelegate {
    
    func targetDeviceIsShowingSasAndExpectingEndOfProtocol(controller: TransferProtocolTargetShowSasViewController, protocolInstanceUID: UID, onSyncSnapshotReception: @escaping () -> Void, onSuccessfulTransfer: @escaping (ObvCryptoId, Error?) -> Void, onKeycloakAuthenticationNeeded: @escaping (ObvCryptoId, ObvKeycloakConfiguration, ObvKeycloakTransferProofElements) -> Void) async {
        await delegate?.onboardingIsShowingSasAndExpectingEndOfProtocol(
            onboardingFlow: self,
            protocolInstanceUID: protocolInstanceUID,
            onSyncSnapshotReception: onSyncSnapshotReception,
            onSuccessfulTransfer: onSuccessfulTransfer,
            onKeycloakAuthenticationNeeded: onKeycloakAuthenticationNeeded)
    }
    
    
    /// Called at the end of the transfer protocol on the target device, when everything worked
    func successfulTransferWasPerformedOnThisTargetDevice(controller: TransferProtocolTargetShowSasViewController, transferredOwnedCryptoId: ObvCryptoId, postTransferError: Error?) async {
        await requestNextAutorisationPermissionAfterCreatingTheOwnedIdentity(profileKind: .transferred(ownedCryptoId: transferredOwnedCryptoId, postTransferError: postTransferError))
    }
    
    
    func userDidCancelOwnedIdentityTransferProtocol(controller: TransferProtocolTargetShowSasViewController) async {
        await userDidCancelOwnedIdentityTransferProtocol()
    }
    
    
    func userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(controller: TransferProtocolTargetShowSasViewController, keycloakConfiguration: ObvKeycloakConfiguration, transferProofElements: ObvKeycloakTransferProofElements) async throws -> ObvKeycloakTransferProofAndAuthState {
        guard let delegate else { throw ObvError.theDelegateIsNotSet }
        return try await delegate.userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(onboardingFlow: self, keycloakConfiguration: keycloakConfiguration, transferProofElements: transferProofElements)
    }
    
    
    func userProvidesProofOfAuthenticationOnKeycloakServer(controller: TransferProtocolTargetShowSasViewController, ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID, proof: ObvTypes.ObvKeycloakTransferProofAndAuthState) async throws {
        guard let delegate else { assertionFailure(); return }
        try await delegate.userProvidesProofOfAuthenticationOnKeycloakServer(onboardingFlow: self, ownedCryptoId: ownedCryptoId, protocolInstanceUID: protocolInstanceUID, proof: proof)
    }

}


// MARK: - SuccessfulTransferConfirmationViewControllerDelegate

extension NewOnboardingFlowViewController: SuccessfulTransferConfirmationViewControllerDelegate {
    
    func userWantsToDismissOnboardingAfterSuccessfulOwnedIdentityTransferOnThisTargetDevice(controller: SuccessfulTransferConfirmationViewController, transferredOwnedCryptoId: ObvCryptoId, userWantsToAddAnotherProfile: Bool) async {
        if userWantsToAddAnotherProfile {
            requestKeycloakSyncOnDeinit = false
        }
        await delegate?.userWantsToDismissOnboardingAfterSuccessfulOwnedIdentityTransferOnThisTargetDevice(
            onboardingFlow: self,
            transferredOwnedCryptoId: transferredOwnedCryptoId,
            userWantsToAddAnotherProfile: userWantsToAddAnotherProfile)
    }
    
    
    // MARK: - InputSASOnSourceViewControllerDelegate
    
    func userEnteredValidSASOnSourceDevice(controller: InputSASOnSourceViewController, enteredSAS: ObvOwnedIdentityTransferSas, ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, protocolInstanceUID: UID, targetDeviceName: String) async throws {
        // Before going to the next screen, we need more information, namely the current list of owned devices and if the user has a multidevice subscription or not
        guard let delegate else { assertionFailure(); return }
        let (ownedDeviceDiscoveryResult, currentDeviceIdentifier) = try await delegate.onboardingRequiresToPerformOwnedDeviceDiscoveryNow(for: ownedCryptoId)
        internalState = .userMustChooseDeviceToKeepActiveOnSourceDevice(
            ownedCryptoId: ownedCryptoId,
            ownedDetails: ownedDetails,
            enteredSAS: enteredSAS,
            ownedDeviceDiscoveryResult: ownedDeviceDiscoveryResult,
            currentDeviceIdentifier: currentDeviceIdentifier,
            targetDeviceName: targetDeviceName,
            protocolInstanceUID: protocolInstanceUID)
        await showNextOnboardingScreen(animated: true)
    }
    
    
    func userDidCancelOwnedIdentityTransferProtocol(controller: InputSASOnSourceViewController) async {
        await userDidCancelOwnedIdentityTransferProtocol()
    }
    

}


// MARK: - ChooseDeviceToKeepActiveViewControllerDelegate

extension NewOnboardingFlowViewController: ChooseDeviceToKeepActiveViewControllerDelegate {
    
    func userChoseDeviceToKeepActive(controller: ChooseDeviceToKeepActiveViewController, ownedCryptoId: ObvCryptoId, ownedDetails: CNContact, enteredSAS: ObvOwnedIdentityTransferSas, ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult, currentDeviceIdentifier: Data, targetDeviceName: String, deviceToKeepActive: ObvOwnedDeviceDiscoveryResult.Device?, protocolInstanceUID: UID) async {
        internalState = .finalOwnedIdentityTransferCheckOnSourceDevice(
            ownedCryptoId: ownedCryptoId,
            ownedDetails: ownedDetails,
            enteredSAS: enteredSAS,
            ownedDeviceDiscoveryResult: ownedDeviceDiscoveryResult,
            targetDeviceName: targetDeviceName,
            protocolInstanceUID: protocolInstanceUID,
            deviceToKeepActive: deviceToKeepActive)
        await showNextOnboardingScreen(animated: true)
    }
    
    
    func userDidCancelOwnedIdentityTransferProtocol(controller: ChooseDeviceToKeepActiveViewController) async {
        await userDidCancelOwnedIdentityTransferProtocol()
    }
    
    
    // MARK: - OwnedIdentityTransferSummaryViewControllerDelegate
    
    func userDidCancelOwnedIdentityTransferProtocol(controller: OwnedIdentityTransferSummaryViewController) async {
        await userDidCancelOwnedIdentityTransferProtocol()
    }
    
    
    func userWishesToFinalizeOwnedIdentityTransferFromSourceDevice(controller: OwnedIdentityTransferSummaryViewController, enteredSAS: ObvOwnedIdentityTransferSas, deviceToKeepActive: UID?, ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID) async throws {
        guard let isTransferRestricted else { assertionFailure(); return }
        try await delegate?.userWishesToFinalizeOwnedIdentityTransferFromSourceDevice(
            onboardingFlow: self,
            enteredSAS: enteredSAS,
            isTransferRestricted: isTransferRestricted,
            deviceToKeepActive: deviceToKeepActive,
            ownedCryptoId: ownedCryptoId,
            protocolInstanceUID: protocolInstanceUID)
    }
    
    
    func refreshDeviceDiscovery(controller: ChooseDeviceToKeepActiveViewController, for ownedCryptoId: ObvCryptoId) async throws -> ObvOwnedDeviceDiscoveryResult {
        guard let delegate else { throw ObvError.theDelegateIsNotSet }
        let result = try await delegate.onboardingRequiresToPerformOwnedDeviceDiscoveryNow(for: ownedCryptoId)
        return result.ownedDeviceDiscoveryResult
    }
    
}


// MARK: - SubscriptionPlansViewActionsProtocol (required for ChooseDeviceToKeepActiveViewControllerDelegate)

extension NewOnboardingFlowViewController {
    
    public func fetchSubscriptionPlans(for ownedCryptoId: ObvCryptoId, alsoFetchFreePlan: Bool) async throws -> (freePlanIsAvailable: Bool, products: [Product]) {
        guard let delegate else { throw ObvError.theDelegateIsNotSet }
        return try await delegate.fetchSubscriptionPlans(for: ownedCryptoId, alsoFetchFreePlan: alsoFetchFreePlan)
    }
    
    
    public func userWantsToStartFreeTrialNow(ownedCryptoId: ObvCryptoId) async throws -> APIKeyElements {
        guard let delegate else { throw ObvError.theDelegateIsNotSet }
        let newAPIKeyElements = try await delegate.userWantsToStartFreeTrialNow(ownedCryptoId: ownedCryptoId)
        return newAPIKeyElements
    }
    
    
    public func userWantsToBuy(_ product: Product) async throws -> StoreKitDelegatePurchaseResult {
        guard let delegate else { assertionFailure(); throw ObvError.theDelegateIsNotSet }
        return try await delegate.userWantsToBuy(product)
    }
    
    
    public func userWantsToRestorePurchases() async throws {
        guard let delegate else { assertionFailure(); throw ObvError.theDelegateIsNotSet }
        try await delegate.userWantsToRestorePurchases()
    }
    
}


// MARK: - NewIdentityProviderManualConfigurationViewControllerDelegate

extension NewOnboardingFlowViewController: NewIdentityProviderManualConfigurationViewControllerDelegate {
    
    @MainActor
    func userWantsToValidateManualKeycloakConfiguration(controller: NewIdentityProviderManualConfigurationViewController, keycloakConfig: ObvKeycloakConfiguration) async {
        self.internalState = .keycloakConfigAvailable(keycloakConfiguration: keycloakConfig, isConfiguredFromMDM: false)
        await showNextOnboardingScreen(animated: true)
    }
    
}


// MARK: - OlvidURLHandler

extension NewOnboardingFlowViewController: OlvidURLHandler {
    
    @MainActor
    public func handleOlvidURL(_ olvidURL: OlvidURL) async {
        switch olvidURL.category {

        case .openIdRedirect:
            // This case should have been dealt with by the MetaFlowController
            assertionFailure()

        case .invitation:
            // Not handled while the user is performing an onboarding (it used to be, in the old flow, but not anymore)
            assertionFailure()

        case .mutualScan:
            // Not handled while the user is performing an onboarding
            assertionFailure()

        case .configuration(let serverAndAPIKey, _, let keycloakConfig):
            
            if let serverAndAPIKey {
                await userWantsToUseCustomServerAndAPIKey(serverAndAPIKey)
            } else if let keycloakConfig {
                self.internalState = .keycloakConfigAvailable(keycloakConfiguration: keycloakConfig.keycloakConfiguration, isConfiguredFromMDM: false)
                await showNextOnboardingScreen(animated: true)
            } else {
                assertionFailure()
                // betaConfiguration are not handled
            }

        }

    }
    
    
    @MainActor
    private func userWantsToUseCustomServerAndAPIKey(_ customServerAndAPIKey: ServerAndAPIKey) async {
        
        let title = String(localizedInThisBundle: "USE_CUSTOM_API_KEY_AND_SERVER_ALERT_TITLE")
        let message = String.localizedStringWithFormat(String(localizedInThisBundle: "USE_CUSTOM_API_KEY_AND_SERVER_ALERT_BODY_%@_%@"), customServerAndAPIKey.server.absoluteString, customServerAndAPIKey.apiKey.uuidString)
        
        let alert = UIAlertController(title:  title,
                                      message: message,
                                      preferredStyleForTraitCollection: .current)
        alert.addAction(.init(title: "Cancel", style: .cancel))
        alert.addAction(.init(title: "Ok", style: .default) { _ in
            self.customServerAndAPIKey = customServerAndAPIKey
        })
        
        present(alert, animated: true)
        
    }

    
    // MARK: - Helpers
    
    @MainActor
    private func userIndicatedHerProfileIsManagedByOrganisation() async {
        let vc = ObvScannerHostingView(buttonType: .back, delegate: self)
        let nav = UINavigationController(rootViewController: vc)
        // Configure the ScannerHostingView properly for the navigation controller
        vc.title = String(localizedInThisBundle: "CONFIGURATION_SCAN")
        let ellipsisButton = getConfiguredEllipsisCircleRightBarButtonItem()
        vc.navigationItem.rightBarButtonItem = ellipsisButton
        flowNavigationController?.present(nav, animated: true)
    }
    
    
    /// Returns the bar button item shown on the scanner hosting view
    private func getConfiguredEllipsisCircleRightBarButtonItem() -> UIBarButtonItem {
        let menuElements: [UIMenuElement] = [
            UIAction(title: String(localizedInThisBundle: "PASTE_CONFIGURATION_LINK"),
                     image: UIImage(systemIcon: .docOnClipboardFill)) { [weak self] _ in
                self?.presentedViewController?.dismiss(animated: true) { [weak self] in
                    Task { [weak self] in await self?.userWantsToPasteConfigurationURL() }
                }
            },
            UIAction(title: String(localizedInThisBundle: "MANUAL_CONFIGURATION"),
                     image: UIImage(systemIcon: .serverRack)) { [weak self] _ in
                self?.presentedViewController?.dismiss(animated: true) { [weak self] in
                    Task { [weak self] in await self?.userChooseToUseManualIdentityProvider() }
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

    
    @MainActor
    private func userWantsToPasteConfigurationURL() async {
        
        guard let pastedString = UIPasteboard.general.string,
              let url = URL(string: pastedString),
              let olvidURL = OlvidURL(urlRepresentation: url) else {
            await delegate?.userPastedStringWhichIsNotValidOlvidURL(onboardingFlow: self)
            return
        }
        
        await delegate?.handleOlvidURL(onboardingFlow: self, olvidURL: olvidURL)

    }

    
    @MainActor
    private func userChooseToUseManualIdentityProvider() async {
        self.internalState = .userWantsToManuallyConfigureTheIdentityProvider
        await showNextOnboardingScreen(animated: true)
    }


    /// This method is sytematically called after the creation of an owned identity (unmanaged, keycloak ,transferred, etc.).
    /// When all the permissions screen have been dealt with, the appropriate "final" screen is chosen depending on the profile kind
    @MainActor
    private func requestNextAutorisationPermissionAfterCreatingTheOwnedIdentity(profileKind: NewOnboardingState.ProfileKind) async {
        
        // In order to prevent the creation of two profiles during the same onboarding, we save the created profile in a local variable.
        
        self.profileKindOfCreatedOwnedIdentity = profileKind
        
        if await requestingAutorisationIsNecessary(for: .localNotifications) {
            internalState = .shouldRequestPermission(profileKind: profileKind, category: .localNotifications)
        } else if await requestingAutorisationIsNecessary(for: .recordPermission) {
            internalState = .shouldRequestPermission(profileKind: profileKind, category: .recordPermission)
        } else {
            internalState = determineLastInternalState(profileKind: profileKind)
        }
        await showNextOnboardingScreen(animated: true)
    }
    
    
    @MainActor
    private func determineLastInternalState(profileKind: NewOnboardingState.ProfileKind) -> NewOnboardingState {
        switch profileKind {
        case .unmanaged, .keycloakManaged, .backupRestored:
            return .finalize(profileKind: profileKind)
        case .transferred(ownedCryptoId: let transferredOwnedCryptoId, postTransferError: let postTransferError):
            return .successfulTransferWasPerfomed(transferredOwnedCryptoId: transferredOwnedCryptoId, postTransferError: postTransferError)
        }
    }

    
    @MainActor
    private func requestingAutorisationIsNecessary(for autorisationCategory: NewAutorisationRequesterViewController.AutorisationCategory) async -> Bool {
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

    
    private var defaultNameForCurrentDevice: String {
        UIDevice.current.preciseModel
    }

    
    // MARK: - Errors
    
    enum ObvError: Error {
        case couldNotCompressImage
        case theDelegateIsNotSet
    }

}
