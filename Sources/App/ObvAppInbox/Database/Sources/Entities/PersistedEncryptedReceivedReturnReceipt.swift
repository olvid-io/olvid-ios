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
import ObvTypes
import ObvCrypto
import ObvAppInboxTypes


@objc(PersistedEncryptedReceivedReturnReceipt)
public final class PersistedEncryptedReceivedReturnReceipt: NSManagedObject {
    
    private static let entityName = "PersistedEncryptedReceivedReturnReceipt"
    
    // MARK: - Attributes
    
    @NSManaged fileprivate var creationTimestamp: Date? // Expected to be non-nil
    @NSManaged fileprivate var nonce: Data? // Expected to be non-nil
    @NSManaged fileprivate var rawEncryptedPayload: Data? // Expected to be non-nil
    @NSManaged fileprivate var rawOwnedIdentity: Data? // Expected to be non-nil
    @NSManaged fileprivate var rawServerUID: Data? // Expected to be non-nil
    @NSManaged fileprivate var receiptTimestamp: Date? // Expected to be non-nil
    
    // MARK: - Computed variables
    
    /// Expected to be non-nil
    fileprivate var ownedCryptoId: ObvCryptoId? {
        get throws {
            guard let rawOwnedIdentity else { return nil }
            return try ObvCryptoId(identity: rawOwnedIdentity)
        }
    }


    /// Expected to be non-nil
    fileprivate var serverUID: UID? {
        guard let rawServerUID else { assertionFailure(); return nil }
        return UID(uid: rawServerUID)
    }
    
    
    /// Expected to be non-nil
    fileprivate var encryptedPayload: EncryptedData? {
        guard let rawEncryptedPayload else { assertionFailure(); return nil }
        return EncryptedData(data: rawEncryptedPayload)
    }

    
    // MARK: - Init
    
    private convenience init(nonce: Data, encryptedPayload: EncryptedData, ownedCryptoId: ObvCryptoId, serverUID: UID, receiptTimestamp: Date, within context: NSManagedObjectContext) {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.creationTimestamp = Date.now
        self.nonce = nonce
        self.rawEncryptedPayload = encryptedPayload.raw
        self.rawOwnedIdentity = ownedCryptoId.getIdentity()
        self.rawServerUID = serverUID.raw
        self.receiptTimestamp = receiptTimestamp
        
    }
    
    
    public static func createPersistedDecryptedReceivedReturnReceipt(from encryptedReceivedReturnReceipt: ObvEncryptedReceivedReturnReceipt, within context: NSManagedObjectContext) -> Self {
        return self.init(nonce: encryptedReceivedReturnReceipt.nonce,
                         encryptedPayload: encryptedReceivedReturnReceipt.encryptedPayload,
                         ownedCryptoId: encryptedReceivedReturnReceipt.ownedCryptoId,
                         serverUID: encryptedReceivedReturnReceipt.serverUid,
                         receiptTimestamp: encryptedReceivedReturnReceipt.timestamp,
                         within: context)
    }

    
    private func deletePersistedEncryptedReceivedReturnReceipt() throws {
        guard let context = self.managedObjectContext else {
            assertionFailure()
            throw ObvError.contextIsNil
        }
        context.delete(self)
    }
    
}


// MARK: - Errors

extension PersistedEncryptedReceivedReturnReceipt {
    
    enum ObvError: Error {
        case contextIsNil
    }
}


// MARK: - Queries

