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
import ObvLocation
import CoreData
import ObvAppTypes
import ObvTypes
import ObvUICoreData


/// This data source streams the model required by the `LocationsCellView` shown in the list of recent discussions when we are sharing the current physical device location
/// (with any of the local profiles) or when receiving a location from the current profile's contacts or any other owned device of the current profile.
@MainActor
final class NewDiscussionsViewControllerForLocationDataSource {
    
    private var streamManagerForStreamUUID = [UUID: LocationStreamManager]()
    
    func getAsyncSequenceOfLocationsCellViewModel(ownedCryptoId: ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<LocationsCellViewModel>) {
        let streamManager = try LocationStreamManager(ownedCryptoId: ownedCryptoId)
        let (streamUUID, stream) = try streamManager.startStream()
        self.streamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }
    
}

extension NewDiscussionsViewControllerForLocationDataSource {
    
    private final class LocationStreamManager: NSObject, NSFetchedResultsControllerDelegate {
        
        let streamUUID = UUID()
        private let ownedCryptoId: ObvCryptoId
        private let frcForContinuousLocationsSharedByContactDeviceOrOtherOwnedDevice: NSFetchedResultsController<PersistedLocationContinuous>
        private let frcForPersistedLocationContinuousSentFromCurrentPhysicalDevice: NSFetchedResultsController<PersistedLocationContinuousSent>
        
        private var stream: AsyncStream<LocationsCellViewModel>?
        private var continuation: AsyncStream<LocationsCellViewModel>.Continuation?
        
        private var previouslyYieldedModel: LocationsCellViewModel?

        @MainActor
        init(ownedCryptoId: ObvCryptoId) throws {
            self.ownedCryptoId = ownedCryptoId
            self.frcForContinuousLocationsSharedByContactDeviceOrOtherOwnedDevice = PersistedLocationContinuous.getFetchedResultsControllerForContinuousLocationsSharedByContactDeviceOrOtherOwnedDevice(ownedCryptoId: ownedCryptoId, within: ObvStack.shared.viewContext)
            self.frcForPersistedLocationContinuousSentFromCurrentPhysicalDevice = try PersistedLocationContinuousSent.getFetchRequestForPersistedLocationContinuousSentFromCurrentPhysicalDevice(within: ObvStack.shared.viewContext)
            super.init()
        }
        
        @MainActor
        func startStream() throws ->(streamUUID: UUID, AsyncStream<LocationsCellViewModel>) {
            if let stream {
                return (streamUUID, stream)
            }
            frcForContinuousLocationsSharedByContactDeviceOrOtherOwnedDevice.delegate = self
            frcForPersistedLocationContinuousSentFromCurrentPhysicalDevice.delegate = self
            try frcForContinuousLocationsSharedByContactDeviceOrOtherOwnedDevice.performFetch()
            try frcForPersistedLocationContinuousSentFromCurrentPhysicalDevice.performFetch()
            
            let stream = AsyncStream(LocationsCellViewModel.self) { [weak self] (continuation: AsyncStream<LocationsCellViewModel>.Continuation) in
                guard let self else { return }
                self.continuation = continuation
                do {
                    let model = try createModel()
                    yieldModelIfNeeded(model: model)
                } catch {
                    assertionFailure()
                }
            }
            self.stream = stream
            return (streamUUID, stream)
        }
        
        
        private func yieldModelIfNeeded(model: LocationsCellViewModel) {
            guard let continuation else { assertionFailure(); return }
            guard previouslyYieldedModel != model else { return }
            previouslyYieldedModel = model
            continuation.yield(model)

        }
        
        
        func finishStream() {
            continuation?.finish()
        }
        
        func controller(_ controller: NSFetchedResultsController<any NSFetchRequestResult>, didChangeContentWith diff: CollectionDifference<NSManagedObjectID>) {
            do {
                let model = try createModel()
                yieldModelIfNeeded(model: model)
            } catch {
                assertionFailure()
            }
        }
        
        private func createModel() throws -> LocationsCellViewModel {

            guard let locationsReceived = frcForContinuousLocationsSharedByContactDeviceOrOtherOwnedDevice.fetchedObjects else {
                assertionFailure()
                throw ObvError.couldNotFetchObjects
            }
            
            guard let locationsSent = frcForPersistedLocationContinuousSentFromCurrentPhysicalDevice.fetchedObjects else {
                assertionFailure()
                throw ObvError.couldNotFetchObjects
            }
            
            let model = LocationsCellViewModel(
                ownedCryptoId: ownedCryptoId,
                numberOfLocationsReceivedForTheCurrentOwnedCryptoId: locationsReceived.count,
                someOwnedIdentityIsSharingTheLocationOfTheCurrentPhysicalDevice: !locationsSent.isEmpty)
            
            return model
        }
        
        enum ObvError: Error {
            case couldNotFetchObjects
            case ownedCryptoIdNotFound
        }
    }
}
