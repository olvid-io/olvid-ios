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

public protocol MACKey: SymmetricKey {
    var data: Data { get } // Such that data.count >= length (declared in SymmetricKey). Note the semantic of length changes here, since it actually is a minimum key length.
    var algorithmImplementationByteId: MACImplementationByteId { get }
}

extension MACKey {
    
    var algorithmClass: CryptographicAlgorithmClassByteId {
        return .mac
    }
    
    var algorithmImplementationByteId: MACImplementationByteId {
        return MACImplementationByteId(rawValue: self.algorithmImplementationByteIdValue)!
    }
}

public final class MACKeyDecoder {
    public static func decode(_ encodedKey: ObvEncoded) -> MACKey? {
        guard encodedKey.byteId == .symmetricKey else { return nil }
        guard let (algorithmClassByteId, implementationByteIdValue, obvDic) = CryptographicKeyDecoder.decode(encodedKey) else { return nil }
        guard algorithmClassByteId == .mac else { return nil }
        guard let implementationByteId = MACImplementationByteId(rawValue: implementationByteIdValue) else { return nil }
        switch implementationByteId {
        case .HMAC_With_SHA256:
            return HMACWithSHA256Key(obvDictionaryOfInternalElements: obvDic)
        }
    }
}

struct HMACWithSHA256Key: MACKey, Equatable {
    
    private static let obvDictionaryKey = "mackey".data(using: .utf8)!
    
    var obvDictionaryOfInternalElements: ObvDictionary {
        return [HMACWithSHA256Key.obvDictionaryKey: data.encode()]
    }
    
    init?(obvDictionaryOfInternalElements obvDict: ObvDictionary) {
        guard let encodedData = obvDict[HMACWithSHA256Key.obvDictionaryKey] else { return nil }
        guard let data = Data(encodedData) else { return nil }
        self.init(data: data)
    }
    
    let algorithmImplementationByteIdValue = MACImplementationByteId.HMAC_With_SHA256.rawValue
    
    let data: Data
    
    static let length = 32
    
    init?(data: Data) {
        guard data.count >= HMACWithSHA256Key.length else { return nil }
        self.data = data
    }
}

// Implementing Equatable
extension HMACWithSHA256Key {
    static func == (lhs: HMACWithSHA256Key, rhs: HMACWithSHA256Key) -> Bool {
        return lhs.data == rhs.data
    }
}

// Implementing ObvDecodable
extension HMACWithSHA256Key {
    init?(_ obvEncoded: ObvEncoded) {
        guard let key = MACKeyDecoder.decode(obvEncoded) as? HMACWithSHA256Key else { return nil }
        self.init(data: key.data)
    }
}
