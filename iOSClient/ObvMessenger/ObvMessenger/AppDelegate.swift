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
import CoreData
import os.log
import Intents
import ObvEngine
import CoreDataStack
import AppAuth

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var appInitializer: AppInitializer!
    var obvEngine: ObvEngine!
    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: AppDelegate.self))
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
                
        os_log("Application did finish launching with options", log: log, type: .info)
        
        self.appInitializer = AppInitializer()

        // Register for push notifications
        application.registerForRemoteNotifications()

        /* Enabling Updating with Background App Refresh. This will trigger a periodic call to:
         * optional func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void)
         */
        application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)

        // Set the shortcut item in case we were launched via a home screen quick action (and the app was not already loaded in memory)
        if let shortcutItem = launchOptions?[UIApplication.LaunchOptionsKey.shortcutItem] as? UIApplicationShortcutItem {
            self.appInitializer.application(application, performActionFor: shortcutItem, completionHandler: { _ in })
        }

        // Start the initialization process (without waiting for the active state)
        DispatchQueue.main.async { [weak self] in
            self?.appInitializer.initializeApp()
        }
        
        return true
    }
    
    
    func application(_ application: UIApplication, shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier) -> Bool {
        os_log("Application shouldAllowExtensionPointIdentifier", log: log, type: .debug)
        switch extensionPointIdentifier {
        case .keyboard:
            return ObvMessengerSettings.Advanced.allowCustomKeyboards
        default:
            return true
        }
    }
    
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        os_log("Application applicationDidEnterBackground", log: log, type: .info)
        guard AppStateManager.shared.currentState.isInitialized else {
            // This protects from trying to access the coredata stack that may not be ready if the app has not been initialized.
            os_log("Application did enter background before being initialized. We cannot schedule background tasks.", log: log, type: .error)
            return
        }
        obvEngine?.applicationDidEnterBackground()
        if #available(iOS 13.0, *) {
            BackgroundTasksManager.shared.cancelAllPendingBGTask()
            scheduleBackgroundTaskForCleaningExpiredMessages()
            scheduleBackgroundTaskForApplyingRetentionPolicies()
            scheduleBackgroundTaskForUpdatingBadge()
        }
    }
    
    
    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        assertionFailure()
        return nil
    }

    
    func applicationDidBecomeActive(_ application: UIApplication) {
        os_log("Application applicationDidBecomeActive", log: log, type: .info)
    }
    
    
    // This method is also called when sending a file through AirDrop, or when a configuration link is tapped
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        os_log("Application open url %{public}@", log: log, type: .info, url.debugDescription)
        return appInitializer.application(app, open: url, options: options)
    }
    
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        os_log("Application continue user activity", log: log, type: .info)
        return appInitializer.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }
    
    
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        os_log("Application perform action for shortcut", log: log, type: .info)
        self.appInitializer.application(application, performActionFor: shortcutItem, completionHandler: completionHandler)
    }

    
    // MARK: - Remote notifications
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        os_log("🍎✅ We received a remote notification device token: %{public}@", log: log, type: .info, deviceToken.hexString())
        appInitializer.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }
    
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        os_log("🍎 Application failed to register for remote notifications: %{public}@", log: log, type: .fault, error.localizedDescription)
        appInitializer.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        os_log("🌊 Application did receive remote notification", log: log, type: .info)
        appInitializer.application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandler)
    }
    
    
    // MARK: - Downloading Files in the Background
    // See https://developer.apple.com/documentation/foundation/url_loading_system/downloading_files_in_the_background
    
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        os_log("🌊 application:handleEventsForBackgroundURLSession:completionHandler called with identifier: %{public}@", log: log, type: .info, identifier)
        // Typically called when a background URLSession was initiated from an extension, but that extension did not finish the job
        appInitializer.application(application, handleEventsForBackgroundURLSession: identifier, completionHandler: completionHandler)
    }
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        os_log("🌊 Application performFetchWithCompletionHandler", log: log, type: .info)
        appInitializer.application(application, performFetchWithCompletionHandler: completionHandler)
    }
    
}
