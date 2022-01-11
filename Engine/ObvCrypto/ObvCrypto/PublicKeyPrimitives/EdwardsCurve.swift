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
import ObvEncoder


struct EdwardsCurveParameters {
    let p: BigInt
    let d: BigInt
    let G: PointOnCurve
    let q: BigInt
    let nu: BigInt
    let cardinality: BigInt
}


public enum EdwardsCurveByteId: UInt8 {
    case MDCByteId = 0x00
    case Curve25519ByteId = 0x01
    
    var curve: EdwardsCurve {
        switch self {
        case .MDCByteId:
            return CurveMDC()
        case .Curve25519ByteId:
            return Curve25519()
        }
    }
}


protocol EdwardsCurve {
    
    var byteId: EdwardsCurveByteId { get }
    
    var parameters: EdwardsCurveParameters { get }
    
    func pointsOnCurve(forYcoordinate y: BigInt) -> (point1: PointOnCurve, point2: PointOnCurve)?
    
}


extension EdwardsCurve {
    
    func getPointAtInfinity() -> PointOnCurve {
        return PointOnCurve(x: 0, y: 1, onCurveWithByteId: self.byteId)!
    }
    
    func getPointOfOrderTwo() -> PointOnCurve {
        return PointOnCurve(x: BigInt(0), y: BigInt(-1).mod(self.parameters.p), onCurveWithByteId: self.byteId)!
    }

    func getPointsOfOrderFour() -> (PointOnCurve, PointOnCurve) {
        let point1 = PointOnCurve(x: 1, y: 0, onCurveWithByteId: self.byteId)!
        let point2 = PointOnCurve(x: BigInt(-1).mod(self.parameters.p), y: BigInt(0), onCurveWithByteId: self.byteId)!
        return (point1, point2)
    }

    /// Given a an Edwards curve, there are two points on the curve that match a given y-coordinate. This method returns these two points.
    ///
    /// - Parameter y: The y-coordinate of the points to return.
    /// - Returns: Two points on the curve having `y` as their y-coordinate.
    func pointsOnCurve(forYcoordinate y: BigInt) -> (point1: PointOnCurve, point2: PointOnCurve)? {
        let p = self.parameters.p
        // Compute y^2
        let ySquare = BigInt(y).powm(2, modulo: p)
        // Deduce x^2 = ((1-y^2) * invert(1-d*y2, p)) % p
        let xSquare = BigInt(ySquare).sub(1)
        guard let temp = try? BigInt(self.parameters.d).mul(ySquare, modulo: p).sub(1).invert(modulo: p) else { return nil }
        _ = xSquare.mul(temp, modulo: p)
        // Deduce both possible values of x (if there is any)
        let x1 = BigInt()
        let x2 = BigInt()
        do {
            try BigInt.sqrtm(rop1: x1, rop2: x2, op: xSquare, p: p)
        } catch {
            return nil
        }
        let point1 = PointOnCurve(x: x1, y: y, onCurveWithByteId: self.byteId, checkPointIsOnCurve: false)!
        let point2 = PointOnCurve(x: x2, y: y, onCurveWithByteId: self.byteId, checkPointIsOnCurve: false)!
        return (point1, point2)
    }
    

