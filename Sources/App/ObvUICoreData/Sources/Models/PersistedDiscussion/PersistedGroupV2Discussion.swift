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
import OlvidUtils
import ObvTypes
import ObvSettings


@objc(PersistedGroupV2Discussion)
public final class PersistedGroupV2Discussion: PersistedDiscussion, ObvIdentifiableManagedObject {
    
    public static let entityName = "PersistedGroupV2Discussion"
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

    /// Expected to be non-nil, unless this `NSManagedObject` is deleted.
    public var objectPermanentID: ObvManagedObjectPermanentID<PersistedGroupV2Discussion> {
        get throws {
            guard self.managedObjectContext != nil else { assertionFailure(); throw ObvUICoreDataError.noContext }
            return ObvManagedObjectPermanentID<PersistedGroupV2Discussion>(uuid: self.permanentUUID)
        }
    }
    
    
    /// Expected to be non-nil
    public var obvGroupIdentifier: ObvGroupV2Identifier? {
        guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedIdentityIdentity) else { assertionFailure(); return nil }
        guard let identifier = ObvGroupV2.Identifier(appGroupIdentifier: groupIdentifier) else { assertionFailure(); return nil }
        return ObvGroupV2Identifier(ownedCryptoId: ownedCryptoId, identifier: identifier)
    }

    // Initializer

    public convenience init(persistedGroupV2: PersistedGroupV2, shouldApplySharedConfigurationFromGlobalSettings: Bool, isRestoringSyncSnapshotOrBackup: Bool) throws {
        
        guard let context = persistedGroupV2.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        
        guard let persistedOwnedIdentity = persistedGroupV2.persistedOwnedIdentity else {
            throw ObvUICoreDataError.ownedIdentityIsNil
        }
        
        guard persistedOwnedIdentity.managedObjectContext == context else {
            assertionFailure()
            throw ObvUICoreDataError.inappropriateContext
        }
        
        try self.init(title: persistedGroupV2.displayName,
                      ownedIdentity: persistedOwnedIdentity,
                      forEntityName: PersistedGroupV2Discussion.entityName,
                      status: .active,
                      shouldApplySharedConfigurationFromGlobalSettings: shouldApplySharedConfigurationFromGlobalSettings,
                      isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)

        self.groupIdentifier = persistedGroupV2.groupIdentifier
        self.rawOwnedIdentityIdentity = try persistedGroupV2.ownCryptoId.getIdentity()

        self.group = persistedGroupV2
        
        try? insertSystemMessagesIfDiscussionIsEmpty(markAsRead: false, messageTimestamp: Date())

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

    
    // MARK: - Processing discussion (all messages) remote delete requests from a contact

    /// Exclusively called from ``PersistedGroupV2.processRemoteRequestToWipeAllMessagesWithinThisGroupDiscussion(from:messageUploadTimestampFromServer:)``, where we make sure that the contact is allowed to perform this request.
    func processRemoteRequestToWipeAllMessagesWithinThisDiscussion(from contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date) throws {

        switch self.status {
            
        case .locked:
            
            throw ObvUICoreDataError.aContactCannotDeleteAllMessagesWithinLockedDiscussion
            
        case .preDiscussion:
            
            throw ObvUICoreDataError.aContactCannotDeleteAllMessagesWithinPreDiscussion
            
        case .active:
            
            guard !self.messages.isEmpty else {
                return
            }
            
            self.removeAllMessages(messageUploadTimestampFromServer: messageUploadTimestampFromServer)

            do {
                try self.insertSystemMessagesIfDiscussionIsEmpty(markAsRead: false, messageTimestamp: messageUploadTimestampFromServer)
                _ = try PersistedMessageSystem(.discussionWasRemotelyWiped, optionalContactIdentity: contact, optionalOwnedCryptoId: nil, optionalCallLogItem: nil, discussion: self, timestamp: messageUploadTimestampFromServer)
            } catch {
                assertionFailure(error.localizedDescription)
            }
            
        }

    }

    
    // MARK: - Inserting system messages on group members updates
    
    func groupMemberHasJoined(_ memberIdentity: PersistedObvContactIdentity) throws {
        try PersistedMessageSystem.insertMemberOfGroupV2HasJoinedSystemMessage(within: self, memberIdentity: memberIdentity)
    }
    
    func groupMemberHasLeft(_ memberIdentity: PersistedObvContactIdentity) throws {
        try PersistedMessageSystem.insertMemberOfGroupV2HasLeftSystemMessage(within: self, memberIdentity: memberIdentity)
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
        static func withObjectID(_ objectID: NSManagedObjectID) -> NSPredicate {
            PersistedDiscussion.Predicate.persistedDiscussion(withObjectID: objectID)
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
    
    
    static func deleteLockedPersistedGroupV2Discussion(ownedIdentity: PersistedObvOwnedIdentity, groupIdentifier: GroupV2Identifier) throws {
        guard let discussion = try getPersistedGroupV2Discussion(ownedIdentity: ownedIdentity, groupV2DiscussionId: .groupV2Identifier(groupV2Identifier: groupIdentifier)) else {
            return
        }
        switch discussion.status {
        case .preDiscussion, .active:
            throw ObvUICoreDataError.discussionIsNotLocked
        case .locked:
            try discussion.deletePersistedDiscussion()
        }
    }
        
    
    static func getPersistedGroupV2Discussion(ownedIdentity: PersistedObvOwnedIdentity, groupV2DiscussionId: GroupV2DiscussionIdentifier) throws -> PersistedGroupV2Discussion? {
        guard let context = ownedIdentity.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let request: NSFetchRequest<PersistedGroupV2Discussion> = PersistedGroupV2Discussion.fetchRequest()
        switch groupV2DiscussionId {
        case .objectID(let objectID):
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withObjectID(objectID),
                Predicate.withOwnCryptoId(ownedIdentity.cryptoId),
            ])
        case .groupV2Identifier(groupV2Identifier: let groupV2Identifier):
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withOwnCryptoId(ownedIdentity.cryptoId),
                Predicate.withGroupIdentifier(groupV2Identifier),
            ])
        }
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
