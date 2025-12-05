/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvTypes
import ObvCrypto
import ObvAppTypes


@objc(MessageIdentifierForLater)
public class MessageIdentifierForLater: NSManagedObject {
    
    private static let entityName = "MessageIdentifierForLater"

    // MARK: Attributes

    @NSManaged private var messageUploadTimestampFromServer: Date? // Non-nil in the model
    @NSManaged private var rawOwnedIdentity: Data? // Non-nil in the model, part of the primary key
    @NSManaged private var rawUID: Data? // Non-nil in the model, part of the primary key
    @NSManaged private var timestampOfFirstNonTruncatedListingAfterInsertion: Date? // Optional in the model, never set during insertion.
    
    // MARK: Init
    
    fileprivate convenience init(messageId: ObvMessageIdentifier, messageUploadTimestampFromServer: Date, entityName: String, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        self.rawOwnedIdentity = messageId.ownedCryptoIdentity.getIdentity()
        self.timestampOfFirstNonTruncatedListingAfterInsertion = nil
        self.rawUID = messageId.uid.raw
    }
    
    fileprivate struct Predicate {
        enum Key: String {
            case messageUploadTimestampFromServer = "messageUploadTimestampFromServer"
            case rawOwnedIdentity = "rawOwnedIdentity"
            case rawUID = "rawUID"
            case timestampOfFirstNonTruncatedListingAfterInsertion = "timestampOfFirstNonTruncatedListingAfterInsertion"
        }
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentity, EqualToData: ownedCryptoId.getIdentity())
        }
        static func withMessageUIDFromEngine(_ uid: UID) -> NSPredicate {
            NSPredicate(Key.rawUID, EqualToData: uid.raw)
        }
        static func withMessageId(_ messageId: ObvMessageIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(Key.rawOwnedIdentity, EqualToData: messageId.ownedCryptoIdentity.getIdentity()),
                withMessageUIDFromEngine(messageId.uid),
            ])
        }
        static var withNilTimestampOfFirstNonTruncatedListingAfterInsertion: NSPredicate {
            NSPredicate(withNilValueForKey: Key.timestampOfFirstNonTruncatedListingAfterInsertion)
        }
        static var withNonNilTimestampOfFirstNonTruncatedListingAfterInsertion: NSPredicate {
            NSCompoundPredicate(notPredicateWithSubpredicate: withNilTimestampOfFirstNonTruncatedListingAfterInsertion)
        }
        static func withTimestampOfFirstNonTruncatedListingAfterInsertionEarlierThan(_ date: Date) -> NSPredicate {
            NSPredicate(Key.timestampOfFirstNonTruncatedListingAfterInsertion, earlierThan: date)
        }
    }

    @nonobjc private static func fetchRequest() -> NSFetchRequest<MessageIdentifierForLater> {
        return NSFetchRequest<MessageIdentifierForLater>(entityName: Self.entityName)
    }
    
    @nonobjc private static func dictionaryFetchRequest() -> NSFetchRequest<NSDictionary> {
        return NSFetchRequest<NSDictionary>(entityName: Self.entityName)
    }

    /// 2025-07-31 ok
    public static func batchDeleteMessageIdentifierForLater(messageId: ObvMessageIdentifier, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = MessageIdentifierForLater.fetchRequest()
        request.predicate = Predicate.withMessageId(messageId)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeObjectIDs
        let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        } else {
            assertionFailure()
        }
    }

    /// Used when an owned identity is deleted
    public static func batchDeleteMessageIdentifierForLater(ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = MessageIdentifierForLater.fetchRequest()
        request.predicate = Predicate.withOwnedCryptoId(ownedCryptoId)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeObjectIDs
        let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        } else {
            assertionFailure()
        }
    }

    // Ok
    public static func batchSetTimestampOfFirstNonTruncatedListingAfterInsertion(ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws {
        let batchRequest = NSBatchUpdateRequest(entity: MessageIdentifierForLater.entity())
        batchRequest.resultType = .updatedObjectIDsResultType
        batchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoId(ownedCryptoId),
            Predicate.withNilTimestampOfFirstNonTruncatedListingAfterInsertion,
        ])
        batchRequest.propertiesToUpdate = [
            Predicate.Key.timestampOfFirstNonTruncatedListingAfterInsertion.rawValue: Date.now,
        ]
        let result = try context.execute(batchRequest) as? NSBatchUpdateResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        } else {
            assertionFailure()
        }
    }
    
    
    public static func fetchObsoleteMessageIdentifiersForLater(withTimestampOfFirstNonTruncatedListingAfterInsertionEarlierThan date: Date, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> [ObvMessageIdentifier] {
        
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()
        
        request.resultType = .dictionaryResultType
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoId(ownedCryptoId),
            Predicate.withNonNilTimestampOfFirstNonTruncatedListingAfterInsertion,
            Predicate.withTimestampOfFirstNonTruncatedListingAfterInsertionEarlierThan(date),
        ])
        request.sortDescriptors = [
            NSSortDescriptor(key: MessageIdentifierForLater.Predicate.Key.messageUploadTimestampFromServer.rawValue, ascending: true),
        ]
        request.propertiesToFetch = [
            MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue,
            MessageIdentifierForLater.Predicate.Key.rawUID.rawValue,
        ]
        request.includesPendingChanges = true
        
        guard let results = try context.fetch(request) as? [[String: Data]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }
        
        let valuesToReturn: [ObvMessageIdentifier] = try results.map { dict in
            guard let rawOwnedIdentity = dict[MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawUID = dict[MessageIdentifierForLater.Predicate.Key.rawUID.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedIdentity) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let messageUIDFromEngine = UID(uid: rawUID) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            return ObvMessageIdentifier(ownedCryptoId: ownedCryptoId, uid: messageUIDFromEngine)
        }
        
        return valuesToReturn
    }

    
    fileprivate static func fetchMessageIdentifierForLater(messageId: ObvMessageIdentifier, within context: NSManagedObjectContext) throws -> MessageIdentifierForLater? {
        let request: NSFetchRequest<MessageIdentifierForLater> = MessageIdentifierForLater.fetchRequest()
        request.predicate = Predicate.withMessageId(messageId)
        request.fetchLimit = 1
        let result = try context.fetch(request).first
        return result
    }
    

    /// This method is used by the 6 sub-entites that store message identifiers for later that expect a specific message.
    fileprivate static func fetchMessageIdentifiersForLaterExpectingMessage(request: NSFetchRequest<NSDictionary>, within context: NSManagedObjectContext) throws -> [ObvMessageIdentifier] {

        request.resultType = .dictionaryResultType
        request.sortDescriptors = [
            NSSortDescriptor(key: MessageIdentifierForLater.Predicate.Key.messageUploadTimestampFromServer.rawValue, ascending: true),
        ]
        request.propertiesToFetch = [
            MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue,
            MessageIdentifierForLater.Predicate.Key.rawUID.rawValue,
        ]
        request.includesPendingChanges = true
        
        guard let results = try context.fetch(request) as? [[String: Data]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }
        
        let valuesToReturn: [ObvMessageIdentifier] = try results.map { dict in
            guard let rawOwnedIdentity = dict[MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawUID = dict[MessageIdentifierForLater.Predicate.Key.rawUID.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedIdentity) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let messageUIDFromEngine = UID(uid: rawUID) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            return ObvMessageIdentifier(ownedCryptoId: ownedCryptoId, uid: messageUIDFromEngine)
        }
        
        return valuesToReturn

    }

    
    enum ObvError: Error {
        case couldNotCastFetchedResult
    }
    
}


// MARK: - MessageIdentifierForLaterExpectingDiscussionOneToOne

@objc(MessageIdentifierForLaterExpectingDiscussionOneToOne)
public final class MessageIdentifierForLaterExpectingDiscussionOneToOne: MessageIdentifierForLater {
 
    private static let entityName = "MessageIdentifierForLaterExpectingDiscussionOneToOne"

    // MARK: Attributes

    @NSManaged private var rawContactCryptoId: Data? // Non-nil in the model
    
    // MARK: Init
    
    fileprivate convenience init(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, contactIdentifier: ObvContactIdentifier, within context: NSManagedObjectContext) {
        let messageId = ObvMessageIdentifier(ownedCryptoId: contactIdentifier.ownedCryptoId, uid: messageUIDFromEngine)
        self.init(messageId: messageId,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                  entityName: Self.entityName,
                  within: context)
        self.rawContactCryptoId = contactIdentifier.contactCryptoId.getIdentity()
    }
    
    // ok
    public static func createOrReplace(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, contactIdentifier: ObvContactIdentifier, within context: NSManagedObjectContext) throws {
        let messageId = ObvMessageIdentifier(ownedCryptoId: contactIdentifier.ownedCryptoId, uid: messageUIDFromEngine)
        let existingMessageIdentifierForLater = try Self.fetchMessageIdentifierForLater(messageId: messageId, within: context)
        if let existingMessageIdentifierForLater {
            if existingMessageIdentifierForLater is Self {
                return
            } else {
                try Self.batchDeleteMessageIdentifierForLater(messageId: messageId, within: context)
            }
        }
        _ = self.init(messageUIDFromEngine: messageUIDFromEngine,
                      messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                      contactIdentifier: contactIdentifier,
                      within: context)
    }
    
    // MARK: Fetching
    
