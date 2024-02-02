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
import CoreData
import ObvTypes
import ObvCrypto
import ObvEncoder
import ObvMetaManager
import OlvidUtils
import os.log

@objc(BackupKey)
final class BackupKey: NSManagedObject, ObvManagedObject, ObvErrorMaker {

    static let errorDomain = "BackupKey"

    // MARK: Internal constants
    
    private static let entityName = "BackupKey"
    private static let backupsKey = "backups"
    private static let keyGenerationTimestampKey = "keyGenerationTimestamp"

    // MARK: Attributes

    @NSManaged private var encryptionPublicKeyRaw: Data
    @NSManaged private(set) var keyGenerationTimestamp: Date
    @NSManaged private var lastKeyVerificationPromptTimestamp: Date?
    @NSManaged private(set) var lastSuccessfulKeyVerificationTimestamp: Date?
    @NSManaged private var macKeyRaw: Data
    @NSManaged private(set) var successfulVerificationCount: Int
    @NSManaged private var uidRaw: Data

    // MARK: Relationships

    private var backups: Set<Backup> {
        get {
            let res = kvoSafePrimitiveValue(forKey: BackupKey.backupsKey) as! Set<Backup>
            res.forEach {
                $0.obvContext = self.obvContext
            }
            return res
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: BackupKey.backupsKey)
        }
    }
    
    // MARK: Local variables
    
    private var encryptionPublicKey: PublicKeyForPublicKeyEncryption {
        get {
            let encoded = ObvEncoded(withRawData: encryptionPublicKeyRaw)!
            return PublicKeyForPublicKeyEncryptionDecoder.obvDecode(encoded)!
        }
        set {
            self.encryptionPublicKeyRaw = newValue.obvEncode().rawData
        }
    }
    
    private var macKey: MACKey {
        get {
            let encoded = ObvEncoded(withRawData: macKeyRaw)!
            return MACKeyDecoder.decode(encoded)!
        }
        set {
            self.macKeyRaw = newValue.obvEncode().rawData
        }
    }
    
    private(set) var uid: UID {
        get {
            return UID(uid: uidRaw)!
        }
        set {
            self.uidRaw = newValue.raw
        }
    }
    
    var derivedKeysForBackup: DerivedKeysForBackup {
        return DerivedKeysForBackup(backupKeyUid: self.uid,
                                    publicKeyForEncryption: self.encryptionPublicKey,
                                    macKey: self.macKey)
    }
    
    var lastBackup: Backup? {
        get throws {
            // For efficiency reasons, we do not use the backups relationship. Instead, we perform a Core Data query.
            return try Backup.getLastBackup(withStatus: nil, for: self)
        }
    }


    var lastExportedBackup: Backup? {
        get throws {
            // For efficiency reasons, we do not use the backups relationship. Instead, we perform a Core Data query.
            return try Backup.getLastBackup(withStatus: .exported, for: self)
        }
    }


    var lastUploadedBackup: Backup? {
        get throws {
            // For efficiency reasons, we do not use the backups relationship. Instead, we perform a Core Data query.
            return try Backup.getLastBackup(withStatus: .uploaded, for: self)
        }
    }

    /// Returns the last uploaded backup that failed, or nil if there is a more recent uploaded backup that succeeded.
    var lastBackupForUploadThatFailed: Backup? {
        get throws {
            return try Backup.getLastUploadedBackupThatFailed(for: self)
        }
    }


    func getBackupWithVersion(_ backupVersion: Int) throws -> Backup? {
        // For efficiency reasons, we do not use the backups relationship. Instead, we perform a Core Data query.
        return try Backup.getBackup(withVersion: backupVersion, for: self)
    }
    
    
    // MARK: Other variables
    
    var obvContext: ObvContext?

    var backupKeyInformation: BackupKeyInformation {
        get throws {
            return BackupKeyInformation(uid: self.uid,
                                        keyGenerationTimestamp: self.keyGenerationTimestamp,
                                        lastSuccessfulKeyVerificationTimestamp: self.lastSuccessfulKeyVerificationTimestamp,
                                        successfulVerificationCount: self.successfulVerificationCount,
                                        lastBackupExportTimestamp: try self.lastExportedBackup?.statusChangeTimestamp,
                                        lastBackupUploadTimestamp: try self.lastUploadedBackup?.statusChangeTimestamp,
                                        lastBackupUploadFailureTimestamp: try self.lastBackupForUploadThatFailed?.statusChangeTimestamp)
        }
    }
    
    // MARK: - Initializer
    
    convenience init(derivedKeysForBackup: DerivedKeysForBackup, within obvContext: ObvContext) {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)

        self.encryptionPublicKey = derivedKeysForBackup.publicKeyForEncryption
        self.keyGenerationTimestamp = Date()
        self.lastKeyVerificationPromptTimestamp = nil
        self.lastSuccessfulKeyVerificationTimestamp = nil
        self.macKey = derivedKeysForBackup.macKey
        self.successfulVerificationCount = 0
        self.uid = derivedKeysForBackup.backupKeyUid
        
        self.backups = Set()
        
        self.obvContext = obvContext
    }
    
}

