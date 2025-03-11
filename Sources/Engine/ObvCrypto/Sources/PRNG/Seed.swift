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


public final class Seed: NSObject, NSCopying, ObvCodable {
    
    public static let minLength = 32 // Changing this requires thorough testing
    public let raw: Data
    
    var length: Int {
        return raw.count
    }
    
    public init?(with raw: Data) {
        guard raw.count >= Seed.minLength else { return nil }
        self.raw = raw
    }
    
    public init(seeds: [Seed]) {
        self.raw = seeds.reduce(Data(), { return $0 + $1.raw })
    }
    
    static func concat(_ seed1: Seed, with seed2: Seed) -> Seed {
        let raw = seed1.raw + seed2.raw
        return Seed(with: raw)!
    }
    
    public func diversify(with uid: UID, withCryptoSuite cryptoSuiteVersion: SuiteVersion) -> Seed? {
        guard let prngClass = ObvCryptoSuite.sharedInstance.concretePRNG(forSuiteVersion: cryptoSuiteVersion) else { return nil }
        let rawSeed = self.raw + uid.raw
        let seed = Seed(with: rawSeed)!
        let prng = prngClass.init(with: seed)
        return prng.genSeed()
    }
    
    public convenience init?(withKeys keys: [AuthenticatedEncryptionKey]) {
        guard keys.count > 0 else { return nil }
        let zeroSeedRaw = Data(repeating: 0, count: Seed.minLength)
        let zeroSeed = Seed(with: zeroSeedRaw)!
        let prng = PRNGWithHMACWithSHA256(with: zeroSeed)
        let fixedBlockOfSeedLength = Data(repeating: 0x00, count: Seed.minLength)
        let ciphertexts = keys.map { AuthenticatedEncryption.encrypt(fixedBlockOfSeedLength, with: $0, and: prng) }
        let toHash = ciphertexts.reduce(Data()) { return $0 + $1.raw }
        let seed = SHA256.hash(toHash)
        self.init(with: seed)
    }
}


// MARK: Implementing Equatable
extension Seed {
    public static func == (lhs: Seed, rhs: Seed) -> Bool {
        return lhs.raw == rhs.raw
    }
}


// MARK: Implementing Hashable
extension Seed {
    
    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(self.raw)
        return hasher.finalize()
    }

}


// MARK: Implementing NSCopying
// Thanks to our experience with the UID type, we know it is best to implement this
extension Seed {
    public func copy(with zone: NSZone? = nil) -> Any {
        return Seed(with: self.raw) as Any
    }
}


// MARK: Implementing ObvCodable
extension Seed {
    
    public convenience init?(_ obvEncoded: ObvEncoded) {
        guard let rawSeed = Data(obvEncoded) else { return nil }
        self.init(with: rawSeed)
    }
    
    public func obvEncode() -> ObvEncoded {
        return self.raw.obvEncode()
    }
}


// MARK: Implementing a ValueTransformer for Seed

public class SeedTransformer: ValueTransformer {
    
    override public class func transformedValueClass() -> AnyClass {
        return Seed.self
    }
    
    override public class func allowsReverseTransformation() -> Bool {
        return true
    }
    
    
    /// Turn an Seed into a Data object. This method never fails.
    override public func transformedValue(_ value: Any?) -> Any? {
        let uid = value as! Seed
        return uid.raw
    }
    
    /// Try to turn a Data object back into a Seed. This method can return nil.
    override public func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return Seed(with: data)
    }
    
}

public extension NSValueTransformerName {
    static let seedTransformerName = NSValueTransformerName(rawValue: "SeedTransformer")
}


// MARK: - Overriding CustomDebugStringConvertible

extension Seed {
    
    public override var debugDescription: String {
        return self.raw.hexString()
    }
    
}


// MARK: -

extension Seed {
    
    static func generateFromSecRandomCopyBytes() -> Seed {
        let seedBytes = UnsafeMutablePointer<UInt8>.allocate(capacity: Seed.minLength)
        defer { seedBytes.deallocate() }
        let res = SecRandomCopyBytes(kSecRandomDefault, Seed.minLength, seedBytes)
        guard res == errSecSuccess else { exit(-1) }
        let rawSeed = Data(bytes: seedBytes, count: Seed.minLength)
        let seed = Seed(with: rawSeed)!
        return seed
    }
    
}
