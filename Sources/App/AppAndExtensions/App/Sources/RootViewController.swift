/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvUICoreData
import Intents
import OSLog
import ObvSettings
import ObvAppCoreConstants
import ObvKeycloakManager
import ObvAppTypes
import ObvTypes
import ObvLocation
import ObvUI
import ObvPollFeature
import ObvUIGroupSharedBetweenV1AndV2
import ObvDesignSystem
import ObvHistoryTransfer

@MainActor
final class RootViewController: UIViewController, LocalAuthenticationViewControllerDelegate, KeycloakSceneDelegate {
    
    enum ChildViewControllerType {
        case initializer
        case initializationFailure(error: Error)
        case call(model: OlvidCallViewController.Model)
        case metaFlow(obvEngine: ObvEngine)
        case localAuthentication
    }

    private let initializerViewController = InitializerViewController()
    private var initializationFailureViewController: InitializationFailureViewController?
    private var callViewController: OlvidCallViewController?
    private var metaFlowViewController: MetaFlowController?
    private var localAuthenticationVC: LocalAuthenticationViewController?

    private var sceneIsActive = false
    private var callViewControllerModel: OlvidCallViewController.Model?
    private var preferMetaViewControllerOverCallViewController = false
    private var userSuccessfullyPerformedLocalAuthentication = false
    private var shouldAutomaticallyPerformLocalAuthentication = true
    private var keycloakManagerWillPresentAuthenticationScreen = false

    private var observationTokens = [NSObjectProtocol]()

