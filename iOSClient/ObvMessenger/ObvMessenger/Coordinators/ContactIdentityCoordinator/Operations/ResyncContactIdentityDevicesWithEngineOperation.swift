/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import OlvidUtils
import os.log
import ObvTypes
import ObvEngine
import ObvUICoreData
import CoreData


final class ResyncContactIdentityDevicesWithEngineOperation: ContextualOperationWithSpecificReasonForCancel<ResyncContactIdentityDevicesWithEngineOperationReasonForCancel> {

    let contactIdentifier: ObvContactIdentifier
    let obvEngine: ObvEngine

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "ResyncContactIdentityDevicesWithEngineOperation")
    
    init(contactIdentifier: ObvContactIdentifier, obvEngine: ObvEngine) {
        self.contactIdentifier = contactIdentifier
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        let engineContactDevices: Set<ObvContactDevice>
        do {
            engineContactDevices = try obvEngine.getAllObvContactDevicesOfContact(with: contactIdentifier)
        } catch {
            os_log("Could not get all Oblivious Channels established with contact. Could not sync with engine. This is ok if the contact was just deleted.", log: Self.log, type: .fault)
            return cancel(withReason: .couldNotGetContactDevicesFromEngine(error: error))
        }
        
        do {
            
            guard let persistedContactIdentity = try PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: obvContext.context) else {
                os_log("The contact cannot be found, it might be added in a few seconds.", log: Self.log, type: .error)
                return
            }
            
            var objectIDsOfDevicesToRefreshInViewContext = Set(persistedContactIdentity.devices.map({ $0.objectID }))
            
            try persistedContactIdentity.synchronizeDevices(with: engineContactDevices)
            
            objectIDsOfDevicesToRefreshInViewContext.formUnion(Set(persistedContactIdentity.devices.map({ $0.objectID })))
            let objectIdOfContact = persistedContactIdentity.objectID
            
            do {
                try? obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else { return }
                    DispatchQueue.main.async {
                        let devicesInViewContext = ObvStack.shared.viewContext.registeredObjects
                            .filter { object in
                                objectIDsOfDevicesToRefreshInViewContext.contains(where: { $0 == object.objectID })
                            }
                        devicesInViewContext.forEach { object in
                            ObvStack.shared.viewContext.refresh(object, mergeChanges: false)
                        }
                        if let contactInViewContext = ObvStack.shared.viewContext.registeredObjects.first(where: { $0.objectID == objectIdOfContact }) {
                            ObvStack.shared.viewContext.refresh(contactInViewContext, mergeChanges: false)
                        }
                        
                    }
                }
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
}



enum ResyncContactIdentityDevicesWithEngineOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case contextIsNil
    case couldNotGetContactDevicesFromEngine(error: Error)
    case couldNotFindPersistedObvOwnedIdentity
    case couldNotFindPersistedContact

    var logType: OSLogType {
        switch self {
        case .coreDataError,
             .contextIsNil,
             .couldNotFindPersistedObvOwnedIdentity,
             .couldNotFindPersistedContact:
            return .fault
        case .couldNotGetContactDevicesFromEngine:
            return .error
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotGetContactDevicesFromEngine(error: let error):
            return "Could not get contact devices from engine: \(error.localizedDescription)"
        case .couldNotFindPersistedObvOwnedIdentity:
            return "Could not find persisted owned identity"
        case .couldNotFindPersistedContact:
            return "Could not find contact"
        }
    }

}
