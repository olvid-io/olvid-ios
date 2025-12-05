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
import ObvMetaManager
import OlvidUtils

@objc(OwnedIdentityMaskingUID)
final class OwnedIdentityMaskingUID: NSManagedObject, ObvErrorMaker {
    
    // MARK: Internal constants
    
    private static let entityName = "OwnedIdentityMaskingUID"
    
    static weak var delegateManager: ObvIdentityDelegateManager?
    
    internal static let errorDomain = "OwnedIdentityMaskingUID"
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { NSError(domain: OwnedIdentityMaskingUID.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    private static var logSubsystem: String { delegateManager?.logSubsystem ?? ObvIdentityDelegateManager.defaultLogSubsystem }
    private static var logger: Logger = { Logger(subsystem: OwnedIdentityMaskingUID.logSubsystem, category: "OwnedIdentityMaskingUID") }()

    // MARK: Attributes
    
    @NSManaged private var rawMaskingUID: Data? // Non-optional in the model
    
    // MARK: Relationships
    
    @NSManaged private(set) var ownedIdentity: OwnedIdentity
    
    // MARK: Other variables
    
    private var maskingUID: UID {
        get throws(ObvError) {
            guard let rawMaskingUID else { assertionFailure(); throw .unexpectedNilValue }
            guard let maskingUID = UID(uid: rawMaskingUID) else { assertionFailure(); throw .couldNotParseValue }
            return maskingUID
        }
    }
        
    // MARK: - Initializer
    
    private convenience init(ownedIdentity: OwnedIdentity, pushToken: Data) throws {
        guard let context = ownedIdentity.managedObjectContext else { throw OwnedIdentityMaskingUID.makeError(message: "Coud not find context within the owned identity instance (1)") }
        let entityDescription = NSEntityDescription.entity(forEntityName: OwnedIdentityMaskingUID.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.rawMaskingUID = try Self.generateDeterministricUID(ownedCryptoId: ownedIdentity.cryptoIdentity, pushToken: pushToken).raw
        self.ownedIdentity = ownedIdentity
    }
    
    enum ObvError: Error {
        case unexpectedNilValue
        case couldNotParseValue
    }
    
}

// MARK: - Other methods

extension OwnedIdentityMaskingUID {
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case rawMaskingUID = "rawMaskingUID"
            // Relationships
            case ownedIdentity = "ownedIdentity"
        }
        static func withOwnedIdentity(_ ownedIdentity: OwnedIdentity) -> NSPredicate {
            NSPredicate(Key.ownedIdentity, equalTo: ownedIdentity)
        }
        static func withMaskingUID(_ maskingUID: UID) -> NSPredicate {
            NSPredicate(Key.rawMaskingUID, EqualToData: maskingUID.raw)
        }
    }
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<OwnedIdentityMaskingUID> {
        return NSFetchRequest<OwnedIdentityMaskingUID>(entityName: entityName)
    }
    

    static func getOrCreate(for ownedIdentity: OwnedIdentity, pushToken: Data) throws -> UID {
        
        guard let context = ownedIdentity.managedObjectContext else { throw makeError(message: "Could not find context within the owned identity instance") }
        
        let request: NSFetchRequest<OwnedIdentityMaskingUID> = OwnedIdentityMaskingUID.fetchRequest()
        request.predicate = Predicate.withOwnedIdentity(ownedIdentity)
        request.fetchLimit = 1
        let item: OwnedIdentityMaskingUID
        if let _item = try context.fetch(request).first {
            let newMaskingUID = try generateDeterministricUID(ownedCryptoId: ownedIdentity.cryptoIdentity, pushToken: pushToken)
            if _item.rawMaskingUID != newMaskingUID.raw {
                _item.rawMaskingUID = newMaskingUID.raw
            }
            item = _item
        } else {
            item = try .init(ownedIdentity: ownedIdentity, pushToken: pushToken)
        }
        return try item.maskingUID
    }
    
    
    static func getOwnedIdentityAssociatedWithMaskingUID(_ maskingUID: UID, within context: NSManagedObjectContext) throws -> OwnedIdentity? {
        let request: NSFetchRequest<OwnedIdentityMaskingUID> = OwnedIdentityMaskingUID.fetchRequest()
        request.predicate = Predicate.withMaskingUID(maskingUID)
        request.fetchLimit = 1
        let item = try context.fetch(request).first
        return item?.ownedIdentity
    }
    
    
    private static func generateDeterministricUID(ownedCryptoId: ObvCryptoIdentity, pushToken: Data) throws -> UID {
        let seedData = Data([ownedCryptoId.getIdentity(), pushToken].joined())
        guard let seed = Seed(with: seedData) else { assertionFailure(); throw Self.makeError(message: "Could not generate seed")}
        let prng = ObvCryptoSuite.sharedInstance.concretePRNG().init(with: seed)
        return UID.gen(with: prng)
    }

}
