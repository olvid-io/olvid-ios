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
import OlvidUtils
import ObvCrypto


@objc(MutualScanSignatureReceived)
final class MutualScanSignatureReceived: NSManagedObject {
    
    private static let entityName = "MutualScanSignatureReceived"

    // MARK: Attributes

    @NSManaged private var signature: Data
    @NSManaged private var rawOwnedIdentity: Data

    // MARK: - Initializer

    /// 2025-08-27: ok
    convenience init?(ownedCryptoIdentity: ObvCryptoIdentity, signature: Data, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: MutualScanSignatureReceived.entityName,
                                                           in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.signature = signature
        self.rawOwnedIdentity = ownedCryptoIdentity.getIdentity()
    }

}


// MARK: - Convenience DB getters

extension MutualScanSignatureReceived {
    
    private struct Predicate {
        enum Key: String {
            case signature = "signature"
            case rawOwnedIdentity = "rawOwnedIdentity"
        }
        static func withSignature(_ signature: Data) -> NSPredicate {
            NSPredicate(Key.signature, EqualToData: signature)
        }
        static func withOwnedIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentity, EqualToData: ownedCryptoIdentity.getIdentity())
        }
    }
    
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<MutualScanSignatureReceived> {
        return NSFetchRequest<MutualScanSignatureReceived>(entityName: MutualScanSignatureReceived.entityName)
    }


    static func exists(ownedCryptoIdentity: ObvCryptoIdentity, signature: Data, within context: NSManagedObjectContext) throws -> Bool {
        let request: NSFetchRequest<MutualScanSignatureReceived> = MutualScanSignatureReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withSignature(signature),
            Predicate.withOwnedIdentity(ownedCryptoIdentity),
        ])
        request.fetchLimit = 1
        request.propertiesToFetch = []
        let item = try context.fetch(request).first
        return item != nil
    }
    
 
    static func batchDeleteAllMutualScanSignatureReceivedForOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: MutualScanSignatureReceived.entityName)
        fetchRequest.predicate = Predicate.withOwnedIdentity(ownedCryptoIdentity)
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
