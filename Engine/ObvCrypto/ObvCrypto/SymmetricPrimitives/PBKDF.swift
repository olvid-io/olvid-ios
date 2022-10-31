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
import CommonCrypto
import OlvidUtils

public final class PBKDF: ObvErrorMaker {

    public static var errorDomain: String { "PBKDF" }

    public static func pbkdf2sha256(password: String, salt: Data, rounds: UInt32, derivedKeyLength: Int) throws -> Data {
        let hash = CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256)
        var derivedKey = [UInt8](repeating: 0, count: derivedKeyLength)
        let status: Int32 = salt.withUnsafeBytes { unsafeBytes in
            guard let saltBytes = unsafeBytes.bindMemory(to: UInt8.self).baseAddress else {
                return Int32(kCCMemoryFailure)
            }
            let status: Int32 = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                                     password,
                                                     password.lengthOfBytes(using: .utf8),
                                                     saltBytes,
                                                     salt.count,
                                                     hash,
                                                     rounds,
                                                     &derivedKey,
                                                     derivedKey.count)
            return status
        }
        guard status == Int32(kCCSuccess) else {
            throw makeError(message: "pbkdf2sha256 failed with error: \(status)")
        }
        return Data(derivedKey)
    }


}
