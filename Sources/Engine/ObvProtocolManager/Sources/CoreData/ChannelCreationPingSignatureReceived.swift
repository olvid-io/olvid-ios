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
import ObvCrypto
import ObvTypes
import OlvidUtils


@objc(ChannelCreationPingSignatureReceived)
final class ChannelCreationPingSignatureReceived: NSManagedObject, ObvManagedObject {
        
    // MARK: Internal constants

    private static let entityName = "ChannelCreationPingSignatureReceived"

    // MARK: Attributes

    @NSManaged private var rawOwnedIdentity: Data
    @NSManaged private var signature: Data

    // MARK: Variables
            
    private var ownedIdentity: ObvCryptoIdentity {
        get { ObvCryptoIdentity(from: rawOwnedIdentity)! }
        set { rawOwnedIdentity = newValue.getIdentity() }
    }
    
    weak var obvContext: ObvContext?

    // MARK: - Initializer

    convenience init?(ownedCryptoIdentity: ObvCryptoIdentity, signature: Data, within obvContext: ObvContext) {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: ChannelCreationPingSignatureReceived.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)

        self.ownedIdentity = ownedCryptoIdentity
        self.signature = signature
        
    }
    
}


// MARK: - Convenience DB getters

extension ChannelCreationPingSignatureReceived {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ChannelCreationPingSignatureReceived> {
        return NSFetchRequest<ChannelCreationPingSignatureReceived>(entityName: ChannelCreationPingSignatureReceived.entityName)
    }

    private struct Predicate {
        enum Key: String {
            case rawOwnedIdentity = "rawOwnedIdentity"
            case signature = "signature"
        }
        static func withOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentity, EqualToData: ownedCryptoIdentity.getIdentity())
        }
        static func withSignature(_ signature: Data) -> NSPredicate {
            NSPredicate(Key.signature, EqualToData: signature)
        }
    }
    
    static func exists(ownedCryptoIdentity: ObvCryptoIdentity, signature: Data, within obvContext: ObvContext) throws -> Bool {
        let request: NSFetchRequest<ChannelCreationPingSignatureReceived> = ChannelCreationPingSignatureReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity),
            Predicate.withSignature(signature),
        ])
        let count = try obvContext.count(for: request)
        return count > 0
    }
    
    static func deleteAllAssociatedWithOwnedIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        let request: NSFetchRequest<ChannelCreationPingSignatureReceived> = ChannelCreationPingSignatureReceived.fetchRequest()
        request.predicate = Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity)
        request.fetchBatchSize = 100
        request.includesPropertyValues = false
        let items = try obvContext.fetch(request)
        for item in items {
            obvContext.delete(item)
        }
    }
    
    static func batchDeleteAllChannelCreationPingSignatureReceivedForOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: ChannelCreationPingSignatureReceived.entityName)
        fetchRequest.predicate = NSPredicate(format: "%K == %@", Predicate.Key.rawOwnedIdentity.rawValue, ownedCryptoIdentity.getIdentity() as NSData)
        let request = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        _ = try obvContext.execute(request)
    }

}
