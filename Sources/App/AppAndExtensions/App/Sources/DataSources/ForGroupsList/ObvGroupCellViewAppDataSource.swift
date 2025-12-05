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
import ObvCells
import ObvUICoreData


@MainActor
final class ObvGroupCellViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var obvGroupCellViewViewModelStreamManagerForStreamUUID = [UUID: ObvGroupCellViewModelStreamManager]()
    
    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
    
}


// MARK: - Implementing ObvGroupCellViewDataSource

extension ObvGroupCellViewAppDataSource: ObvGroupCellViewDataSource {
    
    func getAsyncStreamOfObvGroupCellViewModel(_ view: ObvCells.ObvGroupCellView, groupIdentifier: ObvCells.ObvGroupCellViewModel.GroupIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvCells.ObvGroupCellViewModel>) {
        guard let objectID = groupIdentifier.objectID else {
            assertionFailure()
            throw ObvError.unexpectedGroupIdentifierType
        }
        let manager = ObvGroupCellViewModelStreamManager(objectID: TypeSafeManagedObjectID<DisplayedContactGroup>(objectID: objectID), within: backgroundContext)
        obvGroupCellViewViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    
    func finishAsyncStreamOfObvGroupCellViewModel(_ view: ObvCells.ObvGroupCellView, streamUUID: UUID) {
        guard let manager = obvGroupCellViewViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
    
}


extension ObvGroupCellViewAppDataSource {
    
    enum ObvError: Error {
        case unexpectedGroupIdentifierType
        case noCurrentOwnedCryptoId
    }
    
}


// MARK: - Internal managers

extension ObvGroupCellViewAppDataSource {
    
    private final class ObvGroupCellViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvCells.ObvGroupCellViewModel, DisplayedContactGroup>, @unchecked Sendable {
        
        init(objectID: TypeSafeManagedObjectID<DisplayedContactGroup>, within context: NSManagedObjectContext) {
            let fetchRequest = DisplayedContactGroup.getNSFetchRequest(objectID: objectID)
            let frc = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, sectionNameKeyPath: nil, cacheName: nil)
            super.init(frc: frc)
        }
        
        override func createModel(fetchedObjects: [DisplayedContactGroup]) throws -> ObvGroupCellViewModel {
            
            let displayedContactGroups = fetchedObjects
            
            assert(displayedContactGroups.count < 2)
            
            guard let displayedContactGroup = displayedContactGroups.first else {
                throw ObvError.couldNotFindDisplayedContactGroup
            }
            
            let model = try ObvGroupCellViewModel(displayedContactGroup: displayedContactGroup)
            
            return model

        }
        
        enum ObvError: Error {
            case couldNotFindDisplayedContactGroup
        }

    }
    
}
