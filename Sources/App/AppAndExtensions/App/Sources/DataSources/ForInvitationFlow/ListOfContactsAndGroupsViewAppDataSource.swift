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
import OSLog
import ObvInvitationFlow
import ObvUICoreData
import ObvTypes
import OlvidUtils
import ObvKeycloakManager
import ObvDesignSystem
import ObvCells
import ObvAppTypes
import ObvAppCoreConstants
import ObvSettings


@MainActor
final class ListOfContactsAndGroupsViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ListOfContactsAndGroupsViewAppDataSource")

    // Stream managers providing the models for the 3 lists, each list corresponding to a tab of the main view of the ObvInvitationFlow
    private var invitationContactsListViewModelStreamManagerForStreamUUID = [UUID: InvitationContactsListViewModelStreamManager]()
    private var invitationFlowGroupListViewModelStreamManagerForStreamUUID = [UUID: InvitationFlowGroupListViewModelStreamManager]()
    private var contactsListViewModelStreamManagerForStreamUUID = [UUID: ContactsListViewModelStreamManager]()

    // Stream managers providing the models for the cells within the lists
    private var contactListCellViewModelStreamManagerForStreamUUID = [UUID: ContactListCellViewModelStreamManager]()

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
    
}


// MARK: - Implementing ObvInvitationContactsListViewDataSource

extension ListOfContactsAndGroupsViewAppDataSource: ListOfContactsAndGroupsViewDataSource {
    
