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

import UIKit
import BackgroundTasks
import OSLog
import CoreData
import ObvEngine
import ObvUICoreData
import OlvidUtils
import ObvAppCoreConstants


/// See https://developer.apple.com/documentation/backgroundtasks/starting-and-terminating-tasks-during-development for testing background tasks.
final class BackgroundTasksManager {
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: BackgroundTasksManager.self))

    /// Also used in info.plist in "Permitted background task scheduler identifiers".
    /// This is the identifier of the only app refresh background task (only one is allowed per app).
    static let appRefreshTaskIdentifier = "io.olvid.background.tasks"
    
    private let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier)

    /// Also used in info.plist in "Permitted background task scheduler identifiers".
    /// These represent the (up to 10) processing background tasks.
    /// The raw values are the identifiers of the processing background tasks.
    enum ObvProcessingTask: String, CaseIterable {
        case appDatabaseSync = "io.olvid.background.processing.database.sync"
        case performNewBackup = "io.olvid.background.processing.perform.new.backup"
        case appInboxSyncMessageIdsKeptForLater = "io.olvid.background.processing.app.inbox.sync.message.ids.kept.for.later"
    }

    weak var delegate: BackgroundTasksManagerDelegate?
    
    private var observationTokens = [NSObjectProtocol]()

    private enum ObvSubBackgroundTask: CaseIterable, CustomStringConvertible {
                
        case cleanExpiredMessages
        case applyRetentionPolicies
        case updateBadge
        case listMessagesOnServer

        var description: String {
            switch self {
            case .cleanExpiredMessages:
                return "Clean Expired Message"
            case .applyRetentionPolicies:
                return "Apply retention policies"
            case .updateBadge:
                return "Update badge"
            case .listMessagesOnServer:
                return "List messages on server"
            }
        }

        func execute() async -> Bool {
            await withCheckedContinuation { cont in
                switch self {
                case .cleanExpiredMessages:
                    ObvMessengerInternalNotification.cleanExpiredMessagesBackgroundTaskWasLaunched { (success) in
                        cont.resume(returning: success)
                    }.postOnDispatchQueue()
                case .applyRetentionPolicies:
                    ObvMessengerInternalNotification.applyRetentionPoliciesBackgroundTaskWasLaunched { (success) in
                        cont.resume(returning: success)
                    }.postOnDispatchQueue()
                case .updateBadge:
                    ObvMessengerInternalNotification.updateBadgeBackgroundTaskWasLaunched { (success) in
                        cont.resume(returning: success)
                    }.postOnDispatchQueue()
                case .listMessagesOnServer:
                    ObvMessengerInternalNotification.listMessagesOnServerBackgroundTaskWasLaunched { (success) in
                        cont.resume(returning: success)
                    }.postOnDispatchQueue()
                }
            }
        }
    }
    
    struct TaskResult {
        let taskDescription: String
        let isSuccess: Bool
    }
    
    init() {
        Self.logger.info("🤿 Registering background task")
        
        // Register the refresh background task
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundTasksManager.appRefreshTaskIdentifier, using: nil) { backgroundTask in
            //ObvDisplayableLogs.shared.log("Background Task executes")

            Task { [weak self] in
                
                let taskResults: [TaskResult] = try await withThrowingTaskGroup(of: TaskResult.self) { taskGroup in
                    
                    var taskResults = [TaskResult]()
                    
                    for task in ObvSubBackgroundTask.allCases {
                        //ObvDisplayableLogs.shared.log("Adding background Task '\(task.description)'")
                        taskGroup.addTask(priority: nil) {
                            //ObvDisplayableLogs.shared.log("Executing background Task '\(task.description)'")
                            let isSuccess = await task.execute()
                            //ObvDisplayableLogs.shared.log("Background Task '\(task.description)' did complete. Success is: \(isSuccess.description)")
                            return TaskResult(taskDescription: task.description, isSuccess: isSuccess)
                        }
                    }
                    
                    for try await taskResult in taskGroup {
                        taskResults.append(taskResult)
                    }
                    
                    return taskResults
                }
                
                Self.logger.info("🤿 All Background Tasks did complete")
                //ObvDisplayableLogs.shared.log("All Background Tasks did complete")
                for taskResult in taskResults {
                    Self.logger.info("🤿 Background Task '\(taskResult.taskDescription, privacy: .public)' did complete. Success is: \(taskResult.isSuccess.description, privacy: .public)")
                    //ObvDisplayableLogs.shared.log("Background Task '\(taskResult.taskDescription)' did complete. Success is: \(taskResult.isSuccess.description)")
                }
                backgroundTask.setTaskCompleted(success: true)

                await self?.scheduleBackgroundTasks()
            }
        }
        
        // Register all the processing background tasks
        
        for processingTask in ObvProcessingTask.allCases {
            let isSuccess = BGTaskScheduler.shared.register(forProcessingTask: processingTask, using: nil) { [weak self] task in
                guard let self, let bgProcessingTask = task as? BGProcessingTask else { assertionFailure(); task.setTaskCompleted(success: false); return }
                Task { [weak self] in
                    guard let self else { assertionFailure(); task.setTaskCompleted(success: false); return }
                    switch processingTask {
                    case .appInboxSyncMessageIdsKeptForLater:
                        await self.handleAppInboxSyncMessageIdsKeptForLater(bgProcessingTask: bgProcessingTask)
                    case .appDatabaseSync:
                        await self.handleAppDatabaseSync(bgProcessingTask: bgProcessingTask)
                    case .performNewBackup:
                        await self.handlePerformNewBackup(bgProcessingTask: bgProcessingTask)
                    }
                }
            }
            guard isSuccess else { assertionFailure(); continue }
        }
        
        // Observe notifications in order to handle certain background tasks

        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeListMessagesOnServerBackgroundTaskWasLaunched(queue: OperationQueue.main) { success in
                Task { [weak self] in
                    let obvEngine = await NewAppStateManager.shared.waitUntilAppIsInitialized()
                    await self?.processListMessagesOnServerBackgroundTaskWasLaunched(obvEngine: obvEngine, success: success)
                }
            },
        ])

    }

    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }


    private func earliestBeginDate(for task: ObvSubBackgroundTask, context: NSManagedObjectContext) -> Date? {
        switch task {
        case .cleanExpiredMessages:
            do {
                guard let expiration = try PersistedMessageExpiration.getEarliestExpiration(laterThan: Date(), within: context) else {
                    return nil
                }
                return expiration.expirationDate
            } catch {
                Self.logger.fault("🤿 We could not get earliest message expiration: \(error.localizedDescription, privacy: .public)")
                assertionFailure()
                return nil
            }
        case .applyRetentionPolicies:
            return Date(timeIntervalSinceNow: TimeInterval(hours: 1))
        case .updateBadge:
            do {
                guard let expiration = try PersistedDiscussionLocalConfiguration.getEarliestMuteExpirationDate(laterThan: Date(), within: context) else {
                    return nil
                }
                return expiration
            } catch {
                Self.logger.fault("🤿 We could not get earliest mute expiration: \(error.localizedDescription, privacy: .public)")
                assertionFailure()
                return nil
            }
        case .listMessagesOnServer:
            return Date(timeIntervalSinceNow: TimeInterval(hours: 2))
        }

    }

    func scheduleBackgroundTasks() async {
        
        // We do not schedule BG tasks when running in the simulator as they are not supported
        
        guard ObvMessengerConstants.isRunningOnRealDevice else { return }
        
        // Schedule processing background tasks
        
        for processingTask in ObvProcessingTask.allCases {
            await scheduleProcessingTask(processingTask)
        }

        // We make sure the app was initialized. Otherwise, the shared stack is not garanteed to exist. Accessing it would crash the app.
        
        _ = await NewAppStateManager.shared.waitUntilAppIsInitialized()
        
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            var earliestBeginDate = Date.distantFuture
            for task in ObvSubBackgroundTask.allCases {
                if let date = self.earliestBeginDate(for: task, context: context) {
                    earliestBeginDate = min(date, earliestBeginDate)
                }
            }
            assert(earliestBeginDate > Date())
            let request = BGAppRefreshTaskRequest(identifier: Self.appRefreshTaskIdentifier)
            request.earliestBeginDate = earliestBeginDate
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch let error {
                //ObvDisplayableLogs.shared.log("Could not schedule background task: \(error.localizedDescription)")
                Self.logger.fault("🤿 Could not schedule background task: \(error.localizedDescription, privacy: .public)")
            }
            //ObvDisplayableLogs.shared.log("Background task was submitted with earliest begin date \(String(describing: earliestBeginDate.description))")
            Self.logger.info("🤿 Background task was submitted with earliest begin date \(String(describing: earliestBeginDate.description), privacy: .public)")
        }

    }
    
    
    private func scheduleProcessingTask(_ processingTask: ObvProcessingTask) async {
        switch processingTask {
            
        case .appInboxSyncMessageIdsKeptForLater:
            
            // If there already is a pending task request, we don't schedule one
            
            let pendingTaskRequests = await BGTaskScheduler.shared.pendingTaskRequests().filter({ $0.identifier == processingTask.rawValue })

            if let pendingRequest = pendingTaskRequests.first {
                
                Self.logger.info("🤿 We don't schedule a \(processingTask.rawValue) processing task as there already a pending task with earliestBeginDate \(pendingRequest.earliestBeginDate?.description ?? "none")")
                
            } else {
             
                guard let userDefaults else { assertionFailure(); return }
                let dateOfLastAppInboxSyncMessageIdsKeptForLater = userDefaults.dateOrNil(forKey: ObvMessengerConstants.UserDefaultsKeys.dateOfLastAppInboxSyncMessageIdsKeptForLater.rawValue) ?? .distantPast
                let dateOfNextAppDatabaseSync = max(Date.now, dateOfLastAppInboxSyncMessageIdsKeptForLater.addingTimeInterval(.init(hours: 6)))
                let request = BGProcessingTaskRequest(identifier: processingTask.rawValue)
                request.earliestBeginDate = dateOfNextAppDatabaseSync
                request.requiresNetworkConnectivity = false
                do {
                    try BGTaskScheduler.shared.submit(request)
                    debugPrint("Task submitted (\(processingTask.rawValue)")
                } catch {
                    Self.logger.fault("🤿 Could not schedule processing task \(processingTask.rawValue)")
                    assertionFailure()
                }
                
            }
            
        case .appDatabaseSync:

            // If there already is a pending task request, we don't schedule one
            
            let pendingTaskRequests = await BGTaskScheduler.shared.pendingTaskRequests().filter({ $0.identifier == processingTask.rawValue })
            
            if let pendingRequest = pendingTaskRequests.first {
                
                Self.logger.info("🤿 We don't schedule a \(processingTask.rawValue) processing task as there already a pending task with earliestBeginDate \(pendingRequest.earliestBeginDate?.description ?? "none")")
                
            } else {
                
                guard let userDefaults else { assertionFailure(); return }
                let dateOfLastAppDatabaseSync = userDefaults.dateOrNil(forKey: ObvMessengerConstants.UserDefaultsKeys.dateOfLastDatabaseSync.rawValue) ?? .distantPast
                let dateOfNextAppDatabaseSync = max(Date.now, dateOfLastAppDatabaseSync.addingTimeInterval(.init(hours: 6)))
                let request = BGProcessingTaskRequest(identifier: processingTask.rawValue)
                request.earliestBeginDate = dateOfNextAppDatabaseSync
                request.requiresNetworkConnectivity = false
                do {
                    try BGTaskScheduler.shared.submit(request)
                    debugPrint("Task submitted (\(processingTask.rawValue)")
                } catch {
                    Self.logger.fault("🤿 Could not schedule processing task \(processingTask.rawValue)")
                    assertionFailure()
                }
                
            }
            
        case .performNewBackup:
            
            guard let delegate else { assertionFailure(); return }
            do {
                guard try await delegate.newBackupsAreConfiguredAndCanBePerformed() else { return }

                // If there already is a pending backup task request, we don't schedule one

                let pendingTaskRequests = await BGTaskScheduler.shared.pendingTaskRequests().filter({ $0.identifier == processingTask.rawValue })

                if let pendingRequest = pendingTaskRequests.first {

                    Self.logger.info("🤿 We don't schedule a \(processingTask.rawValue) processing task as there already a pending task with earliestBeginDate \(pendingRequest.earliestBeginDate?.description ?? "none")")

                } else {

                    let dateOfNextBackup = Date.now.addingTimeInterval(.init(hours: 24))
                    let request = BGProcessingTaskRequest(identifier: processingTask.rawValue)
                    request.earliestBeginDate = dateOfNextBackup
                    request.requiresNetworkConnectivity = true
                    try BGTaskScheduler.shared.submit(request)
                    debugPrint("Task submitted (\(processingTask.rawValue)")

                }
            } catch {
                Self.logger.fault("🤿 Could not schedule processing task \(processingTask.rawValue)")
                assertionFailure()
            }
            
        }
    }

    
    private func commonCompletion(obvTask: ObvSubBackgroundTask, backgroundTask: BGTask, success: Bool) {
        Self.logger.info("🤿 Background Task '\(obvTask.description, privacy: .public)' did complete. Success is: \(success.description, privacy: .public)")
        //ObvDisplayableLogs.shared.log("Background Task '\(obvTask.description)' did complete. Success is: \(success.description)")
        backgroundTask.setTaskCompleted(success: success)
    }
        
}
 

