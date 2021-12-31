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

@objc(PersistedOneToOneDiscussion)
final class PersistedOneToOneDiscussion: PersistedDiscussion {
    
    private static let entityName = "PersistedOneToOneDiscussion"
    private static let contactIdentityKey = "contactIdentity"
    private static let errorDomain = "PersistedOneToOneDiscussion"
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedOneToOneDiscussion")
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedOneToOneDiscussion")

    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    // MARK: - Attributes

    // MARK: - Relationships

    @NSManaged private(set) var contactIdentity: PersistedObvContactIdentity? // If nil, this entity is eventually cascade-deleted
    
}


// MARK: - Initializer

extension PersistedOneToOneDiscussion {
    
    convenience init?(contactIdentity: PersistedObvContactIdentity, insertDiscussionIsEndToEndEncryptedSystemMessage: Bool = true, sharedConfigurationToKeep: PersistedDiscussionSharedConfiguration? = nil, localConfigurationToKeep: PersistedDiscussionLocalConfiguration? = nil) {
        guard let ownedIdentity = contactIdentity.ownedIdentity else {
            os_log("Could not find owned identity. This is ok if it was just deleted.", log: PersistedOneToOneDiscussion.log, type: .error)
            return nil
        }
        self.init(title: contactIdentity.nameForSettingOneToOneDiscussionTitle,
                  ownedIdentity: ownedIdentity,
                  forEntityName: PersistedOneToOneDiscussion.entityName,
                  sharedConfigurationToKeep: sharedConfigurationToKeep,
                  localConfigurationToKeep: localConfigurationToKeep)
        
        self.contactIdentity = contactIdentity
        
        if insertDiscussionIsEndToEndEncryptedSystemMessage {
            try? insertSystemMessagesIfDiscussionIsEmpty(markAsRead: false)
        }

    }
    
}

// MARK: - Other methods

extension PersistedOneToOneDiscussion {
    
    func hasAtLeastOneRemoteContactDevice() -> Bool {
        guard let contactIdentity = self.contactIdentity else {
            os_log("Could not find contact identity. This is ok if it has just been deleted.", log: log, type: .error)
            return false
        }
        return !contactIdentity.devices.isEmpty
    }
    
}

// MARK: - NSFetchRequest

extension PersistedOneToOneDiscussion {
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedOneToOneDiscussion> {
        return NSFetchRequest<PersistedOneToOneDiscussion>(entityName: PersistedOneToOneDiscussion.entityName)
    }


    /// Returns a `NSFetchRequest` for all the one-tone discussions of the owned identity, sorted by the discussion title.
    static func getFetchRequestForAllOneToOneDiscussionsSortedByTitleForOwnedIdentity(with ownedCryptoId: ObvCryptoId) -> NSFetchRequest<PersistedDiscussion> {
        
        let fetchRequest: NSFetchRequest<PersistedDiscussion> = NSFetchRequest<PersistedDiscussion>(entityName: PersistedOneToOneDiscussion.entityName)
        
        fetchRequest.predicate = NSPredicate(format: "%K == %@",
                                             ownedIdentityIdentityKey, ownedCryptoId.getIdentity() as NSData)
        
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: PersistedDiscussion.titleKey, ascending: true)]

        return fetchRequest
    }


    /// This method always returns a `PersistedOneToOneDiscussion` since it creates it if required. As a consequence, it cannot be called
    /// on the view context.
    static func getOrCreate(with contact: PersistedObvContactIdentity) throws -> PersistedOneToOneDiscussion {
        guard let context = contact.managedObjectContext else { throw makeError(message: "Cannot find context") }
        assert(context != ObvStack.shared.viewContext)
        var discussion: PersistedOneToOneDiscussion? = nil
        do {
            let request: NSFetchRequest<PersistedOneToOneDiscussion> = PersistedOneToOneDiscussion.fetchRequest()
            request.predicate = NSPredicate(format: "%K == %@", PersistedOneToOneDiscussion.contactIdentityKey, contact)
            request.fetchLimit = 1
            discussion = (try context.fetch(request)).first
        }
        if discussion == nil {
            discussion = PersistedOneToOneDiscussion(contactIdentity: contact)
        }
        guard let returnedDiscussion = discussion else { throw makeError(message: "Cannot find discussion") }
        return returnedDiscussion
    }

    /// This method returs a `PersistedOneToOneDiscussion` if it can be found, and `nil` otherwise.
    static func get(with contact: PersistedObvContactIdentity) throws -> PersistedOneToOneDiscussion? {
        guard let context = contact.managedObjectContext else { throw NSError() }
        let request: NSFetchRequest<PersistedOneToOneDiscussion> = PersistedOneToOneDiscussion.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", PersistedOneToOneDiscussion.contactIdentityKey, contact)
        request.fetchLimit = 1
        return (try context.fetch(request)).first
    }
    
}

extension TypeSafeManagedObjectID where T == PersistedOneToOneDiscussion {
    var downcast: TypeSafeManagedObjectID<PersistedDiscussion> {
        TypeSafeManagedObjectID<PersistedDiscussion>(objectID: objectID)
    }
}
