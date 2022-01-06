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
import JWS

public struct ObvKeycloakState {
    
    public let keycloakServer: URL
    public let clientId: String
    public let clientSecret: String?
    public let jwks: ObvJWKSet
    public let rawAuthState: Data?
    public let signatureVerificationKey: ObvJWK?
    public let latestLocalRevocationListTimestamp: Date? // Server timestamp, only set at the engine level when informing the app of latest known (locally stored) revocation list timestamp

    public init(keycloakServer: URL, clientId: String, clientSecret: String?, jwks: ObvJWKSet, rawAuthState: Data?, signatureVerificationKey: ObvJWK?, latestLocalRevocationListTimestamp: Date?) {
        self.keycloakServer = keycloakServer
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.jwks = jwks
        self.rawAuthState = rawAuthState
        self.signatureVerificationKey = signatureVerificationKey
        self.latestLocalRevocationListTimestamp = latestLocalRevocationListTimestamp
    }

}
