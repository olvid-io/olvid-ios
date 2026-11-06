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
import ObvEncoder
@testable import ObvCrypto


/// Checks how decoded public keys and KEM ciphertexts treat their coordinates.
///
/// A coordinate is a number modulo p, and its encoding has room for numbers up to 2^(8·length) - 1. A y that is not below p
/// would be a second encoding of y mod p, so a second encoding of the same key and of the identity that holds it: decoding
/// refuses it, in the compact and the dictionary forms. Decoding does not check that y belongs to a point on the curve, as
/// ``PublicKeyFromEdwardsCurvePoint/init(yCoordinate:curveByteId:)`` explains, so an off-curve key decodes, signatures never
/// verify with it and ``KEM_ECIES256KEM512`` refuses to encrypt to it. KEM decryption checks that its ciphertext is a
/// canonical y-coordinate of a point on the curve.
final class PublicKeyYCoordinateValidationTests: XCTestCase {

    private let prng = ObvCryptoSuite.sharedInstance.prngService()


    // MARK: - The on-curve check

    /// ``EdwardsCurve/isCanonicalYCoordinateOfAPointOnCurve(_:)`` uses a Legendre symbol, ``EdwardsCurve/pointsOnCurve(forYcoordinate:)``
    /// a square root. They must agree on every y but ±1, where the square root refuses x² = 0.
    func testTheOnCurveCheckAgreesWithTheSquareRoot() {
        for c in curvesUnderTest {
            let curve = c.curve
            var onCurveCount = 0
            for _ in 0..<100 {
                let y = prng.genBigInt(smallerThan: curve.parameters.p)
                let isOnCurve = curve.isCanonicalYCoordinateOfAPointOnCurve(y)
                XCTAssertEqual(isOnCurve, curve.pointsOnCurve(forYcoordinate: y) != nil, "\(c.name), y = \(y)")
                if isOnCurve { onCurveCount += 1 }
            }
            // About half of the y-coordinates belong to a point on the curve; both answers must have been tested
            XCTAssertGreaterThan(onCurveCount, 0, c.name)
            XCTAssertLessThan(onCurveCount, 100, c.name)
        }
    }


    func testTheOnCurveCheckAcceptsTheYCoordinatesWhereXIsZeroOrSquaresToOne() {
        for c in curvesUnderTest {
            let curve = c.curve
            let p = curve.parameters.p
            XCTAssertTrue(curve.isCanonicalYCoordinateOfAPointOnCurve(BigInt(1)), c.name)
            XCTAssertTrue(curve.isCanonicalYCoordinateOfAPointOnCurve(BigInt(p).sub(1)), c.name)
            XCTAssertTrue(curve.isCanonicalYCoordinateOfAPointOnCurve(BigInt(0)), c.name)
        }
    }


    func testTheOnCurveCheckRefusesACoordinateThatIsNotCanonical() {
        for c in curvesUnderTest {
            let curve = c.curve
            let p = curve.parameters.p
            let y = randomOnCurveY(on: curve)
            XCTAssertFalse(curve.isCanonicalYCoordinateOfAPointOnCurve(BigInt(y).add(p)), c.name)
            XCTAssertFalse(curve.isCanonicalYCoordinateOfAPointOnCurve(BigInt(p)), c.name)
            XCTAssertFalse(curve.isCanonicalYCoordinateOfAPointOnCurve(BigInt(-1)), c.name)
        }
    }


    // MARK: - Compact keys

    func testACompactKeyWhoseYIsNotBelowPIsRefused() throws {
        for c in curvesUnderTest {
            let p = c.curve.parameters.p
            for y in [BigInt(p), BigInt(p).add(1), largestEncodableY(on: c.curve)] {
                XCTAssertNil(try encryptionKey(fromCompactY: y, on: c), "\(c.name), y = \(y)")
                XCTAssertNil(try authenticationKey(fromCompactY: y, on: c), "\(c.name), y = \(y)")
            }
        }
    }


    /// A y and y + p would decode to the same key.
    func testACompactKeyHasASingleEncoding() throws {
        for c in curvesUnderTest {
            let y = randomOnCurveY(on: c.curve, withAnAliasThatFits: true)
            let alias = BigInt(y).add(c.curve.parameters.p)
            XCTAssertNotNil(try encryptionKey(fromCompactY: y, on: c), c.name)
            XCTAssertNotNil(try authenticationKey(fromCompactY: y, on: c), c.name)
            XCTAssertNil(try encryptionKey(fromCompactY: alias, on: c), c.name)
            XCTAssertNil(try authenticationKey(fromCompactY: alias, on: c), c.name)
        }
    }


