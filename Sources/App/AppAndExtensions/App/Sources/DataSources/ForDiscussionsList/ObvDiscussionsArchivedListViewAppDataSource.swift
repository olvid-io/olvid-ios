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
import CoreData
import ObvDiscussionsList
import ObvDesignSystem
import ObvTypes
import ObvUICoreData
import ObvProfilePictureBarButtonItem
import OlvidUtils


/// This data source is used when displaying the list of archived discussions. It is similar to `ObvDiscussionsListViewAppDataSource`, but it restricts to archived discussions.
@MainActor
final class ObvDiscussionsArchivedListViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    
    private var discussionsListViewModelStreamManagerForStreamUUID = [UUID: DiscussionsListViewModelStreamManager]()
    private var discussionCellViewModelStreamManagerForStreamUUID = [UUID: DiscussionCellViewModelStreamManager]()
    private var userActivityDiscussionIdentifierContinuationForStreamUUID = [UUID: AsyncStream<ObvDiscussionsList.ObvDiscussionsListViewModel.DiscussionIdentifier?>.Continuation]()

    private var cancellables: Set<AnyCancellable> = []
    
    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
        produceStreamsOnChangeOfDiscussionID()
    }
    
    deinit {
        cancellables.forEach { $0.cancel() }
    }
    
}


// MARK: - Implementing ObvDiscussionsListViewDataSource

extension ObvDiscussionsArchivedListViewAppDataSource: ObvDiscussionsListViewDataSource {

    // For the list of recent discussion's identifiers
    
