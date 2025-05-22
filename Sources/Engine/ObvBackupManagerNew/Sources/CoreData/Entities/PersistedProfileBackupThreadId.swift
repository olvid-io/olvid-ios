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
import ObvTypes
import OlvidUtils



@objc(PersistedProfileBackupThreadId)
final class PersistedProfileBackupThreadId: NSManagedObject {
    
    private static let entityName = "PersistedProfileBackupThreadId"
    private static let logger = Logger(subsystem: "io.olvid.backup", category: "PersistedProfileBackupThreadId")

    // MARK: Properties

    @NSManaged private var rawNextBackupUUID: UUID?
    @NSManaged private var rawOwnedIdentity: Data? // Non-nil in the model, primary key
    @NSManaged private var rawThreadUID: Data? // Non-nil in the model
    
    // MARK: - Accessors

    private var profileBackupThreadUID: UID {
        get throws {
            guard let rawThreadUID else {
                assertionFailure()
                throw ObvError.rawThreadUIDIsNil
            }
            guard let threadUID = UID(uid: rawThreadUID) else {
                assertionFailure()
                throw ObvError.threadUIDParsingFailed
            }
            return threadUID
        }
    }
    
    private var ownedCryptoId: ObvCryptoId {
        get throws {
            guard let rawOwnedIdentity else {
                throw ObvError.rawOwnedIdentityParsingFailed
            }
            return try ObvCryptoId(identity: rawOwnedIdentity)
        }
    }
    
    // MARK: - Initializer
    
    private convenience init(ownedCryptoId: ObvCryptoId, prng: PRNGService, within context: NSManagedObjectContext) {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedProfileBackupThreadId.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.rawNextBackupUUID = nil
        self.rawOwnedIdentity = ownedCryptoId.getIdentity()
        self.rawThreadUID = UID.gen(with: prng).raw
        
    }
    
    
    private func deletePersistedProfileBackupThreadId() throws(ObvError) {
        guard let context = self.managedObjectContext else {
            assertionFailure()
            throw .contextIsNil
        }
        context.delete(self)
    }

}


// MARK: Errors

extension PersistedProfileBackupThreadId {
    
    enum ObvError: Error {
        case rawThreadUIDIsNil
        case threadUIDParsingFailed
        case rawOwnedIdentityParsingFailed
        case coreDataError(Error)
        case contextIsNil
    }
    
}


// MARK: - Convenience DB getters

extension PersistedProfileBackupThreadId {
    
