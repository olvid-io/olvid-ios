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
import ObvTypes
import ObvAppTypes


public struct PersistedMessageReceivedStructure {
    
    public let textBody: String?
    public let messageIdentifierFromEngine: Data
    public let contact: PersistedObvContactIdentityStructure
    public let attachmentsCount: Int
    public let attachementImages: [ObvAttachmentImage]?
    public let senderThreadIdentifier: UUID
    public let senderSequenceNumber: Int

    fileprivate let abstractStructure: PersistedMessageAbstractStructure
    public var readOnce: Bool { abstractStructure.readOnce }
    public var forwarded: Bool { abstractStructure.forwarded }
    public var mentions: [PersistedUserMentionStructure] { abstractStructure.mentions }
    public var discussionKind: PersistedDiscussionAbstractStructure.StructureKind { abstractStructure.discussionKind }
    public var timestamp: Date { abstractStructure.timestamp }
    public var visibilityDuration: TimeInterval? { abstractStructure.visibilityDuration }
    public var repliedToMessage: RepliedToMessageStructure? { abstractStructure.repliedToMessage }
    public var location: PersistedLocationStructure? { abstractStructure.location }
    
    var senderIdentifier: Data {
        contact.cryptoId.getIdentity()
    }
    
    public var messageAppIdentifier: ObvMessageAppIdentifier {
        let discussionIdentifier = discussionKind.discussionIdentifier
        return ObvMessageAppIdentifier.received(
            discussionIdentifier: discussionIdentifier,
            senderIdentifier: senderIdentifier,
            senderThreadIdentifier: senderThreadIdentifier,
            senderSequenceNumber: senderSequenceNumber)
    }
    
    
    public init(textBody: String?, messageIdentifierFromEngine: Data, contact: PersistedObvContactIdentityStructure, attachmentsCount: Int, attachementImages: [ObvAttachmentImage]?, abstractStructure: PersistedMessageAbstractStructure, senderThreadIdentifier: UUID, senderSequenceNumber: Int) {
        self.textBody = textBody
        self.messageIdentifierFromEngine = messageIdentifierFromEngine
        self.contact = contact
        self.attachmentsCount = attachmentsCount
        self.attachementImages = attachementImages
        self.abstractStructure = abstractStructure
        self.senderThreadIdentifier = senderThreadIdentifier
        self.senderSequenceNumber = senderSequenceNumber
    }
    
}
