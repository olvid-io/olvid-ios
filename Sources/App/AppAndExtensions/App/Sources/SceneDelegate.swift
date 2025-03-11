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
  

import UIKit
import os.log
import Intents
import ObvEngine
import OlvidUtils
import ObvUICoreData
import ObvAppTypes
import ObvAppCoreConstants

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: KeyboardWindow? // Can handle keyboard input
    var privacyWindow: UIWindow? // For iOS
    
    private var rootViewController: RootViewController?
    private let privacyViewControler = UIStoryboard(name: "LaunchScreen", bundle: nil).instantiateInitialViewController()!
    
    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "SceneDelegate")
    
    /// On some occasions, we want to prevent the privacy window from showing the next time ``SceneDelegate.sceneWillResignActive(_:)`` is called.
    /// This variable is typically set to `true` from a child view controller, just before showing a system alert. This is for example the case during onboarding,
    /// when requesting the authorization to send push notifications.
    fileprivate var preventPrivacyWindowFromShowingOnNextWillResignActive = false

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).

        os_log("🧦 scene willConnectTo", log: Self.log, type: .info)

        guard let windowScene = (scene as? UIWindowScene) else { assertionFailure(); return }

        let rootViewController = RootViewController()
        self.rootViewController = rootViewController
        let window = KeyboardWindow(windowScene: windowScene)
        window.rootViewController = rootViewController
        window.makeKeyAndVisible()
        self.window = window

        let privacyWindow = UIWindow(windowScene: windowScene)
        privacyWindow.windowLevel = .alert
        privacyWindow.rootViewController = privacyViewControler
        privacyWindow.makeKeyAndVisible()
        self.privacyWindow = privacyWindow

        if !connectionOptions.userActivities.isEmpty {
            os_log("📲 Scene will connect with user activities", log: Self.log, type: .info)
            rootViewController.continueUserActivities(connectionOptions.userActivities)
        }

        if !connectionOptions.urlContexts.isEmpty {
            os_log("📲 Scene will connect with url contexts", log: Self.log, type: .info)
            rootViewController.openURLContexts(connectionOptions.urlContexts)
        }

        if let shortcutItem = connectionOptions.shortcutItem {
            os_log("📲 Scene will connect with a shortcutItem", log: Self.log, type: .info)
            Task { [weak self] in
                assert(self?.rootViewController != nil)
                _ = await self?.rootViewController?.performActionFor(shortcutItem: shortcutItem)
            }
        }
        
    }
    
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        // Called when, e.g., the user taps on an Olvid backup file from the Files app.
        os_log("🧦 openURLContexts", log: Self.log, type: .info)
        rootViewController?.openURLContexts(URLContexts)
    }

    
    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
        ObvDisplayableLogs.shared.log("sceneDidDisconnect")
        os_log("🧦 sceneDidDisconnect", log: Self.log, type: .info)
    }

    
    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        os_log("🧦 sceneDidBecomeActive", log: Self.log, type: .info)
        ObvDisplayableLogs.shared.log("sceneDidBecomeActive")
        assert(rootViewController != nil)
        rootViewController?.sceneDidBecomeActive(scene)
        self.privacyWindow?.resignKey()
        self.privacyWindow?.isHidden = true
    }

    
    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
        os_log("🧦 sceneWillResignActive", log: Self.log, type: .info)
        ObvDisplayableLogs.shared.log("sceneWillResignActive")
        assert(rootViewController != nil)
        rootViewController?.sceneWillResignActive(scene)
        if !preventPrivacyWindowFromShowingOnNextWillResignActive {
            self.privacyWindow?.makeKeyAndVisible()
        }
        preventPrivacyWindowFromShowingOnNextWillResignActive = false
    }

    
    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
        os_log("🧦 sceneWillEnterForeground", log: Self.log, type: .info)
        ObvDisplayableLogs.shared.log("sceneWillEnterForeground")
        assert(rootViewController != nil)
        preventPrivacyWindowFromShowingOnNextWillResignActive = false
        rootViewController?.sceneWillEnterForeground(scene)
        window?.makeKeyAndVisible()
    }

    
    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information to restore the scene back to its current state.
        os_log("🧦 sceneDidEnterBackground", log: Self.log, type: .info)
        ObvDisplayableLogs.shared.log("sceneDidEnterBackground")
        assert(rootViewController != nil)
        rootViewController?.sceneDidEnterBackground(scene)
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
            assert(rootViewController != nil)
            await rootViewController?.continueUserActivity(userActivity)
        }
    }
    
    
    func scene(_ scene: UIScene, didFailToContinueUserActivityWithType userActivityType: String, error: Error) {
        os_log("📲 Scene did fail to continue user activity with type: %{public}@", log: Self.log, type: .error, userActivityType)
    }
    
    
    // MARK: - Performing Tasks

    @MainActor
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        // Called when the users taps on the "Scan QR code" shortcut on the app icon
        os_log("UIWindowScene perform action for shortcut", log: Self.log, type: .info)
        assert(rootViewController != nil)
        guard let rootViewController else { return false }
        return await rootViewController.performActionFor(shortcutItem: shortcutItem)
    }
        
}


// MARK: - Helper of all UIViewControllers

extension UIViewController {
    
    func preventPrivacyWindowSceneFromShowingOnNextWillResignActive() {
        (self.view.window?.windowScene?.delegate as? SceneDelegate)?.preventPrivacyWindowFromShowingOnNextWillResignActive = true
    }

}