    private var uptimeAtTheTimeOfChangeoverToNotActiveState: TimeInterval?

    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "RootViewController")
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "RootViewController")

    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func viewDidLoad() {

        // This allows to make sure the initializer view controller is part of the view hierarchy
        _ = getInitializerViewController()
        
        observeVoIPNotifications()

    }
    
    
    func sceneDidBecomeActive(_ scene: UIScene) {

        debugPrint("🫵 sceneDidBecomeActive")
        
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        sceneIsActive = true
        Task(priority: .userInitiated) {
            do {
                try await switchToNextViewController()
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
        Task {
            _ = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
            await KeycloakManagerSingleton.shared.setKeycloakSceneDelegate(to: self)
            guard let metaFlowViewController else { assertionFailure(); return }
            metaFlowViewController.sceneDidBecomeActive(scene)
        }
        
    }
    
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        
        // If the user successfully authenticated, we want to reset reset the `uptimeAtTheTimeOfChangeoverToNotActiveState` for this scene.
        // Note that if the user successfully authenticated, it means that the app was initialized properly.
        if userSuccessfullyPerformedLocalAuthentication {
            uptimeAtTheTimeOfChangeoverToNotActiveState = TimeInterval.getUptime()
        }

        userSuccessfullyPerformedLocalAuthentication = false
        shouldAutomaticallyPerformLocalAuthentication = true
        keycloakManagerWillPresentAuthenticationScreen = false
        
        // In case we have a local authentication policy, we dismiss any presented view controller to prevent a glitch
        // during next relaunch (the presented screen would show in front of the other screens, including the privacy screen and
        // the authentication screen.
        
        if ObvMessengerSettings.Privacy.localAuthenticationPolicy != .none {
            presentedViewController?.dismiss(animated: false)
        }
        
    }
    
    
    func sceneWillResignActive(_ scene: UIScene) {
        
        sceneIsActive = false

        // If the keycloak manager is about to present a Safari authentication screen, we ignore the fact that the scene will resign active.
        guard !keycloakManagerWillPresentAuthenticationScreen else {
            keycloakManagerWillPresentAuthenticationScreen = false
            return
        }

        Task(priority: .userInitiated) {
            do {
                try await switchToNextViewController()
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
        Task {
            _ = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
            guard let metaFlowViewController else { assertionFailure(); return }
            metaFlowViewController.sceneWillResignActive(scene)
        }

    }
    
    
    func sceneWillEnterForeground(_ scene: UIScene) {
        
        // We now deal with the closing of opened hidden profiles:
        // - If the `hiddenProfileClosePolicy` is `.background`
        // - and the elapsed time since the last switch to background is "large",
        // We close any opened hidden profile.
        if ObvMessengerSettings.Privacy.hiddenProfileClosePolicy == .background {
            let timeIntervalSinceLastChangeoverToNotActiveState = TimeInterval.getUptime() - (uptimeAtTheTimeOfChangeoverToNotActiveState ?? 0)
            assert(0 <= timeIntervalSinceLastChangeoverToNotActiveState)
            if timeIntervalSinceLastChangeoverToNotActiveState > ObvMessengerSettings.Privacy.timeIntervalForBackgroundHiddenProfileClosePolicy.timeInterval || ObvMessengerSettings.Privacy.timeIntervalForBackgroundHiddenProfileClosePolicy == .immediately {
                Task {
                    // The following line allows to make sure we won't switch to the hidden profile
                    await LatestCurrentOwnedIdentityStorage.shared.removeLatestHiddenCurrentOWnedIdentityStored()
                    await switchToNonHiddenOwnedIdentityIfCurrentIsHidden()
                }
            }
        }

    }
    
    
    private func switchToNextViewController() async throws {
        assert(Thread.isMainThread)
                
        let result = await NewAppStateManager.shared.waitUntilAppInitializationSucceededOrFailed()
        
        let obvEngine: ObvEngine
        
        switch result {
        case .failure(let error):
            return try await switchToChildViewController(type: .initializationFailure(error: error))
        case .success(let _obvEngine):
            obvEngine = _obvEngine
        }
        
        // If we reach this point, the initialization was successful.
        
        // Since the app did initialize, we don't want the initializerWindow to show the spinner ever again
        
        self.initializerViewController.appInitializationSucceeded()
        
        // We choose the most appropriate view controller to show depending on the current view controller and on various state variables
        
        guard sceneIsActive else {
            // When the user choosed to lock the screen, we hide the app content each time the scene becomes inactive
            if ObvMessengerSettings.Privacy.localAuthenticationPolicy.lockScreen {
                return try await switchToChildViewController(type: .initializer)
            }
            return
        }
        
        // If we reach this point, the scene is active
        
        // If there is a call in progress, show it instead of any other view controller
        
        if let callViewControllerModel, !preferMetaViewControllerOverCallViewController {
            //return try await switchToChildViewController(type: .call(callInProgress: callInProgress))
            return try await switchToChildViewController(type: .call(model: callViewControllerModel))
        }
        
        // At this point, there is not call in progress (or the user prefers to see the meta view controller instead of the call view)
        
        if userSuccessfullyPerformedLocalAuthentication || !ObvMessengerSettings.Privacy.localAuthenticationPolicy.lockScreen {
            return try await switchToChildViewController(type: .metaFlow(obvEngine: obvEngine))
        } else {
            try await switchToChildViewController(type: .localAuthentication)
            let localAuthenticationVC = try await getLocalAuthenticationViewController()
            if shouldAutomaticallyPerformLocalAuthentication {
                shouldAutomaticallyPerformLocalAuthentication = false
                await localAuthenticationVC.performLocalAuthentication(
                    customPasscodePresentingViewController: self,
                    uptimeAtTheTimeOfChangeoverToNotActiveState: uptimeAtTheTimeOfChangeoverToNotActiveState)
            } else {
                await localAuthenticationVC.shouldPerformLocalAuthentication()
            }
            return
        }
        
    }

    
    private func switchToChildViewController(type: ChildViewControllerType) async throws {

        debugPrint("🫵 switchToChildViewController(\(type))")
        
        defer {
            // Make sure the child view controller views are in the right order
            if let view = localAuthenticationVC?.view {
                self.view.bringSubviewToFront(view)
            }
            self.view.bringSubviewToFront(initializerViewController.view)
        }
        
        switch type {
            
        case .initializer:
            let vc = getInitializerViewController()
            vc.becomeFirstResponder()
            vc.view.isHidden = true
            hideAllChildViewControllersBut(type: type)
            
        case .initializationFailure(error: let error):
            let vc = getInitializationFailureViewController()
            vc.becomeFirstResponder()
            vc.view.isHidden = true
            vc.error = error
            hideAllChildViewControllersBut(type: type)

//        case .call(callInProgress: let callInProgress):
//            let vc = getCallViewHostingController(callInProgress: callInProgress)
//            vc.becomeFirstResponder()
//            vc.view.isHidden = true
//            hideAllChildViewControllersBut(type: type)

        case .call(model: let callViewControllerModel):
            let vc = getOlvidCallViewController(callViewControllerModel: callViewControllerModel)
            vc.becomeFirstResponder()
            vc.view.isHidden = true
            hideAllChildViewControllersBut(type: type)

        case .metaFlow(obvEngine: let obvEngine):
            let vc = try await getMetaFlowViewController(obvEngine: obvEngine)
            vc.becomeFirstResponder()
            vc.view.isHidden = true
            hideAllChildViewControllersBut(type: type)
            
        case .localAuthentication:
            let vc = try await getLocalAuthenticationViewController()
            vc.becomeFirstResponder()
            vc.view.isHidden = true
            hideAllChildViewControllersBut(type: type)
            
        }
        
    }
    
    
    private func hideAllChildViewControllersBut(type: ChildViewControllerType) {
        
        let allChildViewControllers = [
            initializerViewController,
            initializationFailureViewController,
            //callViewHostingController,
            callViewController,
            metaFlowViewController,
            localAuthenticationVC,
        ]
        
        // We hide all view controllers
        
        allChildViewControllers.forEach { vcToHide in
            vcToHide?.view.endEditing(true)
            vcToHide?.view.isHidden = true
        }
        
        // We show the appropriate one. Certain child view controllers, like the call view controller, must make sure no view controller is presented. Otherwise, the user would not see them. Other situations are a bit more complex: for example, when pasting an API key, the system request an authorization to the user, and hides the meta flow controller. When unhiding the meta flow, we don't want to dismiss the presented view controller.
        
        switch type {
        case .initializer:
            initializerViewController.view.isHidden = false
        case .initializationFailure:
            initializationFailureViewController?.view.isHidden = false
        case .call:
            callViewController?.view.isHidden = false
            allChildViewControllers.forEach({ $0?.presentedViewController?.dismiss(animated: true) })
        case .metaFlow:
            metaFlowViewController?.view.isHidden = false
        case .localAuthentication:
            localAuthenticationVC?.view.isHidden = false
        }
        
        // When type != call, we want to deallocate the CallViewController (to release the OlvidCall object)
        
        switch type {
        case .call:
            break
        default:
            removeCurrentCallViewController()
        }
        
    }
    
    
    // MARK: - Creating/Getting child view controllers
    
    private func getMetaFlowViewController(obvEngine: ObvEngine) async throws -> MetaFlowController {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        
        if let metaFlowViewController {
            
            return metaFlowViewController
            
        } else {
            
            guard let createPasscodeDelegate = await appDelegate.createPasscodeDelegate else { assertionFailure(); throw ObvError.couldNotGetCreatePasscodeDelegate }
            guard let localAuthenticationDelegate = await appDelegate.localAuthenticationDelegate else { assertionFailure(); throw ObvError.couldNotGetLocalAuthenticationDelegate }
            guard let appBackupDelegate = await appDelegate.appBackupDelegate else { assertionFailure(); throw ObvError.couldNotGetAppBackupDelegate }
            guard let storeKitDelegate = await appDelegate.storeKitDelegate else { assertionFailure(); throw ObvError.couldNotGetStoreKitDelegate }

            // Since we had to "await", another task might have created the MetaFlowController in the meantime
            
            if let metaFlowViewController {
                return metaFlowViewController
            }
            
            assert(self.metaFlowViewController == nil)
            let shouldShowCallBanner = callViewControllerModel != nil
            let metaFlowViewController = MetaFlowController(
                obvEngine: obvEngine,
                createPasscodeDelegate: createPasscodeDelegate,
                localAuthenticationDelegate: localAuthenticationDelegate,
                appBackupDelegate: appBackupDelegate, 
                storeKitDelegate: storeKitDelegate,
                metaFlowControllerDelegate: self,
                shouldShowCallBanner: shouldShowCallBanner)
            
            addChildViewControllerAndChildView(metaFlowViewController)
            assert(self.metaFlowViewController == nil)
            self.metaFlowViewController = metaFlowViewController
            return metaFlowViewController
            
        }
        
    }

    
    private func getInitializationFailureViewController() -> InitializationFailureViewController {
        
        if let initializationFailureViewController {
            
            return initializationFailureViewController
            
        } else {
            
            let initializationFailureViewController = InitializationFailureViewController()
            let nav = UINavigationController(rootViewController: initializationFailureViewController)
            addChildViewControllerAndChildView(nav)
            self.initializationFailureViewController = initializationFailureViewController
            return initializationFailureViewController
            
        }
        
    }
    
    
    private func getInitializerViewController() -> InitializerViewController {
        
        if initializerViewController.parent == nil {
            addChildViewControllerAndChildView(initializerViewController)
        }
        
        return initializerViewController
        
    }
    
    
    private func getOlvidCallViewController(callViewControllerModel: OlvidCallViewController.Model) -> OlvidCallViewController {
        
        removeCurrentCallViewController()
        
        let callViewController = OlvidCallViewController(model: callViewControllerModel)
        addChildViewControllerAndChildView(callViewController)
        self.callViewController = callViewController
        return callViewController

    }
    
    
    private func removeCurrentCallViewController() {
        if let callViewController {
            callViewController.view.removeFromSuperview()
            callViewController.willMove(toParent: nil)
            callViewController.removeFromParent()
            callViewController.didMove(toParent: nil)
            self.callViewController = nil
        }
    }

    
    private func getLocalAuthenticationViewController() async throws -> LocalAuthenticationViewController {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }

        if let localAuthenticationVC {
            
            return localAuthenticationVC
            
        } else {
            
            guard let localAuthenticationDelegate = await appDelegate.localAuthenticationDelegate else { assertionFailure(); throw ObvError.couldNotGetLocalAuthenticationDelegate }
            
            // Since we had to "await", another task might have created the view controller in the meantime
            if let localAuthenticationVC {
                return localAuthenticationVC
            }
            
            let localAuthenticationVC = LocalAuthenticationViewController(localAuthenticationDelegate: localAuthenticationDelegate, delegate: self)
            addChildViewControllerAndChildView(localAuthenticationVC)
            assert(self.localAuthenticationVC == nil)
            self.localAuthenticationVC = localAuthenticationVC
            return localAuthenticationVC

        }
        
    }
    
    /// Helper method
    private func addChildViewControllerAndChildView(_ vc: UIViewController) {
        guard vc.parent == nil else { assertionFailure(); return }
        vc.willMove(toParent: self)
        self.addChild(vc)
        vc.didMove(toParent: self)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(vc.view)
        self.view.pinAllSidesToSides(of: vc.view)
    }
    
    
    // MARK: - Errors
    
    enum ObvError: Error {
        case couldNotGetLocalAuthenticationDelegate
        case couldNotGetAppDelegate
        case couldNotGetCreatePasscodeDelegate
        case couldNotGetAppBackupDelegate
        case couldNotGetStoreKitDelegate
        case metaFlowViewControllerIsNotSet
        case appCoordinatorsHolderIsNil
        case failedToAddAttachmentToDraft
    }
    
    
    /// Restricts device orientation to portrait mode on iPhone only.
    ///
    /// On iPad and Mac (Catalyst), all orientations are allowed.
    ///  - Returns: `.portrait` for iPhone, `.all` for iPad and Mac.
    ///  - Note: Ensure `Info.plist` includes all supported orientations for iPad and Mac.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .portrait
        }
        return .all
    }
    
}

