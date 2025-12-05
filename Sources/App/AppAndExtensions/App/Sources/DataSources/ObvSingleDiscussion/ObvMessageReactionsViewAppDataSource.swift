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
import Combine
import ObvSingleDiscussion
import ObvUICoreData
import OlvidUtils
import ObvDesignSystem
import ObvSettings
import CoreData
import ObvTypes



@MainActor
final class ObvMessageReactionsViewAppDataSource: ObvMessageReactionsViewDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }

    
    private var obvMessageReactionsViewModelStreamManagerForStreamUUID = [UUID: ObvMessageReactionsViewModelStreamManager]()
    private var sentReactionCellViewModelStreamManagerForStreamUUID = [UUID: SentReactionCellViewModelStreamManager]()
    private var receivedReactionCellViewModelStreamManagerForStreamUUID = [UUID: ReceivedReactionCellViewModelStreamManager]()
    private var obvReactionsCountViewModelStreamManagerForStreamUUID = [UUID: ObvReactionsCountViewModelStreamManager]()
    
    // Create/Finish a stream of models returning all the reactions' identifiers of the given message
    
    func getAsyncStreamOfObvMessageReactionsViewModel(messageIdentifier: ObvSingleDiscussion.ObvMessageReactionsViewModel.MessageIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvSingleDiscussion.ObvMessageReactionsViewModel>) {
        let manager = try ObvMessageReactionsViewModelStreamManager(messageIdentifier: messageIdentifier, context: backgroundContext)
        obvMessageReactionsViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfObvMessageReactionsViewModel(streamUUID: UUID) {
        guard let manager = obvMessageReactionsViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
    // Create/Finish a stream of models for a single cell of the view
    
    func getAsyncStreamOfReactionCellViewModel(reactionIdentifier: ObvSingleDiscussion.ObvMessageReactionsViewModel.ReactionIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvSingleDiscussion.ReactionCellViewModel>) {
        switch reactionIdentifier {
        case .forPreviews:
            assertionFailure()
            throw ObvError.unexpectedReactionIdentifierType
        case .objectID(let objectID):
            guard let reaction = try PersistedMessageReaction.get(with: .init(objectID: objectID), within: viewContext) else {
                assertionFailure()
                throw ObvError.couldNotFindReaction
            }
            if let sentReaction = reaction as? PersistedMessageReactionSent {
                guard let reaction = try PersistedMessageReactionSent.get(with: sentReaction.typedObjectID, within: viewContext) else {
                    assertionFailure()
                    throw ObvError.couldNotFindReaction
                }
                guard let ownedCryptoId = reaction.message?.discussion?.ownedIdentity?.cryptoId else {
                    assertionFailure()
                    throw ObvError.couldNotDetermineOwnedIdentity
                }
                let manager = try SentReactionCellViewModelStreamManager(persistedMessageReactionSentObjectID: sentReaction.typedObjectID, ownedCryptoId: ownedCryptoId, context: backgroundContext)
                sentReactionCellViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
                return try await manager.startStream()
            } else if let receivedReaction = reaction as? PersistedMessageReactionReceived {
                guard let reaction = try PersistedMessageReactionReceived.get(with: receivedReaction.typedObjectID, within: viewContext) else {
                    assertionFailure()
                    throw ObvError.couldNotFindReaction
                }
                guard let contactObjectID = reaction.contact?.typedObjectID else {
                    assertionFailure()
                    throw ObvError.couldNotDetermineContact
                }
                let manager = try ReceivedReactionCellViewModelStreamManager(persistedMessageReactionReceivedObjectID: receivedReaction.typedObjectID, contactObjectID: contactObjectID, context: backgroundContext)
                receivedReactionCellViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
                return try await manager.startStream()
            } else {
                assertionFailure()
                throw ObvError.unexpectedReactionType
            }
        }
    }
    
    func finishAsyncStreamOfReactionCellViewModel(streamUUID: UUID) {
        if let manager = sentReactionCellViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            manager.finishStream()
        }
        if let manager = receivedReactionCellViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            manager.finishStream()
        }
    }
    
    // Create/Finish a stream of models for the bottom view showing all reactions and their count

    func getAsyncStreamOfReactionsCountViewModel(messageIdentifier: ObvSingleDiscussion.ObvMessageReactionsViewModel.MessageIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvSingleDiscussion.ObvReactionsCountViewModel>) {
        let manager = try ObvReactionsCountViewModelStreamManager(messageIdentifier: messageIdentifier, context: backgroundContext)
        obvReactionsCountViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfReactionsCountViewModel(streamUUID: UUID) {
        guard let manager = obvReactionsCountViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
    // Errors
    
    enum ObvError: Error {
        case unexpectedReactionIdentifierType
        case couldNotFindReaction
        case unexpectedReactionType
        case couldNotDetermineOwnedIdentity
        case couldNotDetermineContact
    }
    
}


// MARK: - Internal managers

extension ObvMessageReactionsViewAppDataSource {
    
    /// This manager produces the stream of the model allowing to display all the reactions on a specific message, and their count.
    private final class ObvReactionsCountViewModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvSingleDiscussion.ObvReactionsCountViewModel, PersistedMessageReactionSent, PersistedMessageReactionReceived>, @unchecked Sendable {
                
        init(messageIdentifier: ObvSingleDiscussion.ObvMessageReactionsViewModel.MessageIdentifier, context: NSManagedObjectContext) throws {
            let messageObjectID: TypeSafeManagedObjectID<PersistedMessage>
            switch messageIdentifier {
            case .objectID(let objectID):
                messageObjectID = TypeSafeManagedObjectID<PersistedMessage>(objectID: objectID)
            case .forPreview:
                assertionFailure()
                throw ObvError.unexpectedMessageIdentifierType
            }
            let frc1 = PersistedMessageReactionSent.getFetchedResultsControllerForSentReactionOnMessage(
                messageObjectID: messageObjectID,
                within: context)
            let frc2 = PersistedMessageReactionReceived.getFetchedResultsControllerForReceivedReactionOnMessage(
                messageObjectID: messageObjectID,
                within: context)
            super.init(frc1: frc1, frc2: frc2)
        }
        
        
        override func createModel(fetchedObjects1: [PersistedMessageReactionSent], fetchedObjects2: [PersistedMessageReactionReceived]) throws -> ObvReactionsCountViewModel {

            let reactionsSent = fetchedObjects1
            let reactionsReceived = fetchedObjects2

            var reactions = [Character]()
            if let reactionSent = reactionsSent.first, let emoji = reactionSent.emoji, let reaction = emoji.first {
                reactions.append(reaction)
            }
            reactions.append(contentsOf: reactionsReceived.compactMap({ reactionReceived in
                guard let emoji = reactionReceived.emoji, let reaction = emoji.first else { return nil }
                return reaction
                
            }))
            
            var countForReaction = [Character: Int]()
            for reaction in reactions {
                var count = countForReaction[reaction, default: 0]
                count += 1
                countForReaction[reaction] = count
            }
            
            let reactionsAndCount: [ObvReactionsCountViewModel.ReactionAndCount] = countForReaction.map { (reaction, count) in
                return ObvReactionsCountViewModel.ReactionAndCount(emoji: reaction, count: count)
            }
            
            return .init(reactionsAndCount: reactionsAndCount)
        }
        
        
        enum ObvError: Error {
            case unexpectedMessageIdentifierType
        }

    }
    
}

extension ObvMessageReactionsViewAppDataSource {
    
    /// This manager produces the stream of the model required to display information about a single **sent** reaction. This include, e.g., the
    /// name of the user who reacted, the reaction itself, etc.
    private final class SentReactionCellViewModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvSingleDiscussion.ReactionCellViewModel, PersistedMessageReactionSent, PersistedObvOwnedIdentity>, @unchecked Sendable {
        
        private var cancellables: Set<AnyCancellable> = []

        init(persistedMessageReactionSentObjectID: TypeSafeManagedObjectID<PersistedMessageReactionSent>, ownedCryptoId: ObvCryptoId, context: NSManagedObjectContext) throws {
            let frc1 = PersistedMessageReactionSent.getFetchedResultsControllerForPersistedMessageReactionSent(
                objectID: persistedMessageReactionSentObjectID,
                within: context)
            let frc2 = PersistedObvOwnedIdentity.getFetchedResultsController(
                ownedCryptoId: ownedCryptoId,
                within: context)
            super.init(frc1: frc1, frc2: frc2)
            continuouslyObservePreferredEmojis()
        }
        
        
        deinit {
            cancellables.forEach { $0.cancel() }
        }
        
        
        private func continuouslyObservePreferredEmojis() {
            ObvMessengerSettingsObservableObject.shared.$preferredEmojisList
                .dropFirst()
                .sink { [weak self] _ in
                    guard let self else { return }
                    Task { [weak self] in
                        guard let self else { return }
                        do {
                            try await getFetchedObjectsAndYieldModelIfNeeded()
                        } catch {
                            assertionFailure(error.localizedDescription)
                        }
                    }
                }
                .store(in: &cancellables)
        }
        
        
        override func createModel(fetchedObjects1: [PersistedMessageReactionSent], fetchedObjects2: [PersistedObvOwnedIdentity]) throws -> ReactionCellViewModel {
            guard let sentReaction = fetchedObjects1.first else {
                throw ObvError.couldNotFindReaction
            }
            let preferredEmojisList = ObvMessengerSettings.Emoji.preferredEmojisList
            guard let ownedIdentity = sentReaction.message?.discussion?.ownedIdentity else {
                assertionFailure()
                throw ObvError.couldNotDetermineOwnedIdentity
            }
            let avatar = ObvAvatarViewModel(ownedIdentity: ownedIdentity)
            let displayName = String(localized: "YOU")
            let date = sentReaction.timestamp
            let positionAndCompany: String? = nil
            let reaction: Character = sentReaction.emoji?.first ?? Character(" ")
            let isOwnReaction = true
            let reactionIsPartOfPreferedReactions = preferredEmojisList.contains(String(reaction))
            return .init(avatar: avatar,
                         displayName: displayName,
                         date: date,
                         positionAndCompany: positionAndCompany,
                         reaction: reaction,
                         isOwnReaction: isOwnReaction,
                         reactionIsPartOfPreferedReactions: reactionIsPartOfPreferedReactions)
        }
        
        
        enum ObvError: Error {
            case couldNotFindReaction
            case fetchedObjectsIsNil
            case couldNotDetermineOwnedIdentity
        }
        
    }
    
    
    /// This manager produces the stream of the model required to display information about a single **received** reaction. This include, e.g., the
    /// name of the user who reacted, the reaction itself, etc.
    private final class ReceivedReactionCellViewModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvSingleDiscussion.ReactionCellViewModel, PersistedMessageReactionReceived, PersistedObvContactIdentity>, @unchecked Sendable {
        
        private var cancellables: Set<AnyCancellable> = []

        init(persistedMessageReactionReceivedObjectID: TypeSafeManagedObjectID<PersistedMessageReactionReceived>, contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, context: NSManagedObjectContext) throws {
            let frc1 = PersistedMessageReactionReceived.getFetchedResultsControllerForPersistedMessageReactionReceived(
                objectID: persistedMessageReactionReceivedObjectID,
                within: context)
            let frc2 = PersistedObvContactIdentity.getFetchedResultsController(
                objectID: contactObjectID,
                within: context)
            super.init(frc1: frc1, frc2: frc2)
            continuouslyObservePreferredEmojis()
        }
        
        
        deinit {
            cancellables.forEach { $0.cancel() }
        }
        
        
        private func continuouslyObservePreferredEmojis() {
            ObvMessengerSettingsObservableObject.shared.$preferredEmojisList
                .dropFirst()
                .sink { [weak self] _ in
                    guard let self else { return }
                    Task { [weak self] in
                        guard let self else { return }
                        do {
                            try await getFetchedObjectsAndYieldModelIfNeeded()
                        } catch {
                            assertionFailure()
                        }
                    }
                }
                .store(in: &cancellables)
        }
        
        
        override func createModel(fetchedObjects1: [PersistedMessageReactionReceived], fetchedObjects2: [PersistedObvContactIdentity]) throws -> ReactionCellViewModel {
            let fetchedObjects = fetchedObjects1
            guard let receivedReaction = fetchedObjects.first else {
                throw ObvError.couldNotFindReaction
            }
            let preferredEmojisList = ObvMessengerSettings.Emoji.preferredEmojisList
            guard let contact = receivedReaction.contact else {
                assertionFailure()
                throw ObvError.couldNotDetermineContact
            }
            let avatar = ObvAvatarViewModel(contact: contact)
            let displayName = contact.customOrNormalDisplayName
            let date = receivedReaction.timestamp
            let positionAndCompany = contact.identityCoreDetails?.positionAtCompany()
            let reaction: Character = receivedReaction.emoji?.first ?? Character(" ")
            let isOwnReaction = false
            let reactionIsPartOfPreferedReactions = preferredEmojisList.contains(String(reaction))
            return .init(avatar: avatar,
                         displayName: displayName,
                         date: date,
                         positionAndCompany: positionAndCompany,
                         reaction: reaction,
                         isOwnReaction: isOwnReaction,
                         reactionIsPartOfPreferedReactions: reactionIsPartOfPreferedReactions)
        }
        
        
        enum ObvError: Error {
            case couldNotFindReaction
            case fetchedObjectsIsNil
            case couldNotDetermineContact
        }
        
    }

}


extension ObvMessageReactionsViewAppDataSource {
    
    /// This manager produces the stream of the reaction identifiers shown on the view shown to the user when she wants to know about the details of the reactions made on a specific message.
    /// The identifiers should include the "sent" reaction if any.
    private final class ObvMessageReactionsViewModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvSingleDiscussion.ObvMessageReactionsViewModel, PersistedMessageReactionSent, PersistedMessageReactionReceived>, @unchecked Sendable {
        
        init(messageIdentifier: ObvSingleDiscussion.ObvMessageReactionsViewModel.MessageIdentifier, context: NSManagedObjectContext) throws {
            let messageObjectID: TypeSafeManagedObjectID<PersistedMessage>
            switch messageIdentifier {
            case .objectID(let objectID):
                messageObjectID = TypeSafeManagedObjectID<PersistedMessage>(objectID: objectID)
            case .forPreview:
                assertionFailure()
                throw ObvError.unexpectedMessageIdentifierType
            }
            let frc1 = PersistedMessageReactionSent.getFetchedResultsControllerForSentReactionOnMessage(
                messageObjectID: messageObjectID,
                within: context)
            let frc2 = PersistedMessageReactionReceived.getFetchedResultsControllerForReceivedReactionOnMessage(
                messageObjectID: messageObjectID,
                within: context)
            super.init(frc1: frc1, frc2: frc2)
        }
        
        
        override func createModel(fetchedObjects1: [PersistedMessageReactionSent], fetchedObjects2: [PersistedMessageReactionReceived]) throws -> ObvMessageReactionsViewModel {

            let reactionsSent = fetchedObjects1
            let reactionsReceived = fetchedObjects2
            
            var reactionsIdentifiers = [ObvSingleDiscussion.ObvMessageReactionsViewModel.ReactionIdentifier]()
            // Insert our own "sent" reaction first
            if let reactionSent = reactionsSent.first {
                reactionsIdentifiers.append(.objectID(reactionSent.objectID))
            }
            // Insert the received reactions
            reactionsIdentifiers.append(contentsOf: reactionsReceived.map({ .objectID($0.objectID) }))
            // Return the model
            return .init(reactionsIdentifiers: reactionsIdentifiers)
        }
        
        
        enum ObvError: Error {
            case unexpectedMessageIdentifierType
        }
        
    }
    
}
