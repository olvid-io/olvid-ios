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
import ObvEncoder
@testable import ObvCrypto


/// Checks that two identities are equal exactly when their full bytes are, server URL included, and that the hash agrees.
///
/// Anyone who knows an identity can present its public keys under another server URL, so the same keys under two URLs are
/// two different identities. Outside this module, `==` and `!=` on two identities resolve to `NSObject`'s, which calls
/// `isEqual`; the tests check both that and the module's own `==`.
final class ObvCryptoIdentityEqualityTests: XCTestCase {

    private let prng = ObvCryptoSuite.sharedInstance.prngService()
    private let serverURL = URL(string: "https://server.olvid.io")!
    private let otherServerURL = URL(string: "https://elsewhere.example")!


    // MARK: - ObvCryptoIdentity

    func testTheSameBytesDecodedTwiceGiveEqualIdentitiesWithTheSameHash() throws {
        let bytes = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng).getObvCryptoIdentity().getIdentity()
        let first = try XCTUnwrap(ObvCryptoIdentity(from: bytes))
        let second = try XCTUnwrap(ObvCryptoIdentity(from: bytes))
        XCTAssertTrue(first == second)
        XCTAssertTrue(first.isEqual(second))
        XCTAssertEqual(first.hash, second.hash)
    }


    func testTheSameKeysUnderAnotherServerAreAnotherIdentity() {
        let identity = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng).getObvCryptoIdentity()
        let sameKeysElsewhere = ObvCryptoIdentity(serverURL: otherServerURL,
                                                  publicKeyForAuthentication: identity.publicKeyForAuthentication,
                                                  publicKeyForPublicKeyEncryption: identity.publicKeyForPublicKeyEncryption)
        XCTAssertFalse(identity == sameKeysElsewhere)
        XCTAssertTrue(identity != sameKeysElsewhere)
        XCTAssertFalse(identity.isEqual(sameKeysElsewhere))
        XCTAssertEqual(Set([identity, sameKeysElsewhere]).count, 2)
        XCTAssertFalse([identity].contains(sameKeysElsewhere))
    }


    func testAnotherIdentityOnTheSameServerIsAnotherIdentity() {
        let identity = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng).getObvCryptoIdentity()
        let other = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng).getObvCryptoIdentity()
        XCTAssertFalse(identity == other)
        XCTAssertFalse(identity.isEqual(other))
    }


    /// Both initializers must give the same bytes, whichever way the identity was made.
    func testTheBytesAreTheSameWhicheverInitializerMadeTheIdentity() throws {
        let built = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng).getObvCryptoIdentity()
        let decoded = try XCTUnwrap(ObvCryptoIdentity(from: built.getIdentity()))
        let decodedFromEncoded = try XCTUnwrap(ObvCryptoIdentity(built.obvEncode()))
        let copied = try XCTUnwrap(built.copy() as? ObvCryptoIdentity)
        for identity in [decoded, decodedFromEncoded, copied] {
            XCTAssertEqual(identity.getIdentity(), built.getIdentity())
            XCTAssertTrue(identity == built)
            XCTAssertEqual(identity.hash, built.hash)
        }
        XCTAssertEqual(Set([built, decoded, decodedFromEncoded, copied]).count, 1)
    }


    // MARK: - ObvOwnedCryptoIdentity

    func testACopyOfAnOwnedIdentityIsEqualWithTheSameHash() throws {
        let owned = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng)
        let copy = try XCTUnwrap(owned.copy() as? ObvOwnedCryptoIdentity)
        XCTAssertTrue(owned == copy)
        XCTAssertTrue(owned.isEqual(copy))
        XCTAssertEqual(owned.hash, copy.hash)
        XCTAssertEqual(Set([owned, copy]).count, 1)
    }


    func testTheSameOwnedKeysUnderAnotherServerAreAnotherOwnedIdentity() {
        let owned = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng)
        let sameKeysElsewhere = ObvOwnedCryptoIdentity(serverURL: otherServerURL,
                                                       publicKeyForAuthentication: owned.publicKeyForAuthentication,
                                                       publicKeyForPublicKeyEncryption: owned.publicKeyForPublicKeyEncryption,
                                                       privateKeyForAuthentication: owned.privateKeyForAuthentication,
                                                       privateKeyForPublicKeyEncryption: owned.privateKeyForPublicKeyEncryption,
                                                       secretMACKey: owned.secretMACKey)
        XCTAssertFalse(owned == sameKeysElsewhere)
        XCTAssertFalse(owned.isEqual(sameKeysElsewhere))
        XCTAssertEqual(Set([owned, sameKeysElsewhere]).count, 2)
    }

}
