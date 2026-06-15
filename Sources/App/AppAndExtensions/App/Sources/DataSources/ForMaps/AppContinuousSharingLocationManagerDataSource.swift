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
import ObvLocation
import ObvUICoreData
import OlvidUtils
import ObvAppTypes


/// This class is the datasource of the `ContinuousSharingLocationManager`. It monitors the `PersistedLocationContinuousSent` database to decide whether the location manager should continuously monitor the current device
/// location (in order to update the `PersistedLocationContinuousSent` and to eventually send appropriate messages to contacts).
@MainActor
final class AppContinuousSharingLocationManagerDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        backgroundContext.automaticallyMergesChangesFromParent = true
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }

    private var continuousSharingLocationManagerModelStreamManagerForStreamUUID = [UUID: ContinuousSharingLocationManagerModelStreamManager]()
    
}


extension AppContinuousSharingLocationManagerDataSource: ContinuousSharingLocationManagerDataSource {
    
    func getAsyncSequenceOfContinuousSharingLocationManagerModel() async throws -> (streamUUID: UUID, stream: AsyncStream<ContinuousSharingLocationManagerModel>) {
        let streamManager = ContinuousSharingLocationManagerModelStreamManager(context: backgroundContext)
        let (streamUUID, stream) = try await streamManager.startStream()
        self.continuousSharingLocationManagerModelStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }
    
}


extension AppContinuousSharingLocationManagerDataSource {

    private final class ContinuousSharingLocationManagerModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ContinuousSharingLocationManagerModel, PersistedLocationContinuousSent, PersistedLocationContinuousSent>, @unchecked Sendable {
        
        init(context: NSManagedObjectContext) {
            let frcForLatestNeverExpiringPersistedLocationContinuousSentFromCurrentOwnedDevice = PersistedLocationContinuousSent.getFetchedResultsControllerForLatestNeverExpiringPersistedLocationContinuousSentFromCurrentOwnedDevice(within: context)
            let frcForMaximumExpiringPersistedLocationContinuousSentFromCurrentOwnedDevice = PersistedLocationContinuousSent.getFetchedResultsControllerForMaximumExpiringPersistedLocationContinuousSentFromCurrentOwnedDevice(within: context)
            super.init(frc1: frcForLatestNeverExpiringPersistedLocationContinuousSentFromCurrentOwnedDevice, frc2: frcForMaximumExpiringPersistedLocationContinuousSentFromCurrentOwnedDevice)
        }
        
        override func createModel(fetchedObjects1: [PersistedLocationContinuousSent], fetchedObjects2: [PersistedLocationContinuousSent]) throws -> ContinuousSharingLocationManagerModel {
            for fetchedObjects in [fetchedObjects1, fetchedObjects2] {
                if let locationContinuousSent = fetchedObjects.first {
                    if !locationContinuousSent.isSharingLocationExpired {
                        return .init(continuousSharingLocationFromCurrentDeviceKind: .sharingFromCurrentOwnedDevice(maxExpiration: locationContinuousSent.locationSharingExpirationDate))
                    }
                }
            }
            return .init(continuousSharingLocationFromCurrentDeviceKind: .notSharingFromCurrentOwnedDevice )
        }

    }
    
}