    func getAsyncStreamOfObvDiscussionsListViewModel(_ view: ObvDiscussionsListView, ownedCryptoId: ObvCryptoId, initialSearchText: String?) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvDiscussionsListViewModel>) {
        let manager = DiscussionsListViewModelStreamManager(ownedCryptoId: ownedCryptoId, initialSearchText: initialSearchText, context: backgroundContext)
        discussionsListViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }

    
    func finishAsyncStreamOfObvDiscussionsListViewModel(_ view: ObvDiscussionsListView, streamUUID: UUID) {
        guard let manager = discussionsListViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
    
    func filterAsyncStreamOfObvDiscussionsListViewModel(_ view: ObvDiscussionsListView, streamUUID: UUID, searchStatus: ObvDiscussionsListViewModel.SearchStatus) {
        guard let manager = discussionsListViewModelStreamManagerForStreamUUID[streamUUID] else { return }
        manager.updateWithSearchText(searchStatus: searchStatus, doPerformFetch: true)
    }
    
    
    func getIdentifiersOfCurrentlyPinnedDiscussions(ownedCryptoId: ObvCryptoId) async throws -> [ObvDiscussionsListViewModel.DiscussionIdentifier] {
        let pinnedDiscussions = try PersistedDiscussion.getAllPinnedDiscussions(ownedCryptoId: ownedCryptoId, with: viewContext)
        let viewIdentifiers: [ObvDiscussionsListViewModel.DiscussionIdentifier] = pinnedDiscussions.map { .persistedDiscussionObjectID($0.objectID) }
        return viewIdentifiers
    }

    
    // For an individual cell, showing a recent discussion
    
    func getAsyncStreamOfObvDiscussionCellViewModel(_ view: DiscussionCellView, discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvDiscussionCellViewModel>) {
        let manager = try DiscussionCellViewModelStreamManager(discussionIdentifier: discussionIdentifier, context: backgroundContext)
        discussionCellViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    
    func finishAsyncStreamOfObvDiscussionCellViewModel(_ view: DiscussionCellView, streamUUID: UUID) {
        guard let manager = discussionCellViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
    func getInitialObvDiscussionCellViewModel(discussionIdentifier: ObvDiscussionsListViewModel.DiscussionIdentifier) -> ObvDiscussionCellViewModel? {
        guard let discussionObjectID = discussionIdentifier.objectID else { assertionFailure(); return nil }
        guard let discussion = try? PersistedDiscussion.get(objectID: discussionObjectID, within: viewContext) else { return nil }
        guard let model = try? ObvDiscussionCellViewModel(discussion: discussion) else { assertionFailure(); return nil }
        return model
    }
    
    // On mac/iPad: Highlighting the discussion the user is in
    
    func getAsyncStreamOfUserActivityDiscussionIdentifier(_ view: DiscussionCellView) throws -> (streamUUID: UUID, stream: AsyncStream<ObvDiscussionsListViewModel.DiscussionIdentifier?>) {
        let streamUUID = UUID()
        let stream = AsyncStream(ObvDiscussionsList.ObvDiscussionsListViewModel.DiscussionIdentifier?.self) { [weak self] (continuation: AsyncStream<ObvDiscussionsList.ObvDiscussionsListViewModel.DiscussionIdentifier?>.Continuation) in
            guard let self else { continuation.finish(); return }
            userActivityDiscussionIdentifierContinuationForStreamUUID[streamUUID] = continuation
            // Send the latest version of the stream
            if let objectID = OlvidUserActivitySingleton.shared.currentDiscussionID?.objectID.objectID {
                continuation.yield(.persistedDiscussionObjectID(objectID))
            } else {
                continuation.yield(nil)
            }
        }
        return (streamUUID, stream)
    }
    
    
    func finishAsyncStreamOfUserActivityDiscussionIdentifier(_ view: DiscussionCellView, streamUUID: UUID) {
        if let continuation = userActivityDiscussionIdentifierContinuationForStreamUUID.removeValue(forKey: streamUUID) {
            continuation.finish()
        }
    }

    private func produceStreamsOnChangeOfDiscussionID() {
        OlvidUserActivitySingleton.shared.$currentDiscussionID
            .sink { [weak self] newValue in
                self?.userActivityDiscussionIdentifierContinuationForStreamUUID.values.forEach { continuation in
                    if let newValue {
                        continuation.yield(.persistedDiscussionObjectID(newValue.objectID.objectID))
                    } else {
                        continuation.yield(nil)
                    }
                }
            }
            .store(in: &cancellables)
    }

}


// MARK: - Internal managers

extension ObvDiscussionsArchivedListViewAppDataSource {
    
    /// This manager produces the stream of the discussion identifiers shown on the "home page" of the app, i.e., the list of recent discussions shown in the left-most tab.
    /// When not performing a search, this manager stream the identifiers of pinned and unpinned discussions that are *not* archived, and not deleted.
    /// During a search, it adds the archived and deleted discussions to the list.
    private final class DiscussionsListViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvDiscussionsList.ObvDiscussionsListViewModel, PersistedDiscussion>, @unchecked Sendable {
        
        private let ownedCryptoId: ObvCryptoId
        let initialPredicateWhenUserDoesNotPerformSearch: NSPredicate
        let initialPredicateWhenUserPerformsSearch: NSPredicate
        private let contentUnavailableViewModel: ObvContentUnavailableView.Model = .init(title: String(localized: "CONTENT_UNAVAILABLE_ARCHIVED_DISCUSSIONS_TEXT"),
                                                                                         systemIcon: .archivebox,
                                                                                         description: String(localized: "CONTENT_UNAVAILABLE_ARCHIVED_DISCUSSIONS_SECONDARY"))

        init(ownedCryptoId: ObvCryptoId, initialSearchText: String?, context: NSManagedObjectContext) {
            self.ownedCryptoId = ownedCryptoId
            // Note that `createModel()` expects the frc to contain two sections (so the splitPinnedDiscussionsIntoSections must be set to true here)
            self.initialPredicateWhenUserDoesNotPerformSearch = PersistedDiscussion.getPredicateForArchivedNotDeletedDiscussionsForOwnedIdentity(ownedCryptoId: ownedCryptoId)
            self.initialPredicateWhenUserPerformsSearch = PersistedDiscussion.getPredicateForAllArchivedDiscussionsForOwnedIdentity(ownedCryptoId: ownedCryptoId)
            let frc = PersistedDiscussion.getFetchedResultsControllerWithPinnedDiscussionsSplitIntoSections(predicate: self.initialPredicateWhenUserDoesNotPerformSearch, within: context)
            super.init(frc: frc)
            self.updateWithSearchText(searchStatus: .notPerformingSearch, doPerformFetch: false)
        }

        func updateWithSearchText(searchStatus: ObvDiscussionsListViewModel.SearchStatus, doPerformFetch: Bool) {
            let newPredicate: NSPredicate
            switch searchStatus {
            case .notPerformingSearch:
                newPredicate = self.initialPredicateWhenUserDoesNotPerformSearch
            case .performingSearch(searchText: let searchText):
                let searchPredicate = PersistedDiscussion.getSearchPredicate(searchText)
                newPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    self.initialPredicateWhenUserPerformsSearch,
                    searchPredicate,
                ])
            }
            self.frc.fetchRequest.predicate = newPredicate
            if doPerformFetch {
                do {
                    try frc.performFetch()
                } catch {
                    assertionFailure()
                }
                Task {
                    do {
                        try await getFetchedObjectsAndYieldModelIfNeeded()
                    } catch {
                        assertionFailure(error.localizedDescription)
                    }
                }
            }
        }


        override func createModel(fetchedObjects: [PersistedDiscussion]) throws -> ObvDiscussionsListViewModel {
            
            guard let sections = frc.sections else {
                assertionFailure()
                throw ObvError.noSections
            }
            
            var identifiersOfPinnedDiscussions = [ObvDiscussionsListViewModel.DiscussionIdentifier]()
            var identifiersOfUnpinnedDiscussions = [ObvDiscussionsListViewModel.DiscussionIdentifier]()

            for section in sections {
                guard let objects = section.objects as? [PersistedDiscussion] else { assertionFailure(); continue }
                guard let sectionIdentifier = PersistedDiscussion.PinnedSectionKeyPathValue(rawValue: section.name) else { assertionFailure(); continue }
                switch sectionIdentifier {
                case .pinned:
                    identifiersOfPinnedDiscussions = objects.map { .persistedDiscussionObjectID($0.objectID) }
                case .unpinned:
                    identifiersOfUnpinnedDiscussions = objects.map { .persistedDiscussionObjectID($0.objectID) }
                }
            }
            
            let model = ObvDiscussionsList.ObvDiscussionsListViewModel(
                ownedCryptoId: ownedCryptoId,
                identifiersOfPinnedDiscussions: identifiersOfPinnedDiscussions,
                identifiersOfUnpinnedDiscussions: identifiersOfUnpinnedDiscussions,
                contentUnavailableViewModel: contentUnavailableViewModel)
            
            return model
            
        }

        enum ObvError: Error {
            case couldNotFetchObjects
            case ownedCryptoIdNotFound
            case noSections
        }

        
    }
        
}