    /// On Curve25519, p < 2^255, so y + p always fits in the 32 bytes of a compact key.
    func testAnIdentityHasASingleEncoding() throws {
        let c = curvesUnderTest[0]
        let pLength = c.curve.parameters.p.byteSize()
        let serverURL = URL(string: "https://server.olvid.io")!
        let owned = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL,
                                               forAuthenticationImplementationId: .Signature_with_EC_SDSA_with_Curve25519,
                                               andPublicKeyEncryptionImplementationByteId: .KEM_ECIES_Curve25519_and_DEM_CTR_AES_256_then_HMAC_SHA_256,
                                               using: prng)
        let authenticationCompactKey = owned.publicKeyForAuthentication.getCompactKey()
        let encryptionCompactKey = owned.publicKeyForPublicKeyEncryption.getCompactKey()
        let prefix = Data(serverURL.absoluteString.utf8) + Data([0x00])

        let bytes = prefix + authenticationCompactKey + encryptionCompactKey
        XCTAssertNotNil(ObvCryptoIdentity(from: bytes))

        let aliasOfAuthenticationKey = try compactKeyWithAliasedY(authenticationCompactKey, on: c.curve, pLength: pLength)
        XCTAssertNil(ObvCryptoIdentity(from: prefix + aliasOfAuthenticationKey + encryptionCompactKey))

