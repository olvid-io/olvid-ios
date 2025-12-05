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
final class SelectUsersToRemoveViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
    
    private var selectUsersToRemoveViewModelStreamManagerForGroupV1StreamManagerForStreamUUID = [UUID: SelectUsersToRemoveViewModelStreamManagerForGroupV1]()
    private var selectUsersToRemoveViewModelStreamManagerForGroupV2StreamManagerForStreamUUID = [UUID: SelectUsersToRemoveViewModelStreamManagerForGroupV2]()
    
}


extension SelectUsersToRemoveViewAppDataSource: SelectUsersToRemoveViewDataSource {
    
    func getAsyncSequenceOfSelectUsersToRemoveViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToRemoveView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, searchText: String?) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.SelectUsersToRemoveView.Model>) {
        switch groupIdentifier {
        case .groupV1(obvGroupV1Identifier: let groupV1Identifier):
            let streamManager = SelectUsersToRemoveViewModelStreamManagerForGroupV1(groupV1Identifier: groupV1Identifier, searchText: searchText, context: backgroundContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.selectUsersToRemoveViewModelStreamManagerForGroupV1StreamManagerForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        case .groupV2(let groupV2Identifier):
            let streamManager = SelectUsersToRemoveViewModelStreamManagerForGroupV2(groupV2Identifier: groupV2Identifier, searchText: searchText, context: backgroundContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.selectUsersToRemoveViewModelStreamManagerForGroupV2StreamManagerForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        }
    }
    
    func filterAsyncSequenceOfSelectUsersToRemoveViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToRemoveView, streamUUID: UUID, searchText: String?) {
        if let streamManager = selectUsersToRemoveViewModelStreamManagerForGroupV1StreamManagerForStreamUUID[streamUUID] {
            streamManager.updateWithSearchText(searchText: searchText)
        }
        if let streamManager = selectUsersToRemoveViewModelStreamManagerForGroupV2StreamManagerForStreamUUID[streamUUID] {
            streamManager.updateWithSearchText(searchText: searchText)
        }
    }
    
    func finishAsyncSequenceOfSelectUsersToRemoveViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToRemoveView, streamUUID: UUID) {
        if let streamManager = selectUsersToRemoveViewModelStreamManagerForGroupV1StreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
        if let streamManager = selectUsersToRemoveViewModelStreamManagerForGroupV2StreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
    }
    
}

extension SelectUsersToRemoveViewAppDataSource {
    
    private final class SelectUsersToRemoveViewModelStreamManagerForGroupV2: ObvDataSourceStreamManagerWithTwoFetchedResultsController<SelectUsersToRemoveView.Model, PersistedGroupV2Member, PersistedGroupV2Member>, @unchecked Sendable {
        
        private let groupV2Identifier: ObvGroupV2Identifier
        
        init(groupV2Identifier: ObvGroupV2Identifier, searchText: String?, context: NSManagedObjectContext) {
            self.groupV2Identifier = groupV2Identifier
            let predicateForAllOtherGroupMembers = PersistedGroupV2Member.getPredicate(groupV2Identifier: groupV2Identifier)
            let predicateForFilteredOtherGroupMembers = PersistedGroupV2Member.getPredicate(groupV2Identifier: groupV2Identifier, searchText: searchText)
            let frcForAllOtherGroupMembers = PersistedGroupV2Member.getFetchedResultsController(predicate: predicateForAllOtherGroupMembers, within: context)
            let frcForFilteredOtherGroupMembers = PersistedGroupV2Member.getFetchedResultsController(predicate: predicateForFilteredOtherGroupMembers, within: context)
            super.init(frc1: frcForAllOtherGroupMembers, frc2: frcForFilteredOtherGroupMembers)
        }
        
        
        override func createModel(fetchedObjects1: [PersistedGroupV2Member], fetchedObjects2: [PersistedGroupV2Member]) throws -> SelectUsersToRemoveView.Model {
            let model: SelectUsersToRemoveView.Model = .init(groupV2Identifier: groupV2Identifier, allOtherGroupMembers: fetchedObjects1, filteredOtherGroupMembers: fetchedObjects2)
            return model
        }
        
        
        func updateWithSearchText(searchText: String?) {
            frc2.managedObjectContext.perform { [weak self] in
                guard let self else { return }
                let predicateForFilteredOtherGroupMembers = PersistedGroupV2Member.getPredicate(groupV2Identifier: groupV2Identifier, searchText: searchText)
                self.frc2.fetchRequest.predicate = predicateForFilteredOtherGroupMembers
                do { try frc2.performFetch() } catch { assertionFailure() }
                Task { [weak self] in do { try await self?.getFetchedObjectsAndYieldModelIfNeeded() } catch { assertionFailure(error.localizedDescription) } }
            }
        }
        
    }
    
}

