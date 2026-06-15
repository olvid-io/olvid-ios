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
        private var currentRefreshTask: Task<Void, any Error>?

        init(ownedCryptoId: ObvCryptoId, context: NSManagedObjectContext) throws {
            self.ownedCryptoId = ownedCryptoId
            let frcForContinuousLocationsSharedByContactDeviceOrOtherOwnedDevice = PersistedLocationContinuous.getFetchedResultsControllerForNotExpiredContinuousLocationsSharedByContactDeviceOrOtherOwnedDevice(ownedCryptoId: ownedCryptoId, within: context)
            let frcForPersistedLocationContinuousSentFromCurrentPhysicalDevice = try PersistedLocationContinuousSent.getFetchRequestForPersistedLocationContinuousSentFromCurrentPhysicalDevice(within: context)
            super.init(frc1: frcForContinuousLocationsSharedByContactDeviceOrOtherOwnedDevice, frc2: frcForPersistedLocationContinuousSentFromCurrentPhysicalDevice)
        }

        override func createModel(fetchedObjects1: [PersistedLocationContinuous], fetchedObjects2: [PersistedLocationContinuousSent]) throws -> ObvLocationsCellViewModel {
            
            // The first fetch request filters out expired shared location, but only wrt the date when the request was created. So we must also filter out expired locations here.
            
            let locationsReceived = fetchedObjects1.filter { $0 is PersistedLocationContinuousReceived && !$0.isSharingLocationExpired }
            
            let locationSentFromOtherDevices = fetchedObjects1.filter { $0 is PersistedLocationContinuousSent && !$0.isSharingLocationExpired }
            
            let locationsSent = fetchedObjects2
            
            // If one of the received continuous shared locations expires in the future, we should request a refresh in the future.
            
            if let minExpirationDate = locationsReceived.compactMap({ $0.sharingExpiration }).filter({ $0 > .now }).min() {
                refresh(at: minExpirationDate)
            }
            
            let model = ObvLocationsCellViewModel(
                ownedCryptoId: ownedCryptoId,
                numberOfLocationsReceivedForTheCurrentOwnedCryptoId: locationsReceived.count,
                someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice: !locationsSent.isEmpty,
                numberOfOtherPhysicalDevicesSharingLocationOfTheCurrentOwnedIdentity: locationSentFromOtherDevices.count)
            
            return model
            
        }
        
        
        private func createAndYieldModelIfNeeded() {
            let context = frc1.managedObjectContext
            context.perform { [weak self] in
                guard let self else { return }
                guard let fetchedObjects1 = self.frc1.fetchedObjects, let fetchedObjects2 = self.frc2.fetchedObjects else { return }
                guard let model = try? createModel(fetchedObjects1: fetchedObjects1, fetchedObjects2: fetchedObjects2) else { assertionFailure(); return }
                self.yieldModelIfNeeded(model: model, within: context)
            }
        }
        

        /// Schedules a refresh at the earliest expiration date among all continuous locations.
        ///
        /// When continuous locations have expiration dates, this method receives the nearest
        /// expiration and schedules a refresh to occur at that time, ensuring expired
        /// locations are removed promptly.
        private func refresh(at date: Date) {
            let timeIntervalSinceNow = date.timeIntervalSinceNow
            guard timeIntervalSinceNow > 0 else { return }
            currentRefreshTask?.cancel()
            currentRefreshTask = Task { [weak self] in
                try await Task.sleep(seconds: timeIntervalSinceNow)
                guard let self else { return }
                createAndYieldModelIfNeeded()
            }
        }
        
    }
        
}
