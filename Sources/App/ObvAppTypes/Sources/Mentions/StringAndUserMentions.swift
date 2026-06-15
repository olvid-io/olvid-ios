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
import ObvTypes


/// Structure allowing to go back and forth between an `AttributedString` containing mentions, and a plain `String`.
public struct StringAndUserMentions: Sendable, Equatable, Hashable {

    public let body: String
    public let mentions: [UserMention]
    
    public init(body: String, mentions: [UserMention]) {
        let sanitizedMentions = mentions.filter { $0.utf16Range.lowerBound >= 0 && $0.utf16Range.upperBound <= body.count }
        self.body = body
        self.mentions = Self.sortAndSanitizeMentions(mentions: sanitizedMentions)
    }
    
    public struct UserMention: Sendable, Equatable, Hashable {
        public let mentionedCryptoId: ObvCryptoId
        public let utf16Range: Range<Int>
        
        public init(mentionedCryptoId: ObvCryptoId, utf16Range: Range<Int>) {
            self.mentionedCryptoId = mentionedCryptoId
            self.utf16Range = utf16Range
        }
        
    }
    
    /// Processes an array of mention ranges, returning a new array of non-overlapping ranges sorted in ascending order by their start positions.
    private static func sortAndSanitizeMentions(mentions: [UserMention]) -> [UserMention] {
        let sorted = mentions.sorted { $0.utf16Range.lowerBound < $1.utf16Range.lowerBound }
        guard let first = sorted.first else { return [] }

        return sorted.dropFirst().reduce(into: [first]) { result, current in
            guard let previous = result.last else { return }
            if current.utf16Range.lowerBound >= previous.utf16Range.upperBound {
                result.append(current)
            } else {
                assertionFailure() // Comment when passing tests
            }
        }
    }
    
    
    /// This is used when forwarding a message (as we do not want to forward mentions)
    public var removingMentions: Self {
        return Self.init(body: self.body, mentions: [])
    }
    
}


// MARK: - Creating a string with Markdown attributes from a StringAndUserMentions

extension StringAndUserMentions {

    public var markdownStringWithMentionAttributes: String {
        
        // Sort the mentions from last to first
        
        let mentionsFromLastToFirst = self.mentions
            .sorted { $0.utf16Range.upperBound > $1.utf16Range.upperBound }

        // Create a new plain String, where the substring corresponding to mentions (e.g., @Alice) are replaced
        // by custom Markdown strings for the ObvMentionAttribute custom attribute
        // (e.g., ^[@Alice](mentionedIdentity: ...))
        
        var body = self.body
        for mention in mentionsFromLastToFirst {
            do {
                let mentionAttributeValue = ObvMentionAttribute.Value(cryptoId: mention.mentionedCryptoId)
                let encodedMentionAttribute = try mentionAttributeValue.jsonEncode()
                let lowerBound: String.Index = String.Index(utf16Offset: mention.utf16Range.lowerBound, in: body)
                let upperBound: String.Index = String.Index(utf16Offset: mention.utf16Range.upperBound, in: body)
                let range: Range<String.Index> = lowerBound..<upperBound
                let replacementString = "^[\(body[range])](\(ObvMentionAttribute.markdownName): \(encodedMentionAttribute))"
                body.replaceSubrange(range, with: replacementString)
            } catch {
                assertionFailure() // In production, continue with the next mention
            }
        }

        return body
        
    }
    
}


// MARK: - Going back and forth between StringAndUserMentions and AttributedString

extension AttributedString {
    
    /// Creates a `StringAndUserMentions` instance from an `AttributedString`.
    ///
    /// Note that we lose all other attributes of `self`.
    ///
    /// The counterpart of this computed variable is
    /// ```
    /// var attributedString: AttributedString
    /// ```
    public var messageBodyWithUserMentions: StringAndUserMentions {
        
        let body = String(self.characters[...])
        
        let mentions: [StringAndUserMentions.UserMention] = self.runs[\.mention].compactMap { (mentionedCryptoId, range) in
            guard let mentionedCryptoId else { return nil }
            guard let lower = String.Index(range.lowerBound, within: body)?.utf16Offset(in: body) else { assertionFailure(); return nil }
            guard let upper = String.Index(range.upperBound, within: body)?.utf16Offset(in: body) else { assertionFailure(); return nil }
            guard lower < upper else { assertionFailure(); return nil }
            return .init(mentionedCryptoId: mentionedCryptoId, utf16Range: lower..<upper)
        }

        return .init(body: body, mentions: mentions)
        
    }
    
}


extension StringAndUserMentions {
    
    /// Creates an `AttributedString` from a `StringAndUserMentions` instance.
    ///
    /// The counterpart of this computed variable is
    /// ```
    /// var messageBodyWithUserMentions: StringAndUserMentions
    /// ```
    public var attributedString: AttributedString {
        
        let body = self.body
        var attributedString = AttributedString(body)
        
        for mention in self.mentions {
            let utf16Range = mention.utf16Range
            
            guard utf16Range.lowerBound >= 0,
                  utf16Range.upperBound <= body.utf16.count else {
                assertionFailure("Mention UTF-16 range is out of bounds")
                continue
            }
            
            let lowerUTF16Index = body.utf16.index(body.utf16.startIndex, offsetBy: utf16Range.lowerBound)
            let upperUTF16Index = body.utf16.index(body.utf16.startIndex, offsetBy: utf16Range.upperBound)
            
            guard let lowerStringIndex = String.Index(lowerUTF16Index, within: body),
                  let upperStringIndex = String.Index(upperUTF16Index, within: body) else {
                assertionFailure("UTF-16 range does not align to Character boundaries")
                continue
            }
            
            guard let lowerAttributedIndex = AttributedString.Index(lowerStringIndex, within: attributedString),
                  let upperAttributedIndex = AttributedString.Index(upperStringIndex, within: attributedString) else {
                assertionFailure("Could not convert String.Index to AttributedString.Index")
                continue
            }
            
            attributedString[lowerAttributedIndex..<upperAttributedIndex].mention = mention.mentionedCryptoId
        }
        
        return attributedString
        
    }
    
}
