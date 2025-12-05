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
import ObvCrypto
import ObvTypes
import ObvAppTypes
import ObvAppInboxDatabase


final class StoreOrReplaceMessageIdentifierForLaterOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let messageUIDFromEngine: UID
    private let messageUploadTimestampFromServer: Date
    private let expected: WhatIsExpected
    
    enum WhatIsExpected {
        case discussion(identifierOfExpectedDiscussion: ObvDiscussionIdentifier)
        case contactInGroup(identifierOfExpectedGroup: ObvGroupIdentifier, cryptoIdOfExpectedContact: ObvCryptoId)
        case message(messageIdentifier: ObvMessageAppIdentifier)
    }
        
    init(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, expected: WhatIsExpected) {
        self.messageUIDFromEngine = messageUIDFromEngine
        self.messageUploadTimestampFromServer = messageUploadTimestampFromServer
        self.expected = expected
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            switch expected {
            case .discussion(let identifierOfExpectedDiscussion):
                switch identifierOfExpectedDiscussion {
                case .oneToOne(let id):
                    try MessageIdentifierForLaterExpectingDiscussionOneToOne.createOrReplace(
                        messageUIDFromEngine: messageUIDFromEngine,
                        messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                        contactIdentifier: id,
                        within: obvContext.context)
                case .groupV1(let obvGroupV1Identifier):
                    try MessageIdentifierForLaterExpectingDiscussionGroupV1.createOrReplace(
                        messageUIDFromEngine: messageUIDFromEngine,
                        messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                        groupV1Identifier: obvGroupV1Identifier,
                        within: obvContext.context)
                case .groupV2(let obvGroupV2Identifier):
                    try MessageIdentifierForLaterExpectingDiscussionGroupV2.createOrReplace(
                        messageUIDFromEngine: messageUIDFromEngine,
                        messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                        groupV2Identifier: obvGroupV2Identifier,
                        within: obvContext.context)
                }
            case .contactInGroup(identifierOfExpectedGroup: let identifierOfExpectedGroup, cryptoIdOfExpectedContact: let cryptoIdOfExpectedContact):
                switch identifierOfExpectedGroup {
                case .groupV1(let obvGroupV1Identifier):
                    try MessageIdentifierForLaterExpectingContactInGroupV1.createOrReplace(
                        messageUIDFromEngine: messageUIDFromEngine,
                        messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                        groupV1Identifier: obvGroupV1Identifier,
                        contactCryptoId: cryptoIdOfExpectedContact,
                        within: obvContext.context)
                case .groupV2(let obvGroupV2Identifier):
                    try MessageIdentifierForLaterExpectingContactInGroupV2.createOrReplace(
                        messageUIDFromEngine: messageUIDFromEngine,
                        messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                        groupV2Identifier: obvGroupV2Identifier,
                        contactCryptoId: cryptoIdOfExpectedContact,
                        within: obvContext.context)
                }
            case .message(messageIdentifier: let messageIdentifier):
                switch messageIdentifier {
                case .sent(let discussionIdentifier, let senderThreadIdentifier, let senderSequenceNumber):
                    switch discussionIdentifier {
                    case .oneToOne(let id):
                        try MessageIdentifierForLaterExpectingSentMessageInOneToOneDiscussion.createOrReplace(
                            messageUIDFromEngine: messageUIDFromEngine,
                            messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                            discussionId: id,
                            sentMessageId: (senderThreadIdentifier, senderSequenceNumber),
                            within: obvContext.context)
                    case .groupV1(let id):
                        try MessageIdentifierForLaterExpectingSentMessageInGroupV1Discussion.createOrReplace(
                            messageUIDFromEngine: messageUIDFromEngine,
                            messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                            discussionId: id,
                            sentMessageId: (senderThreadIdentifier, senderSequenceNumber),
                            within: obvContext.context)
                    case .groupV2(let id):
                        try MessageIdentifierForLaterExpectingSentMessageInGroupV2Discussion.createOrReplace(
                            messageUIDFromEngine: messageUIDFromEngine,
                            messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                            discussionId: id,
                            sentMessageId: (senderThreadIdentifier, senderSequenceNumber),
                            within: obvContext.context)
                    }
                case .received(let discussionIdentifier, let senderIdentifier, let senderThreadIdentifier, let senderSequenceNumber):
                    switch discussionIdentifier {
                    case .oneToOne(let id):
                        try MessageIdentifierForLaterExpectingReceivedMessageInOneToOneDiscussion.createOrReplace(
                            messageUIDFromEngine: messageUIDFromEngine,
                            messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                            discussionId: id,
                            receivedMessageId: (senderThreadIdentifier, senderSequenceNumber, senderIdentifier),
                            within: obvContext.context)
                    case .groupV1(let id):
                        try MessageIdentifierForLaterExpectingReceivedMessageInGroupV1Discussion.createOrReplace(
                            messageUIDFromEngine: messageUIDFromEngine,
                            messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                            discussionId: id,
                            receivedMessageId: (senderThreadIdentifier, senderSequenceNumber, senderIdentifier),
                            within: obvContext.context)
                    case .groupV2(let id):
                        try MessageIdentifierForLaterExpectingReceivedMessageInGroupV2Discussion.createOrReplace(
                            messageUIDFromEngine: messageUIDFromEngine,
                            messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                            discussionId: id,
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
