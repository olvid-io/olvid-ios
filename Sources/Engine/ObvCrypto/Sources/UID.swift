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
import Darwin
import CoreFoundation
import ObvEncoder


/// UID represents a 32 bytes unique identifier. Although it is a class, it just as immutable as a struct. Using a class is more convenient since this make it easier to interface with Core Data by means of a ValueTransformer
public final class UID: NSObject, NSCopying, Comparable, @unchecked Sendable {
    
    public static let length = 32
    
    public let raw: Data
    
    var debugUid: [UInt8] {
        return [UInt8](raw)
    }
    
    public init?(uid: Data) {
        guard uid.count == UID.length else { return nil }
        self.raw = uid
    }
    
    public convenience init?(hexString: String) {
        guard hexString.count == UID.length * 2 else { return nil }
        guard let uidAsData = Data(hexString: hexString) else { return nil }
        self.init(uid: uidAsData)
    }
    
    public func hexString() -> String {
        return raw.map { String.init(format: "%02hhx", $0) }.joined()
    }

    public static var zero: UID {
        let raw = Data(repeating: 0x00, count: length)
        return UID(uid: raw)!
    }
    
}

// Deterministic UUID from an UID. Should *NOT* be used for long term storage as this implementation might change anytime

extension UID {
    
    public var deterministicUUID: UUID {
        let bytes = [UInt8](raw)
        return .init(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7], bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    
}

// Implementing Comparable
extension UID {
    
    public static func < (lhs: UID, rhs: UID) -> Bool {
        for (lhsByte, rhsByte) in zip(lhs.raw, rhs.raw) {
            if lhsByte < rhsByte {
                return true
            } else if lhsByte > rhsByte {
                return false
            }
        }
        return false
    }
}

// Implementing Equatable
extension UID {
    public static func == (lhs: UID, rhs: UID) -> Bool {
        return [UInt8](lhs.raw) == [UInt8](rhs.raw)
    }
    public static func != (lhs: UID, rhs: UID) -> Bool {
        return [UInt8](lhs.raw) != [UInt8](rhs.raw)
    }
    public override func isEqual(_ object: Any?) -> Bool {
        if let o = object as? UID {
            return self == o
        } else {
            return false
        }
    }
}


// Implementing Hashable
extension UID {
    // Since we subclass NSObject, we cannot override hash(into:inout Hasher). Instead, we must override the `hash` property. See https://developer.apple.com/documentation/xcode_release_notes/xcode_10_release_notes/swift_4_2_release_notes_for_xcode_10
    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(self.raw)
        return hasher.finalize()
    }
}


// Implementing NSCopying (this solves a bug we encoutered while using UIDs with Core Data)
extension UID {
    public func copy(with zone: NSZone? = nil) -> Any {
        return UID(uid: self.raw) as Any
    }
}

// Implementing CustomDebugStringConvertible
extension UID {
    override public var debugDescription: String {
        let uidAsData = self.raw
        let rangeLength = min(8, uidAsData.count)
        let range = uidAsData.endIndex-rangeLength..<uidAsData.endIndex
        let description = uidAsData[range].map { String.init(format: "%02hhx", $0) }.joined()
        return description
    }
}

// Implementing a ValueTransformer for UID

public class UIDTransformer: ValueTransformer {
    
    override public class func transformedValueClass() -> AnyClass {
        return UID.self
    }
    
    override public class func allowsReverseTransformation() -> Bool {
        return true
    }

    
    /// Turn an UID into a Data object. This method never fails.
    override public func transformedValue(_ value: Any?) -> Any? {
        let uid = value as! UID
        return uid.raw
    }
    
    /// Try to turn a Data object back into a UID. This method can return nil.
    override public func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return UID(uid: data)
    }
    
}

public extension NSValueTransformerName {
    static let uidTransformerName = NSValueTransformerName(rawValue: "UIDTransformer")
}


extension UID: Codable {
    
    // Synthezised implementation
    
}

// ObvCodable

extension UID: ObvCodable {
    
    public convenience init?(_ obvEncoded: ObvEncoded) {
        guard let data = Data(obvEncoded) else { return nil }
        self.init(uid: data)
    }
    
    public func obvEncode() -> ObvEncoded {
        return ObvEncoded(byteId: .bytes, innerData: self.raw)
    }
}