extension PersistedEncryptedReceivedReturnReceipt {
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case creationTimestamp = "creationTimestamp"
            case nonce = "nonce"
            case rawEncryptedPayload = "rawEncryptedPayload"
            case rawOwnedIdentity = "rawOwnedIdentity"
            case rawServerUID = "rawServerUID"
            case receiptTimestamp = "receiptTimestamp"
        }
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentity, EqualToData: ownedCryptoId.getIdentity())
        }
        static func withNonce(_ nonce: Data) -> NSPredicate {
            NSPredicate(Key.nonce, EqualToData: nonce)
        }
        static func withIdentifier(_ identifier: ObvPersistedEncryptedReceivedReturnReceiptID) -> NSPredicate {
            NSPredicate(withObjectID: identifier.objectID)
        }
        static func createdBefore(_ date: Date) -> NSPredicate {
            NSPredicate(Key.creationTimestamp, earlierThan: date)
        }
    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedEncryptedReceivedReturnReceipt> {
        return NSFetchRequest<PersistedEncryptedReceivedReturnReceipt>(entityName: PersistedEncryptedReceivedReturnReceipt.entityName)
    }

    
    public static func getPersistedEncryptedReceivedReturnReceipts(ownedCryptoId: ObvCryptoId, nonce: Data, within context: NSManagedObjectContext) throws -> [(receipt: ObvEncryptedReceivedReturnReceipt, identifier: ObvPersistedEncryptedReceivedReturnReceiptID)] {
        let request: NSFetchRequest<PersistedEncryptedReceivedReturnReceipt> = Self.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoId(ownedCryptoId),
            Predicate.withNonce(nonce),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.receiptTimestamp.rawValue, ascending: true)]
        request.fetchBatchSize = 100
        let items = try context.fetch(request)
        let encryptedReceivedReturnReceipt: [(receipt: ObvEncryptedReceivedReturnReceipt, identifier: ObvPersistedEncryptedReceivedReturnReceiptID)] = items.compactMap {
            guard let receipt = ObvEncryptedReceivedReturnReceipt($0) else { return nil }
            return (receipt, ObvPersistedEncryptedReceivedReturnReceiptID(objectID: $0.objectID))
        }
        return encryptedReceivedReturnReceipt
    }
    
    
    public static func deletePersistedEncryptedReceivedReturnReceipts(identifier: ObvPersistedEncryptedReceivedReturnReceiptID, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<PersistedEncryptedReceivedReturnReceipt> = Self.fetchRequest()
        request.predicate = Predicate.withIdentifier(identifier)
        request.fetchLimit = 1
        request.propertiesToFetch = []
        guard let item = try context.fetch(request).first else { return }
        try item.deletePersistedEncryptedReceivedReturnReceipt()
    }
 
    
    public static func getPersistedEncryptedReceivedReturnReceipts(createdBefore date: Date, within context: NSManagedObjectContext) throws -> [(receipt: ObvEncryptedReceivedReturnReceipt, identifier: ObvPersistedEncryptedReceivedReturnReceiptID)] {
        let request: NSFetchRequest<PersistedEncryptedReceivedReturnReceipt> = Self.fetchRequest()
        request.predicate = Predicate.createdBefore(date)
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.receiptTimestamp.rawValue, ascending: true)]
        request.fetchBatchSize = 100
        let items = try context.fetch(request)
        let encryptedReceivedReturnReceipt: [(receipt: ObvEncryptedReceivedReturnReceipt, identifier: ObvPersistedEncryptedReceivedReturnReceiptID)] = items.compactMap {
            guard let receipt = ObvEncryptedReceivedReturnReceipt($0) else { return nil }
            return (receipt, ObvPersistedEncryptedReceivedReturnReceiptID(objectID: $0.objectID))
        }
        return encryptedReceivedReturnReceipt
    }
    
    
    public static func batchDeletePersistedEncryptedReceivedReturnReceipts(createdBefore date: Date, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = PersistedEncryptedReceivedReturnReceipt.fetchRequest()
        request.predicate = Predicate.createdBefore(date)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeObjectIDs
        let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
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



// MARK: - `ObvEncryptedReceivedReturnReceipt` from `PersistedEncryptedReceivedReturnReceipt`


private extension ObvEncryptedReceivedReturnReceipt {
    
    init?(_ item: PersistedEncryptedReceivedReturnReceipt) {
        do {
            guard let ownedCryptoId = try item.ownedCryptoId else { assertionFailure(); return nil }
            guard let serverUID = item.serverUID else { assertionFailure(); return nil }
            guard let nonce = item.nonce else { assertionFailure(); return nil }
            guard let encryptedPayload = item.encryptedPayload else { assertionFailure(); return nil }
            guard let receiptTimestamp = item.receiptTimestamp else { assertionFailure(); return nil }
            self.init(ownedCryptoId: ownedCryptoId,
                      serverUid: serverUID,
                      nonce: nonce,
                      encryptedPayload: encryptedPayload,
                      timestamp: receiptTimestamp)
        } catch {
            assertionFailure(error.localizedDescription)
            return nil
        }
    }
    
}
