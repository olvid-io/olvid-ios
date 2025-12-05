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

@MainActor
final class SelectUsersToAddViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var selectUsersToAddViewModelStreamManagerForGroupV1ForStreamUUID = [UUID: SelectUsersToAddViewModelStreamManagerForGroupV1]()
    private var selectUsersToAddViewModelStreamManagerForGroupV2ForStreamUUID = [UUID: SelectUsersToAddViewModelStreamManagerForGroupV2]()

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
    
}


extension SelectUsersToAddViewAppDataSource: SelectUsersToAddViewDataSource {

    // This method is called when creating a group V1 or V2. We use the same stream manager in both cases.
    func getAsyncSequenceOfUsersToAddToCreatingGroup(_ view: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddView, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel>) {
        let streamManager = SelectUsersToAddViewModelStreamManagerForGroupV2(mode: .creation(ownedCryptoId: ownedCryptoId), context: backgroundContext)
        let (streamUUID, stream) = try await streamManager.startStream()
        self.selectUsersToAddViewModelStreamManagerForGroupV2ForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }
    
    /// Called when displaying a list of contacts that can be added to a group. We display both one2one and non-one2one contacts. We remove the contacts that are already parts of the group members.
    func getAsyncSequenceOfUsersToAddToExistingGroup(_ view: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel>) {
        switch groupIdentifier {
        case .groupV1(let groupIdentifier):
            let streamManager = SelectUsersToAddViewModelStreamManagerForGroupV1(groupIdentifier: groupIdentifier, context: backgroundContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.selectUsersToAddViewModelStreamManagerForGroupV1ForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        case .groupV2(let groupIdentifier):
            let streamManager = SelectUsersToAddViewModelStreamManagerForGroupV2(mode: .edition(groupIdentifier: groupIdentifier), context: backgroundContext)
            let (streamUUID, stream) = try await streamManager.startStream()
            self.selectUsersToAddViewModelStreamManagerForGroupV2ForStreamUUID[streamUUID] = streamManager
            return (streamUUID, stream)
        }
    }
    
    func filterAsyncSequenceOfUsersToAdd(_ view: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddView.InternalView, streamUUID: UUID, searchText: String?) {
        if let streamManager = selectUsersToAddViewModelStreamManagerForGroupV1ForStreamUUID[streamUUID] {
            streamManager.updateWithSearchText(searchText)
        }
        if let streamManager = selectUsersToAddViewModelStreamManagerForGroupV2ForStreamUUID[streamUUID] {
            streamManager.updateWithSearchText(searchText)
        }
    }
    
    func finishAsyncSequenceOfSelectUsersToAddViewModel(_ view: ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddView, streamUUID: UUID) {
        if let streamManager = selectUsersToAddViewModelStreamManagerForGroupV1ForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
        if let streamManager = selectUsersToAddViewModelStreamManagerForGroupV2ForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
    }
    
}


// MARK: - Stream Manager for SelectUsersToAddViewModel

extension SelectUsersToAddViewAppDataSource {
    
    /// Not used for group creation, only for group V1 **edition**
    private final class SelectUsersToAddViewModelStreamManagerForGroupV1: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel, PersistedObvContactIdentity>, @unchecked Sendable {

        private let groupIdentifier: ObvGroupV1Identifier
        private let textOnEmptySetOfUsers = String(localized: "CHOOSE_THE_USERS_YOU_WANT_TO_ADD_TO_THE_GROUP")

        init(groupIdentifier: ObvGroupV1Identifier, context: NSManagedObjectContext) {
            self.groupIdentifier = groupIdentifier
            let predicate = PersistedObvContactIdentity.getPredicateForAllReachableContactsOfOwnedIdentityButExcludingGroupMembers(groupIdentifier: groupIdentifier, searchText: nil)
            let frc = PersistedObvContactIdentity.getFetchedResultsController(predicate: predicate, within: context)
            super.init(frc: frc)
        }
        
        override func createModel(fetchedObjects: [PersistedObvContactIdentity]) throws -> SelectUsersToAddViewModel {
            let allUserIdentifiers: [ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier] = fetchedObjects
                .map { $0.objectID }
                .map { ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier.objectIDOfPersistedObvContactIdentity(objectID: $0) }
            let model = ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel(textOnEmptySetOfUsers: textOnEmptySetOfUsers,
                                                               allUserIdentifiers: allUserIdentifiers)
            return model
        }
        
        func updateWithSearchText(_ searchText: String?) {
            let newPredicate = PersistedObvContactIdentity.getPredicateForAllReachableContactsOfOwnedIdentityButExcludingGroupMembers(groupIdentifier: groupIdentifier, searchText: nil)
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

extension SelectUsersToAddViewAppDataSource {
    
    /// Note that this stream manager is also used during the creatin of a group v1
    private final class SelectUsersToAddViewModelStreamManagerForGroupV2: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel, PersistedObvContactIdentity>, @unchecked Sendable {
        
        let mode: ObvUIGroupV2.ObvUIGroupV2RouterDataSourceMode
        private let textOnEmptySetOfUsers = String(localized: "CHOOSE_THE_USERS_YOU_WANT_TO_ADD_TO_THE_GROUP")

        init(mode: ObvUIGroupV2.ObvUIGroupV2RouterDataSourceMode, context: NSManagedObjectContext) {
            self.mode = mode
            let frc: NSFetchedResultsController<PersistedObvContactIdentity> // IDs of PersistedObvContactIdentity entities
            switch mode {
            case .creation(let ownedCryptoId):
                frc = PersistedObvContactIdentity.getFetchedResultsControllerForAllReachableContactsOfOwnedIdentity(ownedCryptoId: ownedCryptoId, within: context)
            case .edition(let groupIdentifier):
                frc = PersistedObvContactIdentity.getFetchedResultsControllerForAllReachableContactsOfOwnedIdentityButExcludingGroupMembers(groupIdentifier: groupIdentifier, within: context)
            }
            super.init(frc: frc)
        }
        
        override func createModel(fetchedObjects: [PersistedObvContactIdentity]) throws -> SelectUsersToAddViewModel {
            let allUserIdentifiers: [ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier] = fetchedObjects
                .map { $0.objectID }
                .map { ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel.User.Identifier.objectIDOfPersistedObvContactIdentity(objectID: $0) }
            let model = ObvUIGroupSharedBetweenV1AndV2.SelectUsersToAddViewModel(textOnEmptySetOfUsers: textOnEmptySetOfUsers,
                                                               allUserIdentifiers: allUserIdentifiers)
            return model
        }
        
        func updateWithSearchText(_ searchText: String?) {
            let newPredicate: NSPredicate
            switch mode {
            case .creation(let ownedCryptoId):
                newPredicate = PersistedObvContactIdentity.getPredicateForAllReachableContactsOfOwnedIdentity(ownedCryptoId: ownedCryptoId, searchText: searchText)
            case .edition(let groupIdentifier):
                newPredicate = PersistedObvContactIdentity.getPredicateForAllReachableContactsOfOwnedIdentityButExcludingGroupMembers(groupIdentifier: groupIdentifier, searchText: searchText)
            }
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
