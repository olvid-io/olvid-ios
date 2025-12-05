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
import ObvAppTypes


public struct ObvGroupLightweightModel: Sendable, Equatable {
    let ownedIdentityIsAdmin: Bool
    let groupType: ObvGroupType?
    let updateInProgressDuringGroupEdition: Bool // Always false during group creation
    let isKeycloakManaged: Bool
    
    public init(ownedIdentityIsAdmin: Bool, groupType: ObvGroupType?, updateInProgressDuringGroupEdition: Bool, isKeycloakManaged: Bool) {
        self.ownedIdentityIsAdmin = ownedIdentityIsAdmin
        self.groupType = groupType
        self.updateInProgressDuringGroupEdition = updateInProgressDuringGroupEdition
        self.isKeycloakManaged = isKeycloakManaged
    }
    
}
