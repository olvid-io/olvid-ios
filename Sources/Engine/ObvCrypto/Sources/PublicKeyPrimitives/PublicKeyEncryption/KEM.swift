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

import Foundation
import ObvBigInt


protocol ConcreteKEMAlgorithm {
    static func encrypt<T: SymmetricKey>(using: PublicKeyForPublicKeyEncryption, with prng: PRNG, _ convertBytesToKey: (Data) -> T) -> (EncryptedData, T)?
    static func decrypt<T: SymmetricKey>(_: EncryptedData, using: PrivateKeyForPublicKeyEncryption, _ convertBytesToKey: (Data) -> T) -> T?
    static func generateKeyPair(with prng: PRNG) -> (PublicKeyForPublicKeyEncryption, PrivateKeyForPublicKeyEncryption)
}


protocol KEM_ECIES256KEM512: ConcreteKEMAlgorithm {
    static var curve: EdwardsCurve { get }
}


extension KEM_ECIES256KEM512 {
    
    static var length: Int {
        return curve.parameters.p.byteSize()
    }
    
    static func generateKeyPair(with prng: PRNG) -> (PublicKeyForPublicKeyEncryption, PrivateKeyForPublicKeyEncryption) {
        let (scalar, point) = curve.generateRandomScalarAndHighOrderPoint(withPRNG: prng)
        let publicKey = PublicKeyForPublicKeyEncryptionOnEdwardsCurve(point: point)!
        let privateKey = PrivateKeyForPublicKeyEncryptionOnEdwardsCurve(scalar: scalar, curveByteId: curve.byteId)
        return (publicKey, privateKey)
    }

    static func generateKeyPairForBackupKey(with prng: PRNG) -> (PublicKeyForPublicKeyEncryption, PrivateKeyForPublicKeyEncryption) {
        let (scalar, point) = curve.generateRandomScalarAndPointForBackupKey(withPRNG: prng)
        let publicKey = PublicKeyForPublicKeyEncryptionOnEdwardsCurve(point: point)!
        let privateKey = PrivateKeyForPublicKeyEncryptionOnEdwardsCurve(scalar: scalar, curveByteId: curve.byteId)
        return (publicKey, privateKey)
    }
    
    static func encrypt<T: SymmetricKey>(using _publicKey: PublicKeyForPublicKeyEncryption, with prng: PRNG, _ convertBytesToKey: (Data) -> T) -> (EncryptedData, T)? {
        guard let publicKey = _publicKey as? PublicKeyForPublicKeyEncryptionOnEdwardsCurve,
            publicKey.curveByteId == curve.byteId
            else { return nil }
        // Check the public key
        guard curve.isCanonicalYCoordinateOfAPointOnCurve(publicKey.yCoordinate) else { return nil }
        guard !publicKey.isLowOrderPoint else { assertionFailure(); return nil }
        let r = BigInt(0)
        while r == BigInt(0) {
            r.set(prng.genBigInt(smallerThan: curve.parameters.q))
        }
        let B = curve.scalarMultiplication(scalar: r, point: curve.parameters.G)!
        let Dy: BigInt
        if let point = publicKey.point {
            guard let D = curve.scalarMultiplication(scalar: r, point: point) else { return nil }
            Dy = D.y
        } else {
            guard let y = curve.scalarMultiplication(scalar: r, yCoordinate: publicKey.yCoordinate) else { return nil }
            Dy = y
        }
        let c = try! Data(B.y, count: length)
        let ciphertext = EncryptedData(data: c)
        var rawSeed = c
        rawSeed.append(try! Data(Dy, count: length))
        guard let seed = Seed(with: rawSeed) else { return nil }
        guard let key = KDFFromPRNGWithHMACWithSHA256.generate(from: seed, convertBytesToKey) else { return nil }
        return (ciphertext, key)
    }

    static func decrypt<T: SymmetricKey>(_ ciphertext: EncryptedData, using _privateKey: PrivateKeyForPublicKeyEncryption, _ convertBytesToKey: (Data) -> T) -> T? {
        guard let privateKey = _privateKey as? PrivateKeyForPublicKeyEncryptionOnEdwardsCurve else { return nil }
        guard ciphertext.count == privateKey.curve.parameters.p.byteSize() else { return nil }
        let nu = curve.parameters.nu
        let nuInv = curve.parameters.nuInv
        let q = curve.parameters.q
        let ciphertextAsData = Data(encryptedData: ciphertext)
        let yCoordinate = BigInt(ciphertextAsData)
        // Unlike a decoded public key, a ciphertext is checked to be a point on the curve: the check costs nothing next to
        // the scalar multiplications, and keeps the computation off the twist
        guard curve.isCanonicalYCoordinateOfAPointOnCurve(yCoordinate) else { return nil }
        guard let By = curve.scalarMultiplication(scalar: nu, yCoordinate: yCoordinate) else { return nil }
        // B has low order exactly when ν·B is the neutral point, whose y-coordinate is 1
        guard By != BigInt(1) else { return nil }
        let a = BigInt(privateKey.scalar).mul(nuInv, modulo: q)
        guard let Dy = curve.scalarMultiplication(scalar: a, yCoordinate: By) else { return nil }
        var rawSeed = ciphertextAsData
        let pLength = curve.parameters.p.byteSize()
        rawSeed.append(try! Data(Dy, count: pLength))
        guard let seed = Seed(with: rawSeed) else { return nil }
        guard let key = KDFFromPRNGWithHMACWithSHA256.generate(from: seed, convertBytesToKey) else { return nil }
        return key
    }
}


class KEM_ECIES256KEM512_WithMDC: KEM_ECIES256KEM512 {
    static let curve: EdwardsCurve = CurveMDC()
}


class KEM_ECIES256KEM512_WithCurve25519: KEM_ECIES256KEM512 {
    static let curve: EdwardsCurve = Curve25519()
}
