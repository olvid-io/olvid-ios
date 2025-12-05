/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OlvidUtils
import ObvAppTypes
import ObvAppInboxDatabase
import ObvTypes


final class FetchMessageIdentifiersForLaterOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let expected: WhatIsExpected

    enum WhatIsExpected {
        case discussion(identifierOfExpectedDiscussion: ObvDiscussionIdentifier)
        case contactInGroup(identifierOfExpectedGroup: ObvGroupIdentifier, cryptoIdOfExpectedContact: ObvCryptoId?)
        case message(messageIdentifier: ObvMessageAppIdentifier)
    }

    init(expected: WhatIsExpected) {
        self.expected = expected
        super.init()
    }
    
    private(set) var messageIdentifiers: [ObvMessageIdentifier]?
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            switch expected {
            case .discussion(let identifierOfExpectedDiscussion):
                switch identifierOfExpectedDiscussion {
                case .oneToOne(let id):
                    messageIdentifiers = try MessageIdentifierForLaterExpectingDiscussionOneToOne.fetchMessageIdentifiersForLater(
                        contactIdentifier: id,
                        within: obvContext.context)
                case .groupV1(let id):
                    messageIdentifiers = try MessageIdentifierForLaterExpectingDiscussionGroupV1.fetchMessageIdentifiersForLater(
                        obvGroupV1Identifier: id,
                        within: obvContext.context)
                case .groupV2(let id):
                    messageIdentifiers = try MessageIdentifierForLaterExpectingDiscussionGroupV2.fetchMessageIdentifiersForLater(
                        obvGroupV2Identifier: id,
                        within: obvContext.context)
                }
            case .contactInGroup(identifierOfExpectedGroup: let identifierOfExpectedGroup, cryptoIdOfExpectedContact: let cryptoIdOfExpectedContact):
                switch identifierOfExpectedGroup {
                case .groupV1(let id):
                    messageIdentifiers = try MessageIdentifierForLaterExpectingContactInGroupV1.fetchMessageIdentifiersForLater(
                        obvGroupV1Identifier: id,
                        contactCryptoId: cryptoIdOfExpectedContact,
                        within: obvContext.context)
                case .groupV2(let id):
                    messageIdentifiers = try MessageIdentifierForLaterExpectingContactInGroupV2.fetchMessageIdentifiersForLater(
                        obvGroupV2Identifier: id,
                        contactCryptoId: cryptoIdOfExpectedContact,
                        within: obvContext.context)
                }
            case .message(messageIdentifier: let messageIdentifier):
                switch messageIdentifier {
                case .sent(let discussionIdentifier, let senderThreadIdentifier, let senderSequenceNumber):
                    switch discussionIdentifier {
                    case .oneToOne(id: let discussionId):
                        messageIdentifiers = try MessageIdentifierForLaterExpectingSentMessageInOneToOneDiscussion.fetchMessageIdentifiersForLater(
                            discussionId: discussionId,
                            sentMessageId: (senderThreadIdentifier, senderSequenceNumber),
                            within: obvContext.context)
                    case .groupV1(id: let discussionId):
                        messageIdentifiers = try MessageIdentifierForLaterExpectingSentMessageInGroupV1Discussion.fetchMessageIdentifiersForLater(
                            discussionId: discussionId,
                            sentMessageId: (senderThreadIdentifier, senderSequenceNumber),
                            within: obvContext.context)
                    case .groupV2(id: let discussionId):
                        messageIdentifiers = try MessageIdentifierForLaterExpectingSentMessageInGroupV2Discussion.fetchMessageIdentifiersForLater(
                            discussionId: discussionId,
                            sentMessageId: (senderThreadIdentifier, senderSequenceNumber),
                            within: obvContext.context)
                    }
                case .received(let discussionIdentifier, let senderIdentifier, let senderThreadIdentifier, let senderSequenceNumber):
                    switch discussionIdentifier {
                    case .oneToOne(id: let discussionId):
                        messageIdentifiers = try MessageIdentifierForLaterExpectingReceivedMessageInOneToOneDiscussion.fetchMessageIdentifiersForLater(
                            discussionId: discussionId,
                            receivedMessageId: (senderThreadIdentifier, senderSequenceNumber, senderIdentifier),
                            within: obvContext.context)
                    case .groupV1(id: let discussionId):
                        messageIdentifiers = try MessageIdentifierForLaterExpectingReceivedMessageInGroupV1Discussion.fetchMessageIdentifiersForLater(
                            discussionId: discussionId,
                            receivedMessageId: (senderThreadIdentifier, senderSequenceNumber, senderIdentifier),
                            within: obvContext.context)
                    case .groupV2(id: let discussionId):
                        messageIdentifiers = try MessageIdentifierForLaterExpectingReceivedMessageInGroupV2Discussion.fetchMessageIdentifiersForLater(
                            discussionId: discussionId,
                            receivedMessageId: (senderThreadIdentifier, senderSequenceNumber, senderIdentifier),
                            within: obvContext.context)
                    }
                }
            }
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
