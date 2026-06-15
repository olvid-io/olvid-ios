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
import SwiftUI

public struct ObvMentionAttribute: AttributedStringKey {
    
    public typealias Value = ObvCryptoId
    
    public static let name = "io.olvid.mention"
    
    /// A Boolean value that determines whether the attribute associated with this key is inherited by text that is later added to the `AttributedString`.
    ///
    /// - If `true`, the attribute’s value is automatically applied to any new text inserted adjacent to the existing attributed text.
    /// - If `false`, the attribute is not inherited, and new text will not automatically receive this attribute.
    public static let inheritedByAddedText: Bool = false
    
    
    /// An array of conditions that specify when the cached representation of an AttributedString should be invalidated for this attribute.
    /// Invalidation ensures that visual or behavioral changes (e.g., font, color, or layout) are correctly reflected when the attribute’s value changes.
    ///
    /// The `textChanged` condition specifies that the cached representation of an `AttributedString` should be invalidated whenever
    /// the underlying text content changes, regardless of whether the attribute’s value itself is modified. On iOS, we invalidate the cach
    ///
    /// The `textChanged` condition ensures that if an character is added in the middle of a mention, the whole mention attribute is removed from both sides
    /// of the inserted text.
    #if os(iOS) && !targetEnvironment(macCatalyst)
    public static let invalidationConditions: Set<AttributedString.AttributeInvalidationCondition>? = [.textChanged]
    #else
    public static let invalidationConditions: Set<AttributedString.AttributeInvalidationCondition>? = nil
    #endif
    
    
}


/// This extension makes it possible to easily look for an `ObvMentionAttribute` in an attributed string.
/// See the `NSAttributedString` extension below.
public extension NSAttributedString.Key {
    
    static let mention: Self = .init(ObvMentionAttribute.name)
    
}


public extension NSAttributedString {
    
    func findFirstMention(in characterRange: NSRange) -> ObvMentionAttribute.Value? {
        
        var mentionFound: ObvMentionAttribute.Value?
        
        self.enumerateAttributes(in: characterRange) { attributes, range, _ in
            if let mention = attributes[.mention] as? ObvMentionAttribute.Value {
                mentionFound = mention
                return
            }
        }

        return mentionFound
        
    }
    
}


extension ObvMentionAttribute {
    
    enum ObvError: Error {
        case stringEncodingFailed
    }
    
}


extension ObvMentionAttribute: CodableAttributedStringKey {

    // Synthetized implementation. Implementing CodableAttributedStringKey allows the
    // ObvMentionAttribute to be encoded to, and decoded from, Data. Since the Value
    // is an ObvCryptoId, that implements Codable, we can leverage the synthetized implementation.

}


extension ObvMentionAttribute.Value {
    
    public func jsonEncode() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard let string = String(data: data, encoding: .utf8) else { assertionFailure(); throw ObvMentionAttribute.ObvError.stringEncodingFailed }
        return string
    }
    
}


extension ObvMentionAttribute: MarkdownDecodableAttributedStringKey {
 
    // Synthetized implementation. Allows to use Apple’s extended syntax for markdown: ^[text](attribute: value).
    // See `MarkdownDecodableAttributedStringKey` documentation.
    // This should allow to decode Markdown attributes like:
    // ^[Alice](mentionedIdentity: ...)
    // When creating attributed strings from Apple's Markdown-based initializers, we must set allowsExtendedAttributes
    // to true.

    public static let markdownName = "mentionedIdentity"

}


public extension AttributeScopes {
    
//    struct ObvComposeAttributes: AttributeScope {
//        public let mention: ObvMentionAttribute
//        public let swiftUI: SwiftUIAttributes
//        //public let foregroundColor: AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
//        //public let font: AttributeScopes.SwiftUIAttributes.FontAttribute
//    }
    
    struct OlvidAppAttributes: AttributeScope {
        public let mention: ObvMentionAttribute
        public let swiftUI: SwiftUIAttributes
        public let uiKit: UIKitAttributes
    }
    
    struct OlvidMentionsOnly: AttributeScope {
        public let mention: ObvMentionAttribute
        public let foregroundColorAttribute: SwiftUIAttributes.ForegroundColorAttribute
        public let fontAttribute: SwiftUIAttributes.FontAttribute
    }
    
    var olvidApp: OlvidAppAttributes.Type { OlvidAppAttributes.self }
    var mentionsOnly: OlvidMentionsOnly.Type { OlvidMentionsOnly.self }

}


/// This extension enables dynamic member lookup for the `ObvComposeAttributes` and `ObvComposeAttributes` attributes.
public extension AttributeDynamicLookup {
    
//    subscript<T: AttributedStringKey>(
//        dynamicMember keyPath: KeyPath<AttributeScopes.ObvComposeAttributes, T>) -> T {
//            self[T.self]
//        }
    
    subscript<T: AttributedStringKey>(
        dynamicMember keyPath: KeyPath<AttributeScopes.OlvidAppAttributes, T>) -> T {
            self[T.self]
        }

}
