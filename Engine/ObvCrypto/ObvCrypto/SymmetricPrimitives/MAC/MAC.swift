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
import ObvEncoder

enum MACError: Error {
    case incorrectKeyLength
    case incorrectKey
}

// MARK: Protocols

/// This protocol is intended to be implemented by the class MAC. The objective is to allow the outside world to call the compute and verify method directly on the class MAC. Thanks to the fact the keys know which concrete implementation of MAC they correspond to, the concrete implementation can be transparently called.
public protocol MACCommon {
    static func compute(forData: Authenticable, withKey: MACKey) throws -> Data
    static func verify(mac: Data, forData: Authenticable, withKey: MACKey) throws -> Bool
}

/// A concrete MAC implementation must not only implement compute and verify, but must also be able to generate keys. Those keys encapsulate the concrete implementation that generated them.
public protocol MACConcrete: MACCommon {
    static func generateKey(with: PRNG?) -> MACKey
    static var outputLength: Int { get }
    static var minimumKeyLength: Int { get }
}

protocol MACGeneric: MACCommon {
    static func generateKey(for: MACImplementationByteId, with: PRNG?) -> MACKey
}

public protocol Authenticable {
    // Update for Swift5
    func withUnsafeBytes<ResultType>(_ body: (UnsafeRawBufferPointer) throws -> ResultType) rethrows -> ResultType
    var count: Int { get }
}

// MARK: Classes

public final class MAC: MACGeneric {
    
    static func generateKey(for implemByteId: MACImplementationByteId, with prng: PRNG?) -> MACKey {
        return implemByteId.algorithmImplementation.generateKey(with: prng)
    }

    
    public static func compute(forData data: Authenticable, withKey key: MACKey) throws -> Data {
        return try key.algorithmImplementationByteId.algorithmImplementation.compute(forData: data, withKey: key)
    }
    
    public static func outputLength(for implemByteId: MACImplementationByteId) -> Int {
        return implemByteId.algorithmImplementation.outputLength
    }
    
    public static func verify(mac: Data, forData data: Authenticable, withKey key: MACKey) throws -> Bool {
        return try key.algorithmImplementationByteId.algorithmImplementation.verify(mac: mac, forData: data, withKey: key)
    }
}

protocol MacBasedOnCommonCrypto {
    
    static var keyType: MACKey.Type { get }
    
    static func ccHmac(_ key: UnsafeRawPointer!, _ keyLength: Int, _ data: UnsafeRawPointer!, _ dataLength: Int, _ macOut: UnsafeMutableRawPointer!)
    
}

extension MACConcrete where Self: MacBasedOnCommonCrypto {
    
    static func compute(forData data: Authenticable, withKey key: MACKey) throws -> Data {
        guard type(of: key) == self.keyType else { throw MACError.incorrectKey }
        let keyBytes = [UInt8](key.data)
        let mac = UnsafeMutablePointer<UInt8>.allocate(capacity: outputLength)
        defer { mac.deallocate() }
        data.withUnsafeBytes { (bufferPtr) -> Void in
            let ptr = bufferPtr.baseAddress!
            ccHmac(keyBytes, keyBytes.count, ptr, data.count, mac)
        }
        let dataToReturn = Data(bytes: mac, count: outputLength)
        return dataToReturn
    }
    
    static func verify(mac: Data, forData data: Authenticable, withKey key: MACKey) throws -> Bool {
        let computedMac = try compute(forData: data, withKey: key)
        return [UInt8](mac) == [UInt8](computedMac)
    }
}

class HMACWithSHA256: MACConcrete, MacBasedOnCommonCrypto {
    
    static let keyType: MACKey.Type = HMACWithSHA256Key.self

    static let outputLength = 32
    static let minimumKeyLength = HMACWithSHA256Key.length
    
    static func generateKey(with _prng: PRNG?) -> MACKey {
        let prng = _prng ?? ObvCryptoSuite.sharedInstance.prngService()
        let seed = prng.genSeed()
        return generateKey(with: seed)
    }

    static func generateKey(with seed: Seed) -> MACKey {
        let key = KDFFromPRNGWithHMACWithSHA256.generate(from: seed, { HMACWithSHA256Key(data: $0)! })!
        return key
    }
    
    static func generateKeyForBackup(with prng: PRNG) -> MACKey {
        let seed = prng.genSeed()
        let key = KDFFromPRNGWithHMACWithSHA256.generate(from: seed, { HMACWithSHA256Key(data: $0)! })!
        return key
    }

    static func ccHmac(_ key: UnsafeRawPointer!, _ keyLength: Int, _ data: UnsafeRawPointer!, _ dataLength: Int, _ macOut: UnsafeMutableRawPointer!) {
        CCHmac(UInt32(kCCHmacAlgSHA256), key, keyLength, data, dataLength, macOut)
    }

}
