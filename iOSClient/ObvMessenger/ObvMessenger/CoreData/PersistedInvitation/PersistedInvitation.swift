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
import os.log
import ObvEngine
import ObvTypes
import OlvidUtils


@objc(PersistedInvitation)
class PersistedInvitation: NSManagedObject {
    
    private static let entityName = "PersistedInvitation"
    private static let errorDomain = "PersistedInvitation"
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    // MARK: - Attributes
    
    @NSManaged private(set) var actionRequired: Bool
    @NSManaged private(set) var date: Date
    private(set) var obvDialog: ObvDialog? {
        get {
            guard let rawData = kvoSafePrimitiveValue(forKey: Predicate.Key.encodedObvDialog.rawValue) as? Data else { return nil }
            return ObvDialog.decode(rawData)
        }
        set {
            guard let newValue = newValue else { assertionFailure(); return }
            guard let rawData = try? newValue.obvEncode().rawData else { assertionFailure(); return }
            kvoSafeSetPrimitiveValue(rawData, forKey: Predicate.Key.encodedObvDialog.rawValue)
        }
    }
    @NSManaged private var rawStatus: Int
    @NSManaged private(set) var uuid: UUID
    
    
    // MARK: Relationships
    
    @NSManaged private(set) var ownedIdentity: PersistedObvOwnedIdentity? // If nil, this entity is eventually cascade-deleted
    
    // MARK: Computed properties
    
    var status: Status {
        return Status(rawValue: self.rawStatus)!
    }

    enum Status: Int {
        case new = 0
        case updated = 1
        case old = 3
    }
    
    // MARK: Other variables
    
    private var changedKeys = Set<String>()

}


// MARK: - Initializer

extension PersistedInvitation {
    
    /// Shall only be called from subclasses
    convenience init(obvDialog: ObvDialog, forEntityName entityName: String, within context: NSManagedObjectContext) throws {
        guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: obvDialog.ownedCryptoId, within: context) else {
            throw Self.makeError(message: "Could not find owned identity")
        }
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.actionRequired = obvDialog.actionRequired
        self.uuid = obvDialog.uuid
        self.rawStatus = Status.new.rawValue
        self.obvDialog = obvDialog
        self.date = Date()
        self.ownedIdentity = ownedIdentity
    }
    
    
    static func insertOrUpdate(_ obvDialog: ObvDialog, within context: NSManagedObjectContext) throws {
        if let existingInvitation = try PersistedInvitation.getPersistedInvitation(uuid: obvDialog.uuid, ownedCryptoId: obvDialog.ownedCryptoId, within: context) {
            if existingInvitation.obvDialog != obvDialog {
                existingInvitation.obvDialog = obvDialog
                existingInvitation.date = Date()
                existingInvitation.rawStatus = Status.updated.rawValue
                existingInvitation.actionRequired = obvDialog.actionRequired
            }
        } else {
            _ = try PersistedInvitation(obvDialog: obvDialog, forEntityName: PersistedInvitation.entityName, within: context)
        }
    }
    
    
    func delete() throws {
        guard let context = self.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        context.delete(self)
    }
    
}


// MARK: - Convenience DB getters

extension PersistedInvitation {
    
    struct Predicate {
        enum Key: String {
            case actionRequired = "actionRequired"
            case date = "date"
            case encodedObvDialog = "encodedObvDialog"
            case rawStatus = "rawStatus"
            case uuid = "uuid"
            case ownedIdentity = "ownedIdentity"
            static var ownedIdentityIdentity: String { [Key.ownedIdentity.rawValue, PersistedObvOwnedIdentity.Predicate.Key.identity.rawValue].joined(separator: ".") }
        }
        fileprivate static func withUUID(_ uuid: UUID) -> NSPredicate {
            NSPredicate(Key.uuid, EqualToUuid: uuid)
        }
        fileprivate static func withPersistedObvOwnedIdentity(_ ownedIdentity: PersistedObvOwnedIdentity) -> NSPredicate {
            NSPredicate(Key.ownedIdentity, equalTo: ownedIdentity)
        }
        fileprivate static func withStatus(_ status: Status) -> NSPredicate {
            NSPredicate(Key.rawStatus, EqualToInt: status.rawValue)
        }
        fileprivate static func withStatusDistinctFrom(_ status: Status) -> NSPredicate {
            NSPredicate(Key.rawStatus, DistinctFromInt: status.rawValue)
        }
        fileprivate static func withActionRequiredTo(_ value: Bool) -> NSPredicate {
            NSPredicate(Key.actionRequired, is: value)
        }
        static func withOwnedIdentity(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.ownedIdentityIdentity, EqualToData: ownedCryptoId.getIdentity())
        }
    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedInvitation> {
        return NSFetchRequest<PersistedInvitation>(entityName: PersistedInvitation.entityName)
    }


