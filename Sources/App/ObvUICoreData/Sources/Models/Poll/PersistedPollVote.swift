/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
    
    // Relationships
    
    @NSManaged public private(set) var candidate: PersistedPollCandidate? // Non-optional in the model
    
    // Initializer
    
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
    
    /// Returns `true` iff the update visibly changed the vote, i.e., iff the `voted` flag changed. A version or timestamp change alone is not user visible.
    @discardableResult
    func update(version: Int, voted: Bool, timestamp: Date) -> Bool {
        guard !self.isDeleted else { return false }
        guard self.version <= version else { return false }
        if self.version != version {
            self.version = version
        }

        let votedChanged = self.voted != voted
        if votedChanged {
            self.voted = voted
        }

        if self.rawTimestamp != timestamp {
            self.rawTimestamp = timestamp
        }

        return votedChanged
    }
}

// MARK: History transfer

extension PersistedPollVote {
    
    static func createDuringHistoryTransfer(pollVote: ObvHistoryReceivedMessage.PollVote, candidate: PersistedPollCandidate) throws {
        guard let ownedCryptoId = candidate.poll?.message?.discussion?.ownedIdentity?.cryptoId else {
            assertionFailure()
            throw ObvUICoreDataError.couldNotDetermineOwnedCryptoId
        }
        if pollVote.sender == ownedCryptoId {
            try PersistedPollVoteSent.createSentDuringHistoryTransfer(pollVote: pollVote, candidate: candidate)
        } else {
            try PersistedPollVoteReceived.createReceivedDuringHistoryTransfer(pollVote: pollVote, candidate: candidate)
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
        
        static func whereVotedIs(_ bool: Bool) -> NSPredicate {
            NSPredicate(Key.voted, is: bool)
        }
        
        static func withPoll(objectID: TypeSafeManagedObjectID<PersistedPoll>) -> NSPredicate {
            let key: String = [
                Key.candidate.rawValue,
                PersistedPollCandidate.Predicate.Key.poll.rawValue,
            ].joined(separator: ".")
            return NSPredicate(key, equalToObjectWithObjectID: objectID.objectID)
        }

        static func withPollInDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) -> NSPredicate {
            let key: String = [
                Key.candidate.rawValue,
                PersistedPollCandidate.Predicate.Key.poll.rawValue,
                PersistedPoll.Predicate.Key.message.rawValue,
                PersistedMessage.Predicate.Key.discussion.rawValue,
            ].joined(separator: ".")
            return NSPredicate(key, equalToObjectWithObjectID: discussionObjectID.objectID)
        }

        static func withTimestampLaterThan(_ date: Date) -> NSPredicate {
            NSPredicate(Key.rawTimestamp, laterThan: date)
        }

        static func withTimestampEarlierOrEqualTo(_ date: Date) -> NSPredicate {
            NSPredicate(Key.rawTimestamp, earlierOrEqualTo: date)
        }

        static func withTimestampInTimeInterval(startDate: Date, endDate: Date) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withTimestampLaterThan(startDate),
                withTimestampEarlierOrEqualTo(endDate),
            ])
        }

    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedPollVote> {
        return NSFetchRequest<PersistedPollVote>(entityName: PersistedPollVote.entityName)
    }

    
    /// Returns an `NSFetchedResultsController` for every `PersistedPollVote` cast on any answer of the given `PersistedPoll`.
    ///
    /// It exists because **a vote is what changes when anyone votes**: casting one inserts or updates a `PersistedPollVote` and touches neither the poll nor the
    /// message showing it. A screen watching only those two therefore misses the very thing it is drawing — which is what the poll bubble of the SwiftUI discussion
    /// screen did until it watched this as well.
    public static func getFetchedResultsController(pollObjectID: TypeSafeManagedObjectID<PersistedPoll>, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedPollVote> {
        let request: NSFetchRequest<PersistedPollVote> = PersistedPollVote.fetchRequest()
        request.predicate = Predicate.withPoll(objectID: pollObjectID)
        request.fetchBatchSize = 500
        request.sortDescriptors = []
        return .init(fetchRequest: request,
                     managedObjectContext: context,
                     sectionNameKeyPath: nil,
                     cacheName: nil)
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



// MARK: - PersistedPollVoteSent

@objc(PersistedPollVoteSent)
public final class PersistedPollVoteSent: PersistedPollVote {
    
    private static let entityName = "PersistedPollVoteSent"
    
    convenience init(version: Int, voted: Bool, timestamp: Date, pollCandidate: PersistedPollCandidate) throws {
        try self.init(version: version, voted: voted, pollCandidate: pollCandidate, timestamp: timestamp, forEntityName: Self.entityName)
    }
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PersistedPollVoteSent> {
        return NSFetchRequest<PersistedPollVoteSent>(entityName: entityName)
    }

    /// When a group member status changes from pending to non-pending, we need to send them the current user's (sent) votes that were set or updated
    /// in the group during the member's pending period: the member did not receive them, since pending members are excluded from the active participants.
    /// This method returns these votes. Note that the filter is on the *vote's* timestamp, not the message's: a vote made during the pending period
    /// on an older poll was missed by the member too.
    public static func getPollVoteSentOnGroupMessages(groupIdentifier: ObvGroupV2Identifier,
                                                      dateInterval: PersistedGroupV2Member.DateInterval,
                                                      within context: NSManagedObjectContext) throws -> [(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, pollVoteCandidateUuid: UUID, version: Int, originalServerTimestamp: Date)] {
        // Determine the objectID of the discussion associated to the group
        guard let groupV2 = try PersistedGroupV2.get(groupIdentifier: groupIdentifier, within: context) else {
            assertionFailure()
            throw ObvUICoreDataError.couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
        }
        guard let objectIDOfGroupDiscussion = groupV2.discussion?.typedObjectID else {
            assertionFailure()
            throw ObvUICoreDataError.couldNotFindDiscussion
        }
        // Find all the sent votes of the discussion that were set or updated in the date interval.
        let request: NSFetchRequest<PersistedPollVoteSent> = PersistedPollVoteSent.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            PersistedPollVote.Predicate.withPollInDiscussion(discussionObjectID: objectIDOfGroupDiscussion.downcast),
            PersistedPollVote.Predicate.withTimestampInTimeInterval(startDate: dateInterval.startDate, endDate: dateInterval.endDate),
            PersistedPollVote.Predicate.whereVotedIs(true),
        ])
        request.fetchBatchSize = 1_000
        let fetchResults = try context.fetch(request)
        let results: [(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, pollVoteCandidateUuid: UUID, version: Int, originalServerTimestamp: Date)] = fetchResults.compactMap { voteSent in
            guard voteSent.voted else { assertionFailure(); return nil }
            guard let messageObjectID = voteSent.candidate?.poll?.message?.typedObjectID else { assertionFailure(); return nil }
            guard let pollVoteCandidateUuid = voteSent.candidate?.uuid else { assertionFailure(); return nil }
            let version = voteSent.version
            let originalServerTimestamp = voteSent.timestamp
            return (messageObjectID, pollVoteCandidateUuid, version, originalServerTimestamp)
        }
        return results
    }

}


