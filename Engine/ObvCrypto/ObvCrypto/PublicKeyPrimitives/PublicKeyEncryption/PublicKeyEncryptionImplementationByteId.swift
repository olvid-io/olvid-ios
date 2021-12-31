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

public enum PublicKeyEncryptionImplementationByteId: UInt8 {
    case KEM_ECIES_MDC_and_DEM_CTR_AES_256_then_HMAC_SHA_256 = 0x00
    case KEM_ECIES_Curve25519_and_DEM_CTR_AES_256_then_HMAC_SHA_256 = 0x01
    
    public var algorithmImplementation: PublicKeyEncryptionConcrete.Type {
        switch self {
        case .KEM_ECIES_MDC_and_DEM_CTR_AES_256_then_HMAC_SHA_256:
            return ECIESwithMDCandDEMwithCTRAES256thenHMACSHA256.self as PublicKeyEncryptionConcrete.Type
        case .KEM_ECIES_Curve25519_and_DEM_CTR_AES_256_then_HMAC_SHA_256:
            return ECIESwithCurve25519andDEMwithCTRAES256thenHMACSHA256.self as PublicKeyEncryptionConcrete.Type
        }
    }
    
}
