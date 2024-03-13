/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvCrypto
import OlvidUtils
import ObvSettings


@objc(PersistedGroupDiscussion)
public final class PersistedGroupDiscussion: PersistedDiscussion, ObvErrorMaker, ObvIdentifiableManagedObject {
    
    public static let entityName = "PersistedGroupDiscussion"
    public static let errorDomain = "PersistedGroupDiscussion"
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedGroupDiscussion")
    
    // MARK: Attributes
    
    @NSManaged public var rawGroupUID: Data?
    @NSManaged private var rawOwnerIdentityIdentity: Data?

    // MARK: Relationships

    @NSManaged private var rawContactGroup: PersistedContactGroup? // Nil if we left the group
    
    // MARK: Other variables
    
    public private(set) var contactGroup: PersistedContactGroup? {
        get {
            return rawContactGroup
        }
        set {
            guard rawContactGroup == nil else { assertionFailure("Can be set only once"); return }
            guard let newValue = newValue else { assertionFailure("Cannot be set to nil"); return }
            self.rawGroupUID = newValue.groupUid.raw
            self.rawOwnerIdentityIdentity = newValue.ownerIdentity
            self.rawContactGroup = newValue
        }
    }


    public var objectPermanentID: ObvManagedObjectPermanentID<PersistedGroupDiscussion> {
        ObvManagedObjectPermanentID<PersistedGroupDiscussion>(uuid: self.permanentUUID)
    }

    // MARK: - Initializer
    
    public convenience init(contactGroup: PersistedContactGroup, groupName: String, ownedIdentity: PersistedObvOwnedIdentity, status: Status, isRestoringSyncSnapshotOrBackup: Bool) throws {
        try self.init(title: groupName,
                      ownedIdentity: ownedIdentity,
                      forEntityName: PersistedGroupDiscussion.entityName,
                      status: status,
                      shouldApplySharedConfigurationFromGlobalSettings: contactGroup.category == .owned,
                      isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)
        self.contactGroup = contactGroup
        if contactGroup.category == .owned {
            self.sharedConfiguration.setValuesUsingSettings()
        }

        try? insertSystemMessagesIfDiscussionIsEmpty(markAsRead: false, messageTimestamp: Date())
    }

    
    // MARK: - Status management
    
    public override func setStatus(to newStatus: PersistedDiscussion.Status) throws {
        guard self.status != newStatus else { return }
        // Insert the appropriate system message in the group discussion
        switch (self.status, newStatus) {
        case (_, .active):
            try PersistedMessageSystem.insertRejoinedGroupSystemMessage(within: self)
        case (.active, .locked):
            try PersistedMessageSystem.insertNotPartOfTheGroupAnymoreSystemMessage(within: self)
            // In that case, we also reset the `PersistedLatestDiscussionSenderSequenceNumber` of all participants
            try PersistedLatestDiscussionSenderSequenceNumber.deleteAllForDiscussion(self)
        default:
            break
        }
        try super.setStatus(to: newStatus)
    }

}


// MARK: - Convenience DB getters

extension PersistedGroupDiscussion {
    
    struct Predicate {
        enum Key: String {
            case rawGroupUID = "rawGroupUID"
            case rawOwnerIdentityIdentity = "rawOwnerIdentityIdentity"
            case rawContactGroup = "rawContactGroup"
            static var rawContactGroupContactIdentities: String {
                [Key.rawContactGroup.rawValue, PersistedContactGroup.Predicate.Key.contactIdentities.rawValue].joined(separator: ".")
            }
        }
        static func withGroupUID(_ groupUID: UID) -> NSPredicate {
            NSPredicate(Key.rawGroupUID, EqualToData: groupUID.raw)
        }
        static func withGroupOwnerCryptoId(_ groupOwnerCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawOwnerIdentityIdentity, EqualToData: groupOwnerCryptoId.getIdentity())
        }
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(PersistedDiscussion.Predicate.Key.ownedIdentityIdentity, EqualToData: ownedCryptoId.getIdentity())
        }
        static func withObjectID(_ objectID: NSManagedObjectID) -> NSPredicate {
            PersistedDiscussion.Predicate.persistedDiscussion(withObjectID: objectID)
        }
        static func withGroupV1Identifier(_ groupV1Identifier: GroupV1Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withGroupUID(groupV1Identifier.groupUid),
                withGroupOwnerCryptoId(groupV1Identifier.groupOwner),
            ])
        }
    }

    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedGroupDiscussion> {
        return NSFetchRequest<PersistedGroupDiscussion>(entityName: PersistedGroupDiscussion.entityName)
    }

    
    static func getGroupDiscussion(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedGroupDiscussion? {
        return try context.existingObject(with: objectID) as? PersistedGroupDiscussion
    }
    
    
    static func getWithGroupUID(_ groupUID: UID, groupOwnerCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> PersistedGroupDiscussion? {
        let request: NSFetchRequest<PersistedGroupDiscussion> = NSFetchRequest<PersistedGroupDiscussion>(entityName: PersistedGroupDiscussion.entityName)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withGroupUID(groupUID),
            Predicate.withGroupOwnerCryptoId(groupOwnerCryptoId),
            Predicate.withOwnedCryptoId(ownedCryptoId),
        ])
        request.fetchLimit = 1
        return (try context.fetch(request)).first
    }
    
    static func getPersistedGroupDiscussion(ownedIdentity: PersistedObvOwnedIdentity, groupV1DiscussionId: GroupV1DiscussionIdentifier) throws -> PersistedGroupDiscussion? {
        guard let context = ownedIdentity.managedObjectContext else { assertionFailure(); throw ObvError.noContext }
        let request: NSFetchRequest<PersistedGroupDiscussion> = PersistedGroupDiscussion.fetchRequest()
        switch groupV1DiscussionId {
        case .objectID(let objectID):
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withObjectID(objectID),
                Predicate.withOwnedCryptoId(ownedIdentity.cryptoId),
            ])
        case .groupV1Identifier(groupV1Identifier: let groupV1Identifier):
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withOwnedCryptoId(ownedIdentity.cryptoId),
                Predicate.withGroupV1Identifier(groupV1Identifier),
            ])
        }
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

}

public extension TypeSafeManagedObjectID where T == PersistedGroupDiscussion {
    var downcast: TypeSafeManagedObjectID<PersistedDiscussion> {
        TypeSafeManagedObjectID<PersistedDiscussion>(objectID: objectID)
    }
}