    func scalarMultiplication(scalar: BigInt, yCoordinate: BigInt) -> BigInt? {

        let res = BigInt()
        let p = self.parameters.p
        let y = BigInt(yCoordinate).mod(p)
        let n = BigInt(scalar).mod(self.parameters.cardinality)
        let zero = BigInt(0) // For comparison only
        let one = BigInt(1) // For comparison only
        let minusOne = BigInt(-1).mod(p) // For comparison only

        if n == zero || y == one {
            res.set(1)
        } else if y == minusOne {
            if n.isOdd() {
                res.set(-1)
            } else {
                res.set(1)
            }
        } else {
            let c = try! BigInt(1).sub(self.parameters.d).invert(modulo: p) /* c = 1/(1-d) mod p */
            
            let pointP = PointOnCurve(x: BigInt(1).add(y, modulo: p),
                                      y: BigInt(1).sub(y, modulo: p),
                                      onCurveWithByteId: self.byteId, checkPointIsOnCurve: false)!
            var pointQ = PointOnCurve(x: 1, y: 0, onCurveWithByteId: self.byteId, checkPointIsOnCurve: false)!
            var pointR = PointOnCurve(with: pointP)
            
            let bitCount = self.parameters.cardinality.size(inBase: .two)
            for i in 0..<bitCount {
                
                /* t1 = ((Q.x-Q.y)*(R.x+R.y))%p */
                let t1 = BigInt(pointQ.x).sub(pointQ.y, modulo: p)
                _ = t1.mul(BigInt(pointR.x).add(pointR.y, modulo: p), modulo: p)
                /* t2 = ((Q.x+Q.y)*(R.x-R.y))%p */
                let t2 = BigInt(pointQ.x).add(pointQ.y, modulo: p)
                _ = t2.mul(BigInt(pointR.x).sub(pointR.y, modulo: p), modulo: p)
                // (Q+R).x = P.y * (t1 + t2)^2 mod p
                // (Q+R).y = P.x * (t1 - t2)^2 mod p
                let resultOfAdding = PointOnCurve(x: BigInt(pointP.y).mul(BigInt(t1).add(t2, modulo: p).powm(2, modulo: p), modulo: p),
                                                  y: BigInt(pointP.x).mul(BigInt(t1).sub(t2, modulo: p).powm(2, modulo: p), modulo: p),
                                                  onCurveWithByteId: self.byteId,
                                                  checkPointIsOnCurve: false)!
                
                let pointerToPointToDouble = n.isBitSet(atPosition: UInt(bitCount-i-1)) ? pointR : pointQ
                /* t1 = (x+y)^2 mod p */
                t1.set(BigInt(pointerToPointToDouble.x).add(pointerToPointToDouble.y, modulo: p).powm(2, modulo: p))
                /* t2 = (x-y)^2 mod p */
                t2.set(BigInt(pointerToPointToDouble.x).sub(pointerToPointToDouble.y, modulo: p).powm(2, modulo: p))
                /* t3 = t1 - t2 mod p */
                let t3 = BigInt(t1).sub(t2, modulo: p)
                /* doubledPoint.x = t1 * t2 mod p */
                /* doubledPoint.y = t3 * (c*t3 + t2) mod p */
                let resultOfDoubling = PointOnCurve(x: BigInt(t1).mul(t2, modulo: p),
                                                    y: BigInt(t3).mul(BigInt(c).mul(t3, modulo: p).add(t2, modulo: p), modulo: p),
                                                    onCurveWithByteId: self.byteId,
                                                    checkPointIsOnCurve: false)!
                
                if n.isBitSet(atPosition: UInt(bitCount-i-1)) {
                    pointQ = resultOfAdding // No need to copy
                    pointR = resultOfDoubling // No need to copy
                } else {
                    pointQ = resultOfDoubling // No need to copy
                    pointR = resultOfAdding // No need to copy
                }
            }
            
            
            /* res = (Q.x-Q.y) / (Q.x+Q.y) mod p */
            let t1 = BigInt(pointQ.x).sub(pointQ.y, modulo: p)
            let t2 = BigInt(pointQ.x).add(pointQ.y, modulo: p)
            do {
                res.set(t1.mul(try t2.invert(modulo: p), modulo: p))
            } catch {
                return nil
            }
        }

        return res
    }
    
    
    public func scalarMultiplication(scalar: BigInt, point: PointOnCurve) -> PointOnCurve? {
        guard self.byteId == point.onCurveWithByteId else { return nil }
        var pointP: PointOnCurve
        let p = self.parameters.p
        let y = BigInt(point.y).mod(p)
        let n = BigInt(scalar).mod(self.parameters.cardinality)
        if n == BigInt(0) || y == BigInt(1) {
            pointP = PointOnCurve(x: 0, y: 1, onCurveWithByteId: self.byteId, checkPointIsOnCurve: false)!
        } else if y == BigInt(-1).mod(p) {
            if n.isOdd() {
                pointP = PointOnCurve(x: 0, y: -1, onCurveWithByteId: self.byteId, checkPointIsOnCurve: false)!
            } else {
                pointP = PointOnCurve(x: 0, y: 1, onCurveWithByteId: self.byteId, checkPointIsOnCurve: false)!
            }
        } else {
            var pointQ = PointOnCurve(with: point)
            pointP = PointOnCurve(x: 0, y: 1, onCurveWithByteId: self.byteId, checkPointIsOnCurve: false)!
            let bitCount = self.parameters.cardinality.size(inBase: .two)
            for i in 0..<bitCount {
                if n.isBitSet(atPosition: UInt(bitCount-i-1)) {
                    pointP = self.add(point: pointP, withPoint: pointQ)!
                    pointQ = self.add(point: pointQ, withPoint: pointQ)!
                } else {
                    pointQ = self.add(point: pointP, withPoint: pointQ)!
                    pointP = self.add(point: pointP, withPoint: pointP)!
                }
            }
        }
        return pointP
    }
    
    
    func add(point point1: PointOnCurve, withPoint point2: PointOnCurve) -> PointOnCurve? {
        guard point1.onCurveWithByteId == point2.onCurveWithByteId else { return nil }
        guard point1.onCurveWithByteId == self.byteId else { return nil }
        let p = self.parameters.p
        let pointR = PointOnCurve(x: 0, y: 0, onCurveWithByteId: self.byteId, checkPointIsOnCurve: false)!
        // Compute t = (d * x1 * x2 * y1 * y2) % p
        let t = BigInt(self.parameters.d).mul(point1.x, modulo: p).mul(point2.x, modulo: p).mul(point1.y, modulo: p).mul(point2.y, modulo: p)
        // Compute z = invert(1+t,p)
        let z: BigInt
        do {
            z = try BigInt(1).add(t).invert(modulo: p)
        } catch {
            return nil
        }
        // Compute R.x = (z * (x1*y2 + y1*x2))%p
        pointR.x.set(BigInt(point1.x).mul(point2.y, modulo: p))
        _ = pointR.x.add(BigInt(point1.y).mul(point2.x, modulo: p), modulo: p)
        _ = pointR.x.mul(z, modulo: p)
        // Compute z = invert(1-t,p)
        z.set(try! BigInt(1).sub(t).invert(modulo: p))
        // Compute R.y = (z * (y1*y2 - x1*x2))%p
        pointR.y.set(BigInt(point1.y).mul(point2.y, modulo: p))
        _ = pointR.y.sub(BigInt(point1.x).mul(point2.x, modulo: p))
        _ = pointR.y.mul(z, modulo: p)
        
        return pointR
    }
    
