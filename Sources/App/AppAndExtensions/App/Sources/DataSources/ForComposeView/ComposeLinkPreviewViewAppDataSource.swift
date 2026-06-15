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
import UniformTypeIdentifiers
import OlvidUtils
import ObvComposition
import ObvEncoder
import ObvAppTypes


final class ComposeLinkPreviewViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }

    private var composeLinkPreviewViewModelStreamManagerForStreamUUID = [UUID : ComposeLinkPreviewViewModelStreamManager]()
    
}


// MARK: - Implementing ComposeLinkPreviewViewDataSource


extension ComposeLinkPreviewViewAppDataSource: ComposeLinkPreviewViewDataSource {
    
    func getAsyncStreamOfComposeLinkPreviewViewModel(_ view: ObvComposition.ComposeLinkPreviewView, attachmentIdentifier: ObvComposition.ComposeAttachmentView.AttachmentIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvComposition.ComposeLinkPreviewView.Model>) {
        let joinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>
        switch attachmentIdentifier {
        case .persistedDraftFyleJoinObjectID(let objectID):
            joinObjectID = TypeSafeManagedObjectID<PersistedDraftFyleJoin>(objectID: objectID)
        }
        let manager = ComposeLinkPreviewViewModelStreamManager(joinObjectID: joinObjectID, context: backgroundContext)
        composeLinkPreviewViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfComposeLinkPreviewViewModel(_ view: ObvComposition.ComposeLinkPreviewView, streamUUID: UUID) {
        guard let manager = composeLinkPreviewViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
}


// MARK: - Internal stream manager


extension ComposeLinkPreviewViewAppDataSource {
    
    private final class ComposeLinkPreviewViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ComposeLinkPreviewView.Model, PersistedDraftFyleJoin>, @unchecked Sendable {
        
        init(joinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>, context: NSManagedObjectContext) {
            let frc = PersistedDraftFyleJoin.getFetchedResultsController(withObjectID: joinObjectID, within: context)
            super.init(frc: frc)
        }
        
        override func createModel(fetchedObjects: [PersistedDraftFyleJoin]) throws -> ComposeLinkPreviewView.Model {
            assert(fetchedObjects.count <= 1)
            guard let join = fetchedObjects.first else {
                throw ObvError.couldNotFindPersistedDraftFyleJoin
            }
            let model = try ComposeLinkPreviewView.Model(join)
            return model
        }
        
    }
    
}


extension ComposeLinkPreviewViewAppDataSource {
    
    enum ObvError: Error {
        case couldNotFindPersistedDraftFyleJoin
        case unexpectedUTType
        case requiredDataIsMissing
        case decodingFailed
    }
    
}


// MARK: - Initializing ComposeLinkPreviewView.Model from a PersistedDraftFyleJoin

extension ComposeLinkPreviewView.Model {
    
    init(_ join: PersistedDraftFyleJoin) throws {
        
        guard join.isPreviewType else {
            assertionFailure()
            throw ComposeLinkPreviewViewAppDataSource.ObvError.unexpectedUTType
        }
        
        guard let fallbackURL = URL(string: join.fileName),
        let fyleURL = join.fyle?.url,
        FileManager.default.fileExists(atPath: fyleURL.path) else {
            assertionFailure()
            throw ComposeLinkPreviewViewAppDataSource.ObvError.requiredDataIsMissing
        }
        
        let data = try Data(contentsOf: fyleURL)
        guard let obvEncoded = ObvEncoded(withRawData: data) else {
            assertionFailure()
            throw ComposeLinkPreviewViewAppDataSource.ObvError.decodingFailed
        }
        
        guard let linkMetadata = ObvLinkMetadata.decode(obvEncoded, fallbackURL: fallbackURL) else {
            assertionFailure()
            throw ComposeLinkPreviewViewAppDataSource.ObvError.decodingFailed
        }
        
        self.init(image: linkMetadata.image,
                  title: linkMetadata.title,
                  desc: linkMetadata.desc,
                  url: linkMetadata.url)
    }
 
    
}
