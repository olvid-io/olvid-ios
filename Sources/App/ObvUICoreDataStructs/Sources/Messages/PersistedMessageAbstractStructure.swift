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


public struct PersistedMessageAbstractStructure {

    let readOnce: Bool
    let visibilityDuration: TimeInterval?
    let existenceDuration: TimeInterval?
    let forwarded: Bool
    let timestamp: Date
    public let isPersistedMessageSent: Bool
    let mentions: [PersistedUserMentionStructure]
    let discussionKind: PersistedDiscussionAbstractStructure.StructureKind
    let repliedToMessage: RepliedToMessageStructure?
    let senderSequenceNumber: Int
    let location: PersistedLocationStructure?
    
    var isReplyToAnotherMessage: Bool {
        repliedToMessage != nil
    }
    
    public var doesMentionOwnedIdentity: Bool {
        mentions.map(\.mentionedCryptoId).contains(discussionKind.ownedCryptoId)
    }
    
    public init(senderSequenceNumber: Int, repliedToMessage: RepliedToMessageStructure?, readOnce: Bool, visibilityDuration: TimeInterval?, existenceDuration: TimeInterval?, forwarded: Bool, timestamp: Date, isPersistedMessageSent: Bool, mentions: [PersistedUserMentionStructure], discussionKind: PersistedDiscussionAbstractStructure.StructureKind, location: PersistedLocationStructure?) {
        self.repliedToMessage = repliedToMessage
        self.readOnce = readOnce
        self.forwarded = forwarded
        self.timestamp = timestamp
        self.isPersistedMessageSent = isPersistedMessageSent
        self.mentions = mentions
        self.discussionKind = discussionKind
        self.visibilityDuration = visibilityDuration
        self.existenceDuration = existenceDuration
        self.senderSequenceNumber = senderSequenceNumber
        self.location = location
    }
    
    public static func computeDoesMentionOwnedIdentityValue(messageMentionsContainOwnedIdentity: Bool, messageDoesReplyToMessageThatMentionsOwnedIdentity: Bool, messageDoesReplyToSentMessage: Bool) -> Bool {
        messageMentionsContainOwnedIdentity || messageDoesReplyToMessageThatMentionsOwnedIdentity || messageDoesReplyToSentMessage
    }

}


public struct RepliedToMessageStructure {
    
    public let doesMentionOwnedIdentity: Bool
    public let isPersistedMessageSent: Bool
    
    public init(doesMentionOwnedIdentity: Bool, isPersistedMessageSent: Bool) {
        self.doesMentionOwnedIdentity = doesMentionOwnedIdentity
        self.isPersistedMessageSent = isPersistedMessageSent
    }
    
}
