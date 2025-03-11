//
//  Olvid for iOS
//  Copyright © 2019-2021 Olvid SAS
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

import Foundation
import ObvBigInt
import ObvEncoder
@testable import ObvCrypto

//extension URL {
//    init(from decoder: Decoder) throws {
//        let container = try decoder.singleValueContainer()
//        let urlAsString = try container.decode(String.self)
//        let url = URL.ini
//    }
//}

// MARK: Types for Hash functions

struct TestVectorForHash {
    let inputMessagePart: String
    let numberOfRepetition: Int
    let digest: Data
}

extension TestVectorForHash : Decodable {
    
    enum MyStructKeys: String, CodingKey {
        case inputMessagePart = "inputMessagePart"
        case numberOfRepetition = "numberOfRepetition"
        case digest = "digest"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: MyStructKeys.self)
        let inputMessagePart = try container.decode(String.self, forKey: .inputMessagePart)
        let numberOfRepetition = try container.decode(Int.self, forKey: .numberOfRepetition)
        let digest = (try container.decode(String.self, forKey: .digest)).dataFromHexString()!
        self.init(inputMessagePart: inputMessagePart, numberOfRepetition: numberOfRepetition, digest: digest)
    }
    
}

// MARK: Types for Block Ciphers

struct TestVectorsAES256 {
    let key: AES256Key
    let plaintext: Data
    let ciphertext: EncryptedData
}

extension TestVectorsAES256 : Decodable {
    
    enum MyStructKeys: String, CodingKey {
        case key = "key"
        case plaintext = "plaintext"
        case ciphertext = "ciphertext"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: MyStructKeys.self)
        let key = AES256Key(data: (try container.decode(String.self, forKey: .key)).dataFromHexString()!)!
        let plaintext = (try container.decode(String.self, forKey: .plaintext)).dataFromHexString()!
        let ciphertext = EncryptedData(data: (try container.decode(String.self, forKey: .ciphertext)).dataFromHexString()!)
        self.init(key: key, plaintext: plaintext, ciphertext: ciphertext)
    }
    
}

// MARK: Types for Symmetric Encryption

struct TestVectorForSymmetricEncryptionWithAES256CTR {
    let key: SymmetricEncryptionAES256CTRKey
    let plaintext: Data
    let ciphertext: EncryptedData
    let iv: Data
}

extension TestVectorForSymmetricEncryptionWithAES256CTR : Decodable {
    
    enum MyStructKeys: String, CodingKey {
        case key = "key"
        case plaintext = "plaintext"
        case ciphertext = "ciphertext"
        case iv = "iv"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: MyStructKeys.self)
        let key = SymmetricEncryptionAES256CTRKey(data: (try container.decode(String.self, forKey: .key)).dataFromHexString()!)!
        let plaintext = (try container.decode(String.self, forKey: .plaintext)).dataFromHexString()!
        let ciphertext = EncryptedData(data: (try container.decode(String.self, forKey: .ciphertext)).dataFromHexString()!)
        let iv = (try container.decode(String.self, forKey: .iv)).dataFromHexString()!
        self.init(key: key, plaintext: plaintext, ciphertext: ciphertext, iv: iv)
    }
}

// MARK: Types for MAC

struct TestVectorForHMACWithSHA256 {
    let key: HMACWithSHA256Key
    let data: Data
    let mac: Data
}

extension TestVectorForHMACWithSHA256 : Decodable {
    
    enum MyStructKeys: String, CodingKey {
        case key = "key"
        case data = "data"
        case mac = "mac"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: MyStructKeys.self)
        let key = HMACWithSHA256Key(data: (try container.decode(String.self, forKey: .key)).dataFromHexString()!)!
        let data = (try container.decode(String.self, forKey: .data)).dataFromHexString()!
        let mac = (try container.decode(String.self, forKey: .mac)).dataFromHexString()!
        self.init(key: key, data: data, mac: mac)
    }
}

// MARK: Types for PRNG

struct TestVectorForPRNG {
    let entropyInput: Data
    let nonce: Data
    let personalizationString: Data
    let generatedBytes: [Data]
}

extension TestVectorForPRNG : Decodable {
    
