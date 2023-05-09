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
import OlvidUtils
import ObvCrypto


@objc(MutualScanSignatureReceived)
final class MutualScanSignatureReceived: NSManagedObject, ObvManagedObject {
    
    private static let entityName = "MutualScanSignatureReceived"

    // MARK: Attributes

    @NSManaged private var signature: Data
    @NSManaged private var rawOwnedIdentity: Data

    // MARK: Variables

    private var ownedCryptoIdentity: ObvCryptoIdentity {
        get { ObvCryptoIdentity(from: rawOwnedIdentity)! }
        set { rawOwnedIdentity = newValue.getIdentity() }
    }

    var obvContext: ObvContext?

    // MARK: - Initializer

    convenience init?(ownedCryptoIdentity: ObvCryptoIdentity, signature: Data, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: MutualScanSignatureReceived.entityName,
                                                           in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.signature = signature
        self.ownedCryptoIdentity = ownedCryptoIdentity
    }

}


// MARK: - Convenience DB getters

extension MutualScanSignatureReceived {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<MutualScanSignatureReceived> {
        return NSFetchRequest<MutualScanSignatureReceived>(entityName: MutualScanSignatureReceived.entityName)
    }

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
    
    static func exists(ownedCryptoIdentity: ObvCryptoIdentity, signature: Data, within obvContext: ObvContext) throws -> Bool {
        let request: NSFetchRequest<MutualScanSignatureReceived> = MutualScanSignatureReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withSignature(signature),
            Predicate.withOwnedIdentity(ownedCryptoIdentity),
        ])
        let count = try obvContext.count(for: request)
        return count > 0
    }
 
    static func batchDeleteAllMutualScanSignatureReceivedForOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: MutualScanSignatureReceived.entityName)
        fetchRequest.predicate = Predicate.withOwnedIdentity(ownedCryptoIdentity)
        let request = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        _ = try obvContext.execute(request)
    }

}
