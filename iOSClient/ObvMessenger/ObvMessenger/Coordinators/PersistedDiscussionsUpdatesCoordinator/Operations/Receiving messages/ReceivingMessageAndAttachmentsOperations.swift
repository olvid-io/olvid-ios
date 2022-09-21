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
import CoreData
import os.log
import ObvEngine
import ObvCrypto
import OlvidUtils


final class CreatePersistedMessageReceivedFromReceivedObvMessageOperation: ContextualOperationWithSpecificReasonForCancel<CreatePersistedMessageReceivedFromReceivedObvMessageOperationReasonForCancel> {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "CreatePersistedMessageReceivedFromReceivedObvMessageOperation")

    private let obvMessage: ObvMessage
    private let messageJSON: MessageJSON
    private let returnReceiptJSON: ReturnReceiptJSON?
    private let overridePreviousPersistedMessage: Bool
    private let obvEngine: ObvEngine
    
    init(obvMessage: ObvMessage, messageJSON: MessageJSON, overridePreviousPersistedMessage: Bool, returnReceiptJSON: ReturnReceiptJSON?, obvEngine: ObvEngine) {
        self.obvMessage = obvMessage
        self.messageJSON = messageJSON
        self.returnReceiptJSON = returnReceiptJSON
        self.overridePreviousPersistedMessage = overridePreviousPersistedMessage
        self.obvEngine = obvEngine
        super.init()
    }

    
    override func main() {
        
        os_log("Executing a CreatePersistedMessageReceivedFromReceivedObvMessageOperation for obvMessage %{public}@", log: log, type: .debug, obvMessage.messageIdentifierFromEngine.debugDescription)

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        let currentUserActivityPersistedDiscussionObjectID = ObvUserActivitySingleton.shared.currentPersistedDiscussionObjectID
        
        obvContext.performAndWait {
            
            do {
                
                // Grab the persisted contact and the appropriate discussion
                
                guard let persistedContactIdentity = try PersistedObvContactIdentity.get(persisted: obvMessage.fromContactIdentity, whereOneToOneStatusIs: .any, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindPersistedObvContactIdentityInDatabase)
                }
                
                guard let ownedIdentity = persistedContactIdentity.ownedIdentity else {
                    return cancel(withReason: .couldNotDetermineOwnedIdentity)
                }
                
                let discussion: PersistedDiscussion
                if let groupId = messageJSON.groupId {
                    guard let contactGroup = try PersistedContactGroup.getContactGroup(groupId: groupId, ownedIdentity: ownedIdentity) else {
                        return cancel(withReason: .couldNotFindPersistedContactGroupInDatabase)
                    }
                    discussion = contactGroup.discussion
                } else if let oneToOneDiscussion = persistedContactIdentity.oneToOneDiscussion {
                    guard persistedContactIdentity.isOneToOne else {
                        return cancel(withReason: .cannotInsertMessageInOneToOneDiscussionFromNonOneToOneContact)
                    }
                    discussion = oneToOneDiscussion
                } else {
                    return cancel(withReason: .couldNotFindDiscussion)
                }
                
                // Try to insert a EndToEndEncryptedSystemMessage if the discussion is empty
                
                try? PersistedDiscussion.insertSystemMessagesIfDiscussionIsEmpty(discussionObjectID: discussion.objectID, markAsRead: true, within: obvContext.context)
                
                // If overridePreviousPersistedMessage is true, we update any previously stored message from DB. If no such message exists, we create it.
                // If overridePreviousPersistedMessage is false, we make sure that no existing PersistedMessageReceived exists in DB. If this is the case, we create the message.
                // Note that processing attachments requires overridePreviousPersistedMessage to be true
                
                if overridePreviousPersistedMessage {
                    
                    if let previousMessage = try PersistedMessageReceived.get(messageIdentifierFromEngine: obvMessage.messageIdentifierFromEngine, from: persistedContactIdentity) {
                        
                        guard !previousMessage.isWiped else {
                            os_log("Trying to update a wiped received message. We don't do that an return immediately.", log: log, type: .info)
                            return
                        }
                        
                        os_log("Updating a previous received message...", log: log, type: .info)
                        
                        do {
                            try previousMessage.update(withMessageJSON: messageJSON,
                                                       messageIdentifierFromEngine: obvMessage.messageIdentifierFromEngine,
                                                       returnReceiptJSON: returnReceiptJSON,
                                                       messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer,
                                                       downloadTimestampFromServer: obvMessage.downloadTimestampFromServer,
                                                       localDownloadTimestamp: obvMessage.localDownloadTimestamp,
                                                       discussion: discussion)
                        } catch {
                            os_log("Could not update existing received message: %{public}@", log: log, type: .error, error.localizedDescription)
                        }
                        
                    } else {
                        
                        // Create the PersistedMessageReceived
                        
                        os_log("Creating a persisted message (overridePreviousPersistedMessage: %{public}@)", log: log, type: .debug, overridePreviousPersistedMessage.description)
                        let missedMessageCount = updateNextMessageMissedMessageCountAndGetCurrentMissedMessageCount(
                            discussion: discussion,
                            contactIdentity: persistedContactIdentity,
                            senderThreadIdentifier: messageJSON.senderThreadIdentifier,
                            senderSequenceNumber: messageJSON.senderSequenceNumber)
                        
                        guard (try? PersistedMessageReceived(messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer,
                                                             downloadTimestampFromServer: obvMessage.downloadTimestampFromServer,
                                                             localDownloadTimestamp: obvMessage.localDownloadTimestamp,
                                                             messageJSON: messageJSON,
                                                             contactIdentity: persistedContactIdentity,
                                                             messageIdentifierFromEngine: obvMessage.messageIdentifierFromEngine,
                                                             returnReceiptJSON: returnReceiptJSON,
                                                             missedMessageCount: missedMessageCount,
                                                             discussion: discussion)) != nil
                        else {
                            return cancel(withReason: .couldNotCreatePersistedMessageReceived)
                        }
                        
                    }
                    
                    // Process the attachments within the message
                    
                    for obvAttachment in obvMessage.attachments {
                        do {
                            try ReceivingMessageAndAttachmentsOperationHelper.processFyleWithinDownloadingAttachment(obvAttachment,
                                                                                                                     newProgress: nil,
                                                                                                                     obvEngine: obvEngine,
                                                                                                                     log: log,
                                                                                                                     within: obvContext)
                        } catch {
                            os_log("Could not process one of the message's attachments: %{public}@", log: log, type: .fault, error.localizedDescription)
                            // We continue anyway
                        }
                    }
                    
                } else {
                    
                    // Make sure the message does not already exists in DB
                    
                    guard try PersistedMessageReceived.get(messageIdentifierFromEngine: obvMessage.messageIdentifierFromEngine, from: persistedContactIdentity) == nil else {
                        return
                    }
                    
                    // We make sure that message has a body (for now, this message comes from the notification extension, and there is no point in creating a `PersistedMessageReceived` if there is no body.
                    
                    guard messageJSON.body?.isEmpty == false else {
                        return
                    }
                    
                    // Create the PersistedMessageReceived
                    
                    os_log("Creating a persisted message (overridePreviousPersistedMessage: %{public}@)", log: log, type: .debug, overridePreviousPersistedMessage.description)
                    let missedMessageCount = updateNextMessageMissedMessageCountAndGetCurrentMissedMessageCount(
                        discussion: discussion,
                        contactIdentity: persistedContactIdentity,
                        senderThreadIdentifier: messageJSON.senderThreadIdentifier,
                        senderSequenceNumber: messageJSON.senderSequenceNumber)
                    
                    guard (try? PersistedMessageReceived(messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer,
                                                         downloadTimestampFromServer: obvMessage.downloadTimestampFromServer,
                                                         localDownloadTimestamp: obvMessage.localDownloadTimestamp,
                                                         messageJSON: messageJSON,
                                                         contactIdentity: persistedContactIdentity,
                                                         messageIdentifierFromEngine: obvMessage.messageIdentifierFromEngine,
                                                         returnReceiptJSON: returnReceiptJSON,
                                                         missedMessageCount: missedMessageCount,
                                                         discussion: discussion)) != nil
                    else {
                        return cancel(withReason: .couldNotCreatePersistedMessageReceived)
                    }
                    
                }
                
                /* The following block of code objective allows to auto-read ephemeral received messges if appropriate.
                 * We first check whether the current user activity is to be within a discussion. If not,
                 * we never auto-read.
                 * If she is within a discussion, we consider all inserted received messages that are ephemeral and
                 * that require user action to be read. For each of these messages, we check that its discussion
                 * is identical to the one corresponding to the user activity, and that this discussion configuration
                 * has its auto-read setting set to `true`.
                 * Finally, if the message ephemerality is more restrictive than that of the discussion, we do not auto-read.
                 * In that case, and in that case only, we immediately allow reading of the message.
                 */
                
                if let currentUserActivityPersistedDiscussionObjectID = currentUserActivityPersistedDiscussionObjectID {
                    
                    let insertedReceivedEphemeralMessagesWithUserAction: [PersistedMessageReceived] = obvContext.context.insertedObjects.compactMap({
                        guard let receivedMessage = $0 as? PersistedMessageReceived,
                              receivedMessage.isEphemeralMessageWithUserAction
                        else {
                            return nil
                        }
                        return receivedMessage
                    })
                    
                    insertedReceivedEphemeralMessagesWithUserAction.forEach { insertedReceivedEphemeralMessageWithUserAction in
                        guard insertedReceivedEphemeralMessageWithUserAction.discussion.typedObjectID == currentUserActivityPersistedDiscussionObjectID,
                              insertedReceivedEphemeralMessageWithUserAction.discussion.autoRead == true
                        else {
                            return
                        }
                        // Check that the message ephemerality is at least that of the discussion, otherwise, do not auto read
                        guard insertedReceivedEphemeralMessageWithUserAction.ephemeralityIsAtLeastAsPermissiveThanDiscussionSharedConfiguration else {
                            return
                        }
                        // If we reach this point, we are receiving a message that is readOnce, within a discussion with an auto-read setting that is the one currently shown to the user. In that case, we auto-read the message.
                        do {
                            try insertedReceivedEphemeralMessageWithUserAction.allowReading(now: Date())
                        } catch {
                            os_log("We received a read-once message within a discussion with auto-read that is shown on screen. We should auto-read the message, but this failed: %{public}@", log: log, type: .fault, error.localizedDescription)
                            assertionFailure()
                            // We continue anyway
                        }
                    }
                }
                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
        
    }

    private func updateNextMessageMissedMessageCountAndGetCurrentMissedMessageCount(discussion: PersistedDiscussion, contactIdentity: PersistedObvContactIdentity, senderThreadIdentifier: UUID, senderSequenceNumber: Int) -> Int {

        let latestDiscussionSenderSequenceNumber: PersistedLatestDiscussionSenderSequenceNumber?
        do {
            latestDiscussionSenderSequenceNumber = try PersistedLatestDiscussionSenderSequenceNumber.get(discussion: discussion, contactIdentity: contactIdentity, senderThreadIdentifier: senderThreadIdentifier)
        } catch {
            os_log("Could not get PersistedLatestDiscussionSenderSequenceNumber: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            return 0
        }

        if let latestDiscussionSenderSequenceNumber = latestDiscussionSenderSequenceNumber {
            if senderSequenceNumber < latestDiscussionSenderSequenceNumber.latestSequenceNumber {
                guard let nextMessage = PersistedMessageReceived.getNextMessageBySenderSequenceNumber(senderSequenceNumber, senderThreadIdentifier: senderThreadIdentifier, contactIdentity: contactIdentity, within: discussion) else {
                    return 0
                }
                if nextMessage.missedMessageCount < nextMessage.senderSequenceNumber - senderSequenceNumber {
                    // The message is older than the number of messages missed in the following message --> nothing to do
                    return 0
                }
                let remainingMissedCount = nextMessage.missedMessageCount - (nextMessage.senderSequenceNumber - senderSequenceNumber)

                nextMessage.updateMissedMessageCount(with: nextMessage.senderSequenceNumber - senderSequenceNumber - 1)

                return remainingMissedCount
            } else if senderSequenceNumber > latestDiscussionSenderSequenceNumber.latestSequenceNumber {
                let missingCount = senderSequenceNumber - latestDiscussionSenderSequenceNumber.latestSequenceNumber - 1
                latestDiscussionSenderSequenceNumber.updateLatestSequenceNumber(with: senderSequenceNumber)
                return missingCount
            } else {
                // Unexpected: senderSequenceNumber == latestSequenceNumber (this should normally not happen...)
                return 0
            }
        } else {
            _ = PersistedLatestDiscussionSenderSequenceNumber(discussion: discussion,
                                                              contactIdentity: contactIdentity,
                                                              senderThreadIdentifier: senderThreadIdentifier,
                                                              latestSequenceNumber: senderSequenceNumber)
            return 0
        }
    }

    
}


enum CreatePersistedMessageReceivedFromReceivedObvMessageOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case contextIsNil
    case couldNotFindPersistedObvContactIdentityInDatabase
    case couldNotDetermineOwnedIdentity
    case couldNotFindPersistedContactGroupInDatabase
    case couldNotCreatePersistedMessageReceived
    case coreDataError(error: Error)
    case couldNotFindDiscussion
    case cannotInsertMessageInOneToOneDiscussionFromNonOneToOneContact
    
    var logType: OSLogType {
        switch self {
        case .couldNotFindPersistedObvContactIdentityInDatabase,
                .couldNotFindPersistedContactGroupInDatabase,
                .couldNotFindDiscussion,
                .cannotInsertMessageInOneToOneDiscussionFromNonOneToOneContact:
            return .error
        case .contextIsNil,
                .coreDataError,
                .couldNotDetermineOwnedIdentity,
                .couldNotCreatePersistedMessageReceived:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "The context is not set"
        case .couldNotFindPersistedObvContactIdentityInDatabase:
            return "Could not find contact identity of received message in database"
        case .couldNotFindPersistedContactGroupInDatabase:
            return "Could not find group of received message in database"
        case .couldNotDetermineOwnedIdentity:
            return "Could not determine owned identity"
        case .couldNotCreatePersistedMessageReceived:
            return "Could not create a PersistedMessageReceived instance"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindDiscussion:
            return "Could not find discussion"
        case .cannotInsertMessageInOneToOneDiscussionFromNonOneToOneContact:
            return "The message comes from a non-oneToOne contact. We could not find the appropriate group discussion, and we cannot add the message to a one2one discussion."
        }
    }
    
}



