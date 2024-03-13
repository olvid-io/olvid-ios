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
import os.log
import OlvidUtils
import CoreData
import ObvTypes
import ObvServerInterface
import ObvCrypto



final class SaveMessagesAndAttachmentsFromServerOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel> {
    
    private let ownedIdentity: ObvCryptoIdentity
    private let listOfMessageAndAttachmentsOnServer: [ObvServerDownloadMessagesAndListAttachmentsMethod.MessageAndAttachmentsOnServer]
    private let downloadTimestampFromServer: Date
    private let localDownloadTimestamp: Date
    private let log: OSLog
    
    init(ownedIdentity: ObvCryptoIdentity, listOfMessageAndAttachmentsOnServer: [ObvServerDownloadMessagesAndListAttachmentsMethod.MessageAndAttachmentsOnServer], downloadTimestampFromServer: Date, localDownloadTimestamp: Date, log: OSLog, idsOfNewMessages: [ObvMessageIdentifier] = [ObvMessageIdentifier]()) {
        self.ownedIdentity = ownedIdentity
        self.listOfMessageAndAttachmentsOnServer = listOfMessageAndAttachmentsOnServer
        self.downloadTimestampFromServer = downloadTimestampFromServer
        self.localDownloadTimestamp = localDownloadTimestamp
        self.log = log
        self.idsOfNewMessages = idsOfNewMessages
        super.init()
    }
    
    private(set) var idsOfNewMessages = [ObvMessageIdentifier]()

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            for messageAndAttachmentsOnServer in listOfMessageAndAttachmentsOnServer {
                
                let messageId = ObvMessageIdentifier(ownedCryptoIdentity: ownedIdentity, uid: messageAndAttachmentsOnServer.messageUidFromServer)
                
                // Check that the message does not already exist in DB
                guard try InboxMessage.get(messageId: messageId, within: obvContext) == nil else { continue }
                
                // Check that the message was not recently deleted from DB
                guard try PendingDeleteFromServer.get(messageId: messageId, within: obvContext) == nil else { continue }
                
                // If we reach this point, the message is actually new
                
                let message: InboxMessage
                do {
                    os_log("Trying yo insert InboxMessage for identity %{public}@: %{public}@", log: log, type: .info, ownedIdentity.debugDescription, messageId.debugDescription)
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
                        os_log("Could not insert message in DB for identity %{public}@ for some unknown reason.", log: log, type: .fault, ownedIdentity.debugDescription)
                        assertionFailure()
                        continue
                    }
                    switch inboxMessageError {
                    case .aMessageWithTheSameMessageIdAlreadyExists:
                        os_log("Could not insert message in DB for identity %{public}@: %{public}@", log: log, type: .fault, ownedIdentity.debugDescription, inboxMessageError.localizedDescription)
                        assertionFailure()
                        continue
                    case .tryingToInsertAMessageThatWasAlreadyDeleted:
                        // This can happen
                        os_log("Could not insert message in DB for identity %{public}@: %{public}@", log: log, type: .error, ownedIdentity.debugDescription, inboxMessageError.localizedDescription)
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
                        os_log("Could not insert attachment in DB for identity %{public}@", log: log, type: .fault, ownedIdentity.debugDescription)
                        continue
                    }
                    
                    // For now, we make sure that none of the signed URL is nil before setting them on the new InboxAttachment. This may change in the future.
                    // If one of the signed URL is nil, we mark the attachment for deletion.
                    if let chunkDownloadSignedUrls = attachmentOnServer.chunkDownloadPrivateUrls as? [URL], !chunkDownloadSignedUrls.isEmpty {
                        do {
                            try inboxAttachment.setChunksSignedURLs(chunkDownloadSignedUrls)
                        } catch {
                            os_log("We could not set the chunk download private URLs. We mark it cancelled by the server", log: log, type: .error)
                            inboxAttachment.markAsCancelledByServer()
                        }
                    } else {
                        os_log("Attachment %{public}@ has a nil chunk URL. It was cancelled by the server.", log: log, type: .info, inboxAttachment.debugDescription)
                        inboxAttachment.markAsCancelledByServer()
                    }
                    
                }
                idsOfNewMessages.append(messageId)
                
            }

            
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
}
