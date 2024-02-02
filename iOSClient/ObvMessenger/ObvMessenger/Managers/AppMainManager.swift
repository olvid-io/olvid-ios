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
import ObvTypes
import ObvUI
import ObvUICoreData
import ObvSettings
import ObvDesignSystem


final actor AppMainManager: ObvErrorMaker {
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "AppMainManager")
    private var observationTokens = [NSObjectProtocol]()
    
    static let errorDomain = "AppMainManager"

    private let runningLog = RunningLogError()
    
    private let fileSystemService = FileSystemService()
    private var appManagersHolder: AppManagersHolder?
    private var appCoordinatorsHolder: AppCoordinatorsHolder?

    private var metaFlowControllerViewDidAppearAtLeastOnce = false

    private(set) var currentAppState = NewAppState.initializationRequired
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func changeAppStateTo(_ newAppState: NewAppState) {
        os_log("Will change state from <%{public}@> to <%{public}@>", log: Self.log, type: .info, currentAppState.debugDescription, newAppState.debugDescription)
        guard newAppState.level != currentAppState.level else { return }
        switch (currentAppState, newAppState) {
        case (.initializationRequired, .initializing):
            currentAppState = newAppState
        case (.initializing, .initializationFailed):
            currentAppState = newAppState
        case (.initializing, .initializedButWasNeverOnScreen):
            currentAppState = newAppState
        case (.initializedButWasNeverOnScreen, .initializedAndMetaFlowControllerViewDidAppear):
            currentAppState = newAppState
        default:
            os_log("Unexpected app state transition from %{public}@ to %{public}@", log: Self.log, type: .fault, currentAppState.debugDescription, newAppState.debugDescription)
            assertionFailure("Unexpected app state transition \(currentAppState.debugDescription) --> \(newAppState.debugDescription)")
        }
        Task {
            await NewAppStateManager.shared.performBlocksAsStateChanged()
        }
    }

    
    /// Called by the AppDelegate.
    /// The managers that are passed here were created early because the need to exist before the app finishes launching (in the iOS lifecycle sense).
    /// This method is called before the app lauching is done (in particular, before it is is active).
    func initializeApp(backgroundTasksManager: BackgroundTasksManager, userNotificationsManager: UserNotificationsManager) async {
        do {
            try await initializeAppIfRequired(backgroundTasksManager: backgroundTasksManager,
                                              userNotificationsManager: userNotificationsManager)
        } catch {
            changeAppStateTo(.initializationFailed(error: error, runningLog: runningLog))
            return
        }
    }
    
    
    private func initializeAppIfRequired(backgroundTasksManager: BackgroundTasksManager, userNotificationsManager: UserNotificationsManager) async throws {
        
        // Ensure the app and the engine are initialized exactly once
        switch currentAppState {
        case .initializationRequired:
            // Initialization required, it will be performed now
            break
        default:
            assertionFailure("The initializeAppIfRequired is not expected to be called twice")
            return
        }
        // Initialize the app state manager singleton and change the state to initializing
        await NewAppStateManager.shared.setAppMainManager(self)
        changeAppStateTo(.initializing)
        
        await performPreInitialization()
        try performAppCoreDataStackInitialization()
        let obvEngine = try await performEngineAndEngineCoreDataStackInitialization()
        initializeManagers(obvEngine: obvEngine,
                           backgroundTasksManager: backgroundTasksManager,
                           userNotificationsManager: userNotificationsManager)
        initializeCoordinators(obvEngine: obvEngine)
        await performPostInitialization(obvEngine: obvEngine)

        observeNotifications()
        
        changeAppStateTo(.initializedButWasNeverOnScreen(obvEngine: obvEngine))
        
    }
    
    
    /// We observe the `MetaFlowControllerViewDidAppear` notification.
    /// Since the `MetaWindow` is created only *after* app initialization succeeded,
    /// (see the `SceneDelegate`), we know we won't miss the notification.
    private func observeNotifications() {
        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeMetaFlowControllerViewDidAppear {
                Task { [weak self] in await self?.processMetaFlowControllerViewDidAppear() }
            },
            ObvMessengerInternalNotification.observeRequestRunningLog { [weak self] completion in
                guard let _self = self else { return }
                completion(_self.runningLog)
            },
            ObvEngineNotificationNew.observeAPushTopicWasReceivedViaWebsocket(within: NotificationCenter.default) { pushTopic in
                Task { [weak self] in try await self?.transferTheReceivedPushTopicToTheKeycloakManager(pushTopic: pushTopic) }
            },
            ObvEngineNotificationNew.observeAKeycloakTargetedPushNotificationReceivedViaWebsocket(within: NotificationCenter.default) { ownedCryptoId in
                Task { [weak self] in try await self?.requestSyncOfOwnedIdentityToTheKeycloakManager() }
            },
            ObvMessengerCoreDataNotification.observeOwnedIdentityHiddenStatusChanged { _, _ in
                Task { await LatestCurrentOwnedIdentityStorage.shared.removeLatestCurrentOWnedIdentityStored() }
            },
        ])
    }
    
    
    private func processMetaFlowControllerViewDidAppear() async {

        let obvEngine = await NewAppStateManager.shared.waitUntilAppIsInitialized()

        changeAppStateTo(.initializedAndMetaFlowControllerViewDidAppear(obvEngine: obvEngine))

        let forTheFirstTime = !metaFlowControllerViewDidAppearAtLeastOnce
        metaFlowControllerViewDidAppearAtLeastOnce = true

        await obvEngine.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        
        assert(appManagersHolder != nil)
        await appManagersHolder?.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        
        assert(appCoordinatorsHolder != nil)
        await appCoordinatorsHolder?.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        
    }
    
    
    private func performPreInitialization() async {
        
        runningLog.addEvent(message: "PreInitialization starts")
        defer { runningLog.addEvent(message: "PreInitialization ends") }

        runningLog.addEvent(message: "Writing down preferences")
        ObvMessengerConstants.writeToPreferences()
        
        // Initialize the App theme
        _ = AppTheme.shared
        
        // Initialize the File System service since it is required before trying to load the persistent container
        runningLog.addEvent(message: "Initializing the filesystem service")
        fileSystemService.createAllDirectoriesIfRequired()

    }
    
    
    private func performAppCoreDataStackInitialization() throws {
        
        runningLog.addEvent(message: "AppCoreDataStackInitialization starts")
        defer { runningLog.addEvent(message: "AppCoreDataStackInitialization ends") }
        
        // Initialize the CoreData Stack
        runningLog.addEvent(message: "Initializing the App Core Data stack")
        do {
            try ObvStack.initSharedInstance(transactionAuthor: ObvUICoreDataConstants.AppType.mainApp.transactionAuthor,
                                            runningLog: runningLog,
                                            enableMigrations: true)
        } catch let error {
            runningLog.addEvent(message: "The initialization of the App Core Data stack failed:\n---\n---\n \(error.localizedDescription)")
            throw error
        }
        runningLog.addEvent(message: "The initialization of the App Core Data stack was successful")
        
        // Perform app migrations and handle exceptional situations
        runningLog.addEvent(message: "Performing exception migrations")
        migrationFromBuild147ToBuild148()
        migrationToV0_9_0()
        migrationToV0_9_5()
        migrationToV0_9_11()
        migrationToV0_9_14()
        migrationToV0_9_17()
        migrationToV0_11_1()
        migrationToV0_12_5()
        migrationToV0_12_6()
        migrationToV0_12_8()
        migrationToV1_4()
    }
    
    
    private func performEngineAndEngineCoreDataStackInitialization() async throws -> ObvEngine {
        
        runningLog.addEvent(message: "EngineAndEngineCoreDataStackInitialization starts")
        defer { runningLog.addEvent(message: "EngineAndEngineCoreDataStackInitialization ends") }

        // Initialize a BackgroundTaskManagerBasedOnUIApplication instance, implementing the ObvBackgroundTaskManager, required to start the engine
        let backgroundTaskManagerBasedOnUIApplication = await initializeBackgroundTaskManagerBasedOnUIApplication()
        
        // Initialize the Oblivious Engine
        runningLog.addEvent(message: "Initializing the Engine")
        let obvEngine: ObvEngine
        do {
            let mainEngineContainer = ObvUICoreDataConstants.ContainerURL.mainEngineContainer.url
            ObvEngine.mainContainerURL = mainEngineContainer
            obvEngine = try ObvEngine.startFull(logPrefix: "FullEngine",
                                                appNotificationCenter: NotificationCenter.default,
                                                backgroundTaskManager: backgroundTaskManagerBasedOnUIApplication,
                                                sharedContainerIdentifier: ObvMessengerConstants.appGroupIdentifier,
                                                supportBackgroundTasks: ObvMessengerConstants.isRunningOnRealDevice,
                                                appType: .mainApp,
                                                runningLog: runningLog)
        } catch let error {
            runningLog.addEvent(message: "The Engine initialization failed: \(error.localizedDescription)")
            assertionFailure()
            throw error
        }
        runningLog.addEvent(message: "The initialization of the Engine was successful")

        return obvEngine
        
    }
    
    
    private func initializeManagers(obvEngine: ObvEngine, backgroundTasksManager: BackgroundTasksManager, userNotificationsManager: UserNotificationsManager) {
        runningLog.addEvent(message: "Initialization of the managers starts")
        defer { runningLog.addEvent(message: "Initialization of the managers ends") }
        self.appManagersHolder = AppManagersHolder(obvEngine: obvEngine,
                                                   backgroundTasksManager: backgroundTasksManager,
                                                   userNotificationsManager: userNotificationsManager)
    }
    
    
    private func initializeCoordinators(obvEngine: ObvEngine) {
        runningLog.addEvent(message: "Initialization of the coordinators starts")
        defer { runningLog.addEvent(message: "Initialization of the coordinators ends") }
        self.appCoordinatorsHolder = AppCoordinatorsHolder(obvEngine: obvEngine)
    }
    
    @MainActor
    private func initializeBackgroundTaskManagerBasedOnUIApplication() -> BackgroundTaskManagerBasedOnUIApplication {
        BackgroundTaskManagerBasedOnUIApplication()
    }
    
    
    private func performPostInitialization(obvEngine: ObvEngine) async {
        
        runningLog.addEvent(message: "PostInitialization starts")
        defer { runningLog.addEvent(message: "PostInitialization ends") }

        // Initialize NetworkStatus singleton
        runningLog.addEvent(message: "Initializing the network status monitor")
        _ = NetworkStatus.shared
        
        // Initialize the ObvPushNotificationManager singleton
        _ = ObvPushNotificationManager.shared
        
        // Finishing touches for certain migrations
        migrationToV0_9_4(obvEngine: obvEngine)
        await migrationToPerformAfterBuild586()
        await migrationToPerformAfterBuild600()

        // Performing post initialization tasks for all managers
        assert(appManagersHolder != nil)
        await appManagersHolder?.performPostInitialization()
        
        // Delete old files from the tmp directory
        deleteOldTemporaryFiles()
        
        // Delete old displayable logs
        do {
            try ObvDisplayableLogs.shared.deleteLogsOlderThan(date: Date(timeIntervalSinceNow: -TimeInterval(days: 5)))
        } catch {
            assertionFailure(error.localizedDescription)
            // In production, continue anyway
        }
        
        // Print a few logs on startup
        printInitialDebugLogs()

    }
    
    
    private func deleteOldTemporaryFiles() {
        DispatchQueue(label: "Internal queue for deleting old temporary files").async {
            do {
                let urlForTempFiles = ObvUICoreDataConstants.ContainerURL.forTempFiles.url
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: urlForTempFiles.path, isDirectory: &isDirectory) else {
                    os_log("The temp directory %{public}@ does not exist", log: Self.log, type: .fault, urlForTempFiles.path)
                    assertionFailure()
                    return
                }
                guard isDirectory.boolValue else {
                    os_log("The temp URL %{public}@ is not a directory", log: Self.log, type: .fault, urlForTempFiles.path)
                    assertionFailure()
                    return
                }
                let dateLimit = Date(timeIntervalSinceNow: -TimeInterval(months: 2))
                let keys: [URLResourceKey] = [.creationDateKey]
                let fileURLs = try FileManager.default.contentsOfDirectory(at: urlForTempFiles, includingPropertiesForKeys: keys)
                for fileURL in fileURLs {
                    guard let attributes = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
                    guard let creationDate = attributes.creationDate, creationDate < dateLimit else { debugPrint("Keep"); return }
                    // Make sure we are considering a regular file
                    guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else { continue }
                    guard !isDirectory.boolValue else { return }
                    // If we reach this point, we should delete the archive
                    try? FileManager.default.removeItem(at: fileURL)
                }
            } catch {
                os_log("We could not clean old temporary files: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }
    }
    
}


// MARK: Methods called from the App Delegate

extension AppMainManager {
        
    /// Upong receiving a device token, we post a registration block on the internal queue. We know for sure that this block will execute *after* a successful initialisation process.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) async {
        os_log("🍎✅ We received a remote notification device token: %{public}@", log: Self.log, type: .info, deviceToken.hexString())
        _ = await NewAppStateManager.shared.waitUntilAppIsInitialized()
        await ObvPushNotificationManager.shared.setCurrentDeviceToken(to: deviceToken)
        await ObvPushNotificationManager.shared.requestRegisterToPushNotificationsForAllActiveOwnedIdentities()
    }
    
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) async {
        os_log("🍎 Application failed to register for remote notifications: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
        _ = await NewAppStateManager.shared.waitUntilAppIsInitialized()
        if ObvMessengerConstants.areRemoteNotificationsAvailable == true {
            os_log("%@", log: Self.log, type: .error, error.localizedDescription)
        }
        await ObvPushNotificationManager.shared.requestRegisterToPushNotificationsForAllActiveOwnedIdentities()
    }

    
    @MainActor
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) async {
        
        let tag = UUID()
        os_log("Receiving a remote notification. We tag is as %{public}@", log: Self.log, type: .debug, tag.uuidString)

        let obvEngine = await NewAppStateManager.shared.waitUntilAppIsInitialized()
                
        if let pushTopic = userInfo["topic"] as? String {
            // We are receiving a notification originated in the keycloak server
            
            os_log("🧥 The received notification is keycloak push topic: %{public}@", log: Self.log, type: .debug, pushTopic)
            
            do {
                try await transferTheReceivedPushTopicToTheKeycloakManager(pushTopic: pushTopic)
            } catch {
                os_log("🌊 The sync of the appropriate identity with the keycloak server failed: %{public}@. Calling the completion handler of the background notification with tag %{public}@", log: Self.log, type: .info, error.localizedDescription, tag.uuidString)
                completionHandler(.failed)
                return
            }
            
            os_log("🌊 We sucessfully sync the appropriate identity with the keycloak server, calling the completion handler of the background notification with tag %{public}@", log: Self.log, type: .info, tag.uuidString)
            completionHandler(.newData)
            return
            
        } else if userInfo["keycloak"] != nil {

            os_log("🧥 The received notification is keycloak notification targeted for our owned identity", log: Self.log, type: .debug)

            do {
                try await requestSyncOfOwnedIdentityToTheKeycloakManager()
            } catch {
                assertionFailure(error.localizedDescription)
                os_log("🌊 The sync of all identities with the keycloak server failed: %{public}@. Calling the completion handler of the background notification with tag %{public}@", log: Self.log, type: .info, error.localizedDescription, tag.uuidString)
                completionHandler(.failed)
                return
            }
            
            os_log("🌊 We sucessfully synced all managed identities with the keycloak server, calling the completion handler of the background notification with tag %{public}@", log: Self.log, type: .info, tag.uuidString)
            completionHandler(.newData)
            return

        } else if userInfo["ownedDevices"] != nil {

            os_log("🧥 The received notification is an ownedDevices notification targeted for our owned identity", log: Self.log, type: .debug)

            Task {
                do {
                    try await obvEngine.performOwnedDeviceDiscoveryForAllOwnedIdentities()
                    await ObvPushNotificationManager.shared.requestRegisterToPushNotificationsForAllActiveOwnedIdentities()
                    completionHandler(.newData)
                } catch {
                    completionHandler(.failed)
                    return
                }
            }
            
            return
            
        } else {
            
            // We are receiving a notification indicating new data is available on the server
            
            let completionHandlerForEngine: (UIBackgroundFetchResult) -> Void = { (result) in
                os_log("🌊 Calling the completion handler of the remote notification tagged as %{public}@. The result is %{public}@", log: Self.log, type: .info, tag.uuidString, result.debugDescription)
                DispatchQueue.main.async {
                    completionHandler(result)
                }
            }
            
            DispatchQueue(label: "Queue for transfering remote notification to engine").async {
                obvEngine.application(didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completionHandlerForEngine)
            }
            
        }
            
    }
    
    
    private func transferTheReceivedPushTopicToTheKeycloakManager(pushTopic: String) async throws {
        try await KeycloakManagerSingleton.shared.forceSyncManagedIdentitiesAssociatedWithPushTopics(pushTopic)
    }
    
    
    /// For now, we do not specify the owned identity although it is available in the notification
    private func requestSyncOfOwnedIdentityToTheKeycloakManager() async throws {
        try await KeycloakManagerSingleton.shared.syncAllManagedIdentities()
    }
    
    
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        // Typically called when a background URLSession was initiated from an extension, but that extension did not finish the job
        Task {
            let obvEngine = await NewAppStateManager.shared.waitUntilAppIsInitialized()
            os_log("🌊 handleEventsForBackgroundURLSession called with identifier %{public}@", log: Self.log, type: .info, identifier)
            do {
                try obvEngine.storeCompletionHandler(completionHandler, forHandlingEventsForBackgroundURLSessionWithIdentifier: identifier)
            } catch {
                os_log("Could not store completion handler: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }
    }
    
}


// MARK: AppCoreDataStackInitialization utils

extension AppMainManager {

    private func migrationToV1_4() {
        guard let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier) else { return }
        userDefaults.removeObject(forKey: "settings.voip.isCallKitEnabled")
    }
    
    private func migrationToV0_12_12() {
        guard let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier) else { return }
        userDefaults.removeObject(forKey: "settings.interface.useOldDiscussionInterface")
    }
    
    private func migrationToV0_12_8() {
        guard let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier) else { return }
        userDefaults.removeObject(forKey: "requestIdentifiersOfSilentNotificationsAddedByExtension")
    }
    
    private func migrationToV0_12_5() {
        guard let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier) else { return }
        userDefaults.removeObject(forKey: "settings.interface.useOldListOfDiscussionsInterface")
    }
    
    private func migrationToV0_12_6() {
        guard let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier) else { return }
        userDefaults.removeObject(forKey: "settings.AnnouncingGroupsV2.wasShownAndPermanentlyDismissedByUser")
        userDefaults.removeObject(forKey: "io.olvid.snackBarCoordinator.lastDisplayDate.announceGroupsV2")
    }
    
    private func migrationToV0_9_0() {
        guard let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier) else { return }
        userDefaults.removeObject(forKey: "settings.discussions.doFetchContentRichURLsMetadata.withinDiscussion")
        userDefaults.removeObject(forKey: "settings.discussions.doSendReadReceipt.withinDiscussion")
    }


    private func migrationToV0_9_4(obvEngine: ObvEngine) {
        
        // Remove secure call from Beta
        
        ObvMessengerSettings.Alert.removeSecureCallsInBeta()
        
        // Download user data if necessary
        
        let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)!
        let key = ObvMessengerConstants.userDataHasBeenDownloadedAfterMigration

        guard !userDefaults.bool(forKey: key) else { return /* Already done the job */}

        do {
            try obvEngine.downloadAllUserData()
        } catch {
            os_log("Could not download user data: %{public}@", log: Self.log, type: .info, error.localizedDescription)
            assertionFailure()
        }

        userDefaults.set(true, forKey: key) /* Mark as Done */
        
    }

    
    /// When migrating to a build larger than 586, we delete all SendMessageIntents as they were using non-persistent (NSManagedObjectID, that can change when a heavyweight migration is performed). Since build 587, they use permanentIDs.
    /// We do it only once. To make sure of this we set a Boolean value in the preferences.
    private func migrationToPerformAfterBuild586() async {
        guard let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier) else { assertionFailure(); return }
        let key = "io.olvid.allIntentsOfBuild586WereDeleted"
        if userDefaults.value(forKey: key) == nil {
            do {
                try await INInteraction.deleteAll()
            } catch {
                assertionFailure()
                return
            }
            userDefaults.setValue(true, forKey: key)
        }
    }
    
    
    private func migrationToPerformAfterBuild600() async {
        guard let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier) else { return }
        userDefaults.removeObject(forKey: "settings.featureflags.toggleNewDiscussionTab")
    }
    
    
    private func migrationToV0_9_17() {
        guard let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier) else { return }
        userDefaults.removeObject(forKey: "obvNewFeatures.privacySetting.wasSeenByUser")
    }
    
    private func migrationToV0_9_14() {
        guard let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier) else { return }
        userDefaults.removeObject(forKey: "settings.voip.useLoadBalancedTurnServers")
    }

    private func migrationToV0_9_11() {
        guard let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier) else { return }
        userDefaults.removeObject(forKey: "settings.interface.useNextGenDiscussionInterface")
        userDefaults.removeObject(forKey: "settings.interface.showReplyToInNextGenDiscussionInterface")
        userDefaults.removeObject(forKey: "settings.interface.fetchBatchSizeInNextGenDiscussionInterface")
        userDefaults.removeObject(forKey: "settings.interface.monthsLimitInNextGenDiscussionInterface")
        userDefaults.removeObject(forKey: "settings.interface.restrictToTextBodyInNextGenDiscussionInterface")
    }

    
    private func migrationToV0_9_5() {
        guard let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier) else { return }
        userDefaults.removeObject(forKey: "settings.privacy.lockScreenStartPeriod")
    }

    
    /// Build 148 moves the Olvid internal preferences from the app space to the shared container space between the App and the share extension.
    /// This method performs the required steps so as to migrate previous user preferences from the old location to the new one.
    private func migrationFromBuild147ToBuild148() {
        
        let oldUserDefaults = UserDefaults(suiteName: "io.olvid.messenger.settings")!
        let newUserDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)!
        // Migrate Downloads.maxAttachmentSizeForAutomaticDownload
        do {
            let oldKey = "downloads.maxAttachmentSizeForAutomaticDownload"
            let newKey = "settings.downloads.maxAttachmentSizeForAutomaticDownload"
            if newUserDefaults.object(forKey: newKey) == nil {
                if let value = oldUserDefaults.object(forKey: oldKey) as? Int {
                    newUserDefaults.set(value, forKey: newKey)
                    oldUserDefaults.removeObject(forKey: oldKey)
                }
            }
        }
        // Migrate Interface.identityColorStyle
        do {
            let oldKey = "interface.identityColorStyle"
            let newKey = "settings.interface.identityColorStyle"
            if newUserDefaults.object(forKey: newKey) == nil {
                if let value = oldUserDefaults.object(forKey: oldKey) as? Int {
                    newUserDefaults.set(value, forKey: newKey)
                    oldUserDefaults.removeObject(forKey: oldKey)
                }
            }
        }
        // Migrate Discussions.doSendReadReceipt
        do {
            let oldKey = "discussions.doSendReadReceipt"
            let newKey = "settings.discussions.doSendReadReceipt"
            if newUserDefaults.object(forKey: newKey) == nil {
                if let value = oldUserDefaults.object(forKey: oldKey) as? Bool {
                    newUserDefaults.set(value, forKey: newKey)
                    oldUserDefaults.removeObject(forKey: oldKey)
                }
            }
        }
        // Migrate Discussions.doSendReadReceipt (specific conversations)
        do {
            let oldKey = "discussions.doSendReadReceipt.withinDiscussion"
            let newKey = "settings.discussions.doSendReadReceipt.withinDiscussion"
            if newUserDefaults.dictionary(forKey: newKey) == nil {
                if let value = oldUserDefaults.dictionary(forKey: oldKey) {
                    newUserDefaults.set(value, forKey: newKey)
                    oldUserDefaults.removeObject(forKey: oldKey)
                }
            }
        }
        // Migrate Privacy.lockScreen (only useful for TestFlight users, but still)
        do {
            let oldKey = "privacy.lockScreen"
            let newKey = "settings.privacy.lockScreen"
            if newUserDefaults.object(forKey: newKey) == nil {
                if let value = oldUserDefaults.object(forKey: oldKey) as? Bool {
                    newUserDefaults.set(value, forKey: newKey)
                    oldUserDefaults.removeObject(forKey: oldKey)
                }
            }
        }
        // Migrate Privacy.lockScreenGracePeriod (only useful for TestFlight users, but still)
        // To prevent a migration issue with V0_11_1, we only remove the old key here.
        do {
            let oldKey = "privacy.lockScreenGracePeriod"
            oldUserDefaults.removeObject(forKey: oldKey)
        }
    }

    private func migrationToV0_11_1() {
        guard let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier) else { return }
        let lockScreenKey = "settings.privacy.lockScreen"
        if let lockScreen = userDefaults.boolOrNil(forKey: lockScreenKey) {
            if lockScreen {
                ObvMessengerSettings.Privacy.localAuthenticationPolicy = .deviceOwnerAuthentication
            } else {
                ObvMessengerSettings.Privacy.localAuthenticationPolicy = .none
            }
        }
        userDefaults.removeObject(forKey: lockScreenKey)
    }
    
}


