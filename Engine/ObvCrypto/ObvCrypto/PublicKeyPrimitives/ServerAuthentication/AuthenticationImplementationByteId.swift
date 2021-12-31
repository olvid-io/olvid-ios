/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

public enum AuthenticationImplementationByteId: UInt8 {
    case Signature_with_EC_SDSA_with_MDC = 0x00
    case Signature_with_EC_SDSA_with_Curve25519 = 0x01
    
    var algorithmImplementation: AuthenticationConcrete.Type {
        switch self {
        case .Signature_with_EC_SDSA_with_MDC:
            return AuthenticationFromSignatureOnMDC.self as AuthenticationConcrete.Type
        case .Signature_with_EC_SDSA_with_Curve25519:
            return AuthenticationFromSignatureOnCurve25519.self as AuthenticationConcrete.Type
        }
    }
}
