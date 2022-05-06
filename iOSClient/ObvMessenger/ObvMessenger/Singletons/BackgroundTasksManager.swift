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
import BackgroundTasks
import os.log
import CoreData


final class BackgroundTasksManager {
    
    static let shared = BackgroundTasksManager()

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: BackgroundTasksManager.self))

    static let identifier = "io.olvid.background.tasks"

    // Also used in info.plist in "Permitted background task scheduler identifiers"
    private enum ObvBackgroundTask: String, CaseIterable, CustomStringConvertible {
                
        case cleanExpiredMessages = "io.olvid.clean.expired.messages"
        case applyRetentionPolicies = "io.olvid.apply.retention.policies"
        case updateBadge = "io.olvid.update.badge"
        case listMessagesOnServer = "io.list.messages.on.server"

        var identifier: String { rawValue }
        
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

        func executes() async -> Bool {
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
    
    private init() {
        let log = self.log
        os_log("🤿 Registering background task", log: log, type: .info)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: BackgroundTasksManager.identifier, using: nil) { backgroundTask in
            ObvDisplayableLogs.shared.log("Background Task executes")

            Task {
                _ = await withTaskGroup(of: Bool.self, body: { taskGroup in
                    for task in ObvBackgroundTask.allCases {
                        taskGroup.addTask(priority: nil) {
                            let success = await task.executes()
                            os_log("🤿 Background Task '%{public}@' did complete. Success is: %{public}@", log: log, type: .info, task.description, success.description)
                            ObvDisplayableLogs.shared.log("Background Task '\(task.description)' did complete. Success is: \(success.description)")
                            return success
                        }
                    }
                    let atLeastOneTaskSuccessed = await taskGroup.contains(true)
                    os_log("🤿 All Background Tasks did complete. Success is: %{public}@", log: log, type: .info, atLeastOneTaskSuccessed.description)
                    ObvDisplayableLogs.shared.log("All Background Tasks did complete. Success is: \(atLeastOneTaskSuccessed.description)")
                    backgroundTask.setTaskCompleted(success: atLeastOneTaskSuccessed)
                })

                self.scheduleBackgroundTasks()
            }
        }
    }

    private func earliestBeginDate(for task: ObvBackgroundTask, context: NSManagedObjectContext) -> Date? {
        switch task {
        case .cleanExpiredMessages:
            do {
                guard let expiration = try PersistedMessageExpiration.getEarliestExpiration(laterThan: Date(), within: context) else {
                    os_log("🤿 We do not schedule any background task for message expiration since there is no expiration left", log: log, type: .info)
                    return nil
                }
                return expiration.expirationDate
            } catch {
                os_log("🤿 We could not get earliest message expiration: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return nil
            }
        case .applyRetentionPolicies:
            return Date(timeIntervalSinceNow: TimeInterval(hours: 1))
        case .updateBadge:
            do {
                guard let expiration = try PersistedDiscussionLocalConfiguration.getEarliestMuteExpirationDate(laterThan: Date(), within: context) else {
                    os_log("🤿 We do not schedule any background task for mute expiration since there is no expiration left", log: log, type: .info)
                    return nil
                }
                return expiration
            } catch {
                os_log("🤿 We could not get earliest mute expiration: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return nil
            }
        case .listMessagesOnServer:
            return Date(timeIntervalSinceNow: TimeInterval(minutes: 15))
        }

    }

    func scheduleBackgroundTasks() {
        // We do not schedule BG tasks when running in the simulator as they are not supported
        guard ObvMessengerConstants.isRunningOnRealDevice else { return }
        // We make sure the app was initialized. Otherwise, the shared stack is not garanteed to exist. Accessing it would crash the app.
        guard AppStateManager.shared.currentState.isInitialized else { return }
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            var earliestBeginDate = Date.distantFuture
            for task in ObvBackgroundTask.allCases {
                if let date = self.earliestBeginDate(for: task, context: context) {
                    earliestBeginDate = min(date, earliestBeginDate)
                }
            }
            let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
            request.earliestBeginDate = earliestBeginDate
            ObvDisplayableLogs.shared.log("Submitting background task with earliest begin date \(String(describing: earliestBeginDate.description))")
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch let error {
                os_log("🤿 Could not schedule background task: %{public}@", log: log, type: .fault, error.localizedDescription)
            }
            os_log("🤿 Background tasks was scheduled", log: log, type: .info)
        }

    }

    
    private func commonCompletion(obvTask: ObvBackgroundTask, backgroundTask: BGTask, success: Bool) {
        os_log("🤿 Background Task '%{public}' did complete. Success is: %{public}@", log: log, type: .info, obvTask.description, success.description)
        ObvDisplayableLogs.shared.log("Background Task '\(obvTask.description)' did complete. Success is: \(success.description)")
        backgroundTask.setTaskCompleted(success: success)
    }
    
    
    func cancelAllPendingBGTask() {
        BGTaskScheduler.shared.cancelAllTaskRequests()
    }
    
}
 
