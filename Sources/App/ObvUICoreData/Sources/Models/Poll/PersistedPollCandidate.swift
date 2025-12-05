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

@objc(PersistedPollCandidate)
public final class PersistedPollCandidate: NSManagedObject {
    
    static let globalEntityName = "PersistedPollCandidate"
    fileprivate static let entityName = "PersistedPollCandidate"
    private let logger = Logger(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedPollCandidate")
    
    // MARK: Attributes
    @NSManaged public private(set) var sortIndex: Int
    @NSManaged private var rawText: String? // Non-optional in the model
    @NSManaged public private(set) var uuid: UUID? // Non-optional in the model
    
    // MARK: - Relationships
    @NSManaged public private(set) var poll: PersistedPoll? // Non-optional in the model
    @NSManaged public private(set) var votes: Set<PersistedPollVote>
    
    public var accuratedVotes: Set<PersistedPollVote> { votes.filter { $0.voted } }
    
    public var ownedVotes: Array<PersistedPollVoteSent> { accuratedVotes.compactMap { $0 as? PersistedPollVoteSent } }
    
    public var otherVotes: Array<PersistedPollVoteReceived> { accuratedVotes.compactMap { $0 as? PersistedPollVoteReceived } }
    
    public func otherVotes(for contact: PersistedObvContactIdentity) -> Array<PersistedPollVoteReceived> {
        otherVotes.filter { $0.contact == contact }
    }
    
    public var isNone: Bool { uuid == .uuidOfPollCandidateNone }
    
    public var text: String {
        rawText ?? ""
    }
        
}

extension PersistedPollCandidate {
    
    convenience init(text: String,
                     uuid: UUID,
                     sortIndex: Int,
                     within context: NSManagedObjectContext) throws {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.sortIndex = sortIndex
        self.rawText = text.trimmingWhitespacesAndNewlines()
        self.uuid = uuid
    }
    
}

extension PersistedPollCandidate {
    func toPollCandidateJSON() throws -> PollCandidateJSON {
        guard let uuid else { throw ObvUICoreDataError.uuidIsNil }
        return PollCandidateJSON(uuid: uuid, text: text)
    }
}


extension PersistedPollCandidate {
    
    struct Predicate {
        
        enum Key: String {
            // Attributes
            case rawText = "rawText"
            case sortIndex = "sortIndex"
            case uuid = "uuid"
            
            // Relationships
            case poll = "poll"
            case votes = "votes"
        }
        
        static func withObjectID(_ objectID: TypeSafeManagedObjectID<PersistedPollCandidate>) -> NSPredicate {
            NSPredicate(withObjectID: objectID.objectID)
        }
        
        static func withPollObjectID(_ objectID: TypeSafeManagedObjectID<PersistedPoll>) -> NSPredicate {
            NSPredicate(Key.poll, equalToObjectWithObjectID: objectID.objectID)
        }
        
        static func withUUID(_ uuid: UUID) -> NSPredicate {
            NSPredicate(Key.uuid, EqualToUuid: uuid)
        }

    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedPollCandidate> {
        return NSFetchRequest<PersistedPollCandidate>(entityName: PersistedPollCandidate.entityName)
    }

    public static func get(with objectID: TypeSafeManagedObjectID<PersistedPollCandidate>, within context: NSManagedObjectContext) throws -> PersistedPollCandidate? {
        let request: NSFetchRequest<PersistedPollCandidate> = PersistedPollCandidate.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    public static func get(pollObjectID: TypeSafeManagedObjectID<PersistedPoll>, candidateUUID: UUID, within context: NSManagedObjectContext) throws -> PersistedPollCandidate? {
        let request: NSFetchRequest<PersistedPollCandidate> = PersistedPollCandidate.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withPollObjectID(pollObjectID),
            Predicate.withUUID(candidateUUID),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    public static func getFetchedResultsController(objectID: TypeSafeManagedObjectID<PersistedPollCandidate>, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedPollCandidate> {
        let request: NSFetchRequest<PersistedPollCandidate> = PersistedPollCandidate.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID)
        request.fetchLimit = 1
        request.sortDescriptors = []
        return .init(fetchRequest: request,
                     managedObjectContext: context,
                     sectionNameKeyPath: nil,
                     cacheName: nil)
    }

    public static func getFetchedResultsController(pollObjectID: TypeSafeManagedObjectID<PersistedPoll>, candidateUUID: UUID, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedPollCandidate> {
        let request: NSFetchRequest<PersistedPollCandidate> = PersistedPollCandidate.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withPollObjectID(pollObjectID),
            Predicate.withUUID(candidateUUID),
        ])
        request.fetchLimit = 1
        request.sortDescriptors = []
        return .init(fetchRequest: request,
                     managedObjectContext: context,
                     sectionNameKeyPath: nil,
                     cacheName: nil)
    }

    /// Returns an `NSFetchedResultsController` for all `PersistedPollCandidate`s for a given poll. Since this `NSFetchedResultsController`
    /// is currently force a refresh of a view model that is computed on the basis of a `PersistedPoll`, we do not fetch any property.
    public static func getFetchedResultsController(pollObjectID: TypeSafeManagedObjectID<PersistedPoll>, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedPollCandidate> {
        let request: NSFetchRequest<PersistedPollCandidate> = PersistedPollCandidate.fetchRequest()
        request.predicate = Predicate.withPollObjectID(pollObjectID)
        request.fetchBatchSize = 500
        request.sortDescriptors = []
        request.propertiesToFetch = []
        return .init(fetchRequest: request,
                     managedObjectContext: context,
                     sectionNameKeyPath: nil,
                     cacheName: nil)
    }

}
