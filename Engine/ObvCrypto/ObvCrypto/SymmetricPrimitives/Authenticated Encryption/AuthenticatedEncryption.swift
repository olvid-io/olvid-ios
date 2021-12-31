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
import CommonCrypto

// MARK: Protocols

public protocol AuthenticatedEncryptionCommon {
    static func encrypt(_: Data, with: AuthenticatedEncryptionKey, and: PRNG?) throws -> EncryptedData
    static func encrypt(fileAtURL: URL, startingAtOffset: Int64, length: Int, with: AuthenticatedEncryptionKey, and: PRNG, toURL: URL) throws
    static func decrypt(_: EncryptedData, with: AuthenticatedEncryptionKey) throws -> Data
}


public protocol AuthenticatedEncryptionConcrete: AuthenticatedEncryptionCommon {
    static var algorithmImplementationByteId: AuthenticatedEncryptionImplementationByteId { get }
    static func generateKey(with: PRNG?) -> AuthenticatedEncryptionKey
    static func generateKey(with: Seed) -> AuthenticatedEncryptionKey
    static func ciphertextLength(forPlaintextLength length: Int) -> Int
    static func plaintexLength(forCiphertextLength length: Int) throws -> Int
    static var keyLength: Int { get }
    static var minimumCiphertextLength: Int { get }
}

protocol AuthenticatedEncryptionGeneric: AuthenticatedEncryptionCommon {
    static func generateKey(for: AuthenticatedEncryptionImplementationByteId, with: PRNG) -> AuthenticatedEncryptionKey
    static func generateKey(for: AuthenticatedEncryptionImplementationByteId, with: Seed) -> AuthenticatedEncryptionKey
    static func ciphertextLength(forPlaintextLength: Int, andFor: AuthenticatedEncryptionImplementationByteId) -> Int
    static func ciphertextLength(forPlaintextLength: Int, whenEncryptedUnder: AuthenticatedEncryptionKey) -> Int
    static func plaintexLength(forCiphertextLength: Int, andFor: AuthenticatedEncryptionImplementationByteId) throws -> Int
    static func plaintexLength(forCiphertextLength: Int, whenDecryptedUnder: AuthenticatedEncryptionKey) throws -> Int
}

// MARK: Classes

enum AuthenticatedEncryptionError: Error {
    case incorrectKeyLength
    case incorrectKey
    case integrityCheckFailed
    case ciphertextIsNotLongEnough
}

public final class AuthenticatedEncryption: AuthenticatedEncryptionGeneric {
    
    public static func ciphertextLength(forPlaintextLength length: Int, whenEncryptedUnder key: AuthenticatedEncryptionKey) -> Int {
        return key.algorithmImplementationByteId.algorithmImplementation.ciphertextLength(forPlaintextLength: length)
    }
    
    public static func plaintexLength(forCiphertextLength length: Int, whenDecryptedUnder key: AuthenticatedEncryptionKey) throws -> Int {
        return try key.algorithmImplementationByteId.algorithmImplementation.plaintexLength(forCiphertextLength: length)
    }
    
    public static func ciphertextLength(forPlaintextLength length: Int, andFor implemByteId: AuthenticatedEncryptionImplementationByteId) -> Int {
        return implemByteId.algorithmImplementation.ciphertextLength(forPlaintextLength: length)
    }
    
    public static func plaintexLength(forCiphertextLength length: Int, andFor implemByteId: AuthenticatedEncryptionImplementationByteId) throws -> Int {
        return try implemByteId.algorithmImplementation.plaintexLength(forCiphertextLength: length)
    }
    
    public static func generateKey(for implemByteId: AuthenticatedEncryptionImplementationByteId, with prng: PRNG) -> AuthenticatedEncryptionKey {
        return implemByteId.algorithmImplementation.generateKey(with: prng)
    }
    
