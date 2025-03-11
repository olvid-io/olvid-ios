//
//  Olvid for iOS
//  Copyright © 2019-2024 Olvid SAS
//
//  This file is part of Olvid for iOS.
//
//  Olvid is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License, version 3,
//  as published by the Free Software Foundation.
//
//  Olvid is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with Olvid.  If not, see  &lt;https://www.gnu.org/licenses/>.
//

import XCTest
import CoreData
import ObvBigInt
import ObvEncoder
@testable import ObvCrypto

class ObvCryptoTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    private static func findRandomPoint(onCurve curve: EdwardsCurve) -> PointOnCurve {
        let prngService = PRNGServiceWithHMACWithSHA256()
        while true {
            let yCoordinateCandidate = prngService.genBigInt(smallerThan: curve.parameters.p)
            let point = curve.pointsOnCurve(forYcoordinate: yCoordinateCandidate)?.point1
            if point != nil {
                return point!
            }
        }
    }
    
    func testSHA256() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsSHA256", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForHash].self, from: jsonData)
        for testVector in testVectors {
            let inputMessage = String(repeating: testVector.inputMessagePart, count: testVector.numberOfRepetition).data(using: .utf8)!
            let digest = testVector.digest
            let computedDigest = SHA256.hash(inputMessage)
            XCTAssertEqual(digest, computedDigest)
        }
    }
    
    func testSHA256ForHashingFile() {
        
        let bundle = Bundle(for: type(of: self))

        // Empty file
        do {
            let url = bundle.url(forResource: "TestFileForSHA256_e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", withExtension: "txt")!
            let computedDigest = try SHA256.hash(fileAtUrl: url)
            XCTAssertEqual(computedDigest.hexString(), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        } catch {
            XCTFail()
        }

        // File containing "abcdef"
        do {
            let url = bundle.url(forResource: "TestFileForSHA256_ae0666f161fed1a5dde998bbd0e140550d2da0db27db1d0e31e370f2bd366a57", withExtension: "txt")!
            let computedDigest = try SHA256.hash(fileAtUrl: url)
            XCTAssertEqual(computedDigest.hexString(), "ae0666f161fed1a5dde998bbd0e140550d2da0db27db1d0e31e370f2bd366a57")
        } catch {
            XCTFail()
        }

        // File containing 1MB of random data
        do {
            let url = bundle.url(forResource: "TestFileForSHA256_46730143a5d12af74ce66dc88ae7740bf79878d9e04b15725ea6100138fa2eb5", withExtension: "txt")!
            let computedDigest = try SHA256.hash(fileAtUrl: url)
            XCTAssertEqual(computedDigest.hexString(), "46730143a5d12af74ce66dc88ae7740bf79878d9e04b15725ea6100138fa2eb5")
        } catch {
            XCTFail()
        }

        // File containing one million (1,000,000) repetitions of the character "a" (0x61)
        do {
            let url = bundle.url(forResource: "TestFileForSHA256_cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0", withExtension: "txt")!
            let computedDigest = try SHA256.hash(fileAtUrl: url)
            XCTAssertEqual(computedDigest.hexString(), "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
        } catch {
            XCTFail()
        }

    }
    
    func testAES256() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsAES256", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorsAES256].self, from: jsonData)
        for testVector in testVectors {
            do {
                let ciphertext = try! AES256.encrypt(testVector.plaintext, underTheKey: testVector.key)
                XCTAssertEqual([UInt8](ciphertext), [UInt8](testVector.ciphertext))
            }
            do {
                let ciphertext = try! BlockCipher.encrypt(testVector.plaintext, underTheKey: testVector.key)
                XCTAssertEqual([UInt8](ciphertext), [UInt8](testVector.ciphertext))
            }
        }
    }
    
    func testEncryptAndDecryptWithAES256() {
        let prng = ObvCryptoSuite.sharedInstance.prngService()
        for _ in 0..<500 {
            let key = AES256.generateKey(with: prng)
            let plaintext = prng.genBytes(count: AES256.blockLength)
            let ciphertext = try! AES256.encrypt(plaintext, underTheKey: key)
            XCTAssertEqual(plaintext, try! AES256.decrypt(ciphertext, underTheKey: key))
        }
        for _ in 0..<500 {
            let key = BlockCipher.generateKey(for: .AES_256, with: prng)
            let plaintext = prng.genBytes(count: AES256.blockLength)
            let ciphertext = try! BlockCipher.encrypt(plaintext, underTheKey: key)
            XCTAssertEqual(plaintext, try! BlockCipher.decrypt(ciphertext, underTheKey: key))
        }
    }

    func testAES256CTR() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsAES256CTR", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForSymmetricEncryptionWithAES256CTR].self, from: jsonData)
        for testVector in testVectors {
            do {
                // Test encryption
                let ciphertext = try! SymmetricEncryptionWithAES256CTR.encrypt(testVector.plaintext, with: testVector.key, andIv: testVector.iv)
                XCTAssertEqual([UInt8](ciphertext), [UInt8](testVector.ciphertext))
                // Test decryption
                let plaintext = try! SymmetricEncryptionWithAES256CTR.decrypt(ciphertext, with: testVector.key)
                XCTAssertEqual([UInt8](plaintext), [UInt8](testVector.plaintext))
            }
            do {
                // Test encryption
                let ciphertext = try! SymmetricEncryption.encrypt(testVector.plaintext, with: testVector.key, andIv: testVector.iv)
                XCTAssertEqual([UInt8](ciphertext), [UInt8](testVector.ciphertext))
                // Test decryption
                let plaintext = try! SymmetricEncryption.decrypt(ciphertext, with: testVector.key)
                XCTAssertEqual([UInt8](plaintext), [UInt8](testVector.plaintext))
            }
        }
    }

    
    func testAES256CTRFromFileWithoutSeek() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsAES256CTR", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForSymmetricEncryptionWithAES256CTR].self, from: jsonData)
        for testVector in testVectors {
            do {
                // Write the plaintext to a temporary file
                let plaintextURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
                let ciphertextURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
                do { try testVector.plaintext.write(to: plaintextURL) } catch { XCTFail(error.localizedDescription) }
                FileManager.default.createFile(atPath: ciphertextURL.path, contents: nil, attributes: nil)
                // Encrypt to file and test encryption
                try! SymmetricEncryptionWithAES256CTR.encrypt(fileAtURL: plaintextURL, startingAtOffset: 0, length: testVector.plaintext.count, with: testVector.key, andIv: testVector.iv, toURL: ciphertextURL)
                let ciphertext = try! Data.init(contentsOf: ciphertextURL)
                XCTAssertEqual([UInt8](ciphertext), [UInt8](testVector.ciphertext))
                // Delete both files
                try! FileManager.default.removeItem(at: plaintextURL)
                try! FileManager.default.removeItem(at: ciphertextURL)
            }
        }
    }

    
    func testAES256CTRFromFileWithSeek() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsAES256CTR", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForSymmetricEncryptionWithAES256CTR].self, from: jsonData)
        for testVector in testVectors {
            do {
                // Write the plaintext to a temporary file (adding random data before and after)
                let plaintextURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
                let ciphertextURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
                let prefixLength = Int.random(in: 0..<32_768)
                let postFixLength = Int.random(in: 0..<32_768)
                let plaintextWithGarbage = Data(repeating: 0x00, count: prefixLength) + testVector.plaintext + Data(repeating: 0x00, count: postFixLength)
                do { try plaintextWithGarbage.write(to: plaintextURL) } catch { XCTFail(error.localizedDescription) }
                FileManager.default.createFile(atPath: ciphertextURL.path, contents: nil, attributes: nil)
                // Encrypt to file and test encryption
                try! SymmetricEncryptionWithAES256CTR.encrypt(fileAtURL: plaintextURL, startingAtOffset: Int64(prefixLength), length: testVector.plaintext.count, with: testVector.key, andIv: testVector.iv, toURL: ciphertextURL)
                let ciphertext = try! Data.init(contentsOf: ciphertextURL)
                XCTAssertEqual([UInt8](ciphertext), [UInt8](testVector.ciphertext))
                // Delete both files
                try! FileManager.default.removeItem(at: plaintextURL)
                try! FileManager.default.removeItem(at: ciphertextURL)
            }
        }
    }

    
    func testAES256CTRUsingCCrypto() {
        let prng = PRNGServiceWithHMACWithSHA256()
        //let startTime = Date()
        for plaintextLength in 0..<2000 {
            let plaintext = prng.genBytes(count: plaintextLength)
            let key = SymmetricEncryptionAES256CTRKey(data: prng.genBytes(count: SymmetricEncryptionAES256CTRKey.length))!
            let iv = prng.genBytes(count: 8)
            let ciphertext1 = try! SymmetricEncryptionWithAES256CTR.encrypt(plaintext, with: key, andIv: iv)
            let ciphertext2 = try! SymmetricEncryptionWithAES256CTRNative.encrypt(plaintext, with: key, andIv: iv)
            XCTAssertEqual([UInt8](ciphertext1), [UInt8](ciphertext2))
        }
//        let timeRequired = Date().timeIntervalSince(startTime)
//        debugPrint("testAES256CTRUsingCCrypto required \(timeRequired)")
    }

    
    func testAES256CTRDecryptionUsingCCrypto() {
        let prng = PRNGServiceWithHMACWithSHA256()
        for plaintextLength in 0..<5000 {
            let plaintext1 = prng.genBytes(count: plaintextLength)
            let key = SymmetricEncryptionAES256CTRKey(data: prng.genBytes(count: SymmetricEncryptionAES256CTRKey.length))!
            let iv = prng.genBytes(count: 8)
            let ciphertext = try! SymmetricEncryptionWithAES256CTR.encrypt(plaintext1, with: key, andIv: iv)
            let plaintext2 = try! SymmetricEncryptionWithAES256CTR.decrypt(ciphertext, with: key)
            XCTAssertEqual([UInt8](plaintext1), [UInt8](plaintext2))
        }
    }
    
    
    func testHMACWithSHA256() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "testVectorsHMACWithSHA256", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForHMACWithSHA256].self, from: jsonData)
        for testVector in testVectors {
            do {
                let mac = try! HMACWithSHA256.compute(forData: testVector.data, withKey: testVector.key)
                XCTAssertEqual([UInt8](mac), [UInt8](testVector.mac))
            }
            do {
                let mac = try! MAC.compute(forData: testVector.data, withKey: testVector.key)
                XCTAssertEqual([UInt8](mac), [UInt8](testVector.mac))
            }
        }
    }
    
    func testPRNGWithHMACWithSHA256() {
        
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsPRNGWithHMACWithSHA256", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForPRNG].self, from: jsonData)
        for testVector in testVectors {
            var rawSeed = Data(capacity: testVector.entropyInput.count + testVector.nonce.count + testVector.personalizationString.count)
            rawSeed.append(testVector.entropyInput)
            rawSeed.append(testVector.nonce)
            rawSeed.append(testVector.personalizationString)
            guard let seed = Seed(with: rawSeed) else { XCTFail(); return }
            let prng = PRNGWithHMACWithSHA256(with: seed)
            for expectedGeneratedBytes in testVector.generatedBytes {
                let generatedBytes = prng.genBytes(count: expectedGeneratedBytes.count)
                XCTAssertEqual([UInt8](generatedBytes), [UInt8](expectedGeneratedBytes))
            }
        }
    }
    
    func testGenRandomBigIntWithPRNGWithHMACWithSHA256() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsPRNGGenBigInt", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForBigIntPRNG].self, from: jsonData)
        for testVector in testVectors {
            guard let seed = Seed(with: testVector.seed) else { XCTFail(); return }
            let prng = PRNGWithHMACWithSHA256(with: seed)
            for (expectedRandomValue, bound) in zip(testVector.values, testVector.bounds) {
                let randomValue = prng.genBigInt(smallerThan: bound)
                XCTAssertEqual(randomValue, expectedRandomValue)
            }
        }
    }
    

    func testPRNGServiceWithHMACWithSHA256() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsPRNGWithHMACWithSHA256", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForPRNG].self, from: jsonData)
        for testVector in testVectors {
            var rawSeed = Data(capacity: testVector.entropyInput.count + testVector.nonce.count + testVector.personalizationString.count)
            rawSeed.append(testVector.entropyInput)
            rawSeed.append(testVector.nonce)
            rawSeed.append(testVector.personalizationString)
            guard let seed = Seed(with: rawSeed) else { XCTFail(); return }
            let prngService = PRNGWithHMACWithSHA256(with: seed)
            for expectedGeneratedBytes in testVector.generatedBytes {
                let generatedBytes = prngService.genBytes(count: expectedGeneratedBytes.count)
                XCTAssertEqual([UInt8](generatedBytes), [UInt8](expectedGeneratedBytes))
            }
        }
    }
    

    func testGenRandomBigIntWithPRNGServiceWithHMACWithSHA256() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsPRNGGenBigInt", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForBigIntPRNG].self, from: jsonData)
        for testVector in testVectors {
            guard let seed = Seed(with: testVector.seed) else { XCTFail(); return }
            let prngService = PRNGWithHMACWithSHA256(with: seed)
            for (expectedRandomValue, bound) in zip(testVector.values, testVector.bounds) {
                let randomValue = prngService.genBigInt(smallerThan: bound)
                XCTAssertEqual(randomValue, expectedRandomValue)
            }
        }
    }
 

    func testAuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsAuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForAuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256].self, from: jsonData)
        for testVector in testVectors {
            do {
                guard let seed = Seed(with: testVector.seed) else { XCTFail(); return }
                let prng = PRNGWithHMACWithSHA256(with: seed)
                // Test encryption
                let ciphertext = try! AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256.encrypt(testVector.plaintext, with: testVector.key, and: prng)
                XCTAssertEqual([UInt8](ciphertext), [UInt8](testVector.ciphertext))
                // Test decryption
                let plaintext = try! AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256.decrypt(ciphertext, with: testVector.key)
                XCTAssertEqual([UInt8](plaintext), [UInt8](testVector.plaintext))
            }
            do {
                guard let seed = Seed(with: testVector.seed) else { XCTFail(); return }
                let prng = PRNGWithHMACWithSHA256(with: seed)
                // Test encryption
                let ciphertext = AuthenticatedEncryption.encrypt(testVector.plaintext, with: testVector.key, and: prng)
                XCTAssertEqual([UInt8](ciphertext), [UInt8](testVector.ciphertext))
                // Test decryption
                let plaintext = try! AuthenticatedEncryption.decrypt(ciphertext, with: testVector.key)
                XCTAssertEqual([UInt8](plaintext), [UInt8](testVector.plaintext))
            }
        }
    }
    
    
    func testLatestAuthenticatedEncryption() {
        let AuthEnc = ObvCryptoSuite.sharedInstance.authenticatedEncryption() // Currently, this returns AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256
        let prng = ObvCryptoSuite.sharedInstance.prngService()
        for _ in 0..<1000 {
            let key = AuthEnc.generateKey(with: nil) //
            let plaintextLength = try! Int(prng.genBigInt(smallerThan: BigInt(10000)))
            let plaintext = prng.genBytes(count: plaintextLength)
            let ciphertext = AuthenticatedEncryption.encrypt(plaintext, with: key, and: nil)
            let recoveredPlaintext = try! AuthenticatedEncryption.decrypt(ciphertext, with: key)
            XCTAssertEqual(plaintext, recoveredPlaintext)
            XCTAssertEqual(try! AuthEnc.plaintexLength(forCiphertextLength: ciphertext.count), plaintext.count)
            XCTAssertEqual(AuthEnc.ciphertextLength(forPlaintextLength: plaintext.count), ciphertext.count)
        }
    }
    
    
    func testLatestAuthenticatedEncryptionSpeed() {
        let AuthEnc = ObvCryptoSuite.sharedInstance.authenticatedEncryption() // Currently, this returns AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256
        let prng = ObvCryptoSuite.sharedInstance.prngService()
        let key = AuthEnc.generateKey(with: prng)
        let plaintext = prng.genBytes(count: 5_000)
        let startTime = Date()
        for _ in 0..<100_000 {
            let _ = AuthenticatedEncryption.encrypt(plaintext, with: key, and: prng)
        }
        let timeRequired = Date().timeIntervalSince(startTime)
        XCTAssert(timeRequired < 10.0) // Less than 5 seconds
    }

    
    func testAuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256FromFileWithoutSeek() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsAuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForAuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256].self, from: jsonData)
        for testVector in testVectors {
            do {
                guard let seed = Seed(with: testVector.seed) else { XCTFail(); return }
                let prng = PRNGWithHMACWithSHA256(with: seed)
                // Write the plaintext to a temporary file
                let plaintextURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
                let ciphertextURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
                do { try testVector.plaintext.write(to: plaintextURL) } catch { XCTFail(error.localizedDescription) }
                FileManager.default.createFile(atPath: ciphertextURL.path, contents: nil, attributes: nil)
                // Encrypt to file and test encryption
                try! AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256.encrypt(fileAtURL: plaintextURL, startingAtOffset: 0, length: testVector.plaintext.count, with: testVector.key, and: prng, toURL: ciphertextURL)
                let ciphertext = try! Data(contentsOf: ciphertextURL)
                XCTAssertEqual([UInt8](ciphertext), [UInt8](testVector.ciphertext))
                // Delete both files
                try! FileManager.default.removeItem(at: plaintextURL)
                try! FileManager.default.removeItem(at: ciphertextURL)
            }
        }
    }
    
    
    func testCompareAuthenticatedEncryptionFromMemoryAndFromURL() {
        let AuthEnc = ObvCryptoSuite.sharedInstance.authenticatedEncryption() // Currently, this returns AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256
        let prng = ObvCryptoSuite.sharedInstance.prngService()
        let plaintextURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
        let ciphertextURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
        for _ in 0..<1000 {
            // Initialize two identical prngs
            let seed = prng.genSeed() //ok
            let prng0 = PRNGWithHMACWithSHA256(with: seed) //ok
            let prng1 = PRNGWithHMACWithSHA256(with: seed)
            // Create a random plaintext
            let key = AuthEnc.generateKey(with: nil) //
            let plaintextLength = try! Int(prng.genBigInt(smallerThan: BigInt(10000)))
            let plaintext = prng.genBytes(count: plaintextLength)
            try! plaintext.write(to: plaintextURL)
            // Encrypt from plaintext in memory
            let ciphertext1 = AuthenticatedEncryption.encrypt(plaintext, with: key, and: prng0)
            // Write the data to a file and encrypt it
            FileManager.default.createFile(atPath: ciphertextURL.path, contents: nil, attributes: nil)
            try! AuthenticatedEncryption.encrypt(fileAtURL: plaintextURL, startingAtOffset: 0, length: plaintextLength, with: key, and: prng1, toURL: ciphertextURL)
            let ciphertext2 = try! Data(contentsOf: ciphertextURL)
            // Compare
            XCTAssertEqual([UInt8](ciphertext1.raw), [UInt8](ciphertext2))
            try! FileManager.default.removeItem(at: ciphertextURL)
        }
        //try! FileManager.default.removeItem(at: plaintextURL)
    }


    
    func testAuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256FromFileWithSeek() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsAuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForAuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256].self, from: jsonData)
        for testVector in testVectors {
            do {
                guard let seed = Seed(with: testVector.seed) else { XCTFail(); return }
                let prng = PRNGWithHMACWithSHA256(with: seed)
                // Write the plaintext to a temporary file
                let plaintextURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
                let ciphertextURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
                let prefixLength = Int.random(in: 0..<32_768)
                let postFixLength = Int.random(in: 0..<32_768)
                let plaintextWithGarbage = Data(repeating: 0x00, count: prefixLength) + testVector.plaintext + Data(repeating: 0x00, count: postFixLength)
                do { try plaintextWithGarbage.write(to: plaintextURL) } catch { XCTFail(error.localizedDescription) }
                FileManager.default.createFile(atPath: ciphertextURL.path, contents: nil, attributes: nil)
                // Encrypt to file and test encryption
                try! AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256.encrypt(fileAtURL: plaintextURL, startingAtOffset: Int64(prefixLength), length: testVector.plaintext.count, with: testVector.key, and: prng, toURL: ciphertextURL)
                let ciphertext = try! Data(contentsOf: ciphertextURL)
                XCTAssertEqual([UInt8](ciphertext), [UInt8](testVector.ciphertext))
                // Delete both files
                try! FileManager.default.removeItem(at: plaintextURL)
                try! FileManager.default.removeItem(at: ciphertextURL)
            }
        }
    }

    
    func testPointOnCurveCurve25519() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsIsOnCurveCurve25519", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForEdwardsCurve].self, from: jsonData)
        for testVector in testVectors {
            XCTAssertNotNil(PointOnCurve(x: testVector.x!, y: testVector.y!, onCurveWithByteId: .Curve25519ByteId))
            XCTAssertNil(PointOnCurve(x: testVector.x2! , y: testVector.y!, onCurveWithByteId: .Curve25519ByteId))
        }
    }

    func testPointOnCurveMDC() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsIsOnCurveMDC", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForEdwardsCurve].self, from: jsonData)
        for testVector in testVectors {
            XCTAssertNotNil(PointOnCurve(x: testVector.x!, y: testVector.y!, onCurveWithByteId: .MDCByteId))
            XCTAssertNil(PointOnCurve(x: testVector.x2! , y: testVector.y!, onCurveWithByteId: .MDCByteId))
        }
    }
    
    func testXCoordinateFromYOnCurve25519() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsIsOnCurveCurve25519", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForEdwardsCurve].self, from: jsonData)
        let curve = Curve25519()
        for testVector in testVectors {
            guard let (point1, point2) = curve.pointsOnCurve(forYcoordinate: testVector.y!) else {
                XCTFail()
                return
            }
            XCTAssert(testVector.x == point1.x || testVector.x == point2.x)
        }
    }

    func testXCoordinateFromYOnCurveMDC() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsIsOnCurveMDC", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForEdwardsCurve].self, from: jsonData)
        let curve = CurveMDC()
        for testVector in testVectors {
            guard let (point1, point2) = curve.pointsOnCurve(forYcoordinate: testVector.y!) else {
                XCTFail()
                return
            }
            XCTAssert(testVector.x == point1.x || testVector.x == point2.x)
        }
    }

    func testPointsOnCurveAndPointIsOnCurve() {
        // We choose a y for which we know that x's exist on Curve25519.
        let curve25519 = Curve25519()
        let y = try! BigInt("28948022309329048855892746252171976963317496166410141009864396001978282409972")
        let (point1, point2) = curve25519.pointsOnCurve(forYcoordinate: y)!
        let computedXCoordinates: Set<BigInt> = [point1.x, point2.x]
        let expectedXCoordinates: Set<BigInt> = [try! BigInt("38917511199502689536259284455909343854654668289251455506793045931053174163997"),
                                                 try! BigInt("18978533419155408175526208048434610071980324043568826512935746072903390655952")]
        XCTAssertEqual(computedXCoordinates, expectedXCoordinates)
        XCTAssertTrue(point1.onCurveWithByteId == EdwardsCurveByteId.Curve25519ByteId)
        XCTAssertTrue(point2.onCurveWithByteId == EdwardsCurveByteId.Curve25519ByteId)
        // We choose another y, for which no point exist on Curve25519
        try! y.set("28948022309329048855892746252171976963317496166410141009864396001978282409973")
        guard curve25519.pointsOnCurve(forYcoordinate: y) == nil else {
            XCTFail()
            return
        }
    }

    func testFixedAddtionOnMDC() {
        let curveMDC = CurveMDC()
        let pointP = PointOnCurve(x: try! BigInt("26926286912707212984851849530098714424667601252981694206161593602596842431391"),
                                  y: try! BigInt("5456905123696657259759107481936513081225861366744333629652350178402361417785"),
                                  onCurveWithByteId: curveMDC.byteId)!
        let pointQ = PointOnCurve(x: try! BigInt("40925455819463360826860655029472922055904763516916222833288091586413709973852"),
                                  y: try! BigInt("91190939406558957767439196887396192154354052008741953387657582196834655948691"),
                                  onCurveWithByteId: curveMDC.byteId)!
        XCTAssertTrue(pointP.onCurveWithByteId == curveMDC.byteId)
        XCTAssertTrue(pointQ.onCurveWithByteId == curveMDC.byteId)
        let Px = BigInt(pointP.x)
        let Py = BigInt(pointP.y)
        let Qx = BigInt(pointQ.x)
        let Qy = BigInt(pointQ.y)
        let pointR = curveMDC.add(point: pointP, withPoint: pointQ)!
        XCTAssertTrue(pointR.onCurveWithByteId == curveMDC.byteId)
        let expectedPointR = PointOnCurve(x: try! BigInt("24412056480195062022556665521641511918322922555493540862278897801578629047523"),
                                          y: try! BigInt("84599690519184401412549724368908336923446920305826884235247446681859838035108"),
                                          onCurveWithByteId: curveMDC.byteId)!
        XCTAssertEqual(pointR, expectedPointR)
        // Make sure that pointP was not mutated during the process
        XCTAssertEqual(pointP.x, Px)
        XCTAssertEqual(pointP.y, Py)
        XCTAssertEqual(pointQ.x, Qx)
        XCTAssertEqual(pointQ.y, Qy)
    }

    
    func testPointsOfSmallOrderOnEdwardsCurve() {
        var curves = [EdwardsCurve]()
        curves.append(Curve25519())
        curves.append(CurveMDC())

        for curve in curves {

            let pointAtInfinity = curve.getPointAtInfinity()
            let pointOfOrder2 = curve.getPointOfOrderTwo()
            let (pointOfOrder4_1, pointOfOrder4_2) = curve.getPointsOfOrderFour()

            XCTAssertEqual(curve.parameters.G.onCurveWithByteId, curve.byteId)
            XCTAssertEqual(pointAtInfinity.onCurveWithByteId, curve.byteId)
            XCTAssertEqual(pointOfOrder2.onCurveWithByteId, curve.byteId)
            XCTAssertEqual(pointOfOrder4_1.onCurveWithByteId, curve.byteId)
            XCTAssertEqual(pointOfOrder4_2.onCurveWithByteId, curve.byteId)

            for n in 0..<100 {
                XCTAssertEqual(curve.getPointAtInfinity().y ,
                               curve.scalarMultiplication(scalar: BigInt(n), yCoordinate: pointAtInfinity.y))
                XCTAssertEqual(curve.getPointAtInfinity() ,
                               curve.scalarMultiplication(scalar: BigInt(n), point: pointAtInfinity))
            }
            
            XCTAssertEqual(pointAtInfinity.y,
                           curve.scalarMultiplication(scalar: BigInt(2), yCoordinate: pointOfOrder2.y))
            XCTAssertEqual(pointAtInfinity.y,
                           curve.scalarMultiplication(scalar: BigInt(4), yCoordinate: pointOfOrder4_1.y))
            XCTAssertEqual(pointAtInfinity.y,
                           curve.scalarMultiplication(scalar: BigInt(4), yCoordinate: pointOfOrder4_2.y))
            
            XCTAssertEqual(pointAtInfinity,
                           curve.scalarMultiplication(scalar: BigInt(2), point: pointOfOrder2))
            XCTAssertEqual(pointAtInfinity,
                           curve.scalarMultiplication(scalar: BigInt(4), point: pointOfOrder4_1))
            XCTAssertEqual(pointAtInfinity,
                           curve.scalarMultiplication(scalar: BigInt(4), point: pointOfOrder4_2))

        }
    }
    
    func testSimpleScalarMultiplicationsForFixedPoint() {
        let pointP = PointOnCurve(x: try! BigInt("63818240566781518740636218113320467026060602342834058135906153766031597012147"),
                                  y: try! BigInt("36631876470030997325435186440201271827372980350334529431614623981369427578982"),
                                  onCurveWithByteId: EdwardsCurveByteId.MDCByteId)!
        let curve = CurveMDC()
        let doubleP = curve.add(point: pointP, withPoint: pointP)!
        let expectedDoubleP = PointOnCurve(x: try! BigInt("5341886641984798922505720296465259185834919606160597102391932801121735222363"),
                                           y: try! BigInt("78714519783538993017271773696077087272897326208082857761287466498510289109908"),
                                           onCurveWithByteId: EdwardsCurveByteId.MDCByteId)!
        XCTAssertEqual(doubleP, expectedDoubleP)
        let doublePy = curve.scalarMultiplication(scalar: BigInt(2), yCoordinate: pointP.y)!
        XCTAssertEqual(doubleP.y, doublePy)
    }
    
    func testCompareScalarMultiplicationAndNaivePointAddition() {
        var curves = [EdwardsCurve]()
        curves.append(Curve25519())
        curves.append(CurveMDC())

        for curve in curves {
            for _ in 0..<1000 {
                let pointP = ObvCryptoTests.findRandomPoint(onCurve: curve)
                let n = Int(arc4random()) % 100 + 1
                // Compute n*P both in a naive way and fast way
                var pointR1 = PointOnCurve(with: pointP)
                for _ in 0..<n-1 {
                    pointR1 = curve.add(point: pointR1, withPoint: pointP)!
                }
                let pointRy = curve.scalarMultiplication(scalar: BigInt(n), yCoordinate: pointP.y)!
                let pointR2 = curve.scalarMultiplication(scalar: BigInt(n), point: pointP)!
                // Test and compare
                XCTAssertEqual(pointR1.onCurveWithByteId, curve.byteId)
                XCTAssertEqual(pointR2.onCurveWithByteId, curve.byteId)
                XCTAssertEqual(pointR1.y, pointRy)
                XCTAssertEqual(pointR2.y, pointRy)
            }
        }
    }
    
    func testScalarMultiplicationOnCurve25519WithoutX() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsScalarMultiplicationCurve25519", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForEdwardsCurve].self, from: jsonData)
        let curve = Curve25519()
        for testVector in testVectors {
            guard let ny = curve.scalarMultiplication(scalar: testVector.n!, yCoordinate: testVector.y!) else {
                XCTFail()
                return
            }
            XCTAssertEqual(ny, testVector.ny!)
        }
    }

    func testScalarMultiplicationOnMDCWithoutX() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsScalarMultiplicationMDC", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForEdwardsCurve].self, from: jsonData)
        let curve = CurveMDC()
        for testVector in testVectors {
            guard let ny = curve.scalarMultiplication(scalar: testVector.n!, yCoordinate: testVector.y!) else {
                XCTFail()
                return
            }
            XCTAssertEqual(ny, testVector.ny!)
        }
    }
    
    func testScalarMultiplicationOnCurve25519WithX() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsScalarMultiplicationWithXCurve25519", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForEdwardsCurve].self, from: jsonData)
        let curve = Curve25519()
        let curveByteId = EdwardsCurveByteId.Curve25519ByteId
        for testVector in testVectors {
            let P = PointOnCurve(x: testVector.x!, y: testVector.y!, onCurveWithByteId: curveByteId)!
            let expectedQ = PointOnCurve(x: testVector.x2!, y: testVector.y2!, onCurveWithByteId: curveByteId)
            guard let Q = curve.scalarMultiplication(scalar: testVector.n!, point: P) else {
                XCTFail()
                return
            }
            XCTAssertEqual(Q, expectedQ)
        }
    }

    
    func testScalarMultiplicationOnMDCWithX() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsScalarMultiplicationWithXMDC", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForEdwardsCurve].self, from: jsonData)
        let curve = CurveMDC()
        let curveByteId = EdwardsCurveByteId.MDCByteId
        for testVector in testVectors {
            let P = PointOnCurve(x: testVector.x!, y: testVector.y!, onCurveWithByteId: curveByteId)!
            let expectedQ = PointOnCurve(x: testVector.x2!, y: testVector.y2!, onCurveWithByteId: curveByteId)
            guard let Q = curve.scalarMultiplication(scalar: testVector.n!, point: P) else {
                XCTFail()
                return
            }
            XCTAssertEqual(Q, expectedQ)
        }
    }


    func testMulAddCoherence() {
        
        var curves = [EdwardsCurve]()
        curves.append(Curve25519())
        curves.append(CurveMDC())
        let prngService = PRNGServiceWithHMACWithSHA256()

        for curve in curves {
            for _ in 0..<100 {
                let point1 = ObvCryptoTests.findRandomPoint(onCurve: curve)
                let point2 = ObvCryptoTests.findRandomPoint(onCurve: curve)
                let a = prngService.genBigInt(smallerThan: curve.parameters.q)
                let b = prngService.genBigInt(smallerThan: curve.parameters.q)
                let point3 = curve.mulAdd(a: a, point1: point1, b: b, point2: point2)!
                let (point3_1, point3_2) = curve.mulAdd(a: a, point1: point1, b: b, yCoordinateOfPoint2: point2.y)!
                XCTAssertTrue(point3 == point3_1 || point3 == point3_2)
            }
        }
    }
    
    func testMulAddFunctionsOnCurve25519() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsMulAddCurve25519", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForEdwardsCurve].self, from: jsonData)
        let curve = Curve25519()
        let curveByteId = EdwardsCurveByteId.Curve25519ByteId
        for testVector in testVectors {
            let a = testVector.a!
            let b = testVector.b!
            let P = PointOnCurve(x: testVector.x!, y: testVector.y!, onCurveWithByteId: curveByteId)!
            let Q = PointOnCurve(x: testVector.x2! , y: testVector.y2!, onCurveWithByteId: curveByteId)!
            let expectedR = PointOnCurve(x: testVector.x3!, y: testVector.y3!, onCurveWithByteId: curveByteId)!
            let R = curve.mulAdd(a: a, point1: P, b: b, point2: Q)!
            XCTAssertEqual(R, expectedR)
            let points = curve.mulAdd(a: a, point1: P, b: b, yCoordinateOfPoint2: Q.y)!
            XCTAssert(R == points.0 || R == points.1)
            let expectedPoints = (PointOnCurve(x: testVector.x4!, y: testVector.y4!, onCurveWithByteId: curveByteId),
                                  PointOnCurve(x: testVector.x5!, y: testVector.y5!, onCurveWithByteId: curveByteId))
            XCTAssert((points.0 == expectedPoints.0 && points.1 == expectedPoints.1) ||
                      (points.0 == expectedPoints.1 && points.1 == expectedPoints.0))
        }
    }

    
    func testMulAddFunctionsOnCurveMDC() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsMulAddMDC", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForEdwardsCurve].self, from: jsonData)
        let curve = CurveMDC()
        let curveByteId = EdwardsCurveByteId.MDCByteId
        for testVector in testVectors {
            let a = testVector.a!
            let b = testVector.b!
            let P = PointOnCurve(x: testVector.x!, y: testVector.y!, onCurveWithByteId: curveByteId)!
            let Q = PointOnCurve(x: testVector.x2! , y: testVector.y2!, onCurveWithByteId: curveByteId)!
            let expectedR = PointOnCurve(x: testVector.x3!, y: testVector.y3!, onCurveWithByteId: curveByteId)!
            let R = curve.mulAdd(a: a, point1: P, b: b, point2: Q)!
            XCTAssertEqual(R, expectedR)
            let points = curve.mulAdd(a: a, point1: P, b: b, yCoordinateOfPoint2: Q.y)!
            XCTAssert(R == points.0 || R == points.1)
            let expectedPoints = (PointOnCurve(x: testVector.x4!, y: testVector.y4!, onCurveWithByteId: curveByteId),
                                  PointOnCurve(x: testVector.x5!, y: testVector.y5!, onCurveWithByteId: curveByteId))
            XCTAssert((points.0 == expectedPoints.0 && points.1 == expectedPoints.1) ||
                (points.0 == expectedPoints.1 && points.1 == expectedPoints.0))
        }
    }

    
    func testScalarMulToIdentitElement() {
        // Compute (n1+n2)G where n1+n2=q
        var curves = [EdwardsCurve]()
        curves.append(Curve25519())
        curves.append(CurveMDC())
        let prngService = PRNGServiceWithHMACWithSHA256()
        
        for curve in curves {
            for _ in 0..<100 {
                let n1 = prngService.genBigInt(smallerThan: curve.parameters.q)
                let n2 = BigInt(curve.parameters.q).sub(n1)
                let point1 = curve.scalarMultiplication(scalar: n1, point: curve.parameters.G)!
                let point2 = curve.scalarMultiplication(scalar: n2, point: curve.parameters.G)!
                let pointR = curve.add(point: point1, withPoint: point2)!
                XCTAssertEqual(pointR, curve.getPointAtInfinity())
            }
        }
    }
    
    func testPointAdditionOnCurve25519() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsPointAdditionCurve25519", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForEdwardsCurve].self, from: jsonData)
        let curve = Curve25519()
        let curveByteId = EdwardsCurveByteId.Curve25519ByteId
        for testVector in testVectors {
            let P = PointOnCurve(x: testVector.x!, y: testVector.y!, onCurveWithByteId: curveByteId)!
            let Q = PointOnCurve(x: testVector.x2! , y: testVector.y2!, onCurveWithByteId: curveByteId)!
            let expectedR = PointOnCurve(x: testVector.x3!, y: testVector.y3!, onCurveWithByteId: curveByteId)!
            guard let R = curve.add(point: P, withPoint: Q) else { XCTFail(); return }
            XCTAssertEqual(R, expectedR)
        }
    }

    
    func testPointAdditionOnMDC() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsPointAdditionMDC", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForEdwardsCurve].self, from: jsonData)
        let curve = CurveMDC()
        let curveByteId = EdwardsCurveByteId.MDCByteId
        for testVector in testVectors {
            let P = PointOnCurve(x: testVector.x!, y: testVector.y!, onCurveWithByteId: curveByteId)!
            let Q = PointOnCurve(x: testVector.x2! , y: testVector.y2!, onCurveWithByteId: curveByteId)!
            let expectedR = PointOnCurve(x: testVector.x3!, y: testVector.y3!, onCurveWithByteId: curveByteId)!
            guard let R = curve.add(point: P, withPoint: Q) else { XCTFail(); return }
            XCTAssertEqual(R, expectedR)
        }
    }
    
    func testKDFFromPRNGWithHMACWithSHA256() {
        let rawSeed = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
                            0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F,
                            0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F,
                            0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27])
        guard let seed = Seed(with: rawSeed) else { XCTFail(); return }
        let key = KDFFromPRNGWithHMACWithSHA256.generate(from: seed, { AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key(data: $0)! })!
        let dataOfExpectedKey = Data([0xD6, 0x7B, 0x8C, 0x17, 0x34, 0xF4, 0x6F, 0xA3, 0xF7, 0x63, 0xCF, 0x57, 0xC6, 0xF9, 0xF4, 0xF2,
                                      0xDC, 0x10, 0x89, 0xBD, 0x8B, 0xC1, 0xF6, 0xF0, 0x23, 0x95, 0x0B, 0xFC, 0x56, 0x17, 0x63, 0x52,
                                      0x08, 0xC8, 0x50, 0x12, 0x38, 0xAD, 0x7A, 0x44, 0x00, 0xDE, 0xFE, 0xE4, 0x6C, 0x64, 0x0B, 0x61,
                                      0xAF, 0x77, 0xC2, 0xD1, 0xA3, 0xBF, 0xAA, 0x90, 0xED, 0xE5, 0xD2, 0x07, 0x40, 0x6E, 0x54, 0x03])
        let expectedKey = AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key(data: dataOfExpectedKey)!
        XCTAssertEqual(key, expectedKey)
    }
    
    func testKDFWithSuiteVersion() {
        let rawSeed = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
                            0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F,
                            0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F,
                            0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27])
        let KDF = ObvCryptoSuite.sharedInstance.kdf()
        guard let seed = Seed(with: rawSeed) else { XCTFail(); return }
        let key = KDF.generate(from: seed, { AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key(data: $0)! })!
        let dataOfExpectedKey = Data([0xD6, 0x7B, 0x8C, 0x17, 0x34, 0xF4, 0x6F, 0xA3, 0xF7, 0x63, 0xCF, 0x57, 0xC6, 0xF9, 0xF4, 0xF2,
                                      0xDC, 0x10, 0x89, 0xBD, 0x8B, 0xC1, 0xF6, 0xF0, 0x23, 0x95, 0x0B, 0xFC, 0x56, 0x17, 0x63, 0x52,
                                      0x08, 0xC8, 0x50, 0x12, 0x38, 0xAD, 0x7A, 0x44, 0x00, 0xDE, 0xFE, 0xE4, 0x6C, 0x64, 0x0B, 0x61,
                                      0xAF, 0x77, 0xC2, 0xD1, 0xA3, 0xBF, 0xAA, 0x90, 0xED, 0xE5, 0xD2, 0x07, 0x40, 0x6E, 0x54, 0x03])
        let expectedKey = AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key(data: dataOfExpectedKey)!
        XCTAssertEqual(key, expectedKey)
    }
    

    /// We Generate a key pair for KEM_ECIES256KEM512 and compare the encoded values to expected values
    func testKEM_ECIES256KEM512GenerateKeyPair() {
        let rawSeed = Data(repeating: 0x55, count: 64)
        guard let seed = Seed(with: rawSeed) else { XCTFail(); return }
        let prng = PRNGWithHMACWithSHA256(with: seed)
        let (encryptionPubKey, decryptionSecKey) = KEM_ECIES256KEM512_WithMDC.generateKeyPair(with: prng)
        // Test the generated pub key
        let expectedPubKey = PublicKeyForPublicKeyEncryptionOnEdwardsCurve(point: PointOnCurve(x: try! BigInt("79846377751654517849505618688376175741947270243169077237179014488576901404964"),
                                                                                            y: try! BigInt("98910258655353414467028540929679317387195966273370592341032403743470448238163"),
                                                                                            onCurveWithByteId: .MDCByteId)!)!
        XCTAssertEqual(encryptionPubKey.algorithmImplementationByteId, expectedPubKey.algorithmImplementationByteId)
        XCTAssertEqual(encryptionPubKey.algorithmClass, CryptographicAlgorithmClassByteId.publicKeyEncryption)
        guard let encryptionPubKeyOnEdCurve = encryptionPubKey as? PublicKeyForPublicKeyEncryptionOnEdwardsCurve else { XCTFail(); return }
        XCTAssertEqual(encryptionPubKeyOnEdCurve.curveByteId, expectedPubKey.curveByteId)
        XCTAssertEqual(encryptionPubKeyOnEdCurve.point!, expectedPubKey.point!)
        XCTAssertEqual(encryptionPubKeyOnEdCurve.yCoordinate, expectedPubKey.yCoordinate)
        // Test the generated sec key
        let expectedSecKey = PrivateKeyForPublicKeyEncryptionOnEdwardsCurve(scalar: try! BigInt("8069776613763975575036116241502152333794423131970318364452172052316024950949"), curveByteId: .MDCByteId)
        XCTAssertEqual(decryptionSecKey.algorithmImplementationByteId, expectedSecKey.algorithmImplementationByteId)
        guard let decryptionSecKeyOnEdCurve = decryptionSecKey as? PrivateKeyForPublicKeyEncryptionOnEdwardsCurve else { XCTFail(); return }
        XCTAssertEqual(decryptionSecKeyOnEdCurve.curveByteId, expectedSecKey.curveByteId)
        XCTAssertEqual(decryptionSecKeyOnEdCurve.scalar, expectedSecKey.scalar)
    }

    
    func test_KEM_ECIES256KEM512_encrypt_then_decrypt() {
        let point = PointOnCurve(x: try! BigInt("79846377751654517849505618688376175741947270243169077237179014488576901404964"),
                                 y: try! BigInt("98910258655353414467028540929679317387195966273370592341032403743470448238163"),
                                 onCurveWithByteId: .MDCByteId)!
        let encryptionPubKey: PublicKeyForPublicKeyEncryption = PublicKeyForPublicKeyEncryptionOnEdwardsCurve(point: point)!
        let rawSeed = Data(repeating: 0xaa, count: 64)
        guard let seed = Seed(with: rawSeed) else { XCTFail(); return }
        let prng = PRNGWithHMACWithSHA256(with: seed)
        let (encryptedData, symKey) = KEM_ECIES256KEM512_WithMDC.encrypt(using: encryptionPubKey, with: prng, { AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key(data: $0)! })!
        let expectedEncryptedData = EncryptedData(bytes: [0xa2, 0xae, 0xb4, 0xc9, 0x14, 0x7d, 0x5f, 0x4e,
                                                          0xdf, 0xef, 0x7f, 0x77, 0xbe, 0xc2, 0x00, 0xb1,
                                                          0xb7, 0x6b, 0x6d, 0xb2, 0x98, 0xb3, 0x55, 0xe1,
                                                          0xb7, 0x9f, 0x45, 0xca, 0x33, 0xfa, 0xb9, 0x97])
        XCTAssertEqual(encryptedData, expectedEncryptedData)
        let expectedSymKey = AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key(data: Data([0x8b, 0x96, 0x32, 0x4d, 0x60, 0xb3, 0x1c, 0x6a,
                                                                                                   0x90, 0xe5, 0x3e, 0x15, 0x14, 0x3a, 0x7c, 0xe2,
                                                                                                   0x64, 0xdc, 0x0b, 0xa7, 0x6b, 0xc3, 0xc4, 0x90,
                                                                                                   0x6a, 0x77, 0xef, 0xd3, 0x94, 0x3d, 0x1e, 0xf1,
                                                                                                   0x18, 0x84, 0x2c, 0xee, 0xf8, 0x29, 0x3c, 0xc5,
                                                                                                   0xa1, 0xa9, 0x8c, 0x21, 0x43, 0x85, 0xbb, 0x79,
                                                                                                   0x93, 0x80, 0x44, 0x98, 0x8d, 0xbb, 0x4c, 0xcd,
                                                                                                   0x9d, 0xee, 0x54, 0x24, 0x61, 0xdf, 0x13, 0x26]))!
        XCTAssertEqual(symKey, expectedSymKey)
        // Test the decryption part
        let scalar = try! BigInt("8069776613763975575036116241502152333794423131970318364452172052316024950949")
        let decryptionSecKey: PrivateKeyForPublicKeyEncryption = PrivateKeyForPublicKeyEncryptionOnEdwardsCurve(scalar: scalar, curveByteId: .MDCByteId)
        let recoveredSymKey = KEM_ECIES256KEM512_WithMDC.decrypt(encryptedData, using: decryptionSecKey, { AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key(data: $0)! })!
        XCTAssertEqual(recoveredSymKey, symKey)
    }

    
    /// Validates the decoding of an encryption public key on an Edwards Curve. We create
    /// 1. public key from the parameters found in the test vector
    /// 2. an encoded public key from the corresponding field in the test vector, and decode it
    /// Then we compare the two keys
    func testObvDecodeAnEncryptionPublicKey() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsForObvEncodeAPublicKeyEncryptionPublicKey", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForPublicKeyEncryptionOverEdwardsCurve].self, from: jsonData)
        for testVector in testVectors {
            // Create the public key from x, y, ...
            let algorithmImplementation = PublicKeyEncryptionImplementationByteId(rawValue: testVector.algorithmImplementationByteIdValue)!
            let curveByteId: EdwardsCurveByteId
            switch algorithmImplementation{
            case .KEM_ECIES_MDC_and_DEM_CTR_AES_256_then_HMAC_SHA_256:
                curveByteId = .MDCByteId
            case .KEM_ECIES_Curve25519_and_DEM_CTR_AES_256_then_HMAC_SHA_256:
                curveByteId = .Curve25519ByteId
            }
            let point = PointOnCurve(x: testVector.xCoordinate!, y: testVector.yCoordinate!, onCurveWithByteId: curveByteId)!
            let publicKey = PublicKeyForPublicKeyEncryptionOnEdwardsCurve(point: point)!
            let decodedPublicKey = PublicKeyForPublicKeyEncryptionOnEdwardsCurve(testVector.encodedPublicKey!)!
            XCTAssertEqual(publicKey, decodedPublicKey)
        }
    }
    
    func testEncodeThenDecodeAnEncryptionPublicKey() {
        let prng = PRNGServiceWithHMACWithSHA256()
        for _ in 0..<100 {
            let publicKey = ECIESwithMDCandDEMwithCTRAES256thenHMACSHA256.generateKeyPair(with: prng).0
            let encodedPublicKey = publicKey.obvEncode()
            let genericDecodedPublicKey: PublicKeyForPublicKeyEncryption = PublicKeyForPublicKeyEncryptionOnEdwardsCurve.init(encodedPublicKey)!
            let decodedPublicKey = genericDecodedPublicKey as! PublicKeyForPublicKeyEncryptionOnEdwardsCurve // cast is required to compare keys
            XCTAssertTrue(decodedPublicKey.isEqualTo(other: publicKey))
        }
    }
    
    /// Validates the decoding of an decryption private key on an Edwards Curve. We create
    /// 1. private key from the parameters found in the test vector
    /// 2. an encoded private key from the corresponding field in the test vector, and decode it
    /// Then we compare the two keys
    func testObvDecodeAnDecryptionPrivateKey() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsForObvEncodeAPublicKeyEncryptionPrivateKey", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForPublicKeyEncryptionOverEdwardsCurve].self, from: jsonData)
        for testVector in testVectors {
            // Create the private key from scalar, ...
            let algorithmImplementation = PublicKeyEncryptionImplementationByteId(rawValue: testVector.algorithmImplementationByteIdValue)!
            let curveByteId: EdwardsCurveByteId
            switch algorithmImplementation{
            case .KEM_ECIES_MDC_and_DEM_CTR_AES_256_then_HMAC_SHA_256:
                curveByteId = .MDCByteId
            case .KEM_ECIES_Curve25519_and_DEM_CTR_AES_256_then_HMAC_SHA_256:
                curveByteId = .Curve25519ByteId
            }
            let privateKey = PrivateKeyForPublicKeyEncryptionOnEdwardsCurve.init(scalar: testVector.scalar!, curveByteId: curveByteId)
            let decodedPrivateKey = PrivateKeyForPublicKeyEncryptionOnEdwardsCurve(testVector.encodedPrivateKey!)!
            XCTAssertEqual(privateKey, decodedPrivateKey)
        }
    }


    func testEncodeThenDecodeAnDecryptionPrivateKey() {
        let prng = PRNGServiceWithHMACWithSHA256()
        for _ in 0..<100 {
            let privateKey = ECIESwithMDCandDEMwithCTRAES256thenHMACSHA256.generateKeyPair(with: prng).1
            let encodedPrivateKey = privateKey.obvEncode()
            let genericDecodedPrivateKey: PrivateKeyForPublicKeyEncryption = PrivateKeyForPublicKeyEncryptionOnEdwardsCurve(encodedPrivateKey)!
            let decodedPrivateKey = genericDecodedPrivateKey as! PrivateKeyForPublicKeyEncryptionOnEdwardsCurve // cast is required to compare keys
            XCTAssertTrue(decodedPrivateKey.isEqualTo(other: privateKey))
        }
    }
    

    func testPublicKeyEncryption() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsForPublickKeyEncryption", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForPublicKeyEncryptionOverEdwardsCurve].self, from: jsonData)
        for testVector in testVectors {
            let publicKey = PublicKeyForPublicKeyEncryptionOnEdwardsCurve(testVector.encodedPublicKey!)!
            let plaintext = testVector.plaintext!
            guard let seed = Seed(with: testVector.seed!) else { XCTFail(); return }
            let prng = PRNGWithHMACWithSHA256(with: seed)
            let ciphertext = PublicKeyEncryption.encrypt(plaintext, using: publicKey, and: prng)
            XCTAssertEqual(ciphertext, testVector.ciphertext!)
        }
    }

    
    func testPublicKeyDecryptionFromEncryption() {
        let prngService = PRNGServiceWithHMACWithSHA256()
        for _ in 0..<100 {
            let (publicKey, privateKey) = ECIESwithMDCandDEMwithCTRAES256thenHMACSHA256.generateKeyPair(with: prngService)
            let plaintextLength = Int(arc4random()) % 10000 + 1
            let plaintext = prngService.genBytes(count: plaintextLength)
            guard let ciphertext = PublicKeyEncryption.encrypt(plaintext, using: publicKey, and: prngService) else { XCTFail(); return }
            let recoveredPlaintext = PublicKeyEncryption.decrypt(ciphertext, using: privateKey)
            if recoveredPlaintext == nil {
                XCTFail()
            }
            XCTAssertEqual(plaintext, recoveredPlaintext!)
        }
    }
    
    
    func testPublicKeyDecryptionFromEncryptionAsKEM() {
        let prngService = PRNGServiceWithHMACWithSHA256()
        for _ in 0..<100 {
            let (publicKey, privateKey) = ECIESwithMDCandDEMwithCTRAES256thenHMACSHA256.generateKeyPair(with: prngService)
            guard let (c, key) = PublicKeyEncryption.kemEncrypt(using: publicKey, with: prngService) else { XCTFail(); return }
            guard let recoveredKey = PublicKeyEncryption.kemDecrypt(c, using: privateKey) else { XCTFail(); return }
            XCTAssertEqual(key.data, recoveredKey.data)
        }
    }
    

    func testPublicKeyEncryptionAsKEMThenDEM() {
        let prngService = PRNGServiceWithHMACWithSHA256()
        for _ in 0..<100 {
            let plaintextLength = Int(arc4random()) % 10000 + 1
            let plaintext = prngService.genBytes(count: plaintextLength)
            let (publicKey, privateKey) = ECIESwithMDCandDEMwithCTRAES256thenHMACSHA256.generateKeyPair(with: prngService)
            guard let (c, key) = PublicKeyEncryption.kemEncrypt(using: publicKey, with: prngService) else { XCTFail(); return }
            let ciphertext = AuthenticatedEncryption.encrypt(plaintext, with: key, and: prngService)
            guard let recoveredKey = PublicKeyEncryption.kemDecrypt(c, using: privateKey) else { XCTFail(); return }
            guard let recoveredPlaintext = try? AuthenticatedEncryption.decrypt(ciphertext, with: recoveredKey) else { XCTFail(); return }
            XCTAssertEqual(plaintext, recoveredPlaintext)
        }
    }

    
    func testSignature() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsForSignature", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForPublicKeyEncryptionOverEdwardsCurve].self, from: jsonData)
        for testVector in testVectors {
            let message = testVector.plaintext!
            let publicKey = PublicKeyForSignatureOnEdwardsCurve(testVector.encodedPublicKey!)!
            let privateKey = PrivateKeyForSignatureOnEdwardsCurve(testVector.encodedPrivateKey!)!
            guard let seed = Seed(with: testVector.seed!) else { XCTFail(); return }
            let prng = PRNGWithHMACWithSHA256(with: seed)
            let signature = Signature.sign(message, with: privateKey, and: publicKey, using: prng)!
            XCTAssertEqual(signature, testVector.signature!)
        }
    }
    

    func testVerifyingEmptySignatureShouldNotCrash() {
        do {
            let prngService = PRNGServiceWithHMACWithSHA256()
            let (pk, _) = SignatureECSDSA256overMDC.generateKeyPair(with: prngService)
            let message = Data([0x00]) // Not important
            let signature = Data([]) // Cannot be valid but should not crash the validation procedure
            let isValid = try Signature.verify(signature, on: message, with: pk)
            XCTAssert(isValid == false)
        } catch {
            XCTFail(error.localizedDescription)
        }
    }
    

    func testSignatureKeyGen() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsForSignatureKeyGen", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForPublicKeyEncryptionOverEdwardsCurve].self, from: jsonData)
        for testVector in testVectors {
            guard let seed = Seed(with: testVector.seed!) else { XCTFail(); return }
            let prng = PRNGWithHMACWithSHA256(with: seed)
            let algorithmImplementation = SignatureImplementationByteId(rawValue: testVector.algorithmImplementationByteIdValue)!
            let (_pk, _sk) = Signature.generateKeyPair(for: algorithmImplementation, with: prng)
            let pk = _pk as! PublicKeyForSignatureOnEdwardsCurve
            let sk = _sk as! PrivateKeyForSignatureOnEdwardsCurve
            let pkFromTestVector = PublicKeyForSignatureOnEdwardsCurve(testVector.encodedPublicKey!)!
            let skFromTestVector = PrivateKeyForSignatureOnEdwardsCurve(testVector.encodedPrivateKey!)!
            XCTAssertEqual(pk, pkFromTestVector)
            XCTAssertEqual(sk, skFromTestVector)
        }
    }
    

    func testSignThenVerifyOverMDC() {
        do {
            let prngService = PRNGServiceWithHMACWithSHA256()
            for _ in 0..<100 {
                let (pk, sk) = SignatureECSDSA256overMDC.generateKeyPair(with: prngService)
                let messageLength = (Int(arc4random()) % 10000) + 1
                let message = prngService.genBytes(count: messageLength)
                guard let signature = Signature.sign(message, with: sk, and: pk, using: prngService) else { XCTFail(); return }
                let isValid = try Signature.verify(signature, on: message, with: pk)
                XCTAssertTrue(isValid)
            }
        } catch {
            XCTFail(error.localizedDescription)
        }
    }


    func testSignThenVerifyOverCurve25519() {
        do {
            let prngService = PRNGServiceWithHMACWithSHA256()
            for _ in 0..<100 {
                let (pk, sk) = SignatureECSDSA256overCurve25519.generateKeyPair(with: prngService)
                let messageLength = (Int(arc4random()) % 10000) + 1
                let message = prngService.genBytes(count: messageLength)
                let signature = Signature.sign(message, with: sk, and: pk, using: prngService)!
                let isValid = try Signature.verify(signature, on: message, with: pk)
                XCTAssertTrue(isValid)
            }
        } catch {
            XCTFail(error.localizedDescription)
        }
    }


    func testCommitment() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsForCommitment", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForCommitment].self, from: jsonData)
        for testVector in testVectors {
            guard let seed = Seed(with: testVector.seed) else { XCTFail(); return }
            let prng = PRNGWithHMACWithSHA256(with: seed)
            let (commitment, decommitmentToken) = CommitmentWithSHA256.commit(onTag: testVector.tag, andValue: testVector.value, with: prng)
            XCTAssertEqual(commitment, testVector.commitment)
            XCTAssertEqual(decommitmentToken, testVector.decommitmentToken)
        }
    }
    

    func testOpenCommitment() {
        let prngService = PRNGServiceWithHMACWithSHA256()
        for _ in 0..<100 {
            let tagLength = (Int(arc4random()) % 1000) + 1
            let tag = prngService.genBytes(count: tagLength)
            let valueLength = (Int(arc4random()) % 1000) + 1
            let value = prngService.genBytes(count: valueLength)
            let (c, d) = CommitmentWithSHA256.commit(onTag: tag, andValue: value, with: prngService)
            let recoveredValue = CommitmentWithSHA256.open(commitment: c, onTag: tag, usingDecommitToken: d)!
            XCTAssertEqual(value, recoveredValue)
        }
    }
    

    func testAuthentication() {
        do {
            let bundle = Bundle(for: type(of: self))
            let url = bundle.url(forResource: "TestVectorsServerAuthentication", withExtension: "json")!
            let jsonData = try! Data(contentsOf: url)
            let decoder = JSONDecoder()
            let testVectors = try! decoder.decode([TestVectorForServerAuthentication].self, from: jsonData)
            let prefix = "authentChallenge".data(using: .utf8)!
            let wrongPrefix = "autxentCxallxnge".data(using: .utf8)!
            for testVector in testVectors {
                let publicKey: PublicKeyForAuthentication = PublicKeyForAuthenticationFromSignatureOnEdwardsCurve(testVector.encodedPublicKey)!
                let privateKey: PrivateKeyForAuthentication = PrivateKeyForAuthenticationFromSignatureOnEdwardsCurve(testVector.encodedPrivateKey)!
                guard let seed = Seed(with: testVector.seed) else { XCTFail(); return }
                let prng = PRNGWithHMACWithSHA256(with: seed)
                let response = try Authentication.solve(testVector.challenge!, prefixedWith: prefix, with: privateKey, and: publicKey, using: prng)
                XCTAssertNotNil(response)
                XCTAssertEqual(response!, testVector.response!)
                // Test the verification routine
                XCTAssert(true == (try Authentication.check(response: response!, toChallenge: testVector.challenge!, prefixedWith: prefix, using: publicKey)))
                XCTAssert(false == (try Authentication.check(response: response!, toChallenge: testVector.challenge!, prefixedWith: wrongPrefix, using: publicKey)))
            }
        } catch {
            XCTFail(error.localizedDescription)
        }
    }

    
    func testServerAuthenticationKeyGeneration() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsServerAuthenticationKeyGeneration", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForServerAuthentication].self, from: jsonData)
        for testVector in testVectors {
            guard let seed = Seed(with: testVector.seed) else { XCTFail(); return }
            let prng = PRNGWithHMACWithSHA256(with: seed)
            let algorithmImplementation = AuthenticationImplementationByteId(rawValue: testVector.algorithmImplementationByteIdValue)!
            let (_pk, _sk) = Authentication.generateKeyPair(for: algorithmImplementation, with: prng)
            guard let pk = _pk as? PublicKeyForAuthenticationFromSignatureOnEdwardsCurve else { XCTFail(); return }
            guard let sk = _sk as? PrivateKeyForAuthenticationFromSignatureOnEdwardsCurve else { XCTFail(); return }
            let pkFromTestVector = PublicKeyForAuthenticationFromSignatureOnEdwardsCurve(testVector.encodedPublicKey)!
            let skFromTestVector = PrivateKeyForAuthenticationFromSignatureOnEdwardsCurve(testVector.encodedPrivateKey)!
            XCTAssertEqual(pk, pkFromTestVector)
            XCTAssertEqual(sk, skFromTestVector)
        }
    }

    
    func testCompactPublicKey() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsForCompactPublicKey", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorForCompactPublicKey].self, from: jsonData)
        for testVector in testVectors {
            let cryptoAlgorithmClassByteId = CryptographicAlgorithmClassByteId(rawValue: testVector.cryptographicAlgorithmClassByteIdValue)!
            let publicKey: CompactableCryptographicKey
            switch cryptoAlgorithmClassByteId {
            case .authentication:
                publicKey = PublicKeyForAuthenticationDecoder.obvDecode(testVector.encodedPublicKey)!
            default:
                XCTFail()
                return
            }
            let compactPublicKey = publicKey.getCompactKey()
            XCTAssertEqual(compactPublicKey, testVector.compactPublicKey)
        }
    }
    
    
    func testExpandCompactPublicKeyForPubEncPubEncWithMDC() {
        let prngService = PRNGServiceWithHMACWithSHA256()
        for _ in 0..<100 {
            let (publicKey, _) = ECIESwithMDCandDEMwithCTRAES256thenHMACSHA256.generateKeyPair(with: prngService)
            let compactPublicKey = publicKey.getCompactKey()
            let recoveredPublicKey = CompactPublicKeyForPublicKeyEncryptionExpander.expand(compactKey: compactPublicKey)
            XCTAssertNotNil(recoveredPublicKey)
            let recoveredPublicKeyCasted = recoveredPublicKey as? PublicKeyForPublicKeyEncryptionOnEdwardsCurve
            XCTAssertNotNil(recoveredPublicKeyCasted)
            let publicKeyCasted = publicKey as! PublicKeyForPublicKeyEncryptionOnEdwardsCurve
            XCTAssertEqual(recoveredPublicKeyCasted!.algorithmClass, publicKey.algorithmClass)
            XCTAssertEqual(recoveredPublicKeyCasted!.algorithmImplementationByteIdValue, publicKey.algorithmImplementationByteIdValue)
            XCTAssertEqual(recoveredPublicKeyCasted!.curveByteId, publicKeyCasted.curveByteId)
            XCTAssertEqual(recoveredPublicKeyCasted!.yCoordinate, publicKeyCasted.yCoordinate)
            XCTAssertNil(recoveredPublicKeyCasted!.point)
        }
    }

    
    func testExpandCompactPublicKeyForAnonAuthPubEncWithCurve25519() {
        let prngService = PRNGServiceWithHMACWithSHA256()
        for _ in 0..<100 {
            let (publicKey, _) = ECIESwithCurve25519andDEMwithCTRAES256thenHMACSHA256.generateKeyPair(with: prngService)
            let compactPublicKey = publicKey.getCompactKey()
            let recoveredPublicKey = CompactPublicKeyForPublicKeyEncryptionExpander.expand(compactKey: compactPublicKey)
            XCTAssertNotNil(recoveredPublicKey)
            let recoveredPublicKeyCasted = recoveredPublicKey as? PublicKeyForPublicKeyEncryptionOnEdwardsCurve
            XCTAssertNotNil(recoveredPublicKeyCasted)
            let publicKeyCasted = publicKey as! PublicKeyForPublicKeyEncryptionOnEdwardsCurve
            XCTAssertEqual(recoveredPublicKeyCasted!.algorithmClass, publicKey.algorithmClass)
            XCTAssertEqual(recoveredPublicKeyCasted!.algorithmImplementationByteIdValue, publicKey.algorithmImplementationByteIdValue)
            XCTAssertEqual(recoveredPublicKeyCasted!.curveByteId, publicKeyCasted.curveByteId)
            XCTAssertEqual(recoveredPublicKeyCasted!.yCoordinate, publicKeyCasted.yCoordinate)
            XCTAssertNil(recoveredPublicKeyCasted!.point)
        }
    }

    
    func testExpandCompactPublicKeyForServerAuthenticationWithMDC() {
        let prngService = PRNGServiceWithHMACWithSHA256()
        for _ in 0..<100 {
            let (publicKey, _) = AuthenticationFromSignatureOnMDC.generateKeyPair(with: prngService)
            let compactPublicKey = publicKey.getCompactKey()
            let recoveredPublicKey = CompactPublicKeyForAuthenticationExpander.expand(compactKey: compactPublicKey)
            XCTAssertNotNil(recoveredPublicKey)
            let recoveredPublicKeyCasted = recoveredPublicKey as? PublicKeyForAuthenticationFromSignatureOnEdwardsCurve
            XCTAssertNotNil(recoveredPublicKeyCasted)
            let publicKeyCasted = publicKey as! PublicKeyForAuthenticationFromSignatureOnEdwardsCurve
            XCTAssertEqual(recoveredPublicKeyCasted!.algorithmClass, publicKey.algorithmClass)
            XCTAssertEqual(recoveredPublicKeyCasted!.algorithmImplementationByteIdValue, publicKey.algorithmImplementationByteIdValue)
            XCTAssertEqual(recoveredPublicKeyCasted!.curveByteId, publicKeyCasted.curveByteId)
            XCTAssertEqual(recoveredPublicKeyCasted!.yCoordinate, publicKeyCasted.yCoordinate)
            XCTAssertNil(recoveredPublicKeyCasted!.point)
        }
    }

    
    func testExpandCompactPublicKeyForServerAuthenticationWithCurve25519() {
        let prngService = PRNGServiceWithHMACWithSHA256()
        for _ in 0..<100 {
            let (publicKey, _) = AuthenticationFromSignatureOnCurve25519.generateKeyPair(with: prngService)
            let compactPublicKey = publicKey.getCompactKey()
            let recoveredPublicKey = CompactPublicKeyForAuthenticationExpander.expand(compactKey: compactPublicKey)
            XCTAssertNotNil(recoveredPublicKey)
            let recoveredPublicKeyCasted = recoveredPublicKey as? PublicKeyForAuthenticationFromSignatureOnEdwardsCurve
            XCTAssertNotNil(recoveredPublicKeyCasted)
            let publicKeyCasted = publicKey as! PublicKeyForAuthenticationFromSignatureOnEdwardsCurve
            XCTAssertEqual(recoveredPublicKeyCasted!.algorithmClass, publicKey.algorithmClass)
            XCTAssertEqual(recoveredPublicKeyCasted!.algorithmImplementationByteIdValue, publicKey.algorithmImplementationByteIdValue)
            XCTAssertEqual(recoveredPublicKeyCasted!.curveByteId, publicKeyCasted.curveByteId)
            XCTAssertEqual(recoveredPublicKeyCasted!.yCoordinate, publicKeyCasted.yCoordinate)
            XCTAssertNil(recoveredPublicKeyCasted!.point)
        }
    }

    
    func testEncodeThenDecodeAuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key() {
        let prngService = PRNGServiceWithHMACWithSHA256()
        for _ in 0..<100 {
            let key = AuthenticatedEncryption.generateKey(for: .CTR_AES_256_THEN_HMAC_SHA_256, with: prngService) as! AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key
            let encodedKey = key.obvEncode()
            let decodedKey = try? AuthenticatedEncryptionKeyDecoder.decode(encodedKey)
            XCTAssertNotNil(decodedKey)
            XCTAssert(key.isEqualTo(other: decodedKey!))
        }
    }


    func testEncodeThenDecodeSymmetricEncryptionKey() {
        let prngService = PRNGServiceWithHMACWithSHA256()
        for _ in 0..<100 {
            let key = SymmetricEncryption.generateKey(for: .SymmetricEncryption_With_AES_256_CTR, with: prngService) as! SymmetricEncryptionAES256CTRKey
            let encodedKey = key.obvEncode()
            let decodedKey = SymmetricEncryptionKeyDecoder.decode(encodedKey)
            XCTAssertNotNil(decodedKey)
            XCTAssert(key.isEqualTo(other: decodedKey!))
        }
    }
    

    func testEncodeThenDecodeMACKey() {
        let prngService = PRNGServiceWithHMACWithSHA256()
        for _ in 0..<100 {
            let key = MAC.generateKey(for: .HMAC_With_SHA256, with: prngService) as! HMACWithSHA256Key
            let encodedKey = key.obvEncode()
            let decodedKey = MACKeyDecoder.decode(encodedKey)
            XCTAssertNotNil(decodedKey)
            XCTAssert(key.isEqualTo(other: decodedKey!))
        }
    }


    func testEncodeThenDecodeBlockCipherKey() {
        let prngService = PRNGServiceWithHMACWithSHA256()
        for _ in 0..<100 {
            let key = BlockCipher.generateKey(for: .AES_256, with: prngService) as! AES256Key
            let encodedKey = key.obvEncode()
            let decodedKey = BlockCipherKeyDecoder.decode(encodedKey)
            XCTAssertNotNil(decodedKey)
            XCTAssert(key.isEqualTo(other: decodedKey!))
        }
    }

    
    func testCompareCryptoIdentityToTheSameCryptoIdentityButAfterItWasExportedThenImportedToDataIdentity() {
        let prngService = PRNGServiceWithHMACWithSHA256()
        let ownedCryptoIdentity = ObvOwnedCryptoIdentity.gen(withServerURL: URL(string: "https://olvid.io")!, using: prngService)
        let cryptoIdentity = ownedCryptoIdentity.getObvCryptoIdentity()
        let identity = cryptoIdentity.getIdentity()
        guard let cryptoIdentity2 = ObvCryptoIdentity.init(from: identity) else { XCTFail(); return }
        XCTAssertEqual(cryptoIdentity, cryptoIdentity2)
    }
    
        
    func testRandomBackupSeedToStringAndBack() {
        let prngService = PRNGServiceWithHMACWithSHA256()
        for _ in 0..<10 {//_000 {
            let backupSeed = prngService.genBackupSeed()
            guard let newSeed = BackupSeed(backupSeed.description) else { XCTFail(); return }
            
            debugPrint(backupSeed.description, backupSeed.raw.hexString())
            
            XCTAssertEqual(backupSeed, newSeed)
        }
    }
    
    func testEquivalentBackupStrings() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsEquivalentBackupSeedString", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorBackupSeedStrings].self, from: jsonData)
        for testVector in testVectors {
            guard let backupSeed1 = BackupSeed(testVector.backupSeedString1) else { XCTFail(); return }
            guard let backupSeed2 = BackupSeed(testVector.backupSeedString2) else { XCTFail(); return }
            XCTAssertEqual(backupSeed1, backupSeed2)
        }
    }
    
    
    func testBackupSeedFromString() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsBackupSeedFromString", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorBackupSeedFromString].self, from: jsonData)
        for testVector in testVectors {
            let backupSeedRaw = testVector.backupSeedRaw
            let backupSeedString = testVector.backupSeedString
            guard let backupSeed1 = BackupSeed(backupSeedString) else { XCTFail(); return }
            guard let backupSeed2 = BackupSeed(with: backupSeedRaw) else { XCTFail(); return }
            XCTAssertEqual(backupSeed1, backupSeed2)
        }
    }
    
    
    func testBackupSeedStringToDerivedKeysForBackup() {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "TestVectorsBackupKeysFromBackupSeedString", withExtension: "json")!
        let jsonData = try! Data(contentsOf: url)
        let decoder = JSONDecoder()
        let testVectors = try! decoder.decode([TestVectorsBackupKeysFromBackupSeedString].self, from: jsonData)
        for testVector in testVectors {
            guard let backupSeed = BackupSeed(testVector.backupSeedString) else { XCTFail(); return }
            let derivedKeys = backupSeed.deriveKeysForBackup()
            XCTAssertEqual(derivedKeys.macKey.data, testVector.macKey.data)
            XCTAssertEqual(derivedKeys.publicKeyForEncryption.getCompactKey(), testVector.publicKeyForEncryption.getCompactKey())
            XCTAssertEqual(derivedKeys.backupKeyUid, testVector.uid)
        }
    }
    
    
    /// Given a private and a public authentication keys, the API allows allows to test if they corresponds. We test this feature.
    func testMathingOfAuthenticationKey() {
        let prngService = ObvCryptoSuite.sharedInstance.prngService()
        for _ in 0..<100 {
            let (pk, sk) = Authentication.generateKeyPair(for: .Signature_with_EC_SDSA_with_Curve25519, with: prngService)
            XCTAssert(Authentication.areKeysMatching(publicKey: pk, privateKey: sk))
        }
        for _ in 0..<100 {
            let (pk, sk) = Authentication.generateKeyPair(for: .Signature_with_EC_SDSA_with_MDC, with: prngService)
            XCTAssert(Authentication.areKeysMatching(publicKey: pk, privateKey: sk))
        }
        for _ in 0..<100 {
            let (pk, _) = Authentication.generateKeyPair(for: .Signature_with_EC_SDSA_with_Curve25519, with: prngService)
            let (_, sk) = Authentication.generateKeyPair(for: .Signature_with_EC_SDSA_with_Curve25519, with: prngService)
            XCTAssert(!Authentication.areKeysMatching(publicKey: pk, privateKey: sk))
        }
        for _ in 0..<100 {
            let (pk, _) = Authentication.generateKeyPair(for: .Signature_with_EC_SDSA_with_MDC, with: prngService)
            let (_, sk) = Authentication.generateKeyPair(for: .Signature_with_EC_SDSA_with_MDC, with: prngService)
            XCTAssert(!Authentication.areKeysMatching(publicKey: pk, privateKey: sk))
        }
        for _ in 0..<100 {
            let (pk, _) = Authentication.generateKeyPair(for: .Signature_with_EC_SDSA_with_Curve25519, with: prngService)
            let (_, sk) = Authentication.generateKeyPair(for: .Signature_with_EC_SDSA_with_MDC, with: prngService)
            XCTAssert(!Authentication.areKeysMatching(publicKey: pk, privateKey: sk))
        }
        for _ in 0..<100 {
            let (pk, _) = Authentication.generateKeyPair(for: .Signature_with_EC_SDSA_with_MDC, with: prngService)
            let (_, sk) = Authentication.generateKeyPair(for: .Signature_with_EC_SDSA_with_Curve25519, with: prngService)
            XCTAssert(!Authentication.areKeysMatching(publicKey: pk, privateKey: sk))
        }

    }
}
