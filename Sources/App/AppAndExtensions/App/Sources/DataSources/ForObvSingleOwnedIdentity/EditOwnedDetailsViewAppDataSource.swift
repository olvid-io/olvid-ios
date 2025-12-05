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
import ObvSingleOwnedIdentity
import OlvidUtils
import ObvDesignSystem


@MainActor
final class EditOwnedDetailsViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }

    private var editOwnedDetailsViewModelStreamManagerForStreamUUID = [UUID: EditOwnedDetailsViewModelStreamManager]()

}

extension EditOwnedDetailsViewAppDataSource: EditOwnedDetailsViewDataSource {
    
    func getAsyncSequenceOfEditOwnedDetailsViewModel(_ view: ObvSingleOwnedIdentity.EditOwnedDetailsView, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvSingleOwnedIdentity.EditOwnedDetailsView.Model>) {
        let streamManager = EditOwnedDetailsViewModelStreamManager(ownedCryptoId: ownedCryptoId, context: backgroundContext)
        let (streamUUID, stream) = try await streamManager.startStream()
        self.editOwnedDetailsViewModelStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }
    
    func finishAsyncSequenceOfEditOwnedDetailsViewModel(_ view: ObvSingleOwnedIdentity.EditOwnedDetailsView, streamUUID: UUID) {
        if let streamManager = editOwnedDetailsViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
    }
    
}


extension EditOwnedDetailsViewAppDataSource {
    
    private final class EditOwnedDetailsViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<EditOwnedDetailsView.Model, PersistedObvOwnedIdentity>, @unchecked Sendable {
        
        init(ownedCryptoId: ObvTypes.ObvCryptoId, context: NSManagedObjectContext) {
            let frc = PersistedObvOwnedIdentity.getFetchedResultsController(ownedCryptoId: ownedCryptoId, within: context)
            super.init(frc: frc)
        }

        override func createModel(fetchedObjects: [PersistedObvOwnedIdentity]) throws -> EditOwnedDetailsView.Model {
            assert(fetchedObjects.count <= 1)
            guard let ownedIdentity = fetchedObjects.first else {
                throw ObvError.ownedIdentityNotFound
            }
            let model = EditOwnedDetailsView.Model(ownedIdentity: ownedIdentity)
            return model
        }
        
    }
    
    enum ObvError: Error {
        case ownedIdentityNotFound
    }
    
}


extension ObvSingleOwnedIdentity.EditOwnedDetailsView.Model {
    
    init(ownedIdentity: PersistedObvOwnedIdentity) {
        self.init(ownedIdentityDetails: ownedIdentity.identityDetails,
                  largePhotoModel: .init(ownedIdentity: ownedIdentity),
                  isManagedByKeycloak: ownedIdentity.isKeycloakManaged)
    }
    
}


extension LargePhotoAndEditButton.InitialModel {
    
    init(ownedIdentity: PersistedObvOwnedIdentity) {
        self.init(textForInitial: ownedIdentity.circledInitialsConfiguration.initials?.text,
                  colors: .init(background: ownedIdentity.circledInitialsConfiguration.backgroundColor(appTheme: AppTheme.shared),
                                foreground: ownedIdentity.circledInitialsConfiguration.foregroundColor(appTheme: AppTheme.shared)),
                  showGreenShield: ownedIdentity.isKeycloakManaged)
    }
    
}