    public static func generateKey(for implemByteId: AuthenticatedEncryptionImplementationByteId, with seed: Seed) -> AuthenticatedEncryptionKey {
        return implemByteId.algorithmImplementation.generateKey(with: seed)
    }

    
    public static func encrypt(_ plaintext: Data, with key: AuthenticatedEncryptionKey, and prng: PRNG?) -> EncryptedData {
        return try! key.algorithmImplementationByteId.algorithmImplementation.encrypt(plaintext, with: key, and: prng)
    }
    
    public static func encrypt(fileAtURL fromURL: URL, startingAtOffset offset: Int64, length plaintextLength: Int, with key: AuthenticatedEncryptionKey, and prng: PRNG, toURL: URL) throws {
        return try! key.algorithmImplementationByteId.algorithmImplementation.encrypt(fileAtURL: fromURL, startingAtOffset: offset, length: plaintextLength, with: key, and: prng, toURL: toURL)
    }
    
    public static func decrypt(_ ciphertext: EncryptedData, with key: AuthenticatedEncryptionKey) throws -> Data {
        return try key.algorithmImplementationByteId.algorithmImplementation.decrypt(ciphertext, with: key)
    }

}

final class AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256: AuthenticatedEncryptionConcrete {
    
    static var algorithmImplementationByteId: AuthenticatedEncryptionImplementationByteId {
        return .CTR_AES_256_THEN_HMAC_SHA_256
    }
    
    static var keyLength: Int {
        return SymmetricEncryptionAES256CTRKey.length + HMACWithSHA256Key.length
    }
    
    static var minimumCiphertextLength: Int {
        return SymmetricEncryptionWithAES256CTR.ciphertextLength(forPlaintextLength: 0) + HMACWithSHA256.outputLength
    }
    
