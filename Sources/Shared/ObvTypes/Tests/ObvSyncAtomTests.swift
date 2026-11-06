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
import ObvCrypto
import ObvEncoder
import XCTest
@testable import ObvTypes


/// An `ObvSyncAtom` is written by one device and read by another, which may be an Android or a desktop that this
/// repository does not rebuild. A field that is encoded but never decoded, or decoded but never encoded, is therefore
/// not a compile error and not a crash: it is a value silently replaced by a default on the other device.
final class ObvSyncAtomTests: XCTestCase {

    /// A real identity's bytes, kept verbatim so that nothing here depends on how a key pair is generated.
    private static let identityHex = "68747470733a2f2f7365727665722e6f6e652e746573740000989694f173f8ca5334f153bf82790283342f3e28db8e048e1e4780301628c78200c521dcd56c05305a1b5f8c9dfd69ad6204f38ff725b285d62d0724bd5852ef2e"

    private static let groupUidHex = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"

    /// The raw values agreed with the other platforms. They are part of the format, not an implementation detail.
    private static let stopSuggestingContactRawValue = 22
    private static let preferredReactionRawValue = 23

    private func cryptoId() throws -> ObvCryptoId {
        try ObvCryptoId(identity: XCTUnwrap(Data(hexString: Self.identityHex)))
    }

    /// One scope of each kind, so that a change to `DiscussionIdentifier` is caught here too.
    private func everyScope() throws -> [ObvSyncAtom.Scope] {
        let cryptoId = try cryptoId()
        let groupUid = try XCTUnwrap(UID(hexString: Self.groupUidHex))
        let groupV2Identifier: GroupV2Identifier = try XCTUnwrap(Data(hexString: "cafebabe"))
        return [
            .global,
            .discussion(.oneToOne(contactCryptoId: cryptoId)),
            .discussion(.groupV1(groupIdentifier: GroupV1Identifier(groupUid: groupUid, groupOwner: cryptoId))),
            .discussion(.groupV2(groupIdentifier: groupV2Identifier)),
        ]
    }

    private func roundTrip(_ atom: ObvSyncAtom) throws -> ObvSyncAtom {
        let encoded = try atom.obvEncode()
        return try XCTUnwrap(ObvSyncAtom(encoded))
    }

    // MARK: - Round trips

    func testAPreferredReactionKeepsItsEmojiInEveryScope() throws {
        for scope in try everyScope() {
            let atom = ObvSyncAtom.preferredReaction(scope: scope, emoji: "👍")
            XCTAssertEqual(try roundTrip(atom), atom)
        }
    }


    /// A skin tone is several scalars, and the emoji travels as a `String`.
    func testAPreferredReactionKeepsAMultiScalarEmoji() throws {
        let atom = ObvSyncAtom.preferredReaction(scope: .global, emoji: "👍🏽")
        XCTAssertEqual(try roundTrip(atom), atom)
    }


    func testAStopSuggestingContactKeepsItsContact() throws {
        let atom = ObvSyncAtom.stopSuggestingContact(contactCryptoId: try cryptoId())
        XCTAssertEqual(try roundTrip(atom), atom)
    }


    /// No emoji means *no choice of your own*: globally, fall back to the default; in a discussion, follow the global
    /// setting. So it must survive as `nil` rather than as an absent key that decodes to something else.
    func testAPreferredReactionKeepsTheAbsenceOfAnEmojiInEveryScope() throws {
        for scope in try everyScope() {
            let atom = ObvSyncAtom.preferredReaction(scope: scope, emoji: nil)
            XCTAssertEqual(try roundTrip(atom), atom)
        }
    }


    // MARK: - What goes on the wire

    func testAPreferredReactionIsSentUnderTheRawValueAgreedWithTheOtherPlatforms() throws {
        for scope in try everyScope() {
            let encoded = try ObvSyncAtom.preferredReaction(scope: scope, emoji: "👍").obvEncode()
            let listOfEncoded = try XCTUnwrap([ObvEncoded](encoded))
            let encodedRawValue = try XCTUnwrap(listOfEncoded.first)
            let rawValue: Int = try encodedRawValue.obvDecode()
            XCTAssertEqual(rawValue, Self.preferredReactionRawValue)
        }
    }


    /// The other platforms send the raw value followed by the contact's identity, and nothing else.
    func testAStopSuggestingContactIsSentAsItsRawValueFollowedByTheContact() throws {
        let cryptoId = try cryptoId()
        let encoded = try ObvSyncAtom.stopSuggestingContact(contactCryptoId: cryptoId).obvEncode()
        let listOfEncoded = try XCTUnwrap([ObvEncoded](encoded))
        XCTAssertEqual(listOfEncoded.count, 2)
        let rawValue: Int = try listOfEncoded[0].obvDecode()
        XCTAssertEqual(rawValue, Self.stopSuggestingContactRawValue)
        let contactCryptoId: ObvCryptoId = try listOfEncoded[1].obvDecode()
        XCTAssertEqual(contactCryptoId, cryptoId)
    }

}
