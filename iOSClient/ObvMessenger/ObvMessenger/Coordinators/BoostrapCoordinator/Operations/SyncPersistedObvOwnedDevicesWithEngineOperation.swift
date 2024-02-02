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
import ObvUICoreData
import CoreData


/// Updates the list of owned devices of all owned identities found at the app level.
final class SyncPersistedObvOwnedDevicesWithEngineOperation: ContextualOperationWithSpecificReasonForCancel<SyncPersistedObvOwnedDevicesWithEngineOperationReasonForCancel> {
    
    private let obvEngine: ObvEngine
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: SyncPersistedObvOwnedIdentitiesWithEngineOperation.self))

    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            // Get the owned identities within the app
            
            let ownedIdentitiesWithApp: [PersistedObvOwnedIdentity]
            do {
                ownedIdentitiesWithApp = try PersistedObvOwnedIdentity.getAll(within: obvContext.context)
            } catch {
                assertionFailure()
                return cancel(withReason: .coreDataError(error: error))
            }
            
            // Loop through all owned identities
            
            for ownedIdentity in ownedIdentitiesWithApp {
                
                // Ask the engine for the latest list of owned devices of the owned identity
                
                let ownedDevicesWithinEngine: Set<ObvOwnedDevice>
                do {
                    ownedDevicesWithinEngine = try obvEngine.getAllOwnedDevicesOfOwnedIdentity(ownedIdentity.cryptoId)
                } catch {
                    // This happens if the owned identity was just deleted
                    return cancel(withReason: .couldNotGetOwnedDevicesFromEngine(error: error))
                }
                
                // Sync the devices of the owned identity
                
                try ownedIdentity.syncWith(ownedDevicesWithinEngine: ownedDevicesWithinEngine)
                
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}


enum SyncPersistedObvOwnedDevicesWithEngineOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case contextIsNil
    case couldNotGetOwnedDevicesFromEngine(error: Error)
    
    public var logType: OSLogType {
        switch self {
        case .coreDataError,
                .contextIsNil:
            return .fault
        case .couldNotGetOwnedDevicesFromEngine:
            return .error
        }
    }
    
    public var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotGetOwnedDevicesFromEngine:
            return "Could not get owned devices within engine."
        }
    }
    
    
}