// MARK: - ProcessFyleWithinDownloadingAttachmentOperation

final class ProcessFyleWithinDownloadingAttachmentOperation: ContextualOperationWithSpecificReasonForCancel<ProcessFyleWithinDownloadingAttachmentOperationReasonForCancel> {
    
    private let obvAttachment: ObvAttachment
    private let newProgress: (totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)?
    private let obvEngine: ObvEngine
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ProcessFyleWithinDownloadingAttachmentOperation.self))

    init(obvAttachment: ObvAttachment, newProgress: (totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)?, obvEngine: ObvEngine) {
        self.obvAttachment = obvAttachment
        self.newProgress = newProgress
        self.obvEngine = obvEngine
        super.init()
    }

    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {
            
            /* This notification can arrive very early, even before the NewMessageReceived notification and thus,
             * before the PersistedMessageReceived is even created. In that case, trying to process the fyle fails.
             * So we check whether the PersistedMessageReceived exists before going any further
             */
            
            guard (try? PersistedMessageReceived.get(messageIdentifierFromEngine: obvAttachment.messageIdentifier, from: obvAttachment.fromContactIdentity, within: obvContext.context)) != nil else { return }
            
            // If we reach this point, we can safely process the fyle
            
            do {
                try ReceivingMessageAndAttachmentsOperationHelper.processFyleWithinDownloadingAttachment(obvAttachment, newProgress: newProgress, obvEngine: obvEngine, log: log, within: obvContext)
            } catch {
                return cancel(withReason: .couldNotProcessFyleWithinDownloadingAttachment(error: error))
            }

        }
        
    }

    
}


