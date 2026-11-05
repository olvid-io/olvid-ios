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
import ObvBigInt
@testable import ObvCrypto


/// Checks that KEM decryption refuses a ciphertext that is a low-order point.
///
/// The ciphertext is the y-coordinate of a point B. Decryption multiplies B by the cofactor ν, so a low-order B gives the
/// neutral point, and the key would then be derived from the ciphertext alone, whatever our private key. A point has low
/// order exactly when ν·B is the neutral point, whose y-coordinate is 1.
///
/// The low-order points are the neutral point (y = 1), the point of order two (y = -1), the points of order four (y = 0)
/// and, on Curve25519 whose cofactor is 8, the points of order eight. Those are found as q·P for points P on the curve,
/// q being the order of the large subgroup: q·P keeps only the low-order part of P.
final class KEMLowOrderPointTests: XCTestCase {

    private let prng = ObvCryptoSuite.sharedInstance.prngService()


    func testALowOrderCiphertextIsRefusedOnCurve25519() throws {
        try assertEveryLowOrderCiphertextIsRefused(by: KEM_ECIES256KEM512_WithCurve25519.self, expectingAtLeast: 4)
    }


    func testALowOrderCiphertextIsRefusedOnMDC() throws {
        try assertEveryLowOrderCiphertextIsRefused(by: KEM_ECIES256KEM512_WithMDC.self, expectingAtLeast: 3)
    }


    func testAnHonestCiphertextStillDecryptsOnBothCurves() throws {
        for kem in [KEM_ECIES256KEM512_WithCurve25519.self, KEM_ECIES256KEM512_WithMDC.self] as [any KEM_ECIES256KEM512.Type] {
            let (publicKey, privateKey) = kem.generateKeyPair(with: prng)
            let (ciphertext, key) = try XCTUnwrap(kem.encrypt(using: publicKey, with: prng, makeKey))
            let decryptedKey = try XCTUnwrap(kem.decrypt(ciphertext, using: privateKey, makeKey))
            XCTAssertEqual(decryptedKey.data, key.data, "\(kem)")
        }
    }


    // MARK: - Helpers

    /// Every low-order y-coordinate found must be refused. `minimumCount` is the number of distinct low-order y-coordinates
    /// the curve has at least (1, -1 and 0, plus those of order eight on Curve25519), so that the search is known to have
    /// reached the points of highest order.
    private func assertEveryLowOrderCiphertextIsRefused(by kem: any KEM_ECIES256KEM512.Type, expectingAtLeast minimumCount: Int) throws {
        let curve = kem.curve
        let (_, privateKey) = kem.generateKeyPair(with: prng)
        let lowOrderYCoordinates = try lowOrderYCoordinates(on: curve)
        XCTAssertGreaterThanOrEqual(lowOrderYCoordinates.count, minimumCount, "\(kem)")
        let pLength = curve.parameters.p.byteSize()
        for y in lowOrderYCoordinates {
            let ciphertext = EncryptedData(data: Data(try [UInt8](y, count: pLength)))
            XCTAssertNil(kem.decrypt(ciphertext, using: privateKey, makeKey), "\(kem), y = \(y)")
        }
    }


    /// The distinct y-coordinates of the low-order points: the known ones, and q·P for random points P until a hundred
    /// tries have passed. Each is checked to be of low order, ν·y being 1.
    private func lowOrderYCoordinates(on curve: EdwardsCurve) throws -> [BigInt] {
        let p = curve.parameters.p
        let q = curve.parameters.q
        var found = [curve.getPointAtInfinity().y, curve.getPointOfOrderTwo().y, curve.getPointsOfOrderFour().0.y]
        for _ in 0..<100 {
            let y = prng.genBigInt(smallerThan: p)
            guard curve.pointsOnCurve(forYcoordinate: y) != nil else { continue }
            let lowOrderY = try XCTUnwrap(curve.scalarMultiplication(scalar: q, yCoordinate: y))
            if !found.contains(where: { $0 == lowOrderY }) {
                found.append(lowOrderY)
            }
        }
        for y in found {
            let nuTimesY = try XCTUnwrap(curve.scalarMultiplication(scalar: curve.parameters.nu, yCoordinate: y))
            XCTAssertTrue(nuTimesY == BigInt(1), "y = \(y) is not of low order")
        }
        return found
    }


    private func makeKey(_ bytes: Data) -> AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key {
        AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key(data: bytes)!
    }

}
