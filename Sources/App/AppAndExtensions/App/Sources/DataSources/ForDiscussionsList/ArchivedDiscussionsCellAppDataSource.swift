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
import ObvUICoreData
import ObvDiscussionsList
import ObvTypes
import OlvidUtils


@MainActor
final class ArchivedDiscussionsCellAppDataSource {

    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    
    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }

    private var archivedDiscussionsCellModelStreamManagerForStreamUUID = [UUID: ArchivedDiscussionsCellModelStreamManager]()
    
}


extension ArchivedDiscussionsCellAppDataSource: ArchivedDiscussionsCellDataSource {
    
    func getAsyncStreamOfObvArchivedDiscussionsCellModel(_ view: ObvDiscussionsListView, ownedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvArchivedDiscussionsCellModel>) {
        let manager = ArchivedDiscussionsCellModelStreamManager(ownedCryptoId: ownedCryptoId, context: backgroundContext)
        archivedDiscussionsCellModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }


    func finishAsyncStreamOfObvArchivedDiscussionsCellModel(_ view: ObvDiscussionsListView, streamUUID: UUID) {
        guard let manager = archivedDiscussionsCellModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
}


// MARK: - Internal managers

extension ArchivedDiscussionsCellAppDataSource {
    
    private final class ArchivedDiscussionsCellModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvDiscussionsList.ObvArchivedDiscussionsCellModel, PersistedDiscussion, PersistedDiscussion>, @unchecked Sendable {
        
        private let ownedCryptoId: ObvCryptoId

        init(ownedCryptoId: ObvCryptoId, context: NSManagedObjectContext) {
            self.ownedCryptoId = ownedCryptoId
            let modelForFrcAllArchivedDiscussions = PersistedDiscussion.getFetchRequestControllerModelForArchivedDiscussionsForOwnedIdentity(with: ownedCryptoId)
            let frcAllArchivedDiscussions = NSFetchedResultsController(fetchRequest: modelForFrcAllArchivedDiscussions.fetchRequest,
                                                                       managedObjectContext: context,
                                                                       sectionNameKeyPath: nil,
                                                                       cacheName: nil)
            let fetchRequestForArchivedDiscussionsWithNewMessages = PersistedDiscussion.getFetchRequestForArchivedDiscussionsWithNewMessagesForOwnedIdentity(ownedCryptoId: ownedCryptoId)
            let frcForArchivedDiscussionsWithNewMessages = NSFetchedResultsController(fetchRequest: fetchRequestForArchivedDiscussionsWithNewMessages,
                                                                                      managedObjectContext: context,
                                                                                      sectionNameKeyPath: nil,
                                                                                      cacheName: nil)
            super.init(frc1: frcAllArchivedDiscussions, frc2: frcForArchivedDiscussionsWithNewMessages)
        }

        override func createModel(fetchedObjects1: [PersistedDiscussion], fetchedObjects2: [PersistedDiscussion]) throws -> ObvArchivedDiscussionsCellModel {
            
            let allArchivedDiscussions = fetchedObjects1
            let archivedDiscussionsWithNewMessages = fetchedObjects2
            
            let atLeastOneDiscussionIsArchived = !allArchivedDiscussions.isEmpty
            let numberOfArchivedPersistedDiscussionsWithNewMessages = archivedDiscussionsWithNewMessages.count
            
            let model = ObvDiscussionsList.ObvArchivedDiscussionsCellModel(
                atLeastOneDiscussionIsArchived: atLeastOneDiscussionIsArchived,
                numberOfArchivedPersistedDiscussionsWithNewMessages: numberOfArchivedPersistedDiscussionsWithNewMessages)
            
            return model
            
        }
        
        enum ObvError: Error {
            case couldNotFetchObjects
            case ownedCryptoIdNotFound
            case noSections
        }

    }
    
}
