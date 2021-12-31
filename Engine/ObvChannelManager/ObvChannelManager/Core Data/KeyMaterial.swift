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
import CoreData
import os.log
import ObvMetaManager
import ObvTypes
import ObvEncoder
import ObvCrypto
import OlvidUtils

@objc(KeyMaterial)
class KeyMaterial: NSManagedObject, ObvManagedObject {

    // MARK: Internal constants
    
    private static let entityName = "KeyMaterial"
    private static let cryptoKeyIdKey = "cryptoKeyId"
    private static let encodedKeyKey = "encodedKey"
    private static let selfRatchetingCountKey = "selfRatchetingCount"
    private static let expirationTimestampKey = "expirationTimestamp"
    private static let provisionKey = "provision"
    private static let provisionObliviousChannelKey = provisionKey + "." + Provision.obliviousChannelKey
    private static let provisionFullRatchetingCountKey = provisionKey + "." + Provision.fullRatchetingCountKey
    private static let provisionObliviousChannelCurrentDeviceUidKey = provisionObliviousChannelKey + "." + ObvObliviousChannel.currentDeviceUidKey
    
    private static let errorDomain = "KeyMaterial"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    // MARK: Attributes
    
    private var cryptoKeyId: CryptoKeyId {
        get {
            let rawCryptoKeyId = kvoSafePrimitiveValue(forKey: KeyMaterial.cryptoKeyIdKey) as! Data
            return CryptoKeyId(rawCryptoKeyId)!
        }
        set {
            kvoSafeSetPrimitiveValue(newValue.raw, forKey: KeyMaterial.cryptoKeyIdKey)
        }
    }
    private(set) var key: AuthenticatedEncryptionKey {
        get {
            let encodedKeyData = kvoSafePrimitiveValue(forKey: KeyMaterial.encodedKeyKey) as! Data
            let encodedKey = ObvEncoded(withRawData: encodedKeyData)!
            return try! AuthenticatedEncryptionKeyDecoder.decode(encodedKey)
        }
        set {
            let encodedKey = newValue.encode()
            kvoSafeSetPrimitiveValue(encodedKey.rawData, forKey: KeyMaterial.encodedKeyKey)
        }
    }
    @NSManaged var expirationTimestamp: Date?
    @NSManaged private(set) var selfRatchetingCount: Int
    
    // MARK: Relationships
    
    private(set) var provision: Provision {
        get {
            let value = kvoSafePrimitiveValue(forKey: KeyMaterial.provisionKey) as! Provision
            value.obvContext = self.obvContext
            return value
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: KeyMaterial.provisionKey)
        }
    }
    
    // MARK: Other variables
    
    weak static var delegateManager: ObvChannelDelegateManager!
    var obvContext: ObvContext?

    // MARK: - Initializer
    
    convenience init(cryptoKeyId: CryptoKeyId, key: AuthenticatedEncryptionKey, selfRatchetingCount: Int, provision: Provision, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: KeyMaterial.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.cryptoKeyId = cryptoKeyId
        self.key = key
        self.expirationTimestamp = nil
        self.selfRatchetingCount = selfRatchetingCount
        self.provision = provision
    }

}


// MARK: - Fetch request

extension KeyMaterial {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<KeyMaterial> {
        return NSFetchRequest<KeyMaterial>(entityName: KeyMaterial.entityName)
    }
    
    // MARK: Helper methods
    
