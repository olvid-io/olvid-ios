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
import OlvidUtils
import ObvUIGroupSharedBetweenV1AndV2
import ObvUICoreData
import ObvTypes
import ObvAppTypes


@MainActor
final class ListOfMembersWithAddAndRemoveButtonsViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
 
    private var listOfMembersWithAddAndRemoveButtonsViewModelStreamManagerForGroupV1ForStreamUUID = [UUID: ListOfMembersWithAddAndRemoveButtonsViewModelStreamManagerForGroupV1]()
    private var listOfMembersWithAddAndRemoveButtonsViewModelStreamManagerForGroupV2ForStreamUUID = [UUID: ListOfMembersWithAddAndRemoveButtonsViewModelStreamManagerForGroupV2]()
    
}


extension ListOfMembersWithAddAndRemoveButtonsViewAppDataSource: ListOfMembersWithAddAndRemoveButtonsViewDataSource {
    
    func getAsyncSequenceOfListOfMembersWithAddAndRemoveButtonsViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfMembersWithAddAndRemoveButtonsView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, searchText: String?) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.ListOfMembersWithAddAndRemoveButtonsView.Model>) {
        switch groupIdentifier {
        case .groupV1(let groupV1Identifier):
            let streamManager = ListOfMembersWithAddAndRemoveButtonsViewModelStreamManagerForGroupV1(groupV1Identifier: groupV1Identifier, searchText: searchText, context: backgroundContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.listOfMembersWithAddAndRemoveButtonsViewModelStreamManagerForGroupV1ForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        case .groupV2(let groupV2Identifier):
            let streamManager = ListOfMembersWithAddAndRemoveButtonsViewModelStreamManagerForGroupV2(groupV2Identifier: groupV2Identifier, searchText: searchText, context: backgroundContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.listOfMembersWithAddAndRemoveButtonsViewModelStreamManagerForGroupV2ForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        }
    }
    
    func filterAsyncSequenceOfListOfMembersWithAddAndRemoveButtonsViewModel(_ view: ListOfMembersWithAddAndRemoveButtonsView, streamUUID: UUID, searchText: String?) {
        if let streamManager = listOfMembersWithAddAndRemoveButtonsViewModelStreamManagerForGroupV1ForStreamUUID[streamUUID] {
            streamManager.updateWithSearchText(searchText: searchText)
        }
        if let streamManager = listOfMembersWithAddAndRemoveButtonsViewModelStreamManagerForGroupV2ForStreamUUID[streamUUID] {
            streamManager.updateWithSearchText(searchText: searchText)
        }
    }
    
    func finishAsyncSequenceOfListOfMembersWithAddAndRemoveButtonsViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfMembersWithAddAndRemoveButtonsView, streamUUID: UUID) {
        if let streamManager = listOfMembersWithAddAndRemoveButtonsViewModelStreamManagerForGroupV1ForStreamUUID[streamUUID] {
            streamManager.finishStream()
        }
        if let streamManager = listOfMembersWithAddAndRemoveButtonsViewModelStreamManagerForGroupV2ForStreamUUID[streamUUID] {
            streamManager.finishStream()
        }
    }
    
}


extension ListOfMembersWithAddAndRemoveButtonsViewAppDataSource {
    
    private final class ListOfMembersWithAddAndRemoveButtonsViewModelStreamManagerForGroupV2: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ListOfMembersWithAddAndRemoveButtonsView.Model, PersistedGroupV2Member, PersistedGroupV2>, @unchecked Sendable {
        
        private let groupV2Identifier: ObvGroupV2Identifier
        private var currentSearchText: String?

        init(groupV2Identifier: ObvGroupV2Identifier, searchText: String?, context: NSManagedObjectContext) {
            self.groupV2Identifier = groupV2Identifier
            self.currentSearchText = searchText
            let predicateForAllOtherGroupMembers = PersistedGroupV2Member.getPredicate(groupV2Identifier: groupV2Identifier, searchText: searchText)
            let frcForAllOtherGroupMembers = PersistedGroupV2Member.getFetchedResultsController(predicate: predicateForAllOtherGroupMembers, within: context)
            let frcForGroup = PersistedGroupV2.getFetchedResultsController(groupV2Identifier: groupV2Identifier, within: context)
            super.init(frc1: frcForAllOtherGroupMembers, frc2: frcForGroup)
        }

