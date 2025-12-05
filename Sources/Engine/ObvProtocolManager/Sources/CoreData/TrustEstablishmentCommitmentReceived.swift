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
import ObvCrypto
import ObvTypes
import OlvidUtils


@objc(TrustEstablishmentCommitmentReceived)
final class TrustEstablishmentCommitmentReceived: NSManagedObject {
    
    // MARK: Internal constants

    private static let entityName = "TrustEstablishmentCommitmentReceived"

    // MARK: Attributes

    @NSManaged private var rawOwnedIdentity: Data? // Non-optional in the model
    @NSManaged private var commitment: Data? // Non-optional in the model

    // MARK: Variables

    private var ownedIdentity: ObvCryptoIdentity {
        get throws(ObvError) {
            guard let rawOwnedIdentity else { assertionFailure(); throw .unexpectedNilValue }
            guard let ownedIdentity = ObvCryptoIdentity(from: rawOwnedIdentity) else { assertionFailure(); throw .couldNotParseValue }
            return ownedIdentity
        }
    }

    // MARK: - Initializer

    /// 2025-08-27: ok
    convenience init(ownedCryptoIdentity: ObvCryptoIdentity, commitment: Data, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: TrustEstablishmentCommitmentReceived.entityName,
                                                           in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.rawOwnedIdentity = ownedCryptoIdentity.getIdentity()
        self.commitment = commitment
    }
    
    enum ObvError: Error {
        case unexpectedNilValue
        case couldNotParseValue
    }
    
}


// MARK: - Convenience DB getters

extension TrustEstablishmentCommitmentReceived {
    
    struct Predicate {
        enum Key: String {
            case rawOwnedIdentity = "rawOwnedIdentity"
            case commitment = "commitment"
        }
        static func withOwnedCryptoIdentity(_ ownedIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentity, EqualToData: ownedIdentity.getIdentity())
        }
        static func withCommitment(_ commitment: Data) -> NSPredicate {
            NSPredicate(Key.commitment, EqualToData: commitment)
        }
    }

    
    @nonobjc class func fetchRequest() -> NSFetchRequest<TrustEstablishmentCommitmentReceived> {
        return NSFetchRequest<TrustEstablishmentCommitmentReceived>(entityName: TrustEstablishmentCommitmentReceived.entityName)
    }

    
    static func exists(ownedCryptoIdentity: ObvCryptoIdentity, commitment: Data, within context: NSManagedObjectContext) throws -> Bool {
        let request: NSFetchRequest<TrustEstablishmentCommitmentReceived> = TrustEstablishmentCommitmentReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity),
            Predicate.withCommitment(commitment),
        ])
        request.fetchLimit = 1
        request.propertiesToFetch = []
        let item = try context.fetch(request).first
        return item != nil
    }

    
    static func batchDeleteAllTrustEstablishmentCommitmentReceivedForOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: TrustEstablishmentCommitmentReceived.entityName)
        fetchRequest.predicate = Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity)
        let request = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        request.resultType = .resultTypeObjectIDs
        let result = try context.execute(request) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        } else {
            assertionFailure()
        }
    }

}