    enum MyStructKeys: String, CodingKey {
        case entropyInput = "entropyInput"
        case nonce = "nonce"
        case personalizationString = "personalizationString"
        case generatedBytes = "generatedBytes"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: MyStructKeys.self)
        let entropyInput = (try container.decode(String.self, forKey: .entropyInput)).dataFromHexString()!
        let nonce = (try container.decode(String.self, forKey: .nonce)).dataFromHexString()!
        let personalizationString = (try container.decode(String.self, forKey: .personalizationString)).dataFromHexString()!
        let generatedBytesAsHexStrings = (try container.decode([String].self, forKey: .generatedBytes))
        let generatedBytes = generatedBytesAsHexStrings.map { $0.dataFromHexString()! }
        self.init(entropyInput: entropyInput, nonce: nonce, personalizationString: personalizationString, generatedBytes: generatedBytes)
    }
}

// MARK: Types for big int generation with the PRNG

struct TestVectorForBigIntPRNG {
    let seed: Data
    let bounds: [BigInt]
    let values: [BigInt]
}

extension TestVectorForBigIntPRNG : Decodable {
    
    private enum MyStructKeys: String, CodingKey {
        case seed = "seed"
        case bounds = "bounds"
        case values = "values"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: MyStructKeys.self)
        let seed = (try container.decode(String.self, forKey: .seed)).dataFromHexString()!
        let bounds = try container.decode([BigInt].self, forKey: .bounds)
        let values = try container.decode([BigInt].self, forKey: .values)
        self.init(seed: seed, bounds: bounds, values: values)
    }
}

// MARK: Types for Authenticated Encryption

struct TestVectorForAuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256 {
    let key: AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key
    let plaintext: Data
    let ciphertext: EncryptedData
    let seed: Data
}

extension TestVectorForAuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256 : Decodable {
    
    enum MyStructKeys: String, CodingKey {
        case key = "key"
        case plaintext = "plaintext"
        case ciphertext = "ciphertext"
        case seed = "seed"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: MyStructKeys.self)
        let key = AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key(data: (try container.decode(String.self, forKey: .key)).dataFromHexString()!)!
        let plaintext = (try container.decode(String.self, forKey: .plaintext)).dataFromHexString()!
        let ciphertext = EncryptedData(data: (try container.decode(String.self, forKey: .ciphertext)).dataFromHexString()!)
        let seed = (try container.decode(String.self, forKey: .seed)).dataFromHexString()!
        self.init(key: key, plaintext: plaintext, ciphertext: ciphertext, seed: seed)
    }
}


// MARK: Types for Edwards Curve

struct TestVectorForEdwardsCurve: Decodable {
    let x: BigInt?
    let x2: BigInt?
    let x3: BigInt?
    let x4: BigInt?
    let x5: BigInt?
    let y: BigInt?
    let y1: BigInt?
    let y2: BigInt?
    let y3: BigInt?
    let y4: BigInt?
    let y5: BigInt?
    let a: BigInt?
    let b: BigInt?
    let n: BigInt?
    let ny: BigInt?
}

//extension TestVectorForEdwardsCurve : Decodable {
//
////    enum MyStructKeys: String, CodingKey {
////        case key = "key"
////        case plaintext = "plaintext"
////        case ciphertext = "ciphertext"
////        case seed = "seed"
////    }
//
////    init(from decoder: Decoder) throws {
////        let container = try decoder.c
////        let key = SymmetricKey(data: (try container.decode(String.self, forKey: .key)).dataFromHexString()!)
////        let plaintext = (try container.decode(String.self, forKey: .plaintext)).dataFromHexString()!
////        let ciphertext = EncryptedData(data: (try container.decode(String.self, forKey: .ciphertext)).dataFromHexString()!)
////        let seed = (try container.decode(String.self, forKey: .seed)).dataFromHexString()!
////        self.init(key: key, plaintext: plaintext, ciphertext: ciphertext, seed: seed)
////    }
//}


// MARK: Types for public key encryption

struct TestVectorForPublicKeyEncryptionOverEdwardsCurve: Decodable {
    let seed: Data?
    let plaintext: Data?
    let ciphertext: EncryptedData?
    let encodedPublicKey: ObvEncoded?
    let encodedPrivateKey: ObvEncoded?
    let encodedRecipientPublicKey: ObvEncoded?
    let encodedRecipientPrivateKey: ObvEncoded?
    let algorithmImplementationByteIdValue: UInt8
    let xCoordinate: BigInt?
    let yCoordinate: BigInt?
    let scalar: BigInt?
    let signature: Data?
}

extension TestVectorForPublicKeyEncryptionOverEdwardsCurve {
    
