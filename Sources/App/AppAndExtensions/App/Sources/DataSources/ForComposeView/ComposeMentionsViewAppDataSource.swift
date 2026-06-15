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
import ObvComposition
import ObvUICoreData
import ObvAppTypes
import CoreData
import OSLog
import ObvAppCoreConstants

@MainActor
final class ComposeMentionsViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ComposeMentionsViewAppDataSource")

    //private var streams: [UUID: AsyncStream<ComposeSuggestionsModel>.Continuation] = [:]
    
    //private var latestYieldedModel: ComposeSuggestionsModel?
    
    private var composeSuggestionsModelStreamManagerForStreamUUID: [UUID: ComposeSuggestionsModelStreamManager] = [:]

    init(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
    }
    
//    private func yield(model: ComposeSuggestionsModel) {
//        guard latestYieldedModel != model else { return }
//        latestYieldedModel = model
//        for stream in streams {
//            stream.value.yield(model)
//        }
//    }
    
//    func getSuggestions(with query: String?, with range: Range<AttributedString.Index>?, discussionIdentifier: ObvDiscussionIdentifier) {
//        
//        guard let query/*, !query.isEmpty*/ else {
//            yield(model: ComposeSuggestionsModel(mentions: [], range: range))
//            return
//        }
//        
//        guard let discussion = try? PersistedDiscussion.get(objectID: discussionObjectID, within: viewContext) else { assertionFailure("failed to retrieve discussion"); return }
//        
//        guard let discussionKind = try? discussion.kind else { assertionFailure("failed to retrieve discussion kind"); return }
//        
//        guard let ownedIdentity = discussion.ownedIdentity else { assertionFailure("our owned identity does not exist, can't mention"); return }
//        
//        var mentionableIdentities = [ComposeMentionSuggestionModel]()
//        
//        switch discussionKind {
//        case .oneToOne(withContactIdentity: let otherContactIdentity):
//            
//            guard let otherContactIdentity else { return }
//            
//            let shouldIncludeContactInResults: Bool = (try? PersistedObvContactIdentity.filterAll(objectIDs: [otherContactIdentity.typedObjectID], searchText: query, within: viewContext).isEmpty) == false
//            
//            if shouldIncludeContactInResults {
//                mentionableIdentities.append(.init(otherContactIdentity))
//            }
//            
//        case .groupV1(withContactGroup: let contactGroup):
//            guard let contactGroup else { return }
//            
//            let allContacts = contactGroup.sortedContactIdentities
//            let contactObjectIDs = allContacts
//                .map(\.typedObjectID)
//            let filteredContactObjectIDs = (try? PersistedObvContactIdentity.filterAll(objectIDs: contactObjectIDs, searchText: query, within: viewContext)) ?? []
//            let filteredContacts = allContacts.filter { filteredContactObjectIDs.contains($0.typedObjectID) }
//                                                                                     
//            mentionableIdentities += filteredContacts.map({ .init($0) })
//                            
//        case .groupV2(withGroup: let group):
//            guard let group else { return }
//
//            let otherMembersFiltered = (try? group.otherMembersSorted.filterAll(searchText: query)) ?? group.otherMembersSorted
//            mentionableIdentities += otherMembersFiltered.map({ .init($0) })
//            
//        }
//        
//        // Add the owned identity at the end of the list if appropriate
//        
//        if let modelForOwned = Self.getComposeSuggestionsModelFiltered(with: query, ownedIdentity: ownedIdentity) {
//            mentionableIdentities.append(modelForOwned)
//        }
//
//        yield(model: ComposeSuggestionsModel(mentions: mentionableIdentities, range: range))
//        
//    }
    
    
//    private static func getComposeSuggestionsModelFiltered(with query: String, ownedIdentity: PersistedObvOwnedIdentity) -> ComposeMentionSuggestionModel? {
//        let model = ComposeMentionSuggestionModel(ownedIdentity)
//        if query.isEmpty { return model }
//        let predicate = NSPredicate(format: "self CONTAINS[cd] %@", query)
//        return predicate.evaluate(with: model.title) ? model : nil
//    }
    
    
    
}


