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


fileprivate let errorDomain = "UtilsForAppMigrationV19ToV20"
fileprivate let debugPrintPrefix = "[\(errorDomain)][UtilsForAppMigrationV19ToV20]"


final class UtilsForAppMigrationV19ToV20 {
    
    private var v20ConstraintsStillNeedToBeEnforced = true
    
    private func makeError(message: String) -> Error {
        let message = [debugPrintPrefix, message].joined(separator: " ")
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    static let shared = UtilsForAppMigrationV19ToV20()

    private var rawOwnedIdentity: Data?
    
    private init() {}
    
    func findOwnedIdentityRawIdentityInSourceContext(manager: NSMigrationManager) throws -> Data {
        
        // If this method was called in the past, we already know about the owned identity
        if let rawOwnedIdentity = self.rawOwnedIdentity {
            return rawOwnedIdentity
        }
                
        let sPersistedObvOwnedIdentity = try self.findPersistedObvOwnedIdentityObjectInSourceContext(manager: manager)
        
        guard let rawOwnedIdentity = sPersistedObvOwnedIdentity.value(forKey: "identity") as? Data else {
            throw makeError(message: "Could not extract (data) identity from the persisted owned identity")
        }
                
        // Set the owned identity for future calls of this method
        self.rawOwnedIdentity = rawOwnedIdentity
        
        return rawOwnedIdentity
    }

    func findPersistedObvOwnedIdentityObjectInSourceContext(manager: NSMigrationManager) throws -> NSManagedObject {
        
        // The following call returns all the PersistedObvOwnedIdentity instances in the source context.
        // Setting the destinationInstances parameter to nil allows to get all the possible instances.
        // We expect to only
        let sPersistedObvOwnedIdentities = manager.sourceContext.registeredObjects.filter { $0.entity.name == "PersistedObvOwnedIdentity"}
        
        guard sPersistedObvOwnedIdentities.count == 1 else {
            throw makeError(message: "Unexpected number of PersistedObvOwnedIdentity instances. Expecting 1, got \(sPersistedObvOwnedIdentities.count)")
        }
        
        let sPersistedObvOwnedIdentity = sPersistedObvOwnedIdentities.first!

        return sPersistedObvOwnedIdentity
    }
    
    
    func enforceV20ConstraintsOnV19(manager: NSMigrationManager) throws {
        
        guard v20ConstraintsStillNeedToBeEnforced else { return }
        defer {
            // Even if this method throws, it won't be necessary to try again...
            v20ConstraintsStillNeedToBeEnforced = false
        }
        
        try enforceV20ConstraintsOnV19Fyle(manager: manager)
        try enforceV20ConstraintsOnV19PersistedObvContactDevice(manager: manager)
        do {
            try enforceV20ConstraintsOnV19PersistedPersistedPendingGroupMember(manager: manager)
        } catch {
            // Continue anyway
        }
        
    }

    
    // Tested
    private func enforceV20ConstraintsOnV19Fyle(manager: NSMigrationManager) throws {
        
        let entityName = "Fyle"

        struct ConstrainedValues: Hashable {
            let sha256: Data
            init(_ dInstance: NSManagedObject) {
                self.sha256 = dInstance.value(forKey: "sha256") as! Data
            }
        }

        let fetchRequest: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: entityName)
        let items = try manager.sourceContext.fetch(fetchRequest)
        
        guard !items.isEmpty else {
            return
        }
        
        let allConstrainedValues = Set(items.map { ConstrainedValues($0) })
        
        guard items.count != allConstrainedValues.count else {
            // Best case, all constraints were natively satisfied
            debugPrint(items.count, allConstrainedValues.count)
            return
        }

        // If we reach this point, we have at least to items that have identical values on the newly constraints values. We must fix this.

        var witnessedConstrainedValues = Set<ConstrainedValues>()
        var itemsToDelete = [NSManagedObject]()
        for item in items {
            let itemVlues = ConstrainedValues(item)
            if witnessedConstrainedValues.contains(itemVlues) {
                itemsToDelete.append(item)
            } else {
                witnessedConstrainedValues.insert(itemVlues)
            }
        }
        
        // We have items to delete. Delete these items,
        
        for item in itemsToDelete {
            manager.sourceContext.delete(item)
        }
        
    }

    
    // Tested
    private func enforceV20ConstraintsOnV19PersistedObvContactDevice(manager: NSMigrationManager) throws {
        
        let entityName = "PersistedObvContactDevice"

        struct ConstrainedValues: Hashable {
            let identifier: Data
            init(_ dInstance: NSManagedObject) {
                self.identifier = dInstance.value(forKey: "identifier") as! Data
            }
        }

        let fetchRequest: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: entityName)
        let items = try manager.sourceContext.fetch(fetchRequest)
        