    private enum CodingKeys: String, CodingKey {
        case seed
        case plaintext
        case ciphertext
        case encodedPublicKey
        case encodedPrivateKey
        case encodedRecipientPublicKey
        case encodedRecipientPrivateKey
        case algorithmImplementationByteIdValue
        case xCoordinate
        case yCoordinate
        case scalar
        case signature
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.seed = (try? container.decode(String.self, forKey: .seed))?.dataFromHexString()
        self.plaintext = (try? container.decode(String.self, forKey: .plaintext))?.dataFromHexString()
        self.ciphertext = try? container.decode(EncryptedData.self, forKey: .ciphertext)
        self.encodedPublicKey = try? container.decode(ObvEncoded.self, forKey: .encodedPublicKey)
        self.encodedPrivateKey = try? container.decode(ObvEncoded.self, forKey: .encodedPrivateKey)
        self.encodedRecipientPublicKey = try? container.decode(ObvEncoded.self, forKey: .encodedRecipientPublicKey)
        self.encodedRecipientPrivateKey = try? container.decode(ObvEncoded.self, forKey: .encodedRecipientPrivateKey)
        self.algorithmImplementationByteIdValue = try! container.decode(UInt8.self, forKey: .algorithmImplementationByteIdValue)
        self.xCoordinate = try? container.decode(BigInt.self, forKey: .xCoordinate)
        self.yCoordinate = try? container.decode(BigInt.self, forKey: .yCoordinate)
        self.scalar = try? container.decode(BigInt.self, forKey: .scalar)
        self.signature = (try? container.decode(String.self, forKey: .signature))?.dataFromHexString()
    }
    
}


// MARK: Types for commitments

struct TestVectorForCommitment: Decodable {
    let seed: Data
    let value: Data
    let tag: Data
    let commitment: Data
    let decommitmentToken: Data
}

extension TestVectorForCommitment {
    
    private enum CodingKeys: String, CodingKey {
        case seed
        case value
        case tag
        case commitment
        case decommitmentToken
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.seed = (try container.decode(String.self, forKey: .seed)).dataFromHexString()!
        self.value = (try container.decode(String.self, forKey: .value)).dataFromHexString()!
        self.tag = (try container.decode(String.self, forKey: .tag)).dataFromHexString()!
        self.commitment = (try container.decode(String.self, forKey: .commitment)).dataFromHexString()!
        self.decommitmentToken = (try container.decode(String.self, forKey: .decommitmentToken)).dataFromHexString()!
    }
    
}

// MARK: Types for Proof of Work

struct TestVectorForProofOfWork: Decodable {
    let challenge: ObvEncoded
    let response: ObvEncoded
}

// MARK: Types for server authentication

struct TestVectorForServerAuthentication: Decodable {
    let seed: Data
    let encodedPublicKey: ObvEncoded
    let encodedPrivateKey: ObvEncoded
    let challenge: Data?
    let response: Data?
    let algorithmImplementationByteIdValue: UInt8
}

extension TestVectorForServerAuthentication {
    
    private enum CodingKeys: String, CodingKey {
        case seed
        case encodedPublicKey
        case encodedPrivateKey
        case challenge
        case response
        case algorithmImplementationByteIdValue
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.seed = (try container.decode(String.self, forKey: .seed)).dataFromHexString()!
        self.encodedPublicKey =  try container.decode(ObvEncoded.self, forKey: .encodedPublicKey)
        self.encodedPrivateKey = try container.decode(ObvEncoded.self, forKey: .encodedPrivateKey)
        self.challenge = (try? container.decode(String.self, forKey: .challenge))?.dataFromHexString()
        self.response = (try? container.decode(String.self, forKey: .response))?.dataFromHexString()
        self.algorithmImplementationByteIdValue = try! container.decode(UInt8.self, forKey: .algorithmImplementationByteIdValue)
    }
    
}

// MARK: Types for compact public keys

struct TestVectorForCompactPublicKey: Decodable {
    let encodedPublicKey: ObvEncoded
    let compactPublicKey: Data
    let algorithmImplementationByteIdValue: UInt8
    let cryptographicAlgorithmClassByteIdValue: UInt8
}

extension TestVectorForCompactPublicKey {
    
