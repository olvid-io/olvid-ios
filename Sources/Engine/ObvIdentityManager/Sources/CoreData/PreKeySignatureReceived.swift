/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvMetaManager
import ObvCrypto


@objc(PreKeySignatureReceived)
final class PreKeySignatureReceived: NSManagedObject {
    
    private static let entityName = "PreKeySignatureReceived"
    
    // MARK: Attributes

    /// The prekey's id, repeated here because the store's uniqueness constraint on the pair cannot name the relationship.
    @NSManaged private var rawPreKeyId: Data? // Expected to be non-nil
    @NSManaged private var signature: Data? // Expected to be non-nil

    // MARK: Relationships

    @NSManaged private var preKey: PreKeyForCurrentOwnedDevice? // Expected to be non-nil

    // MARK: Initializers

    private convenience init(signature: Data, preKey: PreKeyForCurrentOwnedDevice) throws {

        guard let context = preKey.managedObjectContext else {
            assertionFailure()
            throw ObvIdentityManagerError.contextIsNil
        }

        guard let cryptoKeyId = preKey.cryptoKeyId else {
            assertionFailure()
            throw ObvError.preKeyHasNoKeyId
        }

        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.rawPreKeyId = cryptoKeyId.raw
        self.signature = signature
        self.preKey = preKey

    }


    enum ObvError: Error {
        case preKeyHasNoKeyId
    }

    
    static func create(signature: Data, preKey: PreKeyForCurrentOwnedDevice) throws {
        _ = try self.init(signature: signature, preKey: preKey)
    }
    
}


// MARK: - Convenience DB getters

extension PreKeySignatureReceived {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<PreKeySignatureReceived> {
        return NSFetchRequest<PreKeySignatureReceived>(entityName: Self.entityName)
    }

    struct Predicate {
        enum Key: String {
            case rawPreKeyId = "rawPreKeyId"
            case signature = "signature"
            case preKey = "preKey"
        }
        private static func withSignature(_ signature: Data) -> NSPredicate {
            NSPredicate(Key.signature, EqualToData: signature)
        }
        private static func withPreKeyId(_ cryptoKeyId: CryptoKeyId) -> NSPredicate {
            NSPredicate(Key.rawPreKeyId, EqualToData: cryptoKeyId.raw)
        }
        /// On the prekey's id rather than on the relationship: the pair is what the uniqueness constraint names, so its
        /// unique index serves this query and the check asks the store the same question the constraint does.
        fileprivate static func with(signature: Data, preKeyId cryptoKeyId: CryptoKeyId) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.withPreKeyId(cryptoKeyId),
                Self.withSignature(signature),
            ])
        }
    }


    /// A count rather than a fetch, so that no row is materialised to answer yes or no.
    static func exists(signature: Data, preKey: PreKeyForCurrentOwnedDevice) throws -> Bool {
        guard let context = preKey.managedObjectContext else { assertionFailure(); throw ObvIdentityManagerError.contextIsNil }
        guard let cryptoKeyId = preKey.cryptoKeyId else { assertionFailure(); throw ObvError.preKeyHasNoKeyId }
        let request: NSFetchRequest<PreKeySignatureReceived> = PreKeySignatureReceived.fetchRequest()
        request.predicate = Predicate.with(signature: signature, preKeyId: cryptoKeyId)
        return try context.count(for: request) > 0
    }
    
}
