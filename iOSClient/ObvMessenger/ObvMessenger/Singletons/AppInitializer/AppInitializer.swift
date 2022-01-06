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

import Foundation
import os.log
import ObvEngine
import Intents
import OlvidUtils


final class AppInitializer {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "AppInitializer")
    private var observationTokens = [NSObjectProtocol]()
    private let internalQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        queue.isSuspended = true
        return queue
    }()
    
    private let queueForTransferingRemoteNotificationToEngine = DispatchQueue(label: "AppInitializer queue for remote notifications")

    private let fileSystemService: FileSystemService
    let windowsManager: WindowsManager
    let runningLog = RunningLogError()
    private(set) var obvEngine: ObvEngine?

    var initializationWasPerformed: Bool { obvEngine != nil }
    
    init() {
        // Perform a few initializations that must be done before application launching is finished or that must be performed on the main thread
        let appStateManager = AppStateManager.shared
        appStateManager.appType = .mainApp
        if #available(iOS 13.0, *) {
            _ = BackgroundTasksManager.shared
        }
        _ = AppTheme.shared

        self.fileSystemService = FileSystemService()
        self.fileSystemService.createAllDirectoriesIfRequired()
        
        let initializerViewController = InitializerViewController()
        initializerViewController.runningLog = runningLog
        self.windowsManager = WindowsManager(initializerViewController: initializerViewController)

        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeAppStateChanged(queue: OperationQueue.main) { [weak self] (previousState, currentState) in
                self?.processAppStateChangedNotification(previousState: previousState, currentState: currentState)
            },
        ])
    }
    
    
    private func processAppStateChangedNotification(previousState: AppState, currentState: AppState) {
        assert(Thread.isMainThread)
        if !previousState.isInitializedAndActive && currentState.isInitializedAndActive {
            guard let obvEngine = self.obvEngine else { return } // The obvEngine is nil when the initialization operation cancels
            obvEngine.applicationIsInitializedAndActive()
        }
    }
    
    
    // Called asynchronously from the AppDelegate
    func initializeApp() {
        assert(Thread.isMainThread)
        guard AppStateManager.shared.currentState.isJustLaunched else { return }
        assert(!initializationWasPerformed)
        AppStateManager.shared.setStateToInitializing()
        assert(!AppStateManager.shared.currentState.isJustLaunched)
        assert(AppStateManager.shared.currentState.isInitializing)
        let op = InitializeAppOperation(runningLog: runningLog, completion: initializeAppOperationDidFinish)
        op.queuePriority = .veryHigh
        internalQueue.addOperation(op)
        internalQueue.isSuspended = false
    }

    
    private func initializeAppOperationDidFinish(result: Result<ObvEngine, InitializeAppOperationReasonForCancel>) {
        assert(OperationQueue.current == internalQueue)
        switch result {
        case .success(let obvEngine):
            self.obvEngine = obvEngine
            ObvPushNotificationManager.shared.obvEngine = obvEngine
            DispatchQueue.main.sync {
                (UIApplication.shared.delegate as? AppDelegate)?.obvEngine = obvEngine // Make the engine available everywhere
                let appRootViewController = MetaFlowController(fileSystemService: fileSystemService)
                let localAuthenticationViewController = LocalAuthenticationViewController()
                localAuthenticationViewController.delegate = AppStateManager.shared
                self.windowsManager.setWindowsRootViewControllers(localAuthenticationViewController: localAuthenticationViewController, appRootViewController: appRootViewController)
            }
            let op = PostAppInitializationOperation(obvEngine: obvEngine)
            op.queuePriority = .veryHigh
            internalQueue.addOperation(op)
            ObvMessengerInternalNotification.AppInitializationEnded
                .postOnDispatchQueue()
        case .failure(let reasonForCancel):
            internalQueue.isSuspended = true
            DispatchQueue.main.sync {
                windowsManager.showInitializationFailureViewController(error: reasonForCancel)
            }
        }
    }
    
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        internalQueue.addOperation { [weak self] in
            let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
            os_log("🍎✅ We received a remote notification device token: %{public}@", log: log, type: .info, deviceToken.hexString())
            DispatchQueue.main.async {
                ObvPushNotificationManager.shared.currentDeviceToken = deviceToken
                ObvPushNotificationManager.shared.tryToRegisterToPushNotifications()
            }
        }
    }
    
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        internalQueue.addOperation { [weak self] in
            let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
            os_log("🍎 Application failed to register for remote notifications: %{public}@", log: log, type: .fault, error.localizedDescription)
            if ObvMessengerConstants.isRunningOnRealDevice == true {
                let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
                os_log("%@", log: log, type: .error, error.localizedDescription)
            }
            DispatchQueue.main.async {
                ObvPushNotificationManager.shared.tryToRegisterToPushNotifications()
            }
        }
    }

    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        internalQueue.addOperation { [weak self] in
            guard let _self = self else { assertionFailure(); completionHandler(.failed); return }
            guard let obvEngine = _self.obvEngine else { assertionFailure(); completionHandler(.failed); return }
            let tag = UUID()
            let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
            os_log("Receiving a remote notification. We tag is as %{public}@", log: log, type: .debug, tag.uuidString)
            
            if let pushTopic = userInfo["topic"] as? String {
                // We are receiving a notification originated in the keycloak server
                
                KeycloakManager.shared.forceSyncManagedIdentitiesAssociatedWithPushTopics(pushTopic) { result in
                    switch result {
                    case .success:
                        os_log("🌊 We sucessfully sync the appropriate identity with the keycloak server, calling the completion handler of the background notification with tag %{public}@", log: log, type: .info, tag.uuidString)
                        completionHandler(.newData)
                        return
                    case .failure(let error):
                        os_log("🌊 The sync of the appropriate identity with the keycloak server failed: %{public}@. Calling the completion handler of the background notification with tag %{public}@", log: log, type: .info, error.localizedDescription, tag.uuidString)
                        completionHandler(.failed)
                        return
                    }
                }

            } else {

                // We are receiving a notification indicating new data is available on the server

                let completionHandlerForEngine: (UIBackgroundFetchResult) -> Void = { (result) in
                    defer { completionHandler(result) }
                    os_log("🌊 Calling the completion handler of the remote notification tagged as %{public}@. The result is %{public}@", log: log, type: .info, tag.uuidString, result.debugDescription)
                }

                _self.queueForTransferingRemoteNotificationToEngine.async {
                    obvEngine.application(didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandlerForEngine)
                }

            }
            
        }
    }
    
    
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        assert(Thread.isMainThread)
        guard initializationWasPerformed else { assertionFailure(); completionHandler(false); return }
        let log = self.log
        internalQueue.addOperation {
            guard let shortcut = ApplicationShortcut(shortcutItem.type) else { assertionFailure(); return }
            let deepLink: ObvDeepLink
            switch shortcut {
            case .scanQRCode:
                deepLink = ObvDeepLink.qrCodeScan
            }
            os_log("🥏 Sending a UserWantsToNavigateToDeepLink notification for shortut item %{public}@", log: log, type: .info, shortcut.description)
            ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                .postOnDispatchQueue()
            completionHandler(true)
        }
    }
    
    
    // This method is also called when sending a file through AirDrop
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        assert(Thread.isMainThread)
        os_log("Call to Application open url %{public}@", log: log, type: .info, url.debugDescription)
        guard initializationWasPerformed else { assertionFailure(); return false }
        if url.scheme == "olvid" {
            guard var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return false }
            urlComponents.scheme = "https"
            guard let newUrl = urlComponents.url else { return false }
            guard let olvidURL = OlvidURL(urlRepresentation: newUrl) else { assertionFailure(); return false }
            AppStateManager.shared.handleOlvidURL(olvidURL)
            return true
        } else if url.isFileURL {
            /* We are certainly dealing with an AirDrop'ed file. See
             * https://developer.apple.com/library/archive/qa/qa1587/_index.html
             * for handling Open in...
             */
            let deepLink = ObvDeepLink.airDrop(fileURL: url)
            ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                .postOnDispatchQueue()
            return true
        } else {
            return false
        }
    }

    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        assert(Thread.isMainThread)
        if let url = userActivity.webpageURL {
            os_log("Call to Application continue user activity with webpage URL %{public}@", log: log, type: .info, url.debugDescription)
            // This is typically called when scanning (tapping?) an invite link
            return openOlvidURL(url)
        } else if let startAudioCallIntent = userActivity.interaction?.intent as? INStartAudioCallIntent {
            AppStateManager.shared.addCompletionHandlerToExecuteWhenInitializedAndActive { [weak self] in
                guard let obvEngine = self?.obvEngine else { return }
                let op = ProcessINStartAudioCallIntentOperation(startAudioCallIntent: startAudioCallIntent, obvEngine: obvEngine)
                self?.internalQueue.addOperation(op)
            }
            return true
        } else {
            return false
        }
    }
    
    
    private func openOlvidURL(_ url: URL) -> Bool {
        assert(Thread.isMainThread)
        os_log("🥏 Call to openDeepLink with URL %{public}@", log: log, type: .info, url.debugDescription)
        guard let olvidURL = OlvidURL(urlRepresentation: url) else { assertionFailure(); return false }
        os_log("An OlvidURL struct was successfully created", log: log, type: .info)
        AppStateManager.shared.handleOlvidURL(olvidURL)
        return true
    }

    
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        assert(Thread.isMainThread)
        let log = self.log
        internalQueue.addOperation { [weak self] in
            // Typically called when a background URLSession was initiated from an extension, but that extension did not finish the job
            os_log("⛑ handleEventsForBackgroundURLSession called with identifier %{public}@", log: log, type: .info, identifier)
            guard let obvEngine = self?.obvEngine else { assertionFailure(); completionHandler(); return }
            DispatchQueue(label: "Queue created for storing a completion handler").async {
                obvEngine.storeCompletionHandler(completionHandler, forHandlingEventsForBackgroundURLSessionWithIdentifier: identifier)
            }
        }
    }
    
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        assert(Thread.isMainThread)
        let log = self.log
        internalQueue.addOperation { [weak self] in
            let tag = UUID()
            os_log("We are performing a background fetch. We tag it as @{public}@", log: log, type: .info, tag.uuidString)
            let completionHandlerForEngine: (UIBackgroundFetchResult) -> Void = { (result) in
                defer { completionHandler(result) }
                os_log("Calling the completion handler of the background fetch tagged as @{public}@. The result is %{public}@", log: log, type: .info, tag.uuidString, result.debugDescription)
                if result == .failed { assertionFailure() }
            }
            guard let obvEngine = self?.obvEngine else { assertionFailure(); completionHandler(.failed); return }
            DispatchQueue(label: "Queue created for handling background fetch tagged \(tag.uuidString)").async {
                obvEngine.application(performFetchWithCompletionHandler: completionHandlerForEngine)
            }
        }
    }
}
