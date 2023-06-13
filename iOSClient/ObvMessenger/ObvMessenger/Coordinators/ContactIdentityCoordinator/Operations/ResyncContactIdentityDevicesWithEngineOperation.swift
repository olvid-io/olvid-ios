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


final class ResyncContactIdentityDevicesWithEngineOperation: ContextualOperationWithSpecificReasonForCancel<ResyncContactIdentityDevicesWithEngineOperationReasonForCancel> {

    let ownedCryptoId: ObvCryptoId
    let contactCryptoId: ObvCryptoId
    let obvEngine: ObvEngine

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "ResyncContactIdentityDevicesWithEngineOperation")
    
    init(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId, obvEngine: ObvEngine) {
        self.ownedCryptoId = ownedCryptoId
        self.contactCryptoId = contactCryptoId
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main() {

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        let engineContactDevices: Set<ObvContactDevice>
        do {
            engineContactDevices = try obvEngine.getAllObliviousChannelsEstablishedWithContactIdentity(with: contactCryptoId, ofOwnedIdentyWith: ownedCryptoId)
        } catch {
            os_log("Could not get all Oblivious Channels established with contact. Could not sync with engine.", log: Self.log, type: .fault)
            return cancel(withReason: .couldNotGetAllObliviousChannelsEstablishedWithContactIdentity(error: error))
        }
        
        obvContext.performAndWait {
            
            do {
                
                guard let persistedOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: obvContext.context) else {
                    os_log("Could not get the persisted owned identity", log: Self.log, type: .fault)
                    assertionFailure()
                    return cancel(withReason: .couldNotFindPersistedObvOwnedIdentity)
                }
                
                guard let persistedContactIdentity = try PersistedObvContactIdentity.get(cryptoId: contactCryptoId, ownedIdentity: persistedOwnedIdentity, whereOneToOneStatusIs: .any) else {
                    os_log("Could not get the persisted obv contact identity", log: Self.log, type: .fault)
                    assertionFailure()
                    return cancel(withReason: .couldNotFindPersistedContact)
                }
                
                let localContactDevicesIdentifiers = Set(persistedContactIdentity.devices.map { $0.identifier })
                let missingDevices = engineContactDevices.filter { !localContactDevicesIdentifiers.contains($0.identifier) }
                for missingDevice in missingDevices {
                    try persistedContactIdentity.insert(missingDevice)
                }
                
                let engineContactDeviceIdentifiers = engineContactDevices.map { $0.identifier }
                let identifiersOfDevicesToRemove = localContactDevicesIdentifiers.filter { !engineContactDeviceIdentifiers.contains($0) }
                for contactDeviceIdentifier in identifiersOfDevicesToRemove {
                    try PersistedObvContactDevice.delete(contactDeviceIdentifier: contactDeviceIdentifier, contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId, within: obvContext.context)
                }
                                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

        }

    }
}



enum ResyncContactIdentityDevicesWithEngineOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case contextIsNil
    case couldNotGetAllObliviousChannelsEstablishedWithContactIdentity(error: Error)
    case couldNotFindPersistedObvOwnedIdentity
    case couldNotFindPersistedContact

    var logType: OSLogType {
        switch self {
        case .coreDataError,
             .contextIsNil,
             .couldNotFindPersistedObvOwnedIdentity,
             .couldNotFindPersistedContact,
             .couldNotGetAllObliviousChannelsEstablishedWithContactIdentity:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotGetAllObliviousChannelsEstablishedWithContactIdentity(error: let error):
            return "Could not get all oblivious channels established with contact identity: \(error.localizedDescription)"
        case .couldNotFindPersistedObvOwnedIdentity:
            return "Could not find persisted owned identity"
        case .couldNotFindPersistedContact:
            return "Could not find contact"
        }
    }

}
