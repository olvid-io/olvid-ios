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


public struct ObvOwnedIdentityTransferSas: CustomDebugStringConvertible, ObvCodable, Equatable {
    
    public let digits: [Character]
    private let rawFullSas: Data
    
    public init(fullSas: Data) throws {
        guard let sasAsString = String(data: fullSas, encoding: .utf8)?.trimmingWhitespacesAndNewlines() else {
            throw ObvError.couldNotParseSasAsString
        }
        assert(sasAsString.count == 8)
        self.digits = sasAsString.map { $0 }
        self.rawFullSas = fullSas
    }
    
    enum ObvError: Error {
        case couldNotParseSasAsString
    }
    
    public var debugDescription: String {
        return digits.reduce("") { $0 + String($1) }
    }
    
    // ObvCodable
    
    public func obvEncode() -> ObvEncoded {
        self.rawFullSas.obvEncode()
    }

    public init?(_ obvEncoded: ObvEncoded) {
        guard let fullSas = Data(obvEncoded) else { assertionFailure(); return nil }
        guard let sas = try? Self.init(fullSas: fullSas) else { assertionFailure(); return nil }
        self = sas
    }
    
}

