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
import ObvCrypto
@testable import ObvTypes


/// What the `identity` field of a keycloak JWT must contain, for each of the three bindings. The details are decoded from JSON, so no
/// signature is involved.
final class IdentityBindingTests: XCTestCase {

    private typealias IdentityBinding = SignedObvKeycloakUserDetails.IdentityBinding
    private typealias ObvError = SignedObvKeycloakUserDetails.ObvError

    private let alice = IdentityBindingTests.makeCryptoId()
    private let bob = IdentityBindingTests.makeCryptoId()

    private static func makeCryptoId() -> ObvCryptoId {
        let prng = ObvCryptoSuite.sharedInstance.prngService()
        let ownedCryptoIdentity = ObvOwnedCryptoIdentity.gen(withServerURL: URL(string: "https://server.example.com")!, using: prng)
        return ObvCryptoId(cryptoIdentity: ownedCryptoIdentity.getObvCryptoIdentity())
    }

    /// Details naming `identity`, or naming none when it is `nil`. The JSON carries `identity` in base64, as the server does.
    private func userDetails(naming identity: ObvCryptoId?) throws -> ObvKeycloakUserDetails {
        var json: [String: Any] = ["id": "keycloak-user-id"]
        json["identity"] = identity?.getIdentity().base64EncodedString()
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(ObvKeycloakUserDetails.self, from: data)
    }

    private func assertThrows(_ expectedError: ObvError, binding: IdentityBinding, details: ObvKeycloakUserDetails, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try binding.check(details), file: file, line: line) { error in
            XCTAssertEqual(error as? ObvError, expectedError, file: file, line: line)
        }
    }


    func testTheDetailsNameTheIdentityTheyWereDecodedWith() throws {
        XCTAssertEqual(try userDetails(naming: alice).identity, alice.getIdentity())
        XCTAssertNil(try userDetails(naming: nil).identity)
        XCTAssertNotEqual(alice, bob)
    }


    // MARK: mustBeBound(to:)

    func testMustBeBoundAcceptsTheIdentityItIsBoundTo() throws {
        XCTAssertNoThrow(try IdentityBinding.mustBeBound(to: alice).check(userDetails(naming: alice)))
    }

    func testMustBeBoundRefusesAnotherIdentity() throws {
        assertThrows(.theDetailsNameAnotherIdentity, binding: .mustBeBound(to: alice), details: try userDetails(naming: bob))
    }

    func testMustBeBoundRefusesDetailsNamingNoIdentity() throws {
        assertThrows(.theDetailsNameNoIdentity, binding: .mustBeBound(to: alice), details: try userDetails(naming: nil))
    }


    // MARK: mayBeUnbound(ownedIdentity:)

    func testMayBeUnboundAcceptsTheOwnedIdentity() throws {
        XCTAssertNoThrow(try IdentityBinding.mayBeUnbound(ownedIdentity: alice).check(userDetails(naming: alice)))
    }

    func testMayBeUnboundRefusesAnotherIdentity() throws {
        assertThrows(.theDetailsNameAnotherIdentity, binding: .mayBeUnbound(ownedIdentity: alice), details: try userDetails(naming: bob))
    }

    func testMayBeUnboundAcceptsDetailsNamingNoIdentity() throws {
        XCTAssertNoThrow(try IdentityBinding.mayBeUnbound(ownedIdentity: alice).check(userDetails(naming: nil)))
    }


    // MARK: notCheckedForOurOwnDetailsFromTheServer

    func testNotCheckedAcceptsAnyIdentity() throws {
        XCTAssertNoThrow(try IdentityBinding.notCheckedForOurOwnDetailsFromTheServer.check(userDetails(naming: bob)))
    }

    func testNotCheckedAcceptsDetailsNamingNoIdentity() throws {
        XCTAssertNoThrow(try IdentityBinding.notCheckedForOurOwnDetailsFromTheServer.check(userDetails(naming: nil)))
    }

}
