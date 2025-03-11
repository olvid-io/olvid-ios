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
import ObvCrypto
import ObvEngine


@objc(PersistedMessageReaction)
public class PersistedMessageReaction: NSManagedObject {

    private static let entityName = "PersistedMessageReaction"

    // MARK: Attributes

    @NSManaged private var rawEmoji: String?
    @NSManaged public private(set) var timestamp: Date

    // MARK: Relationships

    @NSManaged public var message: PersistedMessage?

    // MARK: Other variables
    
    public var emoji: String? {
        return self.rawEmoji
    }
    
    // MARK: - Initializer
    
    fileprivate convenience init(emoji: String?, timestamp: Date, message: PersistedMessage, forEntityName entityName: String) throws {

        guard let context = message.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.rawEmoji = emoji
        self.timestamp = timestamp
        self.message = message
    }
    
    
    func updateEmoji(with newEmoji: String, at newTimestamp: Date) throws {
        
        guard self.timestamp < newTimestamp else { return }
        
        guard newEmoji.count == 1 else { assertionFailure(); throw ObvUICoreDataError.invalidEmoji }
        if self.rawEmoji != newEmoji {
            self.rawEmoji = newEmoji
        }
        if self.timestamp != newTimestamp {
            self.timestamp = newTimestamp
        }
    }
    
    
    func delete() throws {
        guard let context = self.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        context.delete(self)
    }
    
}

// MARK: - Convenience DB getters

extension PersistedMessageReaction {

    fileprivate struct Predicate {
        enum Key: String {
            case rawEmoji = "rawEmoji"
        }
        static func withObjectID(_ objectID: TypeSafeManagedObjectID<PersistedMessageReaction>) -> NSPredicate {
            NSPredicate(withObjectID: objectID.objectID)
        }
    }

    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PersistedMessageReaction> {
        return NSFetchRequest<PersistedMessageReaction>(entityName: entityName)
    }

    
    public static func get(with objectID: TypeSafeManagedObjectID<PersistedMessageReaction>, within context: NSManagedObjectContext) throws -> PersistedMessageReaction? {
        let request: NSFetchRequest<PersistedMessageReaction> = PersistedMessageReaction.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

}


// MARK: - PersistedMessageReactionSent

@objc(PersistedMessageReactionSent)
public final class PersistedMessageReactionSent: PersistedMessageReaction {

    private static let entityName = "PersistedMessageReactionSent"

    convenience init(emoji: String, timestamp: Date, message: PersistedMessage) throws {
        try self.init(emoji: emoji, timestamp: timestamp, message: message, forEntityName: Self.entityName)
    }
    
}


// MARK: - PersistedMessageReactionReceived

@objc(PersistedMessageReactionReceived)
public final class PersistedMessageReactionReceived: PersistedMessageReaction {

    private static let entityName = "PersistedMessageReactionReceived"

    // MARK: Relationships

    @NSManaged public private(set) var contact: PersistedObvContactIdentity?

    // MARK: - Initializer

    convenience init(emoji: String?, timestamp: Date, message: PersistedMessage, contact: PersistedObvContactIdentity) throws {
        guard message.managedObjectContext == contact.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.inappropriateContext }
        try self.init(emoji: emoji, timestamp: timestamp, message: message, forEntityName: Self.entityName)
        self.contact = contact
    }

    private struct UserInfoForDeletionKeys {
        static let messagePermanentID = "messagePermanentID"
        static let contactPermanentID = "contactPermanentID"
    }

    private var userInfoForDeletion: [String: Any]?

    public override func prepareForDeletion() {
        super.prepareForDeletion()
        guard let managedObjectContext else { assertionFailure(); return }
        guard managedObjectContext.concurrencyType != .mainQueueConcurrencyType else { return }
        // We keep user infos for deletion only in the case we are considering a reaction on a sent message
        guard let message = message as? PersistedMessageSent,
              let messageObjectPermanentID = try? message.objectPermanentID,
              let contactObjectPermanentID = try? contact?.objectPermanentID else { return }
        userInfoForDeletion = [UserInfoForDeletionKeys.messagePermanentID: messageObjectPermanentID,
                               UserInfoForDeletionKeys.contactPermanentID: contactObjectPermanentID]
    }

    public override func didSave() {
        super.didSave()
        defer {
            self.userInfoForDeletion = nil
        }

        if isDeleted, let userInfoForDeletion = self.userInfoForDeletion {
            guard let messagePermanentID = userInfoForDeletion[UserInfoForDeletionKeys.messagePermanentID] as? MessageSentPermanentID,
                  let contactPermanentID = userInfoForDeletion[UserInfoForDeletionKeys.contactPermanentID] as? ObvManagedObjectPermanentID<PersistedObvContactIdentity>
            else {
                return
            }
            ObvMessengerCoreDataNotification.persistedMessageReactionReceivedWasDeletedOnSentMessage(messagePermanentID: messagePermanentID, contactPermanentID: contactPermanentID)
                .postOnDispatchQueue()
        } else {
            ObvMessengerCoreDataNotification.persistedMessageReactionReceivedWasInsertedOrUpdated(objectID: typedObjectID).postOnDispatchQueue()
        }
    }

}

public extension TypeSafeManagedObjectID where T == PersistedMessageReactionReceived {
    var downcast: TypeSafeManagedObjectID<PersistedMessageReaction> {
        TypeSafeManagedObjectID<PersistedMessageReaction>(objectID: objectID)
    }
}
