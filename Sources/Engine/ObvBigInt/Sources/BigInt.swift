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
import gmp

final public class BigInt: Comparable, Hashable, CustomDebugStringConvertible, Decodable {
    
    fileprivate var readVal: mpz_t
    private var writeVal: mpz_t
    
    // MARK: Initialization and Deinitialization Functions
    
    public init() {
        readVal = mpz_t()
        writeVal = mpz_t()
        __gmpz_init(&readVal)
        __gmpz_init(&writeVal)
    }
    
    convenience public init(_ op: Int) {
        self.init()
        set(op)
    }

    convenience public init(_ op: String, base: BigIntBasis = .ten) throws {
        self.init()
        try set(op, base: base)
    }
    
    public init(_ op: BigInt) {
        readVal = mpz_t()
        writeVal = mpz_t()
        __gmpz_init_set(&readVal, &op.readVal)
        __gmpz_init(&writeVal)
    }

    /// Initialize a BigInt, assuming that the bytes represent a positive value.
    ///
    /// - Parameters:
    ///   - bytes: The bytes representing the BigInt, the first byte being the most significant byte.
    convenience public init(_ bytes: [UInt8]) {
        self.init(0)
        if bytes.count > 0 {
            let limbByteSize = MemoryLayout<mp_limb_t>.size
            let numberOfRequiredLimbs = 1 + (bytes.count - 1) / limbByteSize /* ceil(bytes.count/limbByteSize) */
            let limbStorage = __gmpz_limbs_write(&readVal, numberOfRequiredLimbs)!
            for limbNumber in 0..<numberOfRequiredLimbs {
                let slice = bytes[max(0, bytes.count - limbByteSize*(limbNumber+1))..<bytes.count - limbByteSize*limbNumber]
                let limb = BigInt.getLimb(fromByteArray: slice, withLimbByteSize: limbByteSize)
                limbStorage[limbNumber] = limb
            }
            __gmpz_limbs_finish(&readVal, numberOfRequiredLimbs)
        }
    }

    private class func getLimb(fromByteArray bytes: ArraySlice<UInt8>, withLimbByteSize limbByteSize: Int) -> mp_limb_t {
        assert(bytes.count <= limbByteSize)
        var limb: mp_limb_t = 0
        for i in 0..<min(limbByteSize, bytes.count) {
            limb <<= 8
            limb += mp_limb_t(bytes[bytes.startIndex + i])
        }
        return limb
    }

    convenience public init(_ data: Data) {
        let bytes = [UInt8](data)
        self.init(bytes)
    }

    deinit {
        __gmpz_clear(&readVal)
        __gmpz_clear(&writeVal)
    }

    // MARK: Assignment Functions

    public func set(_ op: Int) {
        __gmpz_set_si(&readVal, op)
    }

    public func set(_ op: UInt) {
        __gmpz_set_ui(&readVal, op)
    }

    public func set(_ op: String, base: BigIntBasis = .ten) throws {
        let ret = __gmpz_set_str(&readVal, op, base.rawValue)
        if ret < 0 {
            throw BigIntError.invalidInitializationString(invalidString: op, base: base)
        }
    }

    public func set(_ op: BigInt) {
        __gmpz_set(&readVal, &op.readVal)
    }

    // MARK: Arithmetic Functions

    public class func add(rop: BigInt, op1: BigInt, op2: BigInt) {
        __gmpz_add(&rop.writeVal, &op1.readVal, &op2.readVal)
        swap(&rop.writeVal, &rop.readVal)
    }
    
    public func add(_ op: BigInt, modulo: BigInt? = nil) -> BigInt {
        __gmpz_add(&self.writeVal, &self.readVal, &op.readVal)
        if modulo != nil {
            __gmpz_mod(&self.readVal, &self.writeVal, &modulo!.readVal)
        } else {
            swap(&self.readVal, &self.writeVal)
        }
        return self
    }
    
