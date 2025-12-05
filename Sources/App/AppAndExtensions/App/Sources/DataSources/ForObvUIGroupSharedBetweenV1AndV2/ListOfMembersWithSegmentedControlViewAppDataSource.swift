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
import ObvUIGroupSharedBetweenV1AndV2
import ObvTypes
import ObvAppTypes
import ObvUICoreData
import ObvDesignSystem
import OlvidUtils

@MainActor
final class ListOfMembersWithSegmentedControlViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
 
    private var listOfMembersWithSegmentedControlViewModelStreamManagerForGroupV1ForStreamUUID = [UUID: ListOfMembersWithSegmentedControlViewModelStreamManagerForGroupV1]()
    private var listOfMembersWithSegmentedControlViewModelStreamManagerForGroupV2ForStreamUUID = [UUID: ListOfMembersWithSegmentedControlViewModelStreamManagerForGroupV2]()
    
}


extension ListOfMembersWithSegmentedControlViewAppDataSource: ListOfMembersWithSegmentedControlViewDataSource {
    
    func getAsyncSequenceOfListOfMembersWithSegmentedControlViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfMembersWithSegmentedControlView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, searchText: String?) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.ListOfMembersWithSegmentedControlView.Model>) {
        switch groupIdentifier {
        case .groupV1(let groupV1Identifier):
            let streamManager = ListOfMembersWithSegmentedControlViewModelStreamManagerForGroupV1(groupV1Identifier: groupV1Identifier, searchText: searchText, context: backgroundContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.listOfMembersWithSegmentedControlViewModelStreamManagerForGroupV1ForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        case .groupV2(let groupV2Identifier):
            let streamManager = ListOfMembersWithSegmentedControlViewModelStreamManagerForGroupV2(groupV2Identifier: groupV2Identifier, searchText: searchText, context: backgroundContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.listOfMembersWithSegmentedControlViewModelStreamManagerForGroupV2ForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        }
    }
    
    func filterAsyncSequenceOfListOfMembersWithSegmentedControlViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfMembersWithSegmentedControlView, streamUUID: UUID, searchText: String?) {
        if let streamManager = listOfMembersWithSegmentedControlViewModelStreamManagerForGroupV1ForStreamUUID[streamUUID] {
            streamManager.updateWithSearchText(searchText: searchText)
        }
        if let streamManager = listOfMembersWithSegmentedControlViewModelStreamManagerForGroupV2ForStreamUUID[streamUUID] {
            streamManager.updateWithSearchText(searchText: searchText)
        }
    }
    
    func finishAsyncSequenceOfListOfMembersWithSegmentedControlViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfMembersWithSegmentedControlView, streamUUID: UUID) {
        if let streamManager = listOfMembersWithSegmentedControlViewModelStreamManagerForGroupV1ForStreamUUID[streamUUID] {
            streamManager.finishStream()
        }
        if let streamManager = listOfMembersWithSegmentedControlViewModelStreamManagerForGroupV2ForStreamUUID[streamUUID] {
            streamManager.finishStream()
        }
    }
    
}


extension ListOfMembersWithSegmentedControlViewAppDataSource {
    
    private final class ListOfMembersWithSegmentedControlViewModelStreamManagerForGroupV2: ObvDataSourceStreamManagerWithThreeFetchedResultsController<ListOfMembersWithSegmentedControlView.Model, PersistedGroupV2Member, PersistedGroupV2Member, PersistedGroupV2>, @unchecked Sendable {
        
        private let groupV2Identifier: ObvGroupV2Identifier
        private var currentSearchText: String?

        init(groupV2Identifier: ObvGroupV2Identifier, searchText: String?, context: NSManagedObjectContext) {
            self.groupV2Identifier = groupV2Identifier
            self.currentSearchText = searchText
            let predicateForAllOtherGroupMembers = PersistedGroupV2Member.getPredicate(groupV2Identifier: groupV2Identifier, restrictToAdmins: false, searchText: searchText)
            let predicateForAllOtherGroupAdmins = PersistedGroupV2Member.getPredicate(groupV2Identifier: groupV2Identifier, restrictToAdmins: true, searchText: searchText)
            let frcForAllOtherGroupMembers = PersistedGroupV2Member.getFetchedResultsController(predicate: predicateForAllOtherGroupMembers, within: context)
            let frcForAllOtherGroupAdmins = PersistedGroupV2Member.getFetchedResultsController(predicate: predicateForAllOtherGroupAdmins, within: context)
            let frcForGroup = PersistedGroupV2.getFetchedResultsController(groupV2Identifier: groupV2Identifier, within: context)
            super.init(frc1: frcForAllOtherGroupMembers, frc2: frcForAllOtherGroupAdmins, frc3: frcForGroup)
        }

