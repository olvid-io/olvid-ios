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
import BigInt


public protocol PRNG {
    func genBytes(count: Int) -> Data
    func genBigInt(smallerThan upperBound: BigInt) -> BigInt
    func genSeed() -> Seed
}

public protocol ConcretePRNG: PRNG {
    init(with: Seed)
    func reseed(with seed: Seed)
}

extension PRNG {
    
    public func genBigInt(smallerThan upperBound: BigInt) -> BigInt {
        var randomBigInt = BigInt()
        // Compute the bitlength of upperBound-1
        let temp = BigInt()
        BigInt.sub(rop: temp, op1: upperBound, op2: 1)
        let bitLength = temp.size()
        // Compute the mask to apply to the most significant byte
        let byteLength = 1 + (bitLength-1)/8
        let maskOnMostSignificantByte = UInt8((1<<(bitLength - 8*(byteLength-1))) - 1)
        // Iterate until an appropriate number is found
        while true {
            let randomBytes = genBytes(count: byteLength)
            let msb = randomBytes.first! & maskOnMostSignificantByte
            var truncatedRandomBytes = Data(capacity: byteLength)
            truncatedRandomBytes.append(msb)
            truncatedRandomBytes.append(randomBytes.dropFirst())
            randomBigInt = BigInt(truncatedRandomBytes)
            if randomBigInt < upperBound {
                break
            }
        }
        return randomBigInt
    }
    
    public func genSeed() -> Seed {
        let rawSeed = genBytes(count: Seed.minLength)
        return Seed(with: rawSeed)!
    }
    
    public func genBackupSeed() -> BackupSeed {
        let rawSeed = genBytes(count: BackupSeed.byteLength)
        return BackupSeed(with: rawSeed)!
    }
}

/// This is an implementation of the PRNG HMAC_DRBG described in section 10.1.2 of the NIST SP 800-90A Rev. 1. We use HMAC with SHA256.
class PRNGWithHMACWithSHA256: ConcretePRNG {
    
    private static var hashOutputLength: Int {
        return SHA256.outputLength
    }
    
    private var k = HMACWithSHA256Key(data: Data(repeating: 0, count: PRNGWithHMACWithSHA256.hashOutputLength))!
    private var v = Data(repeating: 1, count: PRNGWithHMACWithSHA256.hashOutputLength)

    required init(with seed: Seed) {
        update(withData: seed.raw)
    }
    
    private func update(withData data: Data = Data()) {
        var dataForUpdatingK = Data()
        dataForUpdatingK.append(v)
        dataForUpdatingK.append(0)
        dataForUpdatingK.append(data)
        k = HMACWithSHA256Key(data: try! HMACWithSHA256.compute(forData: dataForUpdatingK, withKey: k))!
        v = try! HMACWithSHA256.compute(forData: v, withKey: k)
        if data.count > 0 {
            dataForUpdatingK = Data()
            dataForUpdatingK.append(v)
            dataForUpdatingK.append(1)
            dataForUpdatingK.append(data)
            k = HMACWithSHA256Key(data: try! HMACWithSHA256.compute(forData: dataForUpdatingK, withKey: k))!
            v = try! HMACWithSHA256.compute(forData: v, withKey: k)
        }
    }
    
    func genBytes(count: Int) -> Data {
        var generatedBytes = Data(capacity: count)
        while generatedBytes.count < count {
            v = try! HMACWithSHA256.compute(forData: v, withKey: k)
            generatedBytes.append(v)
        }
        update()
        return generatedBytes.prefix(count)
    }
    
    func reseed(with seed: Seed) {
        update(withData: seed.raw)
    }
    
}

public extension CryptoKeyId {
    static func gen(with prng: PRNG) -> CryptoKeyId {
        let raw = prng.genBytes(count: CryptoKeyId.length)
        return CryptoKeyId.init(raw)!
    }
}

public extension UID {
    static func gen(with prng: PRNG) -> UID {
        let raw = prng.genBytes(count: UID.length)
        return UID(uid: raw)!
    }
}