// MARK: - Implemention ComposeMentionsViewDataSource

extension ComposeMentionsViewAppDataSource: ComposeMentionsViewDataSource {
    
    func getAsyncStreamOfComposeSuggestionsModel(_ view: ComposeMentionsView, discussionIdentifier: ObvDiscussionIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ComposeSuggestionsModel>) {
        let manager = ComposeSuggestionsModelStreamManager(discussionIdentifier: discussionIdentifier, viewContext: viewContext)
        composeSuggestionsModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try manager.startStream()
    }
    
    func getSuggestions(_ view: ComposeMentionsView, with query: String?, streamUUID: UUID) {
        guard let manager = composeSuggestionsModelStreamManagerForStreamUUID[streamUUID] else { assertionFailure(); return }
        manager.getSuggestions(with: query, with: nil)
    }
    
    func finishAsyncStreamOfComposeSuggestionsModel(_ view: ComposeMentionsView, streamUUID: UUID) {
        if let manager = composeSuggestionsModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            manager.finishStream()
        }
    }

}


// MARK: - Internal managers

extension ComposeMentionsViewAppDataSource {
    
    @MainActor
    private final class ComposeSuggestionsModelStreamManager {
        
        let viewContext: NSManagedObjectContext
        let discussionIdentifier: ObvDiscussionIdentifier
        let streamUUID = UUID()
        private var stream: AsyncStream<ObvComposition.ComposeSuggestionsModel>?
        private var continuation: AsyncStream<ObvComposition.ComposeSuggestionsModel>.Continuation?
        private var previouslyYieldedModel: ObvComposition.ComposeSuggestionsModel?

        init(discussionIdentifier: ObvDiscussionIdentifier, viewContext: NSManagedObjectContext) {
            self.discussionIdentifier = discussionIdentifier
            self.viewContext = viewContext
            assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        }
        
        func startStream() throws -> (streamUUID: UUID, stream: AsyncStream<ObvComposition.ComposeSuggestionsModel>) {
            if let stream {
                return (streamUUID, stream)
            }

            let stream = AsyncStream(ObvComposition.ComposeSuggestionsModel.self) { [weak self] (continuation: AsyncStream<ObvComposition.ComposeSuggestionsModel>.Continuation) in
                guard let self else { return }
                self.continuation = continuation
                let model = createModel(query: nil, with: nil)
                yieldModelIfNeeded(model: model)
            }
            self.stream = stream
            return (streamUUID, stream)
        }

        
        func finishStream() {
            continuation?.finish()
            continuation = nil
        }
        
        
        func getSuggestions(with query: String?, with range: Range<AttributedString.Index>?) {
            let model = createModel(query: query, with: range)
            yieldModelIfNeeded(model: model)
        }
        

        private func createModel(query: String?, with range: Range<AttributedString.Index>?) -> ObvComposition.ComposeSuggestionsModel {
            
            let emptyModel = ComposeSuggestionsModel(mentions: [], range: range)
            
            guard let query/*, !query.isEmpty*/ else {
                return emptyModel
            }
            
            guard let discussion = try? PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: discussionIdentifier, within: viewContext) else { assertionFailure("failed to retrieve discussion"); return emptyModel }
            
            guard let discussionKind = try? discussion.kind else { assertionFailure("failed to retrieve discussion kind"); return emptyModel }
            
            guard let ownedIdentity = discussion.ownedIdentity else { assertionFailure("our owned identity does not exist, can't mention"); return  emptyModel}
            
            var mentionableIdentities = [ComposeMentionSuggestionModel]()
            
