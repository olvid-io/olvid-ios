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

@objc(Provision)
final class Provision: NSManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "Provision"
    private static let logger = Logger(subsystem: "io.olvid.channel", category: "Provision")

    // MARK: Attributes
    
    // The full ratcheting count uniquely identifies this provision within an oblivious channel
    // Part of primary key (with `obliviousChannel`)
    @NSManaged private(set) var fullRatchetingCount: Int
    
    // The self ratcheting count is the number of times this provision was self ratcheted. In other words, this is the total number ok keys created within this provision. This value is used when self ratcheting this provision in order to know the selfRatchetingCount of each new key.
    @NSManaged private(set) var selfRatchetingCount: Int
    
    
    // Used to compute the next provisioned receive key
    @NSManaged private(set) var rawSeedForNextProvisionedReceiveKey: Data? // Non-nil in the model
    
    // Used to determine which prng to use (to generate the next seed, the encryption key, and the crypto key id) as well as which authenticated encryption algorithm to use
    @NSManaged private(set) var cryptoSuiteVersion: Int // Always 0, for now
    
    // MARK: Relationships
    
    // The oblivious channel this provision belongs to. Should be non-optional in the model, but it must be optional due to the uniqueness constraints.
    // Part of the primary key (with fullRatchetingCount)
    @NSManaged private(set) var obliviousChannel: ObvObliviousChannel?

    // The set of all provisioned receive keys within this provision.
    @NSManaged private(set) var receiveKeys: Set<KeyMaterial>
    
    // MARK: Accessors
    
    private var seedForNextProvisionedReceiveKey: Seed {
        get throws(ObvError) {
            guard let rawSeedForNextProvisionedReceiveKey else { assertionFailure(); throw .unexpectedNilValue }
            guard let seed = Seed(with: rawSeedForNextProvisionedReceiveKey) else { assertionFailure(); throw .unexpectedNilValue }
            return seed
        }
    }

    
    // MARK: - Initializer
    
    convenience init(fullRatchetingCount: Int, obliviousChannel: ObvObliviousChannel, seedForNextProvisionedReceiveKey: Seed) throws {
        
        guard let context = obliviousChannel.managedObjectContext else { assertionFailure(); throw ObvError.noContext }

        guard try !Provision.exists(obliviousChannel: obliviousChannel, fullRatchetingCount: fullRatchetingCount) else { assertionFailure(); throw ObvError.provisionAlreadyExists }

        let entityDescription = NSEntityDescription.entity(forEntityName: Provision.entityName, in: context)!

        self.init(entity: entityDescription, insertInto: context)

        self.cryptoSuiteVersion = 0
        self.fullRatchetingCount = fullRatchetingCount
        self.rawSeedForNextProvisionedReceiveKey = seedForNextProvisionedReceiveKey.raw
        self.selfRatchetingCount = 0

        self.obliviousChannel = obliviousChannel
        self.receiveKeys = Set<KeyMaterial>()
        // At this point, this provision has no receive key material, so we self-ratchet it
        try selfRatchet(count: 2*ObvConstants.reprovisioningThreshold)

    }
    
    enum ObvError: Error {
        case noContext
        case provisionAlreadyExists
        case unexpectedNilValue
    }
 
}


// MARK: - Helper functions

extension Provision {
    