// MARK: - Implementing PollFlowControllerDelegate
extension RootViewController: PollFlowControllerDelegate {
    
    func userWantsToCreatePoll(for discussionIdentifier: ObvDiscussionIdentifier, poll: ObvPoll) {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); return }
        Task {
            guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); return }
            do {
                try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.userWantsToCreatePoll(for: discussionIdentifier, poll: poll)
            } catch {
                assertionFailure()
            }
        }
    }
}


// MARK: - Implementing MapSharingHostingControllerDelegate

@available(iOS 17.0, *)
extension RootViewController: MapSharingHostingControllerDelegate {
    
    func userWantsToSendLocation(_ vc: MapSharingHostingController, locationData: ObvLocationData, discussionIdentifier: ObvDiscussionIdentifier) {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); return }
        Task {
            guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); return }
            do {
                try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.userWantsToSendLocation(locationData: locationData, discussionIdentifier: discussionIdentifier)
            } catch {
                assertionFailure()
            }
        }
    }
    
    
    func userWantsToShareLocationContinuously(_ vc: MapSharingHostingController, initialLocationData: ObvLocationData, expirationMode: SharingLocationExpirationMode, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); return }
        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.userWantsToShareLocationContinuously(initialLocationData: initialLocationData, discussionIdentifier: discussionIdentifier, expirationMode: expirationMode)
        // Since the `ContinuousSharingLocationManager` observes the `PersistedLocationContinuousSent` database thanks to its data source, and
        // since the above call will create `PersistedLocationContinuousSent` database entry, the `ContinuousSharingLocationManager` will eventually start (or continue)
        // its loop through locations live updates.
    }
    
}


// MARK: - Implementing MetaFlowControllerDelegate

extension RootViewController: MetaFlowControllerDelegate {
    
