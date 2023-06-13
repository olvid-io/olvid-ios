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
import CoreData
import struct ObvTypes.ObvCryptoId
import protocol OlvidUtils.ObvManagedObject
import class OlvidUtils.ObvContext
import protocol OlvidUtils.ObvErrorMaker

/// Abstract class with two concrete subclasses: ``PersistedUserMentionInMessage`` and ``PersistedUserMentionInMessage``.
@objc(PersistedUserMention)
public class PersistedUserMention: NSManagedObject, ObvErrorMaker {
    
    public static let errorDomain = "PersistedUserMention"
    
    /// We're storing this bound as an UTF-16 offset.
    @NSManaged private var mentionRangeLowerBound: Int

    /// We're storing this bound as an UTF-16 offset.
    @NSManaged private var mentionRangeUpperBound: Int

    /// The bytes of the mentionned identity. This can corresponds to the owned identity, a contact, a group member, or to none of these cases (e.g., after a contact has been removed from a group and deleted).
    @NSManaged private var rawMentionnedIdentity: Data
    
    // Other variables
    
    var mentionnedCryptoId: ObvCryptoId {
        get throws {
            try ObvCryptoId(identity: rawMentionnedIdentity)
        }
    }
    
    fileprivate enum Kind: CaseIterable {
        case inMessage
        case inDraft
    }
    
    
    /// The `kind` is not persisted and is only here to make sure the `PersistedUserMention` concrete subclass calling this initialiser is known to this class.
    /// The `textContainingMention` is not persisted either. Passing it in this initialiser allows to centralise the checks we want to perform on the range.
    fileprivate convenience init(mention: MessageJSON.UserMention, textContainingMention: String, kind: Kind, forEntityName entityName: String, within context: NSManagedObjectContext) throws {
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        // Sanity checks: we do not create the mention if the bounds clearely make no sense
        guard mention.range.lowerBound < mention.range.upperBound,
              mention.range.lowerBound >= textContainingMention.startIndex,
              mention.range.upperBound <= textContainingMention.endIndex else {
            assertionFailure()
            return
        }
        self.mentionRangeLowerBound = mention.range.lowerBound.utf16Offset(in: textContainingMention)
        self.mentionRangeUpperBound = mention.range.upperBound.utf16Offset(in: textContainingMention)
        self.rawMentionnedIdentity = mention.mentionedCryptoId.getIdentity()
    }

    
    /// Deletes this user mention. Shall **only** be called from ``PersistedDraft`` and from ``PersistedMessage``.
    public func deleteUserMention() throws {
        guard let managedObjectContext else { assertionFailure(); throw Self.makeError(message: "Could not find context") }
        managedObjectContext.delete(self)
    }

    
    // MARK: Obtaining a MessageJSON.UserMention
    
    /// - SeeAlso: ``MessageJSON.UserMention``
    public var userMention: MessageJSON.UserMention {
        get throws {
            let mentionRange = try self.mentionRange
            let mentionnedCryptoId = try self.mentionnedCryptoId
            return .init(mentionedCryptoId: mentionnedCryptoId, range: mentionRange)
        }
    }

    
    // MARK: Obtaining a range for the mention
    
    /// Returns the the range of our given mention relative to the body of our message
    ///
    /// Will return `nil` when:
    ///   - no `message` is linked
    ///   - `message`'s body is empty
    public var mentionRange: Range<String.Index> {
        get throws {
            // Try to determine the text body where this mention occurs
            guard let textBodyContainingMention else {
                assertionFailure()
                throw Self.makeError(message: "We cannot determine the text body containing the mention")
            }
            // Try to return a range for the mention
            return try mentionRangeInText(textBodyContainingMention)
        }
    }

    
    private var textBodyContainingMention: String? {
        for kind in Kind.allCases {
            switch kind {
            case .inDraft:
                if let textBody = (self as? PersistedUserMentionInDraft)?.draft?.body {
                    return textBody
                }
            case .inMessage:
                if let textBody = (self as? PersistedUserMentionInMessage)?.message?.body {
                    return textBody
                }
            }
        }
        return nil
    }
    
    
    private func mentionRangeInText(_ text: String) throws -> Range<String.Index> {
        
        guard mentionRangeLowerBound < mentionRangeUpperBound,
              mentionRangeLowerBound >= 0,
              mentionRangeUpperBound <= text.endIndex.utf16Offset(in: text) else {
            assertionFailure()
            throw Self.makeError(message: "Given the way we initialised this mention, it is likely that the message body was updated but we did not delete the mentions, which is an error.")
        }

        let mentionRangeLowerBoundIndex = String.Index(utf16Offset: mentionRangeLowerBound, in: text)
        let mentionRangeUpperBoundIndex = String.Index(utf16Offset: mentionRangeUpperBound, in: text)

        return .init(uncheckedBounds: (mentionRangeLowerBoundIndex, mentionRangeUpperBoundIndex))

    }


