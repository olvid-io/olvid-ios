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
import ObvEncoder

protocol BlockCipherKey: SymmetricKey {
    var data: Data { get } // Such that data.count == length (declared in SymmetricKey)
    var algorithmImplementationByteId: BlockCipherImplementationByteId { get }
}

extension BlockCipherKey {
    
    var algorithmClass: CryptographicAlgorithmClassByteId {
        return .blockCipher
    }
    
    var algorithmImplementationByteId: BlockCipherImplementationByteId {
        return BlockCipherImplementationByteId(rawValue: self.algorithmImplementationByteIdValue)!
    }
 
}

final class BlockCipherKeyDecoder {
    static func decode(_ encodedKey: ObvEncoded) -> BlockCipherKey? {
        guard encodedKey.byteId == .symmetricKey else { return nil }
        guard let (algorithmClassByteId, implementationByteIdValue, obvDic) = CryptographicKeyDecoder.decode(encodedKey) else { return nil }
        guard algorithmClassByteId == .blockCipher else { return nil }
        guard let implementationByteId = BlockCipherImplementationByteId(rawValue: implementationByteIdValue) else { return nil }
        switch implementationByteId {
        case .AES_256:
            return AES256Key(obvDictionaryOfInternalElements: obvDic)
        }
    }
}

struct AES256Key: BlockCipherKey, Equatable {
    
    private static let obvDictionaryKey = "enckey".data(using: .utf8)!
    
    var obvDictionaryOfInternalElements: ObvDictionary {
        return [AES256Key.obvDictionaryKey: data.encode()]
    }
    
    init?(obvDictionaryOfInternalElements obvDict: ObvDictionary) {
        guard let encodedData = obvDict[AES256Key.obvDictionaryKey] else { return nil }
        guard let data = Data(encodedData) else { return nil }
        self.init(data: data)
    }
    
    let algorithmImplementationByteIdValue = BlockCipherImplementationByteId.AES_256.rawValue
    
    let data: Data
    
    static let length = 32
    
    init?(data: Data) {
        guard data.count == AES256Key.length else { return nil }
        self.data = data
    }
    
}

// Implementing Equatable
extension AES256Key {
    static func == (lhs: AES256Key, rhs: AES256Key) -> Bool {
        return lhs.data == rhs.data
    }
}

// Implementing ObvDecodable
extension AES256Key {
    init?(_ obvEncoded: ObvEncoded) {
        guard let key = BlockCipherKeyDecoder.decode(obvEncoded) as? AES256Key else { return nil }
        self.init(data: key.data)
    }
}
