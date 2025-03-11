/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
final class Backup: NSManagedObject, ObvManagedObject, ObvErrorMaker {

    static let errorDomain = "Backup"

    // MARK: Internal constants
    
    private static let entityName = "Backup"

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
    /// ``true`` if the backup was exported to the device Files app,
    /// ``false`` if the backup was uploaded to iCloud.
    @NSManaged private(set) var forExport: Bool
    @NSManaged private(set) var statusChangeTimestamp: Date
    @NSManaged private var rawBackupKeyUid: Data // Required for enforcing core data constrains
    @NSManaged private var statusRaw: Int
    @NSManaged private(set) var version: Int // Incremented for each backup with the same key

    // MARK: Relationships
    
    // If nil, we expect this backup to be cascade deleted
    private var rawBackupKey: BackupKey? {
        get {
            let res = kvoSafePrimitiveValue(forKey: Predicate.Key.rawBackupKey.rawValue) as? BackupKey
            res?.obvContext = obvContext
            return res
        }
        set {
            assert(newValue != nil)
            kvoSafeSetPrimitiveValue(newValue, forKey: Predicate.Key.rawBackupKey.rawValue)
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
    
    weak var obvContext: ObvContext?

    var successfulBackupInfos: SuccessfulBackupInfos? {
        return SuccessfulBackupInfos(backup: self)
    }

    // MARK: - Initializer

    private convenience init(forExport: Bool, status: Status, backupKey: BackupKey) throws {
        
        guard let obvContext = backupKey.obvContext else { throw Self.makeError(message: "The context of the backupKey is nil") }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        
        self.backupJsonVersion = 0
        self.encryptedContent = nil
        self.forExport = forExport
        self.statusChangeTimestamp = Date()
        self.status = status
        self.version = 1 + (try Backup.getCurrentLatestVersionForBackupKey(backupKey, within: obvContext) ?? -1)
        
        self.backupKey = backupKey
        
        self.obvContext = obvContext
    }

    static func createOngoingBackup(forExport: Bool, backupKey: BackupKey) throws -> Backup {
        let backup = try Backup(forExport: forExport, status: .ongoing, backupKey: backupKey)
        return backup
    }
    
    
    static func deleteBackup(_ backup: Backup) throws {
        guard let context = backup.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        context.delete(backup)
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
        // Delete older exported or ready backups backups
        if let backupKey {
            try? Self.deleteAllBackups(withStatus: .ready, withVersionLessThan: self.version, for: backupKey)
            try? Self.deleteAllBackups(withStatus: .exported, withVersionLessThan: self.version, for: backupKey)
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
        // Delete older uploaded backups
        if let backupKey {
            try? Self.deleteAllBackups(withStatus: .uploaded, withVersionLessThan: self.version, for: backupKey)
        }
    }

}

extension Backup {
    
    private struct Predicate {
        fileprivate enum Key: String {
            case forExport = "forExport"
            case statusRaw = "statusRaw"
            case version = "version"
            case rawBackupKey = "rawBackupKey"
        }
        static func withBackupKey(equalTo backupKey: BackupKey) -> NSPredicate {
            NSPredicate(Key.rawBackupKey, equalTo: backupKey)
        }
        static func withStatus(equalTo status: Status) -> NSPredicate {
            NSPredicate(Key.statusRaw, EqualToInt: status.rawValue)
        }
        static var withMaxVersion: NSPredicate {
            NSPredicate(format: "%K == max(%K)", Key.version.rawValue, Key.version.rawValue)
        }
        static func forExportIs(_ forExport: Bool) -> NSPredicate {
            NSPredicate(Key.forExport, is: forExport)
        }
        static func withVersionEqualTo(_ version: Int) -> NSPredicate {
            NSPredicate(Key.version, EqualToInt: version)
        }
        static func withVersionLessThan(_ version: Int) -> NSPredicate {
            NSPredicate(Key.version, LessThanInt: version)
        }
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<Backup> {
        return NSFetchRequest<Backup>(entityName: self.entityName)
    }

    private static func getCurrentLatestVersionForBackupKey(_ backupKey: BackupKey, within obvContext: ObvContext) throws -> Int? {
        return try getLastBackup(for: backupKey)?.version
    }

    static func get(objectID: NSManagedObjectID, within obvContext: ObvContext) throws -> Backup? {
        let request: NSFetchRequest<Backup> = Backup.fetchRequest()
        request.predicate = NSPredicate(format: "Self == %@", objectID)
        request.fetchLimit = 1
        let item = try obvContext.fetch(request).first
        item?.obvContext = obvContext
        return item
    }


    static func getLastBackup(withStatus status: Status?, for backupKey: BackupKey) throws -> Backup? {
        return try getLastBackup(withStatus: status, forExport: nil, for: backupKey)
    }

    
    static func getLastUploadedBackupThatFailed(for backupKey: BackupKey) throws -> Backup? {
        return try getLastBackup(withStatus: .failed, forExport: false, for: backupKey)
    }
    
    
    private static func getLastBackup(withStatus status: Status? = nil,
                                      forExport: Bool? = nil,
                                      for backupKey: BackupKey) throws -> Backup? {
        guard let obvContext = backupKey.obvContext else {
            assertionFailure()
            throw Self.makeError(message: "ObvContext is not set")
        }
        let request: NSFetchRequest<Backup> = Backup.fetchRequest()
        var predicates = [Predicate.withBackupKey(equalTo: backupKey)]
        if let status {
            predicates += [Predicate.withStatus(equalTo: status)]
        }
        if let forExport {
            predicates += [Predicate.forExportIs(forExport)]
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        // We cannot add the withMaxVersion in the predicates, as the item with a max version number has not necessarily the queried status
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.version.rawValue, ascending: false)]
        request.fetchLimit = 1
        let item = try obvContext.fetch(request).first
        item?.obvContext = obvContext
        return item
    }

    static func getBackup(withVersion version: Int, for backupKey: BackupKey) throws -> Backup? {
        guard let obvContext = backupKey.obvContext else {
            assertionFailure()
            throw Self.makeError(message: "ObvContext is not set")
        }
        let request: NSFetchRequest<Backup> = Backup.fetchRequest()
        request.fetchLimit = 1 // We expect only one backup for a specific version number
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withBackupKey(equalTo: backupKey),
            Predicate.withVersionEqualTo(version),
        ])
        let item = try obvContext.fetch(request).first
        item?.obvContext = obvContext
        return item
    }
    
    
    static func getMaxVersionAmongBackups(withStatus status: Status, for backupKey: BackupKey) throws -> Int? {
        
        guard let obvContext = backupKey.obvContext else {
            assertionFailure()
            throw Self.makeError(message: "ObvContext is not set")
        }
        
        let request = NSFetchRequest<NSDictionary>(entityName: self.entityName)
        request.resultType = .dictionaryResultType
        
        let keyPathExpression = NSExpression(forKeyPath: \Backup.version)
        let expressionForMaxFunction = NSExpression(forFunction: "max:", arguments: [keyPathExpression])
        let expressionDescription = NSExpressionDescription()
        expressionDescription.name = Predicate.Key.version.rawValue
        expressionDescription.expression = expressionForMaxFunction
        expressionDescription.expressionResultType = .integer64AttributeType
        request.propertiesToFetch = [expressionDescription]
        
        request.fetchLimit = 1 // We expect only one backup for a specific version number
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withBackupKey(equalTo: backupKey),
            Predicate.withStatus(equalTo: status),
        ])
                
        guard let dict = try obvContext.context.fetch(request).first else {
            return nil
        }
        
        guard let maxVersion = dict[Predicate.Key.version.rawValue] as? Int else {
            return nil
        }

        return Int(maxVersion)
        
    }
    
    
    static func deleteAllBackups(withStatus status: Status, withVersionLessThan version: Int, for backupKey: BackupKey) throws {
        
        guard let obvContext = backupKey.obvContext else {
            assertionFailure()
            throw Self.makeError(message: "ObvContext is not set")
        }
        
        let request: NSFetchRequest<Backup> = Backup.fetchRequest()
        request.fetchBatchSize = 500
        request.propertiesToFetch = []
        
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withBackupKey(equalTo: backupKey),
            Predicate.withStatus(equalTo: status),
            Predicate.withVersionLessThan(version),
        ])

        let backups = try obvContext.context.fetch(request)
        for backup in backups {
            try Self.deleteBackup(backup)
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
