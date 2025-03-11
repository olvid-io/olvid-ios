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
import ObvUICoreDataStructs

// MARK: - Thread safe structure

extension PersistedLocation {
 
    public func toStructure() throws -> PersistedLocationStructure {

        if self is PersistedLocationContinuous {
            return PersistedLocationStructure(type: LocationJSON.LocationSharingType.SHARING.rawValue,
                                              address: self.address)
        } else if self is PersistedLocationOneShot {
            return PersistedLocationStructure(type: LocationJSON.LocationSharingType.SEND.rawValue,
                                              address: self.address)
        } else {
            return PersistedLocationStructure(type: LocationJSON.LocationSharingType.END_SHARING.rawValue,
                                              address: self.address)
        }
        
    }
}
