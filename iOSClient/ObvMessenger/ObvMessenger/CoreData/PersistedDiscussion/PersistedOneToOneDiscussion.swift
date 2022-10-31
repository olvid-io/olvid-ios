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
import OlvidUtils
import ObvCrypto
import ObvTypes


@objc(PersistedOneToOneDiscussion)
final class PersistedOneToOneDiscussion: PersistedDiscussion, ObvErrorMaker {
    
    private static let entityName = "PersistedOneToOneDiscussion"
    static let errorDomain = "PersistedOneToOneDiscussion"
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedOneToOneDiscussion")

    // Attributes
    
    @NSManaged private var rawContactIdentityIdentity: Data? // Keeps track of the bytes of the contact, making it possible to unlock a discussion

    // Relationships

    @NSManaged private var rawContactIdentity: PersistedObvContactIdentity? // If nil, this entity is eventually cascade-deleted
    
    // Accessors
    
    private(set) var contactIdentity: PersistedObvContactIdentity? {
        get {
            return rawContactIdentity
        }
        set {
            if let newValue = newValue {
                assert(self.rawContactIdentityIdentity == nil || self.rawContactIdentityIdentity == newValue.identity)
                self.rawContactIdentityIdentity = newValue.identity
            }
            self.rawContactIdentity = newValue
        }
    }

    
    // MARK: - Initializer
    
    convenience init(contactIdentity: PersistedObvContactIdentity, status: Status, insertDiscussionIsEndToEndEncryptedSystemMessage: Bool = true, sharedConfigurationToKeep: PersistedDiscussionSharedConfiguration? = nil, localConfigurationToKeep: PersistedDiscussionLocalConfiguration? = nil) throws {
        guard let ownedIdentity = contactIdentity.ownedIdentity else {
            os_log("Could not find owned identity. This is ok if it was just deleted.", log: PersistedOneToOneDiscussion.log, type: .error)
            throw Self.makeError(message: "Could not find owned identity. This is ok if it was just deleted.")
        }
        try self.init(title: contactIdentity.nameForSettingOneToOneDiscussionTitle,
                      ownedIdentity: ownedIdentity,
                      forEntityName: PersistedOneToOneDiscussion.entityName,
                      status: status,
                      shouldApplySharedConfigurationFromGlobalSettings: true,
                      sharedConfigurationToKeep: sharedConfigurationToKeep,
                      localConfigurationToKeep: localConfigurationToKeep)

        self.contactIdentity = contactIdentity

        if insertDiscussionIsEndToEndEncryptedSystemMessage {
            try? insertSystemMessagesIfDiscussionIsEmpty(markAsRead: false)
        }

    }
    
    
    // MARK: - Status management
    
    override func setStatus(to newStatus: PersistedDiscussion.Status) throws {
        guard self.status != newStatus else { return }
        // Insert the appropriate system message in the group discussion
        switch (self.status, newStatus) {
        case (.locked, .active):
            try PersistedMessageSystem.insertContactIsOneToOneAgainSystemMessage(within: self)
        default:
            break
        }
        try super.setStatus(to: newStatus)
        if newStatus == .locked {
            _ = try PersistedMessageSystem(.contactWasDeleted,
                                           optionalContactIdentity: nil,
                                           optionalCallLogItem: nil,
                                           discussion: self)
        }
    }
        
}


// MARK: - Thread safe struct

extension PersistedOneToOneDiscussion {
    
    struct Structure {
        let typedObjectID: TypeSafeManagedObjectID<PersistedOneToOneDiscussion>
        let contactIdentity: Data
        fileprivate let discussionStruct: PersistedDiscussion.AbstractStructure
        var title: String { discussionStruct.title }
        var localConfiguration: PersistedDiscussionLocalConfiguration.Structure { discussionStruct.localConfiguration }
    }
    
    func toStruct() throws -> Structure {
        guard let contactIdentity = self.rawContactIdentityIdentity else {
            assertionFailure()
            throw Self.makeError(message: "Could not extract required attributes")
        }
        let discussionStruct = try toAbstractStruct()
        return Structure(typedObjectID: self.typedObjectID,
                         contactIdentity: contactIdentity,
                         discussionStruct: discussionStruct)
    }
    
}


// MARK: - NSFetchRequest

extension PersistedOneToOneDiscussion {
    
    struct Predicate {
        enum Key: String {
            case rawContactIdentityIdentity = "rawContactIdentityIdentity"
            case rawContactIdentity = "rawContactIdentity"
            static var ownedIdentityIdentity: String {
                [PersistedDiscussion.Predicate.Key.ownedIdentity.rawValue, PersistedObvOwnedIdentity.identityKey].joined(separator: ".")
            }
        }
        static func withContactCryptoId(_ cryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawContactIdentityIdentity, EqualToData: cryptoId.getIdentity())
        }
        static func withContactIdentity(_ contact: PersistedObvContactIdentity) -> NSPredicate {
            NSPredicate(Key.rawContactIdentity, equalTo: contact)
        }
        static func withOwnedCryptoId(_ ownCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.ownedIdentityIdentity, EqualToData: ownCryptoId.getIdentity())
        }
    }
    
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedOneToOneDiscussion> {
        return NSFetchRequest<PersistedOneToOneDiscussion>(entityName: PersistedOneToOneDiscussion.entityName)
    }
    
    
    /// Returns a `NSFetchRequest` for all the one-tone discussions of the owned identity, sorted by the discussion title.
    static func getFetchRequestForAllActiveOneToOneDiscussionsSortedByTitleForOwnedIdentity(with ownedCryptoId: ObvCryptoId) -> NSFetchRequest<PersistedDiscussion> {
        let request: NSFetchRequest<PersistedDiscussion> = NSFetchRequest<PersistedDiscussion>(entityName: PersistedOneToOneDiscussion.entityName)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoId(ownedCryptoId),
            PersistedDiscussion.Predicate.withStatus(.active),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: PersistedDiscussion.Predicate.Key.title.rawValue, ascending: true)]
        return request
    }


    /// This method returns a `PersistedOneToOneDiscussion` if one can be found and `nil` otherwise.
    /// If `status` is non-nil, the returned discussion will have this specific status.
    static func get(with contact: PersistedObvContactIdentity, status: Status?) throws -> PersistedOneToOneDiscussion? {
        guard let context = contact.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        let request: NSFetchRequest<PersistedOneToOneDiscussion> = PersistedOneToOneDiscussion.fetchRequest()
        var predicates = [Predicate.withContactIdentity(contact)]
        if let status = status {
            predicates.append(PersistedDiscussion.Predicate.withStatus(status))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.fetchLimit = 1
        return (try context.fetch(request)).first
    }
    
    
    /// This method returns a `PersistedOneToOneDiscussion` if one can be found and `nil` otherwise.
    static func getWithContactCryptoId(_ contact: ObvCryptoId, ofOwnedCryptoId ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> PersistedOneToOneDiscussion? {
        let request: NSFetchRequest<PersistedOneToOneDiscussion> = PersistedOneToOneDiscussion.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withContactCryptoId(contact),
            Predicate.withOwnedCryptoId(ownedCryptoId),
        ])
        request.fetchLimit = 1
        return (try context.fetch(request)).first
    }

}

extension TypeSafeManagedObjectID where T == PersistedOneToOneDiscussion {
    var downcast: TypeSafeManagedObjectID<PersistedDiscussion> {
        TypeSafeManagedObjectID<PersistedDiscussion>(objectID: objectID)
    }
}