    func historySourceDeviceWantsToSendTransferConfirmationRequestToDestinationOwnedDevice(_ metaFlowController: MetaFlowController, transferId: String, otherOwnedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier) async throws -> ObvHistoryTransfer.DestinationOwnedDeviceDecision {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }
        return try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.historySourceDeviceWantsToSendTransferConfirmationRequestToDestinationOwnedDevice(transferId: transferId, otherOwnedDeviceIdentifier: otherOwnedDeviceIdentifier)
    }
    
    
    func userRequiresMessageHistoryTransferService(_ metaFlowController: MetaFlowController) async throws -> TransferService {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }
        return appCoordinatorsHolder.transferService
    }

    func userWantsToForwardMessage(_ vc: MetaFlowController, identifierOfMessageToForwad: ObvMessageAppIdentifier, identifiersOfDiscussionsWhereMessageShouldBeForwarded: Set<ObvDiscussionIdentifier>) async throws {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }
        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.processUserWantsToForwardMessage(
            identifierOfMessageToForwad: identifierOfMessageToForwad,
            identifiersOfDiscussionsWhereMessageShouldBeForwarded: identifiersOfDiscussionsWhereMessageShouldBeForwarded)
    }
    
    func userWantsToUpdateDiscussionLocalConfiguration(_ vc: MetaFlowController, value: ObvUICoreData.PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: ObvUICoreData.TypeSafeManagedObjectID<ObvUICoreData.PersistedDiscussionLocalConfiguration>) async throws {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }
        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.processUserWantsToUpdateDiscussionLocalConfiguration(
            with: value,
            localConfigurationObjectID: localConfigurationObjectID)
    }
    
    
    func userWantsToUpdateOwnedCustomDisplayName(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvCryptoId, newCustomDisplayName: String?) async throws {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }
        try await appCoordinatorsHolder.obvOwnedIdentityCoordinator.updateOwnedNickname(ownedCryptoId: ownedCryptoId, newCustomDisplayName: newCustomDisplayName)
    }
    
    func userWantsToUnhideOwnedIdentity(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvCryptoId) async throws {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }
        try await appCoordinatorsHolder.obvOwnedIdentityCoordinator.processUserWantsToUnhideOwnedIdentity(ownedCryptoId: ownedCryptoId)
    }
    
    func userWantsToHideOwnedIdentity(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvTypes.ObvCryptoId, password: String) async throws {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }
        try await appCoordinatorsHolder.obvOwnedIdentityCoordinator.processUserWantsToHideOwnedIdentity(ownedCryptoId: ownedCryptoId, password: password)
    }
    
    
    func userHasSeenPublishedDetails(_ metaFlowController: MetaFlowController, publishedDetails: PublishedDetailsValidationViewModel) async throws {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); return }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); return }
        try await appCoordinatorsHolder.contactGroupCoordinator.processUserHasSeenPublishedDetailsOfGroup(groupIdentifier: publishedDetails.groupIdentifier)
    }
    
    func freshContactIdentityReceivedWhileShowingSingleContactView(_ metaFlowController: MetaFlowController, contactIdentity: ObvTypes.ObvContactIdentity) async {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); return }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); return }
        await appCoordinatorsHolder.contactIdentityCoordinator.processCreatedOrUpdatedContactIdentity(obvContactIdentity: contactIdentity)
    }
    
    
    func userDidSeeNewDetailsOfContact(_ metaFlowController: MetaFlowController, contactIdentifier: ObvTypes.ObvContactIdentifier) {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); return }
        Task {
            guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); return }
            appCoordinatorsHolder.contactIdentityCoordinator.processUserDidSeeNewDetailsOfContact(contactIdentifier: contactIdentifier)
        }
    }
    
    func userWantsToUpdatePersonalNote(_ metaFlowController: MetaFlowController, with newText: String?, about: PersonalNoteEditorView.Model.About) async throws {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); return }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); return }
        switch about {
        case .contact(let contactIdentifier):
            try await appCoordinatorsHolder.contactIdentityCoordinator.processUserWantsToUpdatePersonalNoteOnContact(contactIdentifier: contactIdentifier, newText: newText)
        case .groupV1(let groupV1Identifier):
            try await appCoordinatorsHolder.contactGroupCoordinator.processUserWantsToUpdatePersonalNoteOnGroupV1(groupV1Identifier: groupV1Identifier, newText: newText)
        case .groupV2(let groupV2Identifier):
            try await appCoordinatorsHolder.contactGroupCoordinator.processUserWantsToUpdatePersonalNoteOnGroupV2(groupV2Identifier: groupV2Identifier, newText: newText)
        }
    }
    
    func userWantsToProcessReceiptsStoredForLater(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvCryptoId, returnReceiptElements: Set<ObvReturnReceiptElements>) async {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); return }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); return }
        await appCoordinatorsHolder.recipientInfosCoordinator.userWantsToProcessReceiptsStoredForLater(ownedCryptoId: ownedCryptoId, returnReceiptElements: returnReceiptElements)
    }
    
    
    func userWantsToDeleteDiscussionsAndHasConfirmed(_ metaFlowController: MetaFlowController, discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>], deletionType: DeletionType) async throws {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }
        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.userWantsToDeleteDiscussionsAndHasConfirmed(discussionObjectIDs: discussionObjectIDs, deletionType: deletionType)
    }
    
    
    func userWantsToArchiveDiscussions(_ metaFlowController: MetaFlowController, discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }
        await withThrowingTaskGroup(of: Void.self) { group in
            for discussionObjectID in discussionObjectIDs {
                group.addTask { try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.userWantsToArchiveDiscussion(discussionObjectID: discussionObjectID) }
                // We don't fail, even if one of the task fails
            }
        }

        showToastAsUserArchivedDiscussion(discussionObjectIDs: discussionObjectIDs)
        
        requestUserChoiceOnUnarchivePolicyIfNeeded()
        
    }
    
    
    /// Helper method for the `userWantsToArchiveDiscussion(...)` method.
    private func showToastAsUserArchivedDiscussion(discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>]) {
        Task {
            let toast = Toast(style: .success, message: NSLocalizedString("ARCHIVED_DISCUSSION", comment: ""))
            Toaster.showToast(toast: toast) { [weak self] in
                Task { [weak self] in
                    guard let self else { return }
                    try? await userWantsToUnarchiveDiscussions(discussionObjectIDs: discussionObjectIDs)
                }
            }
        }
    }
    
    
    /// Helper method for the `userWantsToArchiveDiscussion(...)` method.
    private func requestUserChoiceOnUnarchivePolicyIfNeeded() {
        
        guard !ObvMessengerSettings.Discussions.isUnarchiveDiscussionsSet else { return }
        
        let alert = UIAlertController(title: NSLocalizedString("ALERT_FIRST_ARCHIVE_TITLE", comment: ""),
                                      message: NSLocalizedString("ALERT_FIRST_ARCHIVE_MESSAGE", comment: ""),
                                      preferredStyleForTraitCollection: self.traitCollection)
        
        let yesAction = UIAlertAction(title: CommonString.Word.Yes, style: .default) { _ in
            ObvMessengerSettings.Discussions.setUnarchiveDiscussions(to: true, changeMadeFromAnotherOwnedDevice: false)
        }
        
        let noAction = UIAlertAction(title: CommonString.Word.No, style: .default) { _ in
            ObvMessengerSettings.Discussions.setUnarchiveDiscussions(to: false, changeMadeFromAnotherOwnedDevice: false)
        }
        
        alert.addAction(yesAction)
        alert.addAction(noAction)
        
        self.presentOnTop(alert, animated: true)
        
    }
    
    
    func userWantsToUnarchiveDiscussions(_ metaFlowController: MetaFlowController, discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws {
        try await self.userWantsToUnarchiveDiscussions(discussionObjectIDs: discussionObjectIDs)
    }
    
    
    func userWantsToUnarchiveDiscussions(discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for discussionObjectID in discussionObjectIDs {
                group.addTask { try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.userWantsToUnarchiveDiscussion(discussionObjectID: discussionObjectID) }
                try await group.next() // If one of the task throws, we fail
            }
        }
    }
    
    
    func userWantsToReorderPinnedDiscussions(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvCryptoId, objectIDOfPinnedDiscussions: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }
        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.userWantsToReorderPinnedDiscussions(ownedCryptoId: ownedCryptoId, objectIDOfPinnedDiscussions: objectIDOfPinnedDiscussions)
    }
    
    
    func userWantsToMarkAllMessagesAsReadInDiscussion(_ metaFlowController: MetaFlowController, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) async throws {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }
        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.userWantsToMarkAllMessagesAsReadInDiscussion(discussionObjectID: discussionObjectID)        
    }
    

    @MainActor
    func userWantsToDeleteOwnedIdentityAndHasConfirmed(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvCryptoId, globalOwnedIdentityDeletion: Bool) async throws {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }

        showHUD(type: .spinner)
        
        do {
            try await appCoordinatorsHolder.obvOwnedIdentityCoordinator.processUserWantsToDeleteOwnedIdentityAndHasConfirmed(ownedCryptoId: ownedCryptoId, globalOwnedIdentityDeletion: globalOwnedIdentityDeletion)
            await showThenHideHUD(type: .checkmark)
        } catch {
            await showThenHideHUD(type: .xmark)
        }
        
    }
    
    
    /// This method is called when the user taps on the location button of a discussion's message composition view.
    func userWantsToShowMapToSendOrShareLocationContinuously(_ metaFlowController: MetaFlowController, presentingViewController: UIViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws {

        if #available(iOS 17, *) {

            let authorizationStatus = try await ObvLocationPermissionService.shared.requestPermissionIfNotDetermined()
            
            switch authorizationStatus {
            case .notDetermined:
                // This is unexpected as we just requested a permission. We consider this means "denied"
                assertionFailure()
                presentAlertForCLAuthorizationStatusDenied(presentingViewController: presentingViewController)
                return
            case .restricted:
                presentAlertForCLAuthorizationStatusRestricted(presentingViewController: presentingViewController)
                return
            case .denied:
                presentAlertForCLAuthorizationStatusDenied(presentingViewController: presentingViewController)
                return
            case .authorizedAlways,
                    .authorizedWhenInUse,
                    .authorized:
                // These are the only cases where we go further
                break
            @unknown default:
                assertionFailure()
                presentAlertForCLAuthorizationStatusDenied(presentingViewController: presentingViewController)
                return
            }
            
            // If we reach this point, we have permission to use location
            let isAlreadyContinouslySharingLocationFromCurrentDevice: Bool
            if let discussion = try? PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: discussionIdentifier, within: ObvStack.shared.viewContext), let location = discussion.ownedIdentity?.currentDevice?.location {
                isAlreadyContinouslySharingLocationFromCurrentDevice = !location.isSharingLocationExpired
            } else {
                isAlreadyContinouslySharingLocationFromCurrentDevice = false
            }
            
            let vc = try MapSharingHostingController(discussionIdentifier: discussionIdentifier,
                                                     isAlreadyContinouslySharingLocationFromCurrentDevice: isAlreadyContinouslySharingLocationFromCurrentDevice,
                                                     delegate: self)
            
            
            if let sheet = vc.sheetPresentationController {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    sheet.detents = [ .large() ]
                    sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
                } else {
                    sheet.detents = [ .custom { _ in 250.0 }, .medium(), .large() ]
                }
                sheet.prefersGrabberVisible = true
                sheet.delegate = vc
                sheet.preferredCornerRadius = 30.0
            }
            
            presentingViewController.present(vc, animated: true, completion: nil)
            
        } else {
            
            presentAlertAsOsUpgradeIsRequired(presentingViewController: presentingViewController)
            
        }
        
    }
    
    
    func userWantsToStopSharingLocationInDiscussion(_ metaFlowController: MetaFlowController, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }
        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.userWantsToStopSharingLocationInDiscussion(discussionIdentifier: discussionIdentifier)
    }
    

    /// Called when the user wants show the interface allowing to create a new poll to be posted in the given discussion.
    func userWantsToCreatePoll(_ metaFlowController: MetaFlowController, presentingViewController: UIViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws {

        if #available(iOS 17, *) {

            let vc = PollCreationFlowHostingController(discussionIdentifier: discussionIdentifier, delegate: self)
            
            presentingViewController.present(vc, animated: true, completion: nil)
            
        } else {
            
            presentAlertAsOsUpgradeIsRequired(presentingViewController: presentingViewController)
            
        }
        
    }
    
    
    func presentAlertAsOsUpgradeIsRequired(_ metaFlowController: MetaFlowController, presentingViewController: UIViewController) {
        self.presentAlertAsOsUpgradeIsRequired(presentingViewController: presentingViewController)
    }
    

    private func presentAlertAsOsUpgradeIsRequired(presentingViewController: UIViewController) {
        
        let alertTitle: String
        let alertMessage: String
        if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
            alertTitle = String(localized: "MACOS_UPGRADE_REQUIRED")
            alertMessage = String(localized: "THIS_FEATURE_REQUIRES_MACOS_15_OR_ABOVE")
        } else {
            alertTitle = String(localized: "IOS_OR_IPADOS_UPGRADE_REQUIRED")
            alertMessage = String(localized: "THIS_FEATURE_REQUIRES_IOS_17_OR_ABOVE")
        }
        
        let alert = UIAlertController(title: alertTitle,
                                      message: alertMessage,
                                      preferredStyle: .alert)
        let okAction = UIAlertAction(title: CommonString.Word.Ok, style: .default)
        alert.addAction(okAction)
        
        presentingViewController.present(alert, animated: true, completion: nil)

    }
    
    
    private func presentAlertForCLAuthorizationStatusDenied(presentingViewController: UIViewController) {
        
        let alert = UIAlertController(title: String(localized: "Authorization Required"),
                                      message: String(localized: "Olvid is not authorized to access your location. You can change this setting within the Settings app."),
                                      preferredStyleForTraitCollection: .current)
        
        let goToSettingsActions = UIAlertAction(title: String(localized: "Open Settings"), style: .destructive) { _ in
            if let settingsURL = URL(string: UIApplication.openLocationSettingsURLString), UIApplication.shared.canOpenURL(settingsURL) {
                UIApplication.shared.open(settingsURL, options: [:])
            }
        }
        let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: .cancel) { _ in }
        
        alert.addAction(goToSettingsActions)
        alert.addAction(cancelAction)
        
        presentingViewController.present(alert, animated: true, completion: nil)
        
    }
    
    
    private func presentAlertForCLAuthorizationStatusRestricted(presentingViewController: UIViewController) {
        
        let alert = UIAlertController(title: String(localized: "Authorization Restricted"),
                                      message: String(localized: "Olvid is not authorized to access your location due to active restrictions such as parental controls or MDM settings."),
                                      preferredStyleForTraitCollection: .current)
        
        let goToSettingsActions = UIAlertAction(title: String(localized: "Open Settings"), style: .destructive) { _ in
            if let settingsURL = URL(string: UIApplication.openLocationSettingsURLString), UIApplication.shared.canOpenURL(settingsURL) {
                UIApplication.shared.open(settingsURL, options: [:])
            }
        }
        let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: .cancel) { _ in }
        
        alert.addAction(goToSettingsActions)
        alert.addAction(cancelAction)
        
        presentingViewController.present(alert, animated: true, completion: nil)
        
    }
    
    
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice(_ metaFlowController: MetaFlowController) async throws {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }
        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice()
    }
    
    
    func userWantsToUpdateReaction(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, newEmoji: String?) async throws {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }

        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.processUserWantsToUpdateReaction(ownedCryptoId: ownedCryptoId, messageObjectID: messageObjectID, newEmoji: newEmoji)

    }
    
    func userWantsToUpdatePollVote(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, pollVoteCandidateUuid: UUID, voted: Bool, version: Int) async throws {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }
        
        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.processUserWantsToUpdatePollVote(ownedCryptoId: ownedCryptoId, messageObjectID: messageObjectID, pollVoteCandidateUuid: pollVoteCandidateUuid, voted: voted, version: version)

    }
    
    
    func messagesAreNotNewAnymore(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageIds: [MessageIdentifier]) async throws {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }

        await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.processMessagesAreNotNewAnymore(ownedCryptoId: ownedCryptoId, discussionId: discussionId, messageIds: messageIds)

    }
    
    func updatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(_ metaFlowController: MetaFlowController, discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentIDs: Set<ObvManagedObjectPermanentID<PersistedMessage>>) async throws {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }

        await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.processUpdatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(
            discussionPermanentID: discussionPermanentID,
            messagePermanentIDs: messagePermanentIDs)

    }
    
    
    func userWantsToReadReceivedMessageThatRequiresUserAction(_ metaFlowController: MetaFlowController, ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageId: ReceivedMessageIdentifier) async throws {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }

        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.processUserWantsToReadReceivedMessageThatRequiresUserActionNotification(
            ownedCryptoId: ownedCryptoId,
            discussionId: discussionId,
            messageId: messageId)

    }
    
    
    func userWantsToUpdateDraftExpiration(_ metaFlowController: MetaFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, value: PersistedDiscussionSharedConfigurationValue?) async throws {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }

        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.processUserWantsToUpdateDraftExpiration(draftObjectID: draftObjectID, value: value)

    }
    
    
    func insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(_ metaFlowController: MetaFlowController, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, markAsRead: Bool) async throws {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }

        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.processInsertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(discussionObjectID: discussionObjectID, markAsRead: markAsRead)

    }
    
    
    func userWantsToRemoveReplyToMessage(_ metaFlowController: MetaFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }

        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.processUserWantsToRemoveReplyToMessage(draftObjectID: draftObjectID)
        
    }
    
    func userWantsToPauseSentFyleMessageJoinWithStatusFromOtherOwnedDevice(_ metaFlowController: MetaFlowController, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }

        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.processUserWantsToPauseSentFyleMessageJoinWithStatusFromOtherOwnedDevice(sentJoinObjectID: sentJoinObjectID)

    }
    
    
    func userWantsToDownloadSentFyleMessageJoinWithStatusFromOtherOwnedDevice(_ metaFlowController: MetaFlowController, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }

        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.processUserWantsToDownloadSentFyleMessageJoinWithStatusFromOtherOwnedDevice(sentJoinObjectID: sentJoinObjectID)

    }
    
    
    func userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(_ metaFlowController: MetaFlowController, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }

        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.processUserWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(receivedJoinObjectID: receivedJoinObjectID)

    }
    
    
    func userWantsToDownloadReceivedFyleMessageJoinWithStatus(_ metaFlowController: MetaFlowController, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws {

        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }

        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.processUserWantsToDownloadReceivedFyleMessageJoinWithStatus(receivedJoinObjectID: receivedJoinObjectID)
    }
    
    
    func userWantsToReplyToMessage(_ metaFlowController: MetaFlowController, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }

        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.userWantsToReplyToMessage(messageObjectID: messageObjectID, draftObjectID: draftObjectID)

    }
    

    func userWantsToDeleteDraftAttachment(_ metaFlowController: MetaFlowController, draftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>) async throws {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); return }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); return }

        await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.userWantsToDeleteDraftAttachment(draftFyleJoinObjectID: draftFyleJoinObjectID)
    }
    
    func userWantsToUpdateDraftBodyAndMentions(_ metaFlowController: MetaFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, body: AttributedString) async throws {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }

        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.processUserWantsToUpdateDraftBodyAndMentions(draftObjectID: draftObjectID, draftBody: body)
        
    }
    
    
    func userWantsToAddAttachmentsToDraftFromURLs(_ metaFlowController: MetaFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, urls: [URL]) async throws {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }
        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.processUserWantsToAddAttachmentsToDraft(draftObjectID: draftObjectID, urls: urls)

    }
    
    
    func userWantsToAddAttachmentsToDraft(_ metaFlowController: MetaFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, itemProviders: [NSItemProvider], source: LoadItemProviderHelper.ItemProviderProviderSource) async throws -> [LoadedItemProviderToPaste] {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }
        let loadedItemProviderToPaste = try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.processUserWantsToAddAttachmentsToDraft(
            draftObjectID: draftObjectID,
            itemProviders: itemProviders,
            source: source)
        return loadedItemProviderToPaste
        
    }
    
    
    func userRequestedAppDatabaseSyncWithEngine(metaFlowController: MetaFlowController) async throws {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        
        try await appDelegate.appMainManager.appCoordinatorsHolder?.bootstrapCoordinator.userRequestedAppDatabaseSyncWithEngine(rootViewController: self)

    }
    
    
    func userWantsToSendDraft(_ metaFlowController: MetaFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, textBody: AttributedString) async throws {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }
        
        try await appCoordinatorsHolder.persistedDiscussionsUpdatesCoordinator.processUserWantsToSendDraft(draftObjectID: draftObjectID, textBody: textBody)        
        
    }
    
    
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ metaFlowController: MetaFlowController, groupIdentifier: ObvGroupV2Identifier) async throws {
        
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); throw ObvError.couldNotGetAppDelegate }
        guard let appCoordinatorsHolder = await appDelegate.appMainManager.appCoordinatorsHolder else { assertionFailure(); throw ObvError.appCoordinatorsHolderIsNil }

        try await appCoordinatorsHolder.contactGroupCoordinator.userWantsToReplaceTrustedDetailsByPublishedDetails(groupIdentifier: groupIdentifier)
        
    }

}


