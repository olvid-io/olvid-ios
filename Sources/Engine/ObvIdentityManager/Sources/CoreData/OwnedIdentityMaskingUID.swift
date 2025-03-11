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
import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils

@objc(OwnedIdentityMaskingUID)
final class OwnedIdentityMaskingUID: NSManagedObject, ObvManagedObject, ObvErrorMaker {
    
    // MARK: Internal constants
    
    private static let entityName = "OwnedIdentityMaskingUID"
    private static let ownedIdentityKey = "ownedIdentity"
    private static let maskingUIDKey = "maskingUID"
    
    internal static let errorDomain = "OwnedIdentityMaskingUID"
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { NSError(domain: OwnedIdentityMaskingUID.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    // MARK: Attributes
    
    @NSManaged private(set) var maskingUID: UID
    
    // MARK: Relationships
    
    private(set) var ownedIdentity: OwnedIdentity {
        get {
            let item = kvoSafePrimitiveValue(forKey: OwnedIdentityMaskingUID.ownedIdentityKey) as! OwnedIdentity
            item.obvContext = self.obvContext
            return item
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: OwnedIdentityMaskingUID.ownedIdentityKey)
        }
    }
    
    // MARK: Other variables
    
    weak var obvContext: ObvContext?
    
    // MARK: - Initializer
    
    private convenience init(ownedIdentity: OwnedIdentity, pushToken: Data) throws {
        guard let obvContext = ownedIdentity.obvContext else { throw OwnedIdentityMaskingUID.makeError(message: "Coud not find ObvContext within the owned identity instance (1)") }
        let entityDescription = NSEntityDescription.entity(forEntityName: OwnedIdentityMaskingUID.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.maskingUID = try Self.generateDeterministricUID(ownedCryptoId: ownedIdentity.cryptoIdentity, pushToken: pushToken)
        self.ownedIdentity = ownedIdentity
    }
    
}

// MARK: - Other methods

extension OwnedIdentityMaskingUID {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<OwnedIdentityMaskingUID> {
        return NSFetchRequest<OwnedIdentityMaskingUID>(entityName: entityName)
    }
    

    static func getOrCreate(for ownedIdentity: OwnedIdentity, pushToken: Data) throws -> UID {
        
        guard let obvContext = ownedIdentity.obvContext else { throw makeError(message: "Could not find ObvContext within the owned identity instance") }
        
        let request: NSFetchRequest<OwnedIdentityMaskingUID> = OwnedIdentityMaskingUID.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", ownedIdentityKey, ownedIdentity)
        request.fetchLimit = 1
        let item: OwnedIdentityMaskingUID
        if let _item = try obvContext.fetch(request).first {
            let newMaskingUID = try generateDeterministricUID(ownedCryptoId: ownedIdentity.cryptoIdentity, pushToken: pushToken)
            if _item.maskingUID != newMaskingUID {
                _item.maskingUID = newMaskingUID
            }
            item = _item
        } else {
            item = try .init(ownedIdentity: ownedIdentity, pushToken: pushToken)
        }
        return item.maskingUID
    }
    
    
    static func getOwnedIdentityAssociatedWithMaskingUID(_ maskingUID: UID, within obvContext: ObvContext) throws -> OwnedIdentity? {
        let request: NSFetchRequest<OwnedIdentityMaskingUID> = OwnedIdentityMaskingUID.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", maskingUIDKey, maskingUID)
        request.fetchLimit = 1
        let item = try obvContext.fetch(request).first
        return item?.ownedIdentity
    }
    
    
    private static func generateDeterministricUID(ownedCryptoId: ObvCryptoIdentity, pushToken: Data) throws -> UID {
        let seedData = Data([ownedCryptoId.getIdentity(), pushToken].joined())
        guard let seed = Seed(with: seedData) else { assertionFailure(); throw Self.makeError(message: "Could not generate seed")}
        let prng = ObvCryptoSuite.sharedInstance.concretePRNG().init(with: seed)
        return UID.gen(with: prng)
    }
    

}
