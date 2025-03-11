/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import OSLog
import OlvidUtils
import ObvUICoreData
import ObvTypes
import ObvCrypto


/// This operation serves a purpose when transmitting a "start call" message for the initiation of a call. Just prior to dispatching said signal, we aim to ascertain whether or not the recipient does not correspond with any existing profile on this specific device.
/// If that proves true, our intent is to omit this very device from the collection of devices receiving the "start call" message. This operation permits us to identify if the intended receiver matches any owned identities present on this gadget and, should it be so,
/// subsequently determine the current device's unique identifier.
final class DetermineCurrentDeviceUIDIfIdentityIsOwnedOperation: ContextualOperationWithSpecificReasonForCancel<DetermineCurrentDeviceUIDIfIdentityIsOwnedOperation.ReasonForCancel>, @unchecked Sendable {

    private let cryptoId: ObvCryptoId

    init(cryptoId: ObvCryptoId) {
        self.cryptoId = cryptoId
        super.init()
    }
    
    private(set) var currentDeviceUID: UID?
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {

        do {
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: cryptoId, within: obvContext.context) else {
                // The identity is not owned, there is no current owned device to return
                return
            }
            guard let currentDeviceIdentifier = ownedIdentity.devices.filter({ $0.secureChannelStatus == .currentDevice }).first?.deviceIdentifier else {
                assertionFailure()
                return cancel(withReason: .couldNotFindCurrentDevice)
            }
            guard let deviceUID = UID(uid: currentDeviceIdentifier) else {
                assertionFailure()
                return cancel(withReason: .couldNotParseCurrentDeviceIdentifier)
            }
            self.currentDeviceUID = deviceUID
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }

    }

    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case couldNotFindCurrentDevice
        case couldNotParseCurrentDeviceIdentifier

        var logType: OSLogType {
            switch self {
            case .coreDataError, .couldNotFindCurrentDevice, .couldNotParseCurrentDeviceIdentifier:
                return .fault
            }
        }
        
        var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .couldNotFindCurrentDevice:
                return "Could not find current device"
            case .couldNotParseCurrentDeviceIdentifier:
                return "Could not parse current device identifier"
            }
        }

        
    }

}


