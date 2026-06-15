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
import ObvUICoreData
import ObvAppTypes
import CoreData
import OlvidUtils
import ObvDesignSystem
import ObvPollFeature
import ObvSharedDataSources


@MainActor
final class PollViewDataSource {
 
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var pollViewModelStreamManagerForStreamUUID = [UUID: PollViewModelStreamManager]()
    private var pollCandidateViewModelStreamManagerForStreamUUID = [UUID: PollCandidateViewModelStreamManager]()
    private var voterWhoDidNotVoteYetViewModelStreamManagerForStreamUUID = [UUID: VoterWhoDidNotVoteYetViewModelStreamManager]()
    private var pollVoteViewModelStreamManagerForStreamUUID = [UUID: PollVoteViewModelStreamManager]()
    
    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }

}


@available(iOS 17.0, *)
extension PollViewDataSource: PollViewDataSourceProtocol {

    func getInitialPollViewModel(pollIdentifier: PollIdentifier, candidatesSortOrder: PollViewModel.CandidatesSortOrder) -> PollViewModel? {
        guard let pollObjectID = try? getPollObjectID(from: pollIdentifier) else { return nil }
        guard let poll = try? PersistedPoll.get(with: pollObjectID, within: viewContext) else { return nil }
        let model = PollViewModel(persistedPoll: poll, candidatesSortOrder: candidatesSortOrder)
        return model
    }
    
    
    func getAsyncStreamOfPollViewModel(_ view: PollView, pollIdentifier: PollIdentifier, candidatesSortOrder: PollViewModel.CandidatesSortOrder) async throws -> (streamUUID: UUID, stream: AsyncStream<PollViewModel>) {
        let pollObjectID = try getPollObjectID(from: pollIdentifier)
        let manager = try PollViewModelStreamManager(pollObjectID: pollObjectID, candidatesSortOrder: candidatesSortOrder, context: backgroundContext, viewContext: viewContext)
        pollViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    
    func changeSortOrderOfAsyncStreamOfPollViewModel(to newSortOrder: PollViewModel.CandidatesSortOrder, streamUUID: UUID) {
        guard let manager = pollViewModelStreamManagerForStreamUUID[streamUUID] else { assertionFailure(); return }
        manager.changeSortOrder(to: newSortOrder)
    }

    
    func finishAsyncStreamOfPollViewModel(_ view: PollView, streamUUID: UUID) {
        guard let manager = pollViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }

    
    func getInitialVoterWhoDidNotVoteYetViewModel(voterIdentifier: VoterWhoDidNotVoteYetViewModel.VoterIdentifier) -> VoterWhoDidNotVoteYetViewModel? {
        guard let contactObjectID = try? getPersistedObvContactIdentityObjectID(voterIdentifier: voterIdentifier) else { return nil }
        guard let contact = try? PersistedObvContactIdentity.get(objectID: contactObjectID.objectID, within: viewContext) else { return nil }
        let model = VoterWhoDidNotVoteYetViewModel(contact: contact)
        return model
    }
    
    func getAsyncStreamOfVoterWhoDidNotVoteYetViewModel(_ view: VoterWhoDidNotVoteYetView, voterIdentifier: VoterWhoDidNotVoteYetViewModel.VoterIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<VoterWhoDidNotVoteYetViewModel>) {
        let contactObjectID = try getPersistedObvContactIdentityObjectID(voterIdentifier: voterIdentifier)
        let manager = VoterWhoDidNotVoteYetViewModelStreamManager(contactObjectID: contactObjectID, context: backgroundContext)
        voterWhoDidNotVoteYetViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfVoterWhoDidNotVoteYetViewModel(_ view: VoterWhoDidNotVoteYetView, streamUUID: UUID) {
        guard let manager = voterWhoDidNotVoteYetViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
    func getInitialPollVoteViewModel(voteIdentifier: PollVoteViewModel.VoteIdentifier) -> PollVoteViewModel? {
        guard let persistedPollVoteObjectID = try? getPersistedPollVoteObjectID(voteIdentifier: voteIdentifier) else { return nil }
        guard let pollVote = try? PersistedPollVote.get(objectID: persistedPollVoteObjectID, within: viewContext) else { return nil }
        let model = PollVoteViewModel(vote: pollVote)
        return model
    }
    
    func getAsyncStreamOfPollVoteViewModel(_ view: VoteView, voteIdentifier: PollVoteViewModel.VoteIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<PollVoteViewModel>) {
        let persistedPollVoteObjectID = try getPersistedPollVoteObjectID(voteIdentifier: voteIdentifier)
        let manager = PollVoteViewModelStreamManager(persistedPollVoteObjectID: persistedPollVoteObjectID, context: backgroundContext)
        pollVoteViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfPollVoteViewModel(_ view: VoteView, streamUUID: UUID) {
        guard let manager = pollVoteViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
    func getInitialPollCandidateViewModel(candidateIdentifier: PollCandidateIdentifier) -> PollCandidateViewModel? {
        guard let candidateObjectID = try? getPollCandidateObjectID(from: candidateIdentifier) else { assertionFailure(); return nil }
        guard let pollCandidate = try? PersistedPollCandidate.get(with: candidateObjectID, within: viewContext) else { return nil }
        let model = PollCandidateViewModel(candidate: pollCandidate)
        return model
    }
    
    func getAsyncStreamOfPollCandidateViewModel(_ view: PollCandidateView, candidateIdentifier: PollCandidateIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<PollCandidateViewModel>) {
        let candidateObjectID = try getPollCandidateObjectID(from: candidateIdentifier)
        let manager = PollCandidateViewModelStreamManager(candidateObjectID: candidateObjectID, context: backgroundContext)
        pollCandidateViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfPollCandidateViewModel(_ view: PollCandidateView, streamUUID: UUID) {
        guard let manager = pollCandidateViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
    
    private func getPersistedPollVoteObjectID(voteIdentifier: PollVoteViewModel.VoteIdentifier) throws -> TypeSafeManagedObjectID<PersistedPollVote> {
        switch voteIdentifier {
        case .pollVoteObjectID(let objectID):
            return .init(objectID: objectID)
        case .forPreviews:
            assertionFailure()
            throw ObvError.unexpectedIdentifierType
        }
    }
    
    
    private func getPersistedObvContactIdentityObjectID(voterIdentifier: VoterWhoDidNotVoteYetViewModel.VoterIdentifier) throws -> TypeSafeManagedObjectID<PersistedObvContactIdentity> {
        switch voterIdentifier {
        case .contactObjectID(let objectID):
            return .init(objectID: objectID)
        case .forPreviews:
            assertionFailure()
            throw ObvError.unexpectedIdentifierType
        }
    }
    
    
    private func getPollObjectID(from pollIdentifier: PollIdentifier) throws -> TypeSafeManagedObjectID<PersistedPoll> {
        switch pollIdentifier {
        case .persistedPollObjectID(let objectID):
            return .init(objectID: objectID)
        case .forPreviews:
            assertionFailure()
            throw ObvError.unexpectedIdentifierType
        }
    }
    
    
    private func getPollCandidateObjectID(from pollCandidateIdentifier: PollCandidateIdentifier) throws -> TypeSafeManagedObjectID<PersistedPollCandidate> {
        switch pollCandidateIdentifier {
        case .pollCandidateObjectID(let objectID):
            return .init(objectID: objectID)
        case .forPreviews:
            assertionFailure()
            throw ObvError.unexpectedIdentifierType
        }
    }
    
    enum ObvError: Error {
        case unexpectedIdentifierType
    }
    
}


// MARK: - PollVoteViewModelStreamManager

extension PollViewDataSource {
    
    private final class PollVoteViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<PollVoteViewModel, PersistedPollVote>, @unchecked Sendable {
        
        init(persistedPollVoteObjectID: TypeSafeManagedObjectID<PersistedPollVote>, context: NSManagedObjectContext) {
            // Since PollVoteViewModel depends on the PersistedPollVote, we create a frc on it
            let frc = PersistedPollVote.getFetchedResultsController(objectID: persistedPollVoteObjectID, within: context)
            // We don't consider the dependencies on PersistedObvContactIdentity for a received vote, nor on PersistedObvOwnedIdentity for a sent vote
            super.init(frc: frc)
        }

        override func createModel(fetchedObjects: [PersistedPollVote]) throws -> PollVoteViewModel {
            
            assert(fetchedObjects.count <= 1)
            
            guard let pollVote = fetchedObjects.first else {
                throw ObvError.objectDoesNotExist
            }
            
            guard let viewModel = PollVoteViewModel(vote: pollVote) else {
                throw ObvError.couldNotInitViewModel
            }
            
            return viewModel

            
        }

        enum ObvError: Error {
            case objectDoesNotExist
            case couldNotInitViewModel
        }

    }
    
}


// MARK: - VoterWhoDidNotVoteYetViewModelStreamManager

extension PollViewDataSource {
    
    private final class VoterWhoDidNotVoteYetViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<VoterWhoDidNotVoteYetViewModel, PersistedObvContactIdentity>, @unchecked Sendable {
        
        init(contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, context: NSManagedObjectContext) {
            // Since `VoterWhoDidNotVoteYetViewModel` depends on the `PersistedObvContactIdentity`, we create a frc for it
            let frc = PersistedObvContactIdentity.getFetchedResultsController(objectID: contactObjectID, within: context)
            super.init(frc: frc)
        }
        
        override func createModel(fetchedObjects: [PersistedObvContactIdentity]) throws -> VoterWhoDidNotVoteYetViewModel {
            
            assert(fetchedObjects.count <= 1)
            
            guard let contact = fetchedObjects.first else {
                // This happens when the contact gets deleted
                throw ObvError.objectDoesNotExist
            }
            
            let viewModel = VoterWhoDidNotVoteYetViewModel(contact: contact)
            
            return viewModel

        }
        
        enum ObvError: Error {
            case objectDoesNotExist
        }

    }
    
}

// MARK: - PollViewModelStreamManager

extension PollViewDataSource {
    
    private final class PollViewModelStreamManager: ObvDataSourceStreamManagerWithFourFetchedResultsController<PollViewModel, PersistedPoll, PersistedPollCandidate, PersistedObvOwnedIdentity, PersistedMessage>, @unchecked Sendable {
        
        private var candidatesSortOrder: PollViewModel.CandidatesSortOrder
        
        @MainActor
        init(pollObjectID: TypeSafeManagedObjectID<PersistedPoll>, candidatesSortOrder: PollViewModel.CandidatesSortOrder, context: NSManagedObjectContext, viewContext: NSManagedObjectContext) throws {
            self.candidatesSortOrder = candidatesSortOrder
            guard let persistedPoll = try PersistedPoll.get(with: pollObjectID, within: viewContext) else {
                throw ObvError.pollDoesNotExist
            }
            guard let messageObjectID = persistedPoll.message?.typedObjectID else {
                throw ObvError.couldNotFetchObjects
            }
            guard let ownedIdentityObjectID = persistedPoll.message?.discussion?.ownedIdentity?.typedObjectID else {
                throw ObvError.couldNotFetchObjects
            }
            // Since `PollViewModel` depends on the `PersistedPoll`, we create a frc for that `PersistedPoll`
            let frc1 = PersistedPoll.getFetchedResultsController(objectID: pollObjectID, within: context)
            // Since `PollViewModel` depends on each candidate of the `PersistedPoll`, we create a frc on them
            let frc2 = PersistedPollCandidate.getFetchedResultsController(pollObjectID: pollObjectID, within: context)
            // Since `PollViewModel` depends on the owned identity, we create a frc on it
            let frc3 = PersistedObvOwnedIdentity.getFetchedResultsController(objectID: ownedIdentityObjectID, within: context)
            // The `PollViewModel` depends on the recipient receipts when the associated message is a sent message. We simply things here
            // by creating an frc on the message. This is not 100% accurate, we it's ok in practice (certain situations will require the user
            // to dismiss the view and re-display it to show updates)
            let frc4 = PersistedMessage.getFetchedResultsController(objectID: messageObjectID, within: context)
            super.init(frc1: frc1, frc2: frc2, frc3: frc3, frc4: frc4)
        }
        
        func changeSortOrder(to newSortOrder: PollViewModel.CandidatesSortOrder) {
            guard self.candidatesSortOrder != newSortOrder else { return }
            self.candidatesSortOrder = newSortOrder
            Task {
                do {
                    try await getFetchedObjectsAndYieldModelIfNeeded()
                } catch {
                    assertionFailure(error.localizedDescription)
                }
            }
        }
        
        override func createModel(fetchedObjects1: [PersistedPoll], fetchedObjects2: [PersistedPollCandidate], fetchedObjects3: [PersistedObvOwnedIdentity], fetchedObjects4: [PersistedMessage]) throws -> PollViewModel {
            
            let fetchedObjects = fetchedObjects1
            
            assert(fetchedObjects.count <= 1)
            
            guard let persistedPoll = fetchedObjects.first else {
                // This happens when the discussion gets deleted
                throw ObvError.objectDoesNotExist
            }
            
            guard let viewModel = PollViewModel(persistedPoll: persistedPoll, candidatesSortOrder: candidatesSortOrder) else {
                throw ObvError.couldNotInitViewModel
            }
            
            return viewModel
            
        }
        
        enum ObvError: Error {
            case pollDoesNotExist
            case couldNotFetchObjects
            case objectDoesNotExist
            case couldNotDetermineCandidateUUID
            case couldNotInitViewModel
        }
    }
}


// MARK: - PollCandidateViewModelStreamManager

extension PollViewDataSource {
    
    private final class PollCandidateViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<PollCandidateViewModel, PersistedPollCandidate>, @unchecked Sendable {
                
        init(candidateObjectID: TypeSafeManagedObjectID<PersistedPollCandidate>, context: NSManagedObjectContext) {
            // Since `PollCandidateViewModel` depends on the `PersistedPollCandidate`, we create a frc for that `PersistedPoll`
            let frc = PersistedPollCandidate.getFetchedResultsController(objectID: candidateObjectID, within: context)
            super.init(frc: frc)
        }
        
        override func createModel(fetchedObjects: [PersistedPollCandidate]) throws -> PollCandidateViewModel {
            assert(fetchedObjects.count <= 1)
            
            guard let pollCandidate = fetchedObjects.first else {
                // This happens when the discussion gets deleted
                throw ObvError.objectDoesNotExist
            }
            
            let viewModel = PollCandidateViewModel(candidate: pollCandidate)
            
            return viewModel
                        
        }
        
        enum ObvError: Error {
            case pollDoesNotExist
            case pollCandidateDoesNotExist
            case objectDoesNotExist
        }
    }
}


// MARK: - PollVoteViewModel from a PersistedPollVote

extension PollVoteViewModel {
    
    /// `PollVoteViewModel` depends on:
    /// - the `PersistedPollVote`
    /// - for a received vote, on the `PersistedObvContactIdentity` (if not deleted)
    /// - for a sent vote, on the `PersistedObvOwnedIdentity`
    init?(vote: PersistedPollVote) {
        
        guard let candidate = vote.candidate else { return nil }
        guard let poll = candidate.poll else { return nil }
        guard let ownedIdentity = poll.message?.discussion?.ownedIdentity else { return nil }

        let name: String
        let avatarModel: ObvAvatarViewModel
        if vote is PersistedPollVoteSent {
            name = ownedIdentity.customOrFullDisplayName
            avatarModel = .init(ownedIdentity: ownedIdentity)
        } else if let receivedVote = vote as? PersistedPollVoteReceived {
            if let contact = receivedVote.contact {
                name = contact.customOrFullDisplayName
                avatarModel = .init(contact: contact)
            } else {
                name = String(localized: "DELETED_CONTACT")
                avatarModel = ObvAvatarViewModel(characterOrIcon: .icon(.lock(.none, .shield)),
                                                 colors: .init(foreground: .label, background: .systemBackground),
                                                 photoURL: nil)
            }
        } else {
            assertionFailure()
            return nil
        }
        
        self = .init(identifier: .pollVoteObjectID(vote.objectID),
                     name: name,
                     timestamp: vote.timestamp,
                     avatarModel: avatarModel)
        
    }
    
}


// MARK: - PollCandidateViewModel from a PersistedObvContactIdentity

extension VoterWhoDidNotVoteYetViewModel {
    
    /// A `VoterWhoDidNotVoteYetViewModel` depends on the `PersistedObvContactIdentity`.
    init(contact: PersistedObvContactIdentity) {
        self = .init(identifier: .contactObjectID(contact.objectID),
                     name: contact.customOrFullDisplayName,
                     avatarModel: ObvAvatarViewModel(contact: contact))
    }
    
}

// MARK: - PollCandidateViewModel from a PersistedPollCandidate

extension PollCandidateViewModel {
    
    /// `PollCandidateViewModel` depends:
    /// - the `PersistedPollCandidate`
    init(candidate: PersistedPollCandidate) {
        
        let identifiersOfVotes: [PollVoteViewModel.VoteIdentifier] = candidate.votes.filter(\.voted).map { vote in
                .pollVoteObjectID(vote.objectID)
        }
        
        self = .init(candidateIdentifier: .pollCandidateObjectID(candidate.objectID),
                     identifiersOfVotes: identifiersOfVotes)
        
    }
    
}

// MARK: - PollViewCandidateModel from a PersistedPollCandidate

extension PollViewCandidateModel {
    
    /// `PollViewCandidateModel` depends on:
    /// - the `PersistedPollCandidate`
    /// - the associated `PersistedPoll`
    /// - the associated owned identity
    init?(candidate: PersistedPollCandidate) {
        
        guard let persistedPoll = candidate.poll else {
            return nil
        }
        
        guard let ownedIdentity = persistedPoll.message?.discussion?.ownedIdentity else {
            return nil
        }
        
        let isVotedByOwnedIdentity: IsVotedByOwnedIdentity
        if candidate.uuid == .uuidOfPollCandidateNone {
            if persistedPoll.hasVoteNone {
                isVotedByOwnedIdentity = .yes(avatarModelOfOwnedIdentity: .init(ownedIdentity: ownedIdentity))
            } else {
                isVotedByOwnedIdentity = .no
            }
        } else {
            if !candidate.ownedVotes.isEmpty && !persistedPoll.hasVoteNone {
                isVotedByOwnedIdentity = .yes(avatarModelOfOwnedIdentity: .init(ownedIdentity: ownedIdentity))
            } else {
                isVotedByOwnedIdentity = .no
            }
        }
        
        let totalNumberOfResponses = persistedPoll.totalNumberOfResponses
        let numberOfResponses = persistedPoll.numberOfResponses(for: candidate)

        self = .init(identifier: .pollCandidateObjectID(candidate.objectID),
                     text: candidate.text,
                     isVotedByOwnedIdentity: isVotedByOwnedIdentity,
                     numberOfResponses: numberOfResponses,
                     totalNumberOfResponses: totalNumberOfResponses,
                     pollSortIndex: candidate.sortIndex)
        
    }
    
}

// MARK: - PollViewModel from a PersistedPoll

extension PollViewModel {
    
    /// `PollViewModel` depends on:
    /// - the `PersistedPoll`
    /// - each candidate of the `candidates` of the `PersistedPoll`
    /// - on the message and its recipient infos (if it is a `PersistedMessageSent`)
    init?(persistedPoll: PersistedPoll, candidatesSortOrder: CandidatesSortOrder) {
        
        let sortedCandidates: [PersistedPollCandidate]
        switch candidatesSortOrder {
        case .pollOrder:
            sortedCandidates = persistedPoll.candidates.sorted(by: \.sortIndex)
        case .numberOfResponses:
            sortedCandidates = persistedPoll.candidates.sorted(by: { candidate1, candidate2 in
                let numberOfVotes1 = candidate1.votes.filter(\.voted).count
                let numberOfVotes2 = candidate2.votes.filter(\.voted).count
                if numberOfVotes1 != numberOfVotes2 {
                    return numberOfVotes1 > numberOfVotes2
                } else {
                    return candidate1.sortIndex < candidate2.sortIndex
                }
            })
        }
        
        let candidates: [PollViewCandidateModel] = sortedCandidates.compactMap { candidate in
            PollViewCandidateModel(candidate: candidate)
        }
        
        let identifiersOfVotersWhoDidNotVoteYet: [VoterWhoDidNotVoteYetViewModel.VoterIdentifier]
        if let persistedMessageSent = persistedPoll.message as? PersistedMessageSent {
            let recipientInfos = persistedMessageSent.unsortedRecipientsInfos
            identifiersOfVotersWhoDidNotVoteYet = recipientInfos.compactMap { recipientInfo in
                if let contact = try? recipientInfo.getRecipient(), !persistedPoll.hasVoted(contact: contact) {
                    return .contactObjectID(contact.objectID)
                } else {
                    return nil
                }
            }
        } else {
            identifiersOfVotersWhoDidNotVoteYet = []
        }
        
        self = .init(question: persistedPoll.question,
                     candidates: candidates,
                     identifiersOfVotersWhoDidNotVoteYet: identifiersOfVotersWhoDidNotVoteYet)
        
    }
    
}
