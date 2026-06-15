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

import Testing
import Foundation
import ObvTypes
@testable import ObvAppTypes

struct StringAndUserMentionsTests {

    // MARK: - Helpers

    private func roundTrip(_ original: StringAndUserMentions) -> StringAndUserMentions {
        original.attributedString.messageBodyWithUserMentions
    }

    // MARK: - Basic

    @Test("Plain string with no mentions round-trips correctly")
    func noMentions() throws {
        let original = StringAndUserMentions(body: "Hello, world!", mentions: [])
        let result = roundTrip(original)
        #expect(result == original)
    }

    
    @Test("Single mention round-trips correctly")
    func singleMention() throws {
        let body = "Hello @Alice, how are you?"
        //                ^-----^ "@Alice" is at UTF-16 offsets 6..<12
        let mention = StringAndUserMentions.UserMention(
            mentionedCryptoId: .sampleDatas[0],
            utf16Range: 6..<12
        )
        let original = StringAndUserMentions(body: body, mentions: [mention])
        let result = roundTrip(original)
        #expect(result == original)
    }

    
    @Test("Multiple non-overlapping mentions round-trip correctly")
    func multipleMentions() throws {
        let body = "Hi @Alice and @Bob!"
        // "@Alice" → 3..<9, "@Bob" → 14..<18
        let mentions = [
            StringAndUserMentions.UserMention(mentionedCryptoId: .sampleDatas[0], utf16Range: 3..<9),
            StringAndUserMentions.UserMention(mentionedCryptoId: .sampleDatas[1], utf16Range: 14..<18),
        ]
        let original = StringAndUserMentions(body: body, mentions: mentions)
        let result = roundTrip(original)
        #expect(result == original)
    }

    
    // MARK: - Emoji and complex Unicode

    @Test("Mention after a simple emoji round-trips correctly")
    func mentionAfterSimpleEmoji() throws {
        // "👍 @Alice" — 👍 is U+1F44D, which is a surrogate pair in UTF-16 (2 code units)
        let body = "👍 @Alice"
        // UTF-16 layout: [0xD83D, 0xDC4D, 0x0020, 0x0040, 0x0041, 0x006C, 0x0069, 0x0063, 0x0065]
        //                  👍(2 units)       space   @      A      l      i      c      e
        // "@Alice" starts at offset 3, ends at 9
        let mention = StringAndUserMentions.UserMention(
            mentionedCryptoId: .sampleDatas[0],
            utf16Range: 3..<9
        )
        let original = StringAndUserMentions(body: body, mentions: [mention])
        let result = roundTrip(original)
        #expect(result == original)
    }

    @Test("Mention after a ZWJ sequence emoji round-trips correctly")
    func mentionAfterZWJEmoji() throws {
        // "👨‍👩‍👧 @Alice"
        // 👨‍👩‍👧 is a ZWJ family sequence:
        // U+1F468 (👨, surrogate pair: 2) + U+200D (ZWJ: 1) + U+1F469 (👩, surrogate pair: 2)
        // + U+200D (ZWJ: 1) + U+1F467 (👧, surrogate pair: 2) = 8 UTF-16 code units total
        // Then space (1) → "@Alice" starts at offset 9
        let body = "👨‍👩‍👧 @Alice"
        let mentionStart = "👨‍👩‍👧 ".utf16.count  // 9
        let mentionEnd = mentionStart + "@Alice".utf16.count  // 15
        let mention = StringAndUserMentions.UserMention(
            mentionedCryptoId: .sampleDatas[0],
            utf16Range: mentionStart..<mentionEnd
        )
        let original = StringAndUserMentions(body: body, mentions: [mention])
        let result = roundTrip(original)
        #expect(result == original)
    }

    @Test("Mention after a flag emoji (regional indicator pair) round-trips correctly")
    func mentionAfterFlagEmoji() throws {
        // "🇫🇷 @Alice"
        // 🇫🇷 = U+1F1EB (🇫) + U+1F1F7 (🇷), each a surrogate pair → 4 UTF-16 code units
        let body = "🇫🇷 @Alice"
        let mentionStart = "🇫🇷 ".utf16.count  // 5
        let mentionEnd = mentionStart + "@Alice".utf16.count  // 11
        let mention = StringAndUserMentions.UserMention(
            mentionedCryptoId: .sampleDatas[0],
            utf16Range: mentionStart..<mentionEnd
        )
        let original = StringAndUserMentions(body: body, mentions: [mention])
        let result = roundTrip(original)
        #expect(result == original)
    }

