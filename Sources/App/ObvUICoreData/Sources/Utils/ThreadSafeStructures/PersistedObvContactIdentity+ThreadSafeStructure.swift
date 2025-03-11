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
import ObvTypes
import os.log
import ObvSettings
import ObvUICoreDataStructs


// MARK: - Thread safe struct

extension PersistedObvContactIdentity {
    
    public func toStructure() throws -> PersistedObvContactIdentityStructure {
        guard let ownedIdentity = self.ownedIdentity else {
            throw ObvUICoreDataError.contactsOwnedIdentityRelationshipIsNil
        }
        guard let personNameComponents else {
            assertionFailure()
            throw ObvUICoreDataError.personNameComponentsIsNil
        }
        let contactDevices: Set<PersistedObvContactDeviceStructure> = try Set(self.devices.map({ try $0.toStructure() }))
        return .init(cryptoId: self.cryptoId,
                     fullDisplayName: self.fullDisplayName,
                     customOrFullDisplayName: self.customOrFullDisplayName,
                     customOrNormalDisplayName: self.customOrNormalDisplayName,
                     displayPhotoURL: self.displayPhotoURL,
                     personNameComponents: personNameComponents,
                     ownedIdentity: try ownedIdentity.toStructure(),
                     contactDevices: contactDevices)
    }
    
}