    private struct Predicate {
        enum Key: String {
            // Properties
            case rawNextBackupUUID = "rawNextBackupUUID"
            case rawOwnedIdentity = "rawOwnedIdentity"
            case rawThreadUID = "rawThreadUID"
        }
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentity, EqualToData: ownedCryptoId.getIdentity())
        }
        static func withThreadUID(_ threadUID: UID) -> NSPredicate {
            NSPredicate(Key.rawThreadUID, EqualToData: threadUID.raw)
        }
    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedProfileBackupThreadId> {
        return NSFetchRequest<PersistedProfileBackupThreadId>(entityName: PersistedProfileBackupThreadId.entityName)
    }
    
    
    static func deletePersistedProfileBackupThreadId(ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws {
        let fetchRequest = Self.fetchRequest()
        fetchRequest.predicate = Predicate.withOwnedCryptoId(ownedCryptoId)
        fetchRequest.fetchLimit = 1
        fetchRequest.propertiesToFetch = []
        let item = try context.fetch(fetchRequest).first
        try item?.deletePersistedProfileBackupThreadId()
    }
    
    
    private static func getProfileBackupThreadUIDForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> UID? {
        
        let fetchRequest = Self.fetchRequest()
        fetchRequest.predicate = Predicate.withOwnedCryptoId(ownedCryptoId)
        fetchRequest.fetchLimit = 1
        fetchRequest.propertiesToFetch = [Predicate.Key.rawThreadUID.rawValue]
        guard let item = try context.fetch(fetchRequest).first else {
            return nil
        }
        return try item.profileBackupThreadUID

    }
    
    
    private static func createProfileBackupThreadUIDForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId, prng: any PRNGService, within context: NSManagedObjectContext) throws -> UID {
        let item = Self.init(ownedCryptoId: ownedCryptoId, prng: prng, within: context)
        return try item.profileBackupThreadUID
    }
    
    
    static func getOrCreateProfileBackupThreadUIDForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId, prng: any PRNGService, within context: NSManagedObjectContext) throws -> UID {
        if let threadUID = try getProfileBackupThreadUIDForOwnedCryptoId(ownedCryptoId, within: context) {
            return threadUID
        } else {
            let threadUID = try createProfileBackupThreadUIDForOwnedCryptoId(ownedCryptoId, prng: prng, within: context)
            return threadUID
        }
    }
    
    
    static func getAllProfileBackupThreadId(within context: NSManagedObjectContext) throws -> [(ownedCryptoId: ObvCryptoId, profileBackupThreadUID: UID)] {
        let fetchRequest = Self.fetchRequest()
        fetchRequest.fetchBatchSize = 100
        fetchRequest.propertiesToFetch = [
            Predicate.Key.rawOwnedIdentity.rawValue,
            Predicate.Key.rawThreadUID.rawValue,
        ]
        let items: [PersistedProfileBackupThreadId] = try context.fetch(fetchRequest)
        return items.compactMap { item in
            do {
                return (try item.ownedCryptoId, try item.profileBackupThreadUID)
            } catch {
                assertionFailure()
                return nil
            }
        }
    }
    
    
    static func exists(ownedCryptoId: ObvCryptoId, threadUID: UID, within context: NSManagedObjectContext) throws -> Bool {
        let fetchRequest = Self.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoId(ownedCryptoId),
            Predicate.withThreadUID(threadUID),
        ])
        fetchRequest.fetchLimit = 1
        fetchRequest.propertiesToFetch = []
        return (try context.fetch(fetchRequest).first != nil)
    }

    
    static func setNextBackupUUID(ownedCryptoId: ObvCryptoId, to uuid: UUID, prng: any PRNGService, within context: NSManagedObjectContext) throws(ObvError) {
        let fetchRequest = Self.fetchRequest()
        fetchRequest.predicate = Predicate.withOwnedCryptoId(ownedCryptoId)
        fetchRequest.fetchLimit = 1
        fetchRequest.propertiesToFetch = []
        let item: PersistedProfileBackupThreadId
        do {
            item = try context.fetch(fetchRequest).first ?? Self.init(ownedCryptoId: ownedCryptoId, prng: prng, within: context)
        } catch {
            throw .coreDataError(error)
        }
        item.rawNextBackupUUID = uuid
    }
    
    
    static func removeNextBackupUUIDIfEqualTo(uuid: UUID, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws(ObvError) {
        
        let fetchRequest = Self.fetchRequest()
        fetchRequest.predicate = Predicate.withOwnedCryptoId(ownedCryptoId)
        fetchRequest.fetchLimit = 1
        fetchRequest.propertiesToFetch = [
            Predicate.Key.rawNextBackupUUID.rawValue,
        ]
        let item: PersistedProfileBackupThreadId?
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
    
    
    static func getNextBackupUUIDs(within context: NSManagedObjectContext) throws(ObvError) -> [(ownedCryptoId: ObvCryptoId, uuid: UUID)] {
        let fetchRequest = Self.fetchRequest()
        fetchRequest.fetchBatchSize = 100
        fetchRequest.propertiesToFetch = [
            Predicate.Key.rawNextBackupUUID.rawValue,
            Predicate.Key.rawOwnedIdentity.rawValue,
        ]
        let items: [PersistedProfileBackupThreadId]
        do {
            items = try context.fetch(fetchRequest)
        } catch {
            throw .coreDataError(error)
        }
        return items.compactMap { profile in
            guard let ownedCryptoId = try? profile.ownedCryptoId else {
                assertionFailure()
                return nil
            }
            guard let uuid = profile.rawNextBackupUUID else {
                return nil
            }
            return (ownedCryptoId, uuid)
        }
    }

}