    @Test("Mention sandwiched between complex emojis round-trips correctly")
    func mentionBetweenComplexEmojis() throws {
        // "🧑‍💻 @Bob 🇯🇵"
        // 🧑‍💻 = U+1F9D1 (2) + U+200D (1) + U+1F4BB (2) = 5 UTF-16 code units
        // space = 1 → "@Bob" starts at 6
        let prefix = "🧑‍💻 "
        let mention = "@Bob"
        let body = "\(prefix)\(mention) 🇯🇵"
        let mentionStart = prefix.utf16.count
        let mentionEnd = mentionStart + mention.utf16.count
        let userMention = StringAndUserMentions.UserMention(
            mentionedCryptoId: .sampleDatas[1],
            utf16Range: mentionStart..<mentionEnd
        )
        let original = StringAndUserMentions(body: body, mentions: [userMention])
        let result = roundTrip(original)
        #expect(result == original)
    }

    @Test("Multiple mentions interleaved with complex emojis round-trip correctly")
    func multipleMentionsWithComplexEmojis() throws {
        // "👨‍👩‍👧 @Alice 🇫🇷 @Bob 🧑‍💻"
        let part1 = "👨‍👩‍👧 "
        let aliceMentionText = "@Alice"
        let part2 = " 🇫🇷 "
        let bobMentionText = "@Bob"

        let aliceStart = part1.utf16.count
        let aliceEnd = aliceStart + aliceMentionText.utf16.count
        let bobStart = aliceEnd + part2.utf16.count
        let bobEnd = bobStart + bobMentionText.utf16.count

        let body = "\(part1)\(aliceMentionText)\(part2)\(bobMentionText) 🧑‍💻"
        let mentions = [
            StringAndUserMentions.UserMention(mentionedCryptoId: .sampleDatas[0], utf16Range: aliceStart..<aliceEnd),
            StringAndUserMentions.UserMention(mentionedCryptoId: .sampleDatas[1], utf16Range: bobStart..<bobEnd),
        ]
        let original = StringAndUserMentions(body: body, mentions: mentions)
        let result = roundTrip(original)
        #expect(result == original)
    }

    // MARK: - Edge cases

    @Test("Mention at the very start of the string round-trips correctly")
    func mentionAtStart() throws {
        let mention = "@Alice"
        let body = "\(mention) hello"
        let userMention = StringAndUserMentions.UserMention(
            mentionedCryptoId: .sampleDatas[0],
            utf16Range: 0..<mention.utf16.count
        )
        let original = StringAndUserMentions(body: body, mentions: [userMention])
        let result = roundTrip(original)
        #expect(result == original)
    }

    @Test("Mention at the very end of the string round-trips correctly")
    func mentionAtEnd() throws {
        let prefix = "Hello "
        let mention = "@Alice"
        let body = "\(prefix)\(mention)"
        let mentionStart = prefix.utf16.count
        let userMention = StringAndUserMentions.UserMention(
            mentionedCryptoId: .sampleDatas[0],
            utf16Range: mentionStart..<mentionStart + mention.utf16.count
        )
        let original = StringAndUserMentions(body: body, mentions: [userMention])
        let result = roundTrip(original)
        #expect(result == original)
    }

    @Test("Empty body with no mentions round-trips correctly")
    func emptyBody() throws {
        let original = StringAndUserMentions(body: "", mentions: [])
        let result = roundTrip(original)
        #expect(result == original)
    }

    @Test("Overlapping mentions are sanitized before round-trip")
    func overlappingMentionsAreSanitized() throws {
        let body = "Hello @Alice!"
        // Both mentions cover overlapping ranges; only the first should survive sanitization
        let mentions = [
            StringAndUserMentions.UserMention(mentionedCryptoId: .sampleDatas[0], utf16Range: 6..<12),
            StringAndUserMentions.UserMention(mentionedCryptoId: .sampleDatas[1], utf16Range: 8..<13),
        ]
        let sanitized = StringAndUserMentions(body: body, mentions: mentions)
        #expect(sanitized.mentions.count == 1)
        #expect(sanitized.mentions[0].mentionedCryptoId == .sampleDatas[0])

        let result = roundTrip(sanitized)
        #expect(result == sanitized)
    }

}


// MARK: - Private helpers

extension ObvCryptoId {
    
    static var sampleDatas: [Self] = [
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000009e171a9c73a0d6e9480b022154c83b13dfa8e4c99496c061c0c35b9b0432b3a014a5393f98a1aead77b813df0afee6b8af7e5f9a5aae6cb55fdb6bc5cc766f8da")!),
    ]

}

