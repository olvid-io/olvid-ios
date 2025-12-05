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


@objc(PersistedPoll)
public final class PersistedPoll: NSManagedObject {
    
    static let globalEntityName = "PersistedPoll"
    fileprivate static let entityName = "PersistedPoll"
    private let logger = Logger(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedPoll")
    
    // MARK: Attributes
    @NSManaged private(set) public var expiration: Date?
    @NSManaged private(set) public var multipleChoice: Bool
    @NSManaged private var rawQuestion: String? // Non-optional in the model
    @NSManaged private var rawType: String? // Non-optional in the model
    
    // MARK: - Relationships
    @NSManaged public private(set) var message: PersistedMessage?
    @NSManaged public private(set) var candidates: Set<PersistedPollCandidate>
    
    convenience init(obvPoll: ObvPoll, within context: NSManagedObjectContext) throws {

        var persistedCandidates = [PersistedPollCandidate]()
        
        obvPoll.candidates.enumerated().forEach { index, candidate in
            if let persistedCandidate = try? PersistedPollCandidate(text: candidate.text,
                                                                    uuid: candidate.uuid,
                                                                    sortIndex: index,
                                                                    within: context) {
                persistedCandidates.append(persistedCandidate)
            }
        }
        
        try self.init(question: obvPoll.question,
                      rawType: obvPoll.type.rawValue,
                      multipleChoice: obvPoll.multipleChoice,
                      expiration: obvPoll.expiration,
                      candidates: Set(persistedCandidates),
                      forEntityName: Self.entityName,
                      within: context)
        
        self.message = nil
    }
    
    public var hasVoteNone: Bool {
        (candidates.first { $0.isNone }?.ownedVotes.filter { $0.voted }.count ?? 0) > 0
    }
    
    public func contactHasVoteNone(forContactCryptoId: ObvCryptoId) -> Bool {
        (candidates.first { $0.isNone }?.otherVotes.filter { $0.contactCryptoId == forContactCryptoId && $0.voted }.count ?? 0) > 0
    }
    
    public var question: String {
        rawQuestion ?? ""
    }
    
    public var typedObjectID: TypeSafeManagedObjectID<PersistedPoll> {
        .init(objectID: self.objectID)
    }
    
    /// Expected to be non-nil
    private var type: ObvPollType? {
        guard let rawType else { return nil }
        return ObvPollType(rawValue: rawType)
    }
    
    public func numberOfResponses(for candidate: PersistedPollCandidate) -> Int {
        
        var totalResponses = 0
        
        candidate.votes.forEach { vote in
            if candidate.isNone {
                totalResponses += vote.voted ? 1 : 0
            } else {
                if vote is PersistedPollVoteSent {
                    if !hasVoteNone {
                        totalResponses += vote.voted ? 1 : 0
                    }
                } else if let voteReceived = vote as? PersistedPollVoteReceived {
                    guard let contactCryptoIdOfVoteReceived = voteReceived.contactCryptoId else { assertionFailure(); return }
                    if !contactHasVoteNone(forContactCryptoId: contactCryptoIdOfVoteReceived) {
                        totalResponses += vote.voted ? 1 : 0
                    }
                }
            }
        }
        
        return totalResponses
    }
    
    public var totalNumberOfResponses: Int {
        let totalResponses = candidates.reduce(0, { $0 + numberOfResponses(for: $1) })
        
        return totalResponses
    }
    
    public func hasVoted(contact: PersistedObvContactIdentity) -> Bool {
        let voters = candidates.compactMap { $0.votes }.joined().filter { $0.voted }.compactMap { $0 as? PersistedPollVoteReceived }.compactMap { $0.contact }
        return voters.first { voter in voter.identity == contact.identity } != nil
    }
    
    public var candidatesVotedByOwnedIdentity: [PersistedPollCandidate] {
        candidates.filter { candidate in !candidate.ownedVotes.isEmpty }
    }
    
    public func candidatesVotedBy(contact: PersistedObvContactIdentity) -> [PersistedPollCandidate] {
        candidates.filter { candidate in !candidate.otherVotes(for: contact).isEmpty }
    }
}

extension PersistedPoll {
    
