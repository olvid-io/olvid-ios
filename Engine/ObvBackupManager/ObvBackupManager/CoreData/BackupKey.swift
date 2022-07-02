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
import CoreData
import ObvTypes
import ObvCrypto
import ObvEncoder
import ObvMetaManager
import OlvidUtils


@objc(BackupKey)
final class BackupKey: NSManagedObject, ObvManagedObject {

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

    private(set) var backups: Set<Backup> {
        get {
            let res = kvoSafePrimitiveValue(forKey: BackupKey.backupsKey) as! Set<Backup>
            return Set(res.map { $0.obvContext = self.obvContext; $0.delegateManager = self.delegateManager; return $0 })
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
    
    var lastExportedBackup: Backup? {
        let exportedBackups = backups.filter({ $0.status == .exported })
        guard !exportedBackups.isEmpty else { return nil }
        let someBackup = exportedBackups.first!
        return exportedBackups.reduce(someBackup) { $0.version > $1.version ? $0 : $1 }
    }

    var lastUploadedBackup: Backup? {
        let uploadedBackups = backups.filter({ $0.status == .uploaded })
        guard !uploadedBackups.isEmpty else { return nil }
        let someBackup = uploadedBackups.first!
        return uploadedBackups.reduce(someBackup) { $0.version > $1.version ? $0 : $1 }
    }

    var lastUploadedBackupThatFailed: Backup? {
        let failedBackupsForUpload = backups.filter({ $0.status == .failed && !$0.forExport })
        guard !failedBackupsForUpload.isEmpty else { return nil }
        let someBackup = failedBackupsForUpload.first!
        return failedBackupsForUpload.reduce(someBackup) { $0.version > $1.version ? $0 : $1 }
    }
        
    var lastBackup: Backup? {
        guard !self.backups.isEmpty else { return nil }
        let someBackup = self.backups.first!
        return self.backups.reduce(someBackup, { $0.version > $1.version ? $0 : $1 })
    }
    
    // MARK: Other variables
    
    var obvContext: ObvContext?
    weak var delegateManager: ObvBackupDelegateManager?

    var backupKeyInformation: BackupKeyInformation {
        return BackupKeyInformation(uid: self.uid,
                                    keyGenerationTimestamp: self.keyGenerationTimestamp,
                                    lastSuccessfulKeyVerificationTimestamp: self.lastSuccessfulKeyVerificationTimestamp,
                                    successfulVerificationCount: self.successfulVerificationCount,
                                    lastBackupExportTimestamp: self.lastExportedBackup?.statusChangeTimestamp,
                                    lastBackupUploadTimestamp: self.lastUploadedBackup?.statusChangeTimestamp,
                                    lastBackupUploadFailureTimestamp: self.lastUploadedBackupThatFailed?.statusChangeTimestamp)
    }
    
    // MARK: - Initializer
    
    convenience init(derivedKeysForBackup: DerivedKeysForBackup, delegateManager: ObvBackupDelegateManager, within obvContext: ObvContext) {
        
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
        self.delegateManager = delegateManager
        
    }
    
}

// MARK: - Various methods

extension BackupKey {
    
    func addSuccessfulVerification() {
        self.lastSuccessfulKeyVerificationTimestamp = Date()
        self.successfulVerificationCount += 1
    }
    
}

// MARK: - Accessing the items

extension BackupKey {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<BackupKey> {
        return NSFetchRequest<BackupKey>(entityName: self.entityName)
    }

    static func deleteAll(delegateManager: ObvBackupDelegateManager, within obvContext: ObvContext) throws {
        let items = try getAll(delegateManager: delegateManager, within: obvContext)
        for item in items {
            _ = item.backups.map({ $0.delegateManager = delegateManager })
            obvContext.delete(item)
        }
    }
    
    static func getAll(delegateManager: ObvBackupDelegateManager, within obvContext: ObvContext) throws -> Set<BackupKey> {
        let request: NSFetchRequest<BackupKey> = BackupKey.fetchRequest()
        let items = try obvContext.fetch(request)
        return Set(items.map { $0.obvContext = obvContext; $0.delegateManager = delegateManager; return $0 })
    }
    
    static func getCurrent(delegateManager: ObvBackupDelegateManager, within obvContext: ObvContext) throws -> BackupKey? {
        let request: NSFetchRequest<BackupKey> = BackupKey.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: BackupKey.keyGenerationTimestampKey, ascending: false)]
        request.fetchLimit = 1
        let items = try obvContext.fetch(request)
        return items.map({ $0.obvContext = obvContext; $0.delegateManager = delegateManager; return $0 }).last
    }
    
}