    private struct Predicate {
        enum Key: String {
            case rawContactCryptoId = "rawContactCryptoId"
        }
        static func withContactCryptoId(_ contactCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawContactCryptoId, EqualToData: contactCryptoId.getIdentity())
        }
        static func withContactIdentifier(_ contactIdentifier: ObvContactIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                MessageIdentifierForLater.Predicate.withOwnedCryptoId(contactIdentifier.ownedCryptoId),
                withContactCryptoId(contactIdentifier.contactCryptoId),
            ])
        }
    }
    
    @nonobjc private static func fetchRequest() -> NSFetchRequest<MessageIdentifierForLaterExpectingDiscussionOneToOne> {
        return NSFetchRequest<MessageIdentifierForLaterExpectingDiscussionOneToOne>(entityName: Self.entityName)
    }

    @nonobjc private static func dictionaryFetchRequest() -> NSFetchRequest<NSDictionary> {
        return NSFetchRequest<NSDictionary>(entityName: Self.entityName)
    }

    // 2025-07-31 Tested
    public static func fetchMessageIdentifiersForLater(contactIdentifier: ObvContactIdentifier, within context: NSManagedObjectContext) throws -> [ObvMessageIdentifier] {
        
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()
        
        request.resultType = .dictionaryResultType
        request.predicate = Predicate.withContactIdentifier(contactIdentifier)
        request.sortDescriptors = [NSSortDescriptor(key: MessageIdentifierForLater.Predicate.Key.messageUploadTimestampFromServer.rawValue, ascending: true)]
        request.propertiesToFetch = [
            MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue,
            MessageIdentifierForLater.Predicate.Key.rawUID.rawValue,
        ]
        request.includesPendingChanges = true
        
        guard let results = try context.fetch(request) as? [[String: Data]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }
        
        let valuesToReturn: [ObvMessageIdentifier] = try results.map { dict in
            guard let rawOwnedIdentity = dict[MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawUID = dict[MessageIdentifierForLater.Predicate.Key.rawUID.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedIdentity) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let messageUIDFromEngine = UID(uid: rawUID) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            return ObvMessageIdentifier(ownedCryptoId: ownedCryptoId, uid: messageUIDFromEngine)
        }
        
        return valuesToReturn

    }
    
    
    public static func getAllExpectedDiscussionIdentifiers(within context: NSManagedObjectContext) throws -> [ObvDiscussionIdentifier] {
        
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()
        request.resultType = .dictionaryResultType
        request.returnsDistinctResults = true
        request.propertiesToFetch = [
            MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue,
            Predicate.Key.rawContactCryptoId.rawValue,
        ]
        request.includesPendingChanges = true
        
        guard let results = try context.fetch(request) as? [[String: Data]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }

        let valuesToReturn: [ObvDiscussionIdentifier] = try results.map { dict in
            guard let rawOwnedIdentity = dict[MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawContactCryptoId = dict[Predicate.Key.rawContactCryptoId.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedIdentity) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let contactCryptoId = try? ObvCryptoId(identity: rawContactCryptoId) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            let contactIdentifier = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            return ObvDiscussionIdentifier.oneToOne(id: contactIdentifier)
        }

        return valuesToReturn
        
    }
    
}


// MARK: - MessageIdentifierForLaterExpectingDiscussionGroupV1

@objc(MessageIdentifierForLaterExpectingDiscussionGroupV1)
public final class MessageIdentifierForLaterExpectingDiscussionGroupV1: MessageIdentifierForLater {
    
    private static let entityName = "MessageIdentifierForLaterExpectingDiscussionGroupV1"

    // MARK: Attributes

    @NSManaged private var rawGroupOwner: Data? // Non-nil in the model
    @NSManaged private var rawGroupV1UID: Data? // Non-nil in the model
    
    // MARK: Init
    
    fileprivate convenience init(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, groupV1Identifier: ObvGroupV1Identifier, within context: NSManagedObjectContext) {
        let messageId = ObvMessageIdentifier(ownedCryptoId: groupV1Identifier.ownedCryptoId, uid: messageUIDFromEngine)
        self.init(messageId: messageId,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                  entityName: Self.entityName,
                  within: context)
        self.rawGroupOwner = groupV1Identifier.groupV1Identifier.groupOwner.getIdentity()
        self.rawGroupV1UID = groupV1Identifier.groupV1Identifier.groupUid.raw
    }
    
    public static func createOrReplace(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, groupV1Identifier: ObvGroupV1Identifier, within context: NSManagedObjectContext) throws {
        let messageId = ObvMessageIdentifier(ownedCryptoId: groupV1Identifier.ownedCryptoId, uid: messageUIDFromEngine)
        let existingMessageIdentifierForLater = try Self.fetchMessageIdentifierForLater(messageId: messageId, within: context)
        if let existingMessageIdentifierForLater {
            if existingMessageIdentifierForLater is Self {
                return
            } else {
                try Self.batchDeleteMessageIdentifierForLater(messageId: messageId, within: context)
            }
        }
        _ = self.init(messageUIDFromEngine: messageUIDFromEngine,
                      messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                      groupV1Identifier: groupV1Identifier,
                      within: context)
    }

    // MARK: Fetching
    
    private struct Predicate {
        enum Key: String {
            case rawGroupOwner = "rawGroupOwner"
            case rawGroupV1UID = "rawGroupV1UID"
        }
        private static func withGroupOwner(_ groupOwner: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawGroupOwner, EqualToData: groupOwner.getIdentity())
        }
        private static func withGroupV1UID(_ groupUID: UID) -> NSPredicate {
            NSPredicate(Key.rawGroupV1UID, EqualToData: groupUID.raw)
        }
        private static func withGroupV1Identifier(_ groupV1Identifier: GroupV1Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withGroupOwner(groupV1Identifier.groupOwner),
                withGroupV1UID(groupV1Identifier.groupUid),
            ])
        }
        static func withObvGroupV1Identifier(_ obvGroupV1Identifier: ObvGroupV1Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                MessageIdentifierForLater.Predicate.withOwnedCryptoId(obvGroupV1Identifier.ownedCryptoId),
                withGroupV1Identifier(obvGroupV1Identifier.groupV1Identifier),
            ])
        }
    }
    
    @nonobjc private static func fetchRequest() -> NSFetchRequest<MessageIdentifierForLaterExpectingDiscussionGroupV1> {
        return NSFetchRequest<MessageIdentifierForLaterExpectingDiscussionGroupV1>(entityName: Self.entityName)
    }

    @nonobjc private static func dictionaryFetchRequest() -> NSFetchRequest<NSDictionary> {
        return NSFetchRequest<NSDictionary>(entityName: Self.entityName)
    }

    public static func fetchMessageIdentifiersForLater(obvGroupV1Identifier: ObvGroupV1Identifier, within context: NSManagedObjectContext) throws -> [ObvMessageIdentifier] {
        
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()

        request.resultType = .dictionaryResultType
        request.predicate = Predicate.withObvGroupV1Identifier(obvGroupV1Identifier)
        request.sortDescriptors = [NSSortDescriptor(key: MessageIdentifierForLater.Predicate.Key.messageUploadTimestampFromServer.rawValue, ascending: true)]
        request.propertiesToFetch = [
            MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue,
            MessageIdentifierForLater.Predicate.Key.rawUID.rawValue,
        ]
        request.includesPendingChanges = true
        
        guard let results = try context.fetch(request) as? [[String: Data]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }
        
        let valuesToReturn: [ObvMessageIdentifier] = try results.map { dict in
            guard let rawOwnedIdentity = dict[MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawUID = dict[MessageIdentifierForLater.Predicate.Key.rawUID.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedIdentity) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let messageUIDFromEngine = UID(uid: rawUID) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            return ObvMessageIdentifier(ownedCryptoId: ownedCryptoId, uid: messageUIDFromEngine)
        }
        
        return valuesToReturn

    }

    
    public static func getAllExpectedDiscussionIdentifiers(within context: NSManagedObjectContext) throws -> [ObvDiscussionIdentifier] {
        
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()
        request.resultType = .dictionaryResultType
        request.returnsDistinctResults = true
        request.propertiesToFetch = [
            MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue,
            Predicate.Key.rawGroupV1UID.rawValue,
            Predicate.Key.rawGroupOwner.rawValue,
        ]
        request.includesPendingChanges = true
        
        guard let results = try context.fetch(request) as? [[String: Data]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }

        let valuesToReturn: [ObvDiscussionIdentifier] = try results.map { dict in
            guard let rawOwnedIdentity = dict[MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawGroupV1UID = dict[Predicate.Key.rawGroupV1UID.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawGroupOwner = dict[Predicate.Key.rawGroupOwner.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedIdentity) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let groupUid = UID(uid: rawGroupV1UID) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let groupOwner = try? ObvCryptoId(identity: rawGroupOwner) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            let groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            let obvGroupV1Identifier = ObvGroupV1Identifier(ownedCryptoId: ownedCryptoId, groupV1Identifier: groupV1Identifier)
            return ObvDiscussionIdentifier.groupV1(id: obvGroupV1Identifier)
        }

        return valuesToReturn
        
    }

}


// MARK: - MessageIdentifierForLaterExpectingDiscussionGroupV2

@objc(MessageIdentifierForLaterExpectingDiscussionGroupV2)
public final class MessageIdentifierForLaterExpectingDiscussionGroupV2: MessageIdentifierForLater {
    
    private static let entityName = "MessageIdentifierForLaterExpectingDiscussionGroupV2"

    // MARK: Attributes

    @NSManaged private var rawCategory: Int
    @NSManaged private var rawGroupV2UID: Data? // Non-nil in the model
    @NSManaged private var serverURL: URL? // Non-nil in the model
    
    // MARK: Init
    
    fileprivate convenience init(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, groupV2Identifier: ObvGroupV2Identifier, within context: NSManagedObjectContext) {
        let messageId = ObvMessageIdentifier(ownedCryptoId: groupV2Identifier.ownedCryptoId, uid: messageUIDFromEngine)
        self.init(messageId: messageId,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                  entityName: Self.entityName,
                  within: context)
        self.rawCategory = groupV2Identifier.identifier.category.rawValue
        self.rawGroupV2UID = groupV2Identifier.identifier.groupUID.raw
        self.serverURL = groupV2Identifier.identifier.serverURL
    }
    
    public static func createOrReplace(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, groupV2Identifier: ObvGroupV2Identifier, within context: NSManagedObjectContext) throws {
        let messageId = ObvMessageIdentifier(ownedCryptoId: groupV2Identifier.ownedCryptoId, uid: messageUIDFromEngine)
        let existingMessageIdentifierForLater = try Self.fetchMessageIdentifierForLater(messageId: messageId, within: context)
        if let existingMessageIdentifierForLater {
            if existingMessageIdentifierForLater is Self {
                return
            } else {
                try Self.batchDeleteMessageIdentifierForLater(messageId: messageId, within: context)
            }
        }
        _ = self.init(messageUIDFromEngine: messageUIDFromEngine,
                      messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                      groupV2Identifier: groupV2Identifier,
                      within: context)
    }

    // MARK: Fetching
    
    private struct Predicate {
        enum Key: String {
            case rawCategory = "rawCategory"
            case rawGroupV2UID = "rawGroupV2UID"
            case serverURL = "serverURL"
        }
        private static func withCategory(_ category: ObvGroupV2.Identifier.Category) -> NSPredicate {
            NSPredicate(Key.rawCategory, EqualToInt: category.rawValue)
        }
        private static func withGroupV2UID(_ groupUID: UID) -> NSPredicate {
            NSPredicate(Key.rawGroupV2UID, EqualToData: groupUID.raw)
        }
        private static func withServerURL(_ serverURL: URL) -> NSPredicate {
            NSPredicate(Key.serverURL, EqualToUrl: serverURL)
        }
        private static func withGroupV2Identifier(_ identifier: ObvGroupV2.Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withCategory(identifier.category),
                withGroupV2UID(identifier.groupUID),
                withServerURL(identifier.serverURL),
            ])
        }
        static func withObvGroupV2Identifier(_ obvGroupV2Identifier: ObvGroupV2Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                MessageIdentifierForLater.Predicate.withOwnedCryptoId(obvGroupV2Identifier.ownedCryptoId),
                withGroupV2Identifier(obvGroupV2Identifier.identifier),
            ])
        }
    }
    
    @nonobjc private static func fetchRequest() -> NSFetchRequest<MessageIdentifierForLaterExpectingDiscussionGroupV2> {
        return NSFetchRequest<MessageIdentifierForLaterExpectingDiscussionGroupV2>(entityName: Self.entityName)
    }

    @nonobjc private static func dictionaryFetchRequest() -> NSFetchRequest<NSDictionary> {
        return NSFetchRequest<NSDictionary>(entityName: Self.entityName)
    }

    public static func fetchMessageIdentifiersForLater(obvGroupV2Identifier: ObvGroupV2Identifier, within context: NSManagedObjectContext) throws -> [ObvMessageIdentifier] {
        
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()

        request.resultType = .dictionaryResultType
        request.predicate = Predicate.withObvGroupV2Identifier(obvGroupV2Identifier)
        request.sortDescriptors = [NSSortDescriptor(key: MessageIdentifierForLater.Predicate.Key.messageUploadTimestampFromServer.rawValue, ascending: true)]
        request.propertiesToFetch = [
            MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue,
            MessageIdentifierForLater.Predicate.Key.rawUID.rawValue,
        ]
        request.includesPendingChanges = true
        
        guard let results = try context.fetch(request) as? [[String: Data]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }
        
        let valuesToReturn: [ObvMessageIdentifier] = try results.map { dict in
            guard let rawOwnedIdentity = dict[MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawUID = dict[MessageIdentifierForLater.Predicate.Key.rawUID.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedIdentity) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let messageUIDFromEngine = UID(uid: rawUID) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            return ObvMessageIdentifier(ownedCryptoId: ownedCryptoId, uid: messageUIDFromEngine)
        }
        
        return valuesToReturn

    }

    
    public static func getAllExpectedDiscussionIdentifiers(within context: NSManagedObjectContext) throws -> [ObvDiscussionIdentifier] {
        
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()
        request.resultType = .dictionaryResultType
        request.returnsDistinctResults = true
        request.propertiesToFetch = [
            MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue,
            Predicate.Key.rawGroupV2UID.rawValue,
            Predicate.Key.serverURL.rawValue,
            Predicate.Key.rawCategory.rawValue,
        ]
        request.includesPendingChanges = true
        
        guard let results = try context.fetch(request) as? [[String: Any]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }
        
        let valuesToReturn: [ObvDiscussionIdentifier] = try results.map { dict in
            guard let rawOwnedIdentity = dict[MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawGroupV2UID = dict[Predicate.Key.rawGroupV2UID.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let serverURL = dict[Predicate.Key.serverURL.rawValue] as? URL else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawCategory = dict[Predicate.Key.rawCategory.rawValue] as? Int else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedIdentity) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let groupUID = UID(uid: rawGroupV2UID) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let category =  ObvGroupV2.Identifier.Category(rawValue: rawCategory) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            let identifier = ObvGroupV2.Identifier(groupUID: groupUID, serverURL: serverURL, category: category)
            let obvGroupV2Identifier = ObvGroupV2Identifier(ownedCryptoId: ownedCryptoId, identifier: identifier)
            return ObvDiscussionIdentifier.groupV2(id: obvGroupV2Identifier)
        }
        
        return valuesToReturn
        
    }

}


// MARK: - MessageIdentifierForLaterExpectingContactInGroupV1

@objc(MessageIdentifierForLaterExpectingContactInGroupV1)
public final class MessageIdentifierForLaterExpectingContactInGroupV1: MessageIdentifierForLater {
    
    private static let entityName = "MessageIdentifierForLaterExpectingContactInGroupV1"
    
    // MARK: Attributes

    @NSManaged private var rawContactCryptoId: Data?
    @NSManaged private var rawGroupOwner: Data? // Non-nil in the model
    @NSManaged private var rawGroupV1UID: Data? // Non-nil in the model
    
    // MARK: Init
    
    fileprivate convenience init(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, groupV1Identifier: ObvGroupV1Identifier, contactCryptoId: ObvCryptoId, within context: NSManagedObjectContext) {
        let messageId = ObvMessageIdentifier(ownedCryptoId: groupV1Identifier.ownedCryptoId, uid: messageUIDFromEngine)
        self.init(messageId: messageId,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                  entityName: Self.entityName,
                  within: context)
        self.rawGroupOwner = groupV1Identifier.groupV1Identifier.groupOwner.getIdentity()
        self.rawGroupV1UID = groupV1Identifier.groupV1Identifier.groupUid.raw
        self.rawContactCryptoId = contactCryptoId.getIdentity()
    }
    
    public static func createOrReplace(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, groupV1Identifier: ObvGroupV1Identifier, contactCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws {
        let messageId = ObvMessageIdentifier(ownedCryptoId: groupV1Identifier.ownedCryptoId, uid: messageUIDFromEngine)
        let existingMessageIdentifierForLater = try Self.fetchMessageIdentifierForLater(messageId: messageId, within: context)
        if let existingMessageIdentifierForLater {
            if existingMessageIdentifierForLater is Self {
                return
            } else {
                try Self.batchDeleteMessageIdentifierForLater(messageId: messageId, within: context)
            }
        }
        _ = self.init(messageUIDFromEngine: messageUIDFromEngine,
                      messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                      groupV1Identifier: groupV1Identifier,
                      contactCryptoId: contactCryptoId,
                      within: context)
    }

    // MARK: Fetching
    
    private struct Predicate {
        enum Key: String {
            case rawContactCryptoId = "rawContactCryptoId"
            case rawGroupOwner = "rawGroupOwner"
            case rawGroupV1UID = "rawGroupV1UID"
        }
        private static func withGroupOwner(_ groupOwner: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawGroupOwner, EqualToData: groupOwner.getIdentity())
        }
        private static func withGroupV1UID(_ groupUID: UID) -> NSPredicate {
            NSPredicate(Key.rawGroupV1UID, EqualToData: groupUID.raw)
        }
        private static func withGroupV1Identifier(_ groupV1Identifier: GroupV1Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withGroupOwner(groupV1Identifier.groupOwner),
                withGroupV1UID(groupV1Identifier.groupUid),
            ])
        }
        static func withObvGroupV1Identifier(_ obvGroupV1Identifier: ObvGroupV1Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                MessageIdentifierForLater.Predicate.withOwnedCryptoId(obvGroupV1Identifier.ownedCryptoId),
                withGroupV1Identifier(obvGroupV1Identifier.groupV1Identifier),
            ])
        }
        static func withContactCryptoId(_ contactCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawContactCryptoId, EqualToData: contactCryptoId.getIdentity())
        }
    }
    
    @nonobjc private static func fetchRequest() -> NSFetchRequest<MessageIdentifierForLaterExpectingContactInGroupV1> {
        return NSFetchRequest<MessageIdentifierForLaterExpectingContactInGroupV1>(entityName: Self.entityName)
    }

    @nonobjc private static func dictionaryFetchRequest() -> NSFetchRequest<NSDictionary> {
        return NSFetchRequest<NSDictionary>(entityName: Self.entityName)
    }

    public static func fetchMessageIdentifiersForLater(obvGroupV1Identifier: ObvGroupV1Identifier, contactCryptoId: ObvCryptoId?, within context: NSManagedObjectContext) throws -> [ObvMessageIdentifier] {
        
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()

        request.resultType = .dictionaryResultType
        var predicate = Predicate.withObvGroupV1Identifier(obvGroupV1Identifier)
        if let contactCryptoId {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                predicate,
                Predicate.withContactCryptoId(contactCryptoId),
            ])
        }
        request.sortDescriptors = [
            NSSortDescriptor(key: MessageIdentifierForLater.Predicate.Key.messageUploadTimestampFromServer.rawValue, ascending: true),
        ]
        request.propertiesToFetch = [
            MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue,
            MessageIdentifierForLater.Predicate.Key.rawUID.rawValue,
        ]
        request.includesPendingChanges = true
        
        guard let results = try context.fetch(request) as? [[String: Data]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }
        
        let valuesToReturn: [ObvMessageIdentifier] = try results.map { dict in
            guard let rawOwnedIdentity = dict[MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawUID = dict[MessageIdentifierForLater.Predicate.Key.rawUID.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedIdentity) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let messageUIDFromEngine = UID(uid: rawUID) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            return ObvMessageIdentifier(ownedCryptoId: ownedCryptoId, uid: messageUIDFromEngine)
        }
        
        return valuesToReturn

    }

    
    public static func getAllExpectedMemberIdentifiers(within context: NSManagedObjectContext) throws -> [ObvGroupMemberIdentifier] {
        
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()
        request.resultType = .dictionaryResultType
        request.returnsDistinctResults = true
        request.propertiesToFetch = [
            MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue,
            Predicate.Key.rawGroupV1UID.rawValue,
            Predicate.Key.rawGroupOwner.rawValue,
            Predicate.Key.rawContactCryptoId.rawValue
        ]
        request.includesPendingChanges = true
        
        guard let results = try context.fetch(request) as? [[String: Data]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }

        let valuesToReturn: [ObvGroupMemberIdentifier] = try results.map { dict in
            guard let rawOwnedIdentity = dict[MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawGroupV1UID = dict[Predicate.Key.rawGroupV1UID.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawGroupOwner = dict[Predicate.Key.rawGroupOwner.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawContactCryptoId = dict[Predicate.Key.rawContactCryptoId.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedIdentity) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let groupUid = UID(uid: rawGroupV1UID) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let groupOwner = try? ObvCryptoId(identity: rawGroupOwner) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let contactCryptoId = try? ObvCryptoId(identity: rawContactCryptoId) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            let groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            let obvGroupV1Identifier = ObvGroupV1Identifier(ownedCryptoId: ownedCryptoId, groupV1Identifier: groupV1Identifier)
            let obvGroupIdentifier = ObvGroupIdentifier.groupV1(obvGroupV1Identifier)
            let memberId = ObvGroupMemberIdentifier(groupId: obvGroupIdentifier, memberCryptoId: contactCryptoId)
            return memberId
        }

        return valuesToReturn
        
    }

}

    
// MARK: - MessageIdentifierForLaterExpectingContactInGroupV2

@objc(MessageIdentifierForLaterExpectingContactInGroupV2)
public final class MessageIdentifierForLaterExpectingContactInGroupV2: MessageIdentifierForLater {
    
    private static let entityName = "MessageIdentifierForLaterExpectingContactInGroupV2"
    
    // MARK: Attributes
    
    @NSManaged private var rawCategory: Int
    @NSManaged private var rawContactCryptoId: Data?
    @NSManaged private var rawGroupV2UID: Data? // Non-nil in the model
    @NSManaged private var serverURL: URL? // Non-nil in the model
    
    // MARK: Init
    
    fileprivate convenience init(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, groupV2Identifier: ObvGroupV2Identifier, contactCryptoId: ObvCryptoId, within context: NSManagedObjectContext) {
        let messageId = ObvMessageIdentifier(ownedCryptoId: groupV2Identifier.ownedCryptoId, uid: messageUIDFromEngine)
        self.init(messageId: messageId,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                  entityName: Self.entityName,
                  within: context)
        self.rawCategory = groupV2Identifier.identifier.category.rawValue
        self.rawGroupV2UID = groupV2Identifier.identifier.groupUID.raw
        self.serverURL = groupV2Identifier.identifier.serverURL
        self.rawContactCryptoId = contactCryptoId.getIdentity()
    }

    public static func createOrReplace(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, groupV2Identifier: ObvGroupV2Identifier, contactCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws {
        let messageId = ObvMessageIdentifier(ownedCryptoId: groupV2Identifier.ownedCryptoId, uid: messageUIDFromEngine)
        let existingMessageIdentifierForLater = try Self.fetchMessageIdentifierForLater(messageId: messageId, within: context)
        if let existingMessageIdentifierForLater {
            if existingMessageIdentifierForLater is Self {
                return
            } else {
                try Self.batchDeleteMessageIdentifierForLater(messageId: messageId, within: context)
            }
        }
        _ = self.init(messageUIDFromEngine: messageUIDFromEngine,
                      messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                      groupV2Identifier: groupV2Identifier,
                      contactCryptoId: contactCryptoId,
                      within: context)
    }

    // MARK: Fetching
    
    private struct Predicate {
        enum Key: String {
            case rawCategory = "rawCategory"
            case rawContactCryptoId = "rawContactCryptoId"
            case rawGroupV2UID = "rawGroupV2UID"
            case serverURL = "serverURL"
        }
        private static func withCategory(_ category: ObvGroupV2.Identifier.Category) -> NSPredicate {
            NSPredicate(Key.rawCategory, EqualToInt: category.rawValue)
        }
        static func withContactCryptoId(_ contactCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawContactCryptoId, EqualToData: contactCryptoId.getIdentity())
        }
        private static func withGroupV2UID(_ groupUID: UID) -> NSPredicate {
            NSPredicate(Key.rawGroupV2UID, EqualToData: groupUID.raw)
        }
        private static func withServerURL(_ serverURL: URL) -> NSPredicate {
            NSPredicate(Key.serverURL, EqualToUrl: serverURL)
        }
        private static func withGroupV2Identifier(_ identifier: ObvGroupV2.Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withCategory(identifier.category),
                withGroupV2UID(identifier.groupUID),
                withServerURL(identifier.serverURL),
            ])
        }
        static func withObvGroupV2Identifier(_ obvGroupV2Identifier: ObvGroupV2Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                MessageIdentifierForLater.Predicate.withOwnedCryptoId(obvGroupV2Identifier.ownedCryptoId),
                withGroupV2Identifier(obvGroupV2Identifier.identifier),
            ])
        }
    }
    
    @nonobjc private static func fetchRequest() -> NSFetchRequest<MessageIdentifierForLaterExpectingContactInGroupV2> {
        return NSFetchRequest<MessageIdentifierForLaterExpectingContactInGroupV2>(entityName: Self.entityName)
    }

    @nonobjc private static func dictionaryFetchRequest() -> NSFetchRequest<NSDictionary> {
        return NSFetchRequest<NSDictionary>(entityName: Self.entityName)
    }

    public static func fetchMessageIdentifiersForLater(obvGroupV2Identifier: ObvGroupV2Identifier, contactCryptoId: ObvCryptoId?, within context: NSManagedObjectContext) throws -> [ObvMessageIdentifier] {
        
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()

        request.resultType = .dictionaryResultType
        var predicate = Predicate.withObvGroupV2Identifier(obvGroupV2Identifier)
        if let contactCryptoId {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                predicate,
                Predicate.withContactCryptoId(contactCryptoId),
            ])
        }
        request.predicate = predicate

        request.sortDescriptors = [
            NSSortDescriptor(key: MessageIdentifierForLater.Predicate.Key.messageUploadTimestampFromServer.rawValue, ascending: true),
        ]
        request.propertiesToFetch = [
            MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue,
            MessageIdentifierForLater.Predicate.Key.rawUID.rawValue,
        ]
        request.includesPendingChanges = true
        
        guard let results = try context.fetch(request) as? [[String: Data]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }
        
        let valuesToReturn: [ObvMessageIdentifier] = try results.map { dict in
            guard let rawOwnedIdentity = dict[MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawUID = dict[MessageIdentifierForLater.Predicate.Key.rawUID.rawValue] else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedIdentity) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let messageUIDFromEngine = UID(uid: rawUID) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            return ObvMessageIdentifier(ownedCryptoId: ownedCryptoId, uid: messageUIDFromEngine)
        }
        
        return valuesToReturn

    }

    
    public static func getAllExpectedMemberIdentifiers(within context: NSManagedObjectContext) throws -> [ObvGroupMemberIdentifier] {
        
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()
        request.resultType = .dictionaryResultType
        request.returnsDistinctResults = true
        request.propertiesToFetch = [
            MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue,
            Predicate.Key.rawGroupV2UID.rawValue,
            Predicate.Key.serverURL.rawValue,
            Predicate.Key.rawCategory.rawValue,
            Predicate.Key.rawContactCryptoId.rawValue,
        ]
        request.includesPendingChanges = true
        
        guard let results = try context.fetch(request) as? [[String: Any]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }
        
        let valuesToReturn: [ObvGroupMemberIdentifier] = try results.map { dict in
            guard let rawOwnedIdentity = dict[MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawGroupV2UID = dict[Predicate.Key.rawGroupV2UID.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let serverURL = dict[Predicate.Key.serverURL.rawValue] as? URL else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawCategory = dict[Predicate.Key.rawCategory.rawValue] as? Int else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawContactCryptoId = dict[Predicate.Key.rawContactCryptoId.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedIdentity) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let groupUID = UID(uid: rawGroupV2UID) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let category =  ObvGroupV2.Identifier.Category(rawValue: rawCategory) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let contactCryptoId = try? ObvCryptoId(identity: rawContactCryptoId) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            let identifier = ObvGroupV2.Identifier(groupUID: groupUID, serverURL: serverURL, category: category)
            let obvGroupV2Identifier = ObvGroupV2Identifier(ownedCryptoId: ownedCryptoId, identifier: identifier)
            let obvGroupIdentifier = ObvGroupIdentifier.groupV2(obvGroupV2Identifier)
            let memberId = ObvGroupMemberIdentifier(groupId: obvGroupIdentifier, memberCryptoId: contactCryptoId)
            return memberId
        }
        
        return valuesToReturn
        
    }
    
}

// MARK: - All entities when a MessageIdentifier expects a message

@objc(MessageIdentifierForLaterExpectingSentMessage)
public class MessageIdentifierForLaterExpectingSentMessage: MessageIdentifierForLater {
    
    // MARK: Attributes (for the sent message)
    @NSManaged private var senderThreadIdentifier: UUID? // Non-optional in the model
    @NSManaged private var senderSequenceNumber: Int

    fileprivate convenience init(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, ownedCryptoId: ObvCryptoId, senderThreadIdentifier: UUID, senderSequenceNumber: Int, entityName: String, within context: NSManagedObjectContext) {
        let messageId = ObvMessageIdentifier(ownedCryptoId: ownedCryptoId, uid: messageUIDFromEngine)

        self.init(messageId: messageId,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                  entityName: entityName,
                  within: context)
        
        self.senderThreadIdentifier = senderThreadIdentifier
        self.senderSequenceNumber = senderSequenceNumber
        
    }
    
    // MARK: Fetching

    struct Predicate {
        enum Key: String {
            // MARK: Attributes (for the sent message)
            case senderThreadIdentifier = "senderThreadIdentifier"
            case senderSequenceNumber = "senderSequenceNumber"
        }
        private static func withSenderThreadIdentifier(_ senderThreadIdentifier: UUID) -> NSPredicate {
            NSPredicate(Key.senderThreadIdentifier, EqualToUuid: senderThreadIdentifier)
        }
        private static func withSenderSequenceNumber(_ senderSequenceNumber: Int) -> NSPredicate {
            NSPredicate(Key.senderSequenceNumber, EqualToInt: senderSequenceNumber)
        }
        static func withSentMessageIdentifier(senderThreadIdentifier: UUID, senderSequenceNumber: Int) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withSenderThreadIdentifier(senderThreadIdentifier),
                withSenderSequenceNumber(senderSequenceNumber),
            ])
        }
    }

}


