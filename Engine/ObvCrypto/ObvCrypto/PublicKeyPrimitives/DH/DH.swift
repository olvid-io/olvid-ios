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

// MARK: protocols

protocol DHCommon {
    static func computeSharedSeed(from: PublicKeyForDH, and: PrivateKeyForDH) -> Seed?
}

protocol DHConcrete: DHCommon {
    static var algorithmImplementationByteId: DHImplementationByteId { get }
    static func generateKeyPair(with: PRNGService?) -> (PublicKeyForDH, PrivateKeyForDH)
}

protocol DHGeneric: DHCommon {
    static func generateKeyPair(for: DHImplementationByteId, with: PRNGService) -> (PublicKeyForDH, PrivateKeyForDH)
}

// MARK: Classes

public final class DH: DHGeneric {
    
    static func generateKeyPair(for implemByteId: DHImplementationByteId, with prng: PRNGService) -> (PublicKeyForDH, PrivateKeyForDH) {
        return implemByteId.algorithmImplementation.generateKeyPair(with: prng)
    }
    
    static func computeSharedSeed(from publicKey: PublicKeyForDH, and privateKey: PrivateKeyForDH) -> Seed? {
        return publicKey.algorithmImplementationByteId.algorithmImplementation.computeSharedSeed(from: publicKey, and: privateKey)
    }
}

protocol DH_over_EdwardsCurve: DHConcrete {
    static var curve: EdwardsCurve { get }
}

extension DH_over_EdwardsCurve {
    
    static func generateKeyPair(with _prng: PRNGService?) -> (PublicKeyForDH, PrivateKeyForDH) {
        let prng = _prng ?? ObvCryptoSuite.sharedInstance.prngService()
        let (scalar, point) = curve.generateRandomScalarAndPoint(withPRNG: prng)
        let publicKey = PublicKeyForDHOnEdwardsCurve(point: point)!
        let privateKey = PrivateKeyForDHOnEdwardsCurve(scalar: scalar, curveByteId: curve.byteId)
        return (publicKey, privateKey)
    }

    
    static func computeSharedSeed(from _publicKey: PublicKeyForDH, and _privateKey: PrivateKeyForDH) -> Seed? {
        guard let publicKey = _publicKey as? PublicKeyForDHOnEdwardsCurve else { return nil }
        guard let privateKey = _privateKey as? PrivateKeyForDHOnEdwardsCurve else { return nil }
        guard publicKey.curveByteId == privateKey.curveByteId else { return nil }
        let curve = publicKey.curve
        // Compute the seed as a big integer
        let bigIntSeed: BigInt?
        if let point = publicKey.point {
            bigIntSeed = curve.scalarMultiplication(scalar: privateKey.scalar, point: point)?.y
        } else {
            bigIntSeed = curve.scalarMultiplication(scalar: privateKey.scalar, yCoordinate: publicKey.yCoordinate)
        }
        // Transform the big integer into a proper data seed
        let seedLength = curve.parameters.p.byteSize()
        guard let rawSeed = bigIntSeed?.encode(withInnerLength: seedLength)?.innerData else { return nil }
        guard let seed = Seed(with: rawSeed) else { return nil }
        return seed
    }
    
}

final class DH_over_MDC: DH_over_EdwardsCurve {
    static let algorithmImplementationByteId = DHImplementationByteId.DH_on_MDC
    static let curve: EdwardsCurve = CurveMDC()
}

final class DH_over_Curve25519: DH_over_EdwardsCurve {
    static let algorithmImplementationByteId = DHImplementationByteId.DH_on_Curve25519
    static let curve: EdwardsCurve = Curve25519()
}
