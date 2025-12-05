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
import CoreData
import OlvidUtils


public enum ObvTrustOrigin: Hashable, Sendable {
    
    case direct(contactIdentifier: ObvContactIdentifier, timestamp: Date)
    case group(contactIdentifier: ObvContactIdentifier, timestamp: Date, groupOwner: ObvCryptoId)
    case introduction(contactIdentifier: ObvContactIdentifier, timestamp: Date, mediator: ObvCryptoId)
    case keycloak(contactIdentifier: ObvContactIdentifier, timestamp: Date, keycloakServer: URL)
    case serverGroupV2(contactIdentifier: ObvContactIdentifier, timestamp: Date, groupIdentifier: ObvGroupV2.Identifier)

    public var date: Date {
        switch self {
        case .direct(contactIdentifier: _, timestamp: let date): return date
        case .group(contactIdentifier: _, timestamp: let date, groupOwner: _): return date
        case .introduction(contactIdentifier: _, timestamp: let date, mediator: _): return date
        case .keycloak(contactIdentifier: _, timestamp: let date, keycloakServer: _): return date
        case .serverGroupV2(contactIdentifier: _, timestamp: let date, groupIdentifier: _): return date
        }
    }
    
    public var contactIdentifier: ObvContactIdentifier {
        switch self {
        case .direct(let contactIdentifier, _):
            return contactIdentifier
        case .group(let contactIdentifier, _, _):
            return contactIdentifier
        case .introduction(let contactIdentifier, _, _):
            return contactIdentifier
        case .keycloak(let contactIdentifier, _, _):
            return contactIdentifier
        case .serverGroupV2(let contactIdentifier, _, _):
            return contactIdentifier
        }
    }
    
}