@objc(MessageIdentifierForLaterExpectingReceivedMessage)
public class MessageIdentifierForLaterExpectingReceivedMessage: MessageIdentifierForLater {
    
    // MARK: Attributes (for the sent message)
    @NSManaged private var senderThreadIdentifier: UUID? // Non-optional in the model
    @NSManaged private var senderSequenceNumber: Int
    @NSManaged private var senderIdentifier: Data? // Non-optional in the model

    fileprivate convenience init(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, ownedCryptoId: ObvCryptoId, senderThreadIdentifier: UUID, senderSequenceNumber: Int, senderIdentifier: Data, entityName: String, within context: NSManagedObjectContext) {
        let messageId = ObvMessageIdentifier(ownedCryptoId: ownedCryptoId, uid: messageUIDFromEngine)

        self.init(messageId: messageId,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                  entityName: entityName,
                  within: context)
        
        self.senderThreadIdentifier = senderThreadIdentifier
        self.senderSequenceNumber = senderSequenceNumber
        self.senderIdentifier = senderIdentifier
        
    }
    
    // MARK: Fetching

    struct Predicate {
        enum Key: String {
            // MARK: Attributes (for the received message)
            case senderThreadIdentifier = "senderThreadIdentifier"
            case senderSequenceNumber = "senderSequenceNumber"
            case senderIdentifier = "senderIdentifier"
        }
        private static func withSenderThreadIdentifier(_ senderThreadIdentifier: UUID) -> NSPredicate {
            NSPredicate(Key.senderThreadIdentifier, EqualToUuid: senderThreadIdentifier)
        }
        private static func withSenderSequenceNumber(_ senderSequenceNumber: Int) -> NSPredicate {
            NSPredicate(Key.senderSequenceNumber, EqualToInt: senderSequenceNumber)
        }
        private static func withSenderIdentifier(_ senderIdentifier: Data) -> NSPredicate {
            NSPredicate(Key.senderIdentifier, EqualToData: senderIdentifier)
        }
        static func withReceivedMessageIdentifier(senderThreadIdentifier: UUID, senderSequenceNumber: Int, senderIdentifier: Data) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withSenderThreadIdentifier(senderThreadIdentifier),
                withSenderSequenceNumber(senderSequenceNumber),
                withSenderIdentifier(senderIdentifier),
            ])
        }
    }

}


