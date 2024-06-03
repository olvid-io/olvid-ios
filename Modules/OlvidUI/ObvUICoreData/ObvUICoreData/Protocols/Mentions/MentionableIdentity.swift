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
import CoreData.NSManagedObject
import UI_ObvCircledInitials
import ObvTypes


/// Type used when constructing mentions in a draft, i.e., when sending a message containing a mention.
/// At some point, we might replace it with ``ObvMentionableIdentityAttribute``.
public enum MentionableIdentityTypes {
    
    /// `[Range<String.Index>: MentionableIdentity]`
    public typealias MentionableIdentityFromRange = [Range<String.Index>: MentionableIdentity]

    /// Represents the different types of inner identities
    ///
    /// - owned: Represents our owned identity. See ``PersistedObvOwnedIdentity``
    /// - contact: Represents a contact identity. See ``PersistedObvContactIdentity``
    /// - groupV2Member: Represents a V2 group member whose contact identity isn't present yet. See ``PersistedGroupV2Member``
    public enum InnerIdentity {
        /// Represents our owned identity. See ``PersistedObvOwnedIdentity``
        case owned(TypeSafeManagedObjectID<PersistedObvOwnedIdentity>)
        /// Represents a contact identity. See ``PersistedObvContactIdentity``
        case contact(TypeSafeManagedObjectID<PersistedObvContactIdentity>)
        /// Represents a V2 group member. See ``PersistedGroupV2Member``
        case groupV2Member(TypeSafeManagedObjectID<PersistedGroupV2Member>)
    }
}


/// This type is a custom attribute used in the attribute string constructed in ``PersistedMessage``, and eventually displayed in the text bubble of a discussion cell.
public enum ObvMentionableIdentityAttribute: CodableAttributedStringKey, MarkdownDecodableAttributedStringKey {
    
    public enum Value: Hashable, Codable {
        
        case ownedIdentity(ownedCryptoId: ObvCryptoId)
        case contact(contactIdentifier: ObvContactIdentifier)
        case groupV2Member(groupIdentifier: ObvGroupV2Identifier, memberId: ObvCryptoId)
        
        enum ObvError: Error {
            case stringEncodingFailed
        }
        
        public func jsonEncode() throws -> String {
            let data = try JSONEncoder().encode(self)
            guard let string = String(data: data, encoding: .utf8) else { assertionFailure(); throw ObvError.stringEncodingFailed }
            return string
        }

    }
    
    public static let name = "mention"
    
}


public extension AttributeScopes {
    struct OlvidAppAttributes: AttributeScope {
        public let mention: ObvMentionableIdentityAttribute
        public let uiKit: UIKitAttributes
    }

    var olvidApp: OlvidAppAttributes.Type { OlvidAppAttributes.self }
}


public extension AttributeDynamicLookup {
    subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.OlvidAppAttributes, T>) -> T {
        self[T.self]
    }
}



public protocol MentionableIdentity: NSManagedObject {
    
    var mentionnedCryptoId: ObvCryptoId? { get }
    
    /// A string to be used against searching
    var mentionSearchMatcher: String { get }

    /// This is the sanitized value that will be sent accross the wire, this corresponds to the given identity's display name, see ``ObvIdentityCoreDetails``
    var mentionPersistedName: String { get }

    /// This is the display value shown locally. If the current profile has set a nickname, this will be shown, if not, ``mentionPersistedName``
    var mentionDisplayName: String { get }

    /// A user-facing value 
    var mentionPickerTitle: String { get }

    /// An optional display subtitle
    var mentionPickerSubtitle: String? { get }

    /// Defines what kind of backing identity this represents
    var innerIdentity: MentionableIdentityTypes.InnerIdentity { get }

    /// Helper that provides the avatar configuration
    var circledInitialsConfiguration: CircledInitialsConfiguration { get }
    
}

public extension MentionableIdentity {
    var mentionDisplayName: String { // disabled for now, not showing any nicknames
        return mentionPersistedName
    }
}