// MARK: History transfer

extension PersistedPollVoteSent {
    
    fileprivate static func createSentDuringHistoryTransfer(pollVote: ObvHistoryReceivedMessage.PollVote, candidate: PersistedPollCandidate) throws {
        _ = try self.init(version: pollVote.version,
                          voted: pollVote.voted,
                          timestamp: pollVote.timestamp,
                          pollCandidate: candidate)
    }
    
}


// MARK: - PersistedPollVoteReceived

@objc(PersistedPollVoteReceived)
public final class PersistedPollVoteReceived: PersistedPollVote {
    
    private static let entityName = "PersistedPollVoteReceived"
    
    // Attributes
    
    @NSManaged private(set) var contactIdentity: Data? // Non-optional in the model
    
    // Relationships
    
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


// MARK: History transfer

extension PersistedPollVoteReceived {
    
    private convenience init(pollVote: ObvHistoryReceivedMessage.PollVote, candidate: PersistedPollCandidate) throws {

        guard let context = candidate.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        guard let ownedCryptoId = candidate.poll?.message?.discussion?.ownedIdentity?.cryptoId else {
            assertionFailure()
            throw ObvUICoreDataError.couldNotDetermineOwnedCryptoId
        }

        try self.init(version: pollVote.version,
                      voted: pollVote.voted,
                      pollCandidate: candidate,
                      timestamp: pollVote.timestamp,
                      forEntityName: Self.entityName)
        
        // Attributes

        self.contactIdentity = pollVote.sender.getIdentity()

        // Relationships
        
        let contactIdentifier = ObvContactIdentifier(contactCryptoId: pollVote.sender, ownedCryptoId: ownedCryptoId)
        if let persistedContact = try PersistedObvContactIdentity.get(
            persisted: contactIdentifier,
            whereOneToOneStatusIs: .any,
            within: context) {
            self.contact = persistedContact
        } else {
            self.contact = nil
        }
        
    }

    fileprivate static func createReceivedDuringHistoryTransfer(pollVote: ObvHistoryReceivedMessage.PollVote, candidate: PersistedPollCandidate) throws {
        _ = try self.init(pollVote: pollVote, candidate: candidate)
    }
    
}
