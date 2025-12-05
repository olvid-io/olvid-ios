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
import ObvUIGroupV2
import ObvUIGroupSharedBetweenV1AndV2
import ObvTypes
import ObvAppTypes
import ObvUICoreData
import ObvDesignSystem
import OlvidUtils


/// This App Data Source is used by multiple views, including
/// - `ObvUIGroupSharedBetweenV1AndV2.ListOfGroupMembersView`
/// - `ObvUIGroupV2.FullListOfGroupMembersViewDataSource`
@MainActor
final class ListOfGroupMembersViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var groupLightweightModelStreamManagerForStreamUUID = [UUID: GroupLightweightModelStreamManager]()
    private var listOfSingleGroupMemberViewModelForGroupV1StreamManagerForStreamUUID = [UUID: ListOfSingleGroupMemberViewModelForGroupV1StreamManager]()
    private var listOfSingleGroupMemberViewModelForGroupV2StreamManagerForStreamUUID = [UUID: ListOfSingleGroupMemberViewModelForGroupV2StreamManager]()
    private var listOfSingleGroupMemberViewModelStreamManagerForGroupCreationForStreamUUID = [UUID: ListOfSingleGroupMemberViewModelStreamManagerForGroupCreation]()

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
    
    enum ObvError: Error {
        case couldNotFetchGroup
        case unexpectedIdentifier
    }
    
}


extension ListOfGroupMembersViewAppDataSource: ListOfGroupMembersViewDataSource {
    
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfGroupMembersView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel>) {
        return try await self.getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(groupIdentifier: groupIdentifier, restrictToAdmins: false)
    }
    
    func filterAsyncSequenceOfListOfSingleGroupMemberViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfGroupMembersView, streamUUID: UUID, searchText: String?) {
        filterAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: streamUUID, searchText: searchText)
    }
    
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.ListOfGroupMembersView, streamUUID: UUID) {
        finishAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: streamUUID)
    }
    
}


extension ListOfGroupMembersViewAppDataSource: FullListOfGroupMembersViewDataSource {
    
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(_ view: FullListOfGroupMembersView, creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId, userIdentifiersOfAddedUsers: [SelectUsersToAddViewModel.User.Identifier]) async throws -> (streamUUID: UUID, stream: AsyncStream<ListOfSingleGroupMemberViewModel>) {
        let userIdentifiersOfAddedUsers: [TypeSafeManagedObjectID<PersistedObvContactIdentity>] = try userIdentifiersOfAddedUsers.map { identifier in
            switch identifier {
            case .contactIdentifier:
                assertionFailure("Only expected in previews")
                throw ObvError.unexpectedIdentifier
            case .objectIDOfPersistedObvContactIdentity(let objectID):
                return .init(objectID: objectID)
            }
        }
        let streamManager = ListOfSingleGroupMemberViewModelStreamManagerForGroupCreation(
            ownedCryptoId: ownedCryptoId,
            userIdentifiersOfAddedUsers: Set(userIdentifiersOfAddedUsers),
            context: backgroundContext)
        
        let (streamUUID, stream) = try await streamManager.startStream()
        self.listOfSingleGroupMemberViewModelStreamManagerForGroupCreationForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }
    
    func filterAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(_ view: ObvUIGroupV2.FullListOfGroupMembersView.InternalView, streamUUID: UUID, userIdentifiersOfAddedUsers: [ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier], searchText: String?) {
        guard let streamManager = listOfSingleGroupMemberViewModelStreamManagerForGroupCreationForStreamUUID[streamUUID] else { return }
        do {
            let userIdentifiersOfAddedUsers: [TypeSafeManagedObjectID<PersistedObvContactIdentity>] = try userIdentifiersOfAddedUsers.map { identifier in
                switch identifier {
                case .contactIdentifier:
                    assertionFailure("Only expected in previews")
                    throw ObvError.unexpectedIdentifier
                case .objectIDOfPersistedObvContactIdentity(let objectID):
                    return .init(objectID: objectID)
                }
            }
            streamManager.updateWithSearchText(searchText, userIdentifiersOfAddedUsers: Set(userIdentifiersOfAddedUsers))
        } catch {
            assertionFailure()
        }
    }
    
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModelForCreatingGroup(_ view: ObvUIGroupV2.FullListOfGroupMembersView, streamUUID: UUID) {
        guard let streamManager = listOfSingleGroupMemberViewModelStreamManagerForGroupCreationForStreamUUID.removeValue(forKey: streamUUID) else { return }
        streamManager.finishStream()
    }

