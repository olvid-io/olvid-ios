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
import CoreData
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils


@objc(Backup)
final class Backup: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "Backup"
    private static let rawBackupKeyKey = "rawBackupKey"
    private static let versionKey = "version"
    private static let statusRawKey = "statusRaw"

    enum Status: Int, CustomDebugStringConvertible {
        case ongoing = 0
        case ready = 1
        case uploaded = 2
        case exported = 3
        case failed = -1
        
        var debugDescription: String {
            switch self {
            case .ongoing: return "ongoing"
            case .ready: return "ready"
            case .uploaded: return "uploaded"
            case .exported: return "exported"
            case .failed: return "failed"
            }
        }
    }
    
    // MARK: Attributes
    
    @NSManaged private(set) var backupJsonVersion: Int
    @NSManaged fileprivate var encryptedContentRaw: Data?
    @NSManaged private(set) var forExport: Bool
    @NSManaged private(set) var statusChangeTimestamp: Date
    @NSManaged private var rawBackupKeyUid: Data // Required for enforcing core data constrains
    @NSManaged private var statusRaw: Int
    @NSManaged private(set) var version: Int // Incremented for each backup with the same key

    // MARK: Relationships
    
    // If nil, we expect this backup to be cascade deleted
    private var rawBackupKey: BackupKey? {
        get {
            let res = kvoSafePrimitiveValue(forKey: Backup.rawBackupKeyKey) as? BackupKey
            res?.obvContext = obvContext
            return res
        }
        set {
            assert(newValue != nil)
            kvoSafeSetPrimitiveValue(newValue, forKey: Backup.rawBackupKeyKey)
        }
    }
    
    // MARK: Local variables
    
    private(set) var backupKey: BackupKey? {
        get {
            self.rawBackupKey?.obvContext = obvContext
            return self.rawBackupKey
        }
        set {
            assert(newValue != nil)
            if let uid = newValue?.uid {
                self.rawBackupKeyUid = uid.raw
            }
            self.rawBackupKey = newValue
        }
    }

    private(set) var encryptedContent: EncryptedData? {
        get {
            return (encryptedContentRaw == nil) ? nil : EncryptedData(data: encryptedContentRaw!)
        }
        set {
            self.encryptedContentRaw = newValue?.raw
        }
    }
    
    private(set) var status: Status {
        get {
            return Status(rawValue: statusRaw)!
        }
        set {
            statusRaw = newValue.rawValue
        }
    }
    
    // MARK: Other variables
    
    var obvContext: ObvContext?
    weak var delegateManager: ObvBackupDelegateManager?

    var successfulBackupInfos: SuccessfulBackupInfos? {
        return SuccessfulBackupInfos(backup: self)
    }
    
    private var changedKeys = Set<String>()
    
    // MARK: - Initializer

    private convenience init(forExport: Bool, status: Status, backupKey: BackupKey, delegateManager: ObvBackupDelegateManager) throws {
        
        guard let obvContext = backupKey.obvContext else { throw NSError() }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        
        self.backupJsonVersion = 0
        self.encryptedContent = nil
        self.forExport = forExport
        self.statusChangeTimestamp = Date()
        self.status = status
        self.version = 1 + (try Backup.getCurrentLatestVersionForBackupKey(backupKey, delegateManager: delegateManager, within: obvContext) ?? -1)
        
        self.backupKey = backupKey
        
        self.obvContext = obvContext
    }

    static func createOngoingBackup(forExport: Bool, backupKey: BackupKey, delegateManager: ObvBackupDelegateManager) throws -> Backup {
        let backup = try Backup(forExport: forExport, status: .ongoing, backupKey: backupKey, delegateManager: delegateManager)
        backup.delegateManager = delegateManager
        return backup
    }
    
}

// MARK: - Managing errors

extension Backup {
    
    private static let errorDomain = "Backup"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }
    
}

// MARK: - Managing status

extension Backup {
    
    func setFailed() throws {
        switch status {
        case .exported, .uploaded:
            throw Backup.makeError(message: "Cannot transtion from status \(self.status.debugDescription) to status \(Status.failed.debugDescription)")
        case .failed, .ongoing, .ready:
            self.status = .failed
        }
    }
    
    func setReady(withEncryptedContent encryptedContent: EncryptedData) throws {
        switch status {
        case .exported, .failed, .ready, .uploaded:
            throw Backup.makeError(message: "Cannot transtion from status \(self.status.debugDescription) to status \(Status.ready.debugDescription)")
        case .ongoing:
            self.status = .ready
        }
        assert(self.encryptedContent == nil)
        self.encryptedContent = encryptedContent
    }
    
    func setExported() throws {
        guard forExport else {
            throw Backup.makeError(message: "Trying to mark as exported a backup that was not intended for export")
        }
        switch status {
        case .ready:
            self.status = .exported
        default:
            throw Backup.makeError(message: "Cannot transtion from status \(self.status.debugDescription) to status \(Status.exported.debugDescription)")
        }
    }