    public class func add(rop: BigInt, op1: BigInt, op2: UInt) {
        __gmpz_add_ui(&rop.writeVal, &op1.readVal, op2)
        swap(&rop.readVal, &rop.writeVal)
    }
    
    public func add(_ op: Int) -> BigInt {
        if op >= 0 {
            __gmpz_add_ui(&self.writeVal, &self.readVal, UInt(op))
        } else {
            __gmpz_sub_ui(&self.writeVal, &self.readVal, UInt(-op))
        }
        swap(&self.readVal, &self.writeVal)
        return self
    }

    public class func sub(rop: BigInt, op1: BigInt, op2: BigInt) {
        __gmpz_sub(&rop.writeVal, &op1.readVal, &op2.readVal)
        swap(&rop.readVal, &rop.writeVal)
    }
    
    public func sub(_ op: BigInt, modulo: BigInt? = nil) -> BigInt {
        __gmpz_sub(&self.writeVal, &self.readVal, &op.readVal)
        if modulo != nil {
            __gmpz_mod(&self.readVal, &self.writeVal, &modulo!.readVal)
        } else {
            swap(&self.readVal, &self.writeVal)
        }
        return self
    }

    public class func sub(rop: BigInt, op1: BigInt, op2: Int) {
        if op2 >= 0 {
            __gmpz_sub_ui(&rop.writeVal, &op1.readVal, UInt(op2))
        } else {
            __gmpz_add_ui(&rop.writeVal, &op1.readVal, UInt(-op2))
        }
        swap(&rop.readVal, &rop.writeVal)
    }
    
    public func sub(_ op: Int) -> BigInt {
        if op >= 0 {
            __gmpz_sub_ui(&self.writeVal, &self.readVal, UInt(op))
        } else {
            __gmpz_add_ui(&self.writeVal, &self.readVal, UInt(-op))
        }
        swap(&self.readVal, &self.writeVal)
        return self
    }

    public class func neg(rop: BigInt, op: BigInt) {
        __gmpz_neg(&rop.writeVal, &op.readVal)
        swap(&rop.readVal, &rop.writeVal)
    }
    
    public func neg() -> BigInt {
        __gmpz_neg(&self.writeVal, &self.readVal)
        swap(&self.readVal, &self.writeVal)
        return self
    }
    
    public class func mul(rop: BigInt, op1: BigInt, op2: BigInt, modulo: BigInt? = nil) {
        __gmpz_mul(&rop.writeVal, &op1.readVal, &op2.readVal)
        if modulo != nil {
            __gmpz_mod(&rop.readVal, &rop.writeVal, &modulo!.readVal)
        } else {
            swap(&rop.readVal, &rop.writeVal)
        }
    }
    
    public func mul(_ op: BigInt, modulo: BigInt? = nil) -> BigInt {
        __gmpz_mul(&self.writeVal, &self.readVal, &op.readVal)
        if modulo != nil {
            __gmpz_mod(&self.readVal, &self.writeVal, &modulo!.readVal)
        } else {
            swap(&self.readVal, &self.writeVal)
        }
        return self
    }

    /// Returns op * 2^pow.
    ///
    /// - Parameters:
    ///   - rop: Where the result is stored.
    ///   - op: The multiplied integer.
    ///   - pow: The power.
    public class func mulTwoExp(rop: BigInt, op: BigInt, pow: UInt) {
        __gmpz_mul_2exp(&rop.writeVal, &op.readVal, pow)
        swap(&rop.readVal, &rop.writeVal)
    }
    
    public func mulTwoExp(_ pow: UInt) -> BigInt {
        __gmpz_mul_2exp(&self.writeVal, &self.readVal, pow)
        swap(&self.readVal, &self.writeVal)
        return self
    }

    // MARK: Division Functions

    public class func mod(rop: BigInt, op: BigInt, modulo: BigInt) {
        __gmpz_mod(&rop.writeVal, &op.readVal, &modulo.readVal)
        swap(&rop.readVal, &rop.writeVal)
    }

    public func mod(_ modulo: BigInt) -> BigInt {
        __gmpz_mod(&self.writeVal, &self.readVal, &modulo.readVal)
        swap(&self.readVal, &self.writeVal)
        return self
    }

