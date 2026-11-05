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

import XCTest
import ObvJWS
@testable import ObvTypes


/// Which keys verify what the keycloak server signs: the pinned key alone when there is one, the JWKS otherwise.
final class ObvKeycloakStateSignatureVerificationKeyTests: XCTestCase {

    // Public keys only. `ObvJWK` compares thumbprints, which ignore `kid`, so the three differ in their key material.
    private static let rawPinnedKey = #"{"kty":"EC","crv":"P-256","x":"MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4","y":"4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM","kid":"pinned"}"#
    private static let rawNewKey = #"{"kty":"EC","crv":"P-256","x":"f83OJ3D2xF1Bg8vub9tLe1gHMzV76e8Tus9uPHvRVEU","y":"x_FEzRu9m36HLN_tue659LNpXW6pCyStikYjKIWI5a0","kid":"new"}"#
    private static let rawRSAKey = #"{"kty":"RSA","n":"0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAtVT86zwu1RK7aPFFxuhDR1L6tSoc_BJECPebWKRXjBZCiFV4n3oknjhMstn64tZ_2W-5JsGY4Hc5n9yBXArwl93lqt7_RN5w6Cf0h4QyQ5v-65YGjQR0_FDW2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0zgdAZHzu6qMQvRL5hajrn1n91CbOpbISD08qNLyrdkt-bFTWhAI4vMQFh6WeZu0fM4lFd2NcRwr3XPksINHaQ-G_xBniIqbw0Ls1jF44-csFCur-kEgU8awapJzKnqDKgw","e":"AQAB","kid":"rsa"}"#

    private func key(_ raw: String) throws -> ObvJWK {
        try ObvJWK.jsonDecode(rawObvJWK: Data(raw.utf8))
    }

    private func jwks(_ raws: String...) throws -> ObvJWKSet {
        try ObvJWKSet(data: Data(#"{"keys":[\#(raws.joined(separator: ","))]}"#.utf8))
    }

    /// The keys of a set, in order. `ObvJWKSet` exposes nothing but its JSON, so they are read back from it.
    private func keys(of jwks: ObvJWKSet) throws -> [ObvJWK] {
        let jsonData = try XCTUnwrap(jwks.jsonData())
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        let rawKeys = try XCTUnwrap(json["keys"] as? [[String: Any]])
        return try rawKeys.map { try ObvJWK.jsonDecode(rawObvJWK: JSONSerialization.data(withJSONObject: $0)) }
    }

    private func keycloakState(jwks: ObvJWKSet, signatureVerificationKey: ObvJWK?) -> ObvKeycloakState {
        ObvKeycloakState(
            keycloakServer: URL(string: "https://keycloak.example.com/realms/olvid")!,
            supportedAuthenticationMethods: .init(openIdConnect: .init(clientId: "olvid", clientSecret: nil), idBased: nil),
            jwks: jwks,
            rawAuthState: nil,
            signatureVerificationKey: signatureVerificationKey,
            latestLocalRevocationListTimestamp: nil,
            latestGroupUpdateTimestamp: nil,
            isTransferRestricted: false)
    }


    func testTheTestKeysAreDistinct() throws {
        let keys = try [key(Self.rawPinnedKey), key(Self.rawNewKey), key(Self.rawRSAKey)]
        for i in keys.indices {
            for j in keys.indices where i != j {
                XCTAssertNotEqual(keys[i], keys[j])
            }
        }
    }


    /// The case the rule exists for: the server now publishes a key the user has not accepted.
    func testWithAPinnedKeyOnlyThatKeyVerifiesWhateverTheJWKSHolds() throws {
        let pinnedKey = try key(Self.rawPinnedKey)
        let state = keycloakState(jwks: try jwks(Self.rawNewKey, Self.rawRSAKey), signatureVerificationKey: pinnedKey)
        XCTAssertEqual(try keys(of: state.signatureVerificationKeyOrJWKS), [pinnedKey])
    }

    func testWithAPinnedKeyAlsoInTheJWKSTheOtherKeysOfTheJWKSAreLeftOut() throws {
        let pinnedKey = try key(Self.rawPinnedKey)
        let state = keycloakState(jwks: try jwks(Self.rawPinnedKey, Self.rawNewKey), signatureVerificationKey: pinnedKey)
        XCTAssertEqual(try keys(of: state.signatureVerificationKeyOrJWKS), [pinnedKey])
    }

    func testWithoutAPinnedKeyTheJWKSVerifies() throws {
        let state = keycloakState(jwks: try jwks(Self.rawNewKey, Self.rawRSAKey), signatureVerificationKey: nil)
        XCTAssertEqual(try keys(of: state.signatureVerificationKeyOrJWKS), [try key(Self.rawNewKey), try key(Self.rawRSAKey)])
    }

}