    private enum CodingKeys: String, CodingKey {
        case encodedPublicKey
        case compactPublicKey
        case algorithmImplementationByteIdValue
        case cryptographicAlgorithmClassByteIdValue
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.encodedPublicKey =  try container.decode(ObvEncoded.self, forKey: .encodedPublicKey)
        self.compactPublicKey = (try container.decode(String.self, forKey: .compactPublicKey)).dataFromHexString()!
        self.algorithmImplementationByteIdValue = (try container.decode(String.self, forKey: .algorithmImplementationByteIdValue)).dataFromHexString()!.first!
        self.cryptographicAlgorithmClassByteIdValue = (try container.decode(String.self, forKey: .cryptographicAlgorithmClassByteIdValue)).dataFromHexString()!.first!
    }
    
}

// MARK: Types for crypto identities

struct TestVectorForCryptoIdentity: Decodable {
    let algorithmImplementationByteIdValue: UInt8
    let encodedServerAuthPublicKey: ObvEncoded
    let encodedServerAuthPrivateKey: ObvEncoded
    let encodedAnonAuthPublicKey: ObvEncoded
    let encodedAnonAuthPrivateKey: ObvEncoded
    let server: URL
    let identity: Data
}

extension TestVectorForCryptoIdentity {
    
    private enum CodingKeys: String, CodingKey {
        case algorithmImplementationByteIdValue
        case encodedServerAuthPublicKey
        case encodedServerAuthPrivateKey
        case encodedAnonAuthPublicKey
        case encodedAnonAuthPrivateKey
        case server
        case identity
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.algorithmImplementationByteIdValue = (try container.decode(String.self, forKey: .algorithmImplementationByteIdValue)).dataFromHexString()!.first!
        self.encodedServerAuthPublicKey = try container.decode(ObvEncoded.self, forKey: .encodedServerAuthPublicKey)
        self.encodedServerAuthPrivateKey = try container.decode(ObvEncoded.self, forKey: .encodedServerAuthPrivateKey)
        self.encodedAnonAuthPublicKey = try container.decode(ObvEncoded.self, forKey: .encodedAnonAuthPublicKey)
        self.encodedAnonAuthPrivateKey = try container.decode(ObvEncoded.self, forKey: .encodedAnonAuthPrivateKey)
        self.server = try container.decode(URL.self, forKey: .server)
        self.identity = (try? container.decode(String.self, forKey: .identity))!.dataFromHexString()!
    }
    
}


// MARK: Types for testing BackupSeed equivalent strings

struct TestVectorBackupSeedStrings: Decodable {
    
    let backupSeedString1: String
    let backupSeedString2: String

    private enum CodingKeys: String, CodingKey {
        case backupSeedString1 = "backupSeedString1"
        case backupSeedString2 = "backupSeedString2"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.backupSeedString1 = try container.decode(String.self, forKey: .backupSeedString1)
        self.backupSeedString2 = try container.decode(String.self, forKey: .backupSeedString2)
    }
}


struct TestVectorBackupSeedFromString: Decodable {
    
    let backupSeedString: String
    let backupSeedRaw: Data
    
    private enum CodingKeys: String, CodingKey {
        case backupSeedString = "backupSeedString"
        case backupSeedRaw = "backupSeed"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.backupSeedString = try container.decode(String.self, forKey: .backupSeedString)
        self.backupSeedRaw = try container.decode(String.self, forKey: .backupSeedRaw).dataFromHexString()!
    }

}


struct TestVectorsBackupKeysFromBackupSeedString: Decodable {
    
    let backupSeedString: String
    let uid: UID
    let publicKeyForEncryption: PublicKeyForPublicKeyEncryption
    let macKey: MACKey

    private enum CodingKeys: String, CodingKey {
        case backupSeedString = "backupSeedString"
        case uid = "uidRaw"
        case publicKeyForEncryption = "publicKeyForEncryption"
        case macKey = "macKey"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.backupSeedString = try container.decode(String.self, forKey: .backupSeedString)
        let uidRaw = try container.decode(String.self, forKey: .uid).dataFromHexString()!
        self.uid = UID(uid: uidRaw)!
        let compactKey = try! container.decode(String.self, forKey: .publicKeyForEncryption).dataFromHexString()!
        self.publicKeyForEncryption = CompactPublicKeyForPublicKeyEncryptionExpander.expand(compactKey: compactKey)!
        let macKeyRaw = try container.decode(String.self, forKey: .macKey).dataFromHexString()!
        self.macKey = HMACWithSHA256Key(data: macKeyRaw)!
    }

}