// MARK: - Implementing certain background tasks

extension BackgroundTasksManager {
    
    /// This method processes the notification sent after launching a background task for listing messages on the server.
    private func processListMessagesOnServerBackgroundTaskWasLaunched(obvEngine: ObvEngine, success: @escaping (Bool) -> Void) async {
        
        let tag = UUID()
        Self.logger.info("🤿 We are performing a background fetch. We tag it as \(tag.uuidString, privacy: .public)")
        
        let isSuccess: Bool
        do {
            try await obvEngine.downloadAllMessagesForOwnedIdentities()
            isSuccess = true
        } catch {
            assertionFailure()
            isSuccess = false
        }
        
        // Wait for some time for giving the app a change to process listed messages
        
        do {
            try await Task.sleep(seconds: 2)
        } catch {
            assertionFailure()
        }
        
        Self.logger.info("🤿 Calling the completion handler of the background fetch tagged as \(tag.uuidString, privacy: .public). The result is \(isSuccess.description, privacy: .public)")

        return success(isSuccess)
        
    }

}


// MARK: - Handling the

extension BackgroundTasksManager {
    
    private func handleAppInboxSyncMessageIdsKeptForLater(bgProcessingTask: BGProcessingTask) async {
        
        // Handle the task
        
        guard let delegate = self.delegate else {
            ObvDisplayableLogs.shared.log("🤿 The delegate is not set. Cannot handle the task.")
            return bgProcessingTask.setTaskCompleted(success: false)
        }
        
        do {
            ObvDisplayableLogs.shared.log("🤿 Calling the syncMessageIdsKeptForLater delegate method.")
            try await delegate.syncMessageIdsKeptForLater(self)
        } catch {
            ObvDisplayableLogs.shared.log("🤿 The call to the syncMessageIdsKeptForLater delegate method failed.")
            return bgProcessingTask.setTaskCompleted(success: false)
        }
        
        ObvDisplayableLogs.shared.log("🤿 The call to the syncMessageIdsKeptForLater delegate method was successful.")

        // Re-schedule a task of the same type
        
        await scheduleProcessingTask(.appInboxSyncMessageIdsKeptForLater)

        // Complete the task
        
        return bgProcessingTask.setTaskCompleted(success: true)

    }

    
}


