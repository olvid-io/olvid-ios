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
import XCTest
@testable import ObvSettings


/// The global settings a new device is given when it joins a profile. The snapshot is read by a device this repository
/// does not build — an Android or a desktop — so the names and the shape below are a format, not an implementation detail.
///
/// These tests read the encoded JSON rather than the node's properties, which are private: the JSON is what actually
/// crosses. They do not call `useToUpdateGlobalSettings()`, which writes the real user defaults.
final class GlobalSettingsSyncSnapshotNodeTests: XCTestCase {

    private func node(preferredReaction: String?) -> GlobalSettingsSyncSnapshotNode {
        .init(autoAcceptGroupInviteFrom: .everyone,
              doSendReadReceipt: true,
              unarchiveOnNotification: true,
              preferredReaction: preferredReaction)
    }

    private func encoded(_ node: GlobalSettingsSyncSnapshotNode) throws -> [String: Any] {
        let data = try JSONEncoder().encode(node)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// What a device on the other side of this format would send us.
    private func decodedThenEncodedAgain(_ json: [String: Any]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: json)
        let node = try JSONDecoder().decode(GlobalSettingsSyncSnapshotNode.self, from: data)
        return try encoded(node)
    }

    private func domain(of json: [String: Any]) throws -> [String] {
        try XCTUnwrap(json["domain"] as? [String])
    }

    // MARK: - The emoji itself

    func testAChosenEmojiIsCarried() throws {
        let json = try encoded(node(preferredReaction: "👍"))
        XCTAssertEqual(json["preferred_reaction"] as? String, "👍")
        XCTAssertTrue(try domain(of: json).contains("preferred_reaction"))
    }


    func testAChosenEmojiSurvivesARoundTrip() throws {
        let json = try decodedThenEncodedAgain(try encoded(node(preferredReaction: "👍🏽")))
        XCTAssertEqual(json["preferred_reaction"] as? String, "👍🏽")
    }


    /// Having chosen nothing is a value of its own — follow the constant — and has to reach the other device as such.
    /// The key is left out, and the domain is what says it was left out **on purpose**.
    func testHavingChosenNothingIsStillSaidOutLoud() throws {
        let json = try encoded(node(preferredReaction: nil))
        XCTAssertNil(json["preferred_reaction"])
        XCTAssertTrue(try domain(of: json).contains("preferred_reaction"))
    }


    func testHavingChosenNothingSurvivesARoundTrip() throws {
        let json = try decodedThenEncodedAgain(try encoded(node(preferredReaction: nil)))
        XCTAssertNil(json["preferred_reaction"])
        XCTAssertTrue(try domain(of: json).contains("preferred_reaction"))
    }


    // MARK: - A sender that has never heard of this setting

    /// Its domain does not name the key, which is how the reader knows to keep whatever it already had rather than
    /// clearing it. Told apart from the case above by the domain alone, both having no value.
    func testASenderThatDoesNotKnowTheSettingSaysNothingAboutIt() throws {
        var json = try encoded(node(preferredReaction: "👍"))
        json["preferred_reaction"] = nil
        json["domain"] = try domain(of: json).filter { $0 != "preferred_reaction" }
        let again = try decodedThenEncodedAgain(json)
        XCTAssertNil(again["preferred_reaction"])
        XCTAssertFalse(try domain(of: again).contains("preferred_reaction"))
    }


    /// A name this version has never seen is dropped rather than refused, or a device on an older build could not read a
    /// snapshot written by a newer one at all.
    func testANameFromALaterVersionIsIgnoredRatherThanRefused() throws {
        var json = try encoded(node(preferredReaction: "👍"))
        json["domain"] = try domain(of: json) + ["something_from_the_future"]
        json["something_from_the_future"] = "whatever"
        let again = try decodedThenEncodedAgain(json)
        XCTAssertEqual(again["preferred_reaction"] as? String, "👍")
        XCTAssertFalse(try domain(of: again).contains("something_from_the_future"))
    }

}
