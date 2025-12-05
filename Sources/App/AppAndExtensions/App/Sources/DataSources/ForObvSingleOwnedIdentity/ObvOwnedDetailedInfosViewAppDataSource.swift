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


protocol ObvOwnedDetailedInfosViewAppDataSourceDelegate: AnyObject {
    func getOwnedIdentityKeycloakState(_ dataSource: ObvOwnedDetailedInfosViewAppDataSource, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> ObvKeycloakStateAndUserDetails?
    func getRegisteredKeycloakAPIKey(_ dataSource: ObvOwnedDetailedInfosViewAppDataSource, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> UUID?
}

@MainActor
final class ObvOwnedDetailedInfosViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    private weak var delegate: ObvOwnedDetailedInfosViewAppDataSourceDelegate?

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext, delegate: ObvOwnedDetailedInfosViewAppDataSourceDelegate) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
        self.delegate = delegate
    }

    private var ownedDetailedInfosViewModelStreamManagerForStreamUUID = [UUID: ObvOwnedDetailedInfosViewModelStreamManager]()
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}


extension ObvOwnedDetailedInfosViewAppDataSource: ObvOwnedDetailedInfosViewDataSource {
    
    func getAsyncSequenceOfObvOwnedDetailedInfosViewModel(_ view: ObvSingleOwnedIdentity.ObvOwnedDetailedInfosView, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvSingleOwnedIdentity.ObvOwnedDetailedInfosView.Model>) {
        let streamManager = ObvOwnedDetailedInfosViewModelStreamManager(ownedCryptoId: ownedCryptoId, context: backgroundContext, delegate: self)
        let (streamUUID, stream) = try await streamManager.startStream()
        self.ownedDetailedInfosViewModelStreamManagerForStreamUUID[streamUUID] = streamManager
        return (streamUUID, stream)
    }
    
    func finishAsyncSequenceOfObvOwnedDetailedInfosViewModel(_ view: ObvSingleOwnedIdentity.ObvOwnedDetailedInfosView, streamUUID: UUID) {
        if let streamManager = ownedDetailedInfosViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            streamManager.finishStream()
        }
    }
    
}

extension ObvOwnedDetailedInfosViewAppDataSource: ObvOwnedDetailedInfosViewModelStreamManagerDelegate {
    
