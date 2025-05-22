/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OSLog
import ObvCrypto
import OlvidUtils
import ObvTypes


@objc(PersistedDeviceBackupSeed)
final class PersistedDeviceBackupSeed: NSManagedObject {
    
    private static let entityName = "PersistedDeviceBackupSeed"
    private static let logger = Logger(subsystem: "io.olvid.backup", category: "PersistedDeviceBackupSeed")
    
    // MARK: Properties

    @NSManaged private(set) var isActive: Bool // There can be at most one active key at a time. Inactive keys are being cleaned from server and deleted. An inactive key means there is a device backup to delete on server.
    @NSManaged private var rawBackupSeed: Data? // Mandatory in the model, primary key
    @NSManaged private var rawNextBackupUUID: UUID?
    @NSManaged private var rawSecAttrAccount: String? // Non-nil in the model
    @NSManaged private var rawServerURL: URL? // Mandatory in the model

    // MARK: - Accessors
    
    /// Expected to be non-nil
    var backupSeed: BackupSeed? {
        guard let rawBackupSeed else { assertionFailure(); return nil }
        return BackupSeed(with: rawBackupSeed)
    }
    
    /// Expected to be non-nil
    var serverURLForStoringDeviceBackup: URL? {
        guard let rawServerURL else { assertionFailure(); return nil }
        return rawServerURL
    }
    
    var secAttrAccount: String? {
        guard let rawSecAttrAccount else { assertionFailure(); return nil }
        return rawSecAttrAccount
    }
    
    // MARK: - Initializer
    
    private convenience init(serverURLForStoringDeviceBackup: URL, physicalDeviceName: String, prng: PRNGService, within context: NSManagedObjectContext) {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedDeviceBackupSeed.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        let newBackupSeed = prng.genBackupSeed()

        self.isActive = true
        self.rawBackupSeed = newBackupSeed.raw
        self.rawNextBackupUUID = nil
        self.rawServerURL = serverURLForStoringDeviceBackup
        self.rawSecAttrAccount = [physicalDeviceName, String(UUID().uuidString)].joined(separator: " ")
        
    }
    
    
    /// Generate a new `PersistedDeviceBackupSeed`. This method throws if an active `PersistedDeviceBackupSeed` already exists.
    static func createNewPersistedDeviceBackupSeed(serverURLForStoringDeviceBackup: URL, physicalDeviceName: String, prng: PRNGService, within context: NSManagedObjectContext) throws(ObvError) -> PersistedDeviceBackupSeedStruct {
        guard try Self.noActivePersistedDeviceBackupSeedExists(within: context) else {
            assertionFailure()
            throw .anActivePersistedDeviceBackupSeedAlreadyExists
        }
        let persistedDeviceBackupSeed = PersistedDeviceBackupSeed(serverURLForStoringDeviceBackup: serverURLForStoringDeviceBackup, physicalDeviceName: physicalDeviceName, prng: prng, within: context)
        guard let backupSeed = persistedDeviceBackupSeed.backupSeed else {
            assertionFailure()
            throw .couldNotParseBackupSeed
        }
        guard let serverURLForStoringDeviceBackup = persistedDeviceBackupSeed.serverURLForStoringDeviceBackup else {
            assertionFailure()
            throw .couldNotParseServerURL
        }
        guard let secAttrAccount = persistedDeviceBackupSeed.secAttrAccount else {
            assertionFailure()
            throw .couldNotParseSecAttrAccount
        }
        return .init(backupSeed: backupSeed, serverURLForStoringDeviceBackup: serverURLForStoringDeviceBackup, secAttrAccount: secAttrAccount)
    }
    
    
    private func deletePersistedDeviceBackupSeed() throws(ObvError) {
        guard let context = self.managedObjectContext else {
            assertionFailure()
            throw .contextIsNil
        }
        context.delete(self)
    }
    
}


// MARK: - Errors

extension PersistedDeviceBackupSeed {
    
    enum ObvError: Error {
        case anActivePersistedDeviceBackupSeedAlreadyExists
        case noActiveDeviceBackupSeed
        case couldNotParseBackupSeed
        case couldNotParseServerURL
        case couldNotParseSecAttrAccount
        case contextIsNil
        case coreDataError(Error)
    }
    
    enum GetError: Error {
        case couldNotParseBackupSeed
        case couldNotParseServerURL
        case couldNotParseSecAttrAccount
        case coreDataError(Error)
    }
    
}


// MARK: - Convenience DB getters

extension PersistedDeviceBackupSeed {
    
