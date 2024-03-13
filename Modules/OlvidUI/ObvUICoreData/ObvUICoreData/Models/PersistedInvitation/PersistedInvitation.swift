/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvSettings


@objc(PersistedInvitation)
public class PersistedInvitation: NSManagedObject {
    
    private static let entityName = "PersistedInvitation"
    private static let errorDomain = "PersistedInvitation"
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    // MARK: - Attributes
    
    @NSManaged public private(set) var actionRequired: Bool
    @NSManaged public private(set) var date: Date
    public private(set) var obvDialog: ObvDialog? {
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
    @NSManaged public private(set) var uuid: UUID
    
    
    // MARK: Relationships
    
    @NSManaged public private(set) var ownedIdentity: PersistedObvOwnedIdentity? // If nil, this entity is eventually cascade-deleted
    
    // MARK: Computed properties
    
    public var status: Status {
        let status = Status(rawValue: self.rawStatus)
        assert(status != nil)
        return status ?? .old
    }

    public enum Status: Int {
        case new = 0
        case updated = 1
        case old = 3
    }
    
    // MARK: Other variables
    
    private var changedKeys = Set<String>()

    
    /// Used when restoring a sync snapshot or when restoring a backup to prevent any notification on insertion
    private var isInsertedWhileRestoringSyncSnapshot = false

}


// MARK: - Initializer

extension PersistedInvitation {
    
    /// Shall only be called from subclasses
    convenience init(obvDialog: ObvDialog, isRestoringSyncSnapshotOrBackup: Bool, forEntityName entityName: String, within context: NSManagedObjectContext) throws {
        guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: obvDialog.ownedCryptoId, within: context) else {
            throw Self.makeError(message: "Could not find owned identity")
        }
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.isInsertedWhileRestoringSyncSnapshot = isRestoringSyncSnapshotOrBackup
        self.actionRequired = obvDialog.actionRequired
        self.uuid = obvDialog.uuid
        self.rawStatus = Status.new.rawValue
        self.obvDialog = obvDialog
        self.date = Date()
        self.ownedIdentity = ownedIdentity
        
