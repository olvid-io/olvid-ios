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

enum SymmetricEncryptionError: Error {
    case incorrectIVLength
    case ciphertextIsNotLongEnough
    case incorrectKeyType
    case couldNotOpenFileToEncrypt
    case couldNotSeekThroughFileToEncrypt
    case couldNotOpenDestinationFile
    case couldNotWriteCiphertextToFile
    case couldNotEncryptFile(status: Int)
    case unexpectedCiphertextLength
}

// MARK: Protocols

/// This protocol is intended to be implemented by the class SymmetricEncryption. The objective is to allow the outside world to call the encrypt and decrypt method directly on the class SymmetricEncryption. Thanks to the fact the keys know which concrete implementation of SymmetricEncryption they correspond to, the concrete implementation can be transparently called.
protocol SymmetricEncryptionCommon {
    static func encrypt(_: Data, with: SymmetricEncryptionKey, andIv: Data) throws -> EncryptedData
    static func decrypt(_: EncryptedData, with: SymmetricEncryptionKey) throws -> Data
}

/// A concrete SymmetricEncryption implementation must not only implement encrypt and decrypt, but must also be able to generate keys. Those keys encapsulate the concrete implementation that generated them.
protocol SymmetricEncryptionConcrete: SymmetricEncryptionCommon {
    static func generateKey(with: PRNG?) -> SymmetricEncryptionKey
    static var keyLength: Int { get }
    static var ivLength: Int { get }
    static func ciphertextLength(forPlaintextLength: Int) -> Int
    static func plaintexLength(forCiphertextLength: Int) throws -> Int

}

protocol SymmetricEncryptionGeneric: SymmetricEncryptionCommon {
    static func generateKey(for: SymmetricEncryptionByteId, with: PRNG?) -> SymmetricEncryptionKey
}

// MARK: Classes

public final class SymmetricEncryption: SymmetricEncryptionGeneric {
    
    static func generateKey(for implemByteId: SymmetricEncryptionByteId, with prng: PRNG?) -> SymmetricEncryptionKey {
        return implemByteId.algorithmImplementation.generateKey(with: prng)
    }
    
    static func encrypt(_ plaintext: Data, with key: SymmetricEncryptionKey, andIv iv: Data) throws -> EncryptedData {
        return try key.algorithmImplementationByteId.algorithmImplementation.encrypt(plaintext, with: key, andIv: iv)
    }
    
    static func decrypt(_ ciphertext: EncryptedData, with key: SymmetricEncryptionKey) throws -> Data {
        return try key.algorithmImplementationByteId.algorithmImplementation.decrypt(ciphertext, with: key)
    }
}






final class SymmetricEncryptionWithAES256CTRNative: SymmetricEncryptionConcrete {
    
    static var keyLength: Int {
        return SymmetricEncryptionAES256CTRKey.length
    }
    
    static var ivLength: Int {
        return 8
    }
    
    private static func counterData(fromCounter counter: UInt64) -> Data {
        var bytes = [UInt8]()
        for i in 0..<8 {
            bytes.append(UInt8(counter >> (8*(7 - i)) & 0xFF))
        }
        return Data(bytes)
    }
    
    static func encrypt(_ plaintext: Data, with _key: SymmetricEncryptionKey, andIv iv: Data) throws -> EncryptedData {
        guard iv.count == SymmetricEncryptionWithAES256CTR.ivLength else { throw SymmetricEncryptionError.incorrectIVLength }
        guard let key = _key as? SymmetricEncryptionAES256CTRKey else { throw SymmetricEncryptionError.incorrectKeyType }
        var counter: UInt64 = 0
        var ciphertextAsData = Data.init(capacity: ciphertextLength(forPlaintextLength: plaintext.count))
        ciphertextAsData.append(iv)
        // Encrypt the plaintext by blocks
        var indexOfNextBlockToEncrypt = plaintext.startIndex
        var indexAfterNextBlockToEncrypt = indexOfNextBlockToEncrypt + AES256.blockLength
        while indexAfterNextBlockToEncrypt <= plaintext.endIndex {
            let plaintextBlock = plaintext[indexOfNextBlockToEncrypt..<indexAfterNextBlockToEncrypt]
            let ciphertextBlock = encrypt(plaintextPart: plaintextBlock, with: key, andIv: iv, andCounter: counter)
            ciphertextAsData.append(ciphertextBlock.raw)
            indexOfNextBlockToEncrypt = indexAfterNextBlockToEncrypt
            indexAfterNextBlockToEncrypt += AES256.blockLength
            counter += 1
        }
        // Encrypt the remaining bytes of plaintext
        let lastBytesOfPlaintext = plaintext[indexOfNextBlockToEncrypt..<plaintext.endIndex]
        let lastBytesOfCiphertext = encrypt(plaintextPart: lastBytesOfPlaintext, with: key, andIv: iv, andCounter: counter)
        ciphertextAsData.append(lastBytesOfCiphertext.raw)
        return EncryptedData.init(data: ciphertextAsData)
    }
    
