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
import ObvAppTypes


public struct PersistedMessageSentStructure {
    
    public let textBody: String?
    public let isEphemeralMessageWithLimitedVisibility: Bool
    fileprivate let abstractStructure: PersistedMessageAbstractStructure
    private let senderThreadIdentifier: UUID

    var isReplyToAnotherMessage: Bool { abstractStructure.isReplyToAnotherMessage }
    var readOnce: Bool { abstractStructure.readOnce }
    var forwarded: Bool { abstractStructure.forwarded }
    public var mentions: [PersistedUserMentionStructure] { abstractStructure.mentions }
    public var discussionKind: PersistedDiscussionAbstractStructure.StructureKind { abstractStructure.discussionKind }
    public var repliedToMessage: RepliedToMessageStructure? { abstractStructure.repliedToMessage }

    
    public init(textBody: String?, senderThreadIdentifier: UUID, isEphemeralMessageWithLimitedVisibility: Bool, abstractStructure: PersistedMessageAbstractStructure) {
        self.textBody = textBody
        self.isEphemeralMessageWithLimitedVisibility = isEphemeralMessageWithLimitedVisibility
        self.abstractStructure = abstractStructure
        self.senderThreadIdentifier = senderThreadIdentifier
    }
 
    public var messageAppIdentifier: ObvMessageAppIdentifier {
        return .sent(discussionIdentifier: self.discussionKind.discussionIdentifier,
                     senderThreadIdentifier: self.senderThreadIdentifier,
                     senderSequenceNumber: self.abstractStructure.senderSequenceNumber)
    }

}