// MARK: PostInitialization utils

extension AppMainManager {
    
    private func printInitialDebugLogs() {

        for containerURL in ObvUICoreDataConstants.ContainerURL.allCases {
            guard containerURL.printInitialDebugLogs else { continue }
            os_log("URL for %{public}@: %{public}@", log: Self.log, type: .info,
                   containerURL.title, containerURL.url.path)
        }

        os_log("developmentMode: %{public}@", log: Self.log, type: .info, ObvMessengerConstants.developmentMode.description)
        os_log("isTestFlight: %{public}@", log: Self.log, type: .info, ObvMessengerConstants.isTestFlight.description)
        os_log("appGroupIdentifier: %{public}@", log: Self.log, type: .info, ObvMessengerConstants.appGroupIdentifier)
        os_log("hostForInvitations: %{public}@", log: Self.log, type: .info, ObvMessengerConstants.Host.forInvitations)
        os_log("hostForConfigurations: %{public}@", log: Self.log, type: .info, ObvMessengerConstants.Host.forConfigurations)
        os_log("hostForOpenIdRedirect: %{public}@", log: Self.log, type: .info, ObvMessengerConstants.Host.forOpenIdRedirect)
        os_log("serverURL: %{public}@", log: Self.log, type: .info, ObvMessengerConstants.serverURL.path)
        os_log("shortVersion: %{public}@", log: Self.log, type: .info, ObvMessengerConstants.shortVersion)
        os_log("bundleVersion: %{public}@", log: Self.log, type: .info, ObvMessengerConstants.bundleVersion)
        os_log("fullVersion: %{public}@", log: Self.log, type: .info, ObvMessengerConstants.fullVersion)
        
        os_log("Running on real device: %{public}@", log: Self.log, type: .info, ObvMessengerConstants.isRunningOnRealDevice.description)
     
        logMDMPreferences()
    }
    
    
    private func logMDMPreferences() {
        
        os_log("[MDM] preferences list starts", log: Self.log, type: .info)
        defer {
            os_log("[MDM] preferences list ends", log: Self.log, type: .info)
        }
        
        guard let mdmConfiguration = ObvMessengerSettings.MDM.configuration else { return }
        
        for (key, value) in mdmConfiguration {
            if let valueString = value as? String {
                os_log("[MDM] %{public}@ : %{public}@", log: Self.log, type: .info, key, valueString)
            } else if let valueInt = value as? String {
                os_log("[MDM] %{public}@ : %{public}d", log: Self.log, type: .info, key, valueInt)
            } else {
                os_log("[MDM] %{public}@ : Cannot read value", log: Self.log, type: .info, key)
            }
        }
        
    }
    
}

