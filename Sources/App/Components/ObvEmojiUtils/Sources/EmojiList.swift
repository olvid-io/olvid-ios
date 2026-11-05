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

extension EmojiList {

    public static var allEmojis: [String] {
        if #available(iOS 16.4, *) {
            return allEmojis15_0
        } else {
            return allEmojis14_0
        }
    }

    public static var variants: [String: [String]] {
        if #available(iOS 16.4, *) {
            return variants15_0
        } else {
            return variants14_0
        }
    }

}

extension EmojiGroup {

    public var firstEmoji: String {
        if #available(iOS 16.4, *) {
            return firstEmoji15_0
        } else {
            return firstEmoji14_0
        }
    }

    public static func group(of position: Int) -> EmojiGroup? {
        if #available(iOS 16.4, *) {
            return group15_0(of: position)
        } else {
            return group14_0(of: position)
        }
    }
}