// MARK: - LocalAuthenticationViewControllerDelegate

extension RootViewController {
    
    func userLocalAuthenticationDidSucceed(authenticationWasPerformed: Bool) async {
        
        userSuccessfullyPerformedLocalAuthentication = true
        // If we just performed authentication, it means the screen was locked. If the hidden profile close policy is `.screenLock`, we should make sure the current identity is not hidden.
        if authenticationWasPerformed && ObvMessengerSettings.Privacy.hiddenProfileClosePolicy == .screenLock {
            // The following line allows to make sure we won't switch to the hidden profile
            await LatestCurrentOwnedIdentityStorage.shared.removeLatestHiddenCurrentOWnedIdentityStored()
            await switchToNonHiddenOwnedIdentityIfCurrentIsHidden()
        }
        Task(priority: .userInitiated) { [weak self] in
            do {
                try await self?.switchToNextViewController()
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }

    }
    
    
    func tooManyWrongPasscodeAttemptsCausedLockOut() async {
        await switchToNonHiddenOwnedIdentityIfCurrentIsHidden()
        ObvMessengerInternalNotification.tooManyWrongPasscodeAttemptsCausedLockOut.postOnDispatchQueue()

    }

}


extension RootViewController {
    
    /// Allows to switch to a non hidden profile if the current one is hidden
    ///
    /// This is called in two cases:
    /// - when the user just authenticated and the hidden profile closing policy is `screenLock`
    /// - or when she was locked out after entering too many bad passcodes.
    private func switchToNonHiddenOwnedIdentityIfCurrentIsHidden() async {
        // In case the meta flow controller is nil, we do nothing. This is not an issue: if it is nil, there is no risk it displays a hidden profile.
        await self.metaFlowViewController?.switchToNonHiddenOwnedIdentityIfCurrentIsHidden()
    }

    
}


// MARK: - Observing notifications

extension RootViewController {
    