@objc(MessageIdentifierForLaterExpectingSentMessageInOneToOneDiscussion)
public final class MessageIdentifierForLaterExpectingSentMessageInOneToOneDiscussion: MessageIdentifierForLaterExpectingSentMessage {
    
    private static let entityName = "MessageIdentifierForLaterExpectingSentMessageInOneToOneDiscussion"

    // MARK: Attributes (for the oneToOne discussion identifier)
    @NSManaged private var rawContactCryptoId: Data? // Non-optional in the model
    
    fileprivate convenience init(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId, senderThreadIdentifier: UUID, senderSequenceNumber: Int, within context: NSManagedObjectContext) {
        
        self.init(messageUIDFromEngine: messageUIDFromEngine,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                  ownedCryptoId: ownedCryptoId,
                  senderThreadIdentifier: senderThreadIdentifier,
                  senderSequenceNumber: senderSequenceNumber,
                  entityName: Self.entityName,
                  within: context)
        
        self.rawContactCryptoId = contactCryptoId.getIdentity()
        
    }


    public static func createOrReplace(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, discussionId: ObvContactIdentifier, sentMessageId: (senderThreadIdentifier: UUID, senderSequenceNumber: Int), within context: NSManagedObjectContext) throws {
        let messageId = ObvMessageIdentifier(ownedCryptoId: discussionId.ownedCryptoId, uid: messageUIDFromEngine)
        let existingMessageIdentifierForLater = try Self.fetchMessageIdentifierForLater(messageId: messageId, within: context)
        if let existingMessageIdentifierForLater {
            if existingMessageIdentifierForLater is Self {
                return
            } else {
                try Self.batchDeleteMessageIdentifierForLater(messageId: messageId, within: context)
            }
        }
        _ = self.init(messageUIDFromEngine: messageUIDFromEngine,
                      messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                      ownedCryptoId: discussionId.ownedCryptoId,
                      contactCryptoId: discussionId.contactCryptoId,
                      senderThreadIdentifier: sentMessageId.senderThreadIdentifier,
                      senderSequenceNumber: sentMessageId.senderSequenceNumber,
                      within: context)
    }

