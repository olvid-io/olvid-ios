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
import ObvMetaManager
import ObvServerInterface
import ObvTypes
import CoreData
import OlvidUtils


/// 2023-12 ok
final class DetermineAttachmentsToDownloadAndCreateURLSessionsOperation: ContextualOperationWithSpecificReasonForCancel<DetermineAttachmentsToDownloadAndCreateURLSessionsOperation.ReasonForCancel> {
    
    private let uuid = UUID()
    private let kind: InboxAttachmentDownloadKind
    private let log: OSLog
    private let logCategory = String(describing: DetermineAttachmentsToDownloadAndCreateURLSessionsOperation.self)
    private let tracker: AttachmentChunkDownloadProgressTracker
    private let delegateManager: ObvNetworkFetchDelegateManager
    
    private(set) var chunksToDownloadForAttachment = [ObvAttachmentIdentifier: (urlSession: URLSession, chunkNumbersAndSignedURLs: [(chunkNumber: Int, signedURL: URL)])]()
    
    init(kind: InboxAttachmentDownloadKind, tracker: AttachmentChunkDownloadProgressTracker, delegateManager: ObvNetworkFetchDelegateManager) {
        self.kind = kind
        self.log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        self.tracker = tracker
        self.delegateManager = delegateManager
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            let attachmentsToDownload: [InboxAttachment]
            switch kind {
            case .allDownloadableAttachmentsWithoutSession:
                let allDownloadableAttachments = try InboxAttachment.getAllDownloadableWithoutSession(within: obvContext)
                attachmentsToDownload = allDownloadableAttachments
            case .allDownloadableAttachmentsWithoutSessionForMessage(messageId: let messageId):
                let allDownloadableAttachments = try InboxAttachment.getAllDownloadableWithoutSession(within: obvContext)
                let attachments = allDownloadableAttachments.filter({ $0.messageId == messageId })
                attachmentsToDownload = attachments
            case .specificDownloadableAttachmentsWithoutSession(attachmentId: let attachmentId, resumeRequestedByApp: let resumeRequestedByApp):
                guard let attachment = try InboxAttachment.get(attachmentId: attachmentId, within: obvContext) else { return }
                if resumeRequestedByApp {
                    try attachment.resumeDownload()
                    attachmentsToDownload = [attachment]
                } else if attachment.canBeDownloaded && attachment.status == .resumeRequested {
                    attachmentsToDownload = [attachment]
                } else {
                    attachmentsToDownload = []
                }
            }
            
            os_log("📄 DetermineAttachmentsToDownloadAndCreateURLSessionsOperation %{public}@ determined that there are %d attachments to download", log: log, type: .info, uuid.description, attachmentsToDownload.count)

            guard !attachmentsToDownload.isEmpty else {
                return
            }

            for attachment in attachmentsToDownload {

                guard let attachmentId = attachment.attachmentId else {
                    assertionFailure()
                    continue
                }
                
                guard !attachment.isDownloaded else {
                    os_log("📄 Attachment is already downloaded", log: log, type: .info)
                    assertionFailure()
                    return cancel(withReason: .attachmentIsAlreadyDownloaded)
                }
                
                guard attachment.status == .resumeRequested else {
                    os_log("📄 Attachment resume is not requested", log: log, type: .error)
                    return cancel(withReason: .resumeNotRequested)
                }
                
                guard attachment.canBeDownloaded else {
                    os_log("📄 Attachment cannot be downloaded yet", log: log, type: .error)
                    assertionFailure()
                    return cancel(withReason: .attachmentCannotBeDownloadedYet)
                }
                
                guard let decryptedAttachmentURL = attachment.getURL(withinInbox: delegateManager.inbox) else {
                    assertionFailure()
                    return cancel(withReason: .cannotDetermineDecryptedAttachmentURL)
                }
                
                guard let decryptionKey = attachment.key else {
                    assertionFailure()
                    return cancel(withReason: .decryptionKeyIsNotAvailable)
                }
                
                let cleartextChunkLengths = attachment.chunks.compactMap { $0.cleartextChunkLength }
                guard cleartextChunkLengths.count == attachment.chunks.count else {
                    assertionFailure()
                    return cancel(withReason: .cannotDetermineCleartextChunkLengths)
                }

                let inboxAttachmentSession: InboxAttachmentSession
                if let existingSession = attachment.session {
                    inboxAttachmentSession = existingSession
                } else {
                    os_log("📄 No OutboxAttachmentSession exists for attachment %{public}@. We create one with a new session identifier.", log: log, type: .info, attachment.attachmentId.debugDescription)
                    guard let newOutboxAttachmentSession = attachment.createSession() else {
                        return cancel(withReason: .failedToCreateInboxAttachmentSession)
                    }
                    inboxAttachmentSession = newOutboxAttachmentSession
                }
                
                guard let contextCreator = delegateManager.contextCreator else {
                    assertionFailure()
                    return cancel(withReason: .contextCreatorIsNil)
                }
                
                let obvContextForDownloadAttachmentChunksSessionDelegate = contextCreator.newBackgroundContext(flowId: obvContext.flowId)
                
                let sessionDelegate = DownloadAttachmentChunksSessionDelegate(
                    attachmentId: attachmentId,
                    logSubsystem: delegateManager.logSubsystem,
                    decryptedAttachmentURL: decryptedAttachmentURL,
                    tracker: tracker,
                    flowId: obvContext.flowId,
                    cleartextChunkLengths: cleartextChunkLengths,
                    decryptionKey: decryptionKey,
                    queueForDecryptingChunks: delegateManager.queueForDecryptingChunks,
                    queueForComposedOperations: delegateManager.queueForComposedOperations,
                    queueSharedAmongCoordinators: delegateManager.queueSharedAmongCoordinators,
                    obvContext: obvContextForDownloadAttachmentChunksSessionDelegate,
                    viewContext: viewContext)
                
                let sessionConfiguration = URLSessionConfiguration.background(withIdentifier: inboxAttachmentSession.sessionIdentifier)
                sessionConfiguration.waitsForConnectivity = true
                sessionConfiguration.isDiscretionary = false
                sessionConfiguration.allowsCellularAccess = true
                sessionConfiguration.sessionSendsLaunchEvents = true
                sessionConfiguration.shouldUseExtendedBackgroundIdleMode = true
                sessionConfiguration.allowsConstrainedNetworkAccess = true
                sessionConfiguration.allowsExpensiveNetworkAccess = true

                let urlSession = URLSession(configuration: sessionConfiguration,
                                            delegate: sessionDelegate,
                                            delegateQueue: nil)

                // Now that we have an URLSession for downloading the attachment, we determine the chunks to download
                
                let chunks = try InboxAttachmentChunk.getAllMissingAttachmentChunks(ofAttachmentId: attachmentId, within: obvContext)

                guard !chunks.isEmpty else {
                    // All chunks are acknowledged. Mark the attachment as downloaded and continue with the next attachment
                    try attachment.tryChangeStatusToDownloaded()
                    continue
                }

                let chunkNumbersAndSignedURLs: [(chunkNumber: Int, signedURL: URL)] = chunks.compactMap {
                    guard let signedURL = $0.signedURL else { return nil }
                    return ($0.chunkNumber, signedURL)
                }

                chunksToDownloadForAttachment[attachmentId] = (urlSession, chunkNumbersAndSignedURLs)
                
            }
            
        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case cannotFindAttachmentInDatabase
        case attachmentIsAlreadyDownloaded
        case resumeNotRequested
        case attachmentCannotBeDownloadedYet
        case failedToCreateInboxAttachmentSession
        case cannotDetermineDecryptedAttachmentURL
        case cannotDetermineCleartextChunkLengths
        case decryptionKeyIsNotAvailable
        case contextCreatorIsNil
        
        public var logType: OSLogType {
            return .fault
        }
        
        public var errorDescription: String? {
            switch self {
            case .coreDataError(error: let error):
                return "Core Data error: \(error.localizedDescription)"
            case .cannotFindAttachmentInDatabase:
                return "Cannot find attachment in database"
            case .attachmentIsAlreadyDownloaded:
                return "Attachment is already downloaded"
            case .resumeNotRequested:
                return "Resume not requested"
            case .attachmentCannotBeDownloadedYet:
                return "Attachment cannot be downloaded yet"
            case .failedToCreateInboxAttachmentSession:
                return "Failed to create inbox attachment session"
            case .cannotDetermineDecryptedAttachmentURL:
                return "Cannot determine decrypted attachment URL"
            case .cannotDetermineCleartextChunkLengths:
                return "Cannot determine cleartext chunks lengths"
            case .decryptionKeyIsNotAvailable:
                return "The decryption key is not available"
            case .contextCreatorIsNil:
                return "The context creator is nil"
            }
        }
        
    }

}