        override func createModel(fetchedObjects1: [PersistedGroupV2Member], fetchedObjects2: [PersistedGroupV2]) throws -> ListOfMembersWithAddAndRemoveButtonsView.Model {
            assert(fetchedObjects2.count <= 1)
            guard let group = fetchedObjects2.first else {
                throw ObvError.couldNotFindGroup
            }
            let model: ListOfMembersWithAddAndRemoveButtonsView.Model = .init(groupV2Identifier: groupV2Identifier, allOtherGroupMembers: fetchedObjects1, group: group)
            return model
        }
        
        func updateWithSearchText(searchText: String?) {
            frc1.managedObjectContext.perform { [weak self] in
                guard let self else { return }
                let predicateForAllOtherGroupMembers = PersistedGroupV2Member.getPredicate(groupV2Identifier: groupV2Identifier, searchText: searchText)
                self.frc1.fetchRequest.predicate = predicateForAllOtherGroupMembers
                do { try frc1.performFetch() } catch { assertionFailure() }
                Task { [weak self] in do { try await self?.getFetchedObjectsAndYieldModelIfNeeded() } catch { assertionFailure(error.localizedDescription) } }
            }
        }
        
        enum ObvError: Error {
            case couldNotFindGroup
        }

    }
    
}


extension ListOfMembersWithAddAndRemoveButtonsViewAppDataSource {
    
    private final class ListOfMembersWithAddAndRemoveButtonsViewModelStreamManagerForGroupV1: ObvDataSourceStreamManagerWithOneFetchedResultsController<ListOfMembersWithAddAndRemoveButtonsView.Model, PersistedContactGroup>, @unchecked Sendable {
        
        private var currentSearchText: String?

        init(groupV1Identifier: ObvGroupV1Identifier, searchText: String?, context: NSManagedObjectContext) {
            self.currentSearchText = searchText
            let frc = PersistedContactGroup.getFetchedResultsController(groupV1Identifier: groupV1Identifier, within: context)
            super.init(frc: frc)
        }

        func updateWithSearchText(searchText: String?) {
            frc.managedObjectContext.perform {
                self.currentSearchText = searchText
                Task { [weak self] in
                    do { try await self?.getFetchedObjectsAndYieldModelIfNeeded() } catch { assertionFailure() }
                }
            }
        }

        override func createModel(fetchedObjects: [PersistedContactGroup]) throws -> ListOfMembersWithAddAndRemoveButtonsView.Model {
            guard let groupV1 = fetchedObjects.first else {
                throw ObvError.groupNotFound
            }
            let model: ListOfMembersWithAddAndRemoveButtonsView.Model = try .init(groupV1: groupV1, searchText: currentSearchText)
            return model
        }
        
        enum ObvError: Error {
            case groupNotFound
        }

    }
    
}


extension ListOfMembersWithAddAndRemoveButtonsView.Model {
    
    init(groupV1: PersistedContactGroup, searchText: String?) throws {
        
        let groupIdentifier = try groupV1.obvGroupIdentifier
        let allOtherGroupMembers: [SingleGroupMemberView.Model.Identifier] = try .init(groupV1: groupV1, searchText: searchText)

        self.init(groupIdentifier: .groupV1(groupIdentifier),
                  allOtherGroupMembers: allOtherGroupMembers,
                  isGroupV2UpdateInProgress: false)
        
    }
    
}


extension ListOfMembersWithAddAndRemoveButtonsView.Model {
    
    init(groupV2Identifier: ObvGroupV2Identifier, allOtherGroupMembers: [PersistedGroupV2Member], group: PersistedGroupV2) {

        let allOtherGroupMembers: [SingleGroupMemberView.Model.Identifier] = allOtherGroupMembers
            .map { .objectIDOfPersistedGroupV2Member(groupIdentifier: groupV2Identifier, objectID: $0.objectID) }
        
        self.init(groupIdentifier: .groupV2(groupV2Identifier),
                  allOtherGroupMembers: allOtherGroupMembers,
                  isGroupV2UpdateInProgress: group.updateInProgress)

    }
    
}
