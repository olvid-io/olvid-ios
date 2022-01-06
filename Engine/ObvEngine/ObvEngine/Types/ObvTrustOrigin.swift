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
import ObvMetaManager
import CoreData
import ObvTypes
import OlvidUtils


public enum ObvTrustOrigin: Hashable {
    
    case direct(timestamp: Date)
    case group(timestamp: Date, groupOwner: ObvContactIdentity?)
    case introduction(timestamp: Date, mediator: ObvContactIdentity?)
    case keycloak(timestamp: Date, keycloakServer: URL)

    public var date: Date {
        switch self {
        case .direct(timestamp: let date): return date
        case .group(timestamp: let date, groupOwner: _): return date
        case .introduction(timestamp: let date, mediator: _): return date
        case .keycloak(timestamp: let date, keycloakServer: _): return date
        }
    }
}

extension ObvTrustOrigin {

    static func getTrustOriginsOfContactIdentity(with contactCryptoId: ObvCryptoId, ofOwnedIdentyWith ownedCryptoId: ObvCryptoId, using identityDelegate: ObvIdentityDelegate, within obvContext: ObvContext) throws -> [ObvTrustOrigin] {
        
        let trustOrigins = try identityDelegate.getTrustOrigins(forContactIdentity: contactCryptoId.cryptoIdentity,
                                                                ofOwnedIdentity: ownedCryptoId.cryptoIdentity,
                                                                within: obvContext)
        let obvTrustOrigins = trustOrigins.map { (trustOrigin) -> ObvTrustOrigin in
            switch trustOrigin {
                
            case .direct(timestamp: let timestamp):
                return ObvTrustOrigin.direct(timestamp: timestamp)
                
            case .group(timestamp: let timestamp, groupOwner: let groupOwnerCryptoIdentity):
                let groupOwner = ObvContactIdentity(contactCryptoIdentity: groupOwnerCryptoIdentity,
                                                    ownedCryptoIdentity: ownedCryptoId.cryptoIdentity,
                                                    identityDelegate: identityDelegate,
                                                    within: obvContext)
                return ObvTrustOrigin.group(timestamp: timestamp, groupOwner: groupOwner)
                
            case .introduction(timestamp: let timestamp, mediator: let mediatorCryptoIdentity):
                let mediator = ObvContactIdentity(contactCryptoIdentity: mediatorCryptoIdentity,
                                                  ownedCryptoIdentity: ownedCryptoId.cryptoIdentity,
                                                  identityDelegate: identityDelegate,
                                                  within: obvContext)
                return ObvTrustOrigin.introduction(timestamp: timestamp, mediator: mediator)

            case .keycloak(timestamp: let timestamp, keycloakServer: let keycloakServer):
                return ObvTrustOrigin.keycloak(timestamp: timestamp, keycloakServer: keycloakServer)

            }
        }
        return obvTrustOrigins
    }

}
