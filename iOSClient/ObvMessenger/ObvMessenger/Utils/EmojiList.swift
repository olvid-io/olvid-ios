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
  

import Foundation

extension EmojiList {

    static var allEmojis: [String] {
        if #available(iOS 15.4, *) {
            return allEmojis14_0
        } else {
            return allEmojis13_1
        }
    }

    static var variants: [String: [String]] {
        if #available(iOS 15.4, *) {
            return variants14_0
        } else {
            return variants13_1
        }
    }

}

extension EmojiGroup {

    var firstEmoji: String {
        if #available(iOS 15.4, *) {
            return firstEmoji14_0
        } else {
            return firstEmoji13_1
        }
    }

    static func group(of position: Int) -> EmojiGroup? {
        if #available(iOS 15.4, *) {
            return group14_0(of: position)
        } else {
            return group13_1(of: position)
        }
    }
}