    private static func encrypt(plaintextPart: Data, with key: SymmetricEncryptionAES256CTRKey, andIv iv: Data, andCounter counter: UInt64) -> EncryptedData {
        assert(plaintextPart.count <= AES256.blockLength)
        let block = createBlockToEncrypt(withIv: iv, andCounter: counter)
        var pad = try! AES256.encrypt(block, underTheKey: key.aes256Key)
        if pad.count != plaintextPart.count {
            pad = pad.removingLast(pad.count - plaintextPart.count)
        }
        let ciphertextPart = EncryptedData(data: try! Data.xor(plaintextPart, pad))
        return ciphertextPart
    }
    
    private static func createBlockToEncrypt(withIv iv: Data, andCounter counter: UInt64) -> Data {
        var block = Data(capacity: AES256.blockLength)
        block.insert(contentsOf: iv, at: block.startIndex)
        block.insert(contentsOf: counterData(fromCounter: counter), at: block.startIndex + SymmetricEncryptionWithAES256CTR.ivLength)
        return block
    }
    
    static func ciphertextLength(forPlaintextLength length: Int) -> Int {
        return length + SymmetricEncryptionWithAES256CTR.ivLength
    }

    static func decrypt(_ ciphertext: EncryptedData, with _key: SymmetricEncryptionKey) throws -> Data {
        guard ciphertext.count >= SymmetricEncryptionWithAES256CTR.ciphertextLength(forPlaintextLength: 0) else { throw SymmetricEncryptionError.ciphertextIsNotLongEnough }
        guard let key = _key as? SymmetricEncryptionAES256CTRKey else { throw SymmetricEncryptionError.incorrectKeyType }
        let indexAfterIv = ciphertext.startIndex+SymmetricEncryptionWithAES256CTR.ivLength
        let iv = Data(ciphertext[ciphertext.startIndex..<indexAfterIv])
        let ciphertextWithoutIv = Data(ciphertext[indexAfterIv..<ciphertext.endIndex])
        let plaintextWithIv = Data(try! encrypt(ciphertextWithoutIv, with: key, andIv: iv))
        let plaintext = plaintextWithIv[plaintextWithIv.startIndex+SymmetricEncryptionWithAES256CTR.ivLength..<plaintextWithIv.endIndex]
        return plaintext
    }

    static func plaintexLength(forCiphertextLength length: Int) throws -> Int {
        guard length >= SymmetricEncryptionWithAES256CTR.ivLength else { throw SymmetricEncryptionError.ciphertextIsNotLongEnough }
        return length - SymmetricEncryptionWithAES256CTR.ivLength
    }
    
    static func generateKey(with _prng: PRNG?) -> SymmetricEncryptionKey {
        let prng = _prng ?? ObvCryptoSuite.sharedInstance.prngService()
        let keyData = prng.genBytes(count: keyLength)
        return SymmetricEncryptionAES256CTRKey(data: keyData)!
    }
}


final class SymmetricEncryptionWithAES256CTR: SymmetricEncryptionConcrete {
    
    static var keyLength: Int {
        return SymmetricEncryptionAES256CTRKey.length
    }
    
