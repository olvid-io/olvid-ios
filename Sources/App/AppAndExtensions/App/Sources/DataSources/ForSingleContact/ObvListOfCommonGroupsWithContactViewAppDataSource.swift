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
import ObvTypes
import ObvSingleContact
import OlvidUtils
import ObvUICoreData
import ObvAppCoreConstants
import ObvCells



final class ObvListOfCommonGroupsWithContactViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    
    private var listOfCommonGroupsWithContactViewModelStreamManagerForStreamUUID = [UUID: ObvListOfCommonGroupsWithContactViewModelStreamManager]()
    
    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }

}


// MARK: - Implementing ObvListOfCommonGroupsWithContactViewDataSource

extension ObvListOfCommonGroupsWithContactViewAppDataSource: ObvListOfCommonGroupsWithContactViewDataSource {
    
    func getAsyncStreamOfObvGroupsListViewModel(_ view: ObvSingleContact.ObvListOfCommonGroupsWithContactView, contactIdentifier: ObvTypes.ObvContactIdentifier, initialSearchStatus: ObvSingleContact.ObvListOfCommonGroupsWithContactView.Model.SearchStatus) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvSingleContact.ObvListOfCommonGroupsWithContactView.Model>) {
        let manager = try ObvListOfCommonGroupsWithContactViewModelStreamManager(contactIdentifier: contactIdentifier, initialSearchStatus: initialSearchStatus, within: backgroundContext)
        listOfCommonGroupsWithContactViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfObvGroupsListViewModel(_ view: ObvSingleContact.ObvListOfCommonGroupsWithContactView, streamUUID: UUID) {
        guard let manager = listOfCommonGroupsWithContactViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
    func filterAsyncStreamOfObvGroupsListViewModel(_ view: ObvSingleContact.ObvListOfCommonGroupsWithContactView, streamUUID: UUID, searchStatus: ObvSingleContact.ObvListOfCommonGroupsWithContactView.Model.SearchStatus) {
        guard let manager = listOfCommonGroupsWithContactViewModelStreamManagerForStreamUUID[streamUUID] else { return }
        manager.updateWithSearchText(searchStatus: searchStatus, doPerformFetch: true)
    }
    
}


// MARK: - Internal manager

extension ObvListOfCommonGroupsWithContactViewAppDataSource {
    
    private final class ObvListOfCommonGroupsWithContactViewModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvSingleContact.ObvListOfCommonGroupsWithContactView.Model, PersistedObvContactIdentity, DisplayedContactGroup>, @unchecked Sendable {
        
        private let contactIdentifier: ObvTypes.ObvContactIdentifier
        private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ObvListOfCommonGroupsWithContactViewModelStreamManager")

        init(contactIdentifier: ObvTypes.ObvContactIdentifier, initialSearchStatus: ObvSingleContact.ObvListOfCommonGroupsWithContactView.Model.SearchStatus, within context: NSManagedObjectContext) throws {
            self.contactIdentifier = contactIdentifier
            let frc1 = PersistedObvContactIdentity.getFetchedResultsControllerForContactIdentifier(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: context)
            let fetchRequest = DisplayedContactGroup.getFetchRequestForAllDisplayedContactGroup(ownedIdentity: contactIdentifier.ownedCryptoId, contactIdentity: contactIdentifier.contactCryptoId)
            let frc2 = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                 managedObjectContext: context,
                                                 sectionNameKeyPath: DisplayedContactGroup.Predicate.Key.sectionName.rawValue,
                                                 cacheName: nil)
            super.init(frc1: frc1, frc2: frc2)
            updateWithSearchText(searchStatus: initialSearchStatus, doPerformFetch: false)
        }
        
        func updateWithSearchText(searchStatus: ObvSingleContact.ObvListOfCommonGroupsWithContactView.Model.SearchStatus, doPerformFetch: Bool) {
            guard let basePredicate = DisplayedContactGroup.getFetchRequestForAllDisplayedContactGroup(ownedIdentity: contactIdentifier.ownedCryptoId, contactIdentity: contactIdentifier.contactCryptoId).predicate else {
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
            
            self.frc2.fetchRequest.predicate = newPredicate
            if doPerformFetch {
                do {
                    try frc2.performFetch()
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

        override func createModel(fetchedObjects1: [PersistedObvContactIdentity], fetchedObjects2: [DisplayedContactGroup]) throws -> ObvListOfCommonGroupsWithContactView.Model {
            
            assert(fetchedObjects1.count <= 1)
            
            guard let contact = fetchedObjects1.first else {
                assertionFailure()
                throw ObvError.couldNotFindContact
            }
            
            guard let sections = frc2.sections else {
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
            
            let viewModel = try ObvListOfCommonGroupsWithContactView.Model(
                contact: contact,
                displayedContactGroupsAdministrated: displayedContactGroupsAdministrated,
                displayedContactGroupsJoined: displayedContactGroupsJoined)
            
            return viewModel
            
        }

        enum ObvError: Error {
            case couldNotFindContact
            case unexpectedSectionName
            case noCurrentOwnedCryptoId
            case fetchedObjectsIsNil
            case noSections
        }

    }
    
}


extension ObvListOfCommonGroupsWithContactView.Model {
    
    init(contact: PersistedObvContactIdentity, displayedContactGroupsAdministrated: [DisplayedContactGroup], displayedContactGroupsJoined: [DisplayedContactGroup]) throws {
        
        let identifiersOfGroupsAdministrated: [ObvCells.ObvGroupCellViewModel.GroupIdentifier] = displayedContactGroupsAdministrated.map {
            .objectIDOfDisplayedContactGroup($0.objectID)
        }
        
        let identifiersOfGroupsJoined: [ObvCells.ObvGroupCellViewModel.GroupIdentifier] = displayedContactGroupsJoined.map {
            .objectIDOfDisplayedContactGroup($0.objectID)
        }
        
        self.init(contactDisplayName: contact.customOrShortDisplayName,
                  identifiersOfGroupsAdministrated: identifiersOfGroupsAdministrated,
                  identifiersOfGroupsJoined: identifiersOfGroupsJoined)
        
        
        
    }
    
}
