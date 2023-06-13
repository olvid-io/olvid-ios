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


// MARK: - Thread safe structure

extension PersistedMessage {
    
    public struct AbstractStructure {
        let objectPermanentID: ObvManagedObjectPermanentID<PersistedMessage>
        let isReplyToAnotherMessage: Bool
        let readOnce: Bool
        let forwarded: Bool
        let timestamp: Date
        let isPersistedMessageSent: Bool
        let mentions: [PersistedUserMention.Structure]
        let discussionKind: PersistedDiscussion.StructureKind
        var discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion> { discussionKind.discussionPermanentID }
        
        var doesMentionOwnedIdentity: Bool {
            mentions.map(\.mentionedCryptoId).contains(discussionKind.ownedCryptoId)
        }
    }
    
    public func toAbstractStructure() throws -> AbstractStructure {
        let discussionKind = try discussion.toStructKind()
        let isPersistedMessageSent = self is PersistedMessageSent
        return AbstractStructure(objectPermanentID: self.messagePermanentID,
                                 isReplyToAnotherMessage: self.isReplyToAnotherMessage,
                                 readOnce: self.readOnce,
                                 forwarded: self.forwarded,
                                 timestamp: self.timestamp,
                                 isPersistedMessageSent: isPersistedMessageSent,
                                 mentions: mentions.compactMap({ try? $0.toStruct() }),
                                 discussionKind: discussionKind)
    }
    
}


// MARK: - Thread safe struct

extension PersistedMessageReceived {
    
    public struct Structure {
        public let objectPermanentID: ObvManagedObjectPermanentID<PersistedMessageReceived>
        public let textBody: String?
        public let messageIdentifierFromEngine: Data
        public let contact: PersistedObvContactIdentity.Structure
        public let attachmentsCount: Int
        public let attachementImages: [NotificationAttachmentImage]?

        fileprivate let abstractStructure: PersistedMessage.AbstractStructure
        public var isReplyToAnotherMessage: Bool { abstractStructure.isReplyToAnotherMessage }
        public var readOnce: Bool { abstractStructure.readOnce }
        public var forwarded: Bool { abstractStructure.forwarded }
        public var mentions: [PersistedUserMention.Structure] { abstractStructure.mentions }
        public var discussionKind: PersistedDiscussion.StructureKind { abstractStructure.discussionKind }
        public var timestamp: Date { abstractStructure.timestamp }
    }
    
    public func toStruct() throws -> Structure {
        guard let contact = self.contactIdentity else {
            assertionFailure()
            throw Self.makeError(message: "Could not extract required relationships")
        }
        let abstractStructure = try toAbstractStructure()
        return Structure(objectPermanentID: self.objectPermanentID,
                         textBody: self.textBody,
                         messageIdentifierFromEngine: self.messageIdentifierFromEngine,
                         contact: try contact.toStruct(),
                         attachmentsCount: fyleMessageJoinWithStatuses.count,
                         attachementImages: fyleMessageJoinWithStatuses.compactMap { $0.attachementImage() },
                         abstractStructure: abstractStructure)
    }

}


// MARK: - Thread safe struct

extension PersistedMessageSent {
    
    public struct Structure {
        public let objectPermanentID: ObvManagedObjectPermanentID<PersistedMessageSent>
        public let textBody: String?
        public let isEphemeralMessageWithLimitedVisibility: Bool
        fileprivate let abstractStructure: PersistedMessage.AbstractStructure

        var isReplyToAnotherMessage: Bool { abstractStructure.isReplyToAnotherMessage }
        var readOnce: Bool { abstractStructure.readOnce }
        var forwarded: Bool { abstractStructure.forwarded }
        public var mentions: [PersistedUserMention.Structure] { abstractStructure.mentions }
        public var discussionKind: PersistedDiscussion.StructureKind { abstractStructure.discussionKind }
        public var discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion> { discussionKind.discussionPermanentID }
    }
    
    public func toStruct() throws -> Structure {
        let abstractStructure = try toAbstractStructure()
        return Structure(objectPermanentID: self.objectPermanentID,
                         textBody: self.textBody,
                         isEphemeralMessageWithLimitedVisibility: self.isEphemeralMessageWithLimitedVisibility,
                         abstractStructure: abstractStructure)
    }
    
}