extension ObvDiscussionsArchivedListViewAppDataSource {
    
    private final class DiscussionCellViewModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvDiscussionsList.ObvDiscussionCellViewModel, PersistedDiscussion, PersistedDiscussionLocalConfiguration>, @unchecked Sendable {
        
        init(discussionIdentifier: ObvDiscussionsList.ObvDiscussionsListViewModel.DiscussionIdentifier, context: NSManagedObjectContext) throws {
            let persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>
            switch discussionIdentifier {
            case .obvDiscussionIdentifier:
                assertionFailure()
                throw ObvError.unexpectedIdentifierKind
            case .persistedDiscussionObjectID(let objectID):
                persistedDiscussionObjectID = .init(objectID: objectID)
            }
            let frc = PersistedDiscussion.getFetchedResultsController(objectID: persistedDiscussionObjectID, within: context)
            let frcForLocalConfigurations = PersistedDiscussionLocalConfiguration.getFetchedResultsController(persistedDiscussionObjectID: persistedDiscussionObjectID, within: context)
            super.init(frc1: frc, frc2: frcForLocalConfigurations)
        }
        
        
        override func createModel(fetchedObjects1: [PersistedDiscussion], fetchedObjects2: [PersistedDiscussionLocalConfiguration]) throws -> ObvDiscussionCellViewModel {
            
            // The frcForLocalConfigurations is only required to be notified of a change that could result in a new view model value
            
            let fetchedObjects = fetchedObjects1
            
            assert(fetchedObjects.count < 2)
            
            guard let firstObject = fetchedObjects.first else {
                // This happens when the discussion gets deleted
                throw ObvError.objectDoesNotExist
            }
            
            let model = try ObvDiscussionCellViewModel(discussion: firstObject)
            
            return model
            
        }


        enum ObvError: Error {
            case unexpectedIdentifierKind
            case couldNotFetchObjects
            case objectDoesNotExist
        }
        

    }
        
}