    private func observeVoIPNotifications() {
        observationTokens.append(contentsOf: [
            VoIPNotification.observeNewCallToShow { model in
                Task(priority: .userInitiated) { [weak self] in
                    self?.preferMetaViewControllerOverCallViewController = false
                    await self?.setCallViewControllerModel(to: model)
                }
            },
            VoIPNotification.observeNoMoreCallInProgress {
                Task(priority: .userInitiated) { [weak self] in
                    self?.preferMetaViewControllerOverCallViewController = false
                    await self?.setCallViewControllerModel(to: nil)
                }
            },
            VoIPNotification.observeHideCallView {
                Task(priority: .userInitiated) { [weak self] in
                    self?.preferMetaViewControllerOverCallViewController = true
                    do {
                        try await self?.switchToNextViewController()
                    } catch {
                        assertionFailure(error.localizedDescription)
                    }
                }
            },
            VoIPNotification.observeShowCallView {
                Task(priority: .userInitiated) { [weak self] in
                    self?.preferMetaViewControllerOverCallViewController = false
                    do {
                        try await self?.switchToNextViewController()
                    } catch {
                        assertionFailure(error.localizedDescription)
                    }
                }
            },
            VoIPNotification.observeAnotherCallParticipantStartedCamera { [weak self] otherParticipantNames in
                guard let self else { return }
                guard !sceneIsActive || preferMetaViewControllerOverCallViewController else { return }
                ObvMessengerInternalNotification.postUserNotificationAsAnotherCallParticipantStartedCamera(otherParticipantNames: otherParticipantNames)
                    .postOnDispatchQueue()
            },
        ])
    }
    
}


// MARK: - Managing calls

extension RootViewController {
    
