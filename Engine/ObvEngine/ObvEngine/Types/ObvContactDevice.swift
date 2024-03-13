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
import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils


public struct ObvContactDevice: Hashable, CustomStringConvertible {
    
    public let deviceUID: UID
    public let contactIdentifier: ObvContactIdentifier
    public let secureChannelStatus: SecureChannelStatus

    public var identifier: Data {
        deviceUID.raw
    }
    
    public var deviceIdentifier: ObvContactDeviceIdentifier {
        .init(contactIdentifier: contactIdentifier, deviceUID: deviceUID)
    }
    
    public enum SecureChannelStatus {
        case creationInProgress
        case created
    }

    init(remoteDeviceUid: UID, contactIdentifier: ObvContactIdentifier, secureChannelStatus: SecureChannelStatus) {
        self.deviceUID = remoteDeviceUid
        self.contactIdentifier = contactIdentifier
        self.secureChannelStatus = secureChannelStatus
    }
    
}


// MARK: Implementing CustomStringConvertible
extension ObvContactDevice {
    public var description: String {
        return "ObvContactDevice<\(contactIdentifier.description), \(identifier.description)>"
    }
}
