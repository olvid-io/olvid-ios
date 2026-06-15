/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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

/// Marker protocol for Keycloak authentication method descriptors.
protocol ObvKeycloakAuthType {}

/// Represents authentication via an Olvid cryptographic identity (ID-based auth).
/// When supported by the server, this allows silent re-authentication with no user interaction.
public struct ObvKeycloakAuthIdBased: ObvKeycloakAuthType {
    public init() {}
}

/// Represents authentication via OpenID Connect (OIDC).
public struct ObvKeycloakAuthOIDC: ObvKeycloakAuthType {
    public let clientId: String
    public let clientSecret: String?
    public init(clientId: String, clientSecret: String?) {
        self.clientId = clientId
        self.clientSecret = clientSecret
    }
}

/// The set of authentication methods supported by a Keycloak server for a given owned identity.
/// `openIdConnect` is always present; `idBased` is non-nil only when the server advertises
/// support via its `.well-known/olvid` endpoint (`supportIdentityAuthentication: true`).
public struct SupportedAuthenticationMethods {
    public let openIdConnect: ObvKeycloakAuthOIDC
    public let idBased: ObvKeycloakAuthIdBased?
    public init(openIdConnect: ObvKeycloakAuthOIDC, idBased: ObvKeycloakAuthIdBased?) {
        self.openIdConnect = openIdConnect
        self.idBased = idBased
    }
}
