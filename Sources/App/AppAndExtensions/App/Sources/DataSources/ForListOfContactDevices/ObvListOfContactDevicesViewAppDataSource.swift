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
import ObvCells
import ObvTypes
import OlvidUtils
import ObvUICoreData


final class ObvListOfContactDevicesViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var contactDeviceViewModelStreamManagerForStreamUUID = [UUID: ContactDeviceViewModelStreamManager]()
    private var listOfContactDevicesViewModelStreamManagerForStreamUUID = [UUID: ListOfContactDevicesViewModelStreamManager]()

    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        assert(viewContext.concurrencyType == .mainQueueConcurrencyType)
        assert(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
    
}


extension ObvListOfContactDevicesViewAppDataSource: ObvContactDeviceViewDataSource {
    
    func getAsyncStreamOfObvContactDeviceViewModel(_ view: ObvCells.ObvContactDeviceView, contactDeviceIdentifier: ObvTypes.ObvContactDeviceIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvCells.ObvContactDeviceView.Model>) {
        let manager = ContactDeviceViewModelStreamManager(contactDeviceIdentifier: contactDeviceIdentifier, context: backgroundContext)
        contactDeviceViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfObvContactDeviceViewModel(_ view: ObvCells.ObvContactDeviceView, streamUUID: UUID) {
        guard let manager = contactDeviceViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
}


extension ObvListOfContactDevicesViewAppDataSource: ObvListOfContactDevicesViewDataSource {
    
    func getAsyncStreamOfObvListOfContactDevicesViewModel(_ view: ObvCells.ObvListOfContactDevicesView, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvCells.ObvListOfContactDevicesView.Model>) {
        let manager = ListOfContactDevicesViewModelStreamManager(contactIdentifier: contactIdentifier, context: backgroundContext)
        listOfContactDevicesViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try await manager.startStream()
    }
    
    func finishAsyncStreamOfObvListOfContactDevicesViewModel(_ view: ObvCells.ObvListOfContactDevicesView, streamUUID: UUID) {
        guard let manager = listOfContactDevicesViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) else { return }
        manager.finishStream()
    }
    
}


// MARK: - Internal managers

extension ObvListOfContactDevicesViewAppDataSource {
    
    private final class ListOfContactDevicesViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvCells.ObvListOfContactDevicesView.Model, PersistedObvContactIdentity>, @unchecked Sendable {
        
        init(contactIdentifier: ObvTypes.ObvContactIdentifier, context: NSManagedObjectContext) {
            let frc = PersistedObvContactIdentity.getFetchedResultsControllerForContactIdentifier(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: context)
            super.init(frc: frc)
        }
        
        override func createModel(fetchedObjects: [PersistedObvContactIdentity]) throws -> ObvListOfContactDevicesView.Model {
            assert(fetchedObjects.count <= 1)
            guard let contact = fetchedObjects.first else {
                throw ObvError.couldNotFindContact
            }
            return try .init(contact: contact)
        }
        
        enum ObvError: Error {
            case couldNotFindContact
        }
        
    }
    
}

extension ObvListOfContactDevicesViewAppDataSource {
    
    private final class ContactDeviceViewModelStreamManager: ObvDataSourceStreamManagerWithOneFetchedResultsController<ObvCells.ObvContactDeviceView.Model, PersistedObvContactDevice>, @unchecked Sendable {
        
        init(contactDeviceIdentifier: ObvTypes.ObvContactDeviceIdentifier, context: NSManagedObjectContext) {
            let frc = PersistedObvContactDevice.getFetchedResultsController(contactDeviceIdentifier: contactDeviceIdentifier, within: context)
            super.init(frc: frc)
        }

        
        override func createModel(fetchedObjects: [PersistedObvContactDevice]) throws -> ObvContactDeviceView.Model {
            
            assert(fetchedObjects.count <= 1)
            
            guard let contactDevice = fetchedObjects.first else {
                // This can happen when clearing all the contact's devices
                throw ObvError.couldNotFetchContactDevice
            }
            
            let model = try ObvContactDeviceView.Model(contactDevice: contactDevice)
            
            return model
            
        }
        
        
        enum ObvError: Error {
            case couldNotFetchContactDevice
        }
        
    }
    
    
    
}



// MARK: - ObvContactDeviceView.Model from PersistedObvContactDevice


extension ObvContactDeviceView.Model {
    
    init(contactDevice: PersistedObvContactDevice) throws {
        
        let contactDeviceIdentifier = try contactDevice.contactDeviceIdentifier
        let name = contactDevice.name
        
        
        guard let status = contactDevice.secureChannelStatus else {
            assertionFailure()
            throw ObvErrorForObvContactDeviceViewModel.persistedObvContactDeviceHasNoChannelStatus
        }
        let secureChannelStatus: ObvContactDeviceView.Model.SecureChannelStatus
        switch status {
        case .creationInProgress(preKeyAvailable: let preKeyAvailable):
            secureChannelStatus = .creationInProgress(preKeyAvailable: preKeyAvailable)
        case .created(preKeyAvailable: let preKeyAvailable):
            secureChannelStatus = .created(preKeyAvailable: preKeyAvailable)
        }
        
        self.init(contactDeviceIdentifier: contactDeviceIdentifier,
                  name: name,
                  secureChannelStatus: secureChannelStatus)
        
    }
 
    enum ObvErrorForObvContactDeviceViewModel: Error {
        case persistedObvContactDeviceHasNoChannelStatus
    }
    
}


// MARK: - ObvListOfContactDevicesView.Model from PersistedObvContactIdentity

extension ObvListOfContactDevicesView.Model {
    
    init(contact: PersistedObvContactIdentity) throws {
        let contactIdentifier = try contact.obvContactIdentifier
        let contactDisplayName = contact.customOrShortDisplayName
        let contactDeviceIdentifiers: [ObvContactDeviceIdentifier] = try contact.devices.map { device in
            try device.contactDeviceIdentifier
        }
        self.init(contactIdentifier: contactIdentifier,
                  contactDisplayName: contactDisplayName,
                  contactDeviceIdentifiers: contactDeviceIdentifiers)
    }
    
}
