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
import OlvidUtils
import ObvTypes


@objc(PersistedGroupV2Discussion)
public final class PersistedGroupV2Discussion: PersistedDiscussion, ObvErrorMaker, ObvIdentifiableManagedObject {
    
    public static let entityName = "PersistedGroupV2Discussion"
    public static let errorDomain = "PersistedGroupV2Discussion"
    
    private static let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedGroupV2Discussion")

    // Attributes
    
    @NSManaged public private(set) var groupIdentifier: Data // Part of the group primary key
    @NSManaged private var rawOwnedIdentityIdentity: Data // Part of the group primary key

    // Relationships

    @NSManaged private var rawGroupV2: PersistedGroupV2?
    
    // Accessors
    
    public private(set) var group: PersistedGroupV2? {
        get {
            return rawGroupV2
        }
        set {
            guard rawGroupV2 == nil else { assertionFailure("Can be set only once"); return }
            guard let newValue = newValue else { assertionFailure("Cannot be set to nil"); return }
            self.rawGroupV2 = newValue
        }
    }

    public var objectPermanentID: ObvManagedObjectPermanentID<PersistedGroupV2Discussion> {
        ObvManagedObjectPermanentID<PersistedGroupV2Discussion>(uuid: self.permanentUUID)
    }

    // Initializer

    public convenience init(persistedGroupV2: PersistedGroupV2, shouldApplySharedConfigurationFromGlobalSettings: Bool, sharedConfigurationToKeep: PersistedDiscussionSharedConfiguration? = nil, localConfigurationToKeep: PersistedDiscussionLocalConfiguration? = nil, permanentUUIDToKeep: UUID? = nil, draftToKeep: PersistedDraft? = nil, pinnedIndexToKeep: Int? = nil, timestampOfLastMessageToKeep: Date? = nil) throws {
        
        guard let context = persistedGroupV2.managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        
        guard let persistedOwnedIdentity = persistedGroupV2.persistedOwnedIdentity else {
            throw Self.makeError(message: "Could not find owned identity")
        }
        
        guard persistedOwnedIdentity.managedObjectContext == context else {
            throw Self.makeError(message: "Unexpected context")
        }
        
        try self.init(title: persistedGroupV2.displayName,
                      ownedIdentity: persistedOwnedIdentity,
                      forEntityName: PersistedGroupV2Discussion.entityName,
                      status: .active,
                      shouldApplySharedConfigurationFromGlobalSettings: shouldApplySharedConfigurationFromGlobalSettings,
                      sharedConfigurationToKeep: sharedConfigurationToKeep,
                      localConfigurationToKeep: localConfigurationToKeep,
                      permanentUUIDToKeep: permanentUUIDToKeep,
                      draftToKeep: draftToKeep,
                      pinnedIndexToKeep: pinnedIndexToKeep,
                      timestampOfLastMessageToKeep: timestampOfLastMessageToKeep)

        self.groupIdentifier = persistedGroupV2.groupIdentifier
        self.rawOwnedIdentityIdentity = try persistedGroupV2.ownCryptoId.getIdentity()

        self.group = persistedGroupV2
        
        try? insertSystemMessagesIfDiscussionIsEmpty(markAsRead: false, messageTimestamp: timestampOfLastMessageToKeep ?? Date())

    }
    
    
    // MARK: - Status management
    
    override func setStatus(to newStatus: PersistedDiscussion.Status) throws {
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

    
    // MARK: - Inserting system messages on group members updates
    
    /// Called by the associated group when the members are updated. This method inserts an appropriate system message in the group discussion.
    func groupMembersWereUpdated() throws {
        try PersistedMessageSystem.insertMembersOfGroupV2WereUpdatedSystemMessage(within: self)
    }
    
    
    func ownedIdentityBecameAnAdmin() throws {
        try PersistedMessageSystem.insertOwnedIdentityIsPartOfGroupV2AdminsMessage(within: self)
    }
    

    func ownedIdentityIsNoLongerAnAdmin() throws {
        try PersistedMessageSystem.insertOwnedIdentityIsNoLongerPartOfGroupV2AdminsMessage(within: self)
    }
    

    // MARK: - Convenience DB getters

    struct Predicate {
        enum Key: String {
            case groupIdentifier = "groupIdentifier"
            case rawOwnedIdentityIdentity = "rawOwnedIdentityIdentity"
        }
        static func withGroupIdentifier(_ groupIdentifier: Data) -> NSPredicate {
            NSPredicate(Key.groupIdentifier, EqualToData: groupIdentifier)
        }
        static func withOwnCryptoId(_ ownCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentityIdentity, EqualToData: ownCryptoId.getIdentity())
        }
    }
    
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedGroupV2Discussion> {
        return NSFetchRequest<PersistedGroupV2Discussion>(entityName: PersistedGroupV2Discussion.entityName)
    }

    
    static func getPersistedGroupV2Discussion(groupIdentifier: Data, ownCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> PersistedGroupV2Discussion? {
        let request: NSFetchRequest<PersistedGroupV2Discussion> = PersistedGroupV2Discussion.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withGroupIdentifier(groupIdentifier),
            Predicate.withOwnCryptoId(ownCryptoId),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
        
}


// MARK: - Downcasting the typed object ID of a PersistedGroupV2Discussion

public extension TypeSafeManagedObjectID where T == PersistedGroupV2Discussion {
    var downcast: TypeSafeManagedObjectID<PersistedDiscussion> {
        TypeSafeManagedObjectID<PersistedDiscussion>(objectID: objectID)
    }
}