// MARK: - Various methods

extension BackupKey {
    
    func addSuccessfulVerification() {
        self.lastSuccessfulKeyVerificationTimestamp = Date()
        self.successfulVerificationCount += 1
    }


    /// Deletes all failed backups that are older than the most recent uploaded or exported backup that succeded.
    /// Also deletes all uploaded (resp. exported) backups that succeeded, but the most recent one.
    /// Also deletes all ready backups with a version less than the most recent exported backup.
    func deleteObsoleteBackups(log: OSLog) throws {

        // Delete all uploaded (resp. exported) backups that succeeded, but the most recent one.
        // Delete all ready backups with a version less than the most recent exported backup

        let versionOfLastUploadedBackup = try Backup.getMaxVersionAmongBackups(withStatus: .uploaded, for: self)
        if let versionOfLastUploadedBackup {
            try Backup.deleteAllBackups(withStatus: .uploaded, withVersionLessThan: versionOfLastUploadedBackup, for: self)
        }
        
        let versionOfLastExportedBackup = try Backup.getMaxVersionAmongBackups(withStatus: .exported, for: self)
        if let versionOfLastExportedBackup {
            try Backup.deleteAllBackups(withStatus: .exported, withVersionLessThan: versionOfLastExportedBackup, for: self)
            try Backup.deleteAllBackups(withStatus: .ready, withVersionLessThan: versionOfLastExportedBackup, for: self)
        }
        
        // Determine the version of the last uploaded or exported backup that was successful
        let versionOfLastSuccessfulBackup = max(versionOfLastUploadedBackup ?? 0, versionOfLastExportedBackup ?? 0)
        
        // Delete the failed backup that have a version smaller than the version found
        try Backup.deleteAllBackups(withStatus: .failed, withVersionLessThan: versionOfLastSuccessfulBackup, for: self)
        
    }
        
}


// MARK: - Accessing the items

extension BackupKey {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<BackupKey> {
        return NSFetchRequest<BackupKey>(entityName: self.entityName)
    }

    static func deleteAll(within obvContext: ObvContext) throws {
        let items = try getAll(within: obvContext)
        for item in items {
            obvContext.delete(item)
        }
    }
    
    static func getAll(within obvContext: ObvContext) throws -> Set<BackupKey> {
        let request: NSFetchRequest<BackupKey> = BackupKey.fetchRequest()
        request.fetchBatchSize = 100
        let items = try obvContext.fetch(request)
        items.forEach {
            $0.obvContext = obvContext
        }
        return Set(items)
    }
    
    static func getCurrent(within obvContext: ObvContext) throws -> BackupKey? {
        let request: NSFetchRequest<BackupKey> = BackupKey.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: BackupKey.keyGenerationTimestampKey, ascending: false)]
        request.fetchLimit = 1
        let item = try obvContext.fetch(request).last
        item?.obvContext = obvContext
        return item
    }
    
}
