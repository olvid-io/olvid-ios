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
import ObvInvitationFlow
import ObvTypes
import OlvidUtils
import ObvUICoreData


@MainActor
final class ObvQRCodeViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var qrCodeViewViewModelStreamManagerForStreamUUID = [UUID: ObvQRCodeViewViewModelStreamManager]()
    
    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }

}


// MARK: - Implementing ObvQRCodeViewDataSource

extension ObvQRCodeViewAppDataSource: ObvInvitationFlow.ObvQRCodeViewDataSource {
    
    func getAsyncStreamOfObvQRCodeViewViewModel(_ view: ObvInvitationFlow.QRCodeView, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvInvitationFlow.ObvQRCodeViewViewModel>) {
        let manager = ObvQRCodeViewViewModelStreamManager(ownedCryptoId: ownedCryptoId, context: backgroundContext)
        qrCodeViewViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfObvQRCodeViewViewModel(_ view: ObvInvitationFlow.QRCodeView, streamUUID: UUID) {
        guard let manager = qrCodeViewViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
}


// MARK: - Internal managers

extension ObvQRCodeViewAppDataSource {
    
    private final class ObvQRCodeViewViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvInvitationFlow.ObvQRCodeViewViewModel, PersistedObvOwnedIdentity>, @unchecked Sendable {
        
        let ownedCryptoId: ObvTypes.ObvCryptoId
        
        init(ownedCryptoId: ObvTypes.ObvCryptoId, context: NSManagedObjectContext) {
            self.ownedCryptoId = ownedCryptoId
            let frc = PersistedObvOwnedIdentity.getFetchedResultsController(ownedCryptoId: ownedCryptoId, within: context)
            super.init(frc: frc)
        }
        
        override func createModel(fetchedObjects: [PersistedObvOwnedIdentity]) throws -> ObvQRCodeViewViewModel {
            
            assert(fetchedObjects.count < 2)
            
            guard let ownedIdentity = fetchedObjects.first else {
                assertionFailure()
                throw ObvError.ownedIdentityIsNil
            }
            
            return ObvQRCodeViewViewModel(ownedIdentity: ownedIdentity)
            
        }
        
        enum ObvError: Error {
            case ownedIdentityIsNil
        }
        
    }
    
}


extension ObvInvitationFlow.ObvQRCodeViewViewModel {
    
    init(ownedIdentity: PersistedObvOwnedIdentity) {
        let avatarViewModel = ownedIdentity.avatarViewModel
        self.init(ownedIdentityAvatarViewModel: avatarViewModel)
    }
    
}
