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

public enum AuthenticatedEncryptionImplementationByteId: UInt8 {
    case CTR_AES_256_THEN_HMAC_SHA_256 = 0x00
    
    public var algorithmImplementation: AuthenticatedEncryptionConcrete.Type {
        switch self {
        case .CTR_AES_256_THEN_HMAC_SHA_256:
            return AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256.self as AuthenticatedEncryptionConcrete.Type
        }
    }
}