    func getAsyncSequenceOfListOfSingleGroupAdminsMemberViewModelForExistingGroup(_ view: ObvUIGroupV2.FullListOfGroupMembersView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel>) {
        return try await self.getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(groupIdentifier: .groupV2(groupIdentifier), restrictToAdmins: true)
    }
    
    func finishAsyncSequenceOfListOfSingleGroupAdminsMemberViewModel(_ view: ObvUIGroupV2.FullListOfGroupMembersView, streamUUID: UUID) {
        finishAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: streamUUID)
    }
    
    func getAsyncSequenceOfGroupLightweightModelForExistingGroup(_ view: ObvUIGroupV2.FullListOfGroupMembersView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.ObvGroupLightweightModel>) {
        return try await self.getAsyncSequenceOfObvGroupLightweightModel(groupIdentifier: groupIdentifier)
    }
    
    func finishAsyncSequenceOfGroupLightweightModelForExistingGroup(_ view: ObvUIGroupV2.FullListOfGroupMembersView, groupIdentifier: ObvTypes.ObvGroupV2Identifier, streamUUID: UUID) {
        self.finishAsyncSequenceOfObvGroupLightweightModel(groupIdentifier: groupIdentifier, streamUUID: streamUUID)
    }
    
    func getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(_ view: ObvUIGroupV2.FullListOfGroupMembersView, groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel>) {
        return try await self.getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(groupIdentifier: .groupV2(groupIdentifier), restrictToAdmins: false)
    }
    
    func filterAsyncSequenceOfListOfSingleGroupMemberViewModel(_ view: ObvUIGroupV2.FullListOfGroupMembersView.InternalView, streamUUID: UUID, searchText: String?) {
        filterAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: streamUUID, searchText: searchText)
    }
    
    func finishAsyncSequenceOfListOfSingleGroupMemberViewModel(_ view: ObvUIGroupV2.FullListOfGroupMembersView, streamUUID: UUID) {
        finishAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: streamUUID)
    }
    
}


extension ListOfGroupMembersViewAppDataSource {
    
    private func getAsyncSequenceOfObvGroupLightweightModel(groupIdentifier: ObvTypes.ObvGroupV2Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupV2.ObvGroupLightweightModel>) {
        let streamManager = GroupLightweightModelStreamManager(groupV2Identifier: groupIdentifier, context: backgroundContext)
        let (streamUUID, stream) = try await streamManager.startStream()
        self.groupLightweightModelStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }

    private func finishAsyncSequenceOfObvGroupLightweightModel(groupIdentifier: ObvTypes.ObvGroupV2Identifier, streamUUID: UUID) {
        guard let streamManager = groupLightweightModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        streamManager.finishStream()
    }
    
}


extension ListOfGroupMembersViewAppDataSource {
    
