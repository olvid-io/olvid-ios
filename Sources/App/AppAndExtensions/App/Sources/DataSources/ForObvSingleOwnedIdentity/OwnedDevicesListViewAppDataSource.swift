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
import ObvSingleOwnedIdentity
import OlvidUtils
import ObvUICoreData
import ObvTypes
import ObvCrypto


@MainActor
final class OwnedDevicesListViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
    
    private var ownedDevicesListViewModelStreamManagerForStreamUUID = [UUID: OwnedDevicesListViewModelStreamManager]()
    
}


extension OwnedDevicesListViewAppDataSource: OwnedDevicesListViewDataSource {
    
    func getOwnedDevicesListViewModel(_ view: ObvSingleOwnedIdentity.OwnedDevicesListView, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvSingleOwnedIdentity.OwnedDevicesListView.Model>) {
        let streamManager = OwnedDevicesListViewModelStreamManager(ownedCryptoId: ownedCryptoId, context: backgroundContext)
        let (streamUUID, stream) = try await streamManager.startStream()
        self.ownedDevicesListViewModelStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }
    
    func finishOwnedDevicesListViewModel(_ view: ObvSingleOwnedIdentity.OwnedDevicesListView, streamUUID: UUID) {
        if let streamManager = ownedDevicesListViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
    }
    
}


extension OwnedDevicesListViewAppDataSource {
    
    private final class OwnedDevicesListViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvSingleOwnedIdentity.OwnedDevicesListView.Model, PersistedObvOwnedIdentity>, @unchecked Sendable {
     
        init(ownedCryptoId: ObvCryptoId, context: NSManagedObjectContext) {
            let frc = PersistedObvOwnedIdentity.getFetchedResultsController(ownedCryptoId: ownedCryptoId, within: context)
            super.init(frc: frc)
        }
        
        override func createModel(fetchedObjects: [PersistedObvOwnedIdentity]) throws -> ObvSingleOwnedIdentity.OwnedDevicesListView.Model {
            assert(fetchedObjects.count <= 1)
            guard let ownedIdentity = fetchedObjects.first else {
                throw ObvError.couldFindOwnedIdentity
            }
            let model: ObvSingleOwnedIdentity.OwnedDevicesListView.Model = try .init(ownedIdentity: ownedIdentity)
            return model
        }
    
        enum ObvError: Error {
            case couldFindOwnedIdentity
        }
    }
    
}


extension ObvSingleOwnedIdentity.OwnedDevicesListView.Model {
    
    init(ownedIdentity: PersistedObvOwnedIdentity) throws {
        
        let currentDeviceUID = try ownedIdentity.currentDevice?.deviceUID
        let otherOwnedDeviceUIDs = try ownedIdentity.sortedDevices
            .filter({ $0.identifier != ownedIdentity.currentDevice?.identifier })
            .compactMap { try $0.deviceUID }
        
        let ownedDeviceUIDs: [UID] = [currentDeviceUID].compactMap({$0}) + otherOwnedDeviceUIDs
        
        self.init(ownedDeviceUIDs: ownedDeviceUIDs)
        
    }
    
}
