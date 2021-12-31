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
import ObvEncoder

// MARK: Protocols

protocol SignatureCommon {
    static func sign(_: Data, with: PrivateKeyForSignature, and: PublicKeyForSignature, using: PRNGService) -> Data?
    static func verify(_: Data, on: Data, with: PublicKeyForSignature) -> Bool?
}

protocol SignatureConcrete: SignatureCommon {
    static var algorithmImplementationByteId: SignatureImplementationByteId { get }
    static func generateKeyPair(with: PRNGService) -> (PublicKeyForSignature, PrivateKeyForSignature)
}

protocol SignatureGeneric: SignatureCommon {
    static func generateKeyPair(for: SignatureImplementationByteId, with: PRNGService) -> (PublicKeyForSignature, PrivateKeyForSignature)
}

// MARK: Classes

public final class Signature: SignatureGeneric {
    
    static func generateKeyPair(for implemByteId: SignatureImplementationByteId, with prng: PRNGService) -> (PublicKeyForSignature, PrivateKeyForSignature) {
        return implemByteId.algorithmImplementation.generateKeyPair(with: prng)
    }
    
    static func sign(_ data: Data, with privateKey: PrivateKeyForSignature, and publicKey: PublicKeyForSignature, using prng: PRNGService) -> Data? {
        let algorithmImplementation = privateKey.algorithmImplementationByteId.algorithmImplementation
        return algorithmImplementation.sign(data, with: privateKey, and: publicKey, using: prng)
    }
    
    static func verify(_ signature: Data, on data: Data, with publicKey: PublicKeyForSignature) -> Bool? {
        let algorithmImplementation = publicKey.algorithmImplementationByteId.algorithmImplementation
        return algorithmImplementation.verify(signature, on: data, with: publicKey)
    }
}

protocol SignatureECSDSA256overEdwardsCurve: SignatureConcrete {
    static var curve: EdwardsCurve { get }
}

extension SignatureECSDSA256overEdwardsCurve {
    
    private static var hLength: Int {
        return SHA256.outputLength
    }
    private static var zLength: Int {
        return curve.parameters.p.byteSize()
    }
    
    static func generateKeyPair(with prng: PRNGService) -> (PublicKeyForSignature, PrivateKeyForSignature) {
        let (scalar, point) = curve.generateRandomScalarAndPoint(withPRNG: prng)
        let publicKey = PublicKeyForSignatureOnEdwardsCurve(point: point)!
        let privateKey = PrivateKeyForSignatureOnEdwardsCurve(scalar: scalar, curveByteId: curve.byteId)
        return (publicKey, privateKey)
    }
    
    static func sign(_ message: Data, with _privateKey: PrivateKeyForSignature, and _publicKey: PublicKeyForSignature, using prng: PRNGService) -> Data? {
        guard let privateKey = _privateKey as? PrivateKeyForSignatureOnEdwardsCurve else { return nil }
        guard let publicKey = _publicKey as? PublicKeyForSignatureOnEdwardsCurve else { return nil }
        guard publicKey.curveByteId == privateKey.curveByteId else { return nil }
        guard publicKey.curveByteId == curve.byteId else { return nil }
        let algorithmImplementation = privateKey.algorithmImplementationByteId.algorithmImplementation
        let (localPublicKey, localPrivateKey) = algorithmImplementation.generateKeyPair(with: prng) as! (PublicKeyForSignatureOnEdwardsCurve, PrivateKeyForSignatureOnEdwardsCurve)
        // Construct the data to hash and sign
        let pLength = curve.parameters.p.byteSize()
        var dataToHash = localPublicKey.yCoordinate.encode(withInnerLength: pLength)!.innerData
        dataToHash.append(publicKey.yCoordinate.encode(withInnerLength: pLength)!.innerData)
        dataToHash.append(message)
        // Hash and cast as a big integer
        let h = SHA256.hash(dataToHash)
        let e = BigInt(ObvEncoded.init(byteId: .unsignedBigInt, innerData: h))!
        // Sign
        let q = BigInt(curve.parameters.q)
        let y = BigInt(localPrivateKey.scalar).sub(BigInt(privateKey.scalar).mul(e, modulo: q), modulo: q) /* y = (r - a*e) % q */
        let z = y.encode(withInnerLength: zLength)!.innerData
        var signature = h
        signature.append(z)
        return signature
    }
    
    static func verify(_ signature: Data, on message: Data, with _publicKey: PublicKeyForSignature) -> Bool? {
        guard let publicKey = _publicKey as? PublicKeyForSignatureOnEdwardsCurve else { return nil }
        guard publicKey.curveByteId == curve.byteId else { return nil }
        guard signature.count == self.hLength + self.zLength else { return false }
        let hRange = signature.startIndex..<signature.startIndex+self.hLength
        let h = signature[hRange]
        let zRange = signature.startIndex+self.hLength..<signature.endIndex
        let z = signature[zRange]
        guard z.count == self.zLength else { return nil }
        let e = BigInt(h)
        let y = BigInt(z)
        let resultingPoints: (point1: PointOnCurve, point2: PointOnCurve)
        if let point = publicKey.point {
            let resultingPoint = curve.mulAdd(a: y, point1: curve.parameters.G, b: e, point2: point)!
            resultingPoints = (resultingPoint, resultingPoint)
        } else {
            resultingPoints = curve.mulAdd(a: y, point1: curve.parameters.G, b: e, yCoordinateOfPoint2: publicKey.yCoordinate)!
        }
        let pLength = curve.parameters.p.byteSize()
        let Ay = publicKey.yCoordinate.encode(withInnerLength: pLength)!.innerData
        let Ay1 = resultingPoints.point1.y.encode(withInnerLength: pLength)!.innerData
        let Ay2 = resultingPoints.point2.y.encode(withInnerLength: pLength)!.innerData
        var dataToHash1 = Ay1
        dataToHash1.append(Ay)
        dataToHash1.append(message)
        var dataToHash2 = Ay2
        dataToHash2.append(Ay)
        dataToHash2.append(message)
        let h1 = SHA256.hash(dataToHash1)
        let h2 = SHA256.hash(dataToHash2)
        return h == h1 || h == h2
    }
    
}

final class SignatureECSDSA256overMDC: SignatureECSDSA256overEdwardsCurve {
    static let algorithmImplementationByteId = SignatureImplementationByteId.EC_SDSA_with_MDC
    static let curve: EdwardsCurve = CurveMDC()
}

final class SignatureECSDSA256overCurve25519: SignatureECSDSA256overEdwardsCurve {
    static let algorithmImplementationByteId = SignatureImplementationByteId.EC_SDSA_with_Curve25519
    static let curve: EdwardsCurve = Curve25519()
}
