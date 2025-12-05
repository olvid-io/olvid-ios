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
final class ObvLocationsCellViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
    
    private var locationsCellViewModelStreamManagerForStreamUUID = [UUID: LocationsCellViewModelStreamManager]()
    
}


extension ObvLocationsCellViewAppDataSource: ObvLocationsCellViewDataSource {
    
    func getAsyncStreamOfLocationsCellViewModel(_ view: ObvDiscussionsListView, ownedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvLocationsCellViewModel>) {
        let manager = try LocationsCellViewModelStreamManager(ownedCryptoId: ownedCryptoId, context: backgroundContext)
        locationsCellViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfLocationsCellViewModel(_ view: ObvDiscussionsListView, streamUUID: UUID) {
        guard let manager = locationsCellViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
}


// MARK: - Internal stream managers

extension ObvLocationsCellViewAppDataSource {
    
    private final class LocationsCellViewModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvDiscussionsList.ObvLocationsCellViewModel, PersistedLocationContinuous, PersistedLocationContinuousSent>, @unchecked Sendable {
        
        private let ownedCryptoId: ObvCryptoId

        init(ownedCryptoId: ObvCryptoId, context: NSManagedObjectContext) throws {
            self.ownedCryptoId = ownedCryptoId
            let frcForContinuousLocationsSharedByContactDeviceOrOtherOwnedDevice = PersistedLocationContinuous.getFetchedResultsControllerForContinuousLocationsSharedByContactDeviceOrOtherOwnedDevice(ownedCryptoId: ownedCryptoId, within: context)
            let frcForPersistedLocationContinuousSentFromCurrentPhysicalDevice = try PersistedLocationContinuousSent.getFetchRequestForPersistedLocationContinuousSentFromCurrentPhysicalDevice(within: context)
            super.init(frc1: frcForContinuousLocationsSharedByContactDeviceOrOtherOwnedDevice, frc2: frcForPersistedLocationContinuousSentFromCurrentPhysicalDevice)
        }

        override func createModel(fetchedObjects1: [PersistedLocationContinuous], fetchedObjects2: [PersistedLocationContinuousSent]) throws -> ObvLocationsCellViewModel {
            
            let locationsReceived = fetchedObjects1
            let locationsSent = fetchedObjects2
            
            let model = ObvLocationsCellViewModel(
                ownedCryptoId: ownedCryptoId,
                numberOfLocationsReceivedForTheCurrentOwnedCryptoId: locationsReceived.count,
                someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice: !locationsSent.isEmpty)
            
            return model
            
        }
        
    }
        
}
