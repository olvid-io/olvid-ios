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

public enum DeletionType: Hashable, CaseIterable, Comparable {
    case fromThisDeviceOnly
    case fromAllOwnedDevices
    case fromAllOwnedDevicesAndAllContactDevices
    
    private var sortOrder: Int {
        switch self {
        case .fromThisDeviceOnly: return 0
        case .fromAllOwnedDevices: return 1
        case .fromAllOwnedDevicesAndAllContactDevices: return 2
        }
    }

    public static func < (lhs: DeletionType, rhs: DeletionType) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
    
}
