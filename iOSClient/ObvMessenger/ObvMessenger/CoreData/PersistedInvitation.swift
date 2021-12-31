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
import os.log
import ObvEngine
import ObvTypes


@objc(PersistedInvitation)
final class PersistedInvitation: NSManagedObject {
    
    private static let entityName = "PersistedInvitation"
    static let actionRequiredKey = "actionRequired"
    static let dateKey = "date"
    static let encodedObvDialogKey = "encodedObvDialog"
    static let rawStatusKey = "rawStatus"
    private static let uuidKey = "uuid"
    static let ownedIdentityKey = "ownedIdentity"
    static let ownedIdentityIdentityKey = [ownedIdentityKey, PersistedObvOwnedIdentity.identityKey].joined(separator: ".")
    private static let errorDomain = "PersistedInvitation"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    // MARK: - Attributes
    
    @NSManaged private(set) var actionRequired: Bool
    @NSManaged private(set) var date: Date
    private(set) var obvDialog: ObvDialog {
        get {
            let rawData = kvoSafePrimitiveValue(forKey: PersistedInvitation.encodedObvDialogKey) as! Data
            return ObvDialog.decode(rawData)!
        }
        set {
            kvoSafeSetPrimitiveValue(newValue.encode().rawData, forKey: PersistedInvitation.encodedObvDialogKey)
        }
    }
    @NSManaged private var rawStatus: Int
    @NSManaged private(set) var uuid: UUID
    
    
    // MARK: - Relationships
    
    @NSManaged private(set) var ownedIdentity: PersistedObvOwnedIdentity? // If nil, this entity is eventually cascade-deleted
    
    // Computed properties
    
    var status: Status {
        return Status(rawValue: self.rawStatus)!
    }

    enum Status: Int {
        case new = 0
        case updated = 1
        case old = 3
    }
    
    // MARK: - Other variables
    
    private var changedKeys = Set<String>()

}


// MARK: - Initializer
extension PersistedInvitation {
    
    private convenience init?(obvDialog: ObvDialog, within context: NSManagedObjectContext) {
        guard let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: obvDialog.ownedCryptoId, within: context) else { return nil }
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedInvitation.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.actionRequired = obvDialog.actionRequired
        self.uuid = obvDialog.uuid
        self.rawStatus = Status.new.rawValue
        self.obvDialog = obvDialog
        self.date = Date()
        self.ownedIdentity = ownedIdentity
    }
    
    
    static func insertOrUpdate(_ obvDialog: ObvDialog, within context: NSManagedObjectContext) throws {
        
        if let existingInvitation = try PersistedInvitation.get(uuid: obvDialog.uuid, within: context) {
            if existingInvitation.obvDialog != obvDialog {
                existingInvitation.obvDialog = obvDialog
                existingInvitation.date = Date()
                existingInvitation.rawStatus = Status.updated.rawValue
                existingInvitation.actionRequired = obvDialog.actionRequired
            }
        } else {
            guard PersistedInvitation(obvDialog: obvDialog, within: context) != nil else { throw NSError() }
        }
        
    }
}


// MARK: - Convenience DB getters

extension PersistedInvitation {
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedInvitation> {
        return NSFetchRequest<PersistedInvitation>(entityName: PersistedInvitation.entityName)
    }

    static func get(uuid: UUID, within context: NSManagedObjectContext) throws -> PersistedInvitation? {
        let request: NSFetchRequest<PersistedInvitation> = PersistedInvitation.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", uuidKey, uuid as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    static func markAllAsOld(for ownedIdentity: PersistedObvOwnedIdentity) throws {
        guard let context = ownedIdentity.managedObjectContext else { throw NSError() }
        let request: NSFetchRequest<PersistedInvitation> = PersistedInvitation.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K != %d",
                                        ownedIdentityKey, ownedIdentity,
                                        rawStatusKey, Status.old.rawValue)
        let results = try context.fetch(request)
        results.forEach { $0.rawStatus = Status.old.rawValue }
    }
    
    
    static func countInvitationsRequiringActionOrWithNotOldStatus(for ownedIdentity: PersistedObvOwnedIdentity) throws -> Int {
        guard let context = ownedIdentity.managedObjectContext else { throw NSError() }
        let request: NSFetchRequest<PersistedInvitation> = PersistedInvitation.fetchRequest()
        do {
            let predicate1 = NSPredicate(format: "%K == %@", ownedIdentityKey, ownedIdentity)
            let predicate2 = NSPredicate(format: "%K != %d OR %K == true",
                                         rawStatusKey, Status.old.rawValue,
                                         actionRequiredKey)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate1, predicate2])
        }
        return try context.count(for: request)
    }
    
    
    static func countInvitationsRequiringActionOrWithNotOldStatusForAllOwnedIdentities(within context: NSManagedObjectContext) throws -> Int {
        let request: NSFetchRequest<PersistedInvitation> = PersistedInvitation.fetchRequest()
        request.predicate = NSPredicate(format: "%K != %d OR %K == true",
                                        rawStatusKey, Status.old.rawValue,
                                        actionRequiredKey)
        return try context.count(for: request)
    }
    
    
    
    static func delete(_ persistedInvitation: PersistedInvitation, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<PersistedInvitation> = PersistedInvitation.fetchRequest()
        request.predicate = NSPredicate(format: "SELF == %@", persistedInvitation)
        request.fetchLimit = 1
        if let object = try context.fetch(request).first {
            context.delete(object)
        }
    }

}


// MARK: - NSFetchedResultsController

extension PersistedInvitation {
    
    static func getFetchedResultsControllerForOwnedIdentity(with ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedInvitation> {
        
        let request: NSFetchRequest<PersistedInvitation> = PersistedInvitation.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@",
                                        PersistedInvitation.ownedIdentityIdentityKey,
                                        ownedCryptoId.getIdentity() as NSData)
        request.sortDescriptors = [NSSortDescriptor.init(key: PersistedInvitation.dateKey, ascending: false)]
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: request,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)
        return fetchedResultsController
    }
    
    
}


// MARK: - Sending notifications on change

extension PersistedInvitation {
    
    override func willSave() {
        super.willSave()
        
        changedKeys = Set<String>(self.changedValues().keys)

    }
    
    override func didSave() {
        super.didSave()

        if !isDeleted {
            
            // We do *not* notify that the invitation has changed when the reason is that the invitation status changed from new or updated to old
            if !(changedKeys.contains(PersistedInvitation.rawStatusKey) && status == .old) {
                let notification = ObvMessengerInternalNotification.newOrUpdatedPersistedInvitation(obvDialog: obvDialog,
                                                                                                    persistedInvitationUUID: uuid)
                notification.postOnDispatchQueue()
            }
        }
        
    }
}
