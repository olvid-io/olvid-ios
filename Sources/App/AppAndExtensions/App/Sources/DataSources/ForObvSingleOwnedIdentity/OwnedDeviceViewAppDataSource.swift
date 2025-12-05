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
import ObvUICoreData
import OlvidUtils
import ObvTypes


@MainActor
final class OwnedDeviceViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
    
    private var ownedDeviceViewModelStreamManagerForStreamUUID = [UUID: OwnedDeviceViewModelStreamManager]()
        
}


extension OwnedDeviceViewAppDataSource: OwnedDeviceViewDataSource {
    
    func getAsyncSequenceOfOwnedDeviceViewModel(_ view: ObvSingleOwnedIdentity.OwnedDeviceView, ownedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvSingleOwnedIdentity.OwnedDeviceView.Model>) {
        let streamManager = OwnedDeviceViewModelStreamManager(ownedDeviceIdentifier: ownedDeviceIdentifier, context: backgroundContext)
        let (streamUUID, stream) = try await streamManager.startStream()
        self.ownedDeviceViewModelStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }
    
    func finishAsyncSequenceOfOwnedDeviceViewModel(_ view: ObvSingleOwnedIdentity.OwnedDeviceView, streamUUID: UUID) {
        if let streamManager = ownedDeviceViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
    }
    
}


extension OwnedDeviceViewAppDataSource {
    
    private final class OwnedDeviceViewModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvSingleOwnedIdentity.OwnedDeviceView.Model, PersistedObvOwnedIdentity, PersistedObvOwnedDevice>, @unchecked Sendable {
        
        private let ownedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier
        
        init(ownedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier, context: NSManagedObjectContext) {
            self.ownedDeviceIdentifier = ownedDeviceIdentifier
            // Note we don't restrict to the `ownedDeviceIdentifier` for the frc, as we also need to be informed of any change relating to the "un-expiring" device.
            // We also watch the owned identity as we need to observe changes to the API permissions
            let frc1 = PersistedObvOwnedIdentity.getFetchedResultsController(ownedCryptoId: ownedDeviceIdentifier.ownedCryptoId, within: context)
            let frc2 = PersistedObvOwnedDevice.getFetchedResultsController(ownedCryptoId: ownedDeviceIdentifier.ownedCryptoId, within: context)
            super.init(frc1: frc1, frc2: frc2)
        }

        override func createModel(fetchedObjects1: [PersistedObvOwnedIdentity], fetchedObjects2: [PersistedObvOwnedDevice]) throws -> ObvSingleOwnedIdentity.OwnedDeviceView.Model {
            assert(fetchedObjects1.count <= 1)
            
            guard let ownedIdentity = fetchedObjects1.first else {
                throw ObvError.couldNotFindOwnedIdentity
            }
            
            guard let ownedDevice = fetchedObjects2.first(where: { $0.identifier == ownedDeviceIdentifier.deviceUID.raw }) else {
                throw ObvError.couldNotFindOwnedDevice
            }
            
            let model: ObvSingleOwnedIdentity.OwnedDeviceView.Model = .init(ownedIdentity: ownedIdentity, ownedDevice: ownedDevice)
            
            return model
        }
        
        enum ObvError: Error {
            case couldNotFindOwnedIdentity
            case couldNotFindOwnedDevice
        }
        
    }
    
}


extension ObvSingleOwnedIdentity.OwnedDeviceView.Model {
    
    init(ownedIdentity: PersistedObvOwnedIdentity, ownedDevice: PersistedObvOwnedDevice) {
        assert(ownedDevice.secureChannelStatus != nil)
        assert(ownedIdentity.sortedDevices.contains(ownedDevice))
        
        let expiration: ObvSingleOwnedIdentity.OwnedDeviceView.Model.Expiration?
        if let expirationDate = ownedDevice.expirationDate {
            let deviceWithoutExpiration: ObvSingleOwnedIdentity.OwnedDeviceView.Model.Expiration.DeviceWithoutExpiration?
            if let ownedDeviceWithoutExpiration = ownedIdentity.sortedDevices.first(where: { $0.expirationDate == nil }), let deviceUID = try? ownedDeviceWithoutExpiration.deviceUID {
                deviceWithoutExpiration = .init(deviceUID: deviceUID,
                                                deviceName: ownedDeviceWithoutExpiration.name)
            } else {
                // This seems to happen when changing the device that should stay active.
                // The model is refreshed shortly afterwards.
                deviceWithoutExpiration = nil
            }
            expiration = .init(date: expirationDate,
                               deviceWithoutExpiration: deviceWithoutExpiration)
        } else {
            expiration = nil
        }
        
        let ownedIdentityEffectiveAPIPermissionsContainsMultidevice = ownedIdentity.effectiveAPIPermissions.contains(.multidevice)
        
        self.init(ownedDeviceName: ownedDevice.name,
                  secureChannelStatus: .init(secureChannelStatus: ownedDevice.secureChannelStatus ?? .creationInProgress(preKeyAvailable: false)),
                  latestRegistrationDate: ownedDevice.latestRegistrationDate,
                  ownedIdentityIsActive: ownedDevice.ownedIdentityIsActive,
                  expiration: expiration,
                  ownedIdentityEffectiveAPIPermissionsContainsMultidevice: ownedIdentityEffectiveAPIPermissionsContainsMultidevice)

    }
    
}

extension ObvSingleOwnedIdentity.OwnedDeviceView.Model.SecureChannelStatus {
    
    init(secureChannelStatus: PersistedObvOwnedDevice.SecureChannelStatus) {
        switch secureChannelStatus {
        case .currentDevice:
            self = .currentDevice
        case .creationInProgress(let preKeyAvailable):
            self = .creationInProgress(preKeyAvailable: preKeyAvailable)
        case .created(let preKeyAvailable):
            self = .created(preKeyAvailable: preKeyAvailable)
        }
    }
    
}
