/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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


public struct BackupSeed: LosslessStringConvertible, CustomStringConvertible, Equatable, Sendable {

    /// the seed is 20-bytes, that is 8x4 characters (MAJ & number without I, O, S, Z)
    public static let byteLength = 20
    
    public let raw: Data
    
    // The 32 characters we accept (5 bits of entropy per character)
    private static let seedArray: [Character] = ["0", "1", "2", "3", "4", "5", "6", "7",
                                                 "8", "9", "A", "B", "C", "D", "E", "F",
                                                 "G", "H", "J", "K", "L", "M", "N", "P",
                                                 "Q", "R", "T", "U", "V", "W", "X", "Y"]

    private static let invArray: [Character: UInt8] = {
        var res = [Character: UInt8]()
        for (index, character) in BackupSeed.seedArray.enumerated() {
            insert(index: index, forCharacter: character, into: &res)
            // Certain characters are equivalent
            switch character {
            case "0":
                insert(index: index, forCharacter: "O", into: &res)
                insert(index: index, forCharacter: "o", into: &res)
            case "1":
                insert(index: index, forCharacter: "I", into: &res)
                insert(index: index, forCharacter: "i", into: &res)
            case "2":
                insert(index: index, forCharacter: "Z", into: &res)
                insert(index: index, forCharacter: "z", into: &res)
            case "5":
                insert(index: index, forCharacter: "S", into: &res)
                insert(index: index, forCharacter: "s", into: &res)
            default:
                break
            }
            // All uppercased letters are equivalent to their lowecased counterpart
            switch character {
            case let upercaseLetter where upercaseLetter.isLetter && upercaseLetter.isUppercase:
                let lowercaseLetter = Character(upercaseLetter.lowercased())
                insert(index: index, forCharacter: lowercaseLetter, into: &res)
            default:
                break
            }
        }
        return res
    }()
    
    public static let acceptableCharacters: CharacterSet = {
        var charactersString = ""
        for character in invArray.keys {
            charactersString.append(character)
        }
        let acceptableCharacters = CharacterSet(charactersIn: charactersString)
        return acceptableCharacters
    }()
    
    private static func insert(index: Int, forCharacter character: Character, into invArray: inout [Character: UInt8]) {
        assert(!invArray.keys.contains(character))
        assert(index < 256 && index >= 0)
        invArray[character] = UInt8(index)
    }
    
    public init?(with raw: Data) {
        guard raw.count == BackupSeed.byteLength else { assertionFailure(); return nil }
        self.raw = raw
    }

    public init?(_ description: String) {
        
        var bitIndex = 0
        var raw = Data(repeating: 0, count: BackupSeed.byteLength)
        
        for character in description {
            
            guard let byte = BackupSeed.invArray[character] else { continue }
            guard bitIndex <= (BackupSeed.byteLength<<3) - 5 else {
                return nil
            }
            
            let byteOffset = bitIndex & 0x7
            let byteIndex = bitIndex>>3

            if byteOffset < 4 {
                raw[byteIndex] |= (byte << (3-byteOffset))
            } else {
                raw[byteIndex] |= (byte >> (byteOffset-3))
                raw[byteIndex+1] |= (byte << (11-byteOffset))
            }
            
            bitIndex += 5
            
        }
        
        guard bitIndex == BackupSeed.byteLength<<3 else {
            return nil
        }
        
        self.raw = raw
        
    }
    
    
    public var description: String {
        
        var res = ""
        var bitIndex = 0
        
        for _ in 0..<32 {

            let byteOffset = bitIndex & 0x07
            let byteIndex = bitIndex>>3
            
            var charIndex: UInt8
            if byteOffset < 4 {
                charIndex = ((raw[byteIndex] >> (3-byteOffset))) & UInt8(0x1F)
            } else {
                charIndex = ((raw[byteIndex] << (byteOffset-3))) & UInt8(0x1F)
                charIndex |= (raw[byteIndex+1] & UInt8(0xFF)) >> (11-byteOffset)
            }
            
            res.append(BackupSeed.seedArray[Int(charIndex)])
            
            bitIndex += 5
        }
        
        return res
    }

    
    public func deriveKeysForLegacyBackup() -> DerivedKeysForLegacyBackup {

        // We padd the backup seed with 0x00's in order to generate a seed
        let seed = deriveFullSeed()

        let prng = PRNGWithHMACWithSHA256(with: seed)
        return DerivedKeysForLegacyBackup.gen(with: prng)

    }
    
    
    public func deriveKeysForNewBackup() -> DerivedKeysForNewBackup {
        
        // We padd the backup seed with 0x00's in order to generate a seed
        let seed = deriveFullSeed()

        let prng = PRNGWithHMACWithSHA256(with: seed)
        return DerivedKeysForNewBackup.gen(with: prng)

    }
    
    
    private func deriveFullSeed() -> Seed {
        // We padd the backup seed with 0x00's in order to generate a seed
        let rawSeed = self.raw + Data(repeating: 0, count: max(0, Seed.minLength - self.raw.count))
        let seed = Seed(with: rawSeed)!
        return seed
    }
    
    
    public static func == (lhs: BackupSeed, rhs: BackupSeed) -> Bool {
        return Array(lhs.raw) == Array(rhs.raw)
    }
}


