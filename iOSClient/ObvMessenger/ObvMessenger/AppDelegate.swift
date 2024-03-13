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

@_exported import UIKit // this is to fix the need to import `UIKit` for several key parts of the app, introduced by tuist
import CoreData
import os.log
import Intents
import ObvEngine
import CoreDataStack
import AppAuth
import OlvidUtils
import ObvUICoreData
import ObvSettings


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, ObvErrorMaker {

    private let appMainManager = AppMainManager()
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: AppDelegate.self))
    static let errorDomain = "AppDelegate"

    var localAuthenticationDelegate: LocalAuthenticationDelegate? {
        get async {
            await appMainManager.localAuthenticationDelegate
        }
    }
    var createPasscodeDelegate: CreatePasscodeDelegate? {
        get async {
            await appMainManager.createPasscodeDelegate
        }
    }
    var appBackupDelegate: AppBackupDelegate? {
        get async {
            await appMainManager.appBackupDelegate
        }
    }
    
    var storeKitDelegate: StoreKitDelegate? {
        get async {
            await appMainManager.storeKitDelegate
        }
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        #if DEBUG
        // This prevents certain SwiftUI previews from crashing
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return true }
        #endif

        os_log("🧦 Application did finish launching with options", log: log, type: .info)

        // Initialize the BackgroundTasksManager as it must registers its tasks
        // Pass it to the App main manager that will register it with the managers holder
        
        let backgroundTasksManager = BackgroundTasksManager()
        
        // Initialize the UserNotificationsManager as it registers the UNUserNotificationCenter delegate.
        // This must be done before the app finishes launching.
        // See https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate

        let userNotificationsManager = UserNotificationsManager()

        // Start the app initialization passing in the managers that had to be created before the app finishes launching.
        
        Task {
            await appMainManager.initializeApp(backgroundTasksManager: backgroundTasksManager,
                                               userNotificationsManager: userNotificationsManager)
        }

        // Register for remote (push) notifications
        registerForRemoteNotificationsOnRealDeviceAndFailOnSimulator(application)

        return true
    }
    
    
    private func registerForRemoteNotificationsOnRealDeviceAndFailOnSimulator(_ application: UIApplication) {
        if ObvMessengerConstants.areRemoteNotificationsAvailable {
            application.registerForRemoteNotifications()
        } else {
            let error = Self.makeError(message: "Cannot register to remote notifications as we are not running on a real device")
            Task { [weak self] in
                await self?.appMainManager.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
            }
        }
    }
    
    
    func application(_ application: UIApplication, shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier) -> Bool {
        // os_log("Application shouldAllowExtensionPointIdentifier", log: log, type: .debug)
        switch extensionPointIdentifier {
        case .keyboard:
            return ObvMessengerSettings.Advanced.allowCustomKeyboards
        default:
            return true
        }
    }
    
    
    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        assertionFailure()
        return nil
    }

    
    // This method is also called when sending a file through AirDrop, or when a configuration link is tapped
    @MainActor
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        os_log("Application open url %{public}@", log: log, type: .info, url.debugDescription)
        assertionFailure("Not expected to be called anymore")
        return true
    }
    
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        os_log("Application continue user activity", log: log, type: .info)
        assertionFailure("Not expected to be called anymore")
        return true
    }
    
    @MainActor
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        os_log("Application perform action for shortcut", log: log, type: .info)
        assertionFailure("Not expected to be called anymore")
        return true
    }

    
    // MARK: - Remote notifications
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        os_log("🍎✅ We received a remote notification device token: %{public}@", log: log, type: .info, deviceToken.hexString())
        Task { [weak self] in await self?.appMainManager.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken) }
    }
    
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        os_log("🍎 Application failed to register for remote notifications: %{public}@", log: log, type: .fault, error.localizedDescription)
        Task { [weak self] in await self?.appMainManager.application(application, didFailToRegisterForRemoteNotificationsWithError: error) }
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        os_log("🫸🌊 Application did receive remote notification", log: log, type: .info)
        Task { [weak self] in await self?.appMainManager.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler) }
    }
    
    
    // MARK: - Downloading Files in the Background
    // See https://developer.apple.com/documentation/foundation/url_loading_system/downloading_files_in_the_background
    
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        os_log("🌊 application:handleEventsForBackgroundURLSession:completionHandler called with identifier: %{public}@", log: log, type: .info, identifier)
        // Typically called when a background URLSession was initiated from an extension, but that extension did not finish the job
        Task { [weak self] in await self?.appMainManager.application(application, handleEventsForBackgroundURLSession: identifier, completionHandler: completionHandler) }
    }
    
}
