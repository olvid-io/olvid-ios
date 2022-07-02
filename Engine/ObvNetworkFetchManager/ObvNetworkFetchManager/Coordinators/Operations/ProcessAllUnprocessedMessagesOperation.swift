/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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


final class ProcessAllUnprocessedMessagesOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    
    private let debugUuid = UUID()
    private let queueForPostingNotifications: DispatchQueue
    private let notificationDelegate: ObvNotificationDelegate
    private let processDownloadedMessageDelegate: ObvProcessDownloadedMessageDelegate
    private let log: OSLog
    
    
    init(queueForPostingNotifications: DispatchQueue, notificationDelegate: ObvNotificationDelegate, processDownloadedMessageDelegate: ObvProcessDownloadedMessageDelegate, log: OSLog) {
        self.queueForPostingNotifications = queueForPostingNotifications
        self.notificationDelegate = notificationDelegate
        self.processDownloadedMessageDelegate = processDownloadedMessageDelegate
        self.log = log
        super.init()
    }
    
    
    override func main() {
        
        os_log("🔑 Starting ProcessAllUnprocessedMessagesOperation %{public}@", log: log, type: .info, debugUuid.debugDescription)
        defer { os_log("🔑 Ending ProcessAllUnprocessedMessagesOperation %{public}@", log: log, type: .info, debugUuid.debugDescription) }
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        do {
            
            try obvContext.performAndWaitOrThrow {
                
                // Find all inbox messages that still need to be processed
                
                let messages = try InboxMessage.getAllUnprocessedMessages(within: obvContext)
                
                guard !messages.isEmpty else {
                    ObvNetworkFetchNotificationNew.noInboxMessageToProcess(flowId: obvContext.flowId)
                        .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)
                    return
                }
                
                for message in messages {
                    os_log("🔑 Will process message %{public}@", log: log, type: .info, message.messageId.debugDescription)
                    assert(message.extendedMessagePayloadKey == nil)
                    assert(message.messagePayload == nil)
                    assert(!message.markedForDeletion)
                }
                
                // If we reach this point, we have at least one message to process.
                // We notify about this.

                for message in messages {
                    ObvNetworkFetchNotificationNew.newInboxMessageToProcess(messageId: message.messageId, attachmentIds: message.attachmentIds, flowId: obvContext.flowId)
                        .postOnBackgroundQueue(queueForPostingNotifications, within: notificationDelegate)
                }
                
                // We then create the appropriate struct that is appropriate to pass each message to our delegate (i.e., the channel manager).
                
                let networkReceivedEncryptedMessages = Set(messages.map {
                    ObvNetworkReceivedMessageEncrypted(
                        messageId: $0.messageId,
                        messageUploadTimestampFromServer: $0.messageUploadTimestampFromServer,
                        downloadTimestampFromServer: $0.downloadTimestampFromServer,
                        localDownloadTimestamp: $0.localDownloadTimestamp,
                        encryptedContent: $0.encryptedContent,
                        wrappedKey: $0.wrappedKey,
                        attachmentCount: $0.attachments.count,
                        hasEncryptedExtendedMessagePayload: $0.hasEncryptedExtendedMessagePayload)
                })
                
                // We ask our delegate to process these messages

                processDownloadedMessageDelegate.processNetworkReceivedEncryptedMessages(networkReceivedEncryptedMessages, within: obvContext)

            }
            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
