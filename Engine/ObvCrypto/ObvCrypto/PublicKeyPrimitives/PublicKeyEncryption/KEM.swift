/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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


protocol ConcreteKEMAlgorithm {
    static func encrypt<T: SymmetricKey>(using: PublicKeyForPublicKeyEncryption, with: PRNGService?, _ convertBytesToKey: (Data) -> T) -> (EncryptedData, T)?
    static func decrypt<T: SymmetricKey>(_: EncryptedData, using: PrivateKeyForPublicKeyEncryption, _ convertBytesToKey: (Data) -> T) -> T?
    static func generateKeyPair(with: PRNGService?) -> (PublicKeyForPublicKeyEncryption, PrivateKeyForPublicKeyEncryption)
}


protocol KEM_ECIES256KEM512: ConcreteKEMAlgorithm {
    static var curve: EdwardsCurve { get }
}


extension KEM_ECIES256KEM512 {
    
    static var length: Int {
        return curve.parameters.p.byteSize()
    }
    
    static func generateKeyPair(with _prng: PRNGService?) -> (PublicKeyForPublicKeyEncryption, PrivateKeyForPublicKeyEncryption) {
        let prng = _prng ?? ObvCryptoSuite.sharedInstance.prngService()
        let (scalar, point) = curve.generateRandomScalarAndPoint(withPRNG: prng)
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
    
    static func encrypt<T: SymmetricKey>(using _publicKey: PublicKeyForPublicKeyEncryption, with _prng: PRNGService?, _ convertBytesToKey: (Data) -> T) -> (EncryptedData, T)? {
        guard let publicKey = _publicKey as? PublicKeyForPublicKeyEncryptionOnEdwardsCurve,
            publicKey.curveByteId == curve.byteId
            else { return nil }
        let prng = _prng ?? ObvCryptoSuite.sharedInstance.prngService()
        let r = BigInt(0)
        while r == BigInt(0) {
            r.set(prng.genBigInt(smallerThan: curve.parameters.q))
        }
        let B = curve.scalarMultiplication(scalar: r, point: curve.parameters.G)!
        let Dy: BigInt
        if publicKey.point != nil {
            let D = curve.scalarMultiplication(scalar: r, point: publicKey.point!)!
            Dy = D.y
        } else {
            Dy = curve.scalarMultiplication(scalar: r, yCoordinate: publicKey.yCoordinate)!
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
        let q = curve.parameters.q
        let ciphertextAsData = Data(encryptedData: ciphertext)
        let yCoordinate = BigInt(ciphertextAsData)
        guard yCoordinate != BigInt(1) else { return nil }
        guard let By = curve.scalarMultiplication(scalar: nu, yCoordinate: yCoordinate) else { return nil }
        let a = BigInt(privateKey.scalar).mul(try! BigInt(nu).invert(modulo: q), modulo: q)
        let Dy = curve.scalarMultiplication(scalar: a, yCoordinate: By)!
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