    private convenience init(question: String,
                             rawType: String,
                             multipleChoice: Bool,
                             expiration: Date?,
                             candidates: Set<PersistedPollCandidate>,
                             forEntityName entityName: String,
                             within context: NSManagedObjectContext) throws {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        // We remove the \0 character from the source string, as Core Data discards any content following this character.
        let sanitizedQuestion = question.trimmingWhitespacesAndNewlines().replacingOccurrences(of: "\0", with: " ")
        
        guard !sanitizedQuestion.isEmpty else {
            assertionFailure()
            throw ObvUICoreDataError.pollQuestionIsEmpty
        }
        
        self.rawQuestion = question
        self.rawType = rawType
        self.multipleChoice = multipleChoice
        self.expiration = expiration
        self.candidates = candidates
    }
    
    
    func delete() throws {
        guard let context = self.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        context.delete(self)
    }

}

extension PersistedPoll {
    
    private func pollVoteFromContact(with cryptoId: ObvCryptoId, for pollCandidateUUID: UUID) -> PersistedPollVoteReceived? {
        let pollCandidate = self.candidates.first(where: { $0.uuid == pollCandidateUUID })
        let pollVotesReceived = pollCandidate?.votes.compactMap { $0 as? PersistedPollVoteReceived } ?? []
        let pollVoteReceived = pollVotesReceived.filter {
            return cryptoId == $0.contactCryptoId
        }
        assert(pollVoteReceived.count <= 1)
        return pollVoteReceived.first
    }
    
    
    private func pollVoteFromOwnedIdentity(for pollCandidateUUID: UUID) -> PersistedPollVoteSent? {
        let pollCandidate = self.candidates.first(where: { $0.uuid == pollCandidateUUID })
        let pollVoteSent = pollCandidate?.votes.compactMap { $0 as? PersistedPollVoteSent } ?? []
        assert(pollVoteSent.count <= 1)
        return pollVoteSent.first
    }

    
    /// Set `messageUploadTimestampFromServer` to `nil` if the request is made on the current device.
    /// This method shall exclusively be called from `PersistedMessage.setPollVoteFromOwnedIdentity(...)`.
    func setPollVoteFromOwnedIdentity(for pollCandidateUUID: UUID, voted: Bool, version: Int, messageUploadTimestampFromServer: Date?) throws {
        
        // Set or update the vote
        let timestamp = messageUploadTimestampFromServer ?? Date.now
        if let pollVote = pollVoteFromOwnedIdentity(for: pollCandidateUUID) {
            pollVote.update(version: version, voted: voted, timestamp: timestamp)
        } else if let pollCandidate = self.candidates.first(where: { $0.uuid == pollCandidateUUID }) {
            _ = try PersistedPollVoteSent(version: version, voted: voted, timestamp: timestamp, pollCandidate: pollCandidate)
        }
        
        // We check that we need to update other votes
        if voted {
            
            // If user vote for other than none, and none has been voted, we set none to false
            if pollCandidateUUID != UUID.uuidOfPollCandidateNone, self.hasVoteNone, let pollVote = pollVoteFromOwnedIdentity(for: UUID.uuidOfPollCandidateNone) {
                pollVote.update(version: version, voted: false, timestamp: timestamp)
            }
            
            // if poll is not a multiple choice one, we force to set all the other votes to false.
            if !self.multipleChoice, pollCandidateUUID != UUID.uuidOfPollCandidateNone {
                let otherVotedCandidates = self.candidatesVotedByOwnedIdentity.filter { $0.uuid != pollCandidateUUID }
                otherVotedCandidates.forEach { candidate in
                    guard let candidateUUID = candidate.uuid else { assertionFailure(); return }
                    if let pollVote = pollVoteFromOwnedIdentity(for: candidateUUID) {
                        pollVote.update(version: version, voted: false, timestamp: timestamp)
                    }
                }
                
            }
        }
        
    }
    
    
    func setPollVoteFromContact(_ contact: PersistedObvContactIdentity, for pollCandidateUUID: UUID, voted: Bool, version: Int, messageUploadTimestampFromServer: Date?) throws {
        
        // Set or update the vote
        let timestamp = messageUploadTimestampFromServer ?? Date.now
        if let pollVote = pollVoteFromContact(with: contact.cryptoId, for: pollCandidateUUID) {
            pollVote.update(version: version, voted: voted, timestamp: timestamp)
        } else if let pollCandidate = self.candidates.first(where: { $0.uuid == pollCandidateUUID }) {
            _ = try PersistedPollVoteReceived(version: version, voted: voted, timestamp: timestamp, pollCandidate: pollCandidate, contact: contact)
        }
        
        // We check that we need to update other votes
        if voted {
            
            // If user vote for other than none, and none has been voted, we set none to false
            if pollCandidateUUID != .uuidOfPollCandidateNone, self.hasVoteNone, let pollVote = pollVoteFromContact(with: contact.cryptoId, for: .uuidOfPollCandidateNone) {
                pollVote.update(version: version, voted: false, timestamp: timestamp)
            }
            
            // if poll is not a multiple choice one, we force to set all the other votes to false.
            if !self.multipleChoice, pollCandidateUUID != .uuidOfPollCandidateNone {
                let otherVotedCandidates = self.candidatesVotedBy(contact: contact).filter { $0.uuid != pollCandidateUUID }
                otherVotedCandidates.forEach { candidate in
                    guard let candidateUUID = candidate.uuid else { assertionFailure(); return }
                    if let pollVote = pollVoteFromContact(with: contact.cryptoId, for: candidateUUID) {
                        pollVote.update(version: version, voted: false, timestamp: timestamp)
                    }
                }
                
            }
        }

        
    }

    
}

extension PersistedPoll {
    func toPollJSON() throws -> PollJSON {

        let answerType: PollJSON.PollAnswerType
        switch self.type {
        case .string:
            answerType = .string
        case .none:
            answerType = .string
        }
        
        let sortedCandidates: [PollCandidateJSON] = try candidates
            .sorted { $0.sortIndex < $1.sortIndex }
            .compactMap { try $0.toPollCandidateJSON() }
        
        let pollJSON = PollJSON(type: answerType,
                                question: question,
                                candidates: sortedCandidates,
                                multipleChoice: multipleChoice,
                                expiration: expiration?.timeIntervalSince1970)
        
        return pollJSON
    }
}

extension PersistedPoll {

