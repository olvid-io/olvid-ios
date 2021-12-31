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
import os.log
import ObvTypes
import ObvMetaManager
import OlvidUtils


final public class ObvBackupManagerImplementationDummy: ObvBackupDelegate {
            
    static let defaultLogSubsystem = "io.olvid.backup.dummy"
    lazy public var logSubsystem: String = {
        return ObvBackupManagerImplementationDummy.defaultLogSubsystem
    }()
    
    public func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
        self.log = OSLog(subsystem: logSubsystem, category: "ObvBackupManagerImplementationDummy")
    }

    public func applicationDidStartRunning(flowId: FlowIdentifier) {}
    public func applicationDidEnterBackground() {}

    private static let errorDomain = "ObvBackupManagerImplementationDummy"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    // MARK: Instance variables
    
    private var log: OSLog

    // MARK: Initialiser

    public init() {
        self.log = OSLog(subsystem: ObvBackupManagerImplementationDummy.defaultLogSubsystem, category: "ObvBackupManagerImplementationDummy")
    }

    // Not used in this dummy implementation
    public let isBackupRequired = false
    
    public func userJustActivatedAutomaticBackup() {
        os_log("userJustActivatedAutomaticBackup does nothing in this dummy implementation", log: log, type: .info)
    }
    
    public func registerAllBackupableManagers(_ allBackupableManagers: [ObvBackupableManager]) {
        os_log("registerAllBackupableManagers does nothing in this dummy implementation", log: log, type: .info)
    }
    
    public func registerAppBackupableObject(_ appBackupableObject: ObvBackupable) {
        os_log("registerAppBackupableObject does nothing in this dummy implementation", log: log, type: .info)
    }
    
    public func generateNewBackupKey(flowId: FlowIdentifier) {
        os_log("generateNewBackupKey does nothing in this dummy implementation", log: log, type: .error)
    }

    public func initiateBackup(forExport: Bool, backupRequestIdentifier: FlowIdentifier) throws {
        os_log("initiateBackup does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func fulfill(requiredDelegate: AnyObject, forDelegateType: ObvEngineDelegateType) throws {}
    
    public var requiredDelegates = [ObvEngineDelegateType]()
    
    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {}
    
    public func getBackupKeyInformation(flowId: FlowIdentifier) throws -> BackupKeyInformation? {
        os_log("initiateBackup does nothing in this dummy implementation", log: log, type: .error)
        throw ObvBackupManagerImplementationDummy.makeError(message: "initiateBackup does nothing in this dummy implementation")
    }

    public func markBackupAsExported(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) throws {
        os_log("markBackupAsExported does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func markBackupAsUploaded(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) throws {
        os_log("markBackupAsUploaded does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func markBackupAsFailed(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) throws {
        os_log("markBackupAsFailed does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func verifyBackupKey(backupSeedString: String, flowId: FlowIdentifier, completion: @escaping (Result<Void,Error>) -> Void) {
        os_log("verifyBackupKey does nothing in this dummy implementation", log: log, type: .error)
    }

    public func recoverBackupData(_: Data, withBackupKey: String, backupRequestIdentifier: FlowIdentifier, completion: @escaping (Result<(backupRequestIdentifier: UUID, backupDate: Date), BackupRestoreError>) -> Void) {
        os_log("recoverBackupData does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func restoreFullBackup(backupRequestIdentifier: FlowIdentifier, completionHandler: @escaping ((Result<Void, Error>) -> Void)) {
        os_log("restoreFullBackup does nothing in this dummy implementation", log: log, type: .error)
    }
}