    // MARK: Fetching

    private struct Predicate {
        enum Key: String {
            // MARK: Attributes (for the oneToOne discussion)
            case rawContactCryptoId = "rawContactCryptoId"
        }
        private static func withContactCryptoId(_ contactCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawContactCryptoId, EqualToData: contactCryptoId.getIdentity())
        }
        private static func withOneToOneDiscussionIdentifier(_ obvContactIdentifier: ObvContactIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                MessageIdentifierForLater.Predicate.withOwnedCryptoId(obvContactIdentifier.ownedCryptoId),
                withContactCryptoId(obvContactIdentifier.contactCryptoId),
            ])
        }
        static func withId(discussionId: ObvContactIdentifier, sentMessageId: (senderThreadIdentifier: UUID, senderSequenceNumber: Int)) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withOneToOneDiscussionIdentifier(discussionId),
                MessageIdentifierForLaterExpectingSentMessage.Predicate.withSentMessageIdentifier(
                    senderThreadIdentifier: sentMessageId.senderThreadIdentifier,
                    senderSequenceNumber: sentMessageId.senderSequenceNumber),
            ])
        }
    }

    @nonobjc private static func fetchRequest() -> NSFetchRequest<MessageIdentifierForLaterExpectingSentMessageInOneToOneDiscussion> {
        return NSFetchRequest<MessageIdentifierForLaterExpectingSentMessageInOneToOneDiscussion>(entityName: Self.entityName)
    }

    @nonobjc private static func dictionaryFetchRequest() -> NSFetchRequest<NSDictionary> {
        return NSFetchRequest<NSDictionary>(entityName: Self.entityName)
    }
    
    public static func fetchMessageIdentifiersForLater(discussionId: ObvContactIdentifier, sentMessageId: (senderThreadIdentifier: UUID, senderSequenceNumber: Int), within context: NSManagedObjectContext) throws -> [ObvMessageIdentifier] {
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()
        request.predicate = Predicate.withId(discussionId: discussionId, sentMessageId: sentMessageId)
        return try Self.fetchMessageIdentifiersForLaterExpectingMessage(request: request, within: context)
    }

    public static func getAllExpectedMessageAppIdentifier(within context: NSManagedObjectContext) throws -> [ObvMessageAppIdentifier] {
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()

        request.resultType = .dictionaryResultType
        request.includesPendingChanges = true

        let propertiesToFetchForOneToOneDiscussionId: [String] = [
            MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue,
            Predicate.Key.rawContactCryptoId.rawValue,
        ]
        let propertiesToFetchForSentMessage: [String] = [
            MessageIdentifierForLaterExpectingSentMessage.Predicate.Key.senderThreadIdentifier.rawValue,
            MessageIdentifierForLaterExpectingSentMessage.Predicate.Key.senderSequenceNumber.rawValue,
        ]
        request.propertiesToFetch = propertiesToFetchForOneToOneDiscussionId + propertiesToFetchForSentMessage
        
        guard let results = try context.fetch(request) as? [[String: Any]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }
        
        let valuesToReturn: [ObvMessageAppIdentifier] = try results.map { dict in
            // OneToOne discussion Id
            guard let rawOwnedIdentity = dict[MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawContactCryptoId = dict[Predicate.Key.rawContactCryptoId.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedIdentity) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let contactCryptoId = try? ObvCryptoId(identity: rawContactCryptoId) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            let discussionId = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            // Sent message Id
            guard let senderThreadIdentifier = dict[MessageIdentifierForLaterExpectingSentMessage.Predicate.Key.senderThreadIdentifier.rawValue] as? UUID else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let senderSequenceNumber = dict[MessageIdentifierForLaterExpectingSentMessage.Predicate.Key.senderSequenceNumber.rawValue] as? Int else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            // Construct and return ObvMessageAppIdentifier
            return ObvMessageAppIdentifier.sent(
                discussionIdentifier: .oneToOne(id: discussionId),
                senderThreadIdentifier: senderThreadIdentifier,
                senderSequenceNumber: senderSequenceNumber)
        }
        
        return valuesToReturn

    }

}


@objc(MessageIdentifierForLaterExpectingReceivedMessageInOneToOneDiscussion)
public final class MessageIdentifierForLaterExpectingReceivedMessageInOneToOneDiscussion: MessageIdentifierForLaterExpectingReceivedMessage {
    
    private static let entityName = "MessageIdentifierForLaterExpectingReceivedMessageInOneToOneDiscussion"

    // MARK: Attributes (for the oneToOne discussion identifier)
    @NSManaged private var rawContactCryptoId: Data? // Non-optional in the model
    
    fileprivate convenience init(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId, senderThreadIdentifier: UUID, senderSequenceNumber: Int, senderIdentifier: Data, within context: NSManagedObjectContext) {
        
        self.init(messageUIDFromEngine: messageUIDFromEngine,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                  ownedCryptoId: ownedCryptoId,
                  senderThreadIdentifier: senderThreadIdentifier,
                  senderSequenceNumber: senderSequenceNumber,
                  senderIdentifier: senderIdentifier,
                  entityName: Self.entityName,
                  within: context)
        
        self.rawContactCryptoId = contactCryptoId.getIdentity()
        
    }

    public static func createOrReplace(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, discussionId: ObvContactIdentifier, receivedMessageId: (senderThreadIdentifier: UUID, senderSequenceNumber: Int, senderIdentifier: Data), within context: NSManagedObjectContext) throws {
        let messageId = ObvMessageIdentifier(ownedCryptoId: discussionId.ownedCryptoId, uid: messageUIDFromEngine)
        let existingMessageIdentifierForLater = try Self.fetchMessageIdentifierForLater(messageId: messageId, within: context)
        if let existingMessageIdentifierForLater {
            if existingMessageIdentifierForLater is Self {
                return
            } else {
                try Self.batchDeleteMessageIdentifierForLater(messageId: messageId, within: context)
            }
        }
        _ = self.init(messageUIDFromEngine: messageUIDFromEngine,
                      messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                      ownedCryptoId: discussionId.ownedCryptoId,
                      contactCryptoId: discussionId.contactCryptoId,
                      senderThreadIdentifier: receivedMessageId.senderThreadIdentifier,
                      senderSequenceNumber: receivedMessageId.senderSequenceNumber,
                      senderIdentifier: receivedMessageId.senderIdentifier,
                      within: context)
    }

    // MARK: Fetching