// MARK: - Handling the appDatabaseSync ProcessingTask

extension BackgroundTasksManager {
    
    /// This is the handler of the `ProcessingTask.appDatabaseSync` background processing task.
    private func handleAppDatabaseSync(bgProcessingTask: BGProcessingTask) async {

        // Handle the task
        
        guard let delegate = self.delegate else {
            ObvDisplayableLogs.shared.log("🤿 The delegate is not set. Cannot handle the task.")
            return bgProcessingTask.setTaskCompleted(success: false)
        }
        
        do {
            ObvDisplayableLogs.shared.log("🤿 Calling the syncAppDatabasesWithEngine delegate method.")
            try await delegate.syncAppDatabasesWithEngine(backgroundTasksManager: self)
        } catch {
            ObvDisplayableLogs.shared.log("🤿 The call to the syncAppDatabasesWithEngine delegate method failed.")
            return bgProcessingTask.setTaskCompleted(success: false)
        }
        
        ObvDisplayableLogs.shared.log("🤿 The call to the syncAppDatabasesWithEngine delegate method was successful.")
        
        // Re-schedule a task of the same type
        
        await scheduleProcessingTask(.appDatabaseSync)

        // Complete the task
        
        return bgProcessingTask.setTaskCompleted(success: true)
        
    }
    
}