    public class func mod(rop: BigInt, op: BigInt, modulo: UInt) {
        __gmpz_fdiv_r_ui(&rop.writeVal, &op.readVal, modulo)
        swap(&rop.readVal, &rop.writeVal)
    }
    
    public func mod(_ modulo: UInt) -> BigInt {
        __gmpz_fdiv_r_ui(&self.writeVal, &self.readVal, modulo)
        swap(&self.readVal, &self.writeVal)
        return self
    }

    /// Compute op / 2^pow, the result being rounded towards zero.
    ///
    /// - Parameters:
    ///   - rop: The quotient.
    ///   - op: The dividend.
    ///   - pow: The power of 2.
    public class func div2pow(rop: BigInt, op: BigInt, pow: UInt) {
        __gmpz_tdiv_q_2exp(&rop.writeVal, &op.readVal, pow)
        swap(&rop.readVal, &rop.writeVal)
    }
    
    public func div2pow(_ pow: UInt) -> BigInt {
        __gmpz_tdiv_q_2exp(&self.writeVal, &self.readVal, pow)
        swap(&self.readVal, &self.writeVal)
        return self
    }
    
    // MARK: Exponentiation Functions

    public class func powm(rop: BigInt, base: BigInt, exp: BigInt, modulo: BigInt) {
        __gmpz_powm(&rop.writeVal, &base.readVal, &exp.readVal, &modulo.readVal)
        swap(&rop.readVal, &rop.writeVal)
    }
    
    /// Raise self to the indicated power. The result is modulo reduced.
    ///
    /// - Parameters:
    ///   - pow: The power at which `self` is raised.
    ///   - modulo: The value of the modulo.
    /// - Returns: `self`
    public func powm(_ exp: BigInt, modulo: BigInt) -> BigInt {
        __gmpz_powm(&self.writeVal, &self.readVal, &exp.readVal, &modulo.readVal)
        swap(&self.readVal, &self.writeVal)
        return self
    }

    public class func powm(rop: BigInt, base: BigInt, exp: UInt, modulo: BigInt) {
        __gmpz_powm_ui(&rop.writeVal, &base.readVal, exp, &modulo.readVal)
        swap(&rop.readVal, &rop.writeVal)
    }

    public func powm(_ exp: UInt, modulo: BigInt) -> BigInt {
        __gmpz_powm_ui(&self.writeVal, &self.readVal, exp, &modulo.readVal)
        swap(&self.readVal, &self.writeVal)
        return self
    }

    // MARK: Number Theoretic Functions

    public class func invert(rop: BigInt, op: BigInt, modulo: BigInt) throws {
        let ret = __gmpz_invert(&rop.writeVal, &op.readVal, &modulo.readVal)
        if ret == 0 {
            throw BigIntError.modularInverseDoesNotExists
        } else {
            swap(&rop.readVal, &rop.writeVal)
        }
    }
    
    public func invert(modulo: BigInt) throws -> BigInt {
        let ret = __gmpz_invert(&self.writeVal, &self.readVal, &modulo.readVal)
        if ret == 0 {
            throw BigIntError.modularInverseDoesNotExists
        }
        swap(&self.readVal, &self.writeVal)
        return self
    }
    

    /// If `op` is a quadratic residue modulo the prime `p`, this method finds the two square roots and store them in `rop1` and `rop2`.
    /// If `op` is not a quadrativ residue modulo `p`, this method throws an error.
    /// This method has undefined behavior if `p` is not a prime.
    ///
    /// - Parameters:
    ///   - rop1: Where one of the two square roots are stored.
    ///   - rop2: Where one of the two square roots are stored.
    ///   - op: An integer between 0 and `p`.
    ///   - p: The modulo, expected to be prime.
    /// - Throws: An exception if `op` is not a QR modulo `p`.
    public class func sqrtm(rop1: BigInt, rop2: BigInt, op: BigInt, p: BigInt) throws {