        guard !items.isEmpty else {
            return
        }
        
        let allConstrainedValues = Set(items.map { ConstrainedValues($0) })
        
        guard items.count != allConstrainedValues.count else {
            // Best case, all constraints were natively satisfied
            debugPrint(items.count, allConstrainedValues.count)
            return
        }

        // If we reach this point, we have at least to items that have identical values on the newly constraints values. We must fix this.

        var witnessedConstrainedValues = Set<ConstrainedValues>()
        var itemsToDelete = [NSManagedObject]()
        for item in items {
            let itemVlues = ConstrainedValues(item)
            if witnessedConstrainedValues.contains(itemVlues) {
                itemsToDelete.append(item)
            } else {
                witnessedConstrainedValues.insert(itemVlues)
            }
        }
        
        // We have items to delete. Delete these items,
        
        for item in itemsToDelete {
            manager.sourceContext.delete(item)
        }
        
    }

    
    // Tested
    private func enforceV20ConstraintsOnV19PersistedPersistedPendingGroupMember(manager: NSMigrationManager) throws {
        
        let entityName = "PersistedPendingGroupMember"

        struct ConstrainedValues: Hashable {
            let identity: Data
            let rawGroupOwnerIdentity: Data
            let rawGroupUidRaw: Data
            private static func makeError(message: String) -> Error {
                let message = [debugPrintPrefix, message].joined(separator: " ")
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
            }
            init(_ instance: NSManagedObject) throws {
                self.identity = instance.value(forKey: "identity") as! Data
                guard let sPersistedContactGroupObject = instance.value(forKey: "contactGroup") as? NSManagedObject else {
                    throw ConstrainedValues.makeError(message: "Could not get the source PersistedContactGroup object")
                }
                guard let groupUidRaw = sPersistedContactGroupObject.value(forKey: "groupUidRaw") as? Data else {
                    throw ConstrainedValues.makeError(message: "Could not get the group uid")
                }
                guard let groupOwnerIdentity = sPersistedContactGroupObject.value(forKey: "ownerIdentity") as? Data else {
                    throw ConstrainedValues.makeError(message: "Could not get the group owner identity")
                }
                self.rawGroupOwnerIdentity = groupOwnerIdentity
                self.rawGroupUidRaw = groupUidRaw
            }
        }

        let fetchRequest: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: entityName)
        let items = try manager.sourceContext.fetch(fetchRequest)
        
        guard !items.isEmpty else {
            return
        }
        
        let allConstrainedValues = try Set(items.map { try ConstrainedValues($0) })
        
        guard items.count != allConstrainedValues.count else {
            // Best case, all constraints were natively satisfied
            debugPrint(items.count, allConstrainedValues.count)
            return
        }

        // If we reach this point, we have at least to items that have identical values on the newly constraints values. We must fix this.
        
        var witnessedConstrainedValues = Set<ConstrainedValues>()
        var itemsToDelete = [NSManagedObject]()
        for item in items {
            let itemVlues = try ConstrainedValues(item)
            if witnessedConstrainedValues.contains(itemVlues) {
                itemsToDelete.append(item)
            } else {
                witnessedConstrainedValues.insert(itemVlues)
            }
        }
        
        // We have items to delete. Delete these items,
        
        for item in itemsToDelete {
            manager.sourceContext.delete(item)
        }
        
    }

}
