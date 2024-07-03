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
import OlvidUtils
import ObvMetaManager
import os.log
import ObvCrypto
import CoreData
import ObvTypes


final class ProcessBatchOfUnprocessedMessagesOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private static let batchSize = 10
    
    /// This operation can be executed for one of the reasons specified by this enum.
    /// Depending on the reason, we might decide *not* to mark the message for deletion in case we were not able to
    /// decrypt it.
    ///
    /// ## Description of the problem solved by not always deleting messages that could not be decrypted
    ///
    /// Assume we always mark for deletion the messages that cannot be decrypted.
    /// Assume that we have many pending messages on the server. While we are downloading these messages and catching up, we may receive a WebSocket message that we are not yet able to decrypt, as
    /// the ratcheting has yet to reach the corresponding decryption key. Assume we receive a lot of these WebSocket messages (like, more than the number of keys in a provision) and that we delete them all.
    /// Once all the normaly-listed messages are processed, the decryption keys for the (now deleted) WebSocket messages are available. Those keys won't be used, as the corresponding messages do not exist
    /// anymore. Any newly downloaded message won't decrypt either, since the channel manager has no reason to go forward with the ratcheting (it expects the messages that we deleted). We end-up with a secure
    /// channel that is "broken" in reception.
    ///
    /// To fix this issue, we don't mark for deletion messages that cannot be decrypted if :
    /// - they were downloaded through the WebSocket;
    /// - they were downloaded using the standard list method, in case the server indicated that the list is truncated.
    enum ExecutionReason {
        case messageReceivedOnWebSocket
        case truncatedListPerformed
        case untruncatedListPerformed(downloadTimestampFromServer: Date)
        case removedExpectedContactOfPreKeyMessage
    }
    
    private let ownedCryptoIdentity: ObvCryptoIdentity
    private let debugUuid = UUID()
    private let queueForPostingNotifications: DispatchQueue
    private let notificationDelegate: ObvNotificationDelegate
    private let processDownloadedMessageDelegate: ObvProcessDownloadedMessageDelegate
    private let inbox: URL // For attachments
    private let log: OSLog
    private let flowId: FlowIdentifier
    private let executionReason: ExecutionReason
    
    /// After the execution of this operation, we will have other tasks to perform.
    enum PostOperationTaskToPerform: Hashable, Comparable {
        
        case processInboxAttachmentsOfMessage(messageId: ObvMessageIdentifier)
        case downloadExtendedPayload(messageId: ObvMessageIdentifier)
        case notifyAboutDecryptedApplicationMessage(messageId: ObvMessageIdentifier, attachmentIds: [ObvAttachmentIdentifier], hasEncryptedExtendedMessagePayload: Bool, uploadTimestampFromServer: Date, flowId: FlowIdentifier)
        case batchDeleteAndMarkAsListed(ownedCryptoIdentity: ObvCryptoIdentity)
        case downloadMessagesAndListAttachments(ownedCryptoIdentity: ObvCryptoIdentity)
        
        /// When the `PostOperationTaskToPerform` values will be performed, this will be in order (0 first).
        private var executionOrder: Int {
            switch self {
            case .batchDeleteAndMarkAsListed: return 0
            case .notifyAboutDecryptedApplicationMessage: return 1
            case .downloadExtendedPayload: return 2 // Note that we notify the app before trying to download the extended payload
            case .processInboxAttachmentsOfMessage: return 3
            case .downloadMessagesAndListAttachments: return 4
            }
        }
        
        /// The post operation tasks to perform will be performed in order. Note that we notify the app about decrypted message in the appropriate order.
        static func < (lhs: PostOperationTaskToPerform, rhs: PostOperationTaskToPerform) -> Bool {
            switch (lhs, rhs) {
            case let(.notifyAboutDecryptedApplicationMessage(messageId: _, attachmentIds: _, hasEncryptedExtendedMessagePayload: _, uploadTimestampFromServer: lhsDate, flowId: _),
                     .notifyAboutDecryptedApplicationMessage(messageId: _, attachmentIds: _, hasEncryptedExtendedMessagePayload: _, uploadTimestampFromServer: rhsDate, flowId: _)):
                return lhsDate < rhsDate
            default:
                return lhs.executionOrder < rhs.executionOrder
            }
        }

    }
    
    private(set) var postOperationTasksToPerform = Set<PostOperationTaskToPerform>()
    private(set) var moreUnprocessedMessagesRemain: Bool? // If the operation finishes without canceling, this is guaranteed to be set
    
    init(ownedCryptoIdentity: ObvCryptoIdentity, executionReason: ExecutionReason, queueForPostingNotifications: DispatchQueue, notificationDelegate: ObvNotificationDelegate, processDownloadedMessageDelegate: ObvProcessDownloadedMessageDelegate, inbox: URL, log: OSLog, flowId: FlowIdentifier) {
        self.ownedCryptoIdentity = ownedCryptoIdentity
        self.queueForPostingNotifications = queueForPostingNotifications
        self.notificationDelegate = notificationDelegate
        self.processDownloadedMessageDelegate = processDownloadedMessageDelegate
        self.inbox = inbox
        self.log = log
        self.flowId = flowId
        self.executionReason = executionReason
        super.init()
    }
    
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        os_log("[%{public}@] 🔑 Starting ProcessBatchOfUnprocessedMessagesOperation %{public}@", log: log, type: .info, flowId.shortDebugDescription, debugUuid.debugDescription)
        defer {
            if !isCancelled && moreUnprocessedMessagesRemain == nil {
                assertionFailure()
            }
            os_log("[%{public}@] 🔑 Ending ProcessBatchOfUnprocessedMessagesOperation %{public}@", log: log, type: .info, flowId.shortDebugDescription, debugUuid.debugDescription)
        }
                
        do {
            
            // Find all inbox messages that still need to be processed
            
            let messages = try InboxMessage.getBatchOfProcessableMessages(ownedCryptoIdentity: ownedCryptoIdentity, fetchLimit: Self.batchSize, within: obvContext)
            
            guard !messages.isEmpty else {
                
                // On rare occasions, we might have processed application messages that still need to be marked as listed on the server (this may happen since the `batchDeleteAndMarkAsListed`
                // post-operation is not atomic with the processing of the message).
                
                postOperationTasksToPerform.insert(.batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity))
                
                os_log("[%{public}@] 🔑 No unprocessed message found in the inbox (we will execute a batchDeleteAndMarkAsListed)", log: log, type: .info, flowId.shortDebugDescription)

                moreUnprocessedMessagesRemain = false
                return
                
            }
            
            moreUnprocessedMessagesRemain = true
            
            for message in messages {
                os_log("🔑 Will process message %{public}@", log: log, type: .info, message.messageId.debugDescription)
                assert(message.extendedMessagePayloadKey == nil)
                assert(message.messagePayload == nil)
                assert(!message.markedForDeletion)
            }
            
            // We then create the appropriate struct that is appropriate to pass each message to our delegate (i.e., the channel manager).
            
            let networkReceivedEncryptedMessages: [ObvNetworkReceivedMessageEncrypted] = messages.compactMap {
                guard let inboxMessageId = $0.messageId else { assertionFailure(); return nil }
                return ObvNetworkReceivedMessageEncrypted(
                    messageId: inboxMessageId,
                    messageUploadTimestampFromServer: $0.messageUploadTimestampFromServer,
                    downloadTimestampFromServer: $0.downloadTimestampFromServer,
                    localDownloadTimestamp: $0.localDownloadTimestamp,
                    encryptedContent: $0.encryptedContent,
                    wrappedKey: $0.wrappedKey,
                    knownAttachmentCount: $0.attachments.count,
                    availableEncryptedExtendedContent: nil) // The encrypted extended content is not available yet
            }
            
            // We ask our delegate to process these messages
            
            let results = try processDownloadedMessageDelegate.processNetworkReceivedEncryptedMessages(Set(networkReceivedEncryptedMessages), within: obvContext)
            
            assert(results.count == networkReceivedEncryptedMessages.count)
            
            // Update this network manager's databases depending on the result for each message.
            // Note that this allows to have to have atomicity between the changes made in the channel manager and the changes made here
            
            for result in results {
                switch result {
                    
                case .noKeyAllowedToDecrypt(messageId: let messageId):
                    
                    // We could not find a key to decrypt the message header. Depending on the `ExecutionReason` of this operation,
                    // we either keep the message for later or mark it for deletion.
                    
                    switch executionReason {
                        
                    case .messageReceivedOnWebSocket, .truncatedListPerformed, .removedExpectedContactOfPreKeyMessage:
                        
                        // Prevent the immediate re-execution of this operation. We want to wait for an untrucated listing.
                        moreUnprocessedMessagesRemain = false
                        // Make sure a list is performed. Eventually, it won't be truncated.
                        postOperationTasksToPerform.insert(.downloadMessagesAndListAttachments(ownedCryptoIdentity: ownedCryptoIdentity))
                        // Make sure we don't list this message endlessly by marking it as listed on server
                        postOperationTasksToPerform.insert(.batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity))

                    case .untruncatedListPerformed:
                        
                        try InboxMessage.markMessageAndAttachmentsForDeletion(messageId: messageId, within: obvContext)
                        postOperationTasksToPerform.insert(.batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity))
                        
                    }
                    
                case .protocolMessageWasProcessed(let messageId),
                        .couldNotDecryptOrParse(let messageId),
                        .protocolManagerFailedToProcessMessage(let messageId),
                        .protocolMessageCouldNotBeParsed(let messageId),
                        .invalidAttachmentCountOfApplicationMessage(let messageId),
                        .applicationMessageCouldNotBeParsed(let messageId),
                        .unexpectedMessageType(let messageId),
                        .messageKeyDoesNotSupportGKMV2AlthoughItShould(messageId: let messageId),
                        .messageReceivedFromContactThatIsRevokedAsCompromised(messageId: let messageId):
                    
                    try InboxMessage.markMessageAndAttachmentsForDeletion(messageId: messageId, within: obvContext)
                    postOperationTasksToPerform.insert(.batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity))

                case .remoteIdentityToSetOnReceivedMessage(let messageId, let remoteCryptoIdentity, let messagePayload, let extendedMessagePayloadKey, let attachmentsInfos):
                    
                    guard let inboxMessage = try InboxMessage.get(messageId: messageId, within: obvContext) else {
                        assertionFailure()
                        continue
                    }
                    
                    guard inboxMessage.attachments.count == attachmentsInfos.count else {
                        assertionFailure()
                        try InboxMessage.markMessageAndAttachmentsForDeletion(messageId: messageId, within: obvContext)
                        postOperationTasksToPerform.insert(.batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity))
                        continue
                    }
                    
                    try inboxMessage.setFromCryptoIdentity(remoteCryptoIdentity,
                                                           andMessagePayload: messagePayload,
                                                           extendedMessagePayloadKey: extendedMessagePayloadKey)
                    
                    for inboxMessageAttachment in inboxMessage.attachments {
                        guard inboxMessageAttachment.attachmentNumber >= 0 && inboxMessageAttachment.attachmentNumber < attachmentsInfos.count else {
                            assertionFailure()
                            continue
                        }
                        let attachmentInfos = attachmentsInfos[inboxMessageAttachment.attachmentNumber]
                        try inboxMessageAttachment.set(decryptionKey: attachmentInfos.key,
                                                       metadata: attachmentInfos.metadata,
                                                       inbox: inbox)
                    }
                    
                    // Compute all the appropriate `PostOperationTaskToPerform`s to perform
                    
                    do {
                        let hasEncryptedExtendedMessagePayload = inboxMessage.hasEncryptedExtendedMessagePayload && (extendedMessagePayloadKey != nil)
                        postOperationTasksToPerform.insert(.notifyAboutDecryptedApplicationMessage(
                            messageId: messageId,
                            attachmentIds: inboxMessage.attachmentIds,
                            hasEncryptedExtendedMessagePayload: hasEncryptedExtendedMessagePayload,
                            uploadTimestampFromServer: inboxMessage.messageUploadTimestampFromServer,
                            flowId: obvContext.flowId))
                    }
                    
                    // Since we set the "from" identity of this application message, we can mark it as listed on the server.
                    // We used to do this only in the case where the message had attachments. We don't do that anymore as this can
                    // introduce a bug when receiving more than 1'000 messages in a group that we just left (in that case,
                    // the app waits some time, hopping that the group will be created and thus, those messages are listed each time we list
                    // messages on the server, preventing new messages to be listed).
                    postOperationTasksToPerform.insert(.batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity))
                    
                    // We have set all the elements allowing the attachments to be downloaded.
                    // So we process all the attachment in case the context saves successfully
                    
                    if !inboxMessage.attachments.isEmpty {
                        postOperationTasksToPerform.insert(.processInboxAttachmentsOfMessage(messageId: messageId))
                    }
                                        
                    // If the message has an encrypted payload to download, we ask for the download
                    if inboxMessage.hasEncryptedExtendedMessagePayload && extendedMessagePayloadKey != nil {
                        postOperationTasksToPerform.insert(.downloadExtendedPayload(messageId: messageId))
                    }

                case .unwrapSucceededButRemoteCryptoIdIsUnknown(messageId: let messageId, remoteCryptoIdentity: let remoteCryptoIdentity):
                    
                    // This happens only when receiving a message sent through a PreKey channel. In that case, we might
                    // receive a message from a remote identity that is not a contact already (but who is likely to become one soon).
                    // In that case, we keep the message for later processing, when the remote identity becomes a contact.
                    
                    guard let inboxMessage = try InboxMessage.get(messageId: messageId, within: obvContext) else {
                        assertionFailure()
                        continue
                    }

                    inboxMessage.unwrapSucceededButRemoteCryptoIdIsUnknown(remoteCryptoIdentity: remoteCryptoIdentity)
                    
                }
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
