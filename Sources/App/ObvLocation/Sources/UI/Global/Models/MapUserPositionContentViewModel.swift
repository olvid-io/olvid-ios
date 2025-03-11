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
import ObvUIObvCircledInitials
import CoreLocation
import ObvTypes

struct MapUserPositionContentViewModel {
    
    let contactCryptoId: ObvCryptoId
    let userInitialConfiguraton: CircledInitialsConfiguration
    let location: CLLocation
    
    init?(contactCryptoId: ObvCryptoId?,
                 userInitialConfiguraton: CircledInitialsConfiguration?,
                 location: CLLocation) {
        guard let contactCryptoId, let userInitialConfiguraton else { return nil }
        self.contactCryptoId = contactCryptoId
        self.userInitialConfiguraton = userInitialConfiguraton
        self.location = location
    }
}