    private func getAsyncSequenceOfListOfSingleGroupMemberViewModelForExistingGroup(groupIdentifier: ObvAppTypes.ObvGroupIdentifier, restrictToAdmins: Bool) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel>) {
        switch groupIdentifier {
        case .groupV1(let groupIdentifier):
            assert(!restrictToAdmins)
            let streamManager = ListOfSingleGroupMemberViewModelForGroupV1StreamManager(groupIdentifier: groupIdentifier, context: backgroundContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.listOfSingleGroupMemberViewModelForGroupV1StreamManagerForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        case .groupV2(let groupIdentifier):
            let streamManager = ListOfSingleGroupMemberViewModelForGroupV2StreamManager(groupIdentifier: groupIdentifier, restrictToAdmins: restrictToAdmins, context: backgroundContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.listOfSingleGroupMemberViewModelForGroupV2StreamManagerForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        }
    }
    
    private func filterAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: UUID, searchText: String?) {
        if let streamManager = listOfSingleGroupMemberViewModelForGroupV1StreamManagerForStreamUUID[streamUUID] {
            streamManager.updateWithSearchText(searchText)
        }
        if let streamManager = listOfSingleGroupMemberViewModelForGroupV2StreamManagerForStreamUUID[streamUUID] {
            streamManager.updateWithSearchText(searchText)
        }
    }
    
    private func finishAsyncSequenceOfListOfSingleGroupMemberViewModel(streamUUID: UUID) {
        if let streamManager = listOfSingleGroupMemberViewModelForGroupV1StreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
        if let streamManager = listOfSingleGroupMemberViewModelForGroupV2StreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
    }

}


// MARK: - Stream Manager for GroupLightweightModel

extension ListOfGroupMembersViewAppDataSource {

    private final class GroupLightweightModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvUIGroupV2.ObvGroupLightweightModel, PersistedGroupV2>, @unchecked Sendable {
        
        init(groupV2Identifier: ObvGroupV2Identifier, context: NSManagedObjectContext) {
            let frc = PersistedGroupV2.getFetchedResultsController(groupV2Identifier: groupV2Identifier, within: context)
            super.init(frc: frc)
        }

        override func createModel(fetchedObjects: [PersistedGroupV2]) throws -> ObvGroupLightweightModel {
            assert(fetchedObjects.count <= 1)
            guard let persistedGroup = fetchedObjects.first else {
                // This happens when the group gets deleted (or we are removed from the group) while in the view
                throw ObvError.couldNotFetchGroup
            }
            let model = try ObvUIGroupV2.ObvGroupLightweightModel(with: persistedGroup)
            return model
        }
        
    }

}


// MARK: - Stream Manager for ListOfSingleGroupMemberViewModel (during a group creation)

extension ListOfGroupMembersViewAppDataSource {
    
    private final class ListOfSingleGroupMemberViewModelStreamManagerForGroupCreation: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel, PersistedObvContactIdentity>, @unchecked Sendable {
        
        let ownedCryptoId: ObvCryptoId
        var userIdentifiersOfAddedUsers: Set<TypeSafeManagedObjectID<PersistedObvContactIdentity>>
        let unfilteredFetchRequest: NSFetchRequest<PersistedObvContactIdentity>
        var searchText: String?
        
        init(ownedCryptoId: ObvCryptoId, userIdentifiersOfAddedUsers: Set<TypeSafeManagedObjectID<PersistedObvContactIdentity>>, context: NSManagedObjectContext) {
            self.searchText = nil
            self.ownedCryptoId = ownedCryptoId
            self.userIdentifiersOfAddedUsers = userIdentifiersOfAddedUsers
            self.unfilteredFetchRequest = PersistedObvContactIdentity.getFetchRequestForAllContactsOfOwnedIdentity(with: ownedCryptoId, predicate: NSPredicate(value: true), whereOneToOneStatusIs: .any)
            let frc = NSFetchedResultsController(fetchRequest: unfilteredFetchRequest, managedObjectContext: context, sectionNameKeyPath: nil, cacheName: nil)
            super.init(frc: frc)
        }
        
        func updateWithSearchText(_ newSearchText: String?, userIdentifiersOfAddedUsers: Set<TypeSafeManagedObjectID<PersistedObvContactIdentity>>) {
            frc.managedObjectContext.perform {
                self.searchText = newSearchText?.trimmingCharacters(in: .whitespacesAndNewlines).mapToNilIfZeroLength()
                self.userIdentifiersOfAddedUsers = userIdentifiersOfAddedUsers
                Task {
                    do {
                        try await super.getFetchedObjectsAndYieldModelIfNeeded()
                    } catch {
                        assertionFailure()
                    }
                }
            }
        }
        
