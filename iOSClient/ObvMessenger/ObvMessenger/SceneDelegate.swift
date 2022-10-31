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
import Intents
import ObvEngine
import OlvidUtils


class SceneDelegate: UIResponder, UIWindowSceneDelegate, KeycloakSceneDelegate, ObvErrorMaker {

    static let errorDomain = "SceneDelegate"
    
    private var initializerWindow: UIWindow?
    private var localAuthenticationWindow: UIWindow?
    private var initializationFailureWindow: UIWindow?
    private var metaWindow: UIWindow?
    private var callWindow: UIWindow?
    
    private let animator = UIViewPropertyAnimator(duration: 0.15, curve: .linear)
    
    private var allWindows: [UIWindow?] { [
        initializerWindow,
        localAuthenticationWindow,
        initializationFailureWindow,
        metaWindow,
        callWindow,
    ] }
    
    private var callNotificationObserved = false
    private var observationTokens = [NSObjectProtocol]()

    private var sceneIsActive = false
    private var userSuccessfullyPerformedLocalAuthentication = false
    private var shouldAutomaticallyPerformLocalAuthentication = true
    private var callInProgress: GenericCall?
    private var preferMetaWindowOverCallWindow = false
    private var keycloakManagerWillPresentAuthenticationScreen = false
        
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "SceneDelegate")
    

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).

        os_log("🧦 scene willConnectTo", log: Self.log, type: .info)

        guard let windowScene = (scene as? UIWindowScene) else { assertionFailure(); return }

        initializerWindow = UIWindow(windowScene: windowScene)
        initializerWindow?.rootViewController = InitializerViewController()
        changeKeyWindow(to: initializerWindow)
        
        observeVoIPNotifications(scene)
        
        if !connectionOptions.userActivities.isEmpty {
            os_log("📲 Scene will connect with user activities", log: Self.log, type: .info)
            Task { [weak self] in
                for userActivity in connectionOptions.userActivities {
                    self?.scene(scene, continue: userActivity)
                }
            }
        }
        
        if !connectionOptions.urlContexts.isEmpty {
            os_log("📲 Scene will connect with url contexts", log: Self.log, type: .info)
            Task { [weak self] in
                self?.scene(scene, openURLContexts: connectionOptions.urlContexts)
            }
        }
                
        if let shortcutItem = connectionOptions.shortcutItem {
            os_log("📲 Scene will connect with a shortcutItem", log: Self.log, type: .info)
            Task { [weak self] in
                await self?.windowScene(windowScene, performActionFor: shortcutItem)
            }
        }
        
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
        debugPrint("sceneDidDisconnect")
        os_log("🧦 sceneDidDisconnect", log: Self.log, type: .info)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        sceneIsActive = true
        Task(priority: .userInitiated) {
            await switchToNextWindowForScene(scene)
        }
        Task {
            _ = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
            await KeycloakManagerSingleton.shared.setKeycloakSceneDelegate(to: self)
            if let metaWindow = metaWindow, let metaFlowController = metaWindow.rootViewController as? MetaFlowController {
                metaFlowController.sceneDidBecomeActive(scene)
            } else {
                assertionFailure()
            }
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
        
        os_log("🧦 sceneWillResignActive", log: Self.log, type: .info)
        
        sceneIsActive = false
        
        // If the keycloak manager is about to present a Safari authentication screen, we ignore the fact that the scene will resign active.
        guard !keycloakManagerWillPresentAuthenticationScreen else {
            keycloakManagerWillPresentAuthenticationScreen = false
            return
        }
        
        Task(priority: .userInitiated) {
            await switchToNextWindowForScene(scene)
        }
        Task {
            _ = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
            if let metaWindow = metaWindow, let metaFlowController = metaWindow.rootViewController as? MetaFlowController {
                metaFlowController.sceneWillResignActive(scene)
            } else {
                assertionFailure()
            }
        }
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
        debugPrint("sceneWillEnterForeground")
        os_log("🧦 sceneWillEnterForeground", log: Self.log, type: .info)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information to restore the scene back to its current state.

        os_log("🧦 sceneDidEnterBackground", log: Self.log, type: .info)

        // If the user successfully authenticated, we want to inform the Local authentication manager that it should reset the `uptimeAtTheTimeOfChangeoverToNotActiveState`.
        // Note that if the user successfully authenticated, it means that the app was initialized properly.
        if userSuccessfullyPerformedLocalAuthentication {
            Task {
                guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
                    assertionFailure(); return
                }
                guard let localAuthenticationDelegate = await appDelegate.localAuthenticationDelegate else {
                    assertionFailure(); return
                }
                await localAuthenticationDelegate.setUptimeAtTheTimeOfChangeoverToNotActiveStateToNow()
            }
        }

        userSuccessfullyPerformedLocalAuthentication = false
        shouldAutomaticallyPerformLocalAuthentication = true
        keycloakManagerWillPresentAuthenticationScreen = false
        
    }

    
    
    // MARK: - Continuing User Activities
    
    func scene(_ scene: UIScene, willContinueUserActivityWithType userActivityType: String) {
        os_log("📲 Scene will continue user activity with type: %{public}@", log: Self.log, type: .info, userActivityType)
    }
    
    
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        // This method is called by the system when an activity can be continued after the app was initialized.
        // We also call it "manually" when scene will connect with options containing one (or more) user activity.
        os_log("📲 Continue user activity", log: Self.log, type: .info)
        Task {
            assert(Thread.isMainThread)
            let obvEngine = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
            if let url = userActivity.webpageURL {
                // Called when tapping the "open in" button on an "identity" webpage or when tapping a call entry in the system call log (?)
                await openOlvidURL(url)
            } else if let startCallIntent = userActivity.interaction?.intent as? INStartCallIntent {
                processINStartCallIntent(startCallIntent: startCallIntent, obvEngine: obvEngine)
            } else {
                assertionFailure()
            }
        }
    }
    
    
    func scene(_ scene: UIScene, didFailToContinueUserActivityWithType userActivityType: String, error: Error) {
        os_log("📲 Scene did fail to continue user activity with type: %{public}@", log: Self.log, type: .error, userActivityType)
    }
    
    
    // MARK: - Performing Tasks

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
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
    
    
    // MARK: - Opening URLs
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        os_log("📲 Scene openURLContexts", log: Self.log, type: .info)
        // Called when tapping an Olvid link, e.g., on an invite webpage
        Task {
            
            _ = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
            
            assert(URLContexts.count < 2)
            if let url = URLContexts.first?.url {
                
                if url.scheme == "olvid" {
                    
                    guard var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }
                    urlComponents.scheme = "https"
                    guard let newUrl = urlComponents.url else { return }
                    await openOlvidURL(newUrl)
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

    
    // MARK: - Switching between windows
    
    @MainActor
    private func switchToNextWindowForScene(_ scene: UIScene) async {
        assert(Thread.isMainThread)
        
        guard let windowScene = (scene as? UIWindowScene) else { assertionFailure(); return }
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { assertionFailure(); return }

        // When switching view controller, we alway make sure the metaWindow is available.
        // The only exception is when the initialization failed.
        
        if metaWindow == nil {
            let result = await NewAppStateManager.shared.waitUntilAppInitializationSucceededOrFailed()
            switch result {
            case .failure(let error):
                initializationFailureWindow = UIWindow(windowScene: windowScene)
                let InitializationFailureVC = InitializationFailureViewController()
                InitializationFailureVC.error = error
                initializationFailureWindow?.rootViewController = InitializationFailureVC
                changeKeyWindow(to: initializationFailureWindow)
                return
            case .success(let obvEngine):
                if metaWindow == nil {
                    metaWindow = UIWindow(windowScene: windowScene)
                    guard let createPasscodeDelegate = await appDelegate.createPasscodeDelegate else { assertionFailure(); return }
                    metaWindow?.rootViewController = MetaFlowController(obvEngine: obvEngine, createPasscodeDelegate: createPasscodeDelegate)
                    metaWindow?.alpha = 0.0
                }
            }
        }
        
        // We make sure all the windows are instanciated
        
        if localAuthenticationWindow == nil {
            localAuthenticationWindow = UIWindow(windowScene: windowScene)
            guard let localAuthenticationDelegate = await appDelegate.localAuthenticationDelegate else { assertionFailure(); return }
            let localAuthenticationVC = LocalAuthenticationViewController(localAuthenticationDelegate: localAuthenticationDelegate, delegate: self)
            localAuthenticationWindow?.rootViewController = localAuthenticationVC
        }

        // If we reach this point, we know the initialization succeeded and that the metaWindow was initialized

        guard let initializerWindow = self.initializerWindow,
              let metaWindow = self.metaWindow,
              let localAuthenticationWindow = self.localAuthenticationWindow else {
            assertionFailure(); return
        }
        
        // Since the app did initialize, we don't want the initializerWindow to show the spinner ever again

        (initializerWindow.rootViewController as? InitializerViewController)?.appInitializationSucceeded()

        // We choose the most appropriate window to show depending on the current key window and on various state variables
        
        if sceneIsActive {
            
            // If there is a call in progress, show it instead of any other view controller

            if let callInProgress = callInProgress, !preferMetaWindowOverCallWindow {
                if callWindow == nil || (callWindow?.rootViewController as? CallViewHostingController)?.callUUID != callInProgress.uuid {
                    callWindow = UIWindow(windowScene: windowScene)
                    callWindow?.rootViewController = CallViewHostingController(call: callInProgress)
                }
                changeKeyWindow(to: callWindow)
                return
            }
            
            // At this point, there is not call in progress
            
            if initializerWindow.isKeyWindow || callWindow?.isKeyWindow == true || localAuthenticationWindow.isKeyWindow {
                if userSuccessfullyPerformedLocalAuthentication || !ObvMessengerSettings.Privacy.localAuthenticationPolicy.lockScreen {
                    changeKeyWindow(to: metaWindow)
                    return
                } else {
                    changeKeyWindow(to: localAuthenticationWindow)
                    if shouldAutomaticallyPerformLocalAuthentication {
                        shouldAutomaticallyPerformLocalAuthentication = false
                        (localAuthenticationWindow.rootViewController as? LocalAuthenticationViewController)?.performLocalAuthentication()
                    } else {
                        (localAuthenticationWindow.rootViewController as? LocalAuthenticationViewController)?.shouldPerformLocalAuthentication()
                    }
                    return
                }
            }
        } else {
            // When the user choosed to lock the screen, we hide the app content each time the scene becomes inactive
            if ObvMessengerSettings.Privacy.localAuthenticationPolicy.lockScreen {
                changeKeyWindow(to: initializerWindow)
            }
        }
    }
    
    
    private func debugDescriptionOfWindow(_ window: UIWindow) -> String {
        switch window {
        case initializerWindow:
            return "Initializer window"
        case localAuthenticationWindow:
            return "Local authentication window"
        case initializationFailureWindow:
            return "Initialization failure window"
        case metaWindow:
            return "Meta Window"
        case callWindow:
            return "Call Window"
        default:
            assertionFailure()
            return "Unknown"
        }
    }
    
    /// Exclusivemy called from ``func switchToNextWindowForScene(_ scene: UIScene) async``.
    @MainActor
    private func changeKeyWindow(to newKeyWindow: UIWindow?) {
        
        guard let newKeyWindow = newKeyWindow else { assertionFailure(); return }

        // Find the current key window, if none can be found, show one requested
        
        guard let currentKeyWindow = allWindows.compactMap({ $0 }).first(where: { $0.isKeyWindow }) else {
            newKeyWindow.alpha = 1.0
            newKeyWindow.makeKeyAndVisible()
            return
        }
        
        // If the current key window is the one requested, there is nothing left to do
        
        guard currentKeyWindow != newKeyWindow else { return }
        
        // We have a current key window and a (distinct) window that must become key and visisble.

        // If an animation is in progress, stop it
        
        if animator.state == UIViewAnimatingState.active {
            animator.stopAnimation(true)
        }

        // We choose the appropriate animation for the transition between the windows
        
        debugPrint("🪟 Changing from \(debugDescriptionOfWindow(currentKeyWindow)) to \(debugDescriptionOfWindow(newKeyWindow))")

        switch (currentKeyWindow, newKeyWindow) {
        case (initializerWindow, metaWindow),
            (metaWindow, callWindow),
            (callWindow, metaWindow):
            
            newKeyWindow.makeKeyAndVisible()

            animator.addAnimations {
                newKeyWindow.alpha = 1.0
            }
            
            animator.addCompletion { [weak self] animatingPosition in
                guard animatingPosition == .end else { return }
                // If the animation ended, we make sure all non-key windows are properly hidden
                self?.hideAllNonKeyWindows()
            }
  
            animator.startAnimation()
            
        default:
            
            // No animation
            newKeyWindow.alpha = 1.0
            newKeyWindow.makeKeyAndVisible()
            hideAllNonKeyWindows()
        }
        

    }
    
    
    private func hideAllNonKeyWindows() {
        let allNonKeyWindows = allWindows.compactMap({ $0 }).filter({ !$0.isKeyWindow })
        allNonKeyWindows.forEach { window in
            window.alpha = 0.0
        }
    }
    
    
    // MARK: - Managing calls
    
    @MainActor
    private func setCallInProgress(to call: GenericCall?, for scene: UIScene) async {
        _ = await NewAppStateManager.shared.waitUntilAppIsInitialized()
        callInProgress = call
        Task(priority: .userInitiated) {
            await switchToNextWindowForScene(scene)
        }
    }

    
    private func observeVoIPNotifications(_ scene: UIScene) {
        guard !callNotificationObserved else { return }
        defer { callNotificationObserved = true }
        observationTokens.append(contentsOf: [
            VoIPNotification.observeShowCallViewControllerForAnsweringNonCallKitIncomingCall { incomingCall in
                Task(priority: .userInitiated) { [weak self] in
                    self?.preferMetaWindowOverCallWindow = false
                    await self?.setCallInProgress(to: incomingCall, for: scene)
                }
            },
            VoIPNotification.observeNoMoreCallInProgress {
                Task(priority: .userInitiated) { [weak self] in
                    self?.preferMetaWindowOverCallWindow = false
                    await self?.setCallInProgress(to: nil, for: scene)
                }
            },
            VoIPNotification.observeNewOutgoingCall { newOutgoingCall in
                Task(priority: .userInitiated) { [weak self] in
                    self?.preferMetaWindowOverCallWindow = false
                    await self?.setCallInProgress(to: newOutgoingCall, for: scene)
                }
            },
            VoIPNotification.observeAnIncomingCallShouldBeShownToUser { newOutgoingCall in
                Task(priority: .userInitiated) { [weak self] in
                    self?.preferMetaWindowOverCallWindow = false
                    await self?.setCallInProgress(to: newOutgoingCall, for: scene)
                }
            },
            VoIPNotification.observeHideCallView(queue: .main) {
                Task(priority: .userInitiated) { [weak self] in
                    self?.preferMetaWindowOverCallWindow = true
                    await self?.switchToNextWindowForScene(scene)
                }
            },
            VoIPNotification.observeShowCallView(queue: .main) {
                Task(priority: .userInitiated) { [weak self] in
                    self?.preferMetaWindowOverCallWindow = false
                    await self?.switchToNextWindowForScene(scene)
                }
            },
        ])
    }

    
    private func processINStartCallIntent(startCallIntent: INStartCallIntent, obvEngine: ObvEngine) {

        os_log("📲 Process INStartCallIntent", log: Self.log, type: .info)

        guard let handle = startCallIntent.contacts?.first?.personHandle?.value else {
            os_log("📲 Could not get appropriate value of INStartCallIntent", log: Self.log, type: .error)
            return
        }

        ObvStack.shared.performBackgroundTaskAndWait { (context) in

            if let callUUID = UUID(handle), let item = try? PersistedCallLogItem.get(callUUID: callUUID, within: context) {
                let contacts = item.logContacts.compactMap { $0.contactIdentity?.typedObjectID }
                os_log("📲 Posting a userWantsToCallButWeShouldCheckSheIsAllowedTo notification following an INStartCallIntent", log: Self.log, type: .info)
                ObvMessengerInternalNotification.userWantsToCallButWeShouldCheckSheIsAllowedTo(contactIDs: contacts, groupId: try? item.getGroupIdentifier()).postOnDispatchQueue()
            } else if let contact = try? PersistedObvContactIdentity.getAll(within: context).first(where: { $0.getGenericHandleValue(engine: obvEngine) == handle }) {
                // To be compatible with previous 1to1 versions
                let contacts = [contact.typedObjectID]
                ObvMessengerInternalNotification.userWantsToCallButWeShouldCheckSheIsAllowedTo(contactIDs: contacts, groupId: nil).postOnDispatchQueue()
            } else {
                os_log("📲 Could not parse INStartCallIntent", log: Self.log, type: .fault)
            }
            
        }
    }


    // MARK: - Opening Olvid URLs

    @MainActor
    private func openOlvidURL(_ url: URL) async {
        assert(Thread.isMainThread)
        os_log("🥏 Call to openDeepLink with URL %{public}@", log: Self.log, type: .info, url.debugDescription)
        guard let olvidURL = OlvidURL(urlRepresentation: url) else { assertionFailure(); return }
        os_log("An OlvidURL struct was successfully created", log: Self.log, type: .info)
        await NewAppStateManager.shared.handleOlvidURL(olvidURL)
    }


}


// MARK: - LocalAuthenticationViewControllerDelegate

extension SceneDelegate: LocalAuthenticationViewControllerDelegate {
    
    @MainActor
    func userLocalAuthenticationDidSucceedOrWasNotRequired() {
        userSuccessfullyPerformedLocalAuthentication = true
        guard let scene = localAuthenticationWindow?.windowScene else { assertionFailure(); return }
        Task(priority: .userInitiated) {
            await switchToNextWindowForScene(scene)
        }
    }

    @MainActor
    func tooManyWrongPasscodeAttemptsCausedLockOut() {
        ObvMessengerInternalNotification.tooManyWrongPasscodeAttemptsCausedLockOut.postOnDispatchQueue()
    }
    
}


// MARK: - KeycloakSceneDelegate

extension SceneDelegate {
    
    func requestViewControllerForPresenting() async throws -> UIViewController {
        
        _ = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
        
        guard let metaWindow = metaWindow else {
            throw Self.makeError(message: "The meta window is not set, unexpected at this point")
        }
        
        guard let rootViewController = metaWindow.rootViewController else {
            throw Self.makeError(message: "The root view controller is not set, unexpected at this point")
        }
        
        assert(rootViewController is MetaFlowController)
        
        keycloakManagerWillPresentAuthenticationScreen = true
        
        return rootViewController
        
    }
    
}


// MARK: - PersistedObvContactIdentity utils

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
