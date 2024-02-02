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
import ObvEngine
import os.log
import CoreData
import ObvTypes
import ObvUICoreData


final class SyncPersistedObvContactDevicesWithEngineOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let obvEngine: ObvEngine
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: SyncPersistedObvContactDevicesWithEngineOperation.self))

    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        os_log("Syncing Persisted Contacts Devices with Engine Devices", log: log, type: .info)
        
        do {
            
            let ownedIdentities = try PersistedObvOwnedIdentity.getAll(within: obvContext.context)
            
            ownedIdentities.forEach { ownedIdentity in
                
                for contact in ownedIdentity.contacts {
                    
                    guard let contactIdentifier = (try? contact.obvContactIdentifier) else { assertionFailure(); continue }
                    guard let devicesFromEngine = try? obvEngine.getAllObvContactDevicesOfContact(with: contactIdentifier) else { assertionFailure(); continue }
                    
                    do {
                        try contact.synchronizeDevices(with: devicesFromEngine)
                    } catch {
                        assertionFailure(error.localizedDescription)
                        // Continue anyway
                    }
                    
                }
                
            }
            
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
}
