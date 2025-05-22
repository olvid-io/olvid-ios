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
final class TrustEstablishmentCommitmentReceived: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants

    private static let entityName = "TrustEstablishmentCommitmentReceived"
    private static let rawOwnedIdentityKey = "rawOwnedIdentity"
    private static let commitmentKey = "commitment"

    // MARK: Attributes

    @NSManaged private var rawOwnedIdentity: Data
    @NSManaged private var commitment: Data

    // MARK: Variables

    private var ownedIdentity: ObvCryptoIdentity {
        get { ObvCryptoIdentity(from: rawOwnedIdentity)! }
        set { rawOwnedIdentity = newValue.getIdentity() }
    }

    weak var obvContext: ObvContext?

    // MARK: - Initializer

    convenience init?(ownedCryptoIdentity: ObvCryptoIdentity, commitment: Data, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: TrustEstablishmentCommitmentReceived.entityName,
                                                           in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.ownedIdentity = ownedCryptoIdentity
        self.commitment = commitment
    }
}


// MARK: - Convenience DB getters

extension TrustEstablishmentCommitmentReceived {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<TrustEstablishmentCommitmentReceived> {
        return NSFetchRequest<TrustEstablishmentCommitmentReceived>(entityName: TrustEstablishmentCommitmentReceived.entityName)
    }

    private struct Predicate {
        static func withOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(format: "%K == %@",
                        TrustEstablishmentCommitmentReceived.rawOwnedIdentityKey,
                        ownedCryptoIdentity.getIdentity() as NSData)
        }
        static func withCommitment(_ commitment: Data) -> NSPredicate {
            NSPredicate(format: "%K == %@",
                        TrustEstablishmentCommitmentReceived.commitmentKey,
                        commitment as NSData)
        }
    }

    static func exists(ownedCryptoIdentity: ObvCryptoIdentity, commitment: Data, within obvContext: ObvContext) throws -> Bool {
        let request: NSFetchRequest<TrustEstablishmentCommitmentReceived> = TrustEstablishmentCommitmentReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity),
            Predicate.withCommitment(commitment),
        ])
        let count = try obvContext.count(for: request)
        return count > 0
    }

    
    static func batchDeleteAllTrustEstablishmentCommitmentReceivedForOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: TrustEstablishmentCommitmentReceived.entityName)
        fetchRequest.predicate = Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity)
        let request = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        request.resultType = .resultTypeObjectIDs
        let result = try obvContext.execute(request) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [obvContext.context])
        } else {
            assertionFailure()
        }
    }

}
