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

public struct TrustLevel {
    
    public let major: Int
    public let minor: Int
    
}


extension TrustLevel: RawRepresentable {
    
    public var rawValue: String {
        return ["\(major)", "\(minor)"].joined(separator: ".")
    }
    
    
    public init?(rawValue: String) {
        let strings = rawValue.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
        guard strings.count == 2 else { return nil }
        guard let major = Int(strings[0]) else { return nil }
        guard let minor = Int(strings[1]) else { return nil }
        self.init(major: major, minor: minor)
    }
    
}


public extension TrustLevel {
    
    static func forDirect() -> TrustLevel {
        return TrustLevel(major: 4, minor: 0)
    }
    
    static func forGroupOrIntroduction(withMinor minor: Int) -> TrustLevel {
        return TrustLevel(major: 2, minor: minor)
    }
    
    static func forServer() -> TrustLevel {
        return TrustLevel(major: 3, minor: 0)
    }

    static var zero: TrustLevel {
        return TrustLevel(major: 0, minor: 0)
    }
    
}


extension TrustLevel: Comparable {
    
    public static func < (lhs: TrustLevel, rhs: TrustLevel) -> Bool {
        if lhs.major < rhs.major { return true }
        if lhs.major > rhs.major { return false }
        if lhs.minor < rhs.minor { return true }
        if lhs.minor > rhs.minor { return false }
        return false
    }

}