        override func createModel(fetchedObjects: [PersistedObvContactIdentity]) throws -> ListOfSingleGroupMemberViewModel {
            
            // The fetchedObjects contain **all** the contacts of the owned identity. We restrict
            // to the contacts indicated in userIdentifiersOfAddedUsers
            
            let addUsersObjectIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>] = fetchedObjects
                .filter { fetchedObject in
                    userIdentifiersOfAddedUsers.contains(where: { $0 == fetchedObject.typedObjectID })
                }
                .map {
                    $0.typedObjectID
                }
            
            let searchedForObjectIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>] = try PersistedObvContactIdentity.filterAll(objectIDs: addUsersObjectIDs, searchText: searchText, within: frc.managedObjectContext)
            
//            let contactIdentifiers: [ObvContactIdentifier] = searchedForObjectIDs.compactMap { objectID in
//                guard let object = fetchedObjects.first(where: { $0.typedObjectID == objectID }) else {
//                    assertionFailure()
//                    return nil
//                }
//                do {
//                    return try object.obvContactIdentifier
//                } catch {
//                    assertionFailure()
//                    return nil
//                }
//            }
            
            let otherGroupMembers: [SingleGroupMemberView.Model.Identifier] = searchedForObjectIDs.map {
                .objectIDOfPersistedContact(objectID: $0.objectID, usageContext: .groupCreation)
            }
            
            let model = ListOfSingleGroupMemberViewModel(otherGroupMembers: otherGroupMembers)
            
            return model
            
        }
        
    }
    
}

// MARK: - Stream Manager for ListOfSingleGroupMemberViewModel (during a group V1 edition)

extension ListOfGroupMembersViewAppDataSource {
    
    private final class ListOfSingleGroupMemberViewModelForGroupV1StreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel, PersistedContactGroup>, @unchecked Sendable {
        
        private let groupIdentifier: ObvGroupV1Identifier
        private var searchText: String? = nil
        
        init(groupIdentifier: ObvGroupV1Identifier, context: NSManagedObjectContext) {
            self.groupIdentifier = groupIdentifier
            let frc = PersistedContactGroup.getFetchedResultsController(groupV1Identifier: groupIdentifier, within: context)
            super.init(frc: frc)
        }
        
        override func createModel(fetchedObjects: [PersistedContactGroup]) throws -> ListOfSingleGroupMemberViewModel {
            assert(fetchedObjects.count <= 1)
            guard let groupV1 = fetchedObjects.first else {
                throw ObvError.couldNotFetchGroup
            }
            
            let otherGroupMembers: [SingleGroupMemberView.Model.Identifier] = try .init(groupV1: groupV1)
            
            let model = ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel(otherGroupMembers: otherGroupMembers)
            return model
            
        }
        
        
        func updateWithSearchText(_ newSearchText: String?) {
            frc.managedObjectContext.perform { [weak self] in
                guard let self else { return }
                guard self.searchText != newSearchText else { return }
                self.searchText = newSearchText
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await getFetchedObjectsAndYieldModelIfNeeded()
                    } catch {
                        assertionFailure()
                    }
                }
            }
        }
        
    }
    
    private final class ListOfSingleGroupMemberViewModelForGroupV2StreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel, PersistedGroupV2Member>, @unchecked Sendable {
        
        let groupIdentifier: ObvGroupV2Identifier
        let initialPredicate: NSPredicate

        init(groupIdentifier: ObvGroupV2Identifier, restrictToAdmins: Bool, context: NSManagedObjectContext) {
            self.groupIdentifier = groupIdentifier
            let frc: NSFetchedResultsController<PersistedGroupV2Member>
            if restrictToAdmins {
                frc = PersistedGroupV2Member.getFetchedResultsControllerForAdmins(groupV2Identifier: groupIdentifier, within: context)
            } else {
                frc = PersistedGroupV2Member.getFetchedResultsController(groupV2Identifier: groupIdentifier, within: context)
            }
            self.initialPredicate = frc.fetchRequest.predicate ?? NSPredicate(value: true)
            super.init(frc: frc)
        }
        
        override func createModel(fetchedObjects: [PersistedGroupV2Member]) throws -> ListOfSingleGroupMemberViewModel {
            let otherGroupMembers: [SingleGroupMemberView.Model.Identifier] = fetchedObjects
                .map(\.objectID)
                .map { SingleGroupMemberView.Model.Identifier.objectIDOfPersistedGroupV2Member(groupIdentifier: self.groupIdentifier, objectID: $0) }
            let model = ObvUIGroupSharedBetweenV1AndV2.ListOfSingleGroupMemberViewModel(otherGroupMembers: otherGroupMembers)
            return model
        }
     
        func updateWithSearchText(_ searchText: String?) {
            let searchPredicate = PersistedGroupV2Member.getSearchPredicate(searchText)
            let newPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                self.initialPredicate,
                searchPredicate,
            ])
            self.frc.fetchRequest.predicate = newPredicate
            do {
                try frc.performFetch()
                Task {
                    do {
                        try await getFetchedObjectsAndYieldModelIfNeeded()
                    } catch {
                        assertionFailure(error.localizedDescription)
                    }
                }
            } catch {
                assertionFailure()
            }
        }

    }
        
}