            switch discussionKind {
            case .oneToOne(withContactIdentity: let otherContactIdentity):
                
                guard let otherContactIdentity else { return emptyModel }
                
                let shouldIncludeContactInResults: Bool = (try? PersistedObvContactIdentity.filterAll(objectIDs: [otherContactIdentity.typedObjectID], searchText: query, within: viewContext).isEmpty) == false
                
                if shouldIncludeContactInResults {
                    mentionableIdentities.append(.init(otherContactIdentity))
                }
                
            case .groupV1(withContactGroup: let contactGroup):
                guard let contactGroup else { return emptyModel }
                
                let allContacts = contactGroup.sortedContactIdentities
                let contactObjectIDs = allContacts
                    .map(\.typedObjectID)
                let filteredContactObjectIDs = (try? PersistedObvContactIdentity.filterAll(objectIDs: contactObjectIDs, searchText: query, within: viewContext)) ?? []
                let filteredContacts = allContacts.filter { filteredContactObjectIDs.contains($0.typedObjectID) }
                                                                                         
                mentionableIdentities += filteredContacts.map({ .init($0) })
                                
            case .groupV2(withGroup: let group):
                guard let group else { return emptyModel }

                let otherMembersFiltered = (try? group.otherMembersSorted.filterAll(searchText: query)) ?? group.otherMembersSorted
                mentionableIdentities += otherMembersFiltered.map({ .init($0) })
                
            }
            
            // Add the owned identity at the end of the list if appropriate
            
            if let modelForOwned = Self.getComposeSuggestionsModelFiltered(with: query, ownedIdentity: ownedIdentity) {
                mentionableIdentities.append(modelForOwned)
            }
            
            // Sort mentionableIdentities so that those starting with the query appear first
            mentionableIdentities.sort { lhs, rhs in
                let lhsStartsWithQuery = lhs.title.lowercased().hasPrefix(query.lowercased())
                let rhsStartsWithQuery = rhs.title.lowercased().hasPrefix(query.lowercased())
                
                if lhsStartsWithQuery && !rhsStartsWithQuery {
                    return true // lhs comes first
                } else if !lhsStartsWithQuery && rhsStartsWithQuery {
                    return false // rhs comes first
                } else {
                    return false // maintain original order for items in the same category
                }
            }
            
            return ComposeSuggestionsModel(mentions: mentionableIdentities, range: range)


        }

        
        private func yieldModelIfNeeded(model: ObvComposition.ComposeSuggestionsModel) {
            guard let continuation else { assertionFailure(); return }
            guard previouslyYieldedModel != model else { return }
            previouslyYieldedModel = model
            continuation.yield(model)
        }

        
        private static func getComposeSuggestionsModelFiltered(with query: String, ownedIdentity: PersistedObvOwnedIdentity) -> ComposeMentionSuggestionModel? {
            let model = ComposeMentionSuggestionModel(ownedIdentity)
            if query.isEmpty { return model }
            let predicate = NSPredicate(format: "self CONTAINS[cd] %@", query)
            return predicate.evaluate(with: model.title) ? model : nil
        }

    }
    
}


// MARK: - Private helpers

private extension ComposeMentionSuggestionModel {
    
    init(_ ownedIdentity: PersistedObvOwnedIdentity) {
        
        let title = PersonNameComponentsFormatter.localizedString(
            from: ownedIdentity.personNameComponents,
            style: .medium)
        
        self.init(title: title,
                  mentionedCryptoId: ownedIdentity.cryptoId,
                  avatarModel: .init(ownedIdentity: ownedIdentity))
        
    }
    
    
    init(_ contactIdentity: PersistedObvContactIdentity) {
        
        let title: String
        if let personNameComponents = contactIdentity.personNameComponents {
            title = PersonNameComponentsFormatter.localizedString(from: personNameComponents, style: .medium)
        } else {
            title = contactIdentity.fullDisplayName
        }

        self.init(title: title,
                  mentionedCryptoId: contactIdentity.cryptoId,
                  avatarModel: .init(contact: contactIdentity))
        
    }

    
    init(_ groupMember: PersistedGroupV2Member) {
        
        if let contact = groupMember.contact {
            
            self = .init(contact)
            
        } else {
            
            var personNameComponents = PersonNameComponents()
            personNameComponents.givenName = groupMember.firstName
            personNameComponents.familyName = groupMember.lastName
            let title = PersonNameComponentsFormatter.localizedString(from: personNameComponents, style: .default)
            
            self.init(title: title,
                      mentionedCryptoId: groupMember.cryptoId,
                      avatarModel: .init(groupV2Member: groupMember))
        }
        
    }
    
}