    /// This function computes a*point1 + b*point2.
    ///
    /// - Parameters:
    ///   - a: A scalar.
    ///   - point1: A point on the curve.
    ///   - b: A scalar.
    ///   - point2: A point on the curve.
    ///   - checkPointsAreOnCurve: If `true`, an exception is raised if one of the points is not on the curve.
    /// - Returns: A point on the curve, equal to a*point1 + b*point2
    func mulAdd(a: BigInt, point1: PointOnCurve, b: BigInt, point2: PointOnCurve) -> PointOnCurve? {
        guard point1.onCurveWithByteId == point2.onCurveWithByteId else { return nil }
        guard point1.onCurveWithByteId == self.byteId else { return nil }
        guard let point3 = self.scalarMultiplication(scalar: a, point: point1),
            let point4 = self.scalarMultiplication(scalar: b, point: point2) else {
                return nil
        }
        return self.add(point: point3, withPoint: point4)!
    }
    
    /// This function computes a*point1 + b*point2, where `point2` is not fully specified. As a consequence, two points are returned by this function.
    ///
    /// - Parameters:
    ///   - a: A scalar.
    ///   - point1: A point on the curve.
    ///   - b: A scalar.
    ///   - yCoordinateOfPoint2: The `y` coordinate of a point on the curve.
    ///   - checkPointsAreOnCurve: If `true`, an exception is raised if one of the points is not on the curve.
    /// - Returns: Two points on the curve
    func mulAdd(a: BigInt, point1: PointOnCurve, b: BigInt, yCoordinateOfPoint2: BigInt) -> (PointOnCurve, PointOnCurve)? {
        guard point1.onCurveWithByteId == self.byteId else { return nil }
        guard let point3 = self.scalarMultiplication(scalar: a, point: point1) else { return nil }
        let y = BigInt(yCoordinateOfPoint2).mod(self.parameters.p)
        guard let y4 = self.scalarMultiplication(scalar: b, yCoordinate: y) else { return nil }
        guard let (point4_1, point4_2) = self.pointsOnCurve(forYcoordinate: y4) else {
            return nil
        }
        guard let resultPoint1 = self.add(point: point3, withPoint: point4_1),
            let resultPoint2 = self.add(point: point3, withPoint: point4_2) else {
                return nil
        }
        return (resultPoint1, resultPoint2)
    }
    