    /// Body of a location message in order to be displayed for legacy versions of the app that do NOT feature location sharing
    var legacyPollMessageBody: String {
        var body = "📊 "
        
        body += "**\(question)**\n"
        
        candidates.sorted { $0.sortIndex < $1.sortIndex }.forEach { candidate in
            body += "\(Int(candidate.sortIndex + 1)). \(candidate.text)\n"
        }

        if let expiration = expiration {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .full
            dateFormatter.timeStyle = .short
            let dateString = dateFormatter.string(from: expiration)
            body += "⏱️ *\(dateString)*\n"
        }
        
        if multipleChoice {
            body += "✅ "
            body += NSLocalizedString("POLL_MULTIPLE_CHOICE_LEGACY_TEXT", comment: "")
        }

        return body
    }

}

extension PersistedPoll {
    
    struct Predicate {
        
        enum Key: String {
            // Attributes
            case expiration = "expiration"
            case multipleChoice = "multipleChoice"
            case rawQuestion = "rawQuestion"
            case rawType = "rawType"
            // Relationships
            case message = "message"
            case candidates = "candidates"
        }
        
        static func withObjectID(_ objectID: TypeSafeManagedObjectID<PersistedPoll>) -> NSPredicate {
            NSPredicate(withObjectID: objectID.objectID)
        }

    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedPoll> {
        return NSFetchRequest<PersistedPoll>(entityName: PersistedPoll.entityName)
    }

    public static func get(with objectID: TypeSafeManagedObjectID<PersistedPoll>, within context: NSManagedObjectContext) throws -> PersistedPoll? {
        let request: NSFetchRequest<PersistedPoll> = PersistedPoll.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    public static func getFetchedResultsController(objectID: TypeSafeManagedObjectID<PersistedPoll>, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedPoll> {
        let request: NSFetchRequest<PersistedPoll> = PersistedPoll.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID)
        request.fetchLimit = 1
        request.sortDescriptors = []
        return .init(fetchRequest: request,
                     managedObjectContext: context,
                     sectionNameKeyPath: nil,
                     cacheName: nil)
    }

}
