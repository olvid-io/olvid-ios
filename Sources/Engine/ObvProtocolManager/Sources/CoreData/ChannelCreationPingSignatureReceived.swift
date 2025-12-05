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


@objc(ChannelCreationPingSignatureReceived)
final class ChannelCreationPingSignatureReceived: NSManagedObject {
        
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
    
    // MARK: - Initializer

    /// 2025-08-27: ok
    convenience init?(ownedCryptoIdentity: ObvCryptoIdentity, signature: Data, within context: NSManagedObjectContext) {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: ChannelCreationPingSignatureReceived.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.ownedIdentity = ownedCryptoIdentity
        self.signature = signature
        
    }
 
    
    private func deleteChannelCreationPingSignatureReceived() throws {
        guard let managedObjectContext else { assertionFailure(); throw ObvError.noContext }
        managedObjectContext.delete(self)
    }
    
    
    enum ObvError: Error {
        case noContext
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
    
    static func exists(ownedCryptoIdentity: ObvCryptoIdentity, signature: Data, within context: NSManagedObjectContext) throws -> Bool {
        let request: NSFetchRequest<ChannelCreationPingSignatureReceived> = ChannelCreationPingSignatureReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity),
            Predicate.withSignature(signature),
        ])
        let count = try context.count(for: request)
        return count > 0
    }
    
    static func deleteAllAssociatedWithOwnedIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<ChannelCreationPingSignatureReceived> = ChannelCreationPingSignatureReceived.fetchRequest()
        request.predicate = Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity)
        request.fetchBatchSize = 100
        request.includesPropertyValues = false
        let items = try context.fetch(request)
        for item in items {
            try item.deleteChannelCreationPingSignatureReceived()
        }
    }
    
    static func batchDeleteAllChannelCreationPingSignatureReceivedForOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: ChannelCreationPingSignatureReceived.entityName)
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