    private func setCallViewControllerModel(to newCallViewControllerModel: OlvidCallViewController.Model?) async {
        _ = await NewAppStateManager.shared.waitUntilAppIsInitialized()
        callViewControllerModel = newCallViewControllerModel
        Task(priority: .userInitiated) { [weak self] in
            do {
                try await self?.switchToNextViewController()
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    

    /// This called, in particular, when the user taps on a previous call in the call log of the phone system app.
    private func processINStartCallIntent(startCallIntent: INStartCallIntent, obvEngine: ObvEngine) {
        
        Self.logger.info("📲 Process INStartCallIntent")
        
        guard let handle = startCallIntent.contacts?.first?.personHandle?.value else {
            Self.logger.error("📲 Could not get appropriate value of INStartCallIntent")
            return
        }
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            
            if let callUUID = UUID(handle), let item = try? PersistedCallLogItem.get(callUUID: callUUID, within: context), let ownedCryptoId = item.ownedCryptoId {
                let contactCryptoIds = item.logContacts.compactMap { $0.contactIdentity?.cryptoId }
                let groupId = item.groupIdentifier
                Self.logger.info("📲 Posting a userWantsToCallButWeShouldCheckSheIsAllowedTo notification following an INStartCallIntent")
                ObvMessengerInternalNotification.userWantsToCallOrUpdateCallCapabilityButWeShouldCheckSheIsAllowedTo(ownedCryptoId: ownedCryptoId, contactCryptoIds: Set(contactCryptoIds), groupId: groupId, startCallIntent: startCallIntent)
                    .postOnDispatchQueue()
            } else if let contact = try? PersistedObvContactIdentity.getAll(within: context).first(where: { $0.getGenericHandleValue(engine: obvEngine) == handle }) {
                // To be compatible with previous 1to1 versions
                let contactCryptoId = contact.cryptoId
                guard let ownedCryptoId = contact.ownedIdentity?.cryptoId else { return }
                ObvMessengerInternalNotification.userWantsToCallOrUpdateCallCapabilityButWeShouldCheckSheIsAllowedTo(ownedCryptoId: ownedCryptoId, contactCryptoIds: Set([contactCryptoId]), groupId: nil, startCallIntent: startCallIntent)
                    .postOnDispatchQueue()
            } else {
                Self.logger.fault("📲 Could not parse INStartCallIntent")
            }
            
        }
    }

    
    private func processINSendMessageIntent(sendMessageIntent: INSendMessageIntent) {
        os_log("📲 Process INSendMessageIntent", log: Self.log, type: .info)
        
        guard let handle = sendMessageIntent.recipients?.first?.personHandle?.value else {
            os_log("📲 Could not get appropriate value of INSendMessageIntent", log: Self.log, type: .error)
            assertionFailure()
            return
        }
        
        guard let objectPermanentID = ObvManagedObjectPermanentID<PersistedObvContactIdentity>(handle) else { assertionFailure(); return }
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            guard let contact = try? PersistedObvContactIdentity.getManagedObject(withPermanentID: objectPermanentID, within: context) else { assertionFailure(); return }
            let deepLink: ObvDeepLink
            if let oneToOneDiscussion = contact.oneToOneDiscussion, let discussionIdentifier = try? oneToOneDiscussion.discussionIdentifier {
                deepLink = .singleDiscussion(discussionIdentifier: discussionIdentifier)
            } else { assertionFailure(); return }
            ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink).postOnDispatchQueue()
        }
    }

}


// MARK: - Continuing User Activities

extension RootViewController {
    
    func continueUserActivities(_ userActivities: Set<NSUserActivity>) {
        Task { [weak self] in
            for userActivity in userActivities {
                await self?.continueUserActivity(userActivity)
            }
        }
    }
    