// MARK: Delegate providers

extension AppMainManager {

    var localAuthenticationDelegate: LocalAuthenticationDelegate? {
        get async {
            await appManagersHolder?.localAuthenticationDelegate
        }
    }

    var createPasscodeDelegate: CreatePasscodeDelegate? {
        get async {
            await appManagersHolder?.createPasscodeDelegate
        }
    }

    var appBackupDelegate: AppBackupDelegate? {
        get async {
            await appManagersHolder?.appBackupDelegate
        }
    }

    var storeKitDelegate: StoreKitDelegate? {
        get async {
            await appManagersHolder?.storeKitDelegate
        }
    }

}


final class BackgroundTaskManagerBasedOnUIApplication: ObvBackgroundTaskManager {
    
    func beginBackgroundTask(expirationHandler handler: (() -> Void)?) -> UIBackgroundTaskIdentifier {
        // This method can be safely called on a non-main thread
        return UIApplication.shared.beginBackgroundTask(expirationHandler: handler)
    }

    
    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier, completionHandler: (() -> Void)?) {
        // This method can be safely called on a non-main thread
        UIApplication.shared.endBackgroundTask(identifier)
        completionHandler?()
    }

}


// MARK: - NewAppStateManager and NewAppState

enum NewAppState: CustomDebugStringConvertible {
    
