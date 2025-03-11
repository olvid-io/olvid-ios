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
import ObvTypes


/// This type is used for a specific type of response of a server query, namely for the `ServerResponse.targetSendEphemeralIdentity` response.
public enum TargetSendEphemeralIdentityResult: ObvCodable {
    
    case requestSucceeded(otherConnectionId: String, payload: Data)
    case incorrectTransferSessionNumber
    case requestDidFail
    
    
    private var rawValue: Int {
        switch self {
        case .requestSucceeded:
            return 0
        case .incorrectTransferSessionNumber:
            return 1
        case .requestDidFail:
            return 2
        }
    }

    
    public func obvEncode() -> ObvEncoded {
        switch self {
        case .requestSucceeded(otherConnectionId: let otherConnectionId, payload: let payload):
            return [rawValue.obvEncode(), otherConnectionId.obvEncode(), payload.obvEncode()].obvEncode()
        case .incorrectTransferSessionNumber:
            return [rawValue.obvEncode()].obvEncode()
        case .requestDidFail:
            return [rawValue.obvEncode()].obvEncode()
        }
    }

    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let listOfEncoded = [ObvEncoded](obvEncoded) else { return nil }
        guard let encodedRawValue = listOfEncoded.first else { return nil }
        guard let rawValue = Int(encodedRawValue) else { return nil }
        switch rawValue {
        case 0:
            guard listOfEncoded.count == 3 else { assertionFailure(); return nil }
            guard let otherConnectionId = String(listOfEncoded[1]) else { return nil }
            guard let payload = Data(listOfEncoded[2]) else { return nil }
            self = .requestSucceeded(otherConnectionId: otherConnectionId, payload: payload)
        case 1:
            self = .incorrectTransferSessionNumber
        case 2:
            self = .requestDidFail
        default:
            assertionFailure()
            return nil
        }
    }

}
