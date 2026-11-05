/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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

import XCTest
@testable import ObvCrypto


/// Checks the answers of the comparisons that MAC and signature verification make, now that they run in constant time.
///
/// Only the answers are checked: equal or not, for a difference at every position, for other lengths, and for slices that
/// do not start at index zero, since a signature's hash is a slice of the signature. Nothing here measures time, so these
/// tests would pass with a comparison that stops at the first difference.
final class ConstantTimeComparisonTests: XCTestCase {

    private let prng = ObvCryptoSuite.sharedInstance.prngService()


    // MARK: - Data.isEqualInConstantTime(to:)

    func testEqualBytesAreEqual() {
        let bytes = prng.genBytes(count: 32)
        XCTAssertTrue(bytes.isEqualInConstantTime(to: Data(bytes)))
    }


    func testADifferenceAtAnyPositionIsSeen() {
        let bytes = prng.genBytes(count: 32)
        for position in 0..<bytes.count {
            var other = bytes
            other[position] ^= 0x01
            XCTAssertFalse(bytes.isEqualInConstantTime(to: other), "position \(position)")
        }
    }


    func testOtherLengthsAreNotEqual() {
        let bytes = prng.genBytes(count: 32)
        XCTAssertFalse(bytes.isEqualInConstantTime(to: bytes.dropLast()))
        XCTAssertFalse(bytes.isEqualInConstantTime(to: bytes + Data([0x00])))
        XCTAssertFalse(bytes.isEqualInConstantTime(to: Data()))
        XCTAssertFalse(Data().isEqualInConstantTime(to: bytes))
    }


    func testTwoEmptyValuesAreEqual() {
        XCTAssertTrue(Data().isEqualInConstantTime(to: Data()))
    }


    func testSlicesAreComparedOnTheirOwnBytes() {
        let bytes = prng.genBytes(count: 32)
        let container = prng.genBytes(count: 7) + bytes + prng.genBytes(count: 5)
        let slice = container[container.startIndex+7..<container.startIndex+7+32]
        XCTAssertNotEqual(slice.startIndex, 0)
        XCTAssertTrue(slice.isEqualInConstantTime(to: bytes))
        XCTAssertTrue(bytes.isEqualInConstantTime(to: slice))
        let shiftedSlice = container[container.startIndex+6..<container.startIndex+6+32]
        XCTAssertFalse(shiftedSlice.isEqualInConstantTime(to: bytes))
    }


    // MARK: - MAC.verify

    func testACorrectMACVerifies() throws {
        let key = HMACWithSHA256.generateKey(with: prng)
        let message = prng.genBytes(count: 100)
        let mac = try MAC.compute(forData: message, withKey: key)
        XCTAssertTrue(try MAC.verify(mac: mac, forData: message, withKey: key))
    }


    func testAMACWithAnyByteChangedIsRefused() throws {
        let key = HMACWithSHA256.generateKey(with: prng)
        let message = prng.genBytes(count: 100)
        let mac = try MAC.compute(forData: message, withKey: key)
        for position in 0..<mac.count {
            var forged = mac
            forged[position] ^= 0x01
            XCTAssertFalse(try MAC.verify(mac: forged, forData: message, withKey: key), "position \(position)")
        }
    }


    func testATruncatedOrExtendedMACIsRefused() throws {
        let key = HMACWithSHA256.generateKey(with: prng)
        let message = prng.genBytes(count: 100)
        let mac = try MAC.compute(forData: message, withKey: key)
        XCTAssertFalse(try MAC.verify(mac: mac.dropLast(), forData: message, withKey: key))
        XCTAssertFalse(try MAC.verify(mac: mac + Data([0x00]), forData: message, withKey: key))
        XCTAssertFalse(try MAC.verify(mac: Data(), forData: message, withKey: key))
    }


    func testAMACOfAnotherMessageIsRefused() throws {
        let key = HMACWithSHA256.generateKey(with: prng)
        let mac = try MAC.compute(forData: prng.genBytes(count: 100), withKey: key)
        XCTAssertFalse(try MAC.verify(mac: mac, forData: prng.genBytes(count: 100), withKey: key))
    }


    // MARK: - Signature.verify

    func testAValidSignatureVerifiesOnBothCurves() throws {
        for implementation in [SignatureImplementationByteId.EC_SDSA_with_Curve25519, .EC_SDSA_with_MDC] {
            let (publicKey, privateKey) = Signature.generateKeyPair(for: implementation, with: prng)
            let message = prng.genBytes(count: 100)
            let signature = try XCTUnwrap(Signature.sign(message, with: privateKey, and: publicKey, using: prng))
            XCTAssertTrue(try Signature.verify(signature, on: message, with: publicKey), "\(implementation)")
        }
    }


    /// The signature is the hash followed by z: a change in the hash is caught by the comparison under test, a change in z
    /// by the recomputed hash.
    func testASignatureWithAnyByteChangedIsRefused() throws {
        let (publicKey, privateKey) = Signature.generateKeyPair(for: .EC_SDSA_with_Curve25519, with: prng)
        let message = prng.genBytes(count: 100)
        let signature = try XCTUnwrap(Signature.sign(message, with: privateKey, and: publicKey, using: prng))
        for position in 0..<signature.count {
            var forged = signature
            forged[position] ^= 0x01
            XCTAssertNotEqual(try? Signature.verify(forged, on: message, with: publicKey), true, "position \(position)")
        }
    }


    func testASignatureOfAnotherMessageIsRefused() throws {
        let (publicKey, privateKey) = Signature.generateKeyPair(for: .EC_SDSA_with_Curve25519, with: prng)
        let signature = try XCTUnwrap(Signature.sign(prng.genBytes(count: 100), with: privateKey, and: publicKey, using: prng))
        XCTAssertNotEqual(try? Signature.verify(signature, on: prng.genBytes(count: 100), with: publicKey), true)
    }

}
