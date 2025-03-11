/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
@testable import EmojiUtils

class EmojiTests: XCTestCase {

    func testAllEmojisAreEmojis() throws {
        for emoji in EmojiList.allEmojis {
            XCTAssertTrue(emoji.isSingleEmoji, "\(emoji) is not a single emoji")
        }
    }

    func testAllVariantsAreEmojis() throws {
        for variants in EmojiList.variants.values {
            for emoji in variants {
                XCTAssertTrue(emoji.isSingleEmoji, "\(emoji) is not a single emoji")
            }
        }
    }

    func testFirstEmojiOfGroupBelongsToItsGroup() throws {
        for group in EmojiGroup.allCases {
            let firstEmoji = group.firstEmoji
            guard let position = EmojiList.allEmojis.firstIndex(of: firstEmoji) else {
                XCTAssertTrue(false, "First emoji of \(group) does not belong to allEmojis list")
                return
            }
            XCTAssertTrue(EmojiGroup.group(of: position) == group, "First emoji of \(group) does not belongs the its group")
        }
    }

    func testNumbersAreNotEmojis() throws {
        let numbers = "0123456789"
        for number in numbers {
            XCTAssertFalse(number.isEmoji, "\(number) should not be an emoji")
        }
    }

    func testLettersAreNotEmojis() throws {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        for letter in letters {
            XCTAssertFalse(letter.isEmoji, "\(letter) should not be an emoji")
        }
    }

    /// For all unicode, if unicode.isEmoji holds, unicode belongs to allEmojis List
    /// For all unicode, if unicode.isEmoji does not hold, unicode does not belong to allEmojis List
    func testInjectionBetweenUnicodeWithIsEmojiAndAllEmojis() throws {
        for i in 0...0x10FFFF {
            guard let scalar = UnicodeScalar(i) else { continue }
            let char = Character(scalar)
            let string = String(char)
            if char.isEmoji {
                XCTAssertTrue(string.isSingleEmoji, "Unicode \(string) should be an emoji")

                /// Hair styles do not belong to the unicode.org list
                guard !scalar.isHairStyle else { continue }
                /// Skin tones do not belong to the unicode.org list
                guard !scalar.isSkinTone else { continue }

                XCTAssertTrue(EmojiList.allEmojis.contains(string), "Unicode \(scalar) should belong to allEmojis list")
            } else {
                XCTAssertFalse(EmojiList.allEmojis.contains(string), "Unicode \(scalar) should not belong to allEmojis list")
            }
        }
    }


}
