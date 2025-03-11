/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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


/// When performing an owned identity transfer protocol, the transfer server communicates a session number made of (up to) 8 digits.
/// We use this type to encapsulate the returned value.
public struct ObvOwnedIdentityTransferSessionNumber: CustomDebugStringConvertible, ObvCodable, Equatable, Hashable {
    
    public static let expectedCount = 8
    public let digits: [Character]
    public let sessionNumber: Int
    
    private static let digitFromInt = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map { Character("\($0)") }
    
    public init(sessionNumber: Int) throws {
        self.sessionNumber = sessionNumber
        guard sessionNumber >= 0 else { assertionFailure(); throw ObvError.invalidIntegerSessionNumber }
        var digits = [Character]()
        var currentValue = sessionNumber
        while currentValue > 0 {
            let digit = Self.digitFromInt[currentValue % 10]
            currentValue = currentValue / 10
            digits.insert(digit, at: 0)
        }
        guard digits.count <= Self.expectedCount else { assertionFailure(); throw ObvError.invalidIntegerSessionNumber }
        while digits.count < Self.expectedCount {
            digits.insert("0", at: 0)
        }
        self.digits = digits
    }
    
    enum ObvError: Error {
        case invalidIntegerSessionNumber
    }
    
    public var debugDescription: String {
        return digits.reduce("") { $0 + String($1) }
    }

    // ObvCodable
    
    public func obvEncode() -> ObvEncoder.ObvEncoded {
        sessionNumber.obvEncode()
    }

    
    public init?(_ obvEncoded: ObvEncoder.ObvEncoded) {
        guard let sessionNumber: Int = try? obvEncoded.obvDecode() else { return nil }
        try? self.init(sessionNumber: sessionNumber)
    }
    
}
