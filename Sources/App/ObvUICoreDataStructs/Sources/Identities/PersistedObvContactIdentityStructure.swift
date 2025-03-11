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
import ObvCrypto


public struct PersistedObvContactIdentityStructure: Hashable, Equatable {
    
    public let cryptoId: ObvCryptoId
    public let fullDisplayName: String
    public let customOrFullDisplayName: String
    public let customOrNormalDisplayName: String
    public let displayPhotoURL: URL?
    public let personNameComponents: PersonNameComponents
    public let ownedIdentity: PersistedObvOwnedIdentityStructure
    public let devices: Set<PersistedObvContactDeviceStructure>
    
    public var contactIdentifier: ObvContactIdentifier {
        .init(contactCryptoId: cryptoId, ownedCryptoId: ownedIdentity.cryptoId)
    }
    
    public var contactDeviceUIDs: Set<UID> {
        Set(devices.map(\.deviceUID))
    }
    
    // Initializer
    
    public init(cryptoId: ObvCryptoId, fullDisplayName: String, customOrFullDisplayName: String, customOrNormalDisplayName: String, displayPhotoURL: URL?, personNameComponents: PersonNameComponents, ownedIdentity: PersistedObvOwnedIdentityStructure, contactDevices: Set<PersistedObvContactDeviceStructure>) {
        self.cryptoId = cryptoId
        self.fullDisplayName = fullDisplayName
        self.customOrFullDisplayName = customOrFullDisplayName
        self.displayPhotoURL = displayPhotoURL
        self.personNameComponents = personNameComponents
        self.ownedIdentity = ownedIdentity
        self.customOrNormalDisplayName = customOrNormalDisplayName
        self.devices = contactDevices
    }
    
    // Hashable and equatable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(contactIdentifier)
    }
    
    public static func == (lhs: PersistedObvContactIdentityStructure, rhs: PersistedObvContactIdentityStructure) -> Bool {
        lhs.contactIdentifier == rhs.contactIdentifier
    }
    
}