    func setUploaded() throws {
        guard !forExport else {
            throw Backup.makeError(message: "Trying to mark as uploaded a backup that was not intended for upload")
        }
        switch status {
        case .ready:
            self.status = .uploaded
        default:
            throw Backup.makeError(message: "Cannot transtion from status \(self.status.debugDescription) to status \(Status.uploaded.debugDescription)")
        }
    }

}

extension Backup {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<Backup> {
        return NSFetchRequest<Backup>(entityName: self.entityName)
    }

    private static func getCurrentLatestVersionForBackupKey(_ backupKey: BackupKey, delegateManager: ObvBackupDelegateManager, within obvContext: ObvContext) throws -> Int? {
        let allBackups = try Backup.getAllBackupsForBackupKey(backupKey, delegateManager: delegateManager, within: obvContext)
        return allBackups.map({ $0.version }).max()
    }
    
    private static func getAllBackupsForBackupKey(_ backupKey: BackupKey, delegateManager: ObvBackupDelegateManager, within obvContext: ObvContext) throws -> [Backup] {
        let request: NSFetchRequest<Backup> = Backup.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@",
                                        self.rawBackupKeyKey, backupKey)
        request.sortDescriptors = [NSSortDescriptor(key: self.versionKey, ascending: false)]
        let items = try obvContext.fetch(request)
        return items.map { $0.obvContext = obvContext; return $0 }
    }
    
    static func get(objectID: NSManagedObjectID, delegateManager: ObvBackupDelegateManager, within obvContext: ObvContext) throws -> Backup? {
        let request: NSFetchRequest<Backup> = Backup.fetchRequest()
        request.predicate = NSPredicate(format: "Self == %@", objectID)
        request.fetchLimit = 1
        let item = try obvContext.fetch(request).first
        item?.obvContext = obvContext
        item?.delegateManager = delegateManager
        return item
    }
    
}


extension Backup {
    
    
    override func willSave() {
        super.willSave()
        if isUpdated {
            changedKeys = Set<String>(self.changedValues().keys)
        }
    }

    override func didSave() {
        super.didSave()
        
        guard let flowId = obvContext?.flowId else {
            assertionFailure()
            return
        }

        guard let delegateManager = self.delegateManager else {
            let log = OSLog(subsystem: ObvBackupDelegateManager.defaultLogSubsystem, category: "Backup")
            os_log("The delegate manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: "Backup")
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        if isInserted && status == .ongoing {
            // For now we do not send any notification when an ongoing backup is created
        } else if changedKeys.contains(Backup.statusRawKey) {
            let notification: ObvBackupNotification?
            switch status {
            case .ongoing:
                notification = nil
            case .ready:
                if let successfulBackupInfos = successfulBackupInfos {
                    if successfulBackupInfos.forExport {
                        notification = ObvBackupNotification.backupForExportWasFinished(backupKeyUid: successfulBackupInfos.backupKeyUid, version: successfulBackupInfos.version, encryptedContent: successfulBackupInfos.encryptedContentRaw, flowId: flowId)
                    } else {
                        notification = ObvBackupNotification.backupForUploadWasFinished(backupKeyUid: successfulBackupInfos.backupKeyUid, version: successfulBackupInfos.version, encryptedContent: successfulBackupInfos.encryptedContentRaw, flowId: flowId)
                    }
                } else {
                    assertionFailure()
                    notification = ObvBackupNotification.backupFailed(flowId: flowId)
                }
            case .exported:
                if let successfulBackupInfos = successfulBackupInfos {
                    notification = ObvBackupNotification.backupForExportWasExported(backupKeyUid: successfulBackupInfos.backupKeyUid, version: successfulBackupInfos.version, flowId: flowId)
                } else {
                    notification = nil
                    assertionFailure()
                }
            case .uploaded:
                if let successfulBackupInfos = successfulBackupInfos {
                    notification = ObvBackupNotification.backupForUploadWasUploaded(backupKeyUid: successfulBackupInfos.backupKeyUid, version: successfulBackupInfos.version, flowId: flowId)
                } else {
                    notification = nil
                    assertionFailure()
                }
            case .failed:
                notification = ObvBackupNotification.backupFailed(flowId: flowId)
            }
            notification?.postOnDispatchQueue(withLabel: "Queue for posting a Backup status changed notification", within: notificationDelegate)
        }
        
    }
    
}

struct SuccessfulBackupInfos {
    
    let backupKeyUid: UID
    let backupJsonVersion: Int
    let encryptedContentRaw: Data
    let forExport: Bool
    let statusChangeTimestamp: Date
    let version: Int
    
    fileprivate init?(backup: Backup) {
        guard backup.status != .failed && backup.status != .ongoing else { return nil }
        guard let encryptedContentRaw = backup.encryptedContentRaw else { return nil }
        guard let backupKeyUid = backup.backupKey?.uid else { return nil }
        self.backupKeyUid = backupKeyUid
        self.backupJsonVersion = backup.backupJsonVersion
        self.encryptedContentRaw = encryptedContentRaw
        self.forExport = backup.forExport
        self.statusChangeTimestamp = backup.statusChangeTimestamp
        self.version = backup.version
    }
    
}