        try self.ownedIdentity?.refreshBadgeCountForInvitationsTab()
    }
    
    
    private func setStatus(to newStatus: Status) {
        if self.status != newStatus {
            self.rawStatus = newStatus.rawValue
            do {
                try ownedIdentity?.refreshBadgeCountForInvitationsTab()
            } catch {
                assertionFailure("Failed to refreshBadgeCountForInvitationsTab: \(error.localizedDescription)")
            }
        }
    }
    
    
    private func setActionRequired(to newActionRequired: Bool) {
        if self.actionRequired != newActionRequired {
            self.actionRequired = newActionRequired
            do {
                try ownedIdentity?.refreshBadgeCountForInvitationsTab()
            } catch {
                assertionFailure("Failed to refreshBadgeCountForInvitationsTab: \(error.localizedDescription)")
            }
        }
    }
    
    
    public static func insertOrUpdate(_ obvDialog: ObvDialog, isRestoringSyncSnapshotOrBackup: Bool, within context: NSManagedObjectContext) throws {
        if let existingInvitation = try PersistedInvitation.getPersistedInvitation(uuid: obvDialog.uuid, ownedCryptoId: obvDialog.ownedCryptoId, within: context) {
            if existingInvitation.obvDialog != obvDialog {
                existingInvitation.obvDialog = obvDialog
                existingInvitation.date = Date()
                existingInvitation.setStatus(to: Status.updated)
                existingInvitation.setActionRequired(to: obvDialog.actionRequired)
            }
        } else {
            _ = try PersistedInvitation(obvDialog: obvDialog, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup, forEntityName: PersistedInvitation.entityName, within: context)
        }
    }
    
    
    public func delete() throws {
        guard let context = self.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        context.delete(self)
        do {
            try ownedIdentity?.refreshBadgeCountForInvitationsTab()
        } catch {
            assertionFailure("Failed to refreshBadgeCountForInvitationsTab: \(error.localizedDescription)")
        }
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
            static let ownedIdentityHiddenProfileHash = [Key.ownedIdentity.rawValue, PersistedObvOwnedIdentity.Predicate.Key.hiddenProfileHash.rawValue].joined(separator: ".")
            static let ownedIdentityHiddenProfileSalt = [Key.ownedIdentity.rawValue, PersistedObvOwnedIdentity.Predicate.Key.hiddenProfileSalt.rawValue].joined(separator: ".")
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
        static var ownedIdentityIsNotHidden: NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(withNonNilValueForKey: Key.ownedIdentity),
                NSPredicate(withNilValueForRawKey: Key.ownedIdentityHiddenProfileHash),
                NSPredicate(withNilValueForRawKey: Key.ownedIdentityHiddenProfileSalt),
            ])
        }
    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedInvitation> {
        return NSFetchRequest<PersistedInvitation>(entityName: PersistedInvitation.entityName)
    }


    public static func getPersistedInvitation(uuid: UUID, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> PersistedInvitation? {
        let request: NSFetchRequest<PersistedInvitation> = PersistedInvitation.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedIdentity(ownedCryptoId),
            Predicate.withUUID(uuid),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    public static func markAllAsOld(for ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<PersistedInvitation> = PersistedInvitation.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedIdentity(ownedCryptoId),
            Predicate.withStatusDistinctFrom(.old),
        ])
        request.propertiesToFetch = []
        let results = try context.fetch(request)
        results.forEach {
            $0.setStatus(to: Status.old)
        }
    }


    static func computeBadgeCountForInvitationsTab(of ownedIdentity: PersistedObvOwnedIdentity) throws -> Int {
        guard let context = ownedIdentity.managedObjectContext else { assertionFailure(); throw Self.makeError(message: "Could not find context") }
        let request: NSFetchRequest<PersistedInvitation> = PersistedInvitation.fetchRequest()
        let predicateOnInvitations = NSCompoundPredicate(orPredicateWithSubpredicates: [
            Predicate.withStatusDistinctFrom(.old),
            Predicate.withActionRequiredTo(true),
        ])
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            predicateOnInvitations,
            Predicate.withPersistedObvOwnedIdentity(ownedIdentity),
        ])
        return try context.count(for: request)
    }

    
    /// This returns all invitations, for all owned identities
    public static func getAll(ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> [PersistedInvitation] {
        let request: NSFetchRequest<PersistedInvitation> = PersistedInvitation.fetchRequest()
        request.predicate = Predicate.withOwnedIdentity(ownedCryptoId)
        request.fetchBatchSize = 100
        return try context.fetch(request)
    }
    
    
    public static func getAllForAllOwnedIdentities(within context: NSManagedObjectContext) throws -> [PersistedInvitation] {
        let request: NSFetchRequest<PersistedInvitation> = PersistedInvitation.fetchRequest()
        request.fetchBatchSize = 100
        return try context.fetch(request)
    }
    
    
    /// This returns all group invitations (both V1 and V2), for all owned identities
    public static func getAllGroupInvitesForAllOwnedIdentities(within context: NSManagedObjectContext) throws -> [PersistedInvitation] {
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
    public static func getAllGroupInvitesFromOneToOneContactsForAllOwnedIdentities(within context: NSManagedObjectContext) throws -> [PersistedInvitation] {
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
    
    public static func getFetchedResultsControllerForOwnedIdentity(with ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedInvitation> {
        
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
    
    public override func willSave() {
        super.willSave()
        changedKeys = Set<String>(self.changedValues().keys)
    }
    
    
    public override func didSave() {
        super.didSave()
        
        defer {
            changedKeys.removeAll()
            isInsertedWhileRestoringSyncSnapshot = false
        }

        guard !isInsertedWhileRestoringSyncSnapshot else {
            assert(isInserted)
            let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: String(describing: Self.self))
            os_log("Insertion of a PersistedInvitation during a snapshot restore --> we don't send any notification", log: log, type: .info)
            return
        }

        if !isDeleted {
            // We do *not* notify that the invitation has changed when the reason is that the invitation status changed from new or updated to old
            if !(changedKeys.contains(Predicate.Key.rawStatus.rawValue) && status == .old) {
                guard let obvDialog = self.obvDialog else { assertionFailure(); return }
                guard let concernedOwnedIdentityIsHidden = ownedIdentity?.isHidden else { assertionFailure(); return }
                let notification = ObvMessengerCoreDataNotification.newOrUpdatedPersistedInvitation(
                    concernedOwnedIdentityIsHidden: concernedOwnedIdentityIsHidden,
                    obvDialog: obvDialog,
                    persistedInvitationUUID: uuid)
                notification.postOnDispatchQueue()
            }
        }
        
    }
}
