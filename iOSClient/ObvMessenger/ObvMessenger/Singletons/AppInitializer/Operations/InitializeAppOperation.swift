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
import OlvidUtils
import ObvEngine

final class InitializeAppOperation: OperationWithSpecificReasonForCancel<InitializeAppOperationReasonForCancel> {

    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
    
    let runningLog: RunningLogError
    let completion: (Result<ObvEngine,InitializeAppOperationReasonForCancel>) -> Void
    private var obvEngine: ObvEngine?
    
    init(runningLog: RunningLogError, completion: @escaping (Result<ObvEngine,InitializeAppOperationReasonForCancel>) -> Void) {
        self.runningLog = runningLog
        self.completion = completion
        super.init()
    }
    
    override func main() {
        
        runningLog.addEvent(message: "Starting the initialization operations")
        
        defer {
            if let obvEngine = self.obvEngine {
                completion(.success(obvEngine))
            } else {
                completion(.failure(reasonForCancel ?? .unknownError))
            }
        }
        
        runningLog.addEvent(message: "Writing down preferences")

        ObvMessengerConstants.writeToPreferences()

        // Initialize the File System service
        runningLog.addEvent(message: "Initializing the filesystem service")
        let fileSystemService = FileSystemService()
        fileSystemService.createAllDirectoriesIfRequired() // Must be called before trying to load the persistent container

        // Initialize the CoreData Stack
        do {
            runningLog.addEvent(message: "Initializing the App Core Data stack")
            try ObvStack.initSharedInstance(transactionAuthor: ObvMessengerConstants.AppType.mainApp.transactionAuthor, runningLog: runningLog, enableMigrations: true)
        } catch let error {
            runningLog.addEvent(message: "The initialization of the App Core Data stack failed:\n---\n---\n \(error.localizedDescription)")
            return cancel(withReason: .failedToInitializeObvStack(error: error))
        }
        runningLog.addEvent(message: "The initialization of the App Core Data was successful")

        // Initialize the Singletons
        runningLog.addEvent(message: "Initializing the network status monitor")
        _ = NetworkStatus.shared

        // Perform app migrations and handle exceptional situations
        runningLog.addEvent(message: "Performing exception migrations")
        migrationFromBuild147ToBuild148()
        migrationToV0_9_0()
        migrationToV0_9_5()
        migrationToV0_9_11()
        migrationToV0_9_14()
        migrationToV0_9_17()

        // Initialize the Oblivious Engine
        do {
            runningLog.addEvent(message: "Initializing the Engine")
            obvEngine = try initializeObliviousEngine(runningLog: runningLog)
        } catch let error {
            runningLog.addEvent(message: "The Engine initialization failed: \(error.localizedDescription)")
            assertionFailure()
            return cancel(withReason: .failedToInitializeObvEngine(error: error))
        }
        runningLog.addEvent(message: "The initialization of the Engine was successful")

        // Print a few logs on startup
        printInitialDebugLogs()

    }
    
}


enum InitializeAppOperationReasonForCancel: LocalizedErrorWithLogType {
    
    
    case failedToInitializeObvStack(error: Error)
    case failedToInitializeObvEngine(error: Error)
    case unknownError

    var logType: OSLogType {
        switch self {
        case .failedToInitializeObvStack,
             .failedToInitializeObvEngine,
             .unknownError:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .failedToInitializeObvStack(error: let error):
            return "Failed to initialize Obv Stack: \(error.localizedDescription)"
        case .failedToInitializeObvEngine(error: let error):
            return "Failed to initialize Engine: \(error.localizedDescription)"
        case .unknownError:
            return "Unknown error"
        }
    }
    
}


// MARK: - Handle exception situations

extension InitializeAppOperation {

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
                }
            }
        }
        // Migrate Privacy.lockScreenGracePeriod (only useful for TestFlight users, but still)
        do {
            let oldKey = "privacy.lockScreenGracePeriod"
            let newKey = "settings.privacy.lockScreenGracePeriod"
            if newUserDefaults.object(forKey: newKey) == nil {
                if let value = oldUserDefaults.object(forKey: oldKey) as? Double {
                    newUserDefaults.set(value, forKey: newKey)
                }
            }
        }
    }

    
    func migrationToV0_9_0() {
        guard let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier) else { return }
        userDefaults.removeObject(forKey: "settings.discussions.doFetchContentRichURLsMetadata.withinDiscussion")
        userDefaults.removeObject(forKey: "settings.discussions.doSendReadReceipt.withinDiscussion")
    }

}