    struct Predicate {
        enum Key: String {
            // MARK: Attributes (for the oneToOne discussion)
            case rawContactCryptoId = "rawContactCryptoId"
        }
        private static func withContactCryptoId(_ contactCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawContactCryptoId, EqualToData: contactCryptoId.getIdentity())
        }
        private static func withOneToOneDiscussionIdentifier(_ obvContactIdentifier: ObvContactIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                MessageIdentifierForLater.Predicate.withOwnedCryptoId(obvContactIdentifier.ownedCryptoId),
                withContactCryptoId(obvContactIdentifier.contactCryptoId),
            ])
        }
        static func withId(discussionId: ObvContactIdentifier, receivedMessageId: (senderThreadIdentifier: UUID, senderSequenceNumber: Int, senderIdentifier: Data)) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withOneToOneDiscussionIdentifier(discussionId),
                MessageIdentifierForLaterExpectingReceivedMessage.Predicate.withReceivedMessageIdentifier(
                    senderThreadIdentifier: receivedMessageId.senderThreadIdentifier,
                    senderSequenceNumber: receivedMessageId.senderSequenceNumber,
                    senderIdentifier: receivedMessageId.senderIdentifier),
            ])
        }
    }

    @nonobjc private static func fetchRequest() -> NSFetchRequest<MessageIdentifierForLaterExpectingReceivedMessageInOneToOneDiscussion> {
        return NSFetchRequest<MessageIdentifierForLaterExpectingReceivedMessageInOneToOneDiscussion>(entityName: Self.entityName)
    }

    @nonobjc private static func dictionaryFetchRequest() -> NSFetchRequest<NSDictionary> {
        return NSFetchRequest<NSDictionary>(entityName: Self.entityName)
    }

    public static func fetchMessageIdentifiersForLater(discussionId: ObvContactIdentifier, receivedMessageId: (senderThreadIdentifier: UUID, senderSequenceNumber: Int, senderIdentifier: Data), within context: NSManagedObjectContext) throws -> [ObvMessageIdentifier] {
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()
        request.predicate = Predicate.withId(discussionId: discussionId, receivedMessageId: receivedMessageId)
        return try Self.fetchMessageIdentifiersForLaterExpectingMessage(request: request, within: context)
    }

    public static func getAllExpectedMessageAppIdentifier(within context: NSManagedObjectContext) throws -> [ObvMessageAppIdentifier] {
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()

        request.resultType = .dictionaryResultType
        request.includesPendingChanges = true

        let propertiesToFetchForOneToOneDiscussionId: [String] = [
            MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue,
            Predicate.Key.rawContactCryptoId.rawValue,
        ]
        let propertiesToFetchForReceivedMessage: [String] = [
            MessageIdentifierForLaterExpectingReceivedMessage.Predicate.Key.senderThreadIdentifier.rawValue,
            MessageIdentifierForLaterExpectingReceivedMessage.Predicate.Key.senderSequenceNumber.rawValue,
            MessageIdentifierForLaterExpectingReceivedMessage.Predicate.Key.senderIdentifier.rawValue,
        ]
        request.propertiesToFetch = propertiesToFetchForOneToOneDiscussionId + propertiesToFetchForReceivedMessage
        
        guard let results = try context.fetch(request) as? [[String: Any]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }
        
        let valuesToReturn: [ObvMessageAppIdentifier] = try results.map { dict in
            // OneToOne discussion Id
            guard let rawOwnedIdentity = dict[MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawContactCryptoId = dict[Predicate.Key.rawContactCryptoId.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedIdentity) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let contactCryptoId = try? ObvCryptoId(identity: rawContactCryptoId) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            let discussionId = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            // Received message Id
            guard let senderThreadIdentifier = dict[MessageIdentifierForLaterExpectingReceivedMessage.Predicate.Key.senderThreadIdentifier.rawValue] as? UUID else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let senderSequenceNumber = dict[MessageIdentifierForLaterExpectingReceivedMessage.Predicate.Key.senderSequenceNumber.rawValue] as? Int else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let senderIdentifier = dict[MessageIdentifierForLaterExpectingReceivedMessage.Predicate.Key.senderIdentifier.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            // Construct and return ObvMessageAppIdentifier
            return ObvMessageAppIdentifier.received(
                discussionIdentifier: .oneToOne(id: discussionId),
                senderIdentifier: senderIdentifier,
                senderThreadIdentifier: senderThreadIdentifier,
                senderSequenceNumber: senderSequenceNumber)
        }
        
        return valuesToReturn

    }

}


@objc(MessageIdentifierForLaterExpectingSentMessageInGroupV1Discussion)
public final class MessageIdentifierForLaterExpectingSentMessageInGroupV1Discussion: MessageIdentifierForLaterExpectingSentMessage {
    
    private static let entityName = "MessageIdentifierForLaterExpectingSentMessageInGroupV1Discussion"

    // MARK: Attributes (for the groupV1 discussion identifier)
    @NSManaged private var rawGroupOwner: Data? // Non-optional in the model
    @NSManaged private var rawGroupV1UID: Data? // Non-optional in the model

    fileprivate convenience init(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, ownedCryptoId: ObvCryptoId, groupOwner: ObvCryptoId, groupV1UID: UID, senderThreadIdentifier: UUID, senderSequenceNumber: Int, within context: NSManagedObjectContext) {
        
        self.init(messageUIDFromEngine: messageUIDFromEngine,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                  ownedCryptoId: ownedCryptoId,
                  senderThreadIdentifier: senderThreadIdentifier,
                  senderSequenceNumber: senderSequenceNumber,
                  entityName: Self.entityName,
                  within: context)
        
        self.rawGroupOwner = groupOwner.getIdentity()
        self.rawGroupV1UID = groupV1UID.raw
        
    }

    public static func createOrReplace(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, discussionId: ObvGroupV1Identifier, sentMessageId: (senderThreadIdentifier: UUID, senderSequenceNumber: Int), within context: NSManagedObjectContext) throws {
        let messageId = ObvMessageIdentifier(ownedCryptoId: discussionId.ownedCryptoId, uid: messageUIDFromEngine)
        let existingMessageIdentifierForLater = try Self.fetchMessageIdentifierForLater(messageId: messageId, within: context)
        if let existingMessageIdentifierForLater {
            if existingMessageIdentifierForLater is Self {
                return
            } else {
                try Self.batchDeleteMessageIdentifierForLater(messageId: messageId, within: context)
            }
        }
        _ = self.init(messageUIDFromEngine: messageUIDFromEngine,
                      messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                      ownedCryptoId: discussionId.ownedCryptoId,
                      groupOwner: discussionId.groupV1Identifier.groupOwner,
                      groupV1UID: discussionId.groupV1Identifier.groupUid,
                      senderThreadIdentifier: sentMessageId.senderThreadIdentifier,
                      senderSequenceNumber: sentMessageId.senderSequenceNumber,
                      within: context)
    }

    // MARK: Fetching

    private struct Predicate {
        enum Key: String {
            // MARK: Attributes (for the group V1 discussion)
            case rawGroupOwner = "rawGroupOwner"
            case rawGroupV1UID = "rawGroupV1UID"
        }
        private static func withGroupOwner(_ groupOwner: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawGroupOwner, EqualToData: groupOwner.getIdentity())
        }
        private static func withGroupV1UID(_ groupUID: UID) -> NSPredicate {
            NSPredicate(Key.rawGroupV1UID, EqualToData: groupUID.raw)
        }
        private static func withGroupV1Identifier(_ groupV1Identifier: GroupV1Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withGroupOwner(groupV1Identifier.groupOwner),
                withGroupV1UID(groupV1Identifier.groupUid),
            ])
        }
        private static func withObvGroupV1Identifier(_ obvGroupV1Identifier: ObvGroupV1Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                MessageIdentifierForLater.Predicate.withOwnedCryptoId(obvGroupV1Identifier.ownedCryptoId),
                withGroupV1Identifier(obvGroupV1Identifier.groupV1Identifier),
            ])
        }
        static func withId(discussionId: ObvGroupV1Identifier, sentMessageId: (senderThreadIdentifier: UUID, senderSequenceNumber: Int)) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withObvGroupV1Identifier(discussionId),
                MessageIdentifierForLaterExpectingSentMessage.Predicate.withSentMessageIdentifier(
                    senderThreadIdentifier: sentMessageId.senderThreadIdentifier,
                    senderSequenceNumber: sentMessageId.senderSequenceNumber),
            ])
        }
    }

    @nonobjc private static func fetchRequest() -> NSFetchRequest<MessageIdentifierForLaterExpectingSentMessageInGroupV1Discussion> {
        return NSFetchRequest<MessageIdentifierForLaterExpectingSentMessageInGroupV1Discussion>(entityName: Self.entityName)
    }

    @nonobjc private static func dictionaryFetchRequest() -> NSFetchRequest<NSDictionary> {
        return NSFetchRequest<NSDictionary>(entityName: Self.entityName)
    }

    public static func fetchMessageIdentifiersForLater(discussionId: ObvGroupV1Identifier, sentMessageId: (senderThreadIdentifier: UUID, senderSequenceNumber: Int), within context: NSManagedObjectContext) throws -> [ObvMessageIdentifier] {
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()
        request.predicate = Predicate.withId(discussionId: discussionId, sentMessageId: sentMessageId)
        return try Self.fetchMessageIdentifiersForLaterExpectingMessage(request: request, within: context)
    }

    public static func getAllExpectedMessageAppIdentifier(within context: NSManagedObjectContext) throws -> [ObvMessageAppIdentifier] {
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()

        request.resultType = .dictionaryResultType
        request.includesPendingChanges = true

        let propertiesToFetchForGroupV1DiscussionId: [String] = [
            MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue,
            Self.Predicate.Key.rawGroupOwner.rawValue,
            Self.Predicate.Key.rawGroupV1UID.rawValue,
        ]
        let propertiesToFetchForSentMessage: [String] = [
            MessageIdentifierForLaterExpectingSentMessage.Predicate.Key.senderThreadIdentifier.rawValue,
            MessageIdentifierForLaterExpectingSentMessage.Predicate.Key.senderSequenceNumber.rawValue,
        ]
        request.propertiesToFetch = propertiesToFetchForGroupV1DiscussionId + propertiesToFetchForSentMessage
        
        guard let results = try context.fetch(request) as? [[String: Any]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }
        
        let valuesToReturn: [ObvMessageAppIdentifier] = try results.map { dict in
            // Group V1 discussion Id
            guard let rawOwnedIdentity = dict[MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawGroupOwner = dict[Predicate.Key.rawGroupOwner.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawGroupV1UID = dict[Predicate.Key.rawGroupV1UID.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedIdentity) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let groupOwner = try? ObvCryptoId(identity: rawGroupOwner) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let groupUid = UID(uid: rawGroupV1UID) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            let groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            let discussionId = ObvGroupV1Identifier(ownedCryptoId: ownedCryptoId, groupV1Identifier: groupV1Identifier)
            // Sent message Id
            guard let senderThreadIdentifier = dict[MessageIdentifierForLaterExpectingSentMessage.Predicate.Key.senderThreadIdentifier.rawValue] as? UUID else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let senderSequenceNumber = dict[MessageIdentifierForLaterExpectingSentMessage.Predicate.Key.senderSequenceNumber.rawValue] as? Int else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            // Construct and return ObvMessageAppIdentifier
            return ObvMessageAppIdentifier.sent(
                discussionIdentifier: .groupV1(id: discussionId),
                senderThreadIdentifier: senderThreadIdentifier,
                senderSequenceNumber: senderSequenceNumber)
        }
        
        return valuesToReturn

    }

}


@objc(MessageIdentifierForLaterExpectingReceivedMessageInGroupV1Discussion)
public final class MessageIdentifierForLaterExpectingReceivedMessageInGroupV1Discussion: MessageIdentifierForLaterExpectingReceivedMessage {
    
    private static let entityName = "MessageIdentifierForLaterExpectingReceivedMessageInGroupV1Discussion"

    // MARK: Attributes (for the groupV1 discussion identifier)
    @NSManaged private var rawGroupOwner: Data? // Non-optional in the model
    @NSManaged private var rawGroupV1UID: Data? // Non-optional in the model

    fileprivate convenience init(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, ownedCryptoId: ObvCryptoId, groupOwner: ObvCryptoId, groupV1UID: UID, senderThreadIdentifier: UUID, senderSequenceNumber: Int, senderIdentifier: Data, within context: NSManagedObjectContext) {
        
        self.init(messageUIDFromEngine: messageUIDFromEngine,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                  ownedCryptoId: ownedCryptoId,
                  senderThreadIdentifier: senderThreadIdentifier,
                  senderSequenceNumber: senderSequenceNumber,
                  senderIdentifier: senderIdentifier,
                  entityName: Self.entityName,
                  within: context)
        
        self.rawGroupOwner = groupOwner.getIdentity()
        self.rawGroupV1UID = groupV1UID.raw

    }

    public static func createOrReplace(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, discussionId: ObvGroupV1Identifier, receivedMessageId: (senderThreadIdentifier: UUID, senderSequenceNumber: Int, senderIdentifier: Data), within context: NSManagedObjectContext) throws {
        let messageId = ObvMessageIdentifier(ownedCryptoId: discussionId.ownedCryptoId, uid: messageUIDFromEngine)
        let existingMessageIdentifierForLater = try Self.fetchMessageIdentifierForLater(messageId: messageId, within: context)
        if let existingMessageIdentifierForLater {
            if existingMessageIdentifierForLater is Self {
                return
            } else {
                try Self.batchDeleteMessageIdentifierForLater(messageId: messageId, within: context)
            }
        }
        _ = self.init(messageUIDFromEngine: messageUIDFromEngine,
                      messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                      ownedCryptoId: discussionId.ownedCryptoId,
                      groupOwner: discussionId.groupV1Identifier.groupOwner,
                      groupV1UID: discussionId.groupV1Identifier.groupUid,
                      senderThreadIdentifier: receivedMessageId.senderThreadIdentifier,
                      senderSequenceNumber: receivedMessageId.senderSequenceNumber,
                      senderIdentifier: receivedMessageId.senderIdentifier,
                      within: context)
    }

    // MARK: Fetching

    private struct Predicate {
        enum Key: String {
            // MARK: Attributes (for the group V1 discussion)
            case rawGroupOwner = "rawGroupOwner"
            case rawGroupV1UID = "rawGroupV1UID"
        }
        private static func withGroupOwner(_ groupOwner: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawGroupOwner, EqualToData: groupOwner.getIdentity())
        }
        private static func withGroupV1UID(_ groupUID: UID) -> NSPredicate {
            NSPredicate(Key.rawGroupV1UID, EqualToData: groupUID.raw)
        }
        private static func withGroupV1Identifier(_ groupV1Identifier: GroupV1Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withGroupOwner(groupV1Identifier.groupOwner),
                withGroupV1UID(groupV1Identifier.groupUid),
            ])
        }
        private static func withObvGroupV1Identifier(_ obvGroupV1Identifier: ObvGroupV1Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                MessageIdentifierForLater.Predicate.withOwnedCryptoId(obvGroupV1Identifier.ownedCryptoId),
                withGroupV1Identifier(obvGroupV1Identifier.groupV1Identifier),
            ])
        }
        static func withId(discussionId: ObvGroupV1Identifier, receivedMessageId: (senderThreadIdentifier: UUID, senderSequenceNumber: Int, senderIdentifier: Data)) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withObvGroupV1Identifier(discussionId),
                MessageIdentifierForLaterExpectingReceivedMessage.Predicate.withReceivedMessageIdentifier(
                    senderThreadIdentifier: receivedMessageId.senderThreadIdentifier,
                    senderSequenceNumber: receivedMessageId.senderSequenceNumber,
                    senderIdentifier: receivedMessageId.senderIdentifier),
            ])
        }
    }

    @nonobjc private static func fetchRequest() -> NSFetchRequest<MessageIdentifierForLaterExpectingReceivedMessageInGroupV1Discussion> {
        return NSFetchRequest<MessageIdentifierForLaterExpectingReceivedMessageInGroupV1Discussion>(entityName: Self.entityName)
    }

    @nonobjc private static func dictionaryFetchRequest() -> NSFetchRequest<NSDictionary> {
        return NSFetchRequest<NSDictionary>(entityName: Self.entityName)
    }

    public static func fetchMessageIdentifiersForLater(discussionId: ObvGroupV1Identifier, receivedMessageId: (senderThreadIdentifier: UUID, senderSequenceNumber: Int, senderIdentifier: Data), within context: NSManagedObjectContext) throws -> [ObvMessageIdentifier] {
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()
        request.predicate = Predicate.withId(discussionId: discussionId, receivedMessageId: receivedMessageId)
        return try Self.fetchMessageIdentifiersForLaterExpectingMessage(request: request, within: context)
    }

    public static func getAllExpectedMessageAppIdentifier(within context: NSManagedObjectContext) throws -> [ObvMessageAppIdentifier] {
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()

        request.resultType = .dictionaryResultType
        request.includesPendingChanges = true

        let propertiesToFetchForGroupV1DiscussionId: [String] = [
            MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue,
            Self.Predicate.Key.rawGroupOwner.rawValue,
            Self.Predicate.Key.rawGroupV1UID.rawValue,
        ]
        let propertiesToFetchForReceivedMessage: [String] = [
            MessageIdentifierForLaterExpectingReceivedMessage.Predicate.Key.senderThreadIdentifier.rawValue,
            MessageIdentifierForLaterExpectingReceivedMessage.Predicate.Key.senderSequenceNumber.rawValue,
            MessageIdentifierForLaterExpectingReceivedMessage.Predicate.Key.senderIdentifier.rawValue,
        ]
        request.propertiesToFetch = propertiesToFetchForGroupV1DiscussionId + propertiesToFetchForReceivedMessage
        
        guard let results = try context.fetch(request) as? [[String: Any]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }
        
        let valuesToReturn: [ObvMessageAppIdentifier] = try results.map { dict in
            // Group V1 discussion Id
            guard let rawOwnedIdentity = dict[MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawGroupOwner = dict[Predicate.Key.rawGroupOwner.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawGroupV1UID = dict[Predicate.Key.rawGroupV1UID.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedIdentity) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let groupOwner = try? ObvCryptoId(identity: rawGroupOwner) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let groupUid = UID(uid: rawGroupV1UID) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            let groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
            let discussionId = ObvGroupV1Identifier(ownedCryptoId: ownedCryptoId, groupV1Identifier: groupV1Identifier)
            // Received message Id
            guard let senderThreadIdentifier = dict[MessageIdentifierForLaterExpectingReceivedMessage.Predicate.Key.senderThreadIdentifier.rawValue] as? UUID else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let senderSequenceNumber = dict[MessageIdentifierForLaterExpectingReceivedMessage.Predicate.Key.senderSequenceNumber.rawValue] as? Int else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let senderIdentifier = dict[MessageIdentifierForLaterExpectingReceivedMessage.Predicate.Key.senderIdentifier.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            // Construct and return ObvMessageAppIdentifier
            return ObvMessageAppIdentifier.received(
                discussionIdentifier: .groupV1(id: discussionId),
                senderIdentifier: senderIdentifier,
                senderThreadIdentifier: senderThreadIdentifier,
                senderSequenceNumber: senderSequenceNumber)
        }
        
        return valuesToReturn

    }

}


@objc(MessageIdentifierForLaterExpectingSentMessageInGroupV2Discussion)
public final class MessageIdentifierForLaterExpectingSentMessageInGroupV2Discussion: MessageIdentifierForLaterExpectingSentMessage {
    
    private static let entityName = "MessageIdentifierForLaterExpectingSentMessageInGroupV2Discussion"

    // MARK: Attributes (for the groupV2 discussion identifier)
    @NSManaged private var rawCategory: Int
    @NSManaged private var rawGroupV2UID: Data? // Non-optional in the model
    @NSManaged private var serverURL: URL? // Non-optional in the model

    fileprivate convenience init(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, ownedCryptoId: ObvCryptoId, category: ObvGroupV2.Identifier.Category, groupV2UID: UID, serverURL: URL, senderThreadIdentifier: UUID, senderSequenceNumber: Int, within context: NSManagedObjectContext) {
        
        self.init(messageUIDFromEngine: messageUIDFromEngine,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                  ownedCryptoId: ownedCryptoId,
                  senderThreadIdentifier: senderThreadIdentifier,
                  senderSequenceNumber: senderSequenceNumber,
                  entityName: Self.entityName,
                  within: context)
        
        self.rawCategory = category.rawValue
        self.rawGroupV2UID = groupV2UID.raw
        self.serverURL = serverURL
        
    }

    public static func createOrReplace(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, discussionId: ObvGroupV2Identifier, sentMessageId: (senderThreadIdentifier: UUID, senderSequenceNumber: Int), within context: NSManagedObjectContext) throws {
        let messageId = ObvMessageIdentifier(ownedCryptoId: discussionId.ownedCryptoId, uid: messageUIDFromEngine)
        let existingMessageIdentifierForLater = try Self.fetchMessageIdentifierForLater(messageId: messageId, within: context)
        if let existingMessageIdentifierForLater {
            if existingMessageIdentifierForLater is Self {
                return
            } else {
                try Self.batchDeleteMessageIdentifierForLater(messageId: messageId, within: context)
            }
        }
        _ = self.init(messageUIDFromEngine: messageUIDFromEngine,
                      messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                      ownedCryptoId: discussionId.ownedCryptoId,
                      category: discussionId.identifier.category,
                      groupV2UID: discussionId.identifier.groupUID,
                      serverURL: discussionId.identifier.serverURL,
                      senderThreadIdentifier: sentMessageId.senderThreadIdentifier,
                      senderSequenceNumber: sentMessageId.senderSequenceNumber,
                      within: context)
    }

    // MARK: Fetching
    
    private struct Predicate {
        enum Key: String {
            // MARK: Attributes (for the group v2 discussion)
            case rawCategory = "rawCategory"
            case rawGroupV2UID = "rawGroupV2UID"
            case serverURL = "serverURL"
        }
        private static func withCategory(_ category: ObvGroupV2.Identifier.Category) -> NSPredicate {
            NSPredicate(Key.rawCategory, EqualToInt: category.rawValue)
        }
        private static func withGroupV2UID(_ groupUID: UID) -> NSPredicate {
            NSPredicate(Key.rawGroupV2UID, EqualToData: groupUID.raw)
        }
        private static func withServerURL(_ serverURL: URL) -> NSPredicate {
            NSPredicate(Key.serverURL, EqualToUrl: serverURL)
        }
        private static func withGroupV2Identifier(_ identifier: ObvGroupV2.Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withCategory(identifier.category),
                withGroupV2UID(identifier.groupUID),
                withServerURL(identifier.serverURL),
            ])
        }
        private static func withObvGroupV2Identifier(_ obvGroupV2Identifier: ObvGroupV2Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                MessageIdentifierForLater.Predicate.withOwnedCryptoId(obvGroupV2Identifier.ownedCryptoId),
                withGroupV2Identifier(obvGroupV2Identifier.identifier),
            ])
        }
        static func withId(discussionId: ObvGroupV2Identifier, sentMessageId: (senderThreadIdentifier: UUID, senderSequenceNumber: Int)) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withObvGroupV2Identifier(discussionId),
                MessageIdentifierForLaterExpectingSentMessage.Predicate.withSentMessageIdentifier(
                    senderThreadIdentifier: sentMessageId.senderThreadIdentifier,
                    senderSequenceNumber: sentMessageId.senderSequenceNumber),
            ])
        }
    }

    @nonobjc private static func fetchRequest() -> NSFetchRequest<MessageIdentifierForLaterExpectingSentMessageInGroupV2Discussion> {
        return NSFetchRequest<MessageIdentifierForLaterExpectingSentMessageInGroupV2Discussion>(entityName: Self.entityName)
    }

    @nonobjc private static func dictionaryFetchRequest() -> NSFetchRequest<NSDictionary> {
        return NSFetchRequest<NSDictionary>(entityName: Self.entityName)
    }

    public static func fetchMessageIdentifiersForLater(discussionId: ObvGroupV2Identifier, sentMessageId: (senderThreadIdentifier: UUID, senderSequenceNumber: Int), within context: NSManagedObjectContext) throws -> [ObvMessageIdentifier] {
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()
        request.predicate = Predicate.withId(discussionId: discussionId, sentMessageId: sentMessageId)
        return try Self.fetchMessageIdentifiersForLaterExpectingMessage(request: request, within: context)
    }

    public static func getAllExpectedMessageAppIdentifier(within context: NSManagedObjectContext) throws -> [ObvMessageAppIdentifier] {
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()

        request.resultType = .dictionaryResultType
        request.includesPendingChanges = true

        let propertiesToFetchForGroupV2DiscussionId: [String] = [
            MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue,
            Self.Predicate.Key.rawCategory.rawValue,
            Self.Predicate.Key.rawGroupV2UID.rawValue,
            Self.Predicate.Key.serverURL.rawValue,
        ]
        let propertiesToFetchForSentMessage: [String] = [
            MessageIdentifierForLaterExpectingSentMessage.Predicate.Key.senderThreadIdentifier.rawValue,
            MessageIdentifierForLaterExpectingSentMessage.Predicate.Key.senderSequenceNumber.rawValue,
        ]
        request.propertiesToFetch = propertiesToFetchForGroupV2DiscussionId + propertiesToFetchForSentMessage
        
        guard let results = try context.fetch(request) as? [[String: Any]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }
        
        let valuesToReturn: [ObvMessageAppIdentifier] = try results.map { dict in
            // Group V2 discussion Id
            guard let rawOwnedIdentity = dict[MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawCategory = dict[Self.Predicate.Key.rawCategory.rawValue] as? Int else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawGroupV2UID = dict[Self.Predicate.Key.rawGroupV2UID.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let serverURL = dict[Self.Predicate.Key.serverURL.rawValue] as? URL else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedIdentity) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let category = ObvGroupV2.Identifier.Category(rawValue: rawCategory) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let groupUID = UID(uid: rawGroupV2UID) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            let identifier = ObvGroupV2.Identifier(groupUID: groupUID, serverURL: serverURL, category: category)
            let discussionId = ObvGroupV2Identifier(ownedCryptoId: ownedCryptoId, identifier: identifier)
            // Sent message Id
            guard let senderThreadIdentifier = dict[MessageIdentifierForLaterExpectingSentMessage.Predicate.Key.senderThreadIdentifier.rawValue] as? UUID else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let senderSequenceNumber = dict[MessageIdentifierForLaterExpectingSentMessage.Predicate.Key.senderSequenceNumber.rawValue] as? Int else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            // Construct and return ObvMessageAppIdentifier
            return ObvMessageAppIdentifier.sent(
                discussionIdentifier: .groupV2(id: discussionId),
                senderThreadIdentifier: senderThreadIdentifier,
                senderSequenceNumber: senderSequenceNumber)
        }
        
        return valuesToReturn

    }

}