        let one = BigInt(1) // Only used for comparison

        // Compute (p-1)/2
        let pMinusOneOverTwo = BigInt(p).sub(1).div2pow(1)
        
        // If op^((p-1)/2) mod p != 1, then op is not a quadratic residue module p
        if BigInt(op).powm(pMinusOneOverTwo, modulo: p) != one {
            throw BigIntError.noSquareRootExists
        }

        if BigInt(p).mod(4) == BigInt(3) {
            // When p mod 4 = 3, then the square roots are ±op^((p+1)/4) mod p
            // Compute op^((p+1)/4) mod p
            let pPlusOneOverFour = BigInt(p).add(1).div2pow(2)
            rop1.set(BigInt(op).powm(pPlusOneOverFour, modulo: p))
            rop2.set(0)
            if rop1 != rop2 {
                BigInt.sub(rop: rop2, op1: p, op2: rop1)
            }
        } else {
            // When p mod 4 != 3, it's more complicated...
            // Find the smaller g s.t. g^((p-1)/2) mod p != 1
            let g = BigInt(2)
            while BigInt(g).powm(pMinusOneOverTwo, modulo: p) == one {
                _ = g.add(1)
            }
            // Find t and s
            let t = BigInt(p).sub(1)
            var s = 1
            while t.isEven() {
                _ = t.div2pow(1)
                s += 1
            }
            // Find e
            let e = BigInt(0)
            for i in 1..<s {
                let temp1 = try BigInt(g).powm(e, modulo: p).invert(modulo: p)
                let temp2 = BigInt(pMinusOneOverTwo).div2pow(UInt(i))
                if BigInt(op).mul(temp1).powm(temp2, modulo: p) != one {
                    _ = e.add(BigInt(1).mulTwoExp(UInt(i)))
                }
            }
            // Compute one of the two square roots
            // First: compute g^(-t*e / 2) mod p
            let pow = BigInt(e).mul(t).div2pow(1)
            rop1.set(try BigInt(g).powm(pow, modulo: p).invert(modulo: p))
            // Second: multiply by op^((t+1)/2) and reduce modulo p
            pow.set(BigInt(t).add(1).div2pow(1))
            _ = rop1.mul(BigInt(op).powm(pow, modulo: p), modulo: p)
            rop2.set(0)
            if rop1 != rop2 {
                BigInt.sub(rop: rop2, op1: p, op2: rop1)
            }
        }


    }

    // MARK: Comparison Functions

    public func isNegative() -> Bool {
        return self.readVal._mp_size < 0
    }
    
    public func isNonNegative() -> Bool {
        return self.readVal._mp_size >= 0
    }
    
    public func isPositive() -> Bool {
        return self.readVal._mp_size > 0
    }

    public class func cmp(op1: BigInt, op2: BigInt) -> Int {
        return Int(__gmpz_cmp(&op1.readVal, &op2.readVal))
    }

    public static func < (lhs: BigInt, rhs: BigInt) -> Bool {
        return BigInt.cmp(op1: lhs, op2: rhs) < 0
    }

    public static func == (lhs: BigInt, rhs: BigInt) -> Bool {
        return BigInt.cmp(op1: lhs, op2: rhs) == 0
    }

    // MARK: Logical and Bit Manipulation Functions

    public func setBit(atIndex index: Int) -> BigInt {
        __gmpz_setbit(&self.readVal, UInt(index))
        return self
    }

    /// Returns true if the bit of `self` at the requested position is set. The least significant bit is number 0.
    ///
    /// - Parameter position: The bit position to test against.
    public func isBitSet(atPosition position: UInt) -> Bool {
        return __gmpz_tstbit(&self.readVal, position) == 1
    }

    public func isOdd() -> Bool {
        return self.isBitSet(atPosition: 0)
    }

    public func isEven() -> Bool {
        return !self.isBitSet(atPosition: 0)
    }

    // MARK: Miscellaneous Functions

    public func size(inBase base: BigIntBasis = .two) -> Int {
        return __gmpz_sizeinbase(&self.readVal, base.rawValue)
    }
    