    func generateRandomScalarAndPoint(withPRNG: PRNGService?) -> (BigInt, PointOnCurve) {
        let prng = withPRNG ?? ObvCryptoSuite.sharedInstance.prngService()
        let scalar = BigInt(0)
        while scalar == BigInt(0) || scalar == BigInt(1) {
            scalar.set(prng.genBigInt(smallerThan: self.parameters.q))
        }
        let point = self.scalarMultiplication(scalar: scalar, point: self.parameters.G)!
        return (scalar, point)
    }
    
    func generateRandomScalarAndPointForBackupKey(withPRNG prng: PRNG) -> (BigInt, PointOnCurve) {
        let scalar = BigInt(0)
        while scalar == BigInt(0) || scalar == BigInt(1) {
            scalar.set(prng.genBigInt(smallerThan: self.parameters.q))
        }
        let point = self.scalarMultiplication(scalar: scalar, point: self.parameters.G)!
        return (scalar, point)
    }

}


struct Curve25519: EdwardsCurve {
    
    var byteId: EdwardsCurveByteId {
        return .Curve25519ByteId
    }
    
    let parameters = EdwardsCurveParameters(p: try! BigInt("57896044618658097711785492504343953926634992332820282019728792003956564819949"),
                                            d: try! BigInt("20800338683988658368647408995589388737092878452977063003340006470870624536394"),
                                            G: PointOnCurve(x: try! BigInt("9771384041963202563870679428059935816164187996444183106833894008023910952347"),
                                                            y: try! BigInt("46316835694926478169428394003475163141307993866256225615783033603165251855960"),
                                                            onCurveWithByteId: EdwardsCurveByteId.Curve25519ByteId,
                                                            checkPointIsOnCurve: false)!,
                                            q: try! BigInt("7237005577332262213973186563042994240857116359379907606001950938285454250989"), // Order
                                            nu: BigInt(8),
                                            cardinality: try! BigInt("57896044618658097711785492504343953926856930875039260848015607506283634007912"))
    
}

struct CurveMDC: EdwardsCurve {
    
    var byteId: EdwardsCurveByteId {
        return .MDCByteId
    }
    
    let parameters = EdwardsCurveParameters(p: try! BigInt("109112363276961190442711090369149551676330307646118204517771511330536253156371"),
                                            d: try! BigInt("39384817741350628573161184301225915800358770588933756071948264625804612259721"),
                                            G: PointOnCurve(x: try! BigInt("82549803222202399340024462032964942512025856818700414254726364205096731424315"),
                                                            y: try! BigInt("91549545637415734422658288799119041756378259523097147807813396915125932811445"),
                                                            onCurveWithByteId: EdwardsCurveByteId.MDCByteId,
                                                            checkPointIsOnCurve: false)!,
                                            q: try! BigInt("27278090819240297610677772592287387918930509574048068887630978293185521973243"), // Order
                                            nu: BigInt(4),
                                            cardinality: try! BigInt("109112363276961190442711090369149551675722038296192275550523913172742087892972"))
    
}



