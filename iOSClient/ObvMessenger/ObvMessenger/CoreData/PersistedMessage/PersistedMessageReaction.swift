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
import ObvCrypto
import ObvEngine


@objc(PersistedMessageReaction)
class PersistedMessageReaction: NSManagedObject {

    private static let entityName = "PersistedMessageReaction"
    private static let errorDomain = "PersistedMessageReaction"
    private static func makeError(message: String) -> Error { NSError(domain: PersistedMessageReaction.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    // MARK: Attributes

    @NSManaged private var rawEmoji: String
    @NSManaged private(set) var timestamp: Date

    // MARK: Relationships

    @NSManaged var message: PersistedMessage?

    // MARK: Other variables
    
    var emoji: String {
        return self.rawEmoji
    }
    
    // MARK: - Initializer
    
    fileprivate convenience init(emoji: String, timestamp: Date, message: PersistedMessage, forEntityName entityName: String) throws {

        guard let context = message.managedObjectContext else { throw PersistedMessageReaction.makeError(message: "Could not find context in message") }
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        try self.setEmoji(with: emoji, at: timestamp)
        self.message = message
    }
    
    
    func updateEmoji(with newEmoji: String?, at newTimestamp: Date) throws {
        guard self.timestamp < newTimestamp else { return }
        if let newEmoji = newEmoji {
            try self.setEmoji(with: newEmoji, at: newTimestamp)
        } else {
            try self.delete()
        }
    }
    
    
    private func setEmoji(with newEmoji: String, at reactionTimestamp: Date) throws {
        guard newEmoji.count == 1 else { throw PersistedMessageReaction.makeError(message: "Invalid emoji: \(newEmoji)") }
        self.rawEmoji = newEmoji
        self.timestamp = reactionTimestamp
    }
    
    
    func delete() throws {
        guard let context = self.managedObjectContext else { throw PersistedMessageReaction.makeError(message: "Cannot find context") }
        context.delete(self)
    }
    
}

// MARK: - Convenience DB getters

extension PersistedMessageReaction {

    private struct Predicate {
        static func withObjectID(_ objectID: TypeSafeManagedObjectID<PersistedMessageReaction>) -> NSPredicate {
            NSPredicate(withObjectID: objectID.objectID)
        }
    }

    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PersistedMessageReaction> {
        return NSFetchRequest<PersistedMessageReaction>(entityName: entityName)
    }

    
    static func get(with objectID: TypeSafeManagedObjectID<PersistedMessageReaction>, within context: NSManagedObjectContext) throws -> PersistedMessageReaction? {
        let request: NSFetchRequest<PersistedMessageReaction> = PersistedMessageReaction.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

}


// MARK: - PersistedMessageReactionSent

@objc(PersistedMessageReactionSent)
final class PersistedMessageReactionSent: PersistedMessageReaction {

    private static let entityName = "PersistedMessageReactionSent"

    convenience init(emoji: String, timestamp: Date, message: PersistedMessage) throws {
        try self.init(emoji: emoji, timestamp: timestamp, message: message, forEntityName: Self.entityName)
    }
    
}


// MARK: - PersistedMessageReactionReceived

@objc(PersistedMessageReactionReceived)
final class PersistedMessageReactionReceived: PersistedMessageReaction {

    private static let entityName = "PersistedMessageReactionReceived"
    private static let errorDomain = "PersistedMessageReactionReceived"
    private static func makeError(message: String) -> Error { NSError(domain: PersistedMessageReactionReceived.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    // MARK: Relationships

    @NSManaged private(set) var contact: PersistedObvContactIdentity?

    // MARK: - Initializer

    convenience init(emoji: String, timestamp: Date, message: PersistedMessage, contact: PersistedObvContactIdentity) throws {
        guard message.managedObjectContext == contact.managedObjectContext else { throw PersistedMessageReactionReceived.makeError(message: "Incoherent contexts") }
        try self.init(emoji: emoji, timestamp: timestamp, message: message, forEntityName: Self.entityName)
        self.contact = contact
    }

    private struct UserInfoForDeletionKeys {
        static let messagePermanentID = "messagePermanentID"
        static let contactPermanentID = "contactPermanentID"
    }

    private var userInfoForDeletion: [String: Any]?

    override func prepareForDeletion() {
        super.prepareForDeletion()
        // We keep user infos for deletion only in the case we are considering a reaction on a sent message
        guard let message = message as? PersistedMessageSent,
              let contact = contact else { return }
        userInfoForDeletion = [UserInfoForDeletionKeys.messagePermanentID: message.objectPermanentID,
                               UserInfoForDeletionKeys.contactPermanentID: contact.objectPermanentID]
    }

    override func didSave() {
        super.didSave()
        defer {
            self.userInfoForDeletion = nil
        }

        if isDeleted, let userInfoForDeletion = self.userInfoForDeletion {
            guard let messagePermanentID = userInfoForDeletion[UserInfoForDeletionKeys.messagePermanentID] as? ObvManagedObjectPermanentID<PersistedMessageSent>,
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

extension TypeSafeManagedObjectID where T == PersistedMessageReactionReceived {
    var downcast: TypeSafeManagedObjectID<PersistedMessageReaction> {
        TypeSafeManagedObjectID<PersistedMessageReaction>(objectID: objectID)
    }
}
