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


/// Recognises a decrypted inbox message whose payload carries a *discussion shared settings* item.
///
/// The engine has to count these and cannot decode one: a decrypted `messagePayload` is the JSON of an app-side `PersistedItemJSON`, and the dependency runs
/// app → engine only. So it recognises the *shape* instead, and ``jsonKey`` is the one place the app's vocabulary is written down on this side.
public enum ObvDiscussionSharedSettingsPayload {

    /// Mirrors `PersistedItemJSON.CodingKeys.discussionSharedConfiguration`, which nothing in the engine can see. Changing it there means changing it here.
    public static let jsonKey = "settings"


    /// Whether this payload carries a discussion-shared-settings item.
    ///
    /// **The key being present, not being alone.** These bytes often come from another platform's serialiser, and an item may carry more than one field —
    /// `PersistedItemJSON.init(messageJSON:returnReceiptJSON:)` sets two. Dropping a settings item because something rode along would understate the backlog
    /// this figure exists to size, in the direction that reads as *nothing wrong here*. A truncated `{"settings":` is counted for the same reason.
    ///
    /// No parser, because the scan is anchored at the first byte and so answers outright. That matters because on the device this figure is for, every
    /// message matches: 100'000 payloads cost 125ms parsed against 0.9ms scanned.
    public static func isADiscussionSharedSettingsItem(_ payload: Data) -> Bool {
        beginsWithTheKeyAndItsColon(payload)
    }


    /// Whether the payload opens an object whose first key is ``jsonKey``, followed by its colon.
    ///
    /// Whitespace is skipped at the three places JSON allows it before that colon — before the `{`, after it, and before the `:` — so `{"settings":{}}` and
    /// `  { "settings" : {} }` both pass. Not inside the quotes: `{" settings":…}` is a different key, and so is one that merely begins like ours, the closing
    /// quote being consumed too. Two legal spellings it cannot see, neither ever observed: an escaped key (`{"\u0073ettings":…}`) and a leading UTF-8 BOM.
    private static func beginsWithTheKeyAndItsColon(_ payload: Data) -> Bool {

        // A raw buffer, and the key built once: this runs for every decrypted message in the store, so its per-payload cost is the whole of its cost.
        payload.withUnsafeBytes { raw -> Bool in

            let count = raw.count
            var index = 0

            // The opening brace.
            while index < count, isWhitespace(raw[index]) { index += 1 }
            guard index < count, raw[index] == UInt8(ascii: "{") else { return false }
            index += 1

            // Our key, with both quotes — the closing one is what stops a key that merely begins like ours.
            while index < count, isWhitespace(raw[index]) { index += 1 }
            guard count - index >= quotedKeyBytes.count else { return false }
            for byte in quotedKeyBytes {
                guard raw[index] == byte else { return false }
                index += 1
            }

            // The colon that follows a key. Establishing this is all the parse used to do that mattered.
            while index < count, isWhitespace(raw[index]) { index += 1 }
            return index < count && raw[index] == UInt8(ascii: ":")

        }

    }


    /// ``jsonKey`` as JSON writes a key, quotes included. Built once: inside the scan it cost an interpolation and an allocation per payload.
    private static let quotedKeyBytes: [UInt8] = Array("\"\(jsonKey)\"".utf8)


    /// The four bytes JSON calls insignificant whitespace.
    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0a || byte == 0x0d
    }

}