@objc(MessageIdentifierForLaterExpectingReceivedMessageInGroupV2Discussion)
public final class MessageIdentifierForLaterExpectingReceivedMessageInGroupV2Discussion: MessageIdentifierForLaterExpectingReceivedMessage {
    
    private static let entityName = "MessageIdentifierForLaterExpectingReceivedMessageInGroupV2Discussion"

    // MARK: Attributes (for the groupV2 discussion identifier)
    @NSManaged private var rawCategory: Int
    @NSManaged private var rawGroupV2UID: Data? // Non-optional in the model
    @NSManaged private var serverURL: URL? // Non-optional in the model

    fileprivate convenience init(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, ownedCryptoId: ObvCryptoId, category: ObvGroupV2.Identifier.Category, groupV2UID: UID, serverURL: URL, senderThreadIdentifier: UUID, senderSequenceNumber: Int, senderIdentifier: Data, within context: NSManagedObjectContext) {
        
        self.init(messageUIDFromEngine: messageUIDFromEngine,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                  ownedCryptoId: ownedCryptoId,
                  senderThreadIdentifier: senderThreadIdentifier,
                  senderSequenceNumber: senderSequenceNumber,
                  senderIdentifier: senderIdentifier,
                  entityName: Self.entityName,
                  within: context)
        
        self.rawCategory = category.rawValue
        self.rawGroupV2UID = groupV2UID.raw
        self.serverURL = serverURL

    }