    static func encrypt(_ plaintext: Data, with _key: AuthenticatedEncryptionKey, and _prng: PRNG?) throws -> EncryptedData {
        guard let key = _key as? AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key else { throw AuthenticatedEncryptionError.incorrectKey }
        let prng = _prng ?? ObvCryptoSuite.sharedInstance.prngService()
        // Encrypt...
        let iv = prng.genBytes(count: SymmetricEncryptionWithAES256CTR.ivLength)
        let ciphertext = try! SymmetricEncryptionWithAES256CTR.encrypt(plaintext, with: key.aes256CTRKey, andIv: iv)
        // And then authenticate
        let mac = try! HMACWithSHA256.compute(forData: ciphertext, withKey: key.hmacWithSHA256Key)
        let authenticatedCiphertext = EncryptedData.byAppending(c1: ciphertext, c2: EncryptedData(data: mac))
        return authenticatedCiphertext
    }
    
    
    static func encrypt(fileAtURL fromURL: URL, startingAtOffset offset: Int64, length plaintextLenght: Int, with _key: AuthenticatedEncryptionKey, and prng: PRNG, toURL: URL) throws {
        
        guard let key = _key as? AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key else { throw AuthenticatedEncryptionError.incorrectKey }
        
        // Get a readonly file descriptor to the file from which we will read the plaintext
        // Seek to the appropriate location in the file
        let fromFd = open(fromURL.path, O_RDONLY)
        defer { close(fromFd) }
        guard fromFd != -1 else {
            throw SymmetricEncryptionError.couldNotOpenFileToEncrypt
        }
        guard offset == lseek(fromFd, Int64(offset), SEEK_SET) else {
            assertionFailure()
            throw SymmetricEncryptionError.couldNotSeekThroughFileToEncrypt
        }
        
        // Get a writeonly file descriptor to the file to which we will write the ciphertext
        let toFd = open(toURL.path, O_WRONLY)
        defer { close(toFd) }
        guard toFd != -1 else {
            throw SymmetricEncryptionError.couldNotOpenDestinationFile
        }

        // Allocate buffers for plaintext and ciphertext parts, and for the final MAC
        let bufferByteCount = min(32_768, plaintextLenght) // 32_768 = 32kB, i.e., 2048 AES blocks
        let fromBufferPointer = UnsafeMutableRawPointer.allocate(byteCount: bufferByteCount, alignment: 1)
        let toBufferPointer = UnsafeMutableRawPointer.allocate(byteCount: bufferByteCount, alignment: 1)
        var macOut = Data(repeating: 0x00, count: Int(CC_SHA256_DIGEST_LENGTH))
        defer {
            free(fromBufferPointer)
            free(toBufferPointer)
        }

        let iv = prng.genBytes(count: SymmetricEncryptionWithAES256CTR.ivLength)
        
        var ccIv = Data(count: kCCBlockSizeAES128)
        let expectedCiphertextLength = ciphertextLength(forPlaintextLength: plaintextLenght)
        
        // Copy the 8 bytes of the IV into the 8 first bytes of the ccIV (which has 16 bytes)
        ccIv.withUnsafeMutableBytes { (ccIvBufferPtr: UnsafeMutableRawBufferPointer) -> Void in
            iv.copyBytes(to: ccIvBufferPtr, count: SymmetricEncryptionWithAES256CTR.ivLength)
        }
        
        // Write the IV to the first 8 bytes of the ciphertext
        do {
            let status = iv.withUnsafeBytes { (ivRawBufferPtr: UnsafeRawBufferPointer) -> Int in
                guard let ptr = ivRawBufferPtr.baseAddress else { return -1 }
                guard iv.count == write(toFd, ptr, iv.count) else { return -1 }
                return 0
            }
            guard status == 0 else { throw SymmetricEncryptionError.couldNotWriteCiphertextToFile }
        }
        var ciphertextLength = iv.count
        
        // Encrypt the file and write the plaintext to the destination URL
        var numberOfRemainingBytesToEncrypt = plaintextLenght
        let status = key.aes256CTRKey.data.withUnsafeBytes { (keyBufferPtr) -> Int in
            let keyPtr = keyBufferPtr.baseAddress!
            let status = ccIv.withUnsafeBytes { (ivBufferPtr) -> Int in
                let ivPtr = ivBufferPtr.baseAddress!
                // Initialize the block cipher
                var cryptoRef: CCCryptorRef?
                CCCryptorCreateWithMode(CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding), ivPtr, keyPtr, SymmetricEncryptionAES256CTRKey.length, nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &cryptoRef)
                guard cryptoRef != nil else { return kCCUnspecifiedError }
                defer { CCCryptorRelease(cryptoRef) }
                // Initialize the MAC and update it with the iv
                var ctx = CCHmacContext()
                let hmacKey = [UInt8](key.hmacWithSHA256Key.data)
                CCHmacInit(&ctx, UInt32(kCCHmacAlgSHA256), hmacKey, hmacKey.count)
                iv.withUnsafeBytes { (rawBufferPointer: UnsafeRawBufferPointer) in
                    CCHmacUpdate(&ctx, rawBufferPointer.baseAddress, iv.count)
                }
                // Loop over the input plaintext
                var dataOutMoved = 0
                while numberOfRemainingBytesToEncrypt > 0 {
                    // Read bytes
                    let numberOfBytesToRead = min(bufferByteCount, numberOfRemainingBytesToEncrypt)
                    guard numberOfBytesToRead == read(fromFd, fromBufferPointer, numberOfBytesToRead) else {
                        return kCCUnspecifiedError
                    }
                    // Encrypt bytes
                    let status = CCCryptorUpdate(cryptoRef, fromBufferPointer, numberOfBytesToRead, toBufferPointer, bufferByteCount, &dataOutMoved)
                    guard status == kCCSuccess else { return Int(status) }
                    // Authenticate encrypted bytes
                    CCHmacUpdate(&ctx, toBufferPointer, dataOutMoved)
                    // Write encrypted bytes to file
                    guard dataOutMoved == write(toFd, toBufferPointer, dataOutMoved) else { return kCCUnspecifiedError }
                    ciphertextLength += dataOutMoved
                    // Decrement numberOfRemainingBytesToEncrypt
                    numberOfRemainingBytesToEncrypt -= numberOfBytesToRead
                }
                // Finalize encryption
                let status = CCCryptorFinal(cryptoRef, toBufferPointer, bufferByteCount, &dataOutMoved)
                guard status == kCCSuccess else { return Int(status) }
                if dataOutMoved > 0 {
                    // Authenticate encrypted bytes
                    CCHmacUpdate(&ctx, toBufferPointer, dataOutMoved)
                    // Write encrypted bytes to file
                    write(toFd, toBufferPointer, dataOutMoved)
                    ciphertextLength += dataOutMoved
                }
                // Finalize authentication and write the MAC to the end of the destination file
                macOut.withUnsafeMutableBytes { (mutableRawBufferPointer) in
                    let ptr = mutableRawBufferPointer.baseAddress!
                    CCHmacFinal(&ctx, ptr)
                }
                let nbrBytesWritten = macOut.withUnsafeBytes { (rawBufferPointer: UnsafeRawBufferPointer) -> Int in
                    write(toFd, rawBufferPointer.baseAddress, macOut.count)
                }
                guard nbrBytesWritten == macOut.count else { return kCCUnspecifiedError }
                ciphertextLength += nbrBytesWritten
                return Int(status)
            }
            return status
        }
        guard status == kCCSuccess else { throw SymmetricEncryptionError.couldNotEncryptFile(status: status) }
        guard ciphertextLength == expectedCiphertextLength else { throw SymmetricEncryptionError.unexpectedCiphertextLength }
        
    }

    
    static func decrypt(_ ciphertext: EncryptedData, with _key: AuthenticatedEncryptionKey) throws -> Data {
        guard let key = _key as? AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key else { throw AuthenticatedEncryptionError.incorrectKey }
        guard ciphertext.count >= AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256.minimumCiphertextLength else { throw AuthenticatedEncryptionError.ciphertextIsNotLongEnough }
        let ciphertextRange = ciphertext.startIndex..<ciphertext.endIndex - HMACWithSHA256.outputLength
        let macRange = ciphertext.endIndex - HMACWithSHA256.outputLength..<ciphertext.endIndex
        let innerCiphertext = ciphertext[ciphertextRange]
        let mac = Data(encryptedData: ciphertext[macRange])
        guard try! HMACWithSHA256.verify(mac: mac, forData: innerCiphertext, withKey: key.hmacWithSHA256Key) else { throw AuthenticatedEncryptionError.integrityCheckFailed }
        let plaintext = try! SymmetricEncryptionWithAES256CTR.decrypt(innerCiphertext, with: key.aes256CTRKey)
        return plaintext
    }

    static func ciphertextLength(forPlaintextLength length: Int) -> Int {
        let innerCiphertextLength = SymmetricEncryptionWithAES256CTR.ciphertextLength(forPlaintextLength: length)
        let macLength = HMACWithSHA256.outputLength
        return innerCiphertextLength + macLength
    }

    static func plaintexLength(forCiphertextLength length: Int) throws -> Int {
        guard length >= AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256.minimumCiphertextLength else {
            throw AuthenticatedEncryptionError.ciphertextIsNotLongEnough
        }
        let innerCiphertextLength = length - HMACWithSHA256.outputLength
        let plaintextLength = try! SymmetricEncryptionWithAES256CTR.plaintexLength(forCiphertextLength: innerCiphertextLength)
        return plaintextLength
    }
    
    static func generateKey(with _prng: PRNG?) -> AuthenticatedEncryptionKey {
        let prng = _prng ?? ObvCryptoSuite.sharedInstance.prngService()
        let seed = prng.genSeed()
        return generateKey(with: seed)
    }
    
    static func generateKey(with seed: Seed) -> AuthenticatedEncryptionKey {
        let key = KDFFromPRNGWithHMACWithSHA256.generate(from: seed, { AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key(data: $0)! })!
        return key
    }
}

// AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key is Equatable
extension AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key {
    static func == (lhs: AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key, rhs: AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key) -> Bool {
        return lhs.aes256CTRKey == rhs.aes256CTRKey && lhs.hmacWithSHA256Key == rhs.hmacWithSHA256Key
    }
}
