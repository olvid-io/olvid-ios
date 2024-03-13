/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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

import UIKit
import _Discussions_Mentions_Builders_Shared
import ObvUICoreData

public enum MentionsTextBubbleAttributedStringBuilder {
    /// Denotes the kind of a bubble this represents
    ///
    /// - `sent`: A message the user sent
    /// - `received`: A message the user received
    public enum MessageKind {
        /// A message the user sent
        case sent

        /// A message the user received
        case received
    }

    /// Generates an instance of `NSAttributedString` suitable for display within an instance of `TextBubble` with links towards the profile of mentioned users
    /// - Parameters:
    ///   - text: The text to show
    ///   - messageKind: The kind of message, see ``MessageKind``
    ///   - mentionedUsers: A dictionary of text ranges to a `MentionableIdentity`
    ///   - baseAttributes: The base attributes to apply to the whole string
    /// - Returns: The generated attributed string
    public static func generateAttributedString(from text: String, messageKind: MessageKind, mentionedUsers: MentionableIdentityTypes.MentionableIdentityFromRange, baseAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text,
                                                         attributes: baseAttributes)

        attributedString.beginEditing()

        let mentionAttributesFunction: (MentionableIdentity) -> [NSAttributedString.Key: Any]

        switch messageKind {
        case .sent:
            mentionAttributesFunction = [NSAttributedString.Key: Any].sentMessageMentionAttributes

        case .received:
            mentionAttributesFunction = [NSAttributedString.Key: Any].receivedMessageMentionAttributes
        }

        for (aRange, anIdentity) in mentionedUsers {
            let nsRange = NSRange(aRange, in: text)

            attributedString.addAttributes(mentionAttributesFunction(anIdentity), range: nsRange)
        }

        attributedString.endEditing()
        
        return attributedString

    }
}
