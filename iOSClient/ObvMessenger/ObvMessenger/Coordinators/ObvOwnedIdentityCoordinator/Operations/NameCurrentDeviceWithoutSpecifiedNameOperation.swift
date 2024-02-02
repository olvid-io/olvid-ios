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
import CoreData
import ObvUICoreData
import ObvEngine


/// This operation is intended to be executed during bootstrap. Its fetches all current devices that have no specified name and set a default name, based on the model of the physical device.
final class NameCurrentDeviceWithoutSpecifiedNameOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    let obvEngine: ObvEngine
    
    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {

            let obvEngine = self.obvEngine

            let currentOwnedDevices = try PersistedObvOwnedDevice.fetchCurrentPersistedObvOwnedDeviceWithNoSpecifiedName(within: obvContext.context)
            
            for currentOwnedDevice in currentOwnedDevices {

                let deviceIdentifier = currentOwnedDevice.deviceIdentifier
                guard let ownedCryptoId = currentOwnedDevice.ownedIdentity?.cryptoId else { continue }
                let ownedDeviceName = UIDevice.current.preciseModel
                
                Task.detached {
                    try? await obvEngine.requestChangeOfOwnedDeviceName(
                        ownedCryptoId: ownedCryptoId,
                        deviceIdentifier: deviceIdentifier,
                        ownedDeviceName: ownedDeviceName)
                }

            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
