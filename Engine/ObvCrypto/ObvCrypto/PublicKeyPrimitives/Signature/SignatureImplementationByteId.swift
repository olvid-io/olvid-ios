/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

public enum SignatureImplementationByteId: UInt8 {
    case EC_SDSA_with_MDC = 0x00
    case EC_SDSA_with_Curve25519 = 0x01
    
    var algorithmImplementation: SignatureConcrete.Type {
        switch self {
        case .EC_SDSA_with_MDC:
            return SignatureECSDSA256overMDC.self as SignatureConcrete.Type
        case .EC_SDSA_with_Curve25519:
            return SignatureECSDSA256overCurve25519.self as SignatureConcrete.Type
        }
    }
}