    public static func createOrReplace(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, discussionId: ObvGroupV2Identifier, receivedMessageId: (senderThreadIdentifier: UUID, senderSequenceNumber: Int, senderIdentifier: Data), within context: NSManagedObjectContext) throws {
        let messageId = ObvMessageIdentifier(ownedCryptoId: discussionId.ownedCryptoId, uid: messageUIDFromEngine)
        let existingMessageIdentifierForLater = try Self.fetchMessageIdentifierForLater(messageId: messageId, within: context)
        if let existingMessageIdentifierForLater {
            if existingMessageIdentifierForLater is Self {
                return
            } else {
                try Self.batchDeleteMessageIdentifierForLater(messageId: messageId, within: context)
            }
        }
        _ = self.init(messageUIDFromEngine: messageUIDFromEngine,
                      messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                      ownedCryptoId: discussionId.ownedCryptoId,
                      category: discussionId.identifier.category,
                      groupV2UID: discussionId.identifier.groupUID,
                      serverURL: discussionId.identifier.serverURL,
                      senderThreadIdentifier: receivedMessageId.senderThreadIdentifier,
                      senderSequenceNumber: receivedMessageId.senderSequenceNumber,
                      senderIdentifier: receivedMessageId.senderIdentifier,
                      within: context)
    }

    // MARK: Fetching
    
    private struct Predicate {
        enum Key: String {
            // MARK: Attributes (for the group v2 discussion)
            case rawCategory = "rawCategory"
            case rawGroupV2UID = "rawGroupV2UID"
            case serverURL = "serverURL"
        }
        private static func withCategory(_ category: ObvGroupV2.Identifier.Category) -> NSPredicate {
            NSPredicate(Key.rawCategory, EqualToInt: category.rawValue)
        }
        private static func withGroupV2UID(_ groupUID: UID) -> NSPredicate {
            NSPredicate(Key.rawGroupV2UID, EqualToData: groupUID.raw)
        }
        private static func withServerURL(_ serverURL: URL) -> NSPredicate {
            NSPredicate(Key.serverURL, EqualToUrl: serverURL)
        }
        private static func withGroupV2Identifier(_ identifier: ObvGroupV2.Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withCategory(identifier.category),
                withGroupV2UID(identifier.groupUID),
                withServerURL(identifier.serverURL),
            ])
        }
        private static func withObvGroupV2Identifier(_ obvGroupV2Identifier: ObvGroupV2Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                MessageIdentifierForLater.Predicate.withOwnedCryptoId(obvGroupV2Identifier.ownedCryptoId),
                withGroupV2Identifier(obvGroupV2Identifier.identifier),
            ])
        }
        static func withId(discussionId: ObvGroupV2Identifier, receivedMessageId: (senderThreadIdentifier: UUID, senderSequenceNumber: Int, senderIdentifier: Data)) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withObvGroupV2Identifier(discussionId),
                MessageIdentifierForLaterExpectingReceivedMessage.Predicate.withReceivedMessageIdentifier(
                    senderThreadIdentifier: receivedMessageId.senderThreadIdentifier,
                    senderSequenceNumber: receivedMessageId.senderSequenceNumber,
                    senderIdentifier: receivedMessageId.senderIdentifier),
            ])
        }
    }

    @nonobjc private static func fetchRequest() -> NSFetchRequest<MessageIdentifierForLaterExpectingReceivedMessageInGroupV2Discussion> {
        return NSFetchRequest<MessageIdentifierForLaterExpectingReceivedMessageInGroupV2Discussion>(entityName: Self.entityName)
    }

    @nonobjc private static func dictionaryFetchRequest() -> NSFetchRequest<NSDictionary> {
        return NSFetchRequest<NSDictionary>(entityName: Self.entityName)
    }

    public static func fetchMessageIdentifiersForLater(discussionId: ObvGroupV2Identifier, receivedMessageId: (senderThreadIdentifier: UUID, senderSequenceNumber: Int, senderIdentifier: Data), within context: NSManagedObjectContext) throws -> [ObvMessageIdentifier] {
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()
        request.predicate = Predicate.withId(discussionId: discussionId, receivedMessageId: receivedMessageId)
        return try Self.fetchMessageIdentifiersForLaterExpectingMessage(request: request, within: context)
    }

    public static func getAllExpectedMessageAppIdentifier(within context: NSManagedObjectContext) throws -> [ObvMessageAppIdentifier] {
        let request: NSFetchRequest<NSDictionary> = Self.dictionaryFetchRequest()

        request.resultType = .dictionaryResultType
        request.includesPendingChanges = true

        let propertiesToFetchForGroupV2DiscussionId: [String] = [
            MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue,
            Self.Predicate.Key.rawCategory.rawValue,
            Self.Predicate.Key.rawGroupV2UID.rawValue,
            Self.Predicate.Key.serverURL.rawValue,
        ]
        let propertiesToFetchForReceivedMessage: [String] = [
            MessageIdentifierForLaterExpectingReceivedMessage.Predicate.Key.senderThreadIdentifier.rawValue,
            MessageIdentifierForLaterExpectingReceivedMessage.Predicate.Key.senderSequenceNumber.rawValue,
            MessageIdentifierForLaterExpectingReceivedMessage.Predicate.Key.senderIdentifier.rawValue,
        ]
        request.propertiesToFetch = propertiesToFetchForGroupV2DiscussionId + propertiesToFetchForReceivedMessage
        
        guard let results = try context.fetch(request) as? [[String: Any]] else { assertionFailure(); throw ObvError.couldNotCastFetchedResult }
        
        let valuesToReturn: [ObvMessageAppIdentifier] = try results.map { dict in
            // Group V2 discussion Id
            guard let rawOwnedIdentity = dict[MessageIdentifierForLater.Predicate.Key.rawOwnedIdentity.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawCategory = dict[Self.Predicate.Key.rawCategory.rawValue] as? Int else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let rawGroupV2UID = dict[Self.Predicate.Key.rawGroupV2UID.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let serverURL = dict[Self.Predicate.Key.serverURL.rawValue] as? URL else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let ownedCryptoId = try? ObvCryptoId(identity: rawOwnedIdentity) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let category = ObvGroupV2.Identifier.Category(rawValue: rawCategory) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let groupUID = UID(uid: rawGroupV2UID) else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            let identifier = ObvGroupV2.Identifier(groupUID: groupUID, serverURL: serverURL, category: category)
            let discussionId = ObvGroupV2Identifier(ownedCryptoId: ownedCryptoId, identifier: identifier)
            // Received message Id
            guard let senderThreadIdentifier = dict[MessageIdentifierForLaterExpectingReceivedMessage.Predicate.Key.senderThreadIdentifier.rawValue] as? UUID else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let senderSequenceNumber = dict[MessageIdentifierForLaterExpectingReceivedMessage.Predicate.Key.senderSequenceNumber.rawValue] as? Int else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            guard let senderIdentifier = dict[MessageIdentifierForLaterExpectingReceivedMessage.Predicate.Key.senderIdentifier.rawValue] as? Data else {
                assertionFailure(); throw ObvError.couldNotCastFetchedResult
            }
            // Construct and return ObvMessageAppIdentifier
            return ObvMessageAppIdentifier.received(
                discussionIdentifier: .groupV2(id: discussionId),
                senderIdentifier: senderIdentifier,
                senderThreadIdentifier: senderThreadIdentifier,
                senderSequenceNumber: senderSequenceNumber)
        }
        
        return valuesToReturn

    }

}
