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
import OSLog
import CoreData
import Combine
import ObvGroupsList
import OlvidUtils
import ObvUICoreData
import ObvTypes
import ObvDesignSystem
import ObvAppCoreConstants
import ObvSharedDataSources
import ObvCells


@MainActor
final class ObvGroupsListViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var obvGroupsListViewModelStreamManagerForStreamUUID = [UUID: ObvGroupsListViewModelStreamManager]()
    
    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
    
}

extension ObvGroupsListViewAppDataSource {
    
    enum ObvError: Error {
        case unexpectedGroupIdentifierType
        case noCurrentOwnedCryptoId
    }
    
}

// MARK: - Implementing ObvGroupsListViewDataSource

extension ObvGroupsListViewAppDataSource: ObvGroupsListViewDataSource {
    
    @MainActor
    func getObvGroupsListViewModel(_ view: ObvGroupsListView, searchStatus: ObvGroupsListViewModel.SearchStatus) throws -> ObvGroupsListViewModel? {
        assert(Thread.isMainThread)
        guard let currentOwnedCryptoId = OlvidUserActivitySingleton.shared.currentUserActivity?.ownedCryptoId else {
            assertionFailure()
            throw ObvError.noCurrentOwnedCryptoId
        }
        let identifiersOfGroupsAdministrated: [ObvCells.ObvGroupCellViewModel.GroupIdentifier] = try DisplayedContactGroup.getAllObjectIDs(
            ownedCryptoId: currentOwnedCryptoId,
            sectionName: "0",
            searchText: searchStatus.searchText,
            within: viewContext)
            .map { .objectIDOfDisplayedContactGroup($0.objectID) }
        let identifiersOfGroupsJoined: [ObvCells.ObvGroupCellViewModel.GroupIdentifier] = try DisplayedContactGroup.getAllObjectIDs(
            ownedCryptoId: currentOwnedCryptoId,
            sectionName: "1",
            searchText: searchStatus.searchText,
            within: viewContext)
            .map { .objectIDOfDisplayedContactGroup($0.objectID) }
        let viewModel = ObvGroupsListViewModel(
            currentOwnedCryptoId: currentOwnedCryptoId,
            identifiersOfGroupsAdministrated: identifiersOfGroupsAdministrated,
            identifiersOfGroupsJoined: identifiersOfGroupsJoined)
        return viewModel
    }
    
    
    func getAsyncStreamOfObvGroupsListViewModel(_ view: ObvGroupsListView, initialSearchStatus: ObvGroupsListViewModel.SearchStatus) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvGroupsListViewModel>) {
        let manager = try ObvGroupsListViewModelStreamManager(initialSearchStatus: initialSearchStatus, within: backgroundContext)
        obvGroupsListViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    
    func finishAsyncStreamOfObvGroupsListViewModel(_ view: ObvGroupsList.ObvGroupsListView, streamUUID: UUID) {
        guard let manager = obvGroupsListViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
    func filterAsyncStreamOfObvGroupsListViewModel(_ view: ObvGroupsList.ObvGroupsListView, streamUUID: UUID, searchStatus: ObvGroupsList.ObvGroupsListViewModel.SearchStatus) {
        guard let manager = obvGroupsListViewModelStreamManagerForStreamUUID[streamUUID] else { return }
        manager.updateWithSearchText(searchStatus: searchStatus, doPerformFetch: true)
    }
    
}


// MARK: - Internal managers

extension ObvGroupsListViewAppDataSource {
    
    private final class ObvGroupsListViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvGroupsList.ObvGroupsListViewModel, DisplayedContactGroup>, @unchecked Sendable {
        
        private var currentOwnedCryptoId: ObvCryptoId
        private var cancellables: Set<AnyCancellable> = []
        private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ObvGroupsListViewModelStreamManager")

        init(initialSearchStatus: ObvGroupsListViewModel.SearchStatus, within context: NSManagedObjectContext) throws {
            guard let currentOwnedCryptoId = OlvidUserActivitySingleton.shared.currentUserActivity?.ownedCryptoId else {
                assertionFailure()
                throw ObvError.noCurrentOwnedCryptoId
            }
            self.currentOwnedCryptoId = currentOwnedCryptoId
            let fetchRequest = DisplayedContactGroup.getNSFetchRequest(ownedCryptoId: currentOwnedCryptoId)
            let frc = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                 managedObjectContext: context,
                                                 sectionNameKeyPath: DisplayedContactGroup.Predicate.Key.sectionName.rawValue,
                                                 cacheName: nil)
            super.init(frc: frc)
            continuouslyObserveCurrentOwnedCryptoId()
            updateWithSearchText(searchStatus: initialSearchStatus, doPerformFetch: false)
        }
        
        
        func updateWithSearchText(searchStatus: ObvGroupsList.ObvGroupsListViewModel.SearchStatus, doPerformFetch: Bool) {
            guard let basePredicate = DisplayedContactGroup.getNSFetchRequest(ownedCryptoId: currentOwnedCryptoId).predicate else {
                Self.logger.fault("Could not obtain predicate during search")
                assertionFailure()
                return
            }

            let newPredicate: NSPredicate
            switch searchStatus {
            case .notPerformingSearch:
                newPredicate = basePredicate
            case .performingSearch(searchText: let searchText):
                let searchPredicate = DisplayedContactGroup.getSearchPredicate(searchText)
                newPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    basePredicate,
                    searchPredicate,
                ])
            }
            
            self.frc.fetchRequest.predicate = newPredicate
            if doPerformFetch {
                do {
                    try frc.performFetch()
                } catch {
                    Self.logger.fault("Failed to perform fetch with error: \(error)")
                    assertionFailure()
                    return
                }
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await getFetchedObjectsAndYieldModelIfNeeded()
                    } catch {
                        assertionFailure(error.localizedDescription)
                    }
                }
            }

        }
        
        
        deinit {
            cancellables.forEach { $0.cancel() }
        }

        
        private func continuouslyObserveCurrentOwnedCryptoId() {
            OlvidUserActivitySingleton.shared.$currentUserActivity
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    guard let newCurrentOwnedCryptoId = OlvidUserActivitySingleton.shared.currentUserActivity?.ownedCryptoId else { return }
                    guard self.currentOwnedCryptoId != newCurrentOwnedCryptoId else { return }
                    self.currentOwnedCryptoId = newCurrentOwnedCryptoId
                    let fetchRequest = DisplayedContactGroup.getNSFetchRequest(ownedCryptoId: currentOwnedCryptoId)
                    self.frc.fetchRequest.predicate = fetchRequest.predicate
                    do {
                        try self.frc.performFetch()
                    } catch {
                        Self.logger.fault("Could not re-perform fetch on change of current crypto id: \(error)")
                        assertionFailure()
                        return
                    }
                    Task { [weak self] in
                        guard let self else { return }
                        do {
                            try await getFetchedObjectsAndYieldModelIfNeeded()
                        } catch {
                            Self.logger.fault("Could not create new model on change of current crypto id: \(error)")
                            assertionFailure(error.localizedDescription)
                        }
                    }
                }
                .store(in: &cancellables)
        }

        
        override func createModel(fetchedObjects: [DisplayedContactGroup]) throws -> ObvGroupsListViewModel {
            
            guard let sections = frc.sections else {
                assertionFailure()
                throw ObvError.noSections
            }

            var displayedContactGroupsAdministrated = [DisplayedContactGroup]()
            var displayedContactGroupsJoined = [DisplayedContactGroup]()
            for section in sections {
                guard let groups = section.objects as? [DisplayedContactGroup] else {
                    assertionFailure()
                    throw ObvError.fetchedObjectsIsNil
                }
                switch section.name {
                case "0":
                    displayedContactGroupsAdministrated = groups
                case "1":
                    displayedContactGroupsJoined = groups
                default:
                    throw ObvError.unexpectedSectionName
                }
            }
            
            let viewModel = try ObvGroupsListViewModel(
                currentOwnedCryptoId: self.currentOwnedCryptoId,
                displayedContactGroupsAdministrated: displayedContactGroupsAdministrated,
                displayedContactGroupsJoined: displayedContactGroupsJoined)
            
            return viewModel
            
        }
        
        enum ObvError: Error {
            case unexpectedSectionName
            case noCurrentOwnedCryptoId
            case fetchedObjectsIsNil
            case noSections
        }
        
    }
    
}


