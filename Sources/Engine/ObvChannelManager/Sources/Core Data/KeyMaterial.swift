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
import ObvMetaManager
import ObvTypes
import ObvEncoder
import ObvCrypto
import OlvidUtils

@objc(KeyMaterial)
final class KeyMaterial: NSManagedObject {

    // MARK: Internal constants
    
    private static let entityName = "KeyMaterial"
    private static let logger = Logger(subsystem: "io.olvid.channel", category: "KeyMaterial")

    // MARK: Attributes
    
    @NSManaged private var encodedKey: Data? // Non-optional in the model
    @NSManaged private(set) var expirationTimestamp: Date? // Optional in the model
    @NSManaged private var rawCryptoKeyId: Data? // Non-optional in the model
    @NSManaged private(set) var selfRatchetingCount: Int

    // MARK: Relationships
    
    @NSManaged private(set) var provision: Provision? // Non-optional in the model

    // MARK: Accessors
    
    private var cryptoKeyId: CryptoKeyId {
        get throws {
            guard let rawCryptoKeyId else { assertionFailure(); throw ObvError.unexpectedNilValue  }
            guard let cryptoKeyId = CryptoKeyId(rawCryptoKeyId) else { assertionFailure(); throw ObvError.unexpectedNilValue }
            return cryptoKeyId
        }
    }


    var key: AuthenticatedEncryptionKey {
        get throws {
            guard let encodedKey else { assertionFailure(); throw ObvError.unexpectedNilValue  }
            guard let encodedKey = ObvEncoded(withRawData: encodedKey) else { assertionFailure(); throw ObvError.unexpectedNilValue  }
            return try AuthenticatedEncryptionKeyDecoder.decode(encodedKey)
        }
    }
    
    
    enum ObvError: Error {
        case unexpectedNilValue
        case noContext
    }
    
    // MARK: - Initializer
    
    convenience init(cryptoKeyId: CryptoKeyId, key: AuthenticatedEncryptionKey, selfRatchetingCount: Int, provision: Provision, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: KeyMaterial.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.encodedKey = key.obvEncode().rawData
        self.expirationTimestamp = nil
        self.rawCryptoKeyId = cryptoKeyId.raw
        self.selfRatchetingCount = selfRatchetingCount
        self.provision = provision
    }

}


// MARK: - Helper methods

extension KeyMaterial {
            
    /// This methods looks for provisioned keys that are:
    /// - with the same provision than `self` but older in terms of `selfRatchetingCount`
    /// - in older provisions than `self`
    /// - not yet expiring, i.e., such that `expirationTimestamp` is nil
    ///
    /// - Returns: A set of all the provisions that had at least one key material marked for expiration
    func setExpirationTimestampOfOlderButNotYetExpiringProvisionedReceiveKeys() throws {
        
        let expirationTimestampForOldKeys = Date.now.addingTimeInterval(ObvConstants.expirationTimeIntervalOfProvisionedKey)
        let olderButNotYetExpiringProvisionedKeys = try KeyMaterial.getAllNotYetExpiring(olderThan: self)
        
        Self.logger.debug("🔑 Number of older but not yet expiring provisioned keys: \(olderButNotYetExpiringProvisionedKeys.count)")
        
        for provisionedKey in olderButNotYetExpiringProvisionedKeys {
            provisionedKey.expirationTimestamp = expirationTimestampForOldKeys
        }
        
    }
    
    /// Given a seed, this function computes a new seed, a crypto key id and an authenticated encryption key. This method is used to self-ratchet a provision (i.e., when computing a new receive key) and to self ratchet the send key of an Oblivious channel.
    ///
    /// - Parameters:
    ///   - seed: The initial seed value.
    ///   - cryptoSuiteVersion: The version of the ObvCrypto suite to use for the prng and for the authenticated encryption.
    /// - Returns: The next value of the seed, the crypto key id, and the authenticated encryption key.
    static func selfRatchet(seed: Seed, usingCryptoSuiteVersion cryptoSuiteVersion: Int) throws -> (Seed, CryptoKeyId, AuthenticatedEncryptionKey) {
        guard let prngClass = ObvCryptoSuite.sharedInstance.concretePRNG(forSuiteVersion: cryptoSuiteVersion) else {
            assertionFailure()
            throw ObvError.unexpectedNilValue
        }
        let prng = prngClass.init(with: seed)
        let nextSeed = prng.genSeed()
        let cryptoKeyId = CryptoKeyId(prng.genBytes(count: CryptoKeyId.length))!
        guard let authEncClass = ObvCryptoSuite.sharedInstance.authenticatedEncryption(forSuiteVersion: cryptoSuiteVersion) else {
            assertionFailure()
            throw ObvError.unexpectedNilValue
        }
        let key = authEncClass.generateKey(with: prng)
        return (nextSeed, cryptoKeyId, key)
    }
    
    
    func deleteKeyMaterial() throws {
        guard let context = self.managedObjectContext else { assertionFailure(); throw ObvError.unexpectedNilValue }
        context.delete(self)
    }
    
}

