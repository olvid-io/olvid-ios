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


/// Checks that an identity decodes only from its exact bytes, and that decoding gives those bytes back.
///
/// If extra bytes after the encryption key were accepted, two different byte strings would decode to the same identity,
/// and a comparison or a signature over the received bytes would not be one over the identity. Since
/// ``ObvCryptoIdentity/getIdentity()`` re-encodes the identity, these tests also check that re-encoding gives back the
/// bytes that were received.
final class ObvCryptoIdentityDecodingTests: XCTestCase {

    private let prng = ObvCryptoSuite.sharedInstance.prngService()


    func testAnIdentityFollowedByTrailingBytesIsRefused() {
        let bytes = makeIdentityBytes(serverURL: URL(string: "https://server.olvid.io")!)
        XCTAssertNotNil(ObvCryptoIdentity(from: bytes))
        XCTAssertNil(ObvCryptoIdentity(from: bytes + Data([0x00])))
        XCTAssertNil(ObvCryptoIdentity(from: bytes + Data([0x01])))
        XCTAssertNil(ObvCryptoIdentity(from: bytes + prng.genBytes(count: 33)))
        XCTAssertNil(ObvCryptoIdentity((bytes + Data([0x00])).obvEncode()))
    }


    func testATruncatedIdentityIsRefused() {
        let bytes = makeIdentityBytes(serverURL: URL(string: "https://server.olvid.io")!)
        XCTAssertNil(ObvCryptoIdentity(from: bytes.dropLast()))
    }


    /// Server URLs that a normalizing parser could rewrite: a trailing slash, an upper-case host, an explicit port, a path.
    func testDecodingGivesBackTheBytesItWasGiven() throws {
        let serverURLs = [
            "https://server.olvid.io",
            "https://server.olvid.io/",
            "https://SERVER.olvid.io",
            "https://server.olvid.io:443",
            "https://server.olvid.io/a/b",
        ].compactMap(URL.init(string:))
        XCTAssertEqual(serverURLs.count, 5)
        for serverURL in serverURLs {
            let bytes = makeIdentityBytes(serverURL: serverURL)
            let identity = try XCTUnwrap(ObvCryptoIdentity(from: bytes), "\(serverURL)")
            XCTAssertEqual(identity.getIdentity(), bytes, "\(serverURL)")
        }
    }


    // MARK: - Helpers

    /// The bytes of a fresh identity on `serverURL`, laid out by hand as the format describes rather than by `getIdentity()`.
    private func makeIdentityBytes(serverURL: URL) -> Data {
        let owned = ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng)
        var bytes = Data(serverURL.absoluteString.utf8)
        bytes.append(0x00)
        bytes.append(owned.publicKeyForAuthentication.getCompactKey())
        bytes.append(owned.publicKeyForPublicKeyEncryption.getCompactKey())
        return bytes
    }

}
