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
import ObvEncoder

protocol SymmetricEncryptionKey: SymmetricKey {
    var algorithmImplementationByteId: SymmetricEncryptionByteId { get }
}

extension SymmetricEncryptionKey {
    
    var algorithmClass: CryptographicAlgorithmClassByteId {
        return .symmetricEncryption
    }
    
    var algorithmImplementationByteId: SymmetricEncryptionByteId {
        return SymmetricEncryptionByteId(rawValue: self.algorithmImplementationByteIdValue)!
    }

}

final class SymmetricEncryptionKeyDecoder {
    static func decode(_ encodedKey: ObvEncoded) -> SymmetricEncryptionKey? {
        guard encodedKey.byteId == .symmetricKey else { return nil }
        guard let (algorithmClassByteId, implementationByteIdValue, obvDic) = CryptographicKeyDecoder.decode(encodedKey) else { return nil }
        guard algorithmClassByteId == .symmetricEncryption else { return nil }
        guard let implementationByteId = SymmetricEncryptionByteId(rawValue: implementationByteIdValue) else { return nil }
        switch implementationByteId {
        case .SymmetricEncryption_With_AES_256_CTR:
            return SymmetricEncryptionAES256CTRKey(obvDictionaryOfInternalElements: obvDic)
        }
    }
}

struct SymmetricEncryptionAES256CTRKey: SymmetricEncryptionKey, Equatable {
    
    var obvDictionaryOfInternalElements: ObvDictionary {
        return aes256Key.obvDictionaryOfInternalElements
    }
    
    init?(obvDictionaryOfInternalElements obvDict: ObvDictionary) {
        guard let aes256Key = AES256Key(obvDictionaryOfInternalElements: obvDict) else { return nil }
        self.aes256Key = aes256Key
    }
    
    let algorithmImplementationByteIdValue = SymmetricEncryptionByteId.SymmetricEncryption_With_AES_256_CTR.rawValue
    
    static let length = AES256Key.length
    
    let aes256Key: AES256Key
    
    var data: Data {
        return aes256Key.data
    }
    
    init?(data: Data) {
        guard data.count == AES256Key.length else { return nil }
        aes256Key = AES256Key(data: data)!
    }
}

// Implementing equatable
extension SymmetricEncryptionAES256CTRKey {
    static func == (lhs: SymmetricEncryptionAES256CTRKey, rhs: SymmetricEncryptionAES256CTRKey) -> Bool {
        return lhs.aes256Key == rhs.aes256Key
    }
}

// Implementing ObvDecodable
extension SymmetricEncryptionAES256CTRKey {
    init?(_ obvEncoded: ObvEncoded) {
        guard let key = SymmetricEncryptionKeyDecoder.decode(obvEncoded) as? SymmetricEncryptionAES256CTRKey else { return nil }
        self.init(data: key.data)
    }
}
