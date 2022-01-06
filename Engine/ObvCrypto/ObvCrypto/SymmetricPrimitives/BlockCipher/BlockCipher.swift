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

enum BlockCipherError: Error {
    case incorrectKeySize
    case incorrectKey
    case incorrectBlockSize
}

// MARK: Protocols

/// This protocol is intended to be implemented by the class BlockCipher. The objective is to allow the outside world to call the encrypt and decrypt method directly on the class BlockCipher. Thanks to the fact the symmetric keys know which concrete implementation of BlockCipher they correspond to, the concrete implementation can be transparently called.
protocol BlockCipherCommon {
    static func encrypt(_: Data, underTheKey: BlockCipherKey) throws -> EncryptedData
    static func decrypt(_: EncryptedData, underTheKey: BlockCipherKey) throws -> Data
}

/// A concrete BlockCipher implementation must not only implement encrypt and decrypt, but must also be able to generate keys. Those keys encapsulate the concrete implementation that generated them.
protocol BlockCipherConcrete: BlockCipherCommon {
    static func generateKey(with: PRNG?) -> BlockCipherKey
    static var keyLength: Int { get }
    static var blockLength: Int { get }
}

protocol BlockCipherGeneric: BlockCipherCommon {
    static func generateKey(for: BlockCipherImplementationByteId, with: PRNG?) -> BlockCipherKey
}


// MARK: Classes

public final class BlockCipher: BlockCipherGeneric {
    
    static func generateKey(for implemByteId: BlockCipherImplementationByteId, with prng: PRNG?) -> BlockCipherKey {
        return implemByteId.algorithmImplementation.generateKey(with: prng)
    }
    
    static func encrypt(_ plaintext: Data, underTheKey key: BlockCipherKey) throws -> EncryptedData {
        return try key.algorithmImplementationByteId.algorithmImplementation.encrypt(plaintext, underTheKey: key)
    }
    
    static func decrypt(_ ciphertext: EncryptedData, underTheKey key: BlockCipherKey) throws -> Data {
        return try key.algorithmImplementationByteId.algorithmImplementation.decrypt(ciphertext, underTheKey: key)
    }

}

protocol BlockCipherBasedOnCommonCrypto {
    
    static var keyType: BlockCipherKey.Type { get }
    
    static func ccCrypt(_ op: CCOperation, key: UnsafeRawPointer!, dataIn: UnsafeRawPointer!, dataOut: UnsafeMutableRawPointer!) -> CCCryptorStatus
    
}

extension BlockCipherConcrete where Self: BlockCipherBasedOnCommonCrypto {
    
    static func encrypt(_ plaintext: Data, underTheKey key: BlockCipherKey) throws -> EncryptedData {
        guard plaintext.count == blockLength else {
            throw BlockCipherError.incorrectKeySize
        }
        guard type(of: key).length == keyLength else {
            throw BlockCipherError.incorrectBlockSize
        }
        var ciphertext = [UInt8](repeating: 0x00, count: blockLength)
        var keyAsBytes = [UInt8](repeating: 0x00, count: keyLength)
        key.data.copyBytes(to: &keyAsBytes, count: keyLength)
        _ = plaintext.withUnsafeBytes() {
            ccCrypt(CCOperation(kCCEncrypt), key: keyAsBytes, dataIn: $0.baseAddress!, dataOut: &ciphertext)
        }
        return EncryptedData(bytes: ciphertext)
    }
    
    static func decrypt(_ ciphertext: EncryptedData, underTheKey key: BlockCipherKey) throws -> Data {
        guard ciphertext.count == blockLength else {
            throw BlockCipherError.incorrectKeySize
        }
        guard type(of: key) == self.keyType else {
            throw BlockCipherError.incorrectKey
        }
        var plaintext = [UInt8](repeating: 0x00, count: blockLength)
        var keyAsBytes = [UInt8](repeating: 0x00, count: keyLength)
        key.data.copyBytes(to: &keyAsBytes, count: keyLength)
        ciphertext.withUnsafeBytes { (bufferPtr) -> Void in
            let ptr = bufferPtr.baseAddress!
            _ = ccCrypt(CCOperation(kCCDecrypt), key: keyAsBytes, dataIn: ptr, dataOut: &plaintext)
        }
        return Data(plaintext)
    }
    
}

class AES256: BlockCipherConcrete, BlockCipherBasedOnCommonCrypto {
    
    static let keyType: BlockCipherKey.Type = AES256Key.self
    

    static var keyLength: Int {
        return kCCKeySizeAES256
    }

    static var blockLength: Int {
        return kCCBlockSizeAES128 // Same block size for all AES versions, only one constant in Common Crypto
    }
    
    static func generateKey(with _prng: PRNG?) -> BlockCipherKey {
        let prng = _prng ?? ObvCryptoSuite.sharedInstance.prngService()
        return AES256Key(data: prng.genBytes(count: keyLength))!
    }

    static func ccCrypt(_ op: CCOperation, key: UnsafeRawPointer!, dataIn: UnsafeRawPointer!, dataOut: UnsafeMutableRawPointer!) -> CCCryptorStatus {
        return CCCrypt(op, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode), key, keyLength, nil, dataIn, blockLength, dataOut, blockLength, nil)
    }
}
