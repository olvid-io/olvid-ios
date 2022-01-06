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

/// Describe a cryptographic key that may be exposed to the outside world. The keys that are not exposed (such as block cipher keys) do not implement this protocol.
public protocol CryptographicKey: ObvCodable {
    var algorithmClass: CryptographicAlgorithmClassByteId { get }
    var algorithmImplementationByteIdValue: UInt8 { get }
    
    var obvDictionaryOfInternalElements: ObvDictionary { get }
    
    var correspondingObvEncodedByteId: ByteIdOfObvEncoded { get } // Each key must indicate the ObvEncodedByteId to use when encoding this key

}

extension CryptographicKey where Self: Equatable {
    func isEqualTo(other: CryptographicKey) -> Bool {
        if let o = other as? Self {
            return self == o
        } else {
            return false
        }
    }
}

// Implementing ObvEncodable
extension CryptographicKey {
    public func encode() -> ObvEncoded {
        // Concatenate the algoClass byte identifier and the implementation byte identifier, encode the two bytes
        let encodedAlgoClassAndImplemByteIds = Data([self.algorithmClass.rawValue,
                                                     self.algorithmImplementationByteIdValue]).encode()
        // Encode the ObvDictionary representing the internal elements of the cryptographic key
        let encodedObvDic = obvDictionaryOfInternalElements.encode()
        // Create a list containing the previous two ObvEncoded, and return its encoding
        let encodedElements = [encodedAlgoClassAndImplemByteIds, encodedObvDic]
        return ObvEncoded.pack(encodedElements, usingByteId: correspondingObvEncodedByteId)
    }
}

final class CryptographicKeyDecoder: ObvDecoder {
    static func decode(_ obvEncoded: ObvEncoded) -> (algorithmClassByteId: CryptographicAlgorithmClassByteId, implementationByteIdValue: UInt8, obvDictionary: ObvDictionary)? {
        guard let unpackedList = ObvEncoded.unpack(obvEncoded) else { return nil }
        guard unpackedList.count == 2 else { return nil }
        let encodedAlgoClassAndImplemByteIds = unpackedList[0]
        let encodedObvDict = unpackedList[1]
        // Decode the CryptographicAlgorithmClassByteId and the PublicKeyEncryptionImplementationByteId
        guard let algoClassAndImplemByteIdValues = Data(encodedAlgoClassAndImplemByteIds) else { return nil }
        guard algoClassAndImplemByteIdValues.count == 2 else { return nil }
        guard let algorithmClassByteId = CryptographicAlgorithmClassByteId(rawValue: algoClassAndImplemByteIdValues.first!) else { return nil }
        let implementationByteIdValue: UInt8 = algoClassAndImplemByteIdValues[algoClassAndImplemByteIdValues.startIndex+1]
        // Decode the dictionary
        guard let obvDictionary = ObvDictionary.init(encodedObvDict) else { return nil }
        return (algorithmClassByteId, implementationByteIdValue, obvDictionary)
    }
}

public protocol CompactableCryptographicKey: CryptographicKey {
    func getCompactKey() -> Data // Automatically implemented by keys implementing PublicKeyFromEdwardsCurvePoint
    init?(fromCompactKey: Data) // Allow to easily define an "Expander" class (e.g. CompactPublicKeyForAuthenticationExpander)
    static func getCompactKeyLength(fromAlgorithmImplementationByteIdValue: UInt8) -> Int?
}

public protocol CompactCryptographicKeyExpander {
    associatedtype CryptographicKeyType
    static func expand(compactKey: Data) -> CryptographicKeyType?
    static func getCompactKeyLength(fromAlgorithmImplementationByteIdValue: UInt8) -> Int?
}
