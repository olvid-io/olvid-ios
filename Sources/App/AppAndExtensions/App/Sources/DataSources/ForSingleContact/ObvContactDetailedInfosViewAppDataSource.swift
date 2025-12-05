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
import ObvSingleContact
import OlvidUtils
import ObvTypes
import ObvUICoreData



final class ObvContactDetailedInfosViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    
    private var contactDetailedInfosViewModelStreamManagerForStreamUUID: [UUID: ObvContactDetailedInfosViewModelStreamManager] = [:]
    
    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
    
}


extension ObvContactDetailedInfosViewAppDataSource: ObvContactDetailedInfosViewDataSource {
    
    func getAsyncSequenceOfContactDetailedInfosViewModel(_ view: ObvSingleContact.ObvContactDetailedInfosView, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvSingleContact.ObvContactDetailedInfosView.Model>) {
        let manager = ObvContactDetailedInfosViewModelStreamManager(contactIdentifier: contactIdentifier, context: backgroundContext)
        contactDetailedInfosViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncSequenceOfContactDetailedInfosViewModel(_ view: ObvSingleContact.ObvContactDetailedInfosView, streamUUID: UUID) {
        guard let manager = contactDetailedInfosViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
}


extension ObvContactDetailedInfosViewAppDataSource {
    
    private final class ObvContactDetailedInfosViewModelStreamManager: ObvDataSourceStreamManagerWithTwoFetchedResultsController<ObvContactDetailedInfosView.Model, PersistedObvContactIdentity, PersistedObvContactDevice>, @unchecked Sendable {
        
        init(contactIdentifier: ObvTypes.ObvContactIdentifier, context: NSManagedObjectContext) {
            let frc1 = PersistedObvContactIdentity.getFetchedResultsControllerForContactIdentifier(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: context)
            let frc2 = PersistedObvContactDevice.getFetchedResultsController(contactIdentifier: contactIdentifier, within: context)
            super.init(frc1: frc1, frc2: frc2)
        }
        
        
        override func createModel(fetchedObjects1: [PersistedObvContactIdentity], fetchedObjects2: [PersistedObvContactDevice]) throws -> ObvContactDetailedInfosView.Model {
            
            assert(fetchedObjects1.count <= 1)
            assert(fetchedObjects1.first?.devices.count == fetchedObjects2.count)
            
            guard let contact = fetchedObjects1.first else {
                throw ObvError.contactIsNil
            }
            
            return try .init(contact: contact)
            
        }
        
        enum ObvError: Error {
            case contactIsNil
        }
        
    }
    
}


extension ObvSingleContact.ObvContactDetailedInfosView.Model {
    
    init(contact: PersistedObvContactIdentity) throws {
        
        guard let identityCoreDetails = contact.identityCoreDetails else {
            throw ObvContactDetailedInfosViewModelError.identityCoreDetailsAreNil
        }
        
        let devices: [ObvContactDetailedInfosView.Model.Device] = contact.devices.map { .init(device: $0) }
        
        self.init(avatarModel: contact.avatarViewModel,
                  identityCoreDetails: identityCoreDetails,
                  customDisplayName: contact.customDisplayName,
                  isActive: contact.isActive,
                  isCertifiedByOwnKeycloak: contact.isCertifiedByOwnKeycloak,
                  wasRecentlyOnline: contact.wasRecentlyOnline,
                  capabilitites: contact.allCapabilitites,
                  devices: devices)
        
    }
    
    enum ObvContactDetailedInfosViewModelError: Error {
        case identityCoreDetailsAreNil
    }
    
}


extension ObvSingleContact.ObvContactDetailedInfosView.Model.Device {
    
    init(device: PersistedObvContactDevice) {
        
        let secureChannelStatus: ObvSingleContact.ObvContactDetailedInfosView.Model.Device.SecureChannelStatus
        if let status = device.secureChannelStatus {
            switch status {
            case .creationInProgress(let preKeyAvailable):
                secureChannelStatus = .creationInProgress(preKeyAvailable: preKeyAvailable)
            case .created(let preKeyAvailable):
                secureChannelStatus = .created(preKeyAvailable: preKeyAvailable)
            }
        } else {
            assertionFailure()
            secureChannelStatus = .unavailable
        }
        self.init(identifier: device.identifier,
                  secureChannelStatus: secureChannelStatus)
    }
    
}
