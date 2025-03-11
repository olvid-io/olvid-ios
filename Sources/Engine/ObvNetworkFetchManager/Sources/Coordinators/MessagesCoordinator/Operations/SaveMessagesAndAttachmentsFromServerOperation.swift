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
import os.log
import OlvidUtils
import CoreData
import ObvTypes
import ObvServerInterface
import ObvCrypto



final class SaveMessagesAndAttachmentsFromServerOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let ownedIdentity: ObvCryptoIdentity
    private let listOfMessageAndAttachmentsOnServer: [ObvServerDownloadMessagesAndListAttachmentsMethod.MessageAndAttachmentsOnServer]
    private let downloadTimestampFromServer: Date
    private let localDownloadTimestamp: Date
    private let logger: Logger
    private let flowId: FlowIdentifier
    
    init(ownedIdentity: ObvCryptoIdentity, listOfMessageAndAttachmentsOnServer: [ObvServerDownloadMessagesAndListAttachmentsMethod.MessageAndAttachmentsOnServer], downloadTimestampFromServer: Date, localDownloadTimestamp: Date, logger: Logger, flowId: FlowIdentifier) {
        self.ownedIdentity = ownedIdentity
        self.listOfMessageAndAttachmentsOnServer = listOfMessageAndAttachmentsOnServer
        self.downloadTimestampFromServer = downloadTimestampFromServer
        self.localDownloadTimestamp = localDownloadTimestamp
        self.logger = logger
        self.flowId = flowId
        super.init()
    }
    
    private(set) var idsOfMessagesToProcess = [ObvMessageIdentifier]()

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        let flowIdDescription = flowId.shortDebugDescription
        let ownedIdentityDescription = ownedIdentity.debugDescription
        
        do {
            
            for messageAndAttachmentsOnServer in listOfMessageAndAttachmentsOnServer {
                
                let messageId = ObvMessageIdentifier(ownedCryptoIdentity: ownedIdentity, uid: messageAndAttachmentsOnServer.messageUidFromServer)
                
                // Check that the message does not already exist in DB. If it exists, add it to the list of messages to process if required
                
                if try InboxMessage.get(messageId: messageId, within: obvContext) != nil {
                    
                    if try InboxMessage.getProcessableMessage(messageIdentifier: messageId, within: obvContext) != nil {
                        idsOfMessagesToProcess.append(messageId)
                    }
                    
                } else {
                    
                    // If we reach this point, the message is actually new
                    
                    let message: InboxMessage
                    do {
                        let messageIdDebugDescription = messageId.debugDescription
                        logger.info("[\(flowIdDescription)] Trying yo insert InboxMessage for identity \(ownedIdentityDescription): \(messageIdDebugDescription)")
                        message = try InboxMessage(
                            messageId: messageId,
                            encryptedContent: messageAndAttachmentsOnServer.encryptedContent,
                            hasEncryptedExtendedMessagePayload: messageAndAttachmentsOnServer.hasEncryptedExtendedMessagePayload,
                            wrappedKey: messageAndAttachmentsOnServer.wrappedKey,
                            messageUploadTimestampFromServer: messageAndAttachmentsOnServer.messageUploadTimestampFromServer,
                            downloadTimestampFromServer: downloadTimestampFromServer,
                            localDownloadTimestamp: localDownloadTimestamp,
                            within: obvContext)
                    } catch {
                        guard let inboxMessageError = error as? InboxMessage.InternalError else {
                            logger.fault("[\(flowIdDescription)] Could not insert message in DB for identity \(ownedIdentityDescription) for some unknown reason.")
                            assertionFailure()
                            continue
                        }
                        switch inboxMessageError {
                        case .aMessageWithTheSameMessageIdAlreadyExists:
                            logger.fault("[\(flowIdDescription)] Could not insert message in DB for identity \(ownedIdentityDescription): \(inboxMessageError.localizedDescription)")
                            assertionFailure()
                            continue
                        case .tryingToInsertAMessageThatWasAlreadyDeleted:
                            // This can happen
                            logger.error("[\(flowIdDescription)] Could not insert message in DB for identity \(ownedIdentityDescription): \(inboxMessageError.localizedDescription)")
                            continue
                        }
                    }
                    
                    for attachmentOnServer in messageAndAttachmentsOnServer.attachments {
                        guard let inboxAttachment = try? InboxAttachment(message: message,
                                                                         attachmentNumber: attachmentOnServer.attachmentNumber,
                                                                         byteCountToDownload: attachmentOnServer.expectedLength,
                                                                         expectedChunkLength: attachmentOnServer.expectedChunkLength,
                                                                         within: obvContext)
                        else {
                            logger.fault("[\(flowIdDescription)] Could not insert attachment in DB for identity \(ownedIdentityDescription)")
                            continue
                        }
                        
                        // For now, we make sure that none of the signed URL is nil before setting them on the new InboxAttachment. This may change in the future.
                        // If one of the signed URL is nil, we mark the attachment for deletion.
                        if let chunkDownloadSignedUrls = attachmentOnServer.chunkDownloadPrivateUrls as? [URL], !chunkDownloadSignedUrls.isEmpty {
                            do {
                                try inboxAttachment.setChunksSignedURLs(chunkDownloadSignedUrls)
                            } catch {
                                logger.error("[\(flowIdDescription)] We could not set the chunk download private URLs. We mark it cancelled by the server")
                                inboxAttachment.markAsCancelledByServer()
                            }
                        } else {
                            logger.info("[\(flowIdDescription)] Attachment \(inboxAttachment.debugDescription) has a nil chunk URL. It was cancelled by the server.")
                            inboxAttachment.markAsCancelledByServer()
                        }
                        
                    }
                    
                    idsOfMessagesToProcess.append(messageId)

                }
                
                
                
            }

            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