    func getAsyncStreamOfInvitationKeycloakContactsListViewModel(_ view: ObvInvitationFlow.ListOfContactsAndGroupsView.ListOfDirectoryContactsView, ownedCryptoId: ObvTypes.ObvCryptoId, initialSearchStatus: ObvInvitationFlow.InvitationContactsListViewModel.SearchStatus) throws -> (streamUUID: UUID, stream: AsyncStream<ObvInvitationFlow.InvitationKeycloakContactsListViewModel>) {
        let manager = InvitationContactsListViewModelStreamManager(ownedCryptoId: ownedCryptoId, initialSearchStatus: initialSearchStatus)
        invitationContactsListViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        do {
            return try manager.startStream()
        } catch {
            Self.logger.fault("🔤 Could not start stream: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
    
    func filterAsyncStreamOfInvitationKeycloakContactsListViewModel(_ view: ObvInvitationFlow.ListOfContactsAndGroupsView.ListOfDirectoryContactsView, streamUUID: UUID, searchStatus: ObvInvitationFlow.InvitationContactsListViewModel.SearchStatus) {
        guard let manager = invitationContactsListViewModelStreamManagerForStreamUUID[streamUUID] else { return }
        manager.updateWithSearchText(searchStatus: searchStatus)
    }
    
    func finishAsyncStreamOfInvitationKeycloakContactsListViewModel(_ view: ObvInvitationFlow.ListOfContactsAndGroupsView.ListOfDirectoryContactsView, streamUUID: UUID) {
        guard let manager = invitationContactsListViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
    func getAsyncStreamOfInvitationFlowGroupListViewModel(_ view: ObvInvitationFlow.ListOfContactsAndGroupsView.ListOfGroupsView, ownedCryptoId: ObvTypes.ObvCryptoId, initialSearchStatus: ObvInvitationFlow.InvitationFlowGroupListViewModel.SearchStatus) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvInvitationFlow.InvitationFlowGroupListViewModel>) {
        let manager = InvitationFlowGroupListViewModelStreamManager(ownedCryptoId: ownedCryptoId, initialSearchStatus: initialSearchStatus, context: backgroundContext)
        invitationFlowGroupListViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func filterAsyncStreamOfInvitationFlowGroupListViewModel(_ view: ObvInvitationFlow.ListOfContactsAndGroupsView.ListOfGroupsView, streamUUID: UUID, searchStatus: ObvInvitationFlow.InvitationFlowGroupListViewModel.SearchStatus) {
        guard let manager = invitationFlowGroupListViewModelStreamManagerForStreamUUID[streamUUID] else { return }
        manager.updateWithSearchText(searchStatus: searchStatus, doPerformFetch: true)
    }
    
    func finishAsyncStreamOfInvitationFlowGroupListViewModel(_ view: ObvInvitationFlow.ListOfContactsAndGroupsView.ListOfGroupsView, streamUUID: UUID) {
        guard let manager = invitationFlowGroupListViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
    func getAsyncStreamOfInvitationContactsListViewModel(_ view: ListOfContactsAndGroupsView.ListOfLocalContactsView, ownedCryptoId: ObvCryptoId, initialSearchStatus: InvitationContactsListViewModel.SearchStatus) async throws -> (streamUUID: UUID, stream: AsyncStream<InvitationContactsListViewModel>) {
        let manager = ContactsListViewModelStreamManager(currentOwnedCryptoId: ownedCryptoId, initialSearchStatus: initialSearchStatus, context: backgroundContext)
        contactsListViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfInvitationContactsListViewModel(_ view: ObvInvitationFlow.ListOfContactsAndGroupsView.ListOfLocalContactsView, streamUUID: UUID) {
        guard let manager = contactsListViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
    func filterAsyncSequenceOfInvitationContactsListViewModel(_ view: ObvInvitationFlow.ListOfContactsAndGroupsView.ListOfLocalContactsView, streamUUID: UUID, searchStatus: ObvInvitationFlow.InvitationContactsListViewModel.SearchStatus) {
        guard let manager = contactsListViewModelStreamManagerForStreamUUID[streamUUID] else { return }
        manager.updateWithSearchText(searchStatus: searchStatus, doPerformFetch: true)
    }
    
    func getInitialObvContactCellViewModel(contactIdentifier: ObvInvitationFlow.InvitationContactsListViewModel.ContactIdentifier) -> ObvInvitationFlow.InvitationContactsListCellView.Model? {
        guard let contactObjectID = contactIdentifier.objectID else { assertionFailure(); return nil }
        guard let persistedContactIdentity = try? PersistedObvContactIdentity.get(objectID: contactObjectID, within: viewContext) else { return nil }
        let model = InvitationContactsListCellView.Model(persistedContactIdentity: persistedContactIdentity)
        return model
    }
    
    func getAsyncStreamOfObvContactCellViewModel(_ view: ObvInvitationFlow.InvitationContactsListCellView, contactIdentifier: ObvInvitationFlow.InvitationContactsListViewModel.ContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvInvitationFlow.InvitationContactsListCellView.Model>) {
        let manager = try ContactListCellViewModelStreamManager(contactIdentifier: contactIdentifier, context: backgroundContext)
        contactListCellViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfObvContactCellViewModel(_ view: ObvInvitationFlow.InvitationContactsListCellView, streamUUID: UUID) {
        guard let manager = contactListCellViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
    
    /// Called for a keycloak user. If this user is already a contact, we return an appropriate model.
    func getInvitationContactsListCellViewModelForKeycloakUser(_ view: InvitationContactsListCellView, ownedCryptoId: ObvCryptoId, keycloakUserDetails: ObvKeycloakUserDetails) async -> InvitationContactsListCellView.Model? {
        let backgroundContext = self.backgroundContext
        return await withCheckedContinuation { (continuation: CheckedContinuation<InvitationContactsListCellView.Model?, Never>) in
            backgroundContext.perform {
                do {
                    guard let userIdentity = keycloakUserDetails.identity else {
                        return continuation.resume(returning: nil)
                    }
                    let contactCryptoId = try ObvCryptoId(identity: userIdentity)
                    let userIdentifier: ObvContactIdentifier = .init(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
                    guard let contact = try PersistedObvContactIdentity.get(persisted: userIdentifier, whereOneToOneStatusIs: .any, within: backgroundContext) else {
                        return continuation.resume(returning: nil)
                    }
                    let model: InvitationContactsListCellView.Model? = .init(persistedContactIdentity: contact)
                    return continuation.resume(returning: model)
                } catch {
                    assertionFailure()
                    return continuation.resume(returning: nil)
                }
            }
        }
    }
    
}


// MARK: - Internal managers

extension ListOfContactsAndGroupsViewAppDataSource {
    
    private final class InvitationContactsListViewModelStreamManager {
        
        let streamUUID = UUID()
        private let ownedCryptoId: ObvTypes.ObvCryptoId
        private var latestYieldedModel: InvitationKeycloakContactsListViewModel?
        private var continuation: AsyncStream<InvitationKeycloakContactsListViewModel>.Continuation?

        private var currentSearchStatus: InvitationContactsListViewModel.SearchStatus
        
        init(ownedCryptoId: ObvTypes.ObvCryptoId, initialSearchStatus: ObvInvitationFlow.InvitationContactsListViewModel.SearchStatus) {
            self.ownedCryptoId = ownedCryptoId
            self.currentSearchStatus = initialSearchStatus
        }
        
        func startStream() throws -> (streamUUID: UUID, stream: AsyncStream<InvitationKeycloakContactsListViewModel>) {
            let stream = AsyncStream<InvitationKeycloakContactsListViewModel> { (continuation: AsyncStream<InvitationKeycloakContactsListViewModel>.Continuation) in
                self.continuation = continuation
                updateWithSearchText(searchStatus: currentSearchStatus)
            }
            return (self.streamUUID, stream)
        }
        
        func finishStream() {
            continuation?.finish()
            continuation = nil
        }
        
        func updateWithSearchText(searchStatus: InvitationContactsListViewModel.SearchStatus) {
            guard continuation != nil else { assertionFailure(); return }
            self.currentSearchStatus = searchStatus
            Task {
                try? await Task.sleep(milliseconds: 300)
                guard self.currentSearchStatus == searchStatus else { return } // The search was updated during the network call
                do {
                    let searchQuery: String?
                    switch searchStatus {
                    case .notPerformingSearch:
                        searchQuery = nil
                    case .performingSearch(let searchText):
                        searchQuery = searchText
                    }
                    let newSearchResults = try await KeycloakManagerSingleton.shared.search(ownedCryptoId: ownedCryptoId, searchQuery: searchQuery)
                    guard self.currentSearchStatus == searchStatus else { return } // The search was updated during the network call
                    let model = createModel(searchResults: newSearchResults)
                    yieldModelIfNeeded(model: .success(model))
                } catch let error as ObvKeycloakSearchError {
                    yieldModelIfNeeded(model: .searchError(error))
                } catch {
                    yieldModelIfNeeded(model: .searchError(.unkownError(error)))
                }
            }
        }
        
        private func yieldModelIfNeeded(model: InvitationKeycloakContactsListViewModel) {
            guard let continuation else { assertionFailure(); return }
            guard latestYieldedModel != model else { return }
            latestYieldedModel = model
            continuation.yield(model)
        }

        private func createModel(searchResults: (userDetails: [ObvKeycloakUserDetails], numberOfMissingResults: Int)) -> InvitationContactsListViewModel {
            
            let contactsSortOrder = ObvMessengerSettings.Interface.contactsSortOrder
            
            let sortedUserDetails: [ObvKeycloakUserDetails] = searchResults.userDetails.sorted(by: { d1, d2 in
                let sortString1: String
                let sortString2: String
                switch contactsSortOrder {
                case .byFirstName:
                    sortString1 = [d1.firstName ?? "", d1.lastName ?? ""].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    sortString2 = [d2.firstName ?? "", d2.lastName ?? ""].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                case .byLastName:
                    sortString1 = [d1.lastName ?? "", d1.firstName ?? ""].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    sortString2 = [d2.lastName ?? "", d2.firstName ?? ""].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return sortString1.localizedCaseInsensitiveContains(sortString2)
            })
            
            // Grouping per initial
            let groupedByInitial: [String: [InvitationContactsListViewModel.ContactIdentifier]] = Dictionary(grouping: sortedUserDetails) { userDetail in
                let firstName = userDetail.firstName ?? ""
                let lastName = userDetail.lastName ?? ""
                let firstNameAndLastName: String
                switch contactsSortOrder {
                case .byFirstName:
                    firstNameAndLastName = [firstName, lastName].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                case .byLastName:
                    firstNameAndLastName = [lastName,firstName].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let initial = firstNameAndLastName.first.map { String($0).uppercased() } ?? "#"
                return initial
            }.mapValues { details in
                details.compactMap { .keycloakContactIdentifier($0, contactsSortOrder: contactsSortOrder) }
            }

            return .init(contactIdentifiers: groupedByInitial,
                         numberOfMissingResults: searchResults.numberOfMissingResults)
            
        }
             
    }
    
}


extension ListOfContactsAndGroupsViewAppDataSource {
    
    private final class InvitationFlowGroupListViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<InvitationFlowGroupListViewModel, DisplayedContactGroup>, @unchecked Sendable {
        
        let ownedCryptoId: ObvTypes.ObvCryptoId
        let initialSearchStatus: ObvInvitationFlow.InvitationFlowGroupListViewModel.SearchStatus
        let basePredicateForGroups: NSPredicate
        
        init(ownedCryptoId: ObvTypes.ObvCryptoId, initialSearchStatus: ObvInvitationFlow.InvitationFlowGroupListViewModel.SearchStatus, context: NSManagedObjectContext) {
            self.ownedCryptoId = ownedCryptoId
            self.initialSearchStatus = initialSearchStatus
            basePredicateForGroups = DisplayedContactGroup.getPredicate(ownedCryptoId: ownedCryptoId)
            let fetchRequest = DisplayedContactGroup.getFetchRequest(predicate: basePredicateForGroups)
            let frc = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, sectionNameKeyPath: nil, cacheName: nil)
            super.init(frc: frc)
            self.updateWithSearchText(searchStatus: initialSearchStatus, doPerformFetch: false)
        }
        
        func updateWithSearchText(searchStatus: ObvInvitationFlow.InvitationFlowGroupListViewModel.SearchStatus, doPerformFetch: Bool) {
            let newPredicateForGroups: NSPredicate
            switch searchStatus {
            case .notPerformingSearch:
                newPredicateForGroups = self.basePredicateForGroups
            case .performingSearch(searchText: let searchText):
                let searchPredicateForGroups = DisplayedContactGroup.getSearchPredicate(searchText)
                newPredicateForGroups = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    self.basePredicateForGroups,
                    searchPredicateForGroups,
                ])
            }
            self.frc.fetchRequest.predicate = newPredicateForGroups
            if doPerformFetch {
                do {
                    try frc.performFetch()
                } catch {
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
        
        override func createModel(fetchedObjects: [DisplayedContactGroup]) throws -> InvitationFlowGroupListViewModel {
            let contactGroups = fetchedObjects
            let groupIdentifiers: [ObvCells.ObvGroupCellViewModel.GroupIdentifier] = contactGroups.map { .objectIDOfDisplayedContactGroup($0.objectID) }
            let model = InvitationFlowGroupListViewModel(groupIdentifiers: groupIdentifiers)
            return model
        }
        
    }
    
}


extension ListOfContactsAndGroupsViewAppDataSource {
    
    /// This manager produces the stream of `InvitationContactsListViewModel` providing the source data required by the first view shown when the user taps the "plus" button within the app.
    private final class ContactsListViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<InvitationContactsListViewModel, PersistedObvContactIdentity>, @unchecked Sendable {
        
        private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ListOfContactsAndGroupsViewAppDataSource")
        
        let currentOwnedCryptoId: ObvCryptoId
        let basePredicateForContacts: NSPredicate
        
        @MainActor
        init(currentOwnedCryptoId: ObvCryptoId, initialSearchStatus: InvitationContactsListViewModel.SearchStatus, context: NSManagedObjectContext) {
            self.currentOwnedCryptoId = currentOwnedCryptoId
            basePredicateForContacts = PersistedObvContactIdentity.getPredicateForAllContactsOfOwnedIdentity(
                with: currentOwnedCryptoId,
                whereOneToOneStatusIs: .any)
            let fetchRequest1 = PersistedObvContactIdentity.getFetchRequest(predicate: basePredicateForContacts)
            let frc = NSFetchedResultsController(fetchRequest: fetchRequest1, managedObjectContext: context, sectionNameKeyPath: PersistedObvContactIdentity.Predicate.Key.sortInitial.rawValue, cacheName: nil)
            super.init(frc: frc)
            self.updateWithSearchText(searchStatus: initialSearchStatus, doPerformFetch: false)
        }
        
        func updateWithSearchText(searchStatus: InvitationContactsListViewModel.SearchStatus, doPerformFetch: Bool) {
            let newPredicateForContacts: NSPredicate
            switch searchStatus {
            case .notPerformingSearch:
                newPredicateForContacts = self.basePredicateForContacts
            case .performingSearch(searchText: let searchText):
                let searchPredicateForContacts = PersistedObvContactIdentity.Predicate.getSearchPredicate(searchText)
                newPredicateForContacts = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    self.basePredicateForContacts,
                    searchPredicateForContacts,
                ])
            }
            self.frc.fetchRequest.predicate = newPredicateForContacts
            if doPerformFetch {
                do {
                    try frc.performFetch()
                } catch {
                    Self.logger.fault("🔤 Could not perform fetch: \(error.localizedDescription, privacy: .public)")
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
        
        
        private var persistedContactIdentities: [String: [PersistedObvContactIdentity]] {
            get throws {
                guard let sections = frc.sections else {
                    assertionFailure()
                    throw ObvError.couldNotFetchObjects
                }
                var result = [String: [PersistedObvContactIdentity]]()
                sections.forEach { section in
                    if let contacts = section.objects as? [PersistedObvContactIdentity], !contacts.isEmpty {
                        result[section.name] = contacts
                    }
                }
                return result
            }
        }
                
        
        override func createModel(fetchedObjects: [PersistedObvContactIdentity]) throws -> InvitationContactsListViewModel {
            do {
                let persistedContactIdentities = try persistedContactIdentities
                let convertedPersistedContactIdentities: [String: [InvitationContactsListViewModel.ContactIdentifier]] = persistedContactIdentities.compactMapValues { value in
                    value.compactMap({ .persistedObvContactIdentity($0.objectID) })
                }
                let model = InvitationContactsListViewModel(
                    contactIdentifiers: convertedPersistedContactIdentities,
                    numberOfMissingResults: 0)
                return model
            } catch {
                Self.logger.fault("🔤 Coud not create model: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
        
        
        enum ObvError: Error {
            case couldNotFetchObjects
            case objectDoesNotExist
            case couldNotCreateModel
            case noOwnedIdentity
        }
    }

}


extension ListOfContactsAndGroupsViewAppDataSource {
    
    private final class ContactListCellViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<InvitationContactsListCellView.Model, PersistedObvContactIdentity>, @unchecked Sendable {
        
        @MainActor
        init(contactIdentifier: InvitationContactsListViewModel.ContactIdentifier, context: NSManagedObjectContext) throws {
            let persistedContactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>
            switch contactIdentifier {
            case .obvContactIdentifier, .keycloakContactIdentifier:
                assertionFailure()
                throw ObvError.unexpectedIdentifierKind
            case .persistedObvContactIdentity(let objectID):
                persistedContactObjectID = .init(objectID: objectID)
            }
            
            let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
            request.predicate = PersistedObvContactIdentity.Predicate.withObjectID(persistedContactObjectID.objectID)
            request.fetchLimit = 1
            request.sortDescriptors = [NSSortDescriptor(key: PersistedObvContactIdentity.Predicate.Key.sortDisplayName.rawValue, ascending: true)]
            let frc = NSFetchedResultsController(fetchRequest: request, managedObjectContext: context, sectionNameKeyPath: nil, cacheName: nil)

            super.init(frc: frc)
        }
        
        public var persistedContactIdentity: PersistedObvContactIdentity {
            get throws {
                let frc = self.frc
                
                guard let fetchedObjects = frc.fetchedObjects else {
                    assertionFailure()
                    throw ObvError.couldNotFetchObjects
                }
                
                assert(fetchedObjects.count <= 1)
                
                guard let persistedContactIdentity = fetchedObjects.first else {
                    // This happens when the discussion gets deleted
                    throw ObvError.objectDoesNotExist
                }
                
                return persistedContactIdentity
            }
        }
        
        override func createModel(fetchedObjects: [PersistedObvContactIdentity]) throws -> InvitationContactsListCellView.Model {
            
            let persistedContactIdentity = try persistedContactIdentity
            
            guard let model = InvitationContactsListCellView.Model(persistedContactIdentity: persistedContactIdentity) else {
                throw ObvError.couldNotCreateModel
            }
            
            return model
        }
        
        enum ObvError: Error {
            case couldNotFetchObjects
            case objectDoesNotExist
            case couldNotCreateModel
            case unexpectedIdentifierKind
        }
    }

    
}


// MARK: - InvitationContactsListCellView.Model from a PersistedObvContactIdentity

extension InvitationContactsListCellView.Model {
    
    init?(persistedContactIdentity: PersistedObvContactIdentity) {
        let avatarModel = persistedContactIdentity.avatarViewModel
        guard let coreDetails = persistedContactIdentity.identityCoreDetails else { return nil }
        let customDisplayName = persistedContactIdentity.customDisplayName?.trimmingWhitespacesAndNewlines().mapToNilIfZeroLength()
        self.init(avatarModel: avatarModel,
                  coreDetails: coreDetails,
                  customDisplayName: customDisplayName,
                  isKeycloakManaged: persistedContactIdentity.isCertifiedByOwnKeycloak,
                  wasRecentlyOnline: persistedContactIdentity.wasRecentlyOnline,
                  contactsSortOrder: ObvMessengerSettings.Interface.contactsSortOrder)
    }
    
}