    /// This methods looks for provisioned keys that are:
    /// - with the same provision than `self` but older in terms of `selfRatchetingCount`
    /// - in older provisions than `self`
    /// - not yet expiring, i.e., such that `expirationTimestamp` is nil
    ///
    /// - Returns: A set of all the provisions that had at least one key material marked for expiration
    func setExpirationTimestampOfOlderButNotYetExpiringProvisionedReceiveKeys() throws {
        let expirationTimestampForOldKeys = Date().addingTimeInterval(ObvConstants.expirationTimeIntervalOfProvisionedKey)
        let olderButNotYetExpiringProvisionedKeys = try KeyMaterial.getAllNotYetExpiring(olderThan: self)
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
    static func selfRatchet(seed: Seed, usingCryptoSuiteVersion cryptoSuiteVersion: Int) -> (Seed, CryptoKeyId, AuthenticatedEncryptionKey)? {
        guard let prngClass = ObvCryptoSuite.sharedInstance.concretePRNG(forSuiteVersion: cryptoSuiteVersion) else { return nil }
        let prng = prngClass.init(with: seed)
        let nextSeed = prng.genSeed()
        let cryptoKeyId = CryptoKeyId(prng.genBytes(count: CryptoKeyId.length))!
        guard let authEncClass = ObvCryptoSuite.sharedInstance.authenticatedEncryption(forSuiteVersion: cryptoSuiteVersion) else { return nil }
        let key = authEncClass.generateKey(with: prng)
        return (nextSeed, cryptoKeyId, key)
    }
    
}

// MARK: Convenience DB getters
extension KeyMaterial {
    
    class func getAll(cryptoKeyId: CryptoKeyId, currentDeviceUid: UID, within obvContext: ObvContext) throws -> [KeyMaterial] {
        let request: NSFetchRequest<KeyMaterial> = KeyMaterial.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        KeyMaterial.cryptoKeyIdKey, cryptoKeyId.raw as NSData,
                                        KeyMaterial.provisionObliviousChannelCurrentDeviceUidKey, currentDeviceUid)
        let items = try obvContext.fetch(request)
        _ = items.map { $0.obvContext = obvContext }
        return items
    }
    
    private class func getAllNotYetExpiring(olderThan provisionedKey: KeyMaterial) throws -> [KeyMaterial] {
        guard let obvContext = provisionedKey.obvContext else {
            throw KeyMaterial.makeError(message: "Cannot set obvContext")
        }
        let request: NSFetchRequest<KeyMaterial> = KeyMaterial.fetchRequest()
        var predicates = [NSPredicate]()
        
        // We look for provisioned keys within the same provision, but with a smaller self ratcheting count
        predicates.append(NSPredicate(format: "%K == %@ AND %K < %d AND %K == nil",
                                      KeyMaterial.provisionKey, provisionedKey.provision,
                                      KeyMaterial.selfRatchetingCountKey, provisionedKey.selfRatchetingCount,
                                      KeyMaterial.expirationTimestampKey))

        // We also look for all provisioned keys within the older provisions of the same oblivious channel
        predicates.append(NSPredicate(format: "%K == %@ AND %K < %d AND %K == nil",
                                      KeyMaterial.provisionObliviousChannelKey, provisionedKey.provision.obliviousChannel,
                                      KeyMaterial.provisionFullRatchetingCountKey, provisionedKey.provision.fullRatchetingCount,
                                      KeyMaterial.expirationTimestampKey))

        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        let items = try obvContext.fetch(request)
        _ = items.map { $0.obvContext = obvContext }
        return items
    }
    
    class func countNotExpiringProvisionedReceiveKey(within provision: Provision) throws -> Int {
        guard let context = provision.managedObjectContext else {
            throw KeyMaterial.makeError(message: "Cannot find context")
        }
        let request: NSFetchRequest<KeyMaterial> = KeyMaterial.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == NIL",
                                        KeyMaterial.provisionKey, provision,
                                        KeyMaterial.expirationTimestampKey)
        return try context.count(for: request)
    }
    
    /// Delete all the expired key materials. We cannot use batch delete due to the DB schema.
    class func deleteAllExpired(before date: Date, within obvContext: ObvContext) throws {
        let fetchRequest = NSFetchRequest<KeyMaterial>(entityName: KeyMaterial.entityName)
        let predicates = [
            NSPredicate(format: "%K != nil", KeyMaterial.expirationTimestampKey),
            NSPredicate(format: "%K < %@", KeyMaterial.expirationTimestampKey, date as NSDate),
        ]
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        fetchRequest.fetchBatchSize = 1_000
        let expiredKeys = try obvContext.fetch(fetchRequest)
        for key in expiredKeys {
            obvContext.delete(key)
        }
    }
}