    static func getPersistedInvitation(uuid: UUID, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> PersistedInvitation? {
        let request: NSFetchRequest<PersistedInvitation> = PersistedInvitation.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedIdentity(ownedCryptoId),
            Predicate.withUUID(uuid),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    static func markAllAsOld(for ownedIdentity: PersistedObvOwnedIdentity) throws {
        guard let context = ownedIdentity.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        let request: NSFetchRequest<PersistedInvitation> = PersistedInvitation.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withPersistedObvOwnedIdentity(ownedIdentity),
            Predicate.withStatusDistinctFrom(.old),
        ])
        let results = try context.fetch(request)
        results.forEach { $0.rawStatus = Status.old.rawValue }
    }
    
    
    static func countInvitationsRequiringActionOrWithNotOldStatus(for ownedIdentity: PersistedObvOwnedIdentity) throws -> Int {
        guard let context = ownedIdentity.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        let request: NSFetchRequest<PersistedInvitation> = PersistedInvitation.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withPersistedObvOwnedIdentity(ownedIdentity),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                Predicate.withStatusDistinctFrom(.old),
                Predicate.withActionRequiredTo(true),
            ]),
        ])
        return try context.count(for: request)
    }
    
    
    static func countInvitationsRequiringActionOrWithNotOldStatusForAllOwnedIdentities(within context: NSManagedObjectContext) throws -> Int {
        let request: NSFetchRequest<PersistedInvitation> = PersistedInvitation.fetchRequest()
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            Predicate.withStatusDistinctFrom(.old),
            Predicate.withActionRequiredTo(true),
        ])
        return try context.count(for: request)
    }
    
    
    /// This returns all invitations, for all owned identities
    static func getAll(ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> [PersistedInvitation] {
        let request: NSFetchRequest<PersistedInvitation> = PersistedInvitation.fetchRequest()
        request.predicate = Predicate.withOwnedIdentity(ownedCryptoId)
        request.fetchBatchSize = 100
        return try context.fetch(request)
    }
    
    
    static func getAllForAllOwnedIdentities(within context: NSManagedObjectContext) throws -> [PersistedInvitation] {
        let request: NSFetchRequest<PersistedInvitation> = PersistedInvitation.fetchRequest()
        request.fetchBatchSize = 100
        return try context.fetch(request)
    }
    
    
    /// This returns all group invitations (both V1 and V2), for all owned identities
    static func getAllGroupInvitesForAllOwnedIdentities(within context: NSManagedObjectContext) throws -> [PersistedInvitation] {
        let invitations = try getAllForAllOwnedIdentities(within: context)
        let groupInvites = invitations.filter({
            guard let obvDialog = $0.obvDialog else { return false }
            switch obvDialog.category {
            case .acceptGroupInvite, .acceptGroupV2Invite:
                return true
            default:
                return false
            }
        })
        return groupInvites
    }

    
    /// This returns all group invitations, for all owned identities
    static func getAllGroupInvitesFromOneToOneContactsForAllOwnedIdentities(within context: NSManagedObjectContext) throws -> [PersistedInvitation] {
        let groupInvites = try getAllGroupInvitesForAllOwnedIdentities(within: context)
        let groupInvitesFromContacts = try groupInvites.filter { persistedInvitation in
            guard let ownedCryptoId = persistedInvitation.ownedIdentity?.cryptoId else { return false }
            guard let obvDialog = persistedInvitation.obvDialog else { return false }
            switch obvDialog.category {
            case .acceptGroupInvite(groupMembers: _, groupOwner: let groupOwner):
                let contact = try PersistedObvContactIdentity.get(contactCryptoId: groupOwner.cryptoId, ownedIdentityCryptoId: ownedCryptoId, whereOneToOneStatusIs: .oneToOne, within: context)
                return contact != nil
            default:
                return false
            }
        }
        return groupInvitesFromContacts
    }

}


// MARK: - NSFetchedResultsController

extension PersistedInvitation {
    
    static func getFetchedResultsControllerForOwnedIdentity(with ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedInvitation> {
        
        let request: NSFetchRequest<PersistedInvitation> = PersistedInvitation.fetchRequest()
        request.predicate = Predicate.withOwnedIdentity(ownedCryptoId)
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.date.rawValue, ascending: false)]
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
        defer { changedKeys.removeAll() }

        if !isDeleted {
            // We do *not* notify that the invitation has changed when the reason is that the invitation status changed from new or updated to old
            if !(changedKeys.contains(Predicate.Key.rawStatus.rawValue) && status == .old) {
                guard let obvDialog = self.obvDialog else { assertionFailure(); return }
                let notification = ObvMessengerCoreDataNotification.newOrUpdatedPersistedInvitation(obvDialog: obvDialog,
                                                                                                    persistedInvitationUUID: uuid)
                notification.postOnDispatchQueue()
            }
        }
        
    }
}
