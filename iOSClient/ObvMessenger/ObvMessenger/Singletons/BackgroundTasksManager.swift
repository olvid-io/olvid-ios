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


@available(iOS 13.0, *)
final class BackgroundTasksManager {
    
    static let shared = BackgroundTasksManager()

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: BackgroundTasksManager.self))

    // Also used in info.plist in "Permitted background task scheduler identifiers"
    enum ObvBackgroundTask: String, CaseIterable, CustomStringConvertible {
                
        case cleanExpiredMessages = "io.olvid.clean.expired.messages"
        case applyRetentionPolicies = "io.olvid.apply.retention.policies"
        case updateBadge = "io.olvid.update.badge"

        var identifier: String { rawValue }
        
        var description: String {
            switch self {
            case .cleanExpiredMessages:
                return "Clean Expired Message"
            case .applyRetentionPolicies:
                return "Apply retention policies"
            case .updateBadge:
                return "Update badge"
            }
        }

    }

    
    private init() {
        let log = self.log
        // Register all background tasks
        os_log("🤿 Registering all background tasks", log: log, type: .info)
        for obvTask in ObvBackgroundTask.allCases {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: obvTask.identifier, using: nil) { (backgroundTask) in
                ObvDisplayableLogs.shared.log("Background Task '\(obvTask.description)' executes")
                switch obvTask {
                case .cleanExpiredMessages:
                    ObvMessengerInternalNotification.cleanExpiredMessagesBackgroundTaskWasLaunched { [weak self] (success) in
                        self?.commonCompletion(obvTask: obvTask, backgroundTask: backgroundTask, success: success)
                    }.postOnDispatchQueue()
                case .applyRetentionPolicies:
                    ObvMessengerInternalNotification.applyRetentionPoliciesBackgroundTaskWasLaunched { [weak self] (success) in
                        self?.commonCompletion(obvTask: obvTask, backgroundTask: backgroundTask, success: success)
                    }.postOnDispatchQueue()
                case .updateBadge:
                    ObvMessengerInternalNotification.updateBadgeBackgroundTaskWasLaunched { [weak self] (success) in
                        self?.commonCompletion(obvTask: obvTask, backgroundTask: backgroundTask, success: success)
                    }.postOnDispatchQueue()
                }
            }
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

    
    func submit(task: ObvBackgroundTask, earliestBeginDate: Date?) throws {
        ObvDisplayableLogs.shared.log("Submitting background task '\(task.description)' with earliest begin date \(String(describing: earliestBeginDate?.description))")
        // We do not schedule BG tasks when running in the simulator as they are not supported
        guard ObvMessengerConstants.isRunningOnRealDevice else { return }
        let request = BGAppRefreshTaskRequest(identifier: task.identifier)
        request.earliestBeginDate = earliestBeginDate
        try BGTaskScheduler.shared.submit(request)
    }
    
}
 