    static var ivLength: Int {
        return 8
    }

    
    static func ciphertextLength(forPlaintextLength length: Int) -> Int {
        return length + SymmetricEncryptionWithAES256CTR.ivLength
    }

    
    static func plaintexLength(forCiphertextLength length: Int) throws -> Int {
        guard length >= SymmetricEncryptionWithAES256CTR.ivLength else { throw SymmetricEncryptionError.ciphertextIsNotLongEnough }
        return length - SymmetricEncryptionWithAES256CTR.ivLength
    }

    
    static func encrypt(_ plaintext: Data, with key: SymmetricEncryptionKey, andIv iv: Data) throws -> EncryptedData {
        
        guard iv.count == ivLength else { throw SymmetricEncryptionError.incorrectIVLength }
        guard let key = key as? SymmetricEncryptionAES256CTRKey else { throw SymmetricEncryptionError.incorrectKeyType }
        
        var ccIv = Data(count: kCCBlockSizeAES128)
        let ciphertextLength = ivLength + plaintext.count
        var ciphertext = Data(count: ciphertextLength) // Only one constant for the AES block size

        // Copy the 8 bytes of the IV into the 8 first bytes of the ccIV (which has 16 bytes)
        ccIv.withUnsafeMutableBytes { (ccIvBufferPtr: UnsafeMutableRawBufferPointer) -> Void in
            iv.copyBytes(to: ccIvBufferPtr, count: ivLength)
        }
        
        // Copy the 8 bytes of the IV into the 8 first bytes of ciphertext
        ciphertext.withUnsafeMutableBytes { (ciphertextBufferPtr: UnsafeMutableRawBufferPointer) -> Void in
            iv.copyBytes(to: ciphertextBufferPtr, count: ivLength)
        }

        
        let status = plaintext.withUnsafeBytes { (plaintextBufferPtr) -> Int in
            let plaintextPtr = plaintextBufferPtr.baseAddress!
            let status = ciphertext.withUnsafeMutableBytes { (ciphertextBufferPtr) -> Int in
                let ciphertextPtr = ciphertextBufferPtr.baseAddress!
                let status = key.data.withUnsafeBytes { (keyBufferPtr) -> Int in
                    let keyPtr = keyBufferPtr.baseAddress!
                    let status = ccIv.withUnsafeBytes { (ivBufferPtr) -> Int in
                        let ivPtr = ivBufferPtr.baseAddress!
                        var cryptoRef: CCCryptorRef?
                        CCCryptorCreateWithMode(CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding), ivPtr, keyPtr, keyLength, nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &cryptoRef)
                        var dataOutMoved = 0
                        CCCryptorUpdate(cryptoRef, plaintextPtr, plaintext.count, ciphertextPtr.advanced(by: ivLength), ciphertextLength-ivLength, &dataOutMoved)
                        let status = CCCryptorFinal(cryptoRef, ciphertextPtr.advanced(by: ivLength + dataOutMoved), ciphertextLength-ivLength-dataOutMoved, &dataOutMoved)
                        CCCryptorRelease(cryptoRef)
                        return Int(status)
                    }
                    return status
                }
                return status
            }
            return status
        }

        
        guard status == 0 else { throw NSError() }
        
