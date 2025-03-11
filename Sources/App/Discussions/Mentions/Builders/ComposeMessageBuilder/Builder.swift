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

import Foundation
import _Discussions_Mentions_Builders_Shared
import ObvUICoreData

public enum ComposeMessageViewAttributedStringBuilder {
    @usableFromInline
    struct SerializedMessageBody {
        /// The final text body to display
        @usableFromInline
        let updatedBody: String

        /// Returns the new mention range for a given mention range
        ///
        /// Since the actual visible body may differ from the initial one, these ranges must be updated to reflect the new position within the updated body
        ///
        /// The body may differ due to the user having a custom nickname for a user, the mentioned user may change their display name, etc.
        @usableFromInline
        let mappedMentionedRangeToUpdatedMentionedRange: [Range<String.Index>: Range<String.Index>]

        internal init(updatedBody: String, mappedMentionedRangeToUpdatedMentionedRange: [Range<String.Index> : Range<String.Index>]) {
            self.updatedBody = updatedBody
            self.mappedMentionedRangeToUpdatedMentionedRange = mappedMentionedRangeToUpdatedMentionedRange
        }
    }

    @usableFromInline
    internal static func serializeMessageBody(for body: String, mentionedUsers: MentionableIdentityTypes.MentionableIdentityFromRange) -> SerializedMessageBody {
        var _text = body

        var oldRangesToNewRanges: [Range<String.Index>: Range<String.Index>] = [:]

        var offset = 0

        for (aRange, anIdentity) in mentionedUsers {
            let _updatedRangeStart = _text.index(aRange.lowerBound, offsetBy: offset)

            let updatedRangeStart = _text.index(_updatedRangeStart, offsetBy: MentionsConstants.mentionPrefix.count) //skip the `@`

            let updatedRangeEnd = _text.index(aRange.upperBound, offsetBy: offset)

            let rangeToUpdate = updatedRangeStart..<updatedRangeEnd

            if _text[rangeToUpdate] == anIdentity.mentionDisplayName {
                oldRangesToNewRanges[aRange] = _text.index(aRange.lowerBound, offsetBy: offset)..<_text.index(aRange.upperBound, offsetBy: offset)
            } else {
                _text.replaceSubrange(rangeToUpdate, with: anIdentity.mentionDisplayName)

                let replacedTextRange = _text.range(of: MentionsConstants.mentionPrefix + anIdentity.mentionDisplayName,
                                                    options: [],
                                                    range: _updatedRangeStart..<_text.endIndex)!

                let rangeEndDifference = _text.distance(from: rangeToUpdate.lowerBound, to: replacedTextRange.upperBound)

                offset -= rangeEndDifference

                oldRangesToNewRanges[aRange] = replacedTextRange
            }
        }

        return .init(
            updatedBody: _text,
            mappedMentionedRangeToUpdatedMentionedRange: oldRangesToNewRanges
        )
    }

    /// Creates the initial draft to display when a user had a draft saved for a given conversation and pre-populates its with its mentions, if any
    /// - Parameters:
    ///   - body: The draft's raw body
    ///   - mentionedUsers: The draft's mentions
    ///   - typingAttributes: The default typing attributes
    /// - Returns: The constructed attributed string
    @inlinable
    public static func createInitialMessageAttributedString(for body: String, mentionedUsers: MentionableIdentityTypes.MentionableIdentityFromRange, typingAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let updatedBodyConfiguration = serializeMessageBody(for: body,
                                               mentionedUsers: mentionedUsers)

        let updatedText = updatedBodyConfiguration.updatedBody

        let attributedString = NSMutableAttributedString(string: updatedText,
                                                         attributes: typingAttributes)

        attributedString.beginEditing()

        for (aRange, anIdentity) in mentionedUsers {
            let newRange = updatedBodyConfiguration.mappedMentionedRangeToUpdatedMentionedRange[aRange]!

            let nsRange = NSRange(newRange, in: updatedText)

            attributedString.addAttributes([NSAttributedString.Key: Any].compositionMentionAttributes(anIdentity), range: nsRange)
        }

        attributedString.endEditing()

        return attributedString.copy() as! NSAttributedString
    }
}
