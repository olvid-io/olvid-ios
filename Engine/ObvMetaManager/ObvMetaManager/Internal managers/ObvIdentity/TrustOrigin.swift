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
import ObvCrypto
import ObvEncoder
import ObvTypes

public enum TrustOrigin {
    case direct(timestamp: Date)
    case group(timestamp: Date, groupOwner: ObvCryptoIdentity)
    case introduction(timestamp: Date, mediator: ObvCryptoIdentity)
    case keycloak(timestamp: Date, keycloakServer: URL)
    case serverGroupV2(timestamp: Date, groupIdentifier: ObvGroupV2.Identifier)
    
    public func addsTrustWhenAddedToAll(otherTrustOrigins: [TrustOrigin]) -> Bool {
        if otherTrustOrigins.isEmpty {
            return true
        }
        return otherTrustOrigins.allSatisfy { otherTrustOrigin in
            self.addsTrustComparedTo(otherTrustOrigin: otherTrustOrigin)
        }
    }
    
    
    private func addsTrustComparedTo(otherTrustOrigin: TrustOrigin) -> Bool {
        
        switch self {
        case .direct:
            // We consider that a .direct TrustOrigin always adds information
            return true
        case .group(timestamp: _, groupOwner: let groupOwner):
            switch otherTrustOrigin {
            case .group(timestamp: _, groupOwner: let otherGroupOwner):
                return groupOwner != otherGroupOwner
            default:
                return true
            }
        case .introduction(timestamp: _, mediator: let mediator):
            switch otherTrustOrigin {
            case .introduction(timestamp: _, mediator: let otherMediator):
                return mediator != otherMediator
            default:
                return true
            }
        case .keycloak(timestamp: _, keycloakServer: let keycloakServer):
            switch otherTrustOrigin {
            case .keycloak(timestamp: _, keycloakServer: let otherKeycloakServer):
                return keycloakServer != otherKeycloakServer
            default:
                return true
            }
        case .serverGroupV2(timestamp: _, groupIdentifier: let groupIdentifier):
            switch otherTrustOrigin {
            case .serverGroupV2(timestamp: _, groupIdentifier: let otherGroupIdentifier):
                return groupIdentifier != otherGroupIdentifier
            default:
                return true
            }
        }

    }
    
    
}
