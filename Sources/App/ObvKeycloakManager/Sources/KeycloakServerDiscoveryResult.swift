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
import ObvJWS
import AppAuth
import ObvAppTypes

/// Aggregates the results of a Keycloak server discovery into a single value.
///
/// Produced by `discoverKeycloakServer(for:)` after:
/// 1. Fetching the OIDC service configuration (issuer discovery).
/// 2. Downloading and parsing the JWK set.
/// 3. Optionally fetching the Olvid-specific well-known document.
///
/// This struct is passed around instead of the previous `(ObvJWKSet, OIDServiceConfiguration)` tuple,
/// adding the well-known data needed to determine supported authentication methods.
public struct KeycloakServerDiscoveryResult {
    public let jwkSet: ObvJWKSet
    public let oidServiceConfiguration: OIDServiceConfiguration
    public let olvidWellKnown: OlvidWellKnownJson?
    
    public var supportsIdBasedAuth: Bool {
        olvidWellKnown?.supportsIdBasedAuth ?? false
    }
    
}