    // MARK: Obtaining a MentionableIdentity
    
    public func fetchMentionableIdentity() throws -> MentionableIdentity? {
        // Try to determine the discussion where this mention occurs
        guard let discussion else {
            assertionFailure()
            throw Self.makeError(message: "We cannot determine the discussion, the rawMentionnedIdentity value alone is not enough to determine the exact identity that is mentionned")
        }
        // Given the discussion, we can try to return an appropriate MentionableIdentity
        return try getMentionableIdentityInDiscussion(discussion)
    }

    
    private var discussion: PersistedDiscussion? {
        for kind in Kind.allCases {
            switch kind {
            case .inDraft:
                if let discussion = (self as? PersistedUserMentionInDraft)?.draft?.discussion {
                    return discussion
                }
            case .inMessage:
                if let discussion = (self as? PersistedUserMentionInMessage)?.message?.discussion {
                    return discussion
                }
            }
        }
        return nil
    }
    
    
    private func getMentionableIdentityInDiscussion(_ discussion: PersistedDiscussion) throws -> MentionableIdentity? {
        guard let ownedIdentity = discussion.ownedIdentity else {
            assertionFailure()
            throw Self.makeError(message: "We cannot determine the owned identity, the rawMentionnedIdentity value alone is not enough to determine the exact identity that is mentionned")
        }
        let ownedCryptoId = ownedIdentity.cryptoId
        let mentionnedCryptoId = try self.mentionnedCryptoId
        // Case 1: the mentionned identity is our owned identity
        if mentionnedCryptoId == ownedCryptoId {
            return ownedIdentity
        }
        // Case 2: the mentionned identity is a contact
        if let contact = try PersistedObvContactIdentity.get(cryptoId: mentionnedCryptoId, ownedIdentity: ownedIdentity, whereOneToOneStatusIs: .any) {
            return contact
        }
        // Case 3: the mentionned identity is a group V2 member that is not a contact
        if let groupV2Discussion = discussion as? PersistedGroupV2Discussion,
              let group = groupV2Discussion.group,
              let mentionnedGroupMember = group.otherMembers.first(where: { $0.cryptoId == mentionnedCryptoId }) {
            return mentionnedGroupMember
        }
        // Case 4: If we reach this point, we could not find a proper MentionableIdentity
        return nil
    }
    
}


// MARK: - PersistedUserMentionInMessage

@objc(PersistedUserMentionInMessage)
public final class PersistedUserMentionInMessage: PersistedUserMention {
    
    private static let entityName = "PersistedUserMentionInMessage"
    private static let kind = Kind.inMessage

    /// The message containing the mention. Expected to be non nil.
    @NSManaged public private(set) var message: PersistedMessage?

    convenience init(mention: MessageJSON.UserMention, message: PersistedMessage) throws {
        guard let context = message.managedObjectContext else { assertionFailure(); throw Self.makeError(message: "Could not find context") }
        guard let messageBody = message.body else {
            assertionFailure()
            throw Self.makeError(message: "The message has no body and thus cannot contain any mention")
        }
        try self.init(mention: mention,
                      textContainingMention: messageBody,
                      kind: Self.kind,
                      forEntityName: Self.entityName,
                      within: context)
        self.message = message
    }
    
}


// MARK: - PersistedUserMentionInDraft

@objc(PersistedUserMentionInDraft)
public final class PersistedUserMentionInDraft: PersistedUserMention {
    
    private static let entityName = "PersistedUserMentionInDraft"
    private static let kind = Kind.inDraft

    /// The draft containing the mention. Expected to be non nil.
    @NSManaged public private(set) var draft: PersistedDraft?

    convenience init(mention: MessageJSON.UserMention, draft: PersistedDraft) throws {
        guard let context = draft.managedObjectContext else { assertionFailure(); throw Self.makeError(message: "Could not find context") }
        guard let draftBody = draft.body else {
            assertionFailure()
            throw Self.makeError(message: "The draft has no body and thus cannot contain any mention")
        }
        try self.init(mention: mention,
                      textContainingMention: draftBody,
                      kind: Self.kind,
                      forEntityName: Self.entityName,
                      within: context)
        self.draft = draft
    }
    
}
