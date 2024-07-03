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

public protocol AuthenticatedEncryptionKey: SymmetricKey, CustomStringConvertible {
    var algorithmImplementationByteId: AuthenticatedEncryptionImplementationByteId { get }
}


extension AuthenticatedEncryptionKey {
    
    private static func makeError(message: String) -> Error { NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { Self.makeError(message: message) }

    var algorithmClass: CryptographicAlgorithmClassByteId {
        return .authenticatedEncryption
    }
    
    var algorithmImplementationByteIdValue: UInt8 {
        return algorithmImplementationByteId.rawValue
    }
    
    func isEqual(to other: AuthenticatedEncryptionKey?) throws -> Bool {
        guard other != nil else { return false }
        if let lhs = self as? AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key, let rhs = other! as? AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key {
            return lhs == rhs
        } else {
            throw makeError(message: "Unknown AuthenticatedEncryptionKey subclass")
        }
    }
    
}

public final class AuthenticatedEncryptionKeyDecoder {
    
    static func makeError(message: String) -> Error { NSError(domain: "AuthenticatedEncryptionKeyDecoder", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    
    public static func decode(_ encodedKey: ObvEncoded) throws -> AuthenticatedEncryptionKey {
        guard encodedKey.byteId == .symmetricKey else {
            throw Self.makeError(message: "encodedKey.byteId is not .symmetricKey")
        }
        guard let (algorithmClassByteId, implementationByteIdValue, obvDic) = CryptographicKeyDecoder.obvDecode(encodedKey) else {
            throw Self.makeError(message: "CryptographicKeyDecoder decoding failed")
        }
        guard algorithmClassByteId == .authenticatedEncryption else {
            throw Self.makeError(message: "algorithmClassByteId is not .authenticatedEncryption")
        }
        guard let implementationByteId = AuthenticatedEncryptionImplementationByteId(rawValue: implementationByteIdValue) else {
            throw Self.makeError(message: "AuthenticatedEncryptionImplementationByteId init failed")
        }
        switch implementationByteId {
        case .CTR_AES_256_THEN_HMAC_SHA_256:
            guard let key = AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key(obvDictionaryOfInternalElements: obvDic) else {
                throw Self.makeError(message: "AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key init failed")
            }
            return key
        }
    }
    
}


public struct AuthenticatedEncryptionKeyComparator {
    
    public static func areEqual(_ lhs: AuthenticatedEncryptionKey?, _ rhs: AuthenticatedEncryptionKey?) throws -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case (.some, .none), (.none, .some):
            return false
        case (.some(let key1), .some(let key2)):
            return try key1.isEqual(to: key2)
        }

    }

}


struct AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key: AuthenticatedEncryptionKey, Equatable {
    
    var obvDictionaryOfInternalElements: ObvDictionary {
        var dict = aes256CTRKey.obvDictionaryOfInternalElements
        for (key, val) in hmacWithSHA256Key.obvDictionaryOfInternalElements {
            dict[key] = val
        }
        return dict
    }
    
    init?(obvDictionaryOfInternalElements obvDict: ObvDictionary) {
        guard let aes256CTRKey = SymmetricEncryptionAES256CTRKey(obvDictionaryOfInternalElements: obvDict) else { return nil }
        guard let hmacWithSHA256Key = HMACWithSHA256Key(obvDictionaryOfInternalElements: obvDict) else { return nil }
        self.aes256CTRKey = aes256CTRKey
        self.hmacWithSHA256Key = hmacWithSHA256Key
    }
    
    let algorithmImplementationByteId: AuthenticatedEncryptionImplementationByteId = .CTR_AES_256_THEN_HMAC_SHA_256
    
    static let length = AES256Key.length + HMACWithSHA256Key.length
    
    let aes256CTRKey: SymmetricEncryptionAES256CTRKey
    let hmacWithSHA256Key: HMACWithSHA256Key
    
    init(aes256CTRKey: SymmetricEncryptionAES256CTRKey, hmacWithSHA256Key: HMACWithSHA256Key) {
        self.aes256CTRKey = aes256CTRKey
        self.hmacWithSHA256Key = hmacWithSHA256Key
    }
    
    init?(data: Data) {
        guard data.count == AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key.length else { return nil }
        let dataForMac = data[data.startIndex..<data.startIndex+HMACWithSHA256Key.length]
        let dataForSymEnc = data[data.startIndex+HMACWithSHA256Key.length..<data.endIndex]
        aes256CTRKey = SymmetricEncryptionAES256CTRKey(data: dataForSymEnc)!
        hmacWithSHA256Key = HMACWithSHA256Key(data: dataForMac)!
    }
    
    var data: Data {
        return hmacWithSHA256Key.data + aes256CTRKey.data
    }
    
}

// Implementing ObvDecodable
extension AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key {
    init?(_ obvEncoded: ObvEncoded) {
        guard let key = try? AuthenticatedEncryptionKeyDecoder.decode(obvEncoded) else { return nil }
        self.init(data: key.data)
    }
}

// Implementing CustomStringConvertible
extension AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key {
    var description: String {
        return "\(hmacWithSHA256Key.data.hexString()) - \(aes256CTRKey.data.hexString())"
    }
}
