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
import ObvAppTypes
import ObvEngine
import OSLog
import ObvSettings

@objc(PersistedPollVote)
public class PersistedPollVote: NSManagedObject {
    
    private static let entityName = "PersistedPollVote"
    private let logger = Logger(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedPollVote")
    
    @NSManaged public private(set) var rawTimestamp: Date? // Non-optional in the model
    @NSManaged public private(set) var version: Int
    @NSManaged public private(set) var voted: Bool
    
    // MARK: - Relationships
    @NSManaged public private(set) var candidate: PersistedPollCandidate? // Non-optional in the model
    
    // MARK: - Initializer
    
    fileprivate convenience init(version: Int, voted: Bool, pollCandidate: PersistedPollCandidate, timestamp: Date, forEntityName entityName: String) throws {

        guard let context = pollCandidate.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.version = version
        self.voted = voted
        self.candidate = pollCandidate
        self.rawTimestamp = timestamp
    }
    
    /// Since `rawTimestamp` is non-optional in the Core Data model, we expect this property
    /// to return the value stored in `rawTimestamp`, except when the value is faulted and the Core Data object is deleted.
    public var timestamp: Date {
        rawTimestamp ?? .now
    }
    
    func update(version: Int, voted: Bool, timestamp: Date) {
        guard !self.isDeleted else { return }
        guard self.version <= version else { return }
        if self.version != version {
            self.version = version
        }
        
        if self.voted != voted {
            self.voted = voted
        }
        
        if self.rawTimestamp != timestamp {
            self.rawTimestamp = timestamp
        }
    }
}

extension PersistedPollVote {
    
    struct Predicate {
        
        enum Key: String {
            // Attributes
            case rawTimestamp = "rawTimestamp"
            case version = "version"
            case voted = "voted"
            // Relationships
            case candidate = "candidate"
        }
        
        static func withObjectID(_ objectID: TypeSafeManagedObjectID<PersistedPollVote>) -> NSPredicate {
            NSPredicate(withObjectID: objectID.objectID)
        }
        
        static func withCandidateObjectID(_ objectID: TypeSafeManagedObjectID<PersistedPollCandidate>) -> NSPredicate {
            NSPredicate(Key.candidate, equalToObjectWithObjectID: objectID.objectID)
        }
        
    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedPollVote> {
        return NSFetchRequest<PersistedPollVote>(entityName: PersistedPollVote.entityName)
    }

    
    /// Returns an `NSFetchedResultsController` for all the `PersistedPollVote`s associated to the given `PersistedPollCandidate`.
    public static func getFetchedResultsController(pollCandidateObjectID: TypeSafeManagedObjectID<PersistedPollCandidate>, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedPollVote> {
        let request: NSFetchRequest<PersistedPollVote> = PersistedPollVote.fetchRequest()
        request.predicate = Predicate.withCandidateObjectID(pollCandidateObjectID)
        request.fetchBatchSize = 500
        request.sortDescriptors = []
        request.propertiesToFetch = []
        return .init(fetchRequest: request,
                     managedObjectContext: context,
                     sectionNameKeyPath: nil,
                     cacheName: nil)
    }
    
    
    public static func getFetchedResultsController(objectID: TypeSafeManagedObjectID<PersistedPollVote>, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedPollVote> {
        let request: NSFetchRequest<PersistedPollVote> = PersistedPollVote.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID)
        request.fetchLimit = 1
        request.sortDescriptors = []
        request.propertiesToFetch = []
        return .init(fetchRequest: request,
                     managedObjectContext: context,
                     sectionNameKeyPath: nil,
                     cacheName: nil)
    }
    
    
    public static func get(objectID: TypeSafeManagedObjectID<PersistedPollVote>, within context: NSManagedObjectContext) throws -> PersistedPollVote? {
        let request: NSFetchRequest<PersistedPollVote> = PersistedPollVote.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

}

@objc(PersistedPollVoteSent)
public final class PersistedPollVoteSent: PersistedPollVote {
    
    private static let entityName = "PersistedPollVoteSent"
    
    convenience init(version: Int, voted: Bool, timestamp: Date, pollCandidate: PersistedPollCandidate) throws {
        try self.init(version: version, voted: voted, pollCandidate: pollCandidate, timestamp: timestamp, forEntityName: Self.entityName)
    }
    
}

@objc(PersistedPollVoteReceived)
public final class PersistedPollVoteReceived: PersistedPollVote {
    
    private static let entityName = "PersistedPollVoteReceived"
    
    // MARK: - Attributes
    @NSManaged private(set) var contactIdentity: Data? // Non-optional in the model
    
    // MARK: - Relationships
    @NSManaged public private(set) var contact: PersistedObvContactIdentity? // Optional in the model
    
    /// Expected to be non-nil, even if the contact was deleted
    public var contactCryptoId: ObvCryptoId? {
        guard let contactIdentity else { assertionFailure(); return nil }
        return try? ObvCryptoId(identity: contactIdentity)
    }
    
    convenience init(version: Int, voted: Bool, timestamp: Date, pollCandidate: PersistedPollCandidate, contact: PersistedObvContactIdentity) throws {
        try self.init(version: version, voted: voted, pollCandidate: pollCandidate, timestamp: timestamp, forEntityName: Self.entityName)
        self.contactIdentity = contact.identity
        self.contact = contact
    }
    
    func setContactIfCurrentlyNil(to newContact: PersistedObvContactIdentity) {
        guard self.contact == nil else { assertionFailure(); return }
        guard self.contactIdentity == newContact.identity else { assertionFailure(); return }
        self.contact = newContact
    }
    
    struct Predicate {
        
        enum Key: String {
            // Attributes
            case contactIdentity = "contactIdentity"
            // Relationships
            case contact = "contact"
        }
        
        static func withContactCryptoId(_ contactCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.contactIdentity, EqualToData: contactCryptoId.getIdentity())
        }
        
        static var withNilContact: NSPredicate {
            NSPredicate(withNilValueForKey: Key.contact)
        }
        
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            let key: String = [PersistedPollVote.Predicate.Key.candidate.rawValue,
                               PersistedPollCandidate.Predicate.Key.poll.rawValue,
                               PersistedPoll.Predicate.Key.message.rawValue,
                               PersistedMessage.Predicate.Key.discussion.rawValue,
                               PersistedDiscussion.Predicate.Key.ownedIdentity.rawValue,
                               PersistedObvOwnedIdentity.Predicate.Key.identity.rawValue,
            ].joined(separator: ".")
            return NSPredicate(key, EqualToData: ownedCryptoId.getIdentity())
        }
        
    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedPollVoteReceived> {
        return NSFetchRequest<PersistedPollVoteReceived>(entityName: PersistedPollVoteReceived.entityName)
    }

    static func getPersistedPollVoteReceivedWithNoAssociatedContact(withContactCryptoId contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> [PersistedPollVoteReceived] {
        let request: NSFetchRequest<PersistedPollVoteReceived> = PersistedPollVoteReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withNilContact,
            Predicate.withContactCryptoId(contactCryptoId),
            Predicate.withOwnedCryptoId(ownedCryptoId),
        ])
        request.fetchBatchSize = 500
        return try context.fetch(request)
    }

}