// MARK: - GroupLightweightModel from PersistedGroupV2

extension ObvGroupLightweightModel {
    
    init(with persistedGroup: PersistedGroupV2) throws {
        self.init(ownedIdentityIsAdmin: persistedGroup.ownedIdentityIsAdmin,
                  groupType: persistedGroup.getOrInferGroupType(),
                  updateInProgressDuringGroupEdition: persistedGroup.updateInProgress,
                  isKeycloakManaged: persistedGroup.keycloakManaged)
    }
    
}


extension [SingleGroupMemberView.Model.Identifier] {
    
    /// Creates a sorted list of identifiers for `SingleGroupMemberView` from a `PersistedContactGroup`.
    ///
    /// - Parameters:
    ///   - groupV1: The group whose members' identifiers are to be constructed.
    ///
    /// - Returns: A sorted list of identifiers, ordered as follows:
    ///   - `.objectIDOfPersistedContact` for members already in the user's contacts (appearing first).
    ///   - `.objectIDOfPersistedPendingGroupMember` for pending members not yet in the user's contacts (appearing after).
    ///
    /// - Note: If a pending member of a joined group is already a contact, the identifier will be of type `.objectIDOfPersistedContact`.
    init(groupV1: PersistedContactGroup) throws {
        
        let groupV1Identifier = try groupV1.obvGroupIdentifier
        
        // The list will fist show the members that are contacts (pending or not, it does not matter)
        // It will then show the list of pending members that are not yet contacts.

        var otherGroupMembers = [SingleGroupMemberView.Model.Identifier]()

        // We start with the list of contacts

        let sortedContacts = groupV1.contactIdentities.sorted(by: \.sortDisplayName)
        for contact in sortedContacts {
            otherGroupMembers.append(.objectIDOfPersistedContact(
                objectID: contact.objectID,
                usageContext: .groupV1Display(groupV1Identifier: groupV1Identifier)))
        }

        let cryptoIdsAlreadyIncluded = sortedContacts.map { $0.cryptoId }

        // We continue with the remaining pending members

        let sortedPendingMembers = groupV1.pendingMembers.sorted(by: \.fullDisplayName)
        for pendingMember in sortedPendingMembers {
            guard !cryptoIdsAlreadyIncluded.contains(where: { $0 == pendingMember.cryptoId }) else { continue }
            guard try pendingMember.ownedCryptoId == groupV1Identifier.ownedCryptoId else { assertionFailure(); throw SingleGroupMemberViewModelIdentifierListInitError.unexpectedIdentifier }
            otherGroupMembers.append(.objectIDOfPersistedPendingGroupMember(objectID: pendingMember.objectID))
        }

        self = otherGroupMembers
        
    }
    
    enum SingleGroupMemberViewModelIdentifierListInitError: Error {
        case unexpectedIdentifier
    }
    
}