    private struct Predicate {
        enum Key: String {
            // Properties
            case isActive = "isActive"
            case rawBackupSeed = "rawBackupSeed"
            case rawNextBackupUUID = "rawNextBackupUUID"
            case rawSecAttrAccount = "rawSecAttrAccount"
            case rawServerURL = "rawServerURL"
        }
        static var isActive: NSPredicate {
            NSPredicate(Key.isActive, is: true)
        }
        static var isNotActive: NSPredicate {
            NSPredicate(Key.isActive, is: false)
        }
        static func withBackupSeed(_ backupSeed: BackupSeed) -> NSPredicate {
            NSPredicate(Key.rawBackupSeed, EqualToData: backupSeed.raw)
        }
    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedDeviceBackupSeed> {
        return NSFetchRequest<PersistedDeviceBackupSeed>(entityName: self.entityName)
    }

    
    static func deletePersistedDeviceBackupSeed(backupSeed: BackupSeed, within context: NSManagedObjectContext) throws {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: PersistedDeviceBackupSeed.entityName)
        fetchRequest.predicate = Predicate.withBackupSeed(backupSeed)
        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        batchDeleteRequest.resultType = .resultTypeStatusOnly
        _ = try context.execute(batchDeleteRequest)
    }


    private static func noActivePersistedDeviceBackupSeedExists(within context: NSManagedObjectContext) throws(ObvError) -> Bool {
        let fetchRequest = Self.fetchRequest()
        fetchRequest.predicate = Predicate.isActive
        fetchRequest.fetchLimit = 1
        fetchRequest.propertiesToFetch = []
        fetchRequest.returnsObjectsAsFaults = true
        let results: [PersistedDeviceBackupSeed]
        do {
            results = try context.fetch(fetchRequest)
        } catch {
            throw .coreDataError(error)
        }
        return results.isEmpty
    }
    
    
    static func deactivateAllPersistedDeviceBackupSeeds(within context: NSManagedObjectContext) throws(ObvError) {
        let fetchRequest = Self.fetchRequest()
        fetchRequest.predicate = Predicate.isActive
        fetchRequest.fetchBatchSize = 100 // We expect only one result
        fetchRequest.propertiesToFetch = []
        fetchRequest.returnsObjectsAsFaults = true
        let results: [PersistedDeviceBackupSeed]
        do {
            results = try context.fetch(fetchRequest)
        } catch {
            throw .coreDataError(error)
        }
        results.forEach { $0.isActive = false }
    }
    
    
    static func getActiveDeviceBackupSeedStruct(within context: NSManagedObjectContext) throws(GetError) -> PersistedDeviceBackupSeedStruct? {
        let fetchRequest = Self.fetchRequest()
        fetchRequest.predicate = Predicate.isActive
        fetchRequest.fetchLimit = 1
        fetchRequest.propertiesToFetch = [
            Predicate.Key.rawBackupSeed.rawValue,
            Predicate.Key.rawServerURL.rawValue,
        ]
        let result: PersistedDeviceBackupSeed
        do {
            guard let _result = try context.fetch(fetchRequest).first else { return nil }
            result = _result
        } catch {
            throw .coreDataError(error)
        }
        guard let backupSeed = result.backupSeed else {
            assertionFailure()
            throw .couldNotParseBackupSeed
        }
        guard let serverURLForStoringDeviceBackup = result.serverURLForStoringDeviceBackup else {
            assertionFailure()
            throw .couldNotParseServerURL
        }
        guard let secAttrAccount = result.secAttrAccount else {
            assertionFailure()
            throw .couldNotParseSecAttrAccount
        }
        return .init(backupSeed: backupSeed, serverURLForStoringDeviceBackup: serverURLForStoringDeviceBackup, secAttrAccount: secAttrAccount)
    }

    
    static func getDeviceBackupSeedAndServer(backupSeed: BackupSeed, within context: NSManagedObjectContext) throws(GetError) -> ObvBackupSeedAndStorageServerURL? {
        let fetchRequest = Self.fetchRequest()
        fetchRequest.fetchLimit = 1
        fetchRequest.predicate = Predicate.withBackupSeed(backupSeed)
        fetchRequest.propertiesToFetch = [
            Predicate.Key.rawBackupSeed.rawValue,
            Predicate.Key.rawServerURL.rawValue,
        ]
        let result: PersistedDeviceBackupSeed
        do {
            guard let _result = try context.fetch(fetchRequest).first else { return nil }
            result = _result
        } catch {
            throw .coreDataError(error)
        }
        guard let backupSeed = result.backupSeed else {
            assertionFailure()
            throw .couldNotParseBackupSeed
        }
        guard let serverURLForStoringDeviceBackup = result.serverURLForStoringDeviceBackup else {
            assertionFailure()
            throw .couldNotParseServerURL
        }
        return ObvBackupSeedAndStorageServerURL(backupSeed: backupSeed, serverURLForStoringDeviceBackup: serverURLForStoringDeviceBackup)
    }
    
    
    static func getAllInactiveDeviceBackupSeeds(within context: NSManagedObjectContext) throws(ObvError) -> [PersistedDeviceBackupSeedStruct] {
        let fetchRequest = Self.fetchRequest()
        fetchRequest.predicate = Predicate.isNotActive
        fetchRequest.fetchBatchSize = 100
        fetchRequest.propertiesToFetch = [
            Predicate.Key.rawBackupSeed.rawValue,
        ]
        let results: [PersistedDeviceBackupSeed]
        do {
            results = try context.fetch(fetchRequest)
        } catch {
            throw .coreDataError(error)
        }
        return results.compactMap { result in
            guard let backupSeed = result.backupSeed else { assertionFailure(); return nil }
            guard let serverURLForStoringDeviceBackup = result.serverURLForStoringDeviceBackup else { assertionFailure(); return nil }
            guard let secAttrAccount = result.secAttrAccount else { assertionFailure(); return nil }
            return .init(backupSeed: backupSeed, serverURLForStoringDeviceBackup: serverURLForStoringDeviceBackup, secAttrAccount: secAttrAccount)
        }
    }
    
    
    static func deleteAllInactiveBackupSeeds(within context: NSManagedObjectContext) throws(ObvError) {
        let fetchRequest = Self.fetchRequest()
        fetchRequest.predicate = Predicate.isNotActive
        fetchRequest.fetchBatchSize = 100
        fetchRequest.propertiesToFetch = []
        fetchRequest.returnsObjectsAsFaults = true
        let results: [PersistedDeviceBackupSeed]
        do {
            results = try context.fetch(fetchRequest)
        } catch {
            throw .coreDataError(error)
        }
        for result in results {
            try result.deletePersistedDeviceBackupSeed()
        }
    }
    
    
    static func getSecAttrAccountOfActiveSeed(within context: NSManagedObjectContext) throws(ObvError) -> String {
        let fetchRequest = Self.fetchRequest()
        fetchRequest.predicate = Predicate.isActive
        fetchRequest.fetchLimit = 1
        fetchRequest.propertiesToFetch = [
            Predicate.Key.rawSecAttrAccount.rawValue,
        ]
        let item: PersistedDeviceBackupSeed?
        do {
            item = try context.fetch(fetchRequest).first
        } catch {
            throw .coreDataError(error)
        }
        guard let item else {
            throw .noActiveDeviceBackupSeed
        }
        guard let secAttrAccount = item.secAttrAccount else {
            throw .couldNotParseSecAttrAccount
        }
        return secAttrAccount
    }
    
    
    static func setNextBackupUUID(to uuid: UUID, within context: NSManagedObjectContext) throws(ObvError) {
        let fetchRequest = Self.fetchRequest()
        fetchRequest.predicate = Predicate.isActive
        fetchRequest.fetchLimit = 1
        fetchRequest.propertiesToFetch = []
        let item: PersistedDeviceBackupSeed?
        do {
            item = try context.fetch(fetchRequest).first
        } catch {
            throw .coreDataError(error)
        }
        guard let item else {
            throw .noActiveDeviceBackupSeed
        }
        item.rawNextBackupUUID = uuid
    }
    
    
    static func removeNextBackupUUIDIfEqualTo(uuid: UUID, within context: NSManagedObjectContext) throws(ObvError) {
        
        let fetchRequest = Self.fetchRequest()
        fetchRequest.predicate = Predicate.isActive
        fetchRequest.fetchLimit = 1
        fetchRequest.propertiesToFetch = [
            Predicate.Key.rawNextBackupUUID.rawValue,
        ]
        let item: PersistedDeviceBackupSeed?
        do {
            item = try context.fetch(fetchRequest).first
        } catch {
            throw .coreDataError(error)
        }
        guard let item else {
            return
        }
        if item.rawNextBackupUUID == uuid {
            item.rawNextBackupUUID = nil
        }
        
    }
    
    
    static func getNextBackupUUID(within context: NSManagedObjectContext) throws(ObvError) -> UUID? {
        let fetchRequest = Self.fetchRequest()
        fetchRequest.predicate = Predicate.isActive
        fetchRequest.fetchLimit = 1
        fetchRequest.propertiesToFetch = [
            Predicate.Key.rawNextBackupUUID.rawValue,
        ]
        let item: PersistedDeviceBackupSeed?
        do {
            item = try context.fetch(fetchRequest).first
        } catch {
            throw .coreDataError(error)
        }
        guard let item else {
            return nil
        }
        return item.rawNextBackupUUID
    }

}



// MARK: - PersistedDeviceBackupSeedStruct

struct PersistedDeviceBackupSeedStruct {

    let backupSeed: BackupSeed
    let serverURLForStoringDeviceBackup: URL
    let secAttrAccount: String
    
    var backupSeedAndStorageServerURL: ObvBackupSeedAndStorageServerURL {
        .init(backupSeed: backupSeed, serverURLForStoringDeviceBackup: serverURLForStoringDeviceBackup)
    }
    
}
