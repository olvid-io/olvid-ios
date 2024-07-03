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

/// Enumerates the cryptographic algorithms classes (or families) potentially exposed to the outside world. This excludes, e.g., block ciphers or hash functions.
///
public enum CryptographicAlgorithmClassByteId: UInt8 {
    // Symmetric primitives
    case symmetricEncryption = 0x00
    case mac = 0x01
    case authenticatedEncryption = 0x02
    case blockCipher = 0x03
    // Assymmetric primitives
    //case DH = 0x10
    case signature = 0x11
    case publicKeyEncryption = 0x12
    case authentication = 0x14
}