        return EncryptedData(data: ciphertext)
    }
    
    
    static func encrypt(fileAtURL fromURL: URL, startingAtOffset offset: Int64, length plaintextLenght: Int, with key: SymmetricEncryptionKey, andIv iv: Data, toURL: URL) throws {
        
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

        // Allocate a buffers for plaintext and ciphertext parts
        let bufferByteCount = min(32_768, plaintextLenght) // 32_768 = 32kB, i.e., 2048 AES blocks
        let fromBufferPointer = UnsafeMutableRawPointer.allocate(byteCount: bufferByteCount, alignment: 1)
        let toBufferPointer = UnsafeMutableRawPointer.allocate(byteCount: bufferByteCount, alignment: 1)
        defer {
            free(fromBufferPointer)
            free(toBufferPointer)
        }

        guard iv.count == ivLength else { throw SymmetricEncryptionError.incorrectIVLength }
        guard let key = key as? SymmetricEncryptionAES256CTRKey else { throw SymmetricEncryptionError.incorrectKeyType }
        
        var ccIv = Data(count: kCCBlockSizeAES128)
        let expectedCiphertextLength = ivLength + plaintextLenght
        
        // Copy the 8 bytes of the IV into the 8 first bytes of the ccIV (which has 16 bytes)
        ccIv.withUnsafeMutableBytes { (ccIvBufferPtr: UnsafeMutableRawBufferPointer) -> Void in
            iv.copyBytes(to: ccIvBufferPtr, count: ivLength)
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
        let status = key.data.withUnsafeBytes { (keyBufferPtr) -> Int in
            let keyPtr = keyBufferPtr.baseAddress!
            let status = ccIv.withUnsafeBytes { (ivBufferPtr) -> Int in
                let ivPtr = ivBufferPtr.baseAddress!
                // Initialize the block cipher
                var cryptoRef: CCCryptorRef?
                CCCryptorCreateWithMode(CCOperation(kCCEncrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding), ivPtr, keyPtr, keyLength, nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &cryptoRef)
                guard cryptoRef != nil else { return kCCUnspecifiedError }
                defer { CCCryptorRelease(cryptoRef) }
                // Loop over the input plaintext
                var dataOutMoved = 0
                while numberOfRemainingBytesToEncrypt > 0 {
                    // Read bytes
                    let numberOfBytesToRead = min(bufferByteCount, numberOfRemainingBytesToEncrypt)
                    guard numberOfBytesToRead == read(fromFd, fromBufferPointer, numberOfBytesToRead) else {
                        return -1
                    }
                    // Encrypt bytes
                    let status = CCCryptorUpdate(cryptoRef, fromBufferPointer, numberOfBytesToRead, toBufferPointer, bufferByteCount, &dataOutMoved)
                    guard status == kCCSuccess else { return Int(status) }
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
                    write(toFd, toBufferPointer, dataOutMoved)
                    ciphertextLength += dataOutMoved
                }
                return Int(status)
            }
            return status
        }
        guard status == kCCSuccess else { throw SymmetricEncryptionError.couldNotEncryptFile(status: status) }
        guard ciphertextLength == expectedCiphertextLength else { throw SymmetricEncryptionError.unexpectedCiphertextLength }
        
    }
    
    
    static func decrypt(_ ciphertext: EncryptedData, with key: SymmetricEncryptionKey) throws -> Data {
        
        guard ciphertext.count >= SymmetricEncryptionWithAES256CTR.ciphertextLength(forPlaintextLength: 0) else { throw SymmetricEncryptionError.ciphertextIsNotLongEnough }
        guard let key = key as? SymmetricEncryptionAES256CTRKey else { throw SymmetricEncryptionError.incorrectKeyType }
        
        var ccIv = Data(count: kCCBlockSizeAES128)
        let plaintextLength = try plaintexLength(forCiphertextLength: ciphertext.count)
        var plaintext = Data(count: plaintextLength)
        
        // Copy the 8 bytes of the ciphertext into the 8 first bytes of the ccIV (which has 16 bytes)
        ccIv.withUnsafeMutableBytes { ccIvBufferPtr -> Void in
            let ccIvPtr = ccIvBufferPtr.baseAddress!.bindMemory(to: UInt8.self, capacity: ivLength)
            ciphertext.raw.copyBytes(to: ccIvPtr, count: ivLength)
        }

        let status = ciphertext.withUnsafeBytes { (ciphertextBufferPtr) -> Int in
            let ciphertextPtr = ciphertextBufferPtr.baseAddress!
            let status = plaintext.withUnsafeMutableBytes { (plaintextBufferPtr) -> Int in
                let plaintextPtr = plaintextBufferPtr.baseAddress!
                let status = key.data.withUnsafeBytes { (keyBufferPtr) -> Int in
                    let keyPtr = keyBufferPtr.baseAddress!
                    let status = ccIv.withUnsafeBytes { (ivBufferPtr) -> Int in
                        let ivPtr = ivBufferPtr.baseAddress!
                        var cryptoRef: CCCryptorRef?
                        CCCryptorCreateWithMode(CCOperation(kCCDecrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding), ivPtr, keyPtr, keyLength, nil, 0, 0, CCModeOptions(kCCModeOptionCTR_BE), &cryptoRef)
                        var dataOutMoved = 0
                        CCCryptorUpdate(cryptoRef, ciphertextPtr.advanced(by: ivLength), plaintextLength, plaintextPtr, plaintextLength, &dataOutMoved)
                        let status = CCCryptorFinal(cryptoRef, plaintextPtr.advanced(by: dataOutMoved), plaintextLength-dataOutMoved, &dataOutMoved)
                        return Int(status)
                    }
                    return status
                }
                return status
            }
            return status
        }

        guard status == 0 else { throw NSError() }

        return plaintext
        
    }
    
    static func generateKey(with _prng: PRNG?) -> SymmetricEncryptionKey {
        let prng = _prng ?? ObvCryptoSuite.sharedInstance.prngService()
        let keyData = prng.genBytes(count: keyLength)
        return SymmetricEncryptionAES256CTRKey(data: keyData)!
    }

}