    fileprivate func getOwnedIdentityKeycloakState(_ streamManager: ObvOwnedDetailedInfosViewModelStreamManager, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> ObvTypes.ObvKeycloakStateAndUserDetails? {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.getOwnedIdentityKeycloakState(self, ownedCryptoId: ownedCryptoId)
    }

    fileprivate func getRegisteredKeycloakAPIKey(_ streamManager: ObvOwnedDetailedInfosViewAppDataSource.ObvOwnedDetailedInfosViewModelStreamManager, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> UUID? {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.getRegisteredKeycloakAPIKey(self, ownedCryptoId: ownedCryptoId)
    }

}


@MainActor
private protocol ObvOwnedDetailedInfosViewModelStreamManagerDelegate: AnyObject {
    func getOwnedIdentityKeycloakState(_ streamManager: ObvOwnedDetailedInfosViewAppDataSource.ObvOwnedDetailedInfosViewModelStreamManager, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> ObvKeycloakStateAndUserDetails?
    func getRegisteredKeycloakAPIKey(_ streamManager: ObvOwnedDetailedInfosViewAppDataSource.ObvOwnedDetailedInfosViewModelStreamManager, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> UUID?
}

extension ObvOwnedDetailedInfosViewAppDataSource {
        
    fileprivate final class ObvOwnedDetailedInfosViewModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvOwnedDetailedInfosView.Model, PersistedObvOwnedIdentity, PersistedObvOwnedDevice>, @unchecked Sendable {
        
        private let ownedCryptoId: ObvTypes.ObvCryptoId
        private weak var delegate: ObvOwnedDetailedInfosViewModelStreamManagerDelegate?

        private var latestKeycloakStateAndUserDetails: ObvKeycloakStateAndUserDetails?
        private var latestOwnedIdentityKeycloakApiKey: UUID?
        
        init(ownedCryptoId: ObvTypes.ObvCryptoId, context: NSManagedObjectContext, delegate: ObvOwnedDetailedInfosViewModelStreamManagerDelegate) {
            self.ownedCryptoId = ownedCryptoId
            self.delegate = delegate
            let frc1 = PersistedObvOwnedIdentity.getFetchedResultsController(ownedCryptoId: ownedCryptoId, within: context)
            let frc2 = PersistedObvOwnedDevice.getFetchedResultsController(ownedCryptoId: ownedCryptoId, within: context)
            super.init(frc1: frc1, frc2: frc2)
        }
        
        private func refreshLatestKeycloakStateAndUserDetails() {
            Task {
                guard let delegate else { assertionFailure(); return }
                do {
                    self.latestKeycloakStateAndUserDetails = try await delegate.getOwnedIdentityKeycloakState(self, ownedCryptoId: ownedCryptoId)
                    self.latestOwnedIdentityKeycloakApiKey = try await delegate.getRegisteredKeycloakAPIKey(self, ownedCryptoId: ownedCryptoId)
                    try await self.getFetchedObjectsAndYieldModelIfNeeded()
                } catch {
                    assertionFailure()
                }
            }
        }
        
        override func createModel(fetchedObjects1: [PersistedObvOwnedIdentity], fetchedObjects2: [PersistedObvOwnedDevice]) throws -> ObvOwnedDetailedInfosView.Model {
            assert(fetchedObjects1.count <= 1)
            guard let ownedIdentity = fetchedObjects1.first else {
                throw ObvError.couldNotFindOWnedIdentity
            }
            let model = ObvOwnedDetailedInfosView.Model(ownedIdentity: ownedIdentity, latestKeycloakStateAndUserDetails: latestKeycloakStateAndUserDetails, latestOwnedIdentityKeycloakApiKey: latestOwnedIdentityKeycloakApiKey)
            refreshLatestKeycloakStateAndUserDetails()
            return model
        }
        
        enum ObvError: Error {
            case couldNotFindOWnedIdentity
        }
        
    }
    
}


extension ObvSingleOwnedIdentity.ObvOwnedDetailedInfosView.Model {
    
    init(ownedIdentity: PersistedObvOwnedIdentity,
         latestKeycloakStateAndUserDetails: ObvKeycloakStateAndUserDetails?,
         latestOwnedIdentityKeycloakApiKey: UUID?) {
        
        let isKeycloakManaged: IsKeycloakManaged
        if ownedIdentity.isKeycloakManaged {
            isKeycloakManaged = .yes(signedDetails: latestKeycloakStateAndUserDetails?.signedUserDetails,
                                     ownedIdentityKeycloakApiKey: latestOwnedIdentityKeycloakApiKey,
                                     isTransferRestricted: latestKeycloakStateAndUserDetails?.keycloakState.isTransferRestricted)
        } else {
            isKeycloakManaged = .no
        }
        
        let devices: [Device] = ownedIdentity.sortedDevices.map { .init(ownedDevice: $0) }
        
        self.init(avatarModel: ownedIdentity.avatarViewModel,
                  identityCoreDetails: ownedIdentity.identityCoreDetails,
                  isActive: ownedIdentity.isActive,
                  isKeycloakManaged: isKeycloakManaged,
                  capabilitites: ownedIdentity.allCapabilitites,
                  devices: devices)
    }
    
}


extension ObvSingleOwnedIdentity.ObvOwnedDetailedInfosView.Model.Device {
    
    init(ownedDevice: PersistedObvOwnedDevice) {
        
        let secureChannelStatus: SecureChannelStatus?
        if let ownedDeviceSecureChannelStatus = ownedDevice.secureChannelStatus {
            secureChannelStatus = .init(secureChannelStatus: ownedDeviceSecureChannelStatus)
        } else {
            secureChannelStatus = nil
        }
        
        self.init(identifier: ownedDevice.identifier,
                  secureChannelStatus: secureChannelStatus ?? .unavailable)
        
    }
    
}


extension ObvOwnedDetailedInfosView.Model.Device.SecureChannelStatus {
    
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