// MARK: Initialize the engine

extension InitializeAppOperation {
    
    private func initializeObliviousEngine(runningLog: RunningLogError) throws -> ObvEngine {
        do {
            let mainEngineContainer = ObvMessengerConstants.containerURL.mainEngineContainer
            ObvEngine.mainContainerURL = mainEngineContainer
            let obvEngine = try ObvEngine.startFull(logPrefix: "FullEngine",
                                                    appNotificationCenter: NotificationCenter.default,
                                                    uiApplication: UIApplication.shared,
                                                    sharedContainerIdentifier: ObvMessengerConstants.appGroupIdentifier,
                                                    supportBackgroundTasks: ObvMessengerConstants.isRunningOnRealDevice,
                                                    appType: .mainApp,
                                                    runningLog: runningLog)
            return obvEngine
        } catch let error {
            throw error
        }
    }

}


// MARK: - Other stuff

extension InitializeAppOperation {
    
    private func printInitialDebugLogs() {
        
        os_log("URL for Documents: %{public}@", log: log, type: .info, ObvMessengerConstants.containerURL.forDocuments.path)
        os_log("URL for Temp files: %{public}@", log: log, type: .info, ObvMessengerConstants.containerURL.forTempFiles.path)
        os_log("URL for hard links: %{public}@", log: log, type: .info, ObvMessengerConstants.containerURL.forFylesHardlinks(within: .mainApp).path)
        os_log("URL for thumbnails: %{public}@", log: log, type: .info, ObvMessengerConstants.containerURL.forThumbnails(within: .mainApp).path)
        os_log("URL for trash: %{public}@", log: log, type: .info, ObvMessengerConstants.containerURL.forTrash.path)
        
        os_log("developmentMode: %{public}@", log: log, type: .info, ObvMessengerConstants.developmentMode.description)
        os_log("isTestFlight: %{public}@", log: log, type: .info, ObvMessengerConstants.isTestFlight.description)
        os_log("appGroupIdentifier: %{public}@", log: log, type: .info, ObvMessengerConstants.appGroupIdentifier)
        os_log("hostForInvitations: %{public}@", log: log, type: .info, ObvMessengerConstants.Host.forInvitations)
        os_log("hostForConfigurations: %{public}@", log: log, type: .info, ObvMessengerConstants.Host.forConfigurations)
        os_log("hostForOpenIdRedirect: %{public}@", log: log, type: .info, ObvMessengerConstants.Host.forOpenIdRedirect)
        os_log("serverURL: %{public}@", log: log, type: .info, ObvMessengerConstants.serverURL.path)
        os_log("shortVersion: %{public}@", log: log, type: .info, ObvMessengerConstants.shortVersion)
        os_log("bundleVersion: %{public}@", log: log, type: .info, ObvMessengerConstants.bundleVersion)
        os_log("fullVersion: %{public}@", log: log, type: .info, ObvMessengerConstants.fullVersion)
        
        os_log("Running on real device: %{public}@", log: log, type: .info, ObvMessengerConstants.isRunningOnRealDevice.description)
     
        logMDMPreferences()
    }
    
    private func logMDMPreferences() {
        
        os_log("[MDM] preferences list starts", log: log, type: .info)
        defer {
            os_log("[MDM] preferences list ends", log: log, type: .info)
        }
        
        guard let mdmConfiguration = ObvMessengerSettings.MDM.configuration else { return }
        
        for (key, value) in mdmConfiguration {
            if let valueString = value as? String {
                os_log("[MDM] %{public}@ : %{public}@", log: log, type: .info, key, valueString)
            } else if let valueInt = value as? String {
                os_log("[MDM] %{public}@ : %{public}d", log: log, type: .info, key, valueInt)
            } else {
                os_log("[MDM] %{public}@ : Cannot read value", log: log, type: .info, key)
            }
        }
        
    }
    
}
