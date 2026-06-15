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

import Foundation
import OSLog
import ObvAppCoreConstants
import BackgroundTasks
import UIKit


public struct ObvContinuedProcessingTaskManager {
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ObvContinuedProcessingTaskManager")
    
    /// Also used in info.plist in "Permitted background task scheduler identifiers".
    /// These represent the continued processing background tasks.
    /// The raw values are the identifiers of the processing background tasks.
    /// They must start with the bundleID, so we have to distinguish between the development and production
    /// environment
    public enum ObvContinuedProcessingTaskKind {
        case historyTransfer
        var identifier: String {
            switch ObvAppCoreConstants.appType {
            case .development:
                return "io.olvid.messenger-debug.bgContinuedProcessingTask.historyTransfer"
            case .production:
                return "io.olvid.messenger.bgContinuedProcessingTask.historyTransfer"
            }
        }
        var title: String {
            switch self {
            case .historyTransfer:
                return String(localizedInThisBundle: "HISTORY_TRANSFER_TITLE")
            }
        }
        var subtitle: String {
            switch self {
            case .historyTransfer:
                return String(localizedInThisBundle: "HISTORY_TRANSFER_SUBTITLE")
            }
        }
    }
    
}


// MARK: - Public methods

extension ObvContinuedProcessingTaskManager {
    
    public static func run(taskKind: ObvContinuedProcessingTaskKind,
                           launchHandler: @escaping (ObvBGContinuedProcessingTask?) async throws -> Void
    ) {
        
        guard supportsContinuedProcessingTask else {
            return executeAsStandardTask(launchHandler: launchHandler)
        }
        
        #if targetEnvironment(macCatalyst)
        return executeAsStandardTask(launchHandler: launchHandler)
        #else
        if #available(iOS 26.0, *) {
            return executeAsContinuedProcessingTask(taskKind: taskKind, launchHandler: launchHandler)
        } else {
            return executeAsStandardTask(launchHandler: launchHandler)
        }
        #endif

    }

}


// MARK: - Private methods

extension ObvContinuedProcessingTaskManager {
    
    private static var supportsContinuedProcessingTask: Bool {
        guard ObvAppCoreConstants.isRunningOnRealDevice else { return false }
        #if targetEnvironment(macCatalyst)
        return false
        #else
        if #available(iOS 26.0, *) {
            return true
        } else {
            return false
        }
        #endif
    }

    
    private static func generateIdentifier(for taskKind: ObvContinuedProcessingTaskKind) -> String {
        return [taskKind.identifier, UUID().uuidString].joined(separator: ".")
    }
        

    #if !targetEnvironment(macCatalyst)
    @available(iOS 26.0, *)
    private static func executeAsContinuedProcessingTask(taskKind: ObvContinuedProcessingTaskKind, launchHandler: @escaping (ObvBGContinuedProcessingTask?) async throws -> Void) {
        do {
            let taskIdentifier = Self.generateIdentifier(for: taskKind)
            let request = BGContinuedProcessingTaskRequest(
                identifier: taskIdentifier,
                title: taskKind.title,
                subtitle: taskKind.subtitle)
            let isRegistrationSuccessful = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: .main) { task in
                let task = task as! BGContinuedProcessingTask
                Task {
                    do {
                        try await launchHandler(task)
                        task.setTaskCompleted(success: true)
                    } catch {
                        task.setTaskCompleted(success: false)
                    }
                }
            }
            guard isRegistrationSuccessful else {
                assertionFailure()
                executeAsStandardTask(launchHandler: launchHandler)
                return
            }
            try BGTaskScheduler.shared.submit(request)
        } catch {
            assertionFailure()
            executeAsStandardTask(launchHandler: launchHandler)
        }
    }
    #endif // !targetEnvironment(macCatalyst)
    
    private static func executeAsStandardTask(launchHandler: @escaping (ObvBGContinuedProcessingTask?) async throws -> Void) {
        Task {
            do {
                startWithIdleTimerDisabled()
                defer { stopWithIdleTimerDisabled() }
                _ = try await launchHandler(nil)
            } catch {
                Self.logger.error("Launch handler threw an error: \(error)")
            }
        }
    }

    
    private static func startWithIdleTimerDisabled() {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    private static func stopWithIdleTimerDisabled() {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

}

// MARK: - Errors

extension ObvContinuedProcessingTaskManager {
    
    enum ObvError: Error {
        case deviceDoesNotSupportContinuedProcessingTask
        case taskRegistrationFailed
    }
    
}


