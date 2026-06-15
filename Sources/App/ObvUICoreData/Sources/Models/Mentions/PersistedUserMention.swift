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
import CoreData
import ObvTypes
import ObvAppTypes


// MARK: - PersistedUserMention

/// Abstract class with two concrete subclasses: ``PersistedUserMentionInMessage`` and ``PersistedUserMentionInDraft``.
@objc(PersistedUserMention)
public class PersistedUserMention: NSManagedObject {
    
    // MARK: Attributes
    
    /// We're storing this bound as an UTF-16 offset.
    @NSManaged private var mentionRangeLowerBound: Int

    /// We're storing this bound as an UTF-16 offset.
    @NSManaged private var mentionRangeUpperBound: Int

    /// The bytes of the mentionned identity.
    @NSManaged private var rawMentionnedIdentity: Data
    
    // MARK: Other variables
    
    var mentionedCryptoId: ObvCryptoId {
        get throws {
            try ObvCryptoId(identity: rawMentionnedIdentity)
        }
    }
    
    private var utf16Range: Range<Int> {
        self.mentionRangeLowerBound..<self.mentionRangeUpperBound
    }
    
    public var userMention: StringAndUserMentions.UserMention {
        get throws {
            return .init(mentionedCryptoId: try mentionedCryptoId,
                         utf16Range: utf16Range)
        }
    }
    
    // MARK: Initializer

    /// The `textContainingMention` is not persisted either. Passing it in this initialiser allows to centralise the checks we want to perform on the range.
    fileprivate convenience init(mention: StringAndUserMentions.UserMention,
                                 forEntityName entityName: String,
                                 within context: NSManagedObjectContext) throws {
        // Sanity checks: we do not create the mention if the bounds clearely make no sense
        guard mention.utf16Range.lowerBound < mention.utf16Range.upperBound else {
            assertionFailure()
            throw ObvUICoreDataError.mentionIsOutOfBounds
        }
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.mentionRangeLowerBound = mention.utf16Range.lowerBound //.utf16Offset(in: textContainingMention)
        self.mentionRangeUpperBound = mention.utf16Range.upperBound //.utf16Offset(in: textContainingMention)
        self.rawMentionnedIdentity = mention.mentionedCryptoId.getIdentity()
    }
    
    
    /// Deletes this user mention. Shall **only** be called from ``PersistedDraft`` and from ``PersistedMessage``.
    func deleteUserMention() throws {
        guard let managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        managedObjectContext.delete(self)
    }
    
}


// MARK: - PersistedUserMentionInMessage

@objc(PersistedUserMentionInMessage)
public final class PersistedUserMentionInMessage: PersistedUserMention {
    
    private static let entityName = "PersistedUserMentionInMessage"

    /// The message containing the mention. Expected to be non nil.
    @NSManaged public private(set) var message: PersistedMessage?

    private convenience init(mention: StringAndUserMentions.UserMention, message: PersistedMessage) throws {
        guard let context = message.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        try self.init(mention: mention,
                      forEntityName: Self.entityName,
                      within: context)
        self.message = message
    }
    
    static func createPersistedUserMentionInMessage(mention: StringAndUserMentions.UserMention, message: PersistedMessage) throws {
        _ = try self.init(mention: mention, message: message)
    }
    
}


// MARK: - PersistedUserMentionInDraft

@objc(PersistedUserMentionInDraft)
public final class PersistedUserMentionInDraft: PersistedUserMention {
    
    private static let entityName = "PersistedUserMentionInDraft"

    /// The draft containing the mention. Expected to be non nil.
    @NSManaged public private(set) var draft: PersistedDraft?

    private convenience init(mention: StringAndUserMentions.UserMention, draft: PersistedDraft) throws {
        guard let context = draft.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        try self.init(mention: mention,
                      forEntityName: Self.entityName,
                      within: context)
        self.draft = draft
    }
    
    static func createPersistedUserMentionInDraft(mention: StringAndUserMentions.UserMention, draft: PersistedDraft) throws {
        _ = try self.init(mention: mention, draft: draft)
    }
    
}
