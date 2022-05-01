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

@objc(PersistedGroupDiscussion)
final class PersistedGroupDiscussion: PersistedDiscussion {
    
    static let entityName = "PersistedGroupDiscussion"
    private static let contactGroupKey = "contactGroup"
    private static let contactGroupcontactIdentitiesKey = [contactGroupKey, PersistedContactGroup.contactIdentitiesKey].joined(separator: ".")
    private static let errorDomain = "PersistedGroupDiscussion"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedGroupDiscussion")

    // MARK: - Relationships

    @NSManaged var contactGroup: PersistedContactGroup? // If nil, this entity is eventually cascade-deleted
    
}


// MARK: - Initializer

extension PersistedGroupDiscussion {
    
    convenience init(contactGroup: PersistedContactGroup, groupName: String, ownedIdentity: PersistedObvOwnedIdentity, insertDiscussionIsEndToEndEncryptedSystemMessage: Bool = true, sharedConfigurationToKeep: PersistedDiscussionSharedConfiguration? = nil, localConfigurationToKeep: PersistedDiscussionLocalConfiguration? = nil) throws {
        try self.init(title: groupName,
                      ownedIdentity: ownedIdentity,
                      forEntityName: PersistedGroupDiscussion.entityName,
                      sharedConfigurationToKeep: sharedConfigurationToKeep,
                      localConfigurationToKeep: localConfigurationToKeep)
        self.contactGroup = contactGroup
        if sharedConfigurationToKeep == nil && contactGroup.category == .owned {
            self.sharedConfiguration.setValuesUsingSettings()
        }

        if insertDiscussionIsEndToEndEncryptedSystemMessage {
            try? insertSystemMessagesIfDiscussionIsEmpty(markAsRead: false)
        }
    }

}


// MARK: - Other methods

extension PersistedGroupDiscussion {
    
    func hasAtLeastOneRemoteContactDevice() -> Bool {
        debugPrint(self.managedObjectContext!.shouldDeleteInaccessibleFaults)
        guard let contactGroup = self.contactGroup else {
            os_log("The contactGroup relationship is nil. This is ok if the contact group has just been deleted.", log: log, type: .error)
            return false
        }
        for contact in contactGroup.contactIdentities {
            if !contact.devices.isEmpty {
                return true
            }
        }
        return false
    }
    
}


// MARK: - Convenience DB getters

extension PersistedGroupDiscussion {
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedGroupDiscussion> {
        return NSFetchRequest<PersistedGroupDiscussion>(entityName: PersistedGroupDiscussion.entityName)
    }

    
    /// Returns a `NSFetchRequest` for all the group discussions of the owned identity, sorted by the discussion title.
    static func getFetchRequestForAllGroupDiscussionsSortedByTitleForOwnedIdentity(with ownedCryptoId: ObvCryptoId) -> NSFetchRequest<PersistedDiscussion> {
        
        let fetchRequest: NSFetchRequest<PersistedDiscussion> = NSFetchRequest<PersistedDiscussion>(entityName: PersistedGroupDiscussion.entityName)
        
        fetchRequest.predicate = NSPredicate(format: "%K == %@",
                                             ownedIdentityIdentityKey, ownedCryptoId.getIdentity() as NSData)
        
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: PersistedDiscussion.titleKey, ascending: true)]

        return fetchRequest
    }

    
    static func getGroupDiscussion(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedGroupDiscussion? {
        return try context.existingObject(with: objectID) as? PersistedGroupDiscussion
    }
    
}

extension TypeSafeManagedObjectID where T == PersistedGroupDiscussion {
    var downcast: TypeSafeManagedObjectID<PersistedDiscussion> {
        TypeSafeManagedObjectID<PersistedDiscussion>(objectID: objectID)
    }
}