enum ProcessFyleWithinDownloadingAttachmentOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case couldNotProcessFyleWithinDownloadingAttachment(error: Error)
    case coreDataError(error: Error)
    case contextIsNil
    
    var logType: OSLogType {
        switch self {
        case .couldNotProcessFyleWithinDownloadingAttachment:
            return .error
        case .coreDataError, .contextIsNil:
            return .fault
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "The context is not set"
        case .couldNotProcessFyleWithinDownloadingAttachment:
            return "Could not process fyle within dowloading attachment"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        }
    }

}




// MARK: - ReceivingMessageAndAttachmentsOperationHelper

fileprivate final class ReceivingMessageAndAttachmentsOperationHelper {
    
    private static func makeError(message: String) -> Error { NSError(domain: "ReceivingMessageAndAttachmentsOperationHelper", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    fileprivate static func processFyleWithinDownloadingAttachment(_ obvAttachment: ObvAttachment, newProgress: (totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)?, obvEngine: ObvEngine, log: OSLog, within obvContext: ObvContext) throws {
        
        let metadata = try FyleMetadata.jsonDecode(obvAttachment.metadata)
        
        // Get or create a ReceivedFyleMessageJoinWithStatus
        
        let fyle: Fyle
        let join: ReceivedFyleMessageJoinWithStatus
        do {
            if let previousJoin = try ReceivedFyleMessageJoinWithStatus.get(metadata: metadata, obvAttachment: obvAttachment, within: obvContext.context) {
                join = previousJoin
                if let _fyle = join.fyle {
                    fyle = _fyle
                } else {
                    guard let newFyle = Fyle(sha256: metadata.sha256, within: obvContext.context) else {
                        throw makeError(message: "Could not get or create Fyle from/in database")
                    }
                    fyle = newFyle
                }
            } else {
                // Since the ReceivedFyleMessageJoinWithStatus must be created, we first get or create a Fyle
                do {
                    if let previousFyle = try Fyle.get(sha256: metadata.sha256, within: obvContext.context) {
                        fyle = previousFyle
                    } else {
                        guard let newFyle = Fyle(sha256: metadata.sha256, within: obvContext.context) else {
                            throw makeError(message: "Could not get or create Fyle from/in database")
                        }
                        fyle = newFyle
                    }
                } catch {
                    os_log("Could not get or create Fyle from/in database", log: log, type: .error)
                    return
                }
                join = try ReceivedFyleMessageJoinWithStatus(metadata: metadata, obvAttachment: obvAttachment, within: obvContext.context)
            }
        } catch {
            throw makeError(message: "Could not get or create ReceivedFyleMessageJoinWithStatus: %{public}@")
        }

        // In the end, if the status is downloaded and the fyle is available, we can delete any existing downsized preview
        try? obvContext.addContextWillSaveCompletionHandler {
            if join.status == .complete && fyle.getFileSize() == join.totalByteCount {
                join.deleteDownsizedThumbnail()
            }
        }
                
        // If the ReceivedFyleMessageJoinWithStatus is completed, we ask the engine to delete the attachment
        if join.status == .complete && join.fyle?.getFileSize() == join.totalByteCount {
            
            do {
                try obvContext.addContextDidSaveCompletionHandler { error in
                    do {
                        try obvEngine.deleteObvAttachment(attachmentNumber: obvAttachment.number, ofMessageWithIdentifier: obvAttachment.messageIdentifier, ownedCryptoId: obvAttachment.ownedCryptoId)
                    } catch {
                        os_log("Call to the engine method deleteObvAttachment did fail", log: log, type: .fault)
                        assertionFailure()
                    }
                }
            } catch {
                throw makeError(message: "Could not add addContextDidSaveCompletionHandler: \(error.localizedDescription)")
            }
            
            return
        }
        
        
        // Update the status of the ReceivedFyleMessageJoinWithStatus depending on the status of the ObvAttachment
        
        switch obvAttachment.status {
        case .paused:
            join.tryToSetStatusTo(.downloadable)
        case .resumed:
            join.tryToSetStatusTo(.downloading)
        case .downloaded:
            join.tryToSetStatusTo(.complete)
        case .cancelledByServer:
            join.tryToSetStatusTo(.cancelledByServer)
        case .markedForDeletion:
            break
        }
        
        // If the ReceivedFyleMessageJoinWithStatus is marked as completed, but the Fyle is not, we have work to do
        
        if obvAttachment.status == .downloaded && fyle.getFileSize() == nil {
            
            // Compute the sha256 of the (complete) file indicated within the obvAttachment and compare it to what was expected
            let realHash: Data
            do {
                let sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()
                realHash = try sha256.hash(fileAtUrl: obvAttachment.url)
            } catch {
                throw makeError(message: "Could not compute the sha256 of the received file")
            }
            guard realHash == fyle.sha256 else {
                os_log("OMG, the sha256 of the received file does not match the one we expected", log: log, type: .error)
                obvContext.context.delete(join) // This also deletes the fyle if possible
                do {
                    try obvContext.addContextDidSaveCompletionHandler { error in
                        guard error == nil else { return }
                        do {
                            try obvEngine.deleteObvAttachment(attachmentNumber: obvAttachment.number,
                                                              ofMessageWithIdentifier: obvAttachment.messageIdentifier,
                                                              ownedCryptoId: obvAttachment.ownedCryptoId)
                        } catch {
                            os_log("The engine call to deleteObvAttachment did fail", log: log, type: .fault)
                            assertionFailure()
                        }
                    }
                } catch {
                    throw makeError(message: "The call to addContextDidSaveCompletionHandler did fail")
                }
                return
            }
            
            // If we reach this point, the sha256 is correct. We move the received file to a permanent location
            try fyle.moveFileToPermanentURL(from: obvAttachment.url, logTo: log)
            
            os_log("We moved a downloaded file to a permanent location", log: log, type: .debug)
            
            // The fyle is now available, so we set fyle's associated joins' status to "downloaded"
            fyle.allFyleMessageJoinWithStatus.forEach({ (fyleMessageJoinWithStatus) in
                if let receivedFyleMessageJoinWithStatus = fyleMessageJoinWithStatus as? ReceivedFyleMessageJoinWithStatus {
                    receivedFyleMessageJoinWithStatus.tryToSetStatusTo(.complete)
                }
            })

        }
        
    }
    
}
