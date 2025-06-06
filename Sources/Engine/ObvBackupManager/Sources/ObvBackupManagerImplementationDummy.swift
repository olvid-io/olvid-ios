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
import ObvTypes
import ObvMetaManager
import OlvidUtils
import ObvCrypto


final public class ObvBackupManagerImplementationDummy: ObvLegacyBackupDelegate {
            
    static let defaultLogSubsystem = "io.olvid.backup.dummy"
    lazy public var logSubsystem: String = {
        return ObvBackupManagerImplementationDummy.defaultLogSubsystem
    }()
    
    public func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
        self.log = OSLog(subsystem: logSubsystem, category: "ObvBackupManagerImplementationDummy")
    }

    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {}

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

    public func initiateBackup(forExport: Bool, backupRequestIdentifier: FlowIdentifier) async throws -> (backupKeyUid: UID, version: Int, encryptedContent: Data) {
        os_log("initiateBackup does nothing in this dummy implementation", log: log, type: .error)
        assertionFailure()
        throw Self.makeError(message: "initiateBackup does nothing in this dummy implementation")
    }
    
    public func fulfill(requiredDelegate: AnyObject, forDelegateType: ObvEngineDelegateType) throws {}
    
    public var requiredDelegates = [ObvEngineDelegateType]()
    
    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {}
    
    public func getBackupKeyInformation(flowId: FlowIdentifier) throws -> BackupKeyInformation? {
        os_log("initiateBackup does nothing in this dummy implementation", log: log, type: .error)
        throw ObvBackupManagerImplementationDummy.makeError(message: "initiateBackup does nothing in this dummy implementation")
    }

    public func markLegacyBackupAsExported(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) throws {
        os_log("markBackupAsExported does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func markLegacyBackupAsUploaded(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) throws {
        os_log("markBackupAsUploaded does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func markLegacyBackupAsFailed(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) throws {
        os_log("markBackupAsFailed does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func recoverBackupData(_: Data, withBackupKey: String, backupRequestIdentifier: FlowIdentifier) async throws -> (backupRequestIdentifier: UUID, backupDate: Date) {
        os_log("recoverBackupData does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "recoverBackupData does nothing in this dummy implementation")
    }
    
    public func restoreFullBackup(backupRequestIdentifier: FlowIdentifier) async throws {
        os_log("restoreFullBackup does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "restoreFullBackup does nothing in this dummy implementation")
    }
    
    public func deleteAllAsUserMigratesToNewBackups(flowId: FlowIdentifier) async throws {
        os_log("deleteAllAsUserMigratesToNewBackups does nothing in this dummy implementation", log: log, type: .error)
        throw Self.makeError(message: "deleteAllAsUserMigratesToNewBackups does nothing in this dummy implementation")
    }
}