// MARK: - Helpers

extension ObvGroupCellViewModel {
    
    init(displayedContactGroup: DisplayedContactGroup) throws {
        
        let showGreenShield: Bool = displayedContactGroup.groupV2?.keycloakManaged ?? false

        let hasUpdatedDetails: HasUpdatedDetails
        if let groupV1 = displayedContactGroup.groupV1 {
            if let groupJoined = groupV1 as? PersistedContactGroupJoined {
                switch groupJoined.status {
                case .noNewPublishedDetails:
                    hasUpdatedDetails = .noNewPublishedDetails
                case .unseenPublishedDetails:
                    hasUpdatedDetails = .unseenPublishedDetails
                case .seenPublishedDetails:
                    hasUpdatedDetails = .seenPublishedDetails
                }
            } else {
                hasUpdatedDetails = .noNewPublishedDetails
            }
        } else if let groupV2 = displayedContactGroup.groupV2 {
            switch groupV2.publishedDetailsStatus {
            case .noNewPublishedDetails:
                hasUpdatedDetails = .noNewPublishedDetails
            case .unseenPublishedDetails:
                hasUpdatedDetails = .unseenPublishedDetails
            case .seenPublishedDetails:
                hasUpdatedDetails = .seenPublishedDetails
            }
        } else {
            hasUpdatedDetails = .noNewPublishedDetails
        }
        
        let updateInProgress: Bool = displayedContactGroup.updateInProgress
        
        self.init(groupIdentifier: try displayedContactGroup.groupIdentifier,
                  avatarModel: try .init(displayedContactGroup: displayedContactGroup),
                  title: displayedContactGroup.displayedTitle,
                  listOfGroupMemberNames: displayedContactGroup.subtitle ?? " ",
                  showGreenShield: showGreenShield,
                  hasUpdatedDetails: hasUpdatedDetails,
                  updateInProgress: updateInProgress)
    }
    
}


extension ObvGroupsList.ObvGroupsListViewModel {
    
    init(currentOwnedCryptoId: ObvCryptoId, displayedContactGroupsAdministrated: [DisplayedContactGroup], displayedContactGroupsJoined: [DisplayedContactGroup]) throws {
        
        let identifiersOfGroupsAdministrated: [ObvCells.ObvGroupCellViewModel.GroupIdentifier] = displayedContactGroupsAdministrated.map {
            .objectIDOfDisplayedContactGroup($0.objectID)
        }

        let identifiersOfGroupsJoined: [ObvCells.ObvGroupCellViewModel.GroupIdentifier] = displayedContactGroupsJoined.map {
            .objectIDOfDisplayedContactGroup($0.objectID)
        }

        self.init(currentOwnedCryptoId: currentOwnedCryptoId,
                  identifiersOfGroupsAdministrated: identifiersOfGroupsAdministrated,
                  identifiersOfGroupsJoined: identifiersOfGroupsJoined)
        
    }
    
}
