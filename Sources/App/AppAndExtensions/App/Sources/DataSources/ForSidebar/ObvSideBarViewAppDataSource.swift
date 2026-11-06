/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvSidebar
import ObvUICoreData
import OlvidUtils
import ObvAppTypes
import ObvTypes


protocol ObvSideBarViewAppDataSourceDelegate: AnyObject {
    func getCurrentOwnedCryptoId(_ dataSource: ObvSideBarViewAppDataSource) -> ObvCryptoId?
}


@MainActor
final class ObvSideBarViewAppDataSource {
 
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }

    
    weak var delegate: ObvSideBarViewAppDataSourceDelegate?
    
    private var obvSideBarViewModelStreamManagerForStreamUUID = [UUID: ObvSideBarViewModelStreamManager]()

    /// The badge of the contacts, which no entity stores: the contacts flow counts the suggestions of the current profile and passes the badge on.
    private var badgeForContacts = BadgeForContacts.none

    /// Called on the main thread by the contacts flow each time it recounts its suggestions, including with 0 when the profile changes.
    func setBadgeForContacts(count: Int, hasANewCard: Bool) {
        let badgeForContacts = BadgeForContacts(count: count, hasANewCard: hasANewCard)
        guard self.badgeForContacts != badgeForContacts else { return }
        self.badgeForContacts = badgeForContacts
        for manager in obvSideBarViewModelStreamManagerForStreamUUID.values {
            manager.setBadgeForContacts(badgeForContacts)
        }
    }

    /// The count of the badge of the contacts, and its colour: red when a card of the suggestions is new, grey otherwise.
    fileprivate struct BadgeForContacts: Equatable {
        let count: Int
        let hasANewCard: Bool
        static let none = BadgeForContacts(count: 0, hasANewCard: false)
    }
    
}



extension ObvSideBarViewAppDataSource: ObvSideBarViewDataSource {
        
    func getAsyncStreamOfObvSideBarViewModel(_ view: ObvSidebar.ObvSideBarView) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvSidebar.ObvSideBarViewModel>) {
        let manager = try ObvSideBarViewModelStreamManager(context: backgroundContext, badgeForContacts: badgeForContacts)
        obvSideBarViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfObvSideBarViewModel(_ view: ObvSidebar.ObvSideBarView, streamUUID: UUID) {
        guard let manager = obvSideBarViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
    /// Called by the `ObvSideBarView` when it appears, to refresh its model immediately. This ensures the UI reflects the latest data without delay.
    func getObvSideBarViewModel(_ view: ObvSideBarView) throws -> ObvSideBarViewModel? {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        guard let currentOwnedCryptoId = delegate.getCurrentOwnedCryptoId(self) else { return nil }
        guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: currentOwnedCryptoId, within: viewContext) else { return nil }
        let flowToHighlight = OlvidUserActivitySingleton.shared.currentUserActivity?.currentFlow ?? .latestDiscussions
        let model = ObvSidebar.ObvSideBarViewModel(ownedIdentity: ownedIdentity, badgeForContacts: badgeForContacts, flowToHighlight: flowToHighlight)
        return model
    }
    
}


extension ObvSideBarViewAppDataSource {

    enum ObvError: Error {
        case delegateIsNil
    }
    
}


// MARK: - Internal stream managers

extension ObvSideBarViewAppDataSource {
    
    private final class ObvSideBarViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvSidebar.ObvSideBarViewModel, PersistedObvOwnedIdentity>, @unchecked Sendable {
                
        private var cancellables: Set<AnyCancellable> = []
        /// Only read and written on the queue of the context of `frc`, once the initializer returned.
        private var badgeForContacts: BadgeForContacts

        init(context: NSManagedObjectContext, badgeForContacts: BadgeForContacts) throws {
            let frc = PersistedObvOwnedIdentity.getFetchedResultsControllerForAllOwnedIdentities(within: context)
            self.badgeForContacts = badgeForContacts
            super.init(frc: frc)
            continuouslyObserveCurrentOwnedCryptoIdAndCurrentFlow()
        }

        /// The blocks of a context run in the order they were submitted, so the last badge given is the one the model ends up with.
        func setBadgeForContacts(_ badgeForContacts: BadgeForContacts) {
            frc.managedObjectContext.perform { [weak self] in
                guard let self else { return }
                self.badgeForContacts = badgeForContacts
                Task { [weak self] in
                    try? await self?.getFetchedObjectsAndYieldModelIfNeeded()
                }
            }
        }
        
        deinit {
            cancellables.forEach { $0.cancel() }
        }

        private func continuouslyObserveCurrentOwnedCryptoIdAndCurrentFlow() {
            OlvidUserActivitySingleton.shared.$currentUserActivity
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    Task { [weak self] in
                        guard let self else { return }
                        do {
                            try await getFetchedObjectsAndYieldModelIfNeeded()
                        } catch {
                            assertionFailure()
                        }
                    }
                }
                .store(in: &cancellables)
        }
        
        override func createModel(fetchedObjects: [PersistedObvOwnedIdentity]) throws -> ObvSideBarViewModel {

            guard let currentOwnedCryptoId = OlvidUserActivitySingleton.shared.currentUserActivity?.ownedCryptoId else {
                assertionFailure()
                throw ObvError.cannotDetermineCurrentOwnedCryptoId
            }
            
            guard let ownedIdentities = frc.fetchedObjects else {
                assertionFailure()
                throw ObvError.fetchedObjectsIsNil
            }
            
            guard let ownedIdentity = ownedIdentities.first(where: { $0.cryptoId == currentOwnedCryptoId }) else {
                assertionFailure()
                throw ObvError.couldNotFindPersistedOwnedIdentity
            }
            
            assert(OlvidUserActivitySingleton.shared.currentUserActivity?.currentFlow != nil)
            let flowToHighlight = OlvidUserActivitySingleton.shared.currentUserActivity?.currentFlow ?? .latestDiscussions
            
            return .init(ownedIdentity: ownedIdentity, badgeForContacts: badgeForContacts, flowToHighlight: flowToHighlight)

        }
        
        enum ObvError: Error {
            case couldNotFindPersistedOwnedIdentity
            case cannotDetermineCurrentOwnedCryptoId
            case fetchedObjectsIsNil
        }
        
    }

}



extension ObvSidebar.ObvSideBarViewModel {
    
    fileprivate init(ownedIdentity: PersistedObvOwnedIdentity, badgeForContacts: ObvSideBarViewAppDataSource.BadgeForContacts, flowToHighlight: ObvAppTypes.ObvFlow) {
        self.init(badgeCountForLatestDiscussions: ownedIdentity.badgeCountForDiscussionsTab,
                  badgeCountForContacts: badgeForContacts.count,
                  badgeForContactsHasANewCard: badgeForContacts.hasANewCard,
                  badgeCountForInvitations: ownedIdentity.badgeCountForInvitationsTab,
                  flowToHighlight: flowToHighlight)
    }
    
}