extension SelectUsersToRemoveViewAppDataSource {
    
    private final class SelectUsersToRemoveViewModelStreamManagerForGroupV1: ObvDataSourceStreamManagerWithOneFetchedResultsController<SelectUsersToRemoveView.Model, PersistedContactGroup>, @unchecked Sendable {
        
        private var currentSearchText: String?
        
        init(groupV1Identifier: ObvGroupV1Identifier, searchText: String?, context: NSManagedObjectContext) {
            let frc = PersistedContactGroup.getFetchedResultsController(groupV1Identifier: groupV1Identifier, within: context)
            self.currentSearchText = searchText
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
        
        override func createModel(fetchedObjects: [PersistedContactGroup]) throws -> SelectUsersToRemoveView.Model {
            guard let groupV1 = fetchedObjects.first else {
                throw ObvError.groupNotFound
            }
            let model: SelectUsersToRemoveView.Model = try .init(groupV1: groupV1, searchText: currentSearchText)
            return model
        }
        
        enum ObvError: Error {
            case groupNotFound
        }
        
    }
    
}


extension [SingleGroupMemberView.Model.Identifier] {
    
    /// Creates a sorted and filtered list of identifiers for `SingleGroupMemberView` from a `PersistedContactGroup`.
    ///
    /// - Parameters:
    ///   - groupV1: The group whose members' identifiers are to be constructed.
    ///
    /// - Returns: A sorted list of identifiers, ordered as follows:
    ///   - `.objectIDOfPersistedContact` for members already in the user's contacts (appearing first).
    ///   - `.objectIDOfPersistedPendingGroupMember` for pending members not yet in the user's contacts (appearing after).
    ///
    /// - Note: If a pending member of a joined group is already a contact, the identifier will be of type `.objectIDOfPersistedContact`.
    init(groupV1: PersistedContactGroup, searchText: String?) throws {
        
        guard let context = groupV1.managedObjectContext else {
            throw SingleGroupMemberViewModelIdentifierFilteredListInitError.noContext
        }
        
        let unfilteredList: [SingleGroupMemberView.Model.Identifier] = try .init(groupV1: groupV1)
        
        var filteredList = [SingleGroupMemberView.Model.Identifier]()
        
        // We know the first elements of the list are `.objectIDOfPersistedContact`, the following are `.objectIDOfPersistedPendingGroupMember`.
        
        // Part 1: We filter the objectIDOfPersistedContact first
        
        do {
            
            let objectIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>] = unfilteredList
                .compactMap { identifier in
                    switch identifier {
                    case .contactIdentifierForExistingGroupForPreviews,
                            .contactIdentifierForCreatingGroupForPreviews,
                            .objectIDOfPersistedGroupV2Member:
                        assertionFailure()
                        return nil
                    case .objectIDOfPersistedPendingGroupMember:
                        return nil // Will be in part2
                    case .objectIDOfPersistedContact(objectID: let objectID, usageContext: _):
                        return TypeSafeManagedObjectID<PersistedObvContactIdentity>(objectID: objectID)
                    }
                }
            
            let filteredObjectIDs = try PersistedObvContactIdentity.filterAll(objectIDs: objectIDs, searchText: searchText, within: context)
            
            let filteredListPart1 = unfilteredList.filter { identifier in
                switch identifier {
                case .contactIdentifierForExistingGroupForPreviews,
                        .contactIdentifierForCreatingGroupForPreviews,
                        .objectIDOfPersistedGroupV2Member:
                    assertionFailure()
                    return false
                case .objectIDOfPersistedPendingGroupMember:
                    return false // Will be in part2
                case .objectIDOfPersistedContact(objectID: let objectID, usageContext: _):
                    return filteredObjectIDs.contains(where: { $0.objectID == objectID })
                }
            }
            
            filteredList += filteredListPart1
            
        }
        