        override func createModel(fetchedObjects1: [PersistedGroupV2Member], fetchedObjects2: [PersistedGroupV2Member], fetchedObjects3: [PersistedGroupV2]) throws -> ListOfMembersWithSegmentedControlView.Model {
            assert(fetchedObjects3.count <= 1)
            guard let group = fetchedObjects3.first else {
                throw ObvError.couldNotFindGroup
            }
            let model: ListOfMembersWithSegmentedControlView.Model = .init(
                groupV2Identifier: groupV2Identifier,
                allOtherGroupMembers: fetchedObjects1,
                allOtherGroupAdmins: fetchedObjects2,
                group: group)
            return model
        }
        
        func updateWithSearchText(searchText: String?) {
            frc1.managedObjectContext.perform { [weak self] in
                guard let self else { return }
                let predicateForAllOtherGroupMembers = PersistedGroupV2Member.getPredicate(groupV2Identifier: groupV2Identifier, restrictToAdmins: false, searchText: searchText)
                let predicateForAllOtherGroupAdmins = PersistedGroupV2Member.getPredicate(groupV2Identifier: groupV2Identifier, restrictToAdmins: true, searchText: searchText)
                self.frc1.fetchRequest.predicate = predicateForAllOtherGroupMembers
                self.frc2.fetchRequest.predicate = predicateForAllOtherGroupAdmins
                do {
                    try frc1.performFetch()
                    try frc2.performFetch()
                } catch { assertionFailure() }
                Task { [weak self] in do { try await self?.getFetchedObjectsAndYieldModelIfNeeded() } catch { assertionFailure(error.localizedDescription) } }
            }
        }

        enum ObvError: Error {
            case couldNotFindGroup
        }

    }
    
}


extension ListOfMembersWithSegmentedControlViewAppDataSource {
    
    private final class ListOfMembersWithSegmentedControlViewModelStreamManagerForGroupV1: ObvDataSourceStreamManagerWithOneFetchedResultsController<ListOfMembersWithSegmentedControlView.Model, PersistedContactGroup>, @unchecked Sendable {
        
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

        override func createModel(fetchedObjects: [PersistedContactGroup]) throws -> ListOfMembersWithSegmentedControlView.Model {
            guard let groupV1 = fetchedObjects.first else {
                throw ObvError.groupNotFound
            }
            let model: ListOfMembersWithSegmentedControlView.Model = try .init(groupV1: groupV1, searchText: currentSearchText)
            return model
        }
        
        enum ObvError: Error {
            case groupNotFound
        }
        
    }
    
}


extension ListOfMembersWithSegmentedControlView.Model {
    
    init(groupV1: PersistedContactGroup, searchText: String?) throws {
        
        let groupIdentifier = try groupV1.obvGroupIdentifier
        let allOtherGroupMembers: [SingleGroupMemberView.Model.Identifier] = try .init(groupV1: groupV1, searchText: searchText)

        let allOtherGroupAdmins: [SingleGroupMemberView.Model.Identifier]
        let isOwnedIdentityAnAdmin: Bool
        switch groupV1.category {
        case .owned:
            allOtherGroupAdmins = []
            isOwnedIdentityAnAdmin = true
        case .joined:
            guard let owner = (groupV1 as? PersistedContactGroupJoined)?.owner else {
                assertionFailure()
                throw ListOfMembersWithSegmentedControlViewModelInitError.couldNotFindGroupOwner
            }
            let adminIdentifier: SingleGroupMemberView.Model.Identifier = .objectIDOfPersistedContact(
                objectID: owner.objectID,
                usageContext: .groupV1Display(groupV1Identifier: groupIdentifier))
            allOtherGroupAdmins = [adminIdentifier]
            isOwnedIdentityAnAdmin = false
        }
        
        self.init(groupIdentifier: .groupV1(groupIdentifier),
                  allOtherGroupMembers: allOtherGroupMembers,
                  allOtherGroupAdmins: allOtherGroupAdmins,
                  isGroupV2UpdateInProgress: false,
                  isOwnedIdentityAnAdmin: isOwnedIdentityAnAdmin)
                
    }
 
    enum ListOfMembersWithSegmentedControlViewModelInitError: Error {
        case couldNotFindGroupOwner
    }
    
}


extension ListOfMembersWithSegmentedControlView.Model {
    
    init(groupV2Identifier: ObvGroupV2Identifier, allOtherGroupMembers: [PersistedGroupV2Member], allOtherGroupAdmins: [PersistedGroupV2Member], group: PersistedGroupV2) {
        
        let allOtherGroupMembers: [SingleGroupMemberView.Model.Identifier] = allOtherGroupMembers
            .map { .objectIDOfPersistedGroupV2Member(groupIdentifier: groupV2Identifier, objectID: $0.objectID) }

        let allOtherGroupAdmins: [SingleGroupMemberView.Model.Identifier] = allOtherGroupAdmins
            .map { .objectIDOfPersistedGroupV2Member(groupIdentifier: groupV2Identifier, objectID: $0.objectID) }
        
        self.init(groupIdentifier: .groupV2(groupV2Identifier),
                  allOtherGroupMembers: allOtherGroupMembers,
                  allOtherGroupAdmins: allOtherGroupAdmins,
                  isGroupV2UpdateInProgress: group.updateInProgress,
                  isOwnedIdentityAnAdmin: group.ownedIdentityIsAdmin)
        
    }
    
}