    func continueUserActivity(_ userActivity: NSUserActivity) async {
        let obvEngine = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
        if let url = userActivity.webpageURL {
            // Called when tapping the "open in" button on an "identity" webpage or when tapping a call entry in the system call log (?)
            await handleOlvidURL(url)
        } else if let startCallIntent = userActivity.interaction?.intent as? INStartCallIntent {
            processINStartCallIntent(startCallIntent: startCallIntent, obvEngine: obvEngine)
        } else if let sendMessageIntent = userActivity.interaction?.intent as? INSendMessageIntent {
            processINSendMessageIntent(sendMessageIntent: sendMessageIntent)
        } else if let olvidUserActivity = OlvidUserActivity(receivedNSUserActivity: userActivity) {
            processOlvidUserActivityReceivedViaHandoff(receivedOlvidUserActivity: olvidUserActivity)
        } else {
            assertionFailure()
        }
    }

}


// MARK: - Handling OlvidUserActivity received via handoff

extension RootViewController {
    
    @MainActor
    private func processOlvidUserActivityReceivedViaHandoff(receivedOlvidUserActivity: OlvidUserActivity) {
        
        let ownedCryptoId = receivedOlvidUserActivity.ownedCryptoId
        
        let deepLink: ObvDeepLink?
        
        if let currentDiscussion = receivedOlvidUserActivity.currentDiscussion {
            let discussionIdentifier = currentDiscussion.toDiscussionIdentifier()
            if let discussion = try? PersistedDiscussion.getPersistedDiscussion(ownedCryptoId: ownedCryptoId, discussionId: discussionIdentifier, within: ObvStack.shared.viewContext),
               let discussionIdentifier = try? discussion.discussionIdentifier {
                deepLink = .singleDiscussion(discussionIdentifier: discussionIdentifier)
            } else {
                deepLink = .latestDiscussions(ownedCryptoId: ownedCryptoId)
            }
        } else {
            switch receivedOlvidUserActivity.currentFlow {
            case .latestDiscussions:
                deepLink = .latestDiscussions(ownedCryptoId: ownedCryptoId)
            case .contacts:
                deepLink = nil
            case .groups:
                deepLink = .allGroups(ownedCryptoId: ownedCryptoId)
            case .invitations:
                deepLink = .invitations(ownedCryptoId: ownedCryptoId)
            }
            
        }
        
        if let deepLink {
            ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                .postOnDispatchQueue()
        }
        
    }
    
}

// MARK: - Opening Olvid URLs

extension RootViewController {
    
    private func handleOlvidURL(_ url: URL) async {
        assert(Thread.isMainThread)
        Self.logger.info("🥏 Call to openDeepLink with URL \(url.debugDescription, privacy: .public)")
        guard let olvidURL = OlvidURL(urlRepresentation: url) else { assertionFailure(); return }
        Self.logger.info("An OlvidURL struct was successfully created: \(olvidURL.url, privacy: .public)")
        await NewAppStateManager.shared.routeOlvidURL(olvidURL)
    }
    
    
    func openURLContexts(_ URLContexts: Set<UIOpenURLContext>) {
        os_log("📲 Scene openURLContexts", log: Self.log, type: .info)
        // Called when tapping an Olvid link, e.g., on an invite webpage
        Task {
            
            _ = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
            
            assert(URLContexts.count < 2)
            if let url = URLContexts.first?.url {
                
                if url.scheme == "olvid" || url.scheme == "olvid.dev" {
                    
                    guard var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }
                    urlComponents.scheme = "https"
                    guard let newUrl = urlComponents.url else { return }
                    await handleOlvidURL(newUrl)
                    return
                    
                } else if url.isFileURL {
                    
                    /* We are certainly dealing with an AirDrop'ed file. See
                     * https://developer.apple.com/library/archive/qa/qa1587/_index.html
                     * for handling Open in...
                     */
                    let deepLink = ObvDeepLink.airDrop(fileURL: url)
                    Task {
                        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                            .postOnDispatchQueue()
                    }
                    return
                    
                } else {
                    assertionFailure()
                }
                
            }
            
        }
        
    }

}


// MARK: - Performing Tasks

extension RootViewController {
    
    func performActionFor(shortcutItem: UIApplicationShortcutItem) async -> Bool {
        // Called when the users taps on the "Scan QR code" shortcut on the app icon
        os_log("UIWindowScene perform action for shortcut", log: Self.log, type: .info)
        _ = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
        guard let shortcut = ApplicationShortcut(shortcutItem.type) else { assertionFailure(); return false }
        let deepLink: ObvDeepLink
        switch shortcut {
        case .scanQRCode:
            deepLink = ObvDeepLink.qrCodeScan
        }
        os_log("🥏 Sending a UserWantsToNavigateToDeepLink notification for shortut item %{public}@", log: Self.log, type: .info, shortcut.description)
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
            .postOnDispatchQueue()
        return true
    }
    
}


// MARK: - KeycloakSceneDelegate

extension RootViewController {

    func requestViewControllerForPresenting() async throws -> UIViewController {

        _ = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()

        guard let metaFlowViewController else {
            assertionFailure()
            throw ObvError.metaFlowViewControllerIsNotSet
        }
        
        keycloakManagerWillPresentAuthenticationScreen = true

        var viewControllerToReturn = metaFlowViewController as UIViewController
        while let presentedViewController = viewControllerToReturn.presentedViewController {
            viewControllerToReturn = presentedViewController
        }
        return viewControllerToReturn

    }

}


// MARK: - Observing trait collection changes

extension RootViewController {
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        OlvidUserActivitySingleton.shared.setTraitCollectionActiveAppearance(traitCollection.activeAppearance)
    }
    
}



// MARK: - Helpers

extension RootViewController.ChildViewControllerType: CustomDebugStringConvertible {
    
    var debugDescription: String {
        switch self {
        case .initializer: return "initializer"
        case .initializationFailure: return "initializationFailure"
        case .call: return "call"
        case .metaFlow: return "metaFlow"
        case .localAuthentication: return "localAuthentication"
        }
    }
    
}


fileprivate extension PersistedObvContactIdentity {

    func getGenericHandleValue(engine: ObvEngine) -> String? {
        guard let context = self.managedObjectContext else { assertionFailure(); return nil }
        var _handleTagData: Data?
        context.performAndWait {
            guard let ownedIdentity = self.ownedIdentity else { assertionFailure(); return }
            do {
                _handleTagData = try engine.computeTagForOwnedIdentity(with: ownedIdentity.cryptoId, on: self.cryptoId.getIdentity())
            } catch {
                assertionFailure()
                return
            }
        }
        guard let handleTagData = _handleTagData else { assertionFailure(); return nil }
        return handleTagData.base64EncodedString()
    }

}
