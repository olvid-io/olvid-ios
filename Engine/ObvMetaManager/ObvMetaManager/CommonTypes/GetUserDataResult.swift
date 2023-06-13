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


/// This type is used for a specific type of response of a server query, namely for the `getUserData` and the `getKeycloakData` responses.
public enum GetUserDataResult: ObvCodable {
    
    case deletedFromServer
    case downloaded(userDataPath: String)
    
    private var rawValue: Int {
        switch self {
        case .deletedFromServer:
            return 0
        case .downloaded:
            return 1
        }
    }
    
    public func obvEncode() -> ObvEncoded {
        switch self {
        case .deletedFromServer:
            return [rawValue.obvEncode()].obvEncode()
        case .downloaded(let userDataPath):
            return [rawValue.obvEncode(), userDataPath.obvEncode()].obvEncode()
        }
    }
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let listOfEncoded = [ObvEncoded](obvEncoded) else { return nil }
        guard let encodedRawValue = listOfEncoded.first else { return nil }
        guard let rawValue = Int(encodedRawValue) else { return nil }
        switch rawValue {
        case 0:
            self = .deletedFromServer
        case 1:
            guard listOfEncoded.count == 2 else { assertionFailure(); return nil }
            guard let userDataPath = String(listOfEncoded[1]) else { return nil }
            self = .downloaded(userDataPath: userDataPath)
        default:
            assertionFailure()
            return nil
        }
    }

}
