/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import UIKit
import os.log

final class RetentionMessagesCoordinator {
    
    fileprivate static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: RetentionMessagesCoordinator.self))

    init() {
        if #available(iOS 13, *) {
            observeApplyRetentionPoliciesBackgroundTaskWasLaunchedNotifications()
        }
    }
    
    private var observationTokens = [NSObjectProtocol]()

    @available(iOS 13, *)
    private func observeApplyRetentionPoliciesBackgroundTaskWasLaunchedNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeApplyRetentionPoliciesBackgroundTaskWasLaunched { (completion) in
            let completionHandler: (Bool) -> Void = { (success) in
                DispatchQueue.main.async {
                    (UIApplication.shared.delegate as? AppDelegate)?.scheduleBackgroundTaskForApplyingRetentionPolicies()
                    completion(success)
                }
            }
            ObvMessengerInternalNotification.applyAllRetentionPoliciesNow(launchedByBackgroundTask: true, completionHandler: completionHandler)
                .postOnDispatchQueue()
        })
    }
    
}


// MARK: - Extending AppDelegate for managing the background task allowing to wipe expired messages

@available(iOS 13.0, *)
extension AppDelegate {

    /// If there exists at least one message expiration in database, this method schedules a background task allowing to perform a wipe of the associated message in the background.
    /// This method is called when the app goes in the background.
    func scheduleBackgroundTaskForApplyingRetentionPolicies() {
        ObvStack.shared.performBackgroundTaskAndWait { (context) in
            // If we reach this point, we should schedule a background task for message expiration
            do {
                try BackgroundTasksManager.shared.submit(task: .applyRetentionPolicies, earliestBeginDate: Date(timeIntervalSinceNow: TimeInterval(3_600)))
            } catch {
                guard ObvMessengerConstants.isRunningOnRealDevice else { assertionFailure("We should not be scheduling BG tasks on a simulator as they are unsuported"); return }
                os_log("🤿 Could not schedule next BG task for applying retention policies: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
        }
    }

    
}
