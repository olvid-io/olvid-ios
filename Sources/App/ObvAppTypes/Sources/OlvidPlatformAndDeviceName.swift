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
import ObvTypes


public struct OlvidPlatformAndDeviceName: Sendable {
        
    public let identifier: Data
    public let deviceName: String
    public let platform: OlvidPlatform
    
    public init(identifier: Data, deviceName: String, platform: OlvidPlatform) {
        self.identifier = identifier
        self.deviceName = deviceName
        self.platform = platform
    }
}


extension OlvidPlatformAndDeviceName: Comparable {
    
    /// `OlvidPlatformAndDeviceName` implements `Comparable` as in certain cases (like in `DeviceDeactivationWarningOnBackupRestoreView`), we display
    /// a list of `OlvidPlatformAndDeviceName` instances that may be refreshed. On refresh, we want to make sure that the cells are not reordered, so we always send a sorted
    /// list (sorted according this implementation)
    public static func < (lhs: OlvidPlatformAndDeviceName, rhs: OlvidPlatformAndDeviceName) -> Bool {
        if lhs.deviceName != rhs.deviceName {
            return lhs.deviceName < rhs.deviceName
        } else {
            return lhs.identifier.hexString() < rhs.identifier.hexString()
        }
    }

}