    func countNotExpiringReceiveKeys() throws -> Int {
        return try KeyMaterial.countNotExpiringProvisionedReceiveKey(within: self)
    }
        
    
    private func selfRatchet(count: Int) throws {
        guard let context = self.managedObjectContext else { assertionFailure(); throw ObvError.noContext }
        for _ in 0..<count {
            let (ratchetedSeed, keyId, key) = try KeyMaterial.selfRatchet(
                seed: seedForNextProvisionedReceiveKey,
                usingCryptoSuiteVersion: cryptoSuiteVersion)
            self.rawSeedForNextProvisionedReceiveKey = ratchetedSeed.raw
            _ = KeyMaterial(cryptoKeyId: keyId,
                            key: key,
                            selfRatchetingCount: selfRatchetingCount,
                            provision: self,
                            within: context)
            selfRatchetingCount += 1
        }
    }
    
    
    func selfRatchetIfRequired() throws {
        let numberOfNotExpiringReceiveKeysWithinProvision = try countNotExpiringReceiveKeys()
        if numberOfNotExpiringReceiveKeysWithinProvision < ObvConstants.reprovisioningThreshold {
            Self.logger.info("Self Ratcheting a Provision")
            try selfRatchet(count: ObvConstants.reprovisioningThreshold)
        } else {
            Self.logger.info("No need to self ratchet the provision (\(numberOfNotExpiringReceiveKeysWithinProvision) >= \(ObvConstants.reprovisioningThreshold))")
        }
    }
}


// MARK: - Convenience DB getters

extension Provision {
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case cryptoSuiteVersion = "cryptoSuiteVersion"
            case fullRatchetingCount = "fullRatchetingCount"
            case rawSeedForNextProvisionedReceiveKey = "rawSeedForNextProvisionedReceiveKey"
            case selfRatchetingCount = "selfRatchetingCount"
            // Relationships
            case obliviousChannel = "obliviousChannel"
            case receiveKeys = "receiveKeys"
        }
        static var withZeroReceiveKeys: NSPredicate {
            NSPredicate(withZeroCountForKey: Key.receiveKeys)
        }
        static func withObvObliviousChannel(_ obliviousChannel: ObvObliviousChannel) -> NSPredicate {
            NSPredicate(Key.obliviousChannel, equalTo: obliviousChannel)
        }
        static func withFullRatchetingCount(_ fullRatchetingCount: Int) -> NSPredicate {
            NSPredicate(Key.fullRatchetingCount, EqualToInt: fullRatchetingCount)
        }
        static func withPrimaryKey(_ obliviousChannel: ObvObliviousChannel, _ fullRatchetingCount: Int) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withObvObliviousChannel(obliviousChannel),
                withFullRatchetingCount(fullRatchetingCount),
            ])
        }
    }
    
    // MARK: Fetch request
    
    @nonobjc private static func fetchRequest() -> NSFetchRequest<Provision> {
        return NSFetchRequest<Provision>(entityName: Provision.entityName)
    }

    
    /// This type method deletes all the `Provision` that have an empty set of keys.
    static func deleteAllEmpty(within context: NSManagedObjectContext) throws {
        let fetchRequest = NSFetchRequest<Provision>(entityName: Provision.entityName)
        fetchRequest.predicate = Predicate.withZeroReceiveKeys
        fetchRequest.fetchBatchSize = 1_000
        fetchRequest.propertiesToFetch = []
        let emptyProvisions = try context.fetch(fetchRequest)
        for provision in emptyProvisions {
            context.delete(provision)
        }
    }

    
    /// The primary key of a Provision is (`obliviousChannel`, `fullRatchetingCount`). This method allows the initializer to ensure that there is at most one such provision.
    ///
    /// - Parameters:
    ///   - obliviousChannel: The `ObvObliviousChannel` to which this provision belongs.
    ///   - fullRatchetingCount: The incremental number of this provision.
    /// - Returns: `true` if such a provision already exist, false otherwise.
    /// - Throws: An error the count request fails
    private static func exists(obliviousChannel: ObvObliviousChannel, fullRatchetingCount: Int) throws -> Bool {
        guard let context = obliviousChannel.managedObjectContext else { assertionFailure(); throw ObvError.noContext }
        let request: NSFetchRequest<Provision> = Provision.fetchRequest()
        request.predicate = Predicate.withPrimaryKey(obliviousChannel, fullRatchetingCount)
        request.fetchLimit = 1
        let results = try context.fetch(request).first
        return results != nil
    }

}