// MARK: Convenience DB getters
extension KeyMaterial {
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case encodedKey = "encodedKey" // Data
            case expirationTimestamp = "expirationTimestamp" // Date
            case rawCryptoKeyId = "rawCryptoKeyId" // Data
            case selfRatchetingCount = "selfRatchetingCount" // Int
            // Relationships
            case provision = "provision" // Provision
        }
        static func withCryptoKeyId(_ cryptoKeyId: CryptoKeyId) -> NSPredicate {
            NSPredicate(Key.rawCryptoKeyId, EqualToData: cryptoKeyId.raw)
        }
        static func withCurrentDeviceUid(_ currentDeviceUID: UID) -> NSPredicate {
            let predicateKey: String = [
                Key.provision.rawValue,
                Provision.Predicate.Key.obliviousChannel.rawValue,
                ObvObliviousChannel.Predicate.Key.rawCurrentDeviceUID.rawValue,
            ].joined(separator: ".")
            return NSPredicate(predicateKey, EqualToData: currentDeviceUID.raw)
        }
        static func withProvision(_ provision: Provision) -> NSPredicate {
            NSPredicate(Key.provision, equalTo: provision)
        }
        static func withObvObliviousChannel(_ channel: ObvObliviousChannel) -> NSPredicate {
            let predicateKey: String = [
                Key.provision.rawValue,
                Provision.Predicate.Key.obliviousChannel.rawValue,
            ].joined(separator: ".")
            return NSPredicate(predicateKey, equalTo: channel)
        }
        static func withSelfRatchetingCountLessThan(_ selfRatchetingCount: Int) -> NSPredicate {
            NSPredicate(Key.selfRatchetingCount, LessThanInt: selfRatchetingCount)
        }
        static func withFullRatchetingCountLessThan(_ fullRatchetingCount: Int) -> NSPredicate {
            let predicateKey: String = [
                Predicate.Key.provision.rawValue,
                Provision.Predicate.Key.fullRatchetingCount.rawValue,
            ].joined(separator: ".")
            return NSPredicate(predicateKey, LessThanInt: fullRatchetingCount)
        }
        static var withNoExpirationTimestamp: NSPredicate {
            NSPredicate(withNilValueForKey: Key.expirationTimestamp)
        }
        static func withExpirationTimestampEarlierThan(_ date: Date) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(withNonNilValueForKey: Key.expirationTimestamp),
                NSPredicate(Key.expirationTimestamp, earlierThan: date),
            ])
        }
    }
    
    @nonobjc private static func fetchRequest() -> NSFetchRequest<KeyMaterial> {
        return NSFetchRequest<KeyMaterial>(entityName: KeyMaterial.entityName)
    }

    
    static func getAll(cryptoKeyId: CryptoKeyId, currentDeviceUID: UID, within context: NSManagedObjectContext) throws -> [KeyMaterial] {
        let request: NSFetchRequest<KeyMaterial> = KeyMaterial.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withCryptoKeyId(cryptoKeyId),
            Predicate.withCurrentDeviceUid(currentDeviceUID),
        ])
        let items = try context.fetch(request)
        return items
    }
    
    
    private static func getAllNotYetExpiring(olderThan provisionedKey: KeyMaterial) throws -> [KeyMaterial] {
        guard let context = provisionedKey.managedObjectContext else {
            assertionFailure()
            throw ObvError.noContext
        }
        let request: NSFetchRequest<KeyMaterial> = KeyMaterial.fetchRequest()
        request.fetchBatchSize = 100
        request.propertiesToFetch = []
        var predicates = [NSPredicate]()
        
        // We look for provisioned keys within the same provision, but with a smaller self ratcheting count
        guard let provisionedKeyProvision = provisionedKey.provision,
              let provisionedKeyChannel = provisionedKeyProvision.obliviousChannel else {
            assertionFailure()
            throw ObvError.unexpectedNilValue
        }
        predicates.append(NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withProvision(provisionedKeyProvision),
            Predicate.withSelfRatchetingCountLessThan(provisionedKey.selfRatchetingCount),
            Predicate.withNoExpirationTimestamp,
        ]))

        // We also look for all provisioned keys within the older provisions of the same oblivious channel
        predicates.append(NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withObvObliviousChannel(provisionedKeyChannel),
            Predicate.withFullRatchetingCountLessThan(provisionedKeyProvision.fullRatchetingCount),
            Predicate.withNoExpirationTimestamp,
        ]))

        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        let items = try context.fetch(request)
        return items
    }
    
    
    static func countNotExpiringProvisionedReceiveKey(within provision: Provision) throws -> Int {
        guard let context = provision.managedObjectContext else {
            throw ObvError.noContext
        }
        let request: NSFetchRequest<KeyMaterial> = KeyMaterial.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withProvision(provision),
            Predicate.withNoExpirationTimestamp,
        ])
        return try context.count(for: request)
    }
    
    
    /// Delete all the expired key materials. We cannot use batch delete due to the DB schema.
    static func deleteAllExpired(before date: Date, within context: NSManagedObjectContext) throws {
        let fetchRequest = NSFetchRequest<KeyMaterial>(entityName: KeyMaterial.entityName)
        fetchRequest.predicate = Predicate.withExpirationTimestampEarlierThan(date)
        fetchRequest.fetchBatchSize = 1_000
        let expiredKeys = try context.fetch(fetchRequest)
        for key in expiredKeys {
            try key.deleteKeyMaterial()
        }
    }
}
