/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvUICoreData
import ObvAppCoreConstants
import ObvKeycloakManager
import ObvLocation


final actor AppManagersHolder {
    
    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "AppManagersHolder")
    
    let obvEngine: ObvEngine
    
    private let userNotificationsBadgesManager: UserNotificationsBadgesManager
    private let hardLinksToFylesManager: HardLinksToFylesManager
    private let thumbnailManager: ThumbnailManager
    private let appBackupManager: AppBackupManager
    private let expirationMessagesManager: ExpirationMessagesManager
    private let retentionMessagesManager: RetentionMessagesManager
    private let callProvider: CallProviderDelegate
    private let profilePictureManager: ProfilePictureManager
    private let subscriptionManager: SubscriptionManager
    private let muteDiscussionManager: MuteDiscussionManager
    private let snackBarManager: SnackBarManager
    private let applicationShortcutItemsManager: ApplicationShortcutItemsManager
    private let keycloakManager: KeycloakManager
    private let backgroundTasksManager: BackgroundTasksManager
    private let webSocketManager: WebSocketManager
    private let localAuthenticationManager: LocalAuthenticationManager
    private let intentManager = IntentManager()
    private let tipManager: OlvidTipManager
    let continuousSharingLocationManager: ContinuousSharingLocationManager
    
    private let appContinuousSharingLocationManagerDataSource: AppContinuousSharingLocationManagerDataSource

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
    
    var storeKitDelegate: StoreKitDelegate {
        subscriptionManager
    }
    
    init(obvEngine: ObvEngine, backgroundTasksManager: BackgroundTasksManager) async {

        self.obvEngine = obvEngine
        self.backgroundTasksManager = backgroundTasksManager

        self.appContinuousSharingLocationManagerDataSource = await AppContinuousSharingLocationManagerDataSource()
        
        self.userNotificationsBadgesManager = UserNotificationsBadgesManager()
        self.hardLinksToFylesManager = HardLinksToFylesManager.makeHardLinksToFylesManagerForMainApp()
        self.thumbnailManager = ThumbnailManager.makeThumbnailManagerForMainApp()
        self.appBackupManager = AppBackupManager(obvEngine: obvEngine)
        self.expirationMessagesManager = ExpirationMessagesManager()
        self.retentionMessagesManager = RetentionMessagesManager()
        self.callProvider = CallProviderDelegate(obvEngine: obvEngine)
        self.profilePictureManager = ProfilePictureManager()
        self.subscriptionManager = SubscriptionManager(obvEngine: obvEngine)
        self.muteDiscussionManager = MuteDiscussionManager()
        self.snackBarManager = SnackBarManager(obvEngine: obvEngine)
        self.applicationShortcutItemsManager = ApplicationShortcutItemsManager()
        self.keycloakManager = KeycloakManager()
        self.webSocketManager = WebSocketManager(obvEngine: obvEngine)
        self.localAuthenticationManager = LocalAuthenticationManager()
        self.tipManager = OlvidTipManager(obvEngine: obvEngine)
        self.continuousSharingLocationManager = ContinuousSharingLocationManager()

        // Listen to StoreKit transactions
        self.subscriptionManager.listenToSKPaymentTransactions()
        
    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    func performPostInitialization() async {
        // Observe app lifecycle events
        await observeAppBasedLifeCycleEvents()
        // Subscribe to notifications
        callProvider.performPostInitialization()
        // Initialize the Keycloak manager singleton
        await keycloakManager.performPostInitialization()
        await webSocketManager.performPostInitialization()
        await localAuthenticationManager.performPostInitialization()
        await snackBarManager.performPostInitialization()
        await intentManager.performPostInitialization()
        // Set the delegates
        await self.keycloakManager.setDelegate(to: self)
    }
    
    
    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        await appBackupManager.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await applicationShortcutItemsManager.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await expirationMessagesManager.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await userNotificationsBadgesManager.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await snackBarManager.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        //await callManager.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await webSocketManager.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        if #available(iOS 17.0, *) {
            await tipManager.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        }
    }

    
    /// Called by the `AppMainManager` to set the delegates of certain managers using coordinators.
    func setManagersDelegates(backgroundTasksManagerDelegate: any BackgroundTasksManagerDelegate,
                              expirationMessagesManager: any ExpirationMessagesManagerDelegate,
                              signalingDelegate: any CallProviderDelegateSignalingDelegate,
                              continuousSharingLocationManagerDelegate: any ContinuousSharingLocationManagerDelegate) async {
        self.backgroundTasksManager.delegate = backgroundTasksManagerDelegate
        self.expirationMessagesManager.delegate = expirationMessagesManager
        self.callProvider.signalingDelegate = signalingDelegate
        await continuousSharingLocationManager.setDelegateAndDatasource(delegate: continuousSharingLocationManagerDelegate, datasource: appContinuousSharingLocationManagerDataSource)
    }
    

    @MainActor
    private func observeAppBasedLifeCycleEvents() async {
        os_log("🧦 observeAppBasedLifeCycleEvents", log: Self.log, type: .info)
        let didEnterBackgroundNotification = UIApplication.didEnterBackgroundNotification
        let tokens = [
            NotificationCenter.default.addObserver(forName: didEnterBackgroundNotification, object: nil, queue: nil) { _ in
                 os_log("didEnterBackgroundNotification", log: Self.log, type: .info)
                 Task { [weak self] in
                     os_log("Call to cancelThenScheduleBackgroundTasksWhenAppDidEnterBackground starts", log: Self.log, type: .info)
                     await self?.scheduleBackgroundTasksWhenAppDidEnterBackground()
                     os_log("Call to cancelThenScheduleBackgroundTasksWhenAppDidEnterBackground ends", log: Self.log, type: .info)
                 }
            },
        ]
        await storeObservationTokens(observationTokens: tokens)
    }
    
    
    private func storeObservationTokens(observationTokens: [NSObjectProtocol]) {
        self.observationTokens += observationTokens
    }
    
    
    private func scheduleBackgroundTasksWhenAppDidEnterBackground() async {
        await backgroundTasksManager.scheduleBackgroundTasks()
    }

}


// MARK: - AppBackupDelegate

protocol AppBackupDelegate: AnyObject {
    func deleteCloudBackup(record: CKRecord) async throws
    func getLatestCloudBackup(desiredKeys: [ObvAppCoreConstants.BackupConstants.Key]?) async throws -> CKRecord?
    func getBackupsAndDevicesCount(identifierForVendor: UUID?) async throws -> (backupCount: Int, deviceCount: Int)
    func checkAccount() async throws
    func getAccountStatus() async throws -> CKAccountStatus

    func exportBackup(sourceView: UIView, sourceViewController: UIViewController) async throws -> Bool
    func uploadBackupToICloud() async throws

    var cleaningProgress: ObvProgress? { get async }
}