        let aliasOfEncryptionKey = try compactKeyWithAliasedY(encryptionCompactKey, on: c.curve, pLength: pLength)
        XCTAssertNil(ObvCryptoIdentity(from: prefix + authenticationCompactKey + aliasOfEncryptionKey))
    }


    // MARK: - Dictionaries

    func testADictionaryWithOnlyAYThatIsNotBelowPIsRefused() {
        for c in curvesUnderTest {
            let curve = c.curve
            let p = curve.parameters.p
            let alias = BigInt(randomOnCurveY(on: curve)).add(p)
            // Longer than any compact key: the dictionary form has no length limit
            let tooLong = BigInt(1).mulTwoExp(UInt(8 * (p.byteSize() + 1)))
            for y in [BigInt(p), alias, tooLong] {
                let obvDic = yOnlyDictionary(y)
                XCTAssertNil(PublicKeyForPublicKeyEncryptionOnEdwardsCurve(obvDictionaryOfInternalElements: obvDic, curveByteId: curve.byteId), "\(c.name), y = \(y)")
                XCTAssertNil(PublicKeyForSignatureOnEdwardsCurve(obvDictionaryOfInternalElements: obvDic, curveByteId: curve.byteId), "\(c.name), y = \(y)")
                XCTAssertNil(PublicKeyForAuthenticationFromSignatureOnEdwardsCurve(obvDictionaryOfInternalElements: obvDic, curveByteId: curve.byteId), "\(c.name), y = \(y)")
            }
        }
    }


    /// The curve equation holds modulo p, so x + p or y + p would pass it.
    func testADictionaryWithACoordinateThatIsNotBelowPIsRefused() throws {
        for c in curvesUnderTest {
            let curve = c.curve
            let p = curve.parameters.p
            let point = try genuinePoint(on: c)
            for obvDic in [pointDictionary(x: BigInt(point.x).add(p), y: point.y),
                           pointDictionary(x: point.x, y: BigInt(point.y).add(p))] {
                XCTAssertNil(PublicKeyForPublicKeyEncryptionOnEdwardsCurve(obvDictionaryOfInternalElements: obvDic, curveByteId: curve.byteId), c.name)
                XCTAssertNil(PublicKeyForSignatureOnEdwardsCurve(obvDictionaryOfInternalElements: obvDic, curveByteId: curve.byteId), c.name)
                XCTAssertNil(PublicKeyForAuthenticationFromSignatureOnEdwardsCurve(obvDictionaryOfInternalElements: obvDic, curveByteId: curve.byteId), c.name)
            }
        }
    }


    /// A dictionary that has an x describes a point, and is refused when that point is not on the curve rather than read
    /// as a y alone.
    func testADictionaryWithAnXOffTheCurveIsRefused() throws {
        for c in curvesUnderTest {
            let curve = c.curve
            let point = try genuinePoint(on: c)
            let obvDic = pointDictionary(x: BigInt(point.x).add(BigInt(1), modulo: curve.parameters.p), y: point.y)
            XCTAssertNil(PublicKeyForPublicKeyEncryptionOnEdwardsCurve(obvDictionaryOfInternalElements: obvDic, curveByteId: curve.byteId), c.name)
            XCTAssertNil(PublicKeyForSignatureOnEdwardsCurve(obvDictionaryOfInternalElements: obvDic, curveByteId: curve.byteId), c.name)
            XCTAssertNil(PublicKeyForAuthenticationFromSignatureOnEdwardsCurve(obvDictionaryOfInternalElements: obvDic, curveByteId: curve.byteId), c.name)
        }
    }


    // MARK: - Keys that still decode

    func testGenuineKeysStillDecodeInEveryForm() throws {
        for c in curvesUnderTest {
            let curve = c.curve
            let (encryptionKey, _) = c.kem.generateKeyPair(with: prng)
            let (signatureKey, _) = c.signature.generateKeyPair(with: prng)

            let expandedEncryptionKey = try XCTUnwrap(CompactPublicKeyForPublicKeyEncryptionExpander.expand(compactKey: encryptionKey.getCompactKey()), c.name)
            XCTAssertTrue(expandedEncryptionKey.isEqualTo(other: encryptionKey), c.name)

            let decodedEncryptionKey = try XCTUnwrap(PublicKeyForPublicKeyEncryptionDecoder.obvDecode(encryptionKey.obvEncode()) as? PublicKeyForPublicKeyEncryptionOnEdwardsCurve, c.name)
            XCTAssertNotNil(decodedEncryptionKey.point, c.name)
            XCTAssertTrue(decodedEncryptionKey.isEqualTo(other: encryptionKey), c.name)

            let signaturePoint = try XCTUnwrap((signatureKey as? PublicKeyForSignatureOnEdwardsCurve)?.point, c.name)
            let decodedSignatureKey = try XCTUnwrap(PublicKeyForSignatureOnEdwardsCurve(obvDictionaryOfInternalElements: signaturePoint.getObvDictionaryOfCoordinates(), curveByteId: curve.byteId), c.name)
            XCTAssertNotNil(decodedSignatureKey.point, c.name)
            XCTAssertEqual(decodedSignatureKey.yCoordinate, signaturePoint.y, c.name)

            let yOnlySignatureKey = try XCTUnwrap(PublicKeyForSignatureOnEdwardsCurve(obvDictionaryOfInternalElements: yOnlyDictionary(signaturePoint.y), curveByteId: curve.byteId), c.name)
            XCTAssertNil(yOnlySignatureKey.point, c.name)
            XCTAssertEqual(yOnlySignatureKey.yCoordinate, signaturePoint.y, c.name)
        }
    }


    func testTheYCoordinatesWhereXIsZeroOrSquaresToOneStillDecode() throws {
        for c in curvesUnderTest {
            let p = c.curve.parameters.p
            for y in [BigInt(0), BigInt(1), BigInt(p).sub(1)] {
                XCTAssertNotNil(try encryptionKey(fromCompactY: y, on: c), "\(c.name), y = \(y)")
                XCTAssertNotNil(try authenticationKey(fromCompactY: y, on: c), "\(c.name), y = \(y)")
            }
        }
    }


    func testAKeyWhoseYIsOffTheCurveStillDecodes() throws {
        for c in curvesUnderTest {
            let curve = c.curve
            let y = try randomOffCurveY(on: curve)
            XCTAssertNotNil(try encryptionKey(fromCompactY: y, on: c), c.name)
            XCTAssertNotNil(try authenticationKey(fromCompactY: y, on: c), c.name)
            XCTAssertNotNil(PublicKeyForSignatureOnEdwardsCurve(obvDictionaryOfInternalElements: yOnlyDictionary(y), curveByteId: curve.byteId), c.name)
        }
    }


    // MARK: - Signatures

    /// `verify` finds no point for a y that is off the curve. It must return false rather than trap.
    func testVerifyReturnsFalseWithAKeyWhoseYIsOffTheCurve() throws {
        for c in curvesUnderTest {
            let curve = c.curve
            let message = prng.genBytes(count: 64)
            let (genuineKey, privateKey) = c.signature.generateKeyPair(with: prng)
            let signature = try XCTUnwrap(Signature.sign(message, with: privateKey, and: genuineKey, using: prng), c.name)
            let offCurveKey = try XCTUnwrap(PublicKeyForSignatureOnEdwardsCurve(yCoordinate: try randomOffCurveY(on: curve), curveByteId: curve.byteId), c.name)
            XCTAssertFalse(try Signature.verify(signature, on: message, with: offCurveKey), c.name)
        }
    }


    /// The y-only key goes through ``EdwardsCurve/mulAdd(a:point1:b:yCoordinateOfPoint2:)``, like an off-curve one.
    func testVerifyStillAcceptsAGenuineSignatureWithAKeyDecodedFromItsY() throws {
        for c in curvesUnderTest {
            let curve = c.curve
            let message = prng.genBytes(count: 64)
            let (genuineKey, privateKey) = c.signature.generateKeyPair(with: prng)
            let signature = try XCTUnwrap(Signature.sign(message, with: privateKey, and: genuineKey, using: prng), c.name)
            let y = try XCTUnwrap(genuineKey as? PublicKeyForSignatureOnEdwardsCurve, c.name).yCoordinate
            let yOnlyKey = try XCTUnwrap(PublicKeyForSignatureOnEdwardsCurve(yCoordinate: y, curveByteId: curve.byteId), c.name)
            XCTAssertNil(yOnlyKey.point, c.name)
            XCTAssertTrue(try Signature.verify(signature, on: message, with: yOnlyKey), c.name)
        }
    }


    // MARK: - KEM

    func testEncryptRefusesAKeyWhoseYIsOffTheCurve() throws {
        for c in curvesUnderTest {
            let offCurveKey = try XCTUnwrap(try encryptionKey(fromCompactY: try randomOffCurveY(on: c.curve), on: c), c.name)
            XCTAssertNil(c.kem.encrypt(using: offCurveKey, with: prng, makeKey), c.name)
        }
    }


    func testEncryptingToAKeyDecodedFromItsCompactFormStillWorks() throws {
        for c in curvesUnderTest {
            let (publicKey, privateKey) = c.kem.generateKeyPair(with: prng)
            let expandedKey = try XCTUnwrap(CompactPublicKeyForPublicKeyEncryptionExpander.expand(compactKey: publicKey.getCompactKey()), c.name)
            XCTAssertNil((expandedKey as? PublicKeyForPublicKeyEncryptionOnEdwardsCurve)?.point, c.name)
            let (ciphertext, key) = try XCTUnwrap(c.kem.encrypt(using: expandedKey, with: prng, makeKey), c.name)
            let decryptedKey = try XCTUnwrap(c.kem.decrypt(ciphertext, using: privateKey, makeKey), c.name)
            XCTAssertEqual(decryptedKey.data, key.data, c.name)
        }
    }


    func testDecryptRefusesACiphertextWhoseYIsOffTheCurve() throws {
        for c in curvesUnderTest {
            let (_, privateKey) = c.kem.generateKeyPair(with: prng)
            let pLength = c.curve.parameters.p.byteSize()
            for _ in 0..<10 {
                let y = try randomOffCurveY(on: c.curve)
                let ciphertext = EncryptedData(data: Data(try [UInt8](y, count: pLength)))
                XCTAssertNil(c.kem.decrypt(ciphertext, using: privateKey, makeKey), "\(c.name), y = \(y)")
            }
        }
    }


    /// The alias is made from an honest ciphertext, so that y mod p is the y of the point the sender chose. On MDC, few
    /// ciphertexts leave room for y + p in their bytes, so encryption is repeated until one does.
    func testDecryptRefusesAnHonestCiphertextWhoseYIsShiftedByP() throws {
        for c in curvesUnderTest {
            let p = c.curve.parameters.p
            let pLength = p.byteSize()
            let (publicKey, privateKey) = c.kem.generateKeyPair(with: prng)
            var alias: EncryptedData?
            for _ in 0..<500 {
                let (ciphertext, _) = try XCTUnwrap(c.kem.encrypt(using: publicKey, with: prng, makeKey), c.name)
                let shiftedY = BigInt(Data(encryptedData: ciphertext)).add(p)
                guard shiftedY <= largestEncodableY(on: c.curve) else { continue }
                XCTAssertNotNil(c.kem.decrypt(ciphertext, using: privateKey, makeKey), c.name)
                alias = EncryptedData(data: Data(try [UInt8](shiftedY, count: pLength)))
                break
            }
            let ciphertext = try XCTUnwrap(alias, "\(c.name): no ciphertext left room for y + p")
            XCTAssertNil(c.kem.decrypt(ciphertext, using: privateKey, makeKey), c.name)
        }
    }


    // MARK: - Helpers

    private struct CurveUnderTest {
        let name: String
        let kem: any KEM_ECIES256KEM512.Type
        let signature: any SignatureConcrete.Type
        let encryptionImplementationByteId: PublicKeyEncryptionImplementationByteId
        let authenticationImplementationByteId: AuthenticationImplementationByteId
        var curve: EdwardsCurve { kem.curve }
    }


    private let curvesUnderTest = [
        CurveUnderTest(name: "Curve25519",
                       kem: KEM_ECIES256KEM512_WithCurve25519.self,
                       signature: SignatureECSDSA256overCurve25519.self,
                       encryptionImplementationByteId: .KEM_ECIES_Curve25519_and_DEM_CTR_AES_256_then_HMAC_SHA_256,
                       authenticationImplementationByteId: .Signature_with_EC_SDSA_with_Curve25519),
        CurveUnderTest(name: "MDC",
                       kem: KEM_ECIES256KEM512_WithMDC.self,
                       signature: SignatureECSDSA256overMDC.self,
                       encryptionImplementationByteId: .KEM_ECIES_MDC_and_DEM_CTR_AES_256_then_HMAC_SHA_256,
                       authenticationImplementationByteId: .Signature_with_EC_SDSA_with_MDC),
    ]


    /// The largest y the bytes of a compact key or a ciphertext can hold.
    private func largestEncodableY(on curve: EdwardsCurve) -> BigInt {
        BigInt(1).mulTwoExp(UInt(8 * curve.parameters.p.byteSize())).sub(1)
    }


    private func encryptionKey(fromCompactY y: BigInt, on c: CurveUnderTest) throws -> PublicKeyForPublicKeyEncryption? {
        let compactKey = Data([c.encryptionImplementationByteId.rawValue]) + Data(try [UInt8](y, count: c.curve.parameters.p.byteSize()))
        return CompactPublicKeyForPublicKeyEncryptionExpander.expand(compactKey: compactKey)
    }


    private func authenticationKey(fromCompactY y: BigInt, on c: CurveUnderTest) throws -> PublicKeyForAuthentication? {
        let compactKey = Data([c.authenticationImplementationByteId.rawValue]) + Data(try [UInt8](y, count: c.curve.parameters.p.byteSize()))
        return CompactPublicKeyForAuthenticationExpander.expand(compactKey: compactKey)
    }


    /// The same compact key with y + p in place of y.
    private func compactKeyWithAliasedY(_ compactKey: Data, on curve: EdwardsCurve, pLength: Int) throws -> Data {
        let y = BigInt(compactKey.dropFirst())
        let alias = BigInt(y).add(curve.parameters.p)
        return Data([compactKey.first!]) + Data(try [UInt8](alias, count: pLength))
    }


    private func yOnlyDictionary(_ y: BigInt) -> ObvDictionary {
        [PointOnCurve.ObvDictionaryKey.forYCoordinate.data: y.obvEncode()]
    }


    private func pointDictionary(x: BigInt, y: BigInt) -> ObvDictionary {
        [PointOnCurve.ObvDictionaryKey.forXCoordinate.data: x.obvEncode(),
         PointOnCurve.ObvDictionaryKey.forYCoordinate.data: y.obvEncode()]
    }


    private func genuinePoint(on c: CurveUnderTest) throws -> PointOnCurve {
        let (publicKey, _) = c.kem.generateKeyPair(with: prng)
        return try XCTUnwrap((publicKey as? PublicKeyForPublicKeyEncryptionOnEdwardsCurve)?.point, c.name)
    }


    /// A y-coordinate of a point on the curve. When `withAnAliasThatFits` is true, y + p also fits in the bytes of a compact
    /// key, which on MDC holds for about one y in sixteen.
    private func randomOnCurveY(on curve: EdwardsCurve, withAnAliasThatFits: Bool = false) -> BigInt {
        let upperBound = withAnAliasThatFits ? BigInt(largestEncodableY(on: curve)).sub(curve.parameters.p).add(1) : BigInt(curve.parameters.p)
        while true {
            let y = prng.genBigInt(smallerThan: upperBound)
            if curve.pointsOnCurve(forYcoordinate: y) != nil { return y }
        }
    }


    /// A canonical y that belongs to no point on the curve, as found by the square root, which also finds none for y = ±1.
    ///
    /// No such y has low order on the twist: the twist's points of order 1 and 2 have y = 1 and y = p - 1, which are on
    /// the curve, and its points of order 4 have no finite y. So the check on ν·y never skips a y; it stands before the
    /// debug assertion `verify` makes on a low-order key.
    private func randomOffCurveY(on curve: EdwardsCurve) throws -> BigInt {
        while true {
            let y = prng.genBigInt(smallerThan: curve.parameters.p)
            guard curve.pointsOnCurve(forYcoordinate: y) == nil, y != BigInt(1), y != BigInt(curve.parameters.p).sub(1) else { continue }
            let nuTimesY = try XCTUnwrap(curve.scalarMultiplication(scalar: curve.parameters.nu, yCoordinate: y))
            guard nuTimesY != BigInt(1) else { continue }
            return y
        }
    }


    private func makeKey(_ bytes: Data) -> AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key {
        AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256Key(data: bytes)!
    }

}