        // Part 2: We filter the objectIDOfPersistedPendingGroupMember
        
        do {
            
            let objectIDs: [TypeSafeManagedObjectID<PersistedPendingGroupMember>] = unfilteredList
                .compactMap { identifier in
                    switch identifier {
                    case .contactIdentifierForExistingGroupForPreviews,
                            .contactIdentifierForCreatingGroupForPreviews,
                            .objectIDOfPersistedGroupV2Member:
                        assertionFailure()
                        return nil
                    case .objectIDOfPersistedPendingGroupMember(objectID: let objectID):
                        return TypeSafeManagedObjectID<PersistedPendingGroupMember>(objectID: objectID)
                    case .objectIDOfPersistedContact:
                        return nil // Was processed as of part 1
                    }
                }

            let filteredObjectIDs = try PersistedPendingGroupMember.filterAll(objectIDs: objectIDs, searchText: searchText, within: context)

            let filteredListPart2 = unfilteredList.filter { identifier in
                switch identifier {
                case .contactIdentifierForExistingGroupForPreviews,
                        .contactIdentifierForCreatingGroupForPreviews,
                        .objectIDOfPersistedGroupV2Member:
                    assertionFailure()
                    return false
                case .objectIDOfPersistedPendingGroupMember(objectID: let objectID):
                    return filteredObjectIDs.contains(where: { $0.objectID == objectID })
                case .objectIDOfPersistedContact(objectID: _, usageContext: _):
                    return false // Was processed as of part 1
                }
            }

            filteredList += filteredListPart2

        }
        
        self = filteredList
        
    }
    
    enum SingleGroupMemberViewModelIdentifierFilteredListInitError: Error {
        case unexpectedIdentifier
        case noContext
    }
    
}

extension SelectUsersToRemoveView.Model {
    
    init(groupV1: PersistedContactGroup, searchText: String?) throws {
        
        let groupIdentifier = try groupV1.obvGroupIdentifier
        let allOtherGroupMembers: [SingleGroupMemberView.Model.Identifier] = try .init(groupV1: groupV1)
        let filteredOtherGroupMembers: [SingleGroupMemberView.Model.Identifier] = try .init(groupV1: groupV1, searchText: searchText)
        
        self.init(groupIdentifier: .groupV1(groupIdentifier),
                  allOtherGroupMembers: allOtherGroupMembers,
                  filteredOtherGroupMembers: filteredOtherGroupMembers)
        
    }
    
}


extension SelectUsersToRemoveView.Model {
    
    init(groupV2Identifier: ObvGroupV2Identifier, allOtherGroupMembers: [PersistedGroupV2Member], filteredOtherGroupMembers: [PersistedGroupV2Member]) {

        let allOtherGroupMembers: [SingleGroupMemberView.Model.Identifier] = allOtherGroupMembers
            .map { .objectIDOfPersistedGroupV2Member(groupIdentifier: groupV2Identifier, objectID: $0.objectID) }
        
        let filteredOtherGroupMembers: [SingleGroupMemberView.Model.Identifier] = filteredOtherGroupMembers
            .map { .objectIDOfPersistedGroupV2Member(groupIdentifier: groupV2Identifier, objectID: $0.objectID) }

        self.init(
            groupIdentifier: .groupV2(groupV2Identifier),
            allOtherGroupMembers: allOtherGroupMembers,
            filteredOtherGroupMembers: filteredOtherGroupMembers)

    }
    
}
