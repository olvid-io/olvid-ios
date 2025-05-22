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
import ObvLocation
import ObvUICoreData


/// This class is the datasource of the `ContinuousSharingLocationManager`. It monitors the `PersistedLocationContinuousSent` database to decide whether the location manager should continuously monitor the current device
/// location (in order to update the `PersistedLocationContinuousSent` and to eventually send appropriate messages to contacts).
@MainActor
final class AppContinuousSharingLocationManagerDataSource: ContinuousSharingLocationManagerDataSource {
    
    private var continuousSharingLocationManagerModelStreamManagerForStreamUUID = [UUID: ContinuousSharingLocationManagerModelStreamManager]()
    
    func getAsyncSequenceOfContinuousSharingLocationManagerModel() throws -> (streamUUID: UUID, stream: AsyncStream<ObvLocation.ContinuousSharingLocationManagerModel>) {
        let streamManager = ContinuousSharingLocationManagerModelStreamManager()
        let (streamUUID, stream) = try streamManager.startStream()
        self.continuousSharingLocationManagerModelStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }
    
}


extension AppContinuousSharingLocationManagerDataSource {
    
    private final class ContinuousSharingLocationManagerModelStreamManager: NSObject, NSFetchedResultsControllerDelegate {
        
        let streamUUID = UUID()
        let frcForLatestNeverExpiringPersistedLocationContinuousSentFromCurrentOwnedDevice: NSFetchedResultsController<PersistedLocationContinuousSent>
        let frcForMaximumExpiringPersistedLocationContinuousSentFromCurrentOwnedDevice: NSFetchedResultsController<PersistedLocationContinuousSent>
        private var stream: AsyncStream<ContinuousSharingLocationManagerModel>?
        private var continuation: AsyncStream<ContinuousSharingLocationManagerModel>.Continuation?

        @MainActor
        override init() {
            self.frcForLatestNeverExpiringPersistedLocationContinuousSentFromCurrentOwnedDevice = PersistedLocationContinuousSent.getFetchedResultsControllerForLatestNeverExpiringPersistedLocationContinuousSentFromCurrentOwnedDevice(within: ObvStack.shared.viewContext)
            self.frcForMaximumExpiringPersistedLocationContinuousSentFromCurrentOwnedDevice = PersistedLocationContinuousSent.getFetchedResultsControllerForMaximumExpiringPersistedLocationContinuousSentFromCurrentOwnedDevice(within: ObvStack.shared.viewContext)
            super.init()
        }
        
        private func createModel() throws -> ObvLocation.ContinuousSharingLocationManagerModel {
            for frc in [frcForLatestNeverExpiringPersistedLocationContinuousSentFromCurrentOwnedDevice, frcForMaximumExpiringPersistedLocationContinuousSentFromCurrentOwnedDevice] {
                guard let fetchedObjects = frc.fetchedObjects else {
                    assertionFailure()
                    throw ObvError.couldNotFetchPersistedLocationContinuousSent
                }
                if let locationContinuousSent = fetchedObjects.first {
                    if !locationContinuousSent.isSharingLocationExpired {
                        return .init(continuousSharingLocationFromCurrentDeviceKind: .sharingFromCurrentOwnedDevice(maxExpiration: locationContinuousSent.locationSharingExpirationDate))
                    }
                }
            }
            return .init(continuousSharingLocationFromCurrentDeviceKind: .notSharingFromCurrentOwnedDevice )
        }
        
        @MainActor
        func startStream() throws -> (streamUUID: UUID, stream: AsyncStream<ObvLocation.ContinuousSharingLocationManagerModel>) {
            if let stream {
                return (streamUUID, stream)
            }
            frcForLatestNeverExpiringPersistedLocationContinuousSentFromCurrentOwnedDevice.delegate = self
            frcForMaximumExpiringPersistedLocationContinuousSentFromCurrentOwnedDevice.delegate = self
            try frcForLatestNeverExpiringPersistedLocationContinuousSentFromCurrentOwnedDevice.performFetch()
            try frcForMaximumExpiringPersistedLocationContinuousSentFromCurrentOwnedDevice.performFetch()
            let stream = AsyncStream(ObvLocation.ContinuousSharingLocationManagerModel.self) { [weak self] (continuation: AsyncStream<ObvLocation.ContinuousSharingLocationManagerModel>.Continuation) in
                guard let self else { return }
                self.continuation = continuation
                do {
                    let model = try createModel()
                    continuation.yield(model)
                } catch {
                    assertionFailure()
                }
            }
            self.stream = stream
            return (streamUUID, stream)
        }
        

        func controller(_ controller: NSFetchedResultsController<any NSFetchRequestResult>, didChangeContentWith diff: CollectionDifference<NSManagedObjectID>) {
            guard let continuation else { assertionFailure(); return }
            do {
                let model = try createModel()
                continuation.yield(model)
            } catch {
                assertionFailure()
            }
        }

        enum ObvError: Error {
            case couldNotFetchPersistedLocationContinuousSent
        }
        
    }
    
}