    case initializationRequired
    case initializing
    case initializationFailed(error: Error, runningLog: RunningLogError)
    case initializedButWasNeverOnScreen(obvEngine: ObvEngine)
    case initializedAndMetaFlowControllerViewDidAppear(obvEngine: ObvEngine)
    
    var debugDescription: String {
        switch self {
        case .initializationRequired: return "Initialization required"
        case .initializing: return "Initializing"
        case .initializationFailed: return "Initialization failed"
        case .initializedButWasNeverOnScreen: return "Initialized but was never on screen"
        case .initializedAndMetaFlowControllerViewDidAppear: return "Initialized and MetaFlowController's view did appear at least once"
        }
    }
    
    fileprivate var level: Int {
        switch self {
        case .initializationRequired: return 0
        case .initializing: return 1
        case .initializationFailed: return 2
        case .initializedButWasNeverOnScreen: return 3
        case .initializedAndMetaFlowControllerViewDidAppear: return 4
        }
    }
    
    var isInitialized: Bool {
        switch self {
        case .initializationRequired, .initializing:
            return false
        case .initializationFailed:
            return false
        case .initializedButWasNeverOnScreen, .initializedAndMetaFlowControllerViewDidAppear:
            return true
        }
    }
    
}


/// This singleton makes it possible to make the current app state available everywhere within the app.
/// Note that the actual current state is managed by the `AppMainManger`
final actor NewAppStateManager {
    
    static let shared = NewAppStateManager()
    
    private init() {}

    private weak var appMainManager: AppMainManager?
    
    private(set) weak var olvidURLHandler: OlvidURLHandler?
    private var olvidURLsOnHold = [OlvidURL]()

    fileprivate func setAppMainManager(_ appMainManager: AppMainManager) {
        self.appMainManager = appMainManager
        for block in blocksWaitingForAppMainManagerToBeSet { block() }
        blocksWaitingForAppMainManagerToBeSet.removeAll()
    }
    
    var currentState: NewAppState {
        get async {
            await waitUntilAppMainManagerIsSet()
            guard let appMainManager = appMainManager else { assertionFailure(); return .initializing }
            return await appMainManager.currentAppState
        }
    }
    
    // When accessing the currentState, the App main manager must be available.
    // The followind methods allow to wait until this is the case.
    
    private var blocksWaitingForAppMainManagerToBeSet = [() -> Void]()
    
    private func waitUntilAppMainManagerIsSet() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            performWhenAppMainManagerIsSet {
                continuation.resume()
            }
        }
    }
    
    private func performWhenAppMainManagerIsSet(_ block: @escaping () -> Void) {
        if self.appMainManager != nil {
            block()
        } else {
            blocksWaitingForAppMainManagerToBeSet.append(block)
        }
    }
    
    // Allowing other places in the app to wait until the app is initialized, on screen, initialization failed, etc.
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "NewAppStateManager")

    private var blocksToPerformWhenInitializationFailed = [(error: Error, runningLog: RunningLogError) -> Void]()
    private var blocksToPerformWhenInitialized = [(dispatchOnMainThread: Bool, block: (ObvEngine) -> Void)]()
    private var blocksToPerformWhenInitializationSucceededOrFailed = [(dispatchOnMainThread: Bool, block: (Result<ObvEngine, Error>) -> Void)]()
    private var blocksToPerformWhenInitializedAndMetaFlowControllerViewDidAppear = [(dispatchOnMainThread: Bool, block: (ObvEngine) -> Void)]()

    
    fileprivate func performBlocksAsStateChanged() async {
        guard let appMainManager = appMainManager else { assertionFailure(); return }

        switch await appMainManager.currentAppState {
        case .initializationRequired:
            break

        case .initializing:
            break

        case .initializationFailed(let error, let runningLog):
            for block in blocksToPerformWhenInitializationFailed { block(error, runningLog) }
            blocksToPerformWhenInitializationFailed.removeAll()

        case .initializedButWasNeverOnScreen(let obvEngine):
            for (dispatchOnMainThread, block) in blocksToPerformWhenInitialized {
                if dispatchOnMainThread {
                    DispatchQueue.main.async { block(obvEngine) }
                } else {
                    block(obvEngine)
                }
            }
            blocksToPerformWhenInitialized.removeAll()
            for (dispatchOnMainThread, block) in blocksToPerformWhenInitializationSucceededOrFailed {
                if dispatchOnMainThread {
                    DispatchQueue.main.async { block(.success(obvEngine)) }
                } else {
                    block(.success(obvEngine))
                }
            }
            blocksToPerformWhenInitializationSucceededOrFailed.removeAll()

        case .initializedAndMetaFlowControllerViewDidAppear(let obvEngine):
            for (dispatchOnMainThread, block) in blocksToPerformWhenInitialized {
                if dispatchOnMainThread {
                    DispatchQueue.main.async { block(obvEngine) }
                } else {
                    block(obvEngine)
                }
            }
            blocksToPerformWhenInitialized.removeAll()
            for (dispatchOnMainThread, block) in blocksToPerformWhenInitializationSucceededOrFailed {
                if dispatchOnMainThread {
                    DispatchQueue.main.async { block(.success(obvEngine)) }
                } else {
                    block(.success(obvEngine))
                }
            }
            blocksToPerformWhenInitializationSucceededOrFailed.removeAll()
            for (dispatchOnMainThread, block) in blocksToPerformWhenInitializedAndMetaFlowControllerViewDidAppear {
                if dispatchOnMainThread {
                    DispatchQueue.main.async { block(obvEngine) }
                } else {
                    block(obvEngine)
                }
            }
            blocksToPerformWhenInitializedAndMetaFlowControllerViewDidAppear.removeAll()
        }
    }
    
    
    /// Allows to asynchronously wait until the app is initialized
    func waitUntilAppIsInitialized() async -> ObvEngine {
        return await withCheckedContinuation { (continuation: CheckedContinuation<ObvEngine, Never>) in
            Task { [weak self] in
                await self?.performWhenAppIsInitialized(dispatchOnMainThread: false) { obvEngine in
                    continuation.resume(returning: obvEngine)
                }
            }
        }
    }
    
    
    private func performWhenAppIsInitialized(dispatchOnMainThread: Bool, _ block: @escaping (ObvEngine) -> Void) {
        Task {
            switch await currentState {
            case .initializationRequired, .initializing, .initializationFailed:
                blocksToPerformWhenInitialized.append((dispatchOnMainThread, block))
            case .initializedButWasNeverOnScreen(let obvEngine), .initializedAndMetaFlowControllerViewDidAppear(let obvEngine):
                if dispatchOnMainThread {
                    DispatchQueue.main.async {
                        block(obvEngine)
                    }
                } else {
                    block(obvEngine)
                }
            }
        }
    }
    
    
    func waitUntilAppInitializationSucceededOrFailed() async -> Result<ObvEngine, Error> {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Result<ObvEngine, Error>, Never>) in
            Task { [weak self] in
                await self?.performWhenAppInitializationSucceededOrFailed(dispatchOnMainThread: false) { result in
                    continuation.resume(returning: result)
                }
            }
        }
    }

    
    private func performWhenAppInitializationSucceededOrFailed(dispatchOnMainThread: Bool, _ block: @escaping (Result<ObvEngine, Error>) -> Void) {
        Task {
            switch await currentState {
            case .initializationRequired, .initializing:
                blocksToPerformWhenInitializationSucceededOrFailed.append((dispatchOnMainThread, block))
            case .initializationFailed(error: let error, runningLog: _):
                if dispatchOnMainThread {
                    DispatchQueue.main.async {
                        block(.failure(error))
                    }
                } else {
                    block(.failure(error))
                }
            case .initializedButWasNeverOnScreen(let obvEngine), .initializedAndMetaFlowControllerViewDidAppear(let obvEngine):
                if dispatchOnMainThread {
                    DispatchQueue.main.async {
                        block(.success(obvEngine))
                    }
                } else {
                    block(.success(obvEngine))
                }
            }
        }
    }
    
    
    func waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce() async -> ObvEngine {
        return await withCheckedContinuation { (continuation: CheckedContinuation<ObvEngine, Never>) in
            Task { [weak self] in
                await self?.performWhenAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce(dispatchOnMainThread: false) { obvEngine in
                    continuation.resume(returning: obvEngine)
                }
            }
        }
    }

    
    private func performWhenAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce(dispatchOnMainThread: Bool, _ block: @escaping (ObvEngine) -> Void) {
        Task {
            switch await currentState {
            case .initializationRequired, .initializing, .initializationFailed, .initializedButWasNeverOnScreen:
                blocksToPerformWhenInitializedAndMetaFlowControllerViewDidAppear.append((dispatchOnMainThread, block))
            case .initializedAndMetaFlowControllerViewDidAppear(let obvEngine):
                if dispatchOnMainThread {
                    DispatchQueue.main.async {
                        block(obvEngine)
                    }
                } else {
                    block(obvEngine)
                }
            }
        }
    }
    
    
    // MARK: Handling Olvid URLs
    
    
    func setOlvidURLHandler(to olvidURLHandler: OlvidURLHandler) async {
        assert(self.olvidURLHandler == nil)
        self.olvidURLHandler = olvidURLHandler
        while let olvidURLOnHold = olvidURLsOnHold.popLast() {
            _ = await olvidURLHandler.handleOlvidURL(olvidURLOnHold)
        }
    }
    
    
    /// Can be called from anywhere within the app. This methods forwards the `OlvidURL` to the appropriate handler,
    /// at the appropriate time (i.e., when a handler is available).
    func handleOlvidURL(_ olvidURL: OlvidURL) async {
        if let olvidURLHandler = self.olvidURLHandler {
            await olvidURLHandler.handleOlvidURL(olvidURL)
        } else {
            olvidURLsOnHold.append(olvidURL)
        }
    }

}



// MARK: - OlvidURLHandler protocol

protocol OlvidURLHandler: AnyObject {
    func handleOlvidURL(_ olvidURL: OlvidURL) async
}