    public func byteSize() -> Int {
        return 1 + (self.size(inBase: .sixteen) - 1) / 2
    }

    // MARK: Implementing Hashable

    public func hash(into hasher: inout Hasher) {
        let limbStorage = __gmpz_limbs_read(&self.readVal)!
        let numberOfLimbs = __gmpz_size(&self.readVal)
        hasher.combine(numberOfLimbs)
        guard numberOfLimbs > 0 else { return }
        for i in 0..<numberOfLimbs {
            hasher.combine(limbStorage[i])
        }
    }
}

// MARK: BigInt implements CustomDebugStringConvertible
extension BigInt {
    
    public var debugDescription: String {
        return String(self, base: .ten)
    }

}

// MARK: BigInt implements Decodable (for Json parsing)
extension BigInt {
    
    // We expect that big integer in Json are represented by a string and that this string is a base 10 representation of the big integer. For example "6713265789432547389257349807590823475893427093257098324".
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let bigIntAsStringInBase10 = try container.decode(String.self)
        try self.init(bigIntAsStringInBase10, base: .ten)
    }
    
}


extension String {
    public init(_ op: BigInt, base: BigIntBasis = .ten) {
        let charPtr = __gmpz_get_str(nil, base.rawValue, &op.readVal)!
        self = String(cString: charPtr)
        free(charPtr)
    }
}

extension UInt {
    public init(_ op: BigInt) throws {
        if __gmpz_fits_ulong_p(&op.readVal) != 0 {
            self = __gmpz_get_ui(&op.readVal)
        } else {
            throw BigIntError.bigIntIsTooBigForUInt
        }
    }
}

extension Int {
    public init(_ op: BigInt) throws {
        if __gmpz_fits_slong_p(&op.readVal) != 0 {
            self = __gmpz_get_si(&op.readVal)
        } else {
            throw BigIntError.bigIntIsTooBigForInt
        }
    }
}

extension Array where Element == UInt8 {

    public init(_ op: BigInt, count targetCount: Int) throws {
        if op.isNegative() {
            throw BigIntError.cannotEncodeNegativeBigInt
        }

        // Determine the limbs we should convert to an array of bytes
        let limbStorage = __gmpz_limbs_read(&op.readVal)!
        let numberOfLimbs = __gmpz_size(&op.readVal)
        // Convert the limbs to an array of bytes
        var bytes = [UInt8]()
        for i in 0..<numberOfLimbs {
            let limb = limbStorage[i]
            let limbAsBytes = Array.bytes(fromLimb: limb)
            bytes.append(contentsOf: limbAsBytes)
        }

        // If the bytes array is too long, we remove the most significant bytes provided that they are 0x00 (if this is not the case, we throw an exception)
        if bytes.count > targetCount {
            let mostSignificantBytes = bytes[targetCount..<bytes.count]
            if mostSignificantBytes.contains(where: { $0 > 0 }) {
                throw BigIntError.insufficientNumberOfBytes
            } else {
                bytes.removeSubrange(Int(targetCount)..<bytes.count)
            }
        }

        // If the bytes array is not as long as expected, with appends as many 0 bytes as required.
        if bytes.count < targetCount {
            let numberOfMissingBytes = Int(targetCount) - bytes.count
            bytes.append(contentsOf: [UInt8](repeating: 0, count: numberOfMissingBytes))
        }

        self = bytes.reversed()

    }

    private static func bytes(fromLimb limb: mp_limb_t) -> [UInt8] {
        let limbByteSize = MemoryLayout<mp_limb_t>.size
        var res = [UInt8](repeating: 0, count: limbByteSize)
        for i in 0..<limbByteSize {
            res[i] = UInt8((limb >> (8*i)) & UInt(0xFF))
        }
        return res
    }
}

extension Data {
    
    public init(_ op: BigInt, count targetCount: Int) throws {
        let bytes = try [UInt8](op, count: targetCount)
        self = Data(bytes)
    }
    
}
