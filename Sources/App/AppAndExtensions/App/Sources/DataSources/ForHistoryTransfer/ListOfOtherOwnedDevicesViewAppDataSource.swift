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
import ObvTypes
import OlvidUtils
import ObvHistoryTransfer

@MainActor
final class ListOfOtherOwnedDevicesViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    
    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
    
    private var listOfOtherOwnedDevicesViewModelStreamManagerForStreamUUID = [UUID: ListOfOtherOwnedDevicesViewModelStreamManager]()
    
}


extension ListOfOtherOwnedDevicesViewAppDataSource: ListOfOtherOwnedDevicesViewDataSource {
    
    func getAsyncStreamOfListOfOtherOwnedDevicesViewModels(_ view: ObvHistoryTransfer.ListOfOtherOwnedDevicesView, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvHistoryTransfer.ListOfOtherOwnedDevicesView.Model>) {
        let manager = ListOfOtherOwnedDevicesViewModelStreamManager(ownedCryptoId: ownedCryptoId, context: backgroundContext)
        listOfOtherOwnedDevicesViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfListOfOtherOwnedDevicesViewModels(_ view: ObvHistoryTransfer.ListOfOtherOwnedDevicesView, streamUUID: UUID) {
        let manager = listOfOtherOwnedDevicesViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID)
        manager?.finishStream()
    }

}


// MARK: - Internal managers

extension ListOfOtherOwnedDevicesViewAppDataSource {
    
    private final class ListOfOtherOwnedDevicesViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvHistoryTransfer.ListOfOtherOwnedDevicesView.Model, PersistedObvOwnedDevice>, @unchecked Sendable {
        
        private let ownedCryptoId: ObvCryptoId

        init(ownedCryptoId: ObvCryptoId, context: NSManagedObjectContext) {
            self.ownedCryptoId = ownedCryptoId
            let frc = PersistedObvOwnedDevice.getFetchedResultsController(ownedCryptoId: ownedCryptoId, within: context)
            super.init(frc: frc)
        }
        
        override func createModel(fetchedObjects: [PersistedObvOwnedDevice]) throws -> ListOfOtherOwnedDevicesView.Model {
            let model: ListOfOtherOwnedDevicesView.Model = try .init(allOwnedDevices: fetchedObjects)
            return model
        }
        
    }
    
}

// MARK: - Errors

extension ListOfOtherOwnedDevicesViewAppDataSource {
    
    enum ObvError: Error {
        case expectingOtherOwnedDeviceAndNotCurrentDevice
    }
    
}

// MARK: - Helpers

extension ObvHistoryTransfer.ListOfOtherOwnedDevicesView.Model {
    
    init(allOwnedDevices: [PersistedObvOwnedDevice]) throws {
        let otherOwnedDevices = allOwnedDevices.filter({ $0.secureChannelStatus != .currentDevice })
        let isCurrentDeviceActive = allOwnedDevices.first(where: { $0.secureChannelStatus == .currentDevice })?.ownedIdentityIsActive ?? false
        self.init(isCurrentDeviceActive: isCurrentDeviceActive,
                  otherOwnedDevices: try otherOwnedDevices.map { try .init(otherOwnedDevice: $0) })
    }
    
}


extension ObvHistoryTransfer.OtherOwnedDeviceView.Model {
    
    init(otherOwnedDevice: PersistedObvOwnedDevice) throws {

        switch otherOwnedDevice.secureChannelStatus {
        case .currentDevice, .none:
            assertionFailure()
            throw ListOfOtherOwnedDevicesViewAppDataSource.ObvError.expectingOtherOwnedDeviceAndNotCurrentDevice
        case .created(preKeyAvailable: _), .creationInProgress(preKeyAvailable: _):
            break
        }
        
        self.init(ownedDeviceIdentifier: try otherOwnedDevice.ownedDeviceIdentifier,
                  deviceName: otherOwnedDevice.name,
                  platform: .unknown)
        
    }
    
}
