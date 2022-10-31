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

protocol ConcreteProtocolState: ObvFailableCodable, CustomStringConvertible {
    
    var rawId: Int { get }
    
}

extension ConcreteProtocolState {
    public var description: String {
        return "ConcreteProtocolState<\(rawId)>"
    }
}

protocol TypeConcreteProtocolState: ConcreteProtocolState {
    
    var id: ConcreteProtocolStateId { get }
    
    init(_: ObvEncoded) throws
}

extension TypeConcreteProtocolState {
    
    var rawId: Int {
        return id.rawValue
    }
    
    init?(_ obvEncoded: ObvEncoded) {
        do {
            try self.init(obvEncoded)
        } catch {
            return nil
        }
    }
    
    static func makeError(message: String) -> Error {
        NSError(domain: String(describing: Self.self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }

}

protocol ConcreteProtocolStateId: ObvCodable {
    
    var rawValue: Int { get }
    
    var concreteProtocolStateType: ConcreteProtocolState.Type { get }
    func getConcreteProtocolState(fromEncodedState: ObvEncoded) -> ConcreteProtocolState?
    
    init?(rawValue: Int)
}

extension ConcreteProtocolStateId {
    
    func obvEncode() -> ObvEncoded {
        return self.rawValue.obvEncode()
    }
    
    init?(_ encoded: ObvEncoded) {
        guard let rawValue = Int(encoded) else { return nil }
        guard let stateId = Self(rawValue: rawValue) else { return nil }
        self = stateId
    }
    
    func getConcreteProtocolState(fromEncodedState encodedState: ObvEncoded) -> ConcreteProtocolState? {
        return concreteProtocolStateType.init(encodedState)
    }

}
