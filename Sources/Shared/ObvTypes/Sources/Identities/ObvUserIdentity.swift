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


public enum ObvUserIdentity {
    
    case owned(ObvOwnedIdentity)
    case contact(ObvContactIdentity)
    
    public var cryptoId: ObvCryptoId {
        switch self {
        case .owned(let obvOwnedIdentity):
            obvOwnedIdentity.cryptoId
        case .contact(let obvContactIdentity):
            obvContactIdentity.cryptoId
        }
    }
    
    public var currentIdentityDetails: ObvIdentityDetails {
        switch self {
        case .owned(let obvOwnedIdentity):
            return obvOwnedIdentity.currentIdentityDetails
        case .contact(let obvContactIdentity):
            return obvContactIdentity.currentIdentityDetails
        }
    }
    
    public var coreDetails: ObvIdentityCoreDetails {
        self.currentIdentityDetails.coreDetails
    }
    
    public var personNameComponents: PersonNameComponents {
        self.coreDetails.personNameComponents
    }
    
    public var photoURL: URL? {
        self.currentIdentityDetails.photoURL
    }
    
    public var isOwnedIdentity: Bool {
        switch self {
        case .owned: return true
        case .contact: return false
        }
    }
    
}
