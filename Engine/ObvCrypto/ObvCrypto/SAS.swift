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

public final class SAS {

    private static let errorDomain = "SAS"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    
//    /// 2019-10-24: This is the legacy way of computing a SAS. It shall be removed within the following weeks.
    public static func compute(seed1: Seed, seed2: Seed, numberOfDigits: Int) -> Data? {
        let seed = Seed.concat(seed1, with: seed2)
        let prng = PRNGWithHMACWithSHA256(with: seed)
        let zeroes = String(repeating: "0", count: numberOfDigits)
        let maxAsString = "1" + zeroes
        let max: BigInt
        do {
            max = try BigInt(maxAsString, base: .ten)
        } catch {
            return nil
        }
        let sasAsBigInt = prng.genBigInt(smallerThan: max)
        let sasPostfix = String(sasAsBigInt, base: .ten)
        let sasPrefix = String(repeating: "0", count: numberOfDigits - sasPostfix.count)
        let sas = sasPrefix + sasPostfix
        return sas.data(using: .utf8)!
    }
    
    
    /// 2019-10-24: This new way of computing a SAS will be used in the new version of the trust authentication protocol.
    public static func compute(seedAlice: Seed, seedBob: Seed, identityBob: ObvCryptoIdentity, numberOfDigits: Int) throws -> Data {
        let toHash = identityBob.getIdentity() + seedAlice.raw
        let hash = SHA256.hash(toHash)
        let xorLength = min(hash.count, seedBob.length)
        let hashToXor = hash[hash.startIndex..<hash.startIndex+xorLength]
        let seedBobToXor = seedBob.raw[seedBob.raw.startIndex..<seedBob.raw.startIndex+xorLength]
        let xorResult = try Data.xor(hashToXor, seedBobToXor)
        guard let seed = Seed(with: xorResult) else {
            throw makeError(message: "Could not instantiate a seed on the basis of the xor between an identity and another seed")
        }
        let prng = PRNGWithHMACWithSHA256(with: seed)
        let zeroes = String(repeating: "0", count: numberOfDigits)
        let maxAsString = "1" + zeroes
        let max: BigInt
        do {
            max = try BigInt(maxAsString, base: .ten)
        } catch {
            throw makeError(message: "Could not instantiate BigInt")
        }
        let sasAsBigInt = prng.genBigInt(smallerThan: max)
        let sasPostfix = String(sasAsBigInt, base: .ten)
        let sasPrefix = String(repeating: "0", count: numberOfDigits - sasPostfix.count)
        let sas = sasPrefix + sasPostfix
        return sas.data(using: .utf8)!
    }

}
