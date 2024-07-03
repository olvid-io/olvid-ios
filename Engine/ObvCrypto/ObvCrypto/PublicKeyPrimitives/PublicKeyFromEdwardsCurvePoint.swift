/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
    //static func isAcceptable(point: PointOnCurve) -> Bool
    
    //static func isLowOrderPoint(_ point: PointOnCurve) -> Bool

    /// Check whether a given y-coordinate is acceptable for a public key
    //static func isAcceptable(yCoordinate: BigInt, onCurveWithByteId: EdwardsCurveByteId) -> Bool
    
    //static func isLowOrderPoint(yCoordinate: BigInt, onCurveWithByteId: EdwardsCurveByteId) -> Bool

}

extension PublicKeyFromEdwardsCurvePoint {
    
    var curve: EdwardsCurve {
        return curveByteId.curve
    }
    

    var isLowOrderPoint: Bool {
        if let point {
            return point.isLowOrderPoint
        }
        return curve.scalarMultiplication(scalar: curve.parameters.nu, yCoordinate: yCoordinate) == curve.getPointAtInfinity().y
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
            return [PointOnCurve.ObvDictionaryKey.forYCoordinate.data: self.yCoordinate.obvEncode()]
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
