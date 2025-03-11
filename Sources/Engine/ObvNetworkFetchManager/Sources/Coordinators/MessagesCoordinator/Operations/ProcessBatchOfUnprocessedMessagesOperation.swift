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


final class ProcessBatchOfUnprocessedMessagesOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
        
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
        case messageReceivedOnWebSocket(idOfMessageToProcess: ObvMessageIdentifier)
        case oneSliceOfListOfDownloadedMessagesWasSaved(idsOfMessagesToProcess: [ObvMessageIdentifier])
        case truncatedListPerformed
        case untruncatedListPerformed(downloadTimestampFromServer: Date)
        case removedExpectedContactOfPreKeyMessage
    }
    
    let ownedCryptoIdentity: ObvCryptoIdentity
    private let debugUuid = UUID()
    private let notificationDelegate: ObvNotificationDelegate
    private let processDownloadedMessageDelegate: ObvProcessDownloadedMessageDelegate
    private let inbox: URL // For attachments
    private let logger: Logger
    private let flowId: FlowIdentifier
    let executionReason: ExecutionReason
    
    /// After the execution of this operation, we will have other tasks to perform.
    enum PostOperationTaskToPerform: Hashable, Comparable {
        
        case processInboxAttachmentsOfMessage(messageId: ObvMessageIdentifier)
        case downloadExtendedPayload(messageId: ObvMessageIdentifier)
        case notifyAboutDecryptedApplicationMessage(messages: [ObvMessageOrObvOwnedMessage], flowId: FlowIdentifier)
        case batchDeleteAndMarkAsListed(ownedCryptoIdentity: ObvCryptoIdentity)
        
        /// When the `PostOperationTaskToPerform` values will be performed, this will be in order (0 first).
        private var executionOrder: Int {
            switch self {
            case .batchDeleteAndMarkAsListed: return 0
            case .notifyAboutDecryptedApplicationMessage: return 1
            case .downloadExtendedPayload: return 2 // Note that we notify the app before trying to download the extended payload
            case .processInboxAttachmentsOfMessage: return 3
            }
        }
        
        /// The post operation tasks to perform will be performed in order. Note that we notify the app about decrypted message in the appropriate order.
        static func < (lhs: PostOperationTaskToPerform, rhs: PostOperationTaskToPerform) -> Bool {
            return lhs.executionOrder < rhs.executionOrder
        }

    }
    
    private(set) var postOperationTasksToPerform = Set<PostOperationTaskToPerform>()
    private(set) var moreUnprocessedMessagesRemain: Bool? // If the operation finishes without canceling, this is guaranteed to be set
    
    init(ownedCryptoIdentity: ObvCryptoIdentity, executionReason: ExecutionReason, notificationDelegate: ObvNotificationDelegate, processDownloadedMessageDelegate: ObvProcessDownloadedMessageDelegate, inbox: URL, logger: Logger, flowId: FlowIdentifier) {
        self.ownedCryptoIdentity = ownedCryptoIdentity
        self.notificationDelegate = notificationDelegate
        self.processDownloadedMessageDelegate = processDownloadedMessageDelegate
        self.inbox = inbox
        self.logger = logger
        self.flowId = flowId
        self.executionReason = executionReason
        super.init()
    }
    
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        let debugUuidDescription = debugUuid.debugDescription
        let flowIdDescription = flowId.shortDebugDescription
        logger.info("[\(flowIdDescription)] 🔑 Starting ProcessBatchOfUnprocessedMessagesOperation \(debugUuidDescription)")
        defer {
            if !isCancelled && moreUnprocessedMessagesRemain == nil {
                assertionFailure()
            }
            logger.info("[\(flowIdDescription)] 🔑 Ending ProcessBatchOfUnprocessedMessagesOperation \(debugUuidDescription)")
        }
                
        do {
            
            // Find all inbox messages that still need to be processed
            
            let messages: [InboxMessage]
            switch executionReason {
            case .truncatedListPerformed,
                    .untruncatedListPerformed,
                    .removedExpectedContactOfPreKeyMessage:
                moreUnprocessedMessagesRemain = true
                messages = try InboxMessage.getBatchOfProcessableMessages(ownedCryptoIdentity: ownedCryptoIdentity, fetchLimit: ObvNetworkFetchDelegateManager.batchSize, within: obvContext)
            case .oneSliceOfListOfDownloadedMessagesWasSaved(idsOfMessagesToProcess: let idsOfMessagesToProcess):
                messages = try InboxMessage.getBatchOfProcessableMessages(restrictTo: idsOfMessagesToProcess, within: obvContext)
            case .messageReceivedOnWebSocket(idOfMessageToProcess: let idOfMessageToProcess):
                messages = try InboxMessage.getBatchOfProcessableMessages(restrictTo: [idOfMessageToProcess], within: obvContext)
            }

            // If there is no message to process, return
            
            guard !messages.isEmpty else {
                
                // On rare occasions, we might have processed application messages that still need to be marked as listed on the server (this may happen since the `batchDeleteAndMarkAsListed`
                // post-operation is not atomic with the processing of the message).
                
                postOperationTasksToPerform.insert(.batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity))
                
                logger.info("[\(flowIdDescription)] 🔑 No unprocessed message found in the inbox (we will execute a batchDeleteAndMarkAsListed)")

                moreUnprocessedMessagesRemain = false
                return
                
            }

            // We have at least one message to process.
            // Determine de best default value for `moreUnprocessedMessagesRemain`
            
            switch executionReason {
            case .messageReceivedOnWebSocket,
                    .truncatedListPerformed,
                    .untruncatedListPerformed,
                    .removedExpectedContactOfPreKeyMessage:
                moreUnprocessedMessagesRemain = true
            case .oneSliceOfListOfDownloadedMessagesWasSaved:
                moreUnprocessedMessagesRemain = false
            }
            
            for message in messages {
                logger.info("[\(flowIdDescription)] 🔑 Will process message \(message.messageId.debugDescription)")
                assert(message.extendedMessagePayloadKey == nil)
                assert(message.messagePayload == nil)
                assert(!message.markedForDeletion)
            }
            
            // We then create the appropriate struct that is appropriate to pass each message to our delegate (i.e., the channel manager).
            
            let networkReceivedEncryptedMessages: [ObvNetworkReceivedMessageEncrypted] = messages.compactMap {
                guard let inboxMessageId = $0.messageId else { assertionFailure(); return nil }
                guard let encryptedContent = $0.encryptedContent else { assertionFailure(); return nil }
                guard let wrappedKey = $0.wrappedKey else { assertionFailure(); return nil }
                return ObvNetworkReceivedMessageEncrypted(
                    messageId: inboxMessageId,
                    messageUploadTimestampFromServer: $0.messageUploadTimestampFromServer,
                    downloadTimestampFromServer: $0.downloadTimestampFromServer,
                    localDownloadTimestamp: $0.localDownloadTimestamp,
                    encryptedContent: encryptedContent,
                    wrappedKey: wrappedKey,
                    knownAttachmentCount: $0.attachments.count,
                    availableEncryptedExtendedContent: nil) // The encrypted extended content is not available yet
            }
            
            // We ask our delegate to process these messages
            
            let results = try processDownloadedMessageDelegate.processNetworkReceivedEncryptedMessages(Set(networkReceivedEncryptedMessages), within: obvContext)
            
            assert(results.count == networkReceivedEncryptedMessages.count)
            
            // Update this network manager's databases depending on the result for each message.
            // Note that this allows to have to have atomicity between the changes made in the channel manager and the changes made here
            
            var messagesToNotify = [ObvMessageOrObvOwnedMessage]()
            
            for result in results {
                
                switch result {
                    
                case .noKeyAllowedToDecrypt(messageId: let messageId):

                    //
                    // Result case 1: No key allowed to decrypt the message
                    //

                    // We could not find a key to decrypt the message header. Depending on the `ExecutionReason` of this operation,
                    // we either keep the message for later or mark it for deletion.
                    
                    switch executionReason {
                        
                    case .oneSliceOfListOfDownloadedMessagesWasSaved:

                        break
                        
                    case .messageReceivedOnWebSocket:
                        
                        // Prevent the immediate re-execution of this operation. We want to wait for an untrucated listing.
                        moreUnprocessedMessagesRemain = false

                    case .truncatedListPerformed, .removedExpectedContactOfPreKeyMessage:
                        
                        // Prevent the immediate re-execution of this operation. We want to wait for an untrucated listing.
                        moreUnprocessedMessagesRemain = false

                    case .untruncatedListPerformed:
                        
                        // We know we will never be able to decrypt this message, we mark it for deletion (together with its attachments)
                        // to make sure the next batch deletion does delete it for good.
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
                    
                    //
                    // Result case 2
                    //

                    try InboxMessage.markMessageAndAttachmentsForDeletion(messageId: messageId, within: obvContext)
                    postOperationTasksToPerform.insert(.batchDeleteAndMarkAsListed(ownedCryptoIdentity: ownedCryptoIdentity))

                case .remoteIdentityToSetOnReceivedMessage(messageId: let messageId, remoteCryptoIdentity: let remoteCryptoIdentity, remoteDeviceUID: let remoteDeviceUID, messagePayload: let messagePayload, extendedMessagePayloadKey: let extendedMessagePayloadKey, attachmentsInfos: let attachmentsInfos):
                    
                    //
                    // Result case 3
                    //

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
                                                           remoteDeviceUID: remoteDeviceUID,
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
                        
                        guard let obvMessageOrObvOwnedMessage = inboxMessage.getObvMessageOrObvOwnedMessage(inbox: inbox) else {
                            assertionFailure()
                            continue
                        }
                        
                        messagesToNotify.append(obvMessageOrObvOwnedMessage)
                        //postOperationTasksToPerform.insert(.notifyAboutDecryptedApplicationMessage(message: obvMessageOrObvOwnedMessage, flowId: flowId))
                        
                    }
                    
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
                    
                    //
                    // Result case 4
                    //

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
            
            if !messagesToNotify.isEmpty {
                let sortedMessages = messagesToNotify.sorted(by: { $0.messageUploadTimestampFromServer < $1.messageUploadTimestampFromServer })
                postOperationTasksToPerform.insert(.notifyAboutDecryptedApplicationMessage(messages: sortedMessages, flowId: flowId))
            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
