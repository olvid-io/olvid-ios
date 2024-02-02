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

/// Used to inform the app about the result of a call to the owned device discovery server method.
public struct ObvOwnedDeviceDiscoveryResult {
    
    public let devices: Set<Device>
    public let isMultidevice: Bool

    public init(devices: Set<Device>, isMultidevice: Bool) {
        self.devices = devices
        self.isMultidevice = isMultidevice
    }

    public struct Device: Hashable, Identifiable {

        public let identifier: Data
        public let expirationDate: Date?
        public let latestRegistrationDate: Date?
        public let name: String?
        
        public var id: Data {
            identifier
        }
        
        public init(identifier: Data, expirationDate: Date?, latestRegistrationDate: Date?, name: String?) {
            self.identifier = identifier
            self.expirationDate = expirationDate
            self.latestRegistrationDate = latestRegistrationDate
            self.name = name
        }
        
    }
    
}
