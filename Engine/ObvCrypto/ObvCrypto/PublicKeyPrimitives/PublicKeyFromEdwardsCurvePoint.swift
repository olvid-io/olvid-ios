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
import ObvEncoder
import BigInt

protocol PublicKeyFromEdwardsCurvePoint: CryptographicKey, Equatable {
    
    var point: PointOnCurve? { get }
    var yCoordinate: BigInt { get }
    var curveByteId: EdwardsCurveByteId { get }
    var curve: EdwardsCurve { get }
    
    init?(point: PointOnCurve)
    init?(yCoordinate y: BigInt, curveByteId: EdwardsCurveByteId)
    init?(obvDictionaryOfInternalElements obvDic: ObvDictionary, curveByteId: EdwardsCurveByteId)
    
    /// Check whether a given point is an acceptable point for a public key
    static func isAcceptable(point: PointOnCurve) -> Bool
    
    /// Check whether a given y-coordinate is acceptable for a public key
    static func isAcceptable(yCoordinate: BigInt, onCurveWithByteId: EdwardsCurveByteId) -> Bool
}

extension PublicKeyFromEdwardsCurvePoint {
    
    var curve: EdwardsCurve {
        return curveByteId.curve
    }
    
    static func isAcceptable(point: PointOnCurve) -> Bool {
        let curve = point.onCurve
        guard point != curve.getPointAtInfinity() else { return false }
        guard point != curve.getPointOfOrderTwo() else { return false }
        guard point != curve.getPointsOfOrderFour().0 else { return false }
        guard point != curve.getPointsOfOrderFour().1 else { return false }
        return true
    }
    
    static func isAcceptable(yCoordinate y: BigInt, onCurveWithByteId curveByteId: EdwardsCurveByteId) -> Bool {
        let curve: EdwardsCurve
        switch curveByteId {
        case .MDCByteId:
            curve = CurveMDC()
        case .Curve25519ByteId:
            curve = Curve25519()
        }
        guard y != curve.getPointAtInfinity().y else { return false }
        guard y != curve.getPointOfOrderTwo().y else { return false }
        guard y != curve.getPointsOfOrderFour().0.y else { return false }
        guard y != curve.getPointsOfOrderFour().1.y else { return false }
        return true
    }
    
    var correspondingObvEncodedByteId: ByteIdOfObvEncoded {
        return .publicKey
    }
}

// Implementing Equatable
extension PublicKeyFromEdwardsCurvePoint {
    static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.algorithmClass == rhs.algorithmClass else { return false }
        guard lhs.algorithmImplementationByteIdValue == rhs.algorithmImplementationByteIdValue else { return false }
        guard lhs.curveByteId == rhs.curveByteId else { return false }
        guard lhs.yCoordinate == rhs.yCoordinate else { return false }
        return true
    }
}

extension PublicKeyFromEdwardsCurvePoint {
    
    var obvDictionaryOfInternalElements: ObvDictionary {
        if self.point != nil {
            return self.point!.getObvDictionaryOfCoordinates()
        } else {
            return [PointOnCurve.ObvDictionaryKey.forYCoordinate.data: self.yCoordinate.encode()]
        }
    }
    
    init?(obvDictionaryOfInternalElements obvDic: ObvDictionary, curveByteId: EdwardsCurveByteId) {
        if let point = PointOnCurve.init(obvDic, onCurveWithByteId: curveByteId) {
            self.init(point: point)
        } else {
            guard let encodedYCoordinate = obvDic[PointOnCurve.ObvDictionaryKey.forYCoordinate.data] else { return nil }
            guard let yCoordinate = BigInt.init(encodedYCoordinate) else { return nil }
            self.init(yCoordinate: yCoordinate, curveByteId: curveByteId)
        }
    }

}

// Implementing part of CompactableCryptographicKey
extension PublicKeyFromEdwardsCurvePoint {

    func getCompactKey() -> Data {
        let pLength = self.curve.parameters.p.byteSize()
        var compactKey = Data([self.algorithmImplementationByteIdValue])
        compactKey.append(self.yCoordinate.encode(withInnerLength: pLength)!.innerData)
        return compactKey
    }
    
}
