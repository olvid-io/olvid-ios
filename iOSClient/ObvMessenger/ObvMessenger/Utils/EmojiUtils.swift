/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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

extension Unicode.Scalar {

    var isRegionalIndicator: Bool {
        return ("🇦"..."🇿").contains(self)
    }

    var isSkinTone: Bool {
        for i in 0x1F3FB...0x1F3FF {
            if self == Unicode.Scalar(i) {
                return true
            }
        }
        return false
    }

    var isHairStyle: Bool {
        return ("🦰"..."🦳").contains(self)
    }
}

extension Character {

    /// A simple emoji is one scalar and presented to the user as an Emoji
    var isSimpleEmoji: Bool {
        guard unicodeScalars.count == 1 else { return false }
        guard let firstScalar = unicodeScalars.first else { return false }
        guard !firstScalar.isRegionalIndicator else { return false }
        return firstScalar.properties.isEmojiPresentation
    }

    /// Checks if the scalars will be merged into and emoji
    var isCombinedIntoEmoji: Bool {
        guard unicodeScalars.count > 1 else { return false }
        return unicodeScalars.contains {
            $0.properties.isJoinControl || $0.properties.isVariationSelector || $0.properties.isEmojiModifier
        }
    }

    var isCountryFlag: Bool {
        guard unicodeScalars.count == 2 else { return false }
        return unicodeScalars.allSatisfy({ $0.isRegionalIndicator })
    }

    var isSubdivisionFlag: Bool {
        guard unicodeScalars.count == 7 else { return false }
        guard unicodeScalars.first?.properties.isEmojiPresentation ?? false else { return false }
        var iterator = unicodeScalars.makeIterator()
        guard iterator.next() == "\u{0001F3F4}" else { return false }
        guard iterator.next() == "\u{000E0067}" else { return false }
        guard iterator.next() == "\u{000E0062}" else { return false }
        return true
    }

    var isFlag: Bool {
        isCountryFlag || isSubdivisionFlag
    }

    var isEmoji: Bool {
        return isSimpleEmoji || isCombinedIntoEmoji || isFlag
    }
}

extension String {
    var isSingleEmoji: Bool {
        return count == 1 && containsEmoji
    }

    var containsEmoji: Bool {
        return contains { $0.isEmoji }
    }

    var containsOnlyEmoji: Bool {
        return !isEmpty && !contains { !$0.isEmoji }
    }
}


extension AttributedString {
    
    var containsOnlyEmoji: Bool {
        self.characters.allSatisfy({ $0.isEmoji })
    }
    
}
