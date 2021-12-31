/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

fileprivate let errorDomain = "ObvEngineMigrationV20ToV21"
fileprivate let debugPrintPrefix = "[\(errorDomain)][UtilsForMigrationV20ToV21]"

final class UtilsForMigrationV20ToV21 {
    
    static let shared = UtilsForMigrationV20ToV21()

    private var rawOwnedIdentity: Data?
    private var v21ConstraintsStillNeedToBeEnforced = true
    
    private init() {}
    
    private func makeError(message: String) -> Error {
        let message = [debugPrintPrefix, message].joined(separator: " ")
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    func findOwnedIdentityRawIdentityInSourceContext(manager: NSMigrationManager) throws -> Data {
        
        // If this method was called in the past, we already know about the owned identity
        if let rawOwnedIdentity = self.rawOwnedIdentity {
            return rawOwnedIdentity
        }
                
        let sOwnedIdentity = try self.findOwnedIdentityObjectInSourceContext(manager: manager)
        
        guard let cryptoIdentity = sOwnedIdentity.value(forKey: "cryptoIdentity") as? ObvCryptoIdentity else {
            throw makeError(message: "Could not extract raw crypto identity from owned identity")
        }
        
        // Set the owned identity for future calls of this method

        let rawOwnedIdentity = cryptoIdentity.getIdentity()
        self.rawOwnedIdentity = rawOwnedIdentity
        
        return rawOwnedIdentity
    }

    func findOwnedIdentityObjectInSourceContext(manager: NSMigrationManager) throws -> NSManagedObject {
        
        // The following call returns all the OwnedIdentity instances in the source context.
        // Setting the destinationInstances parameter to nil allows to get all the possible instances.
        // We expect to only
        let sOwnedIdentities = manager.sourceContext.registeredObjects.filter { $0.entity.name == "OwnedIdentity"}

        guard sOwnedIdentities.count == 1 else {
            throw makeError(message: "Unexpected number of owned identities. Expecting 1, got \(sOwnedIdentities.count).")
        }
        
        let sOwnedIdentity = sOwnedIdentities.first!

        return sOwnedIdentity
    }
    
    /// New core data constraints were added in V21. We must make sure these constraints are satisfied otherwise the migration process will crash.
    /// We enforce these constraints right on source (V20) entities by calling this method at the beginning of *all* calls to the `createDestinationInstances` methods.
    /// Of course, this method will perform the work only once, during the first call.
    func enforceV21ConstraintsOnV20(manager: NSMigrationManager) throws {
        
        guard v21ConstraintsStillNeedToBeEnforced else { return }
        defer {
            // Even if this method throws, it won't be necessary to try again...
            v21ConstraintsStillNeedToBeEnforced = false
        }
        
        try enforceV21ConstraintsOnV20OutboxMessage(manager: manager)
        try enforceV21ConstraintsOnV20InboxMessage(manager: manager)
        
    }
    
    
    private func enforceV21ConstraintsOnV20InboxMessage(manager: NSMigrationManager) throws {
                
        let entityName = "InboxMessage"

        struct ConstrainedValuesInV20: Hashable {
            let messageId: UID
            init(_ dInstance: NSManagedObject) {
                self.messageId = dInstance.value(forKey: "messageId") as! UID
            }
        }

        let fetchRequest: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: entityName)
        let items = try manager.sourceContext.fetch(fetchRequest)
        
        guard !items.isEmpty else {
            return
        }
        
        let allConstrainedValues = Set(items.map { ConstrainedValuesInV20($0) })
        
        guard items.count != allConstrainedValues.count else {
            // Best case, all constraints were natively satisfied
            debugPrint(items.count, allConstrainedValues.count)
            return
        }

        // If we reach this point, we have at least to items that have identical values on the newly constraints values. We must fix this.
        
        var witnessedConstrainedValues = Set<ConstrainedValuesInV20>()
        var itemsToDelete = [NSManagedObject]()
        for item in items {
            let itemVlues = ConstrainedValuesInV20(item)
            if witnessedConstrainedValues.contains(itemVlues) {
                itemsToDelete.append(item)
            } else {
                witnessedConstrainedValues.insert(itemVlues)
            }
        }
        
        // We have items to delete. Delete these items and its relationships
        
        for item in itemsToDelete {
            let fetchRequest: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "InboxAttachment")
            fetchRequest.predicate = NSPredicate(format: "%K == %@", "message", item)
            let dbAttachments = try manager.sourceContext.fetch(fetchRequest)
            for dbAttachment in dbAttachments {
                manager.sourceContext.delete(dbAttachment)
            }
            manager.sourceContext.delete(item)
        }
        
    }
    
    
    // Tested
    private func enforceV21ConstraintsOnV20OutboxMessage(manager: NSMigrationManager) throws {
        
        let entityName = "OutboxMessage"

        struct ConstrainedValuesInV20: Hashable {
            let messageId: UID
            init(_ dInstance: NSManagedObject) {
                self.messageId = dInstance.value(forKey: "messageId") as! UID
            }
        }
        
        let fetchRequest: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: entityName)
        let items = try manager.sourceContext.fetch(fetchRequest)
        
        guard !items.isEmpty else {
            return
        }
        
        let allConstrainedValues = Set(items.map { ConstrainedValuesInV20($0) })
        
        guard items.count != allConstrainedValues.count else {
            // Best case, all constraints were natively satisfied
            debugPrint(items.count, allConstrainedValues.count)
            return
        }

        // If we reach this point, we have at least to items that have identical values on the newly constraints values. We must fix this.

        var witnessedConstrainedValues = Set<ConstrainedValuesInV20>()
        var itemsToDelete = [NSManagedObject]()
        for item in items {
            let itemVlues = ConstrainedValuesInV20(item)
            if witnessedConstrainedValues.contains(itemVlues) {
                itemsToDelete.append(item)
            } else {
                witnessedConstrainedValues.insert(itemVlues)
            }
        }
        
        // We have items to delete. Delete these items and its relationships
        
        for item in itemsToDelete {
            guard let headers = item.value(forKey: "headers") as? Set<NSManagedObject> else {
                throw makeError(message: "Could not get headers of an OutboxMessage duplicate")
            }
            guard let unsortedAttachments = item.value(forKey: "unsortedAttachments") as? Set<NSManagedObject> else {
                throw makeError(message: "Could not get unsortedAttachments of an OutboxMessage duplicate")
            }
            for header in headers {
                manager.sourceContext.delete(header)
            }
            for attachment in unsortedAttachments {
                manager.sourceContext.delete(attachment)
            }
            manager.sourceContext.delete(item)
        }
                
    }
    
}
