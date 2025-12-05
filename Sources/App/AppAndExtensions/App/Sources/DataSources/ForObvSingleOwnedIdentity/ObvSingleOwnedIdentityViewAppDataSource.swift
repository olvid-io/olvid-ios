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
final class ObvSingleOwnedIdentityViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }

    private var singleOwnedIdentityViewModelStreamManagerForStreamUUID = [UUID: ObvSingleOwnedIdentityViewModelStreamManager]()

}

extension ObvSingleOwnedIdentityViewAppDataSource: ObvSingleOwnedIdentityViewDataSource {
    
    func getAsyncSequenceOfObvSingleOwnedIdentityViewModel(_ view: ObvSingleOwnedIdentity.ObvSingleOwnedIdentityView, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvSingleOwnedIdentity.ObvSingleOwnedIdentityView.ModelOrDeleted>) {
        let streamManager = ObvSingleOwnedIdentityViewModelStreamManager(ownedCryptoId: ownedCryptoId, context: backgroundContext)
        let (streamUUID, stream) = try await streamManager.startStream()
        self.singleOwnedIdentityViewModelStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }
    
    func finishAsyncSequenceOfObvSingleOwnedIdentityViewModel(_ view: ObvSingleOwnedIdentity.ObvSingleOwnedIdentityView, streamUUID: UUID) {
        if let streamManager = singleOwnedIdentityViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
    }
    
}


extension ObvSingleOwnedIdentityViewAppDataSource {
    
    final private class ObvSingleOwnedIdentityViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvSingleOwnedIdentity.ObvSingleOwnedIdentityView.ModelOrDeleted, PersistedObvOwnedIdentity>, @unchecked Sendable {
        
        private let ownedCryptoId: ObvTypes.ObvCryptoId
        
        init(ownedCryptoId: ObvTypes.ObvCryptoId, context: NSManagedObjectContext) {
            self.ownedCryptoId = ownedCryptoId
            // The frc watches *all* owned identites, since we need to know the number of *other* non-hidden profiles
            // of the user
            let frc = PersistedObvOwnedIdentity.getFetchedResultsControllerForAllOwnedIdentities(within: context)
            super.init(frc: frc)
        }
        
        override func createModel(fetchedObjects: [PersistedObvOwnedIdentity]) throws -> ObvSingleOwnedIdentityView.ModelOrDeleted {
            guard let ownedIdentity = fetchedObjects.first(where: { $0.ownedCryptoId == ownedCryptoId }) else {
                return .deleted
            }
            let otherOwnedIdentities: [PersistedObvOwnedIdentity] = fetchedObjects.filter { $0.ownedCryptoId != ownedCryptoId }
            let model = ObvSingleOwnedIdentityView.Model(
                ownedIdentity: ownedIdentity,
                otherOwnedIdentities: otherOwnedIdentities)
            return .model(model)
        }
        
    }
    
}


extension ObvSingleOwnedIdentity.ObvSingleOwnedIdentityView.Model {
    
    init(ownedIdentity: PersistedObvOwnedIdentity, otherOwnedIdentities: [PersistedObvOwnedIdentity]) {
        
        let numberOfOtherNonHiddenOwnedIdentities = otherOwnedIdentities.count(where: { !$0.isHidden })
        
        self.init(
            ownedCryptoId: ownedIdentity.ownedCryptoId,
            avatarModel: .init(ownedIdentity: ownedIdentity),
            identityDetails: ownedIdentity.identityDetails,
            isActive: ownedIdentity.isActive,
            numberOfOwnedDevices: ownedIdentity.devices.count,
            apiKeyElements: ownedIdentity.apiKeyElements,
            isHidden: ownedIdentity.isHidden,
            numberOfOtherNonHiddenOwnedIdentities: numberOfOtherNonHiddenOwnedIdentities,
            customDisplayName: ownedIdentity.customDisplayName)
        
    }
    
}