// MARK: -

extension BackgroundTasksManager {
    
    /// This is the handler of the `ProcessingTask.performNewBackup` background processing task.
    private func handlePerformNewBackup(bgProcessingTask: BGProcessingTask) async {
        
        // Handle the task

        guard let delegate = self.delegate else {
            ObvDisplayableLogs.shared.log("🤿 The delegate is not set. Cannot handle the task.")
            return bgProcessingTask.setTaskCompleted(success: false)
        }

        do {
            ObvDisplayableLogs.shared.log("🤿 Calling the createAndUploadDeviceAndProfilesBackupDuringBackgroundProcessing delegate method.")
            guard try await delegate.newBackupsAreConfiguredAndCanBePerformed() else {
                ObvDisplayableLogs.shared.log("🤿 Since new backups are not yet configured, we cannot perform a backup. Returning now.")
                return
            }
            try await delegate.createAndUploadDeviceAndProfilesBackupDuringBackgroundProcessing()
            ObvDisplayableLogs.shared.log("🤿 The call to the createAndUploadDeviceAndProfilesBackupDuringBackgroundProcessing delegate did succeed.")
        } catch {
            ObvDisplayableLogs.shared.log("🤿 The call to the createAndUploadDeviceAndProfilesBackupDuringBackgroundProcessing delegate method failed.")
            return bgProcessingTask.setTaskCompleted(success: false)
        }

        // Re-schedule a task of the same type
        
        await scheduleProcessingTask(.performNewBackup)

        // Complete the task
        
        return bgProcessingTask.setTaskCompleted(success: true)

    }
    
}

// MARK: - Private helpers

private extension BGTaskScheduler {
    
    func register(forProcessingTask processingTask: BackgroundTasksManager.ObvProcessingTask, using queue: dispatch_queue_t?, launchHandler: @escaping (BGTask) -> Void) -> Bool {
        self.register(forTaskWithIdentifier: processingTask.rawValue, using: queue, launchHandler: launchHandler)
    }
    
}