// MARK: - DerivedKeysForNewBackup

public struct DerivedKeysForNewBackup {
    
    public let backupKeyUID: UID
    public let encryptionKey: any AuthenticatedEncryptionKey
    public let authenticationKeyPair: (publicKey: any PublicKeyForAuthentication, privateKey: any PrivateKeyForAuthentication)

    static func gen(with prng: PRNG) -> Self {
        let backupKeyUID = UID.gen(with: prng)
        let encryptionKey = AuthenticatedEncryption.generateKey(for: .CTR_AES_256_THEN_HMAC_SHA_256, with: prng)
        let authenticationKeyPair = Authentication.generateKeyPair(for: .Signature_with_EC_SDSA_with_Curve25519, with: prng)
        return self.init(backupKeyUID: backupKeyUID,
                         encryptionKey: encryptionKey,
                         authenticationKeyPair: authenticationKeyPair)
    }
    
}


// MARK: - DerivedKeysForLegacyBackup

public struct DerivedKeysForLegacyBackup: Equatable {
    
    // Warning: Adding a local var requires updating the method required in order to implement Equatable
    public let backupKeyUid: UID // Not used for testing equality (due to a bug in the Android version  of the app)
    public let publicKeyForEncryption: PublicKeyForPublicKeyEncryption
    public let privateKeyForEncryption: PrivateKeyForPublicKeyEncryption?
    public let macKey: MACKey
    
    static func gen(with prng: PRNG) -> Self {
        let backupKeyUid = UID.gen(with: prng)
        let (publicKeyForEncryption, privateKeyForEncryption) = ECIESwithCurve25519andDEMwithCTRAES256thenHMACSHA256.generateKeyPairForBackupKey(with: prng)
        let macKey = HMACWithSHA256.generateKeyForBackup(with: prng)
        return DerivedKeysForLegacyBackup(backupKeyUid: backupKeyUid, publicKeyForEncryption: publicKeyForEncryption, privateKeyForEncryption: privateKeyForEncryption, macKey: macKey)
    }

    private init(backupKeyUid: UID, publicKeyForEncryption: PublicKeyForPublicKeyEncryption, privateKeyForEncryption: PrivateKeyForPublicKeyEncryption, macKey: MACKey) {
        self.backupKeyUid = backupKeyUid
        self.publicKeyForEncryption = publicKeyForEncryption
        self.privateKeyForEncryption = privateKeyForEncryption
        self.macKey = macKey
    }

    public init(backupKeyUid: UID, publicKeyForEncryption: PublicKeyForPublicKeyEncryption, macKey: MACKey) {
        self.backupKeyUid = backupKeyUid
        self.publicKeyForEncryption = publicKeyForEncryption
        self.privateKeyForEncryption = nil
        self.macKey = macKey
    }
    
    public static func == (lhs: DerivedKeysForLegacyBackup, rhs: DerivedKeysForLegacyBackup) -> Bool {
        // We do *not* test the equality of the backupKeyUid (due to a bug in the Android version  of the app)
        guard lhs.publicKeyForEncryption.getCompactKey() == rhs.publicKeyForEncryption.getCompactKey() else { return false }
        guard lhs.macKey.data == rhs.macKey.data else { return false }
        return true
    }

}


// MARK: - Implementing Hashable

extension BackupSeed: Hashable {}

// MARK: Implementing Codable (used by sync snapshots)

extension BackupSeed: Codable {
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.raw)
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(Data.self)
        guard let backupSeed = BackupSeed(with: raw) else {
            throw CodableError.decodingFailed
        }
        self = backupSeed
    }
    
    enum CodableError: Error {
        case decodingFailed
    }

}


// MARK: Implementing ObvCodable

extension BackupSeed: ObvCodable {
    
    public func obvEncode() -> ObvEncoded {
        self.raw.obvEncode()
    }
    
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let raw = Data(obvEncoded) else { assertionFailure(); return nil }
        guard let backupSeed = BackupSeed(with: raw) else { assertionFailure(); return nil }
        self = backupSeed
    }
    
}