final class PointOnCurve: Equatable, NSCopying, CustomDebugStringConvertible {
    
    let x: BigInt
    let y: BigInt
    let onCurveWithByteId: EdwardsCurveByteId
    
    var onCurve: EdwardsCurve {
        return onCurveWithByteId.curve
    }

    init?(x: BigInt, y: BigInt, onCurveWithByteId byteId: EdwardsCurveByteId, checkPointIsOnCurve: Bool = true) {
        if checkPointIsOnCurve {
            let curve = byteId.curve
            guard PointOnCurve.check((x, y), isOnCurve: curve) else { return nil }
        }
        self.x = x
        self.y = y
        self.onCurveWithByteId = byteId
    }
    
    convenience init?(x: Int, y: Int, onCurveWithByteId byteId: EdwardsCurveByteId, checkPointIsOnCurve check: Bool = true) {
        self.init(x: BigInt(x), y: BigInt(y), onCurveWithByteId: byteId, checkPointIsOnCurve: check)
    }
    
    
    init(with point: PointOnCurve) {
        self.x = BigInt(point.x)
        self.y = BigInt(point.y)
        self.onCurveWithByteId = point.onCurveWithByteId
    }
    
    private static func check(_ point: (BigInt, BigInt), isOnCurve curve: EdwardsCurve) -> Bool {
        let p = curve.parameters.p
        // Compute x^2 % p and y^2 % p
        let (x, y) = point
        let xSquare = BigInt(x).powm(2, modulo: p)
        let ySquare = BigInt(y).powm(2, modulo: p)
        // Compute lhs = (x2 + y2) % p
        let lhs = BigInt(xSquare).add(ySquare, modulo: p)
        // Compuse rhs = (1 + d*x2*y2) % p
        let rhs = BigInt(curve.parameters.d).mul(xSquare, modulo: p).mul(ySquare, modulo: p).add(BigInt(1), modulo: p)
        // The point is on the curve iff lhs == rhs
        return lhs == rhs
    }
    
    static func == (lhs: PointOnCurve, rhs: PointOnCurve) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y && lhs.onCurveWithByteId == rhs.onCurveWithByteId
    }
    
    func copy(with zone: NSZone? = nil) -> Any {
        return PointOnCurve(with: self)
    }
    
}

// Implementing CustomDebugStringConvertible
extension PointOnCurve {
    var debugDescription: String {
        let debugDesc = """
            Point on curve identified by \(self.onCurveWithByteId) with
                \tx = \(self.x)
                \ty = \(self.y)
        """
        return debugDesc
    }
}

// Convenience init useful when the point is represented by a curve and an ObvDict with 'x' and 'y' coordinates.
extension PointOnCurve {
    
    enum ObvDictionaryKey: UInt8 {
        case forXCoordinate = 0x78 // "x" in UTF8
        case forYCoordinate = 0x79 // "y" in UTF8
        case forScalar = 0x6e // "n" in UTF8
        
        var data: Data {
            return Data([self.rawValue])
        }        
    }
    
    private static func valueOf(_ coordinate: ObvDictionaryKey, in obvDic: ObvDictionary) -> BigInt? {
        let coordinateValue: BigInt?
        if let encodedCoordinate = obvDic[coordinate.data] {
            coordinateValue = BigInt(encodedCoordinate)
        } else {
            coordinateValue = nil
        }
        return coordinateValue
    }

    convenience init?(_ obvDic: ObvDictionary, onCurveWithByteId byteId: EdwardsCurveByteId) {
        guard let x = PointOnCurve.valueOf(.forXCoordinate, in: obvDic) else { return nil }
        guard let y = PointOnCurve.valueOf(.forYCoordinate, in: obvDic) else { return nil }
        self.init(x: x, y: y, onCurveWithByteId: byteId)
    }
    
    
    func getObvDictionaryOfCoordinates() -> ObvDictionary {
        return [ObvDictionaryKey.forXCoordinate.data: self.x.encode(),
                ObvDictionaryKey.forYCoordinate.data: self.y.encode()]
    }

}
