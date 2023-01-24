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
import ObvEngine
import os.log
import CloudKit


final actor AppManagersHolder {
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "AppManagersHolder")
    
    private let obvEngine: ObvEngine
    
    private let userNotificationsManager: UserNotificationsManager
    private let userNotificationsBadgesManager: UserNotificationsBadgesManager
    private let hardLinksToFylesManager: HardLinksToFylesManager
    private let thumbnailManager: ThumbnailManager
    private let appBackupManager: AppBackupManager
    private let expirationMessagesManager: ExpirationMessagesManager
    private let retentionMessagesManager: RetentionMessagesManager
    private let callManager: CallManager
    private let profilePictureManager: ProfilePictureManager
    private let subscriptionManager: SubscriptionManager
    private let muteDiscussionManager: MuteDiscussionManager
    private let snackBarManager: SnackBarManager
    private let applicationShortcutItemsManager: ApplicationShortcutItemsManager
    private let keycloakManager: KeycloakManager
    private let backgroundTasksManager: BackgroundTasksManager
    private let webSocketManager: WebSocketManager
    private let localAuthenticationManager: LocalAuthenticationManager

    private var observationTokens = [NSObjectProtocol]()

    var localAuthenticationDelegate: LocalAuthenticationDelegate {
        localAuthenticationManager
    }
    var createPasscodeDelegate: CreatePasscodeDelegate {
        localAuthenticationManager
    }
    var appBackupDelegate: AppBackupDelegate {
        appBackupManager
    }

    init(obvEngine: ObvEngine, backgroundTasksManager: BackgroundTasksManager, userNotificationsManager: UserNotificationsManager) {

        self.obvEngine = obvEngine
        self.backgroundTasksManager = backgroundTasksManager
        self.userNotificationsManager = userNotificationsManager

        self.userNotificationsBadgesManager = UserNotificationsBadgesManager()
        self.hardLinksToFylesManager = HardLinksToFylesManager(appType: .mainApp)
        self.thumbnailManager = ThumbnailManager(appType: .mainApp)
        self.appBackupManager = AppBackupManager(obvEngine: obvEngine)
        self.expirationMessagesManager = ExpirationMessagesManager()
        self.retentionMessagesManager = RetentionMessagesManager()
        self.callManager = CallManager(obvEngine: obvEngine)
        self.profilePictureManager = ProfilePictureManager()
        self.subscriptionManager = SubscriptionManager(obvEngine: obvEngine)
        self.muteDiscussionManager = MuteDiscussionManager()
        self.snackBarManager = SnackBarManager(obvEngine: obvEngine)
        self.applicationShortcutItemsManager = ApplicationShortcutItemsManager()
        self.keycloakManager = KeycloakManager(obvEngine: obvEngine)
        self.webSocketManager = WebSocketManager(obvEngine: obvEngine)
        self.localAuthenticationManager = LocalAuthenticationManager()

        // Listen to StoreKit transactions
        self.subscriptionManager.listenToSKPaymentTransactions()
        
    }
    
    
    func performPostInitialization() async {
        // Observe app lifecycle events
        await observeAppBasedLifeCycleEvents()
        // Subscribe to notifications
        await callManager.performPostInitialization()
        // Initialize the Keycloak manager singleton
        await keycloakManager.performPostInitialization()
        await webSocketManager.performPostInitialization()
        await localAuthenticationManager.performPostInitialization()
        await snackBarManager.performPostInitialization()
    }
    
    
    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        await appBackupManager.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await applicationShortcutItemsManager.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await expirationMessagesManager.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await userNotificationsBadgesManager.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await snackBarManager.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await callManager.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await webSocketManager.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
    }


    @MainActor
    private func observeAppBasedLifeCycleEvents() async {
        os_log("🧦 observeAppBasedLifeCycleEvents", log: Self.log, type: .info)
        let didEnterBackgroundNotification = UIApplication.didEnterBackgroundNotification
        let tokens = [
            NotificationCenter.default.addObserver(forName: didEnterBackgroundNotification, object: nil, queue: .main) { _ in
                 os_log("🧦 didEnterBackgroundNotification", log: Self.log, type: .info)
                 Task { [weak self] in
                     os_log("🧦 Call to cancelThenScheduleBackgroundTasksWhenAppDidEnterBackground starts", log: Self.log, type: .info)
                     await self?.cancelThenScheduleBackgroundTasksWhenAppDidEnterBackground()
                     os_log("🧦 Call to cancelThenScheduleBackgroundTasksWhenAppDidEnterBackground ends", log: Self.log, type: .info)
                 }
            },
        ]
        await storeObservationTokens(observationTokens: tokens)
    }
    
    
    private func storeObservationTokens(observationTokens: [NSObjectProtocol]) {
        self.observationTokens += observationTokens
    }
    
    
    private func cancelThenScheduleBackgroundTasksWhenAppDidEnterBackground() async {
        backgroundTasksManager.cancelAllPendingBGTask()
        await backgroundTasksManager.scheduleBackgroundTasks()
    }

}


// MARK: - AppBackupDelegate

protocol AppBackupDelegate: AnyObject {
    func deleteCloudBackup(record: CKRecord) async throws
    func getLatestCloudBackup(desiredKeys: [AppBackupManager.Key]?) async throws -> CKRecord?
    func getBackupsAndDevicesCount(identifierForVendor: UUID?) async throws -> (backupCount: Int, deviceCount: Int)
    func checkAccount() async throws
    func getAccountStatus() async throws -> CKAccountStatus

    func exportBackup(sourceView: UIView, sourceViewController: UIViewController) async throws -> Bool
    func uploadBackupToICloud() async throws

    var cleaningProgress: ObvProgress? { get async }
}
