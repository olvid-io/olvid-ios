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
import ObvTypes
import ObvUICoreData
import ObvDesignSystem
import ObvProfilePictureBarButtonItem
import OlvidUtils


@MainActor
final class ProfilePictureBarButtonItemViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
    
    private var obvProfilePictureBarButtonItemViewModelStreamManagerForStreamUUID = [UUID: ObvProfilePictureBarButtonItemViewModelStreamManager]()

}


// MARK: - Implementing ObvProfilePictureBarButtonItemViewDataSource

extension ProfilePictureBarButtonItemViewAppDataSource: ObvProfilePictureBarButtonItemViewDataSource {
    
    func getAsyncStreamOfObvProfilePictureBarButtonItemViewModel(_ view: ObvProfilePictureBarButtonItemView, ownedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvProfilePictureBarButtonItemViewModel>) {
        let manager = ObvProfilePictureBarButtonItemViewModelStreamManager(ownedCryptoId: ownedCryptoId, context: backgroundContext)
        obvProfilePictureBarButtonItemViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfObvProfilePictureBarButtonItemViewModel(_ view: ObvProfilePictureBarButtonItemView, streamUUID: UUID) {
        guard let manager = obvProfilePictureBarButtonItemViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }

    func getNextOwnedCryptoId(_ view: ObvProfilePictureBarButtonItem.ObvProfilePictureBarButtonItemView, currentOwnedCryptoId: ObvTypes.ObvCryptoId) async throws -> ObvTypes.ObvCryptoId {
        let ownedIdentities = try PersistedObvOwnedIdentity.getAll(within: viewContext)
        guard ownedIdentities.count > 1 else { return currentOwnedCryptoId }
        guard let currentIndex = ownedIdentities.firstIndex(where: { $0.cryptoId == currentOwnedCryptoId }) else { return currentOwnedCryptoId }
        for offset in 1..<ownedIdentities.count {
            let nextIndex = (currentIndex+offset) % ownedIdentities.count
            let ownedIdentity = ownedIdentities[nextIndex]
            guard !ownedIdentity.isHidden else { continue }
            return ownedIdentity.cryptoId
        }
        // If we reach this point, we could not find an appropriate unhidden identy
        return currentOwnedCryptoId
    }

}


extension ProfilePictureBarButtonItemViewAppDataSource {
    
    enum ObvError: Error {
        case delegateNotSet
    }
    
}


// MARK: - Internal Managers


extension ProfilePictureBarButtonItemViewAppDataSource {
    
    fileprivate final class ObvProfilePictureBarButtonItemViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvProfilePictureBarButtonItem.ObvProfilePictureBarButtonItemViewModel, PersistedObvOwnedIdentity>, PersistedObvOwnedIdentityObserver, @unchecked Sendable {
        
        private let ownedCryptoId: ObvCryptoId
        private var observationTokens = [any NSObjectProtocol]()

        init(ownedCryptoId: ObvCryptoId, context: NSManagedObjectContext) {
            self.ownedCryptoId = ownedCryptoId
            let frc = PersistedObvOwnedIdentity.getFetchedResultsController(ownedCryptoId: ownedCryptoId, within: context)
            super.init(frc: frc)
            Task { await PersistedObvOwnedIdentity.addObvObserver(self) }
        }

        
        override func startStream() async throws -> (streamUUID: UUID, stream: AsyncStream<ObvProfilePictureBarButtonItem.ObvProfilePictureBarButtonItemViewModel>) {
            continuouslyUpdateTheRedDotOnTheProfilePictureView()
            return try await super.startStream()
        }
        
        
        override func finishStream() {
            observationTokens.removeAll()
            super.finishStream()
        }

        
//        @MainActor
//        private func createAndYieldModelIfNeeded() {
//            do {
//                let model = try createModel()
//                self.yieldModelIfNeeded(model: model)
//            } catch {
//                // This happens when deleting an owned identity
//                if let error = error as? ObvProfilePictureBarButtonItemViewModelStreamManager.ObvError {
//                    switch error {
//                    case .couldNotFindPersistedObvOwnedIdentity:
//                        return
//                    }
//                } else {
//                    assertionFailure()
//                }
//            }
//        }
        

        override func createModel(fetchedObjects: [PersistedObvOwnedIdentity]) throws -> ObvProfilePictureBarButtonItemViewModel {
            
            assert(fetchedObjects.count < 2)
            
            guard let firstObject = fetchedObjects.first else {
                // This happens when the discussion gets deleted
                throw ObvError.couldNotFindPersistedObvOwnedIdentity
            }

            assert(firstObject.cryptoId == self.ownedCryptoId)
            
            let showRedDot = try PersistedObvOwnedIdentity.shouldShowRedDotOnTheProfilePictureView(of: ownedCryptoId, within: frc.managedObjectContext)

            return .init(ownedIdentity: firstObject, showRedDot: showRedDot)
            
        }
        
        // Methods required to update the red dot when appropriate
        
        func aPersistedObvOwnedIdentityWasDeleted(ownedCryptoId: ObvCryptoId) async {
            await refreshModelUnlessThisProfileIsGone()
        }


        /// Refetches and yields, treating *this profile no longer exists* as an ordinary outcome rather than a fault.
        ///
        /// Both callers are told that *some* profile changed, and one of those changes is this very profile being deleted — whereupon the fetched results
        /// controller has nothing to build a model from. There is nothing to show and the button is on its way out with the profile, so the answer is to stop.
        /// Asserting instead is a crash on the ordinary path of deleting a profile, in every Debug build.
        private func refreshModelUnlessThisProfileIsGone() async {
            do {
                try await getFetchedObjectsAndYieldModelIfNeeded()
            } catch ObvError.couldNotFindPersistedObvOwnedIdentity {
                return
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }

        
        private func continuouslyUpdateTheRedDotOnTheProfilePictureView() {
            observationTokens.append(contentsOf: [
                ObvMessengerCoreDataNotification.observeBadgeCountForDiscussionsOrInvitationsTabChangedForOwnedIdentity { [weak self] concernedOwnedIdentity in
                    // If the number of new messages changed for the current owned identity, no need to updae the red dot
                    guard self?.ownedCryptoId != concernedOwnedIdentity else { return }
                    Task { [weak self] in
                        guard let self else { return }
                        await refreshModelUnlessThisProfileIsGone()
                    }
                },
            ])
        }
        

        enum ObvError: Error {
            case couldNotFindPersistedObvOwnedIdentity
        }

    }

}
