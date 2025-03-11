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
import os.log
import ObvMetaManager
import ObvTypes
import ObvEncoder
import ObvCrypto
import OlvidUtils

@objc(Provision)
class Provision: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "Provision"
    static let obliviousChannelKey = "obliviousChannel"
    static let fullRatchetingCountKey = "fullRatchetingCount"
    private static let receiveKeysKey = "receiveKeys"
    private static let obliviousChannelCurrentDeviceUidKey = [obliviousChannelKey, ObvObliviousChannel.currentDeviceUidKey].joined(separator: ".")
    private static let obliviousChannelRemoteCryptoIdentityKey = [obliviousChannelKey, ObvObliviousChannel.remoteCryptoIdentityKey].joined(separator: ".")
    private static let obliviousChannelRemoteDeviceUidKey = [obliviousChannelKey, ObvObliviousChannel.remoteDeviceUidKey].joined(separator: ".")

    // MARK: Attributes
    
    // The full ratcheting count uniquely identifies this provision within an oblivious channel
    // Part of primary key (with `obliviousChannel`)
    @NSManaged private(set) var fullRatchetingCount: Int
    
    // The self ratcheting count is the number of times this provision was self ratcheted. In other words, this is the total number ok keys created within this provision. This value is used when self ratcheting this provision in order to know the selfRatchetingCount of each new key.
    @NSManaged private(set) var selfRatchetingCount: Int
    
    
    // Used to compute the next provisioned receive key
    @NSManaged private(set) var seedForNextProvisionedReceiveKey: Seed
    
    // Used to determine which prng to use (to generate the next seed, the encryption key, and the crypto key id) as well as which authenticated encryption algorithm to use
    @NSManaged private(set) var cryptoSuiteVersion: Int // Always 0, for now
    
    // MARK: Relationships
    
    // The oblivious channel this provision belongs to
    // Part of primary key (with `fullRatchetingCount`)
    private(set) var obliviousChannel: ObvObliviousChannel {
        get {
            let value = kvoSafePrimitiveValue(forKey: Provision.obliviousChannelKey) as! ObvObliviousChannel
            value.obvContext = self.obvContext
            return value
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: Provision.obliviousChannelKey)
        }
    }

    // The set of all provisioned receive keys within this provision
    private(set) var receiveKeys: Set<KeyMaterial> {
        get {
            let values = kvoSafePrimitiveValue(forKey: Provision.receiveKeysKey) as! Set<KeyMaterial>
            return Set(values.map { $0.obvContext = self.obvContext; return $0})
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: Provision.receiveKeysKey)
        }
    }

    
    // MARK: Other variables
    
    weak static var delegateManager: ObvChannelDelegateManager!
    weak var obvContext: ObvContext?

    static func makeError(message: String) -> Error { NSError(domain: "Provision", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    // MARK: - Initializer
    
    convenience init?(fullRatchetingCount: Int, obliviousChannel: ObvObliviousChannel, seedForNextProvisionedReceiveKey: Seed) {
        let log = OSLog.init(subsystem: Provision.delegateManager.logSubsystem, category: Provision.entityName)
        guard let obvContext = obliviousChannel.obvContext else { return nil }
        do {
            guard try !Provision.exists(obliviousChannel: obliviousChannel, fullRatchetingCount: fullRatchetingCount) else { return nil }
        } catch let error {
            os_log("%@", log: log, type: .error, error.localizedDescription)
        }
        let entityDescription = NSEntityDescription.entity(forEntityName: Provision.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.fullRatchetingCount = fullRatchetingCount
        self.selfRatchetingCount = 0
        self.obliviousChannel = obliviousChannel
        self.receiveKeys = Set<KeyMaterial>()
        self.seedForNextProvisionedReceiveKey = seedForNextProvisionedReceiveKey
        self.cryptoSuiteVersion = 0
        // At this point, this provision has no receive key material, so we self-ratchet it
        selfRatchet(count: 2*ObvConstants.reprovisioningThreshold)
    }
 
    
}


// MARK: - Helper functions

extension Provision {
    
    func countNotExpiringReceiveKeys() throws -> Int {
        return try KeyMaterial.countNotExpiringProvisionedReceiveKey(within: self)
    }
        
    private func selfRatchet(count: Int) {
        assert(self.obvContext != nil, "We do not expect the obvContext to be nil")
        let obvContext = self.obvContext!
        for _ in 0..<count {
            let (ratchetedSeed, keyId, key) = KeyMaterial.selfRatchet(seed: seedForNextProvisionedReceiveKey,
                                                                      usingCryptoSuiteVersion: cryptoSuiteVersion)!
            seedForNextProvisionedReceiveKey = ratchetedSeed
            _ = KeyMaterial(cryptoKeyId: keyId,
                            key: key,
                            selfRatchetingCount: selfRatchetingCount,
                            provision: self,
                            within: obvContext)
            selfRatchetingCount += 1
        }
    }
    
    func selfRatchetIfRequired() throws {
        let numberOfNotExpiringReceiveKeysWithinProvision = try countNotExpiringReceiveKeys()
        let log = OSLog(subsystem: Provision.delegateManager.logSubsystem, category: Provision.entityName)
        if numberOfNotExpiringReceiveKeysWithinProvision < ObvConstants.reprovisioningThreshold {
            os_log("Self Ratcheting a Provision", log: log, type: .info)
            selfRatchet(count: ObvConstants.reprovisioningThreshold)
        } else {
            os_log("No need to self ratchet the provision (%d >= %d)", log: log, type: .info, numberOfNotExpiringReceiveKeysWithinProvision, ObvConstants.reprovisioningThreshold)
        }
    }
}


// MARK: - Convenience DB getters

extension Provision {
    
    // MARK: Fetch request
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<Provision> {
        return NSFetchRequest<Provision>(entityName: Provision.entityName)
    }

    
    /// This type method deletes all the `Provision` that have an empty set of keys.
    static func deleteAllEmpty(within obvContext: ObvContext) throws {
        let fetchRequest = NSFetchRequest<Provision>(entityName: Provision.entityName)
        fetchRequest.predicate = NSPredicate(format: "%K.@count == 0", Provision.receiveKeysKey)
        fetchRequest.fetchBatchSize = 1_000
        let emptyProvisions = try obvContext.fetch(fetchRequest)
        for provision in emptyProvisions {
            obvContext.delete(provision)
        }
    }

    /// The primart key of a Provision is (`obliviousChannel`, `fullRatchetingCount`). This method allows the initializer to ensure that there is at most one such provision.
    ///
    /// - Parameters:
    ///   - obliviousChannel: The `ObvObliviousChannel` to which this provision belongs.
    ///   - fullRatchetingCount: The incremental number of this provision.
    ///   - context:
    /// - Returns: `true` if such a provision already exist, false otherwise.
    /// - Throws: An error the count request fails
    static func exists(obliviousChannel: ObvObliviousChannel, fullRatchetingCount: Int) throws -> Bool {
        guard let obvContext = obliviousChannel.obvContext else {
            throw Self.makeError(message: "obliviousChannel has not obvContext")
        }
        let request: NSFetchRequest<Provision> = Provision.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %@ AND %K == %d",
                                        obliviousChannelCurrentDeviceUidKey, obliviousChannel.currentDeviceUid,
                                        obliviousChannelRemoteCryptoIdentityKey, obliviousChannel.remoteCryptoIdentity,
                                        obliviousChannelRemoteDeviceUidKey, obliviousChannel.remoteDeviceUid,
                                        fullRatchetingCountKey, fullRatchetingCount)
        return try obvContext.count(for: request) != 0
    }
    
}
