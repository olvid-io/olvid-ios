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
        case drainEngineInbox = "io.olvid.background.processing.drain.inbox"
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
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundTasksManager.appRefreshTaskIdentifier, using: nil) { [weak self] backgroundTask in
            //ObvDisplayableLogs.shared.log("Background Task executes")

            Task {
                
                guard let taskResults: [TaskResult] = try? await withThrowingTaskGroup(of: TaskResult.self, body: { taskGroup in
                    
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
                }) else {
                    Self.logger.fault("🤿 The background tasks could not be run. The background task is not marked as completed, exactly as it was not before.")
                    return
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
                    case .drainEngineInbox:
                        await self.handleDrainEngineInbox(bgProcessingTask: bgProcessingTask)
                    }
                }
            }
            // Said out loud rather than only asserted on. Apple documents `register` as answering false when the identifier is missing from the Info.plist —
            // where ours are generated by Tuist, so a new task whose identifier was not added there fails to register, and does so **silently** in a build
            // with assertions compiled out. One line means the question can be answered from a log instead of by reading a plist inside a bundle.
            if isSuccess {
                // `notice`, not `info`: an `info` line lives in a memory ring buffer and is never written to the log store, so it is absent from `log show`
                // and from a plain `log stream`. This line exists to be read during a walk on a device, which makes it a probe, and a probe that cannot be
                // seen is worse than none — it invites the reading that it never ran.
                Self.logger.notice("🤿 Registered the processing task \(processingTask.rawValue, privacy: .public)")
            } else {
                Self.logger.fault("🤿 Could NOT register the processing task \(processingTask.rawValue, privacy: .public). Is its identifier in BGTaskSchedulerPermittedIdentifiers?")
                assertionFailure()
                continue
            }
        }
        
        // Observe notifications in order to handle certain background tasks

        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeListMessagesOnServerBackgroundTaskWasLaunched(queue: OperationQueue.main) { [weak self] success in
                Task {
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
            
        case .drainEngineInbox:

            // If there already is a pending task request, we don't schedule one.
            //
            // **The known gap, left deliberately.** A backlog arriving while a six-hour request is pending waits for it: this path declines to replace a
            // queued request, so the first pass over a hundred thousand new messages can be up to six hours away. Two reasons to leave it. Replacing on
            // every backgrounding — which is what this path does, several times a day — resets whatever standing the request has accrued with the
            // scheduler, and is a plausible way to be launched never. And the delay is mostly notional for *this* task: it requires external power, so the
            // moment it can run at all is the device idle on a charger, which is typically once a night. The case that genuinely matters is consecutive
            // passes within one such night, and that one is answered by the run itself asking for another window in a minute when it was cut off with work
            // outstanding — see `earliestBeginDateForTheNextDrainWindow(after:)`.

            let pendingTaskRequests = await BGTaskScheduler.shared.pendingTaskRequests().filter({ $0.identifier == processingTask.rawValue })

            if let pendingRequest = pendingTaskRequests.first {

                Self.logger.info("🤿 We don't schedule a \(processingTask.rawValue) processing task as there already a pending task with earliestBeginDate \(pendingRequest.earliestBeginDate?.description ?? "none")")

            } else {

                // Asked for on the strength of the last run's report, so that a device whose last window was cut off with work outstanding is asked for
                // another one soon rather than in six hours — including when the request was lost, which is what brings us here.
                submitDrainEngineInboxRequest(after: ObvInboxDrainReport.lastStored(in: userDefaults), reason: "scheduling the background tasks")

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
                // Completed rather than simply returned. Apple: "Not calling setTaskCompleted(success:) before the time for the task expires may result in
                // the system killing your app" — and being killed also makes the next launch slower. This path used to return without completing.
                return bgProcessingTask.setTaskCompleted(success: false)
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

// MARK: - Handling the drainEngineInbox ProcessingTask

extension BackgroundTasksManager {

    /// A backstop against a window that is never expired, and nothing else.
    ///
    /// **It has one job now.** It used to have two, the second being to give the loop a deadline to bound each of its uncancellable engine calls against —
    /// that was `awaiting(_:upTo:before:)`, which took `min(budget, deadline - now)`, and it went when the sweep did. The only remaining reader is
    /// `ObvInboxDrainRoundDecision`, which ends a run once the clock has passed.
    ///
    /// **Raised from ten minutes to thirty on 2026-09-12, because ten was cutting off the case this feature exists for.** A window is not a clock: a
    /// processing task runs *for as long as the device stays idle*, and the system terminates one outright the moment the user picks the device up — so this
    /// number only ever binds on a device left alone and charging, which is precisely the overnight backlog the drain was built for. At ten it was the
    /// binding constraint there and irrelevant everywhere else. Measured against it: 100'000 stalled rows take about twelve minutes to drain, and 10'000
    /// messages fetched from the server took 872 seconds.
    ///
    /// **Finite rather than `.distantFuture`, and that matters more than it looks.** `requiresExternalPower` is set on this request, and setting it is also
    /// how an app turns CPU Monitor off for the duration of the task — so the platform's usual catch for a runaway background process is disabled by our own
    /// request, and this is the only guard left. Half an hour is above everything we have measured and bounded enough that a run nothing ever expires costs
    /// half an hour of CPU on an idle charging device.
    ///
    /// **Nothing here is a documented budget**, because Apple publishes none: the header says only that a processing task "can run for minutes". If a
    /// *Last run* report ever comes back ending on `theDeadlinePassed` at thirty minutes with work still outstanding, that is the evidence for raising it
    /// again.
    private static var drainWindow: TimeInterval { TimeInterval(minutes: 30) }

    /// How long we are prepared to wait for the app to finish initialising before giving the window up.
    ///
    /// A background launch has to build both Core Data stacks and the engine before the delegate exists. Bounded because a wait with no bound is how a
    /// screen elsewhere in this app spent three seconds blank on a new OS, and because a window spent waiting is a window not spent draining.
    private static var budgetForWaitingUntilTheAppIsInitialized: TimeInterval { 60 }


    /// This is the handler of the `ObvProcessingTask.drainEngineInbox` background processing task.
    ///
    /// **There is no drain logic here, and that is deliberate.** Everything below is plumbing that cannot be exercised where the drain itself can: background
    /// tasks are never scheduled on a simulator, and the tool that builds a backlog to drain can only reach a simulator's container. So the work lives behind
    /// one delegate call that takes a deadline and a stop flag, which the debug row in the advanced settings drives identically, and what is left here is
    /// short enough to be read.
    private func handleDrainEngineInbox(bgProcessingTask: BGProcessingTask) async {

        let run = ObvInboxDrainInProgress(report: .init(trigger: .backgroundProcessingTask, startedAt: .now, stopReason: .theDeadlinePassed))
        let completion = OneShotBackgroundTaskCompletion(bgProcessingTask: bgProcessingTask)

        // Submitted before the work rather than after it. The expiration handler runs on a budget the documentation says is shared between every handler and
        // does not grow with their number, and `pendingTaskRequests()` is async — so nothing that must happen at expiry may be. Submitting now means that
        // whenever this window ends, and however abruptly, the next one is already asked for. A submit for an identifier that is already queued replaces the
        // previous request, so the refinement at the end of the run costs nothing.
        submitDrainEngineInboxRequest(after: nil, reason: "the task was launched")

        bgProcessingTask.expirationHandler = { [weak self] in
            // **Nothing here can cancel anything.** No part of the engine's fetch path checks for cancellation: a listing or a processing round in flight
            // will run to its end whatever we do, and there is no API — internal or otherwise — that would stop one. Do not go looking for one. All this can
            // do is stop the loop asking for more, write down where it got to, and complete the task. Whatever is still in flight lands or does not; every
            // row involved is persistent, so the next window carries on from wherever this one stopped and nothing is processed twice.
            run.requestStop(becauseTheWindowExpired: true)
            // A floor rather than the final word: this is the last published snapshot, so it is a round or so behind whatever the loop is about to return
            // with — but completing the task invites the system to suspend us at once, and then the loop never comes back and this is all there is. If the
            // loop does come back, its fuller account replaces this.
            // Read once and used for both things below — the record, when this handler is the one writing it, and the flag — so that what is stored and
            // what is completed cannot disagree about the same run.
            var report = run.latestReport
            report.stopReason = .weWereAskedToStop
            report.endedOnTheExpirationHandler = true
            // The only report ever stored while the pass is on a step is this one, so this is the one place its step's duration must stop counting.
            report.noteThatTheRunWasCutOffDuringTheStaleSettingsPass()

            if run.theExpirationHandlerShouldWriteTheRecord {
                report.store(in: self?.userDefaults)
                // "Provisionally" is the whole of what this line has to say that the loop's own does not: seeing it after a `Drain finished:` line does not
                // mean it won, only that it fired in the gap before the loop claimed the record — and the loop's account then replaced this one.
                ObvDisplayableLogs.shared.log("🤿 The drain's window expired. Recorded provisionally; the drain's own report supersedes this if it returns. \(report.descriptionForLogs)")
                Self.logger.notice("🤿 The drain's window expired. Recorded provisionally; the drain's own report supersedes this if it returns. \(report.descriptionForLogs, privacy: .public)")
            }
            // **The same test the loop's own ending uses: did this window move the backlog forward** — see ``ObvInboxDrainReport/theWindowWasWorthHaving``.
            //
            // This line has now said three things. It said `true` unconditionally until 2026-09-12, on no stated reasoning. It then said `false`
            // unconditionally, reasoning that the window had been taken away with work outstanding and that Apple's own sample completes with
            // `!operation.isCancelled`. Both were answers to the wrong question. **A device with a large backlog cannot empty its inbox inside one window**,
            // so *was the work finished* reports failure on every run this feature exists for — including one that moved eight thousand messages before the
            // reader picked the device up, which is precisely the window we want more of. What the flag should carry is whether the time was used.
            //
            // **Being cut off is not itself the failure, and this is the case that shows it.** A processing task is terminated the moment the reader picks
            // the device up, so most windows end here — and a run that fetched and stored for twenty minutes before that happened did everything that was
            // asked of it. What still reports `false` from here is a window that was taken away having achieved nothing: cut off in its first seconds, or
            // before its counts ever came back.
            //
            // One caveat, and it is the reason for the floor above rather than for a different test: this reads the last published snapshot, so it is a round
            // or so behind. It can therefore miss progress made in the final round — which errs towards `false`, the safe direction, and is corrected by the
            // loop's own ending whenever the loop comes back first.
            completion.completeOnce(success: report.theWindowWasWorthHaving)
        }

        // A cold background launch can reach this before the delegate exists: the tasks are registered in `init`, during
        // `didFinishLaunchingWithOptions`, and the delegate is connected later by `AppMainManager.connectCoordinatorsAndManagers()`.

        // **Both of these endings write the run down, and both then re-ask for the next window before completing.** They used to do neither, so a window that
        // never got started left the diagnostics panel showing the *previous* run's figures as though they were this one's — and `scheduleBackgroundTasks`,
        // which reads that same record when no request is pending, went on deciding the next window from them too. The two are given different endings
        // rather than one, because `ObvInboxDrainWindowSchedule` separates them: an app that was too busy to finish launching may well not be busy in a
        // minute, where a missing delegate is a fault in how the app is put together and is worth standing down over.
        //
        // The order matters in both. The record is claimed before it is written, so a handler firing from here on leaves it alone; the next request is
        // submitted before the task is completed, `setTaskCompleted` being an invitation to the system to suspend us at once.

        guard await waitUntilTheAppIsInitialized(within: Self.budgetForWaitingUntilTheAppIsInitialized) else {
            ObvDisplayableLogs.shared.log("🤿 The app did not finish initializing in time. Giving the drain's window up.")
            let report = ObvInboxDrainReport.couldNotBeRun(trigger: .backgroundProcessingTask, stopReason: .theAppDidNotFinishInitializingInTime)
            run.noteThatTheLoopIsWritingTheRecord()
            report.store(in: userDefaults)
            submitDrainEngineInboxRequest(after: report, reason: "the app did not finish initializing in time")
            completion.completeOnce(success: false)
            return
        }

        guard let delegate = self.delegate else {
            ObvDisplayableLogs.shared.log("🤿 The delegate is not set. Cannot drain the engine's inbox.")
            let report = ObvInboxDrainReport.couldNotBeRun(trigger: .backgroundProcessingTask)
            run.noteThatTheLoopIsWritingTheRecord()
            report.store(in: userDefaults)
            submitDrainEngineInboxRequest(after: report, reason: "the drain could not be started")
            completion.completeOnce(success: false)
            return
        }

        let report = await delegate.drainEngineInbox(self, deadline: .now.addingTimeInterval(Self.drainWindow), run: run)

        // This account supersedes anything the expiration handler wrote: same run, same conclusion about why it stopped — `report` carries `expired` from the
        // run itself — and every figure measured a round later. Claimed before writing, so a handler firing from here on leaves it alone.

        run.noteThatTheLoopIsWritingTheRecord()
        report.store(in: userDefaults)

        // Replaces the request submitted before the work — a submit for a queued identifier replaces it — now that we know whether anything is still owed.
        submitDrainEngineInboxRequest(after: report, reason: "the drain finished")

        // Asked of the report rather than asserted. **Progress, not completion**: a device with a large backlog cannot empty its inbox in one window, so the
        // question is whether this one moved things forward — see ``ObvInboxDrainReport/theWindowWasWorthHaving``. What still reports `false` from here is a
        // run that achieved nothing at all.
        completion.completeOnce(success: report.theWindowWasWorthHaving)

    }


    /// When to ask for the next window, given what the last run achieved.
    ///
    /// The rule itself is ``ObvInboxDrainWindowSchedule``, which is where its reasoning is written down and the only
    /// part of this feature a unit test can reach — a minute when a run was cut off with work outstanding, the
    /// ordinary six hours when it found nothing. What is left here is reading the four facts it needs off the report
    /// and handing it the clock.
    private func earliestBeginDateForTheNextDrainWindow(after report: ObvInboxDrainReport?) -> Date {

        let whatTheLastRunLeft = report.map {
            ObvInboxDrainWindowSchedule.WhatTheLastRunLeft(stopReason: $0.stopReason,
                                                          whatWasLearnedAboutTheInbox: $0.whatWasLearnedAboutTheInbox,
                                                          theStaleSettingsPassLeftRowsHeld: $0.theStaleSettingsPassStoppedEarly == true,
                                                          startedAt: $0.startedAt)
        }

        return ObvInboxDrainWindowSchedule.earliestBeginDate(after: whatTheLastRunLeft, now: .now)

    }


    /// Asks for the next drain window.
    ///
    /// `requiresExternalPower` is what makes a run of minutes permissible at all: besides biasing the system towards launching us on a charger, Apple
    /// documents it as what disables CPU Monitor — the feature that terminates apps using too many CPU cycles in the background — for the task's duration.
    /// Nothing else in this app sets it.
    ///
    /// Not async, so that it can be called from anywhere that cannot await, and synchronous by nature: `submit` is documented as a blocking call.
    private func submitDrainEngineInboxRequest(after report: ObvInboxDrainReport?, reason: String) {

        let earliestBeginDate = earliestBeginDateForTheNextDrainWindow(after: report)

        let request = BGProcessingTaskRequest(identifier: ObvProcessingTask.drainEngineInbox.rawValue)
        request.earliestBeginDate = earliestBeginDate
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = true

        do {
            try BGTaskScheduler.shared.submit(request)
            // `notice` for the same reason as the registration line above: this is the one line that answers *is there a request for the debugger to launch
            // into*, and `_simulateLaunchForTaskWithIdentifier:` answers "no task request with identifier … has been scheduled" when there is not.
            Self.logger.notice("🤿 Submitted a \(ObvProcessingTask.drainEngineInbox.rawValue) request with earliestBeginDate \(earliestBeginDate.description) (\(reason))")
            ObvDisplayableLogs.shared.log("🤿 Submitted a \(ObvProcessingTask.drainEngineInbox.rawValue) request with earliestBeginDate \(earliestBeginDate.description) (\(reason))")
        } catch {
            // Named rather than logged as one indistinguishable fault, as the four older submit sites do: `tooManyPendingTaskRequests` means we are at
            // Apple's limit of ten processing tasks and something has to give, where `notPermitted` and `unavailable` mean the device or the user has
            // declined and there is nothing to fix. A log that cannot tell them apart cannot answer why a task never ran.
            let name = (error as? BGTaskScheduler.Error).map { String(describing: $0.code) } ?? error.localizedDescription
            Self.logger.fault("🤿 Could not submit the \(ObvProcessingTask.drainEngineInbox.rawValue) request: \(name, privacy: .public)")
            ObvDisplayableLogs.shared.log("🤿 Could not submit the \(ObvProcessingTask.drainEngineInbox.rawValue) request: \(name)")
            assertionFailure()
        }

    }


    /// Waits until the app is initialized, or answers `false` if that takes longer than `budget`.
    ///
    /// Both outcomes are said out loud by the caller. A wait that returns in silence cannot be told apart from one that never happened, which is exactly how
    /// an unbounded wait elsewhere in this app went undiagnosed.
    private func waitUntilTheAppIsInitialized(within budget: TimeInterval) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let hasResumed = OSAllocatedUnfairLock<Bool>(initialState: false)
            @Sendable func resumeOnce(with value: Bool) {
                let isOurs = hasResumed.withLock { hasAlreadyResumed in
                    guard !hasAlreadyResumed else { return false }
                    hasAlreadyResumed = true
                    return true
                }
                guard isOurs else { return }
                continuation.resume(returning: value)
            }
            Task {
                _ = await NewAppStateManager.shared.waitUntilAppIsInitialized()
                resumeOnce(with: true)
            }
            Task {
                try? await Task.sleep(seconds: budget)
                resumeOnce(with: false)
            }
        }
    }

}


// MARK: - Completing a background task exactly once

/// Calls `setTaskCompleted(success:)` once and only once, whichever of the two endings arrives first.
///
/// A background processing task has two endings that genuinely race: the work finishing, and the system taking the window away. Apple documents both halves
/// of getting this wrong — not completing before the time expires "may result in the system killing your app", and a task without an expiration handler is
/// silently marked complete and unsuccessful. This makes both mistakes impossible to write, which the older handlers in this file do not: one returns without
/// completing at all.
///
/// `@unchecked` because `BGProcessingTask` is not `Sendable`. The task is written exactly twice — at initialisation, and by whichever caller wins
/// `hasCompletedLock` — and read only by that winner, so there is one writer and no concurrent reader.
///
/// **The task is let go of there because holding it is a cycle**: `BGTask` holds its `expirationHandler`, that handler captures this object, and this object
/// holds the task. Nothing clears the handler afterwards, so the task, this object, the run it captured and its report all leaked — one set per window, on a
/// task meant to run every night.
private final class OneShotBackgroundTaskCompletion: @unchecked Sendable {

    /// Nil once the task has been completed, which is what breaks the cycle described above. Touched only by the winner of `hasCompletedLock`.
    private var bgProcessingTask: BGProcessingTask?
    private let hasCompletedLock = OSAllocatedUnfairLock<Bool>(initialState: false)

    init(bgProcessingTask: BGProcessingTask) {
        self.bgProcessingTask = bgProcessingTask
    }

    /// Completes the task, if nobody has yet. Answers whether this call is the one that did, which callers may ignore.
    ///
    /// **This gates the completion only, deliberately — not the recording of what the run achieved.** Those are different questions with different answers:
    /// the task must be completed exactly once and immediately, whereas the record should be the best account available, which is always the work's own and
    /// never the expiration handler's snapshot of it. See `ObvInboxDrainInProgress.theExpirationHandlerShouldWriteTheRecord`, and note that an earlier
    /// version of this method took the recording inside the gate and so let the poorer of the two accounts win a race.
    @discardableResult
    func completeOnce(success: Bool) -> Bool {
        let isOurs = hasCompletedLock.withLock { hasAlreadyCompleted in
            guard !hasAlreadyCompleted else { return false }
            hasAlreadyCompleted = true
            return true
        }
        guard isOurs else { return false }
        // Taken out of the property rather than read from it, so that the reference this object holds is gone whatever happens next — and taken by the one
        // caller the gate above let through, which is what makes an unsynchronised write to it sound.
        let task = bgProcessingTask
        bgProcessingTask = nil
        task?.setTaskCompleted(success: success)
        // The handler holds this object; this object held the task; the task holds the handler. One of the three has to go, and this is the only place that
        // knows the task is finished with. Cleared after completing rather than before, so the system cannot find itself with a window to expire and nothing
        // to call.
        task?.expirationHandler = nil
        return true
    }

}


// MARK: - Private helpers

private extension BGTaskScheduler {
    
    func register(forProcessingTask processingTask: BackgroundTasksManager.ObvProcessingTask, using queue: dispatch_queue_t?, launchHandler: @escaping (BGTask) -> Void) -> Bool {
        self.register(forTaskWithIdentifier: processingTask.rawValue, using: queue, launchHandler: launchHandler)
    }
    
}
