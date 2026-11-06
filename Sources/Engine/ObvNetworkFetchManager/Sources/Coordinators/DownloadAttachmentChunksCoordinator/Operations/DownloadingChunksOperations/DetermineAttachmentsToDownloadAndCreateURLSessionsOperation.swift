/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import OSLog
import ObvMetaManager
import ObvServerInterface
import ObvTypes
import CoreData
import OlvidUtils


final class DetermineAttachmentsToDownloadAndCreateURLSessionsOperation: ContextualOperationWithSpecificReasonForCancel<DetermineAttachmentsToDownloadAndCreateURLSessionsOperation.ReasonForCancel>, @unchecked Sendable {
    
    private static let logger = Logger(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: "DetermineAttachmentsToDownloadAndCreateURLSessionsOperation")

    private let uuid = UUID()
    private let kind: InboxAttachmentDownloadKind
    private let log: OSLog
    private let logCategory = String(describing: DetermineAttachmentsToDownloadAndCreateURLSessionsOperation.self)
    private let tracker: AttachmentChunkDownloadProgressTracker
    private let delegateManager: ObvNetworkFetchDelegateManager

    /// The attachments for which the coordinator already holds a `URLSession` in memory, and for which this operation must therefore build none.
    ///
    /// See where it is consulted, which is where the reasoning is.
    private let attachmentsTheCoordinatorIsAlreadyHandling: Set<ObvAttachmentIdentifier>

    /// The chunks left to fetch for each attachment, and the session to fetch them in — `nil` for an attachment the coordinator is already handling, which
    /// has a session of its own and needs none from here.
    private(set) var chunksToDownloadForAttachment = [ObvAttachmentIdentifier: (urlSession: URLSession?, chunkNumbersAndSignedURLs: [(chunkNumber: Int, signedURL: URL)])]()

    init(kind: InboxAttachmentDownloadKind, tracker: AttachmentChunkDownloadProgressTracker, delegateManager: ObvNetworkFetchDelegateManager, attachmentsTheCoordinatorIsAlreadyHandling: Set<ObvAttachmentIdentifier>) {
        self.kind = kind
        self.log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        self.tracker = tracker
        self.delegateManager = delegateManager
        self.attachmentsTheCoordinatorIsAlreadyHandling = attachmentsTheCoordinatorIsAlreadyHandling
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            let attachmentsToDownload: [InboxAttachment]
            switch kind {
            case .allDownloadableAttachmentsWithoutSession:
                let allDownloadableAttachments = try InboxAttachment.getAllDownloadableWithoutSession(within: obvContext.context)
                attachmentsToDownload = allDownloadableAttachments
            case .allDownloadableAttachmentsWithoutSessionForMessage(messageId: let messageId):
                let allDownloadableAttachments = try InboxAttachment.getAllDownloadableWithoutSession(within: obvContext.context)
                let attachments = allDownloadableAttachments.filter({ $0.messageId == messageId })
                attachmentsToDownload = attachments
            case .specificDownloadableAttachmentsWithoutSession(attachmentId: let attachmentId, resumeRequestedByApp: let resumeRequestedByApp):
                guard let attachment = try InboxAttachment.get(attachmentId: attachmentId, within: obvContext.context) else { return }
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

                guard let attachmentId = try? attachment.attachmentId else {
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

                // Unconditionally, before a single byte is asked for. This is the only moment at which "the file was already gone before this download began"
                // can be told from "something removed it while it was running", and the two have entirely different culprits.
                Self.logger.info("📁 [\(attachmentId.debugDescription, privacy: .public)] About to hand a download to a URLSession writing into \(decryptedAttachmentURL.path, privacy: .public): \(attachment.reportOnWhatIsOnDiskForTheChunks(withinInbox: self.delegateManager.inbox), privacy: .public)")
                
                guard let decryptionKey = attachment.key else {
                    assertionFailure()
                    return cancel(withReason: .decryptionKeyIsNotAvailable)
                }
                
                let cleartextChunkLengths = attachment.chunks.compactMap { $0.cleartextChunkLength }
                guard cleartextChunkLengths.count == attachment.chunks.count else {
                    assertionFailure()
                    return cancel(withReason: .cannotDetermineCleartextChunkLengths)
                }

                // **The last moment at which a download that cannot succeed can be stopped from being started.** Everything below hands this URL to a session
                // delegate that keeps it for the whole transfer, so a missing file is discovered chunk by chunk, at the cost of the whole attachment, and the
                // failure is permanent: the write is refused, the coordinator cancels, the attachment goes back to `paused`, and the reader's next tap does
                // exactly the same again. See `makeTheFileForWritingChunksAgainIfItIsMissing(withinInbox:)` for what it costs and why every chunk is
                // forgotten rather than only the missing ones. It changes nothing when the file is there, which is every ordinary download.
                do {
                    _ = try attachment.makeTheFileForWritingChunksAgainIfItIsMissing(withinInbox: self.delegateManager.inbox)
                } catch {
                    // Cancelled rather than carried on with: a download whose first write is already known to be impossible must not be started at all.
                    Self.logger.fault("📁 [\(attachmentId.debugDescription, privacy: .public)] The file the chunks are written into is missing and could not be made again, so no download is started: \(error.localizedDescription, privacy: .public)")
                    return cancel(withReason: .couldNotMakeTheFileTheChunksAreWrittenIntoAgain(error: error))
                }

                // **No session is built for an attachment the coordinator is already handling**, and until 2026-08-31 one was, for every attachment this
                // operation was asked about.
                //
                // The coordinator holds the session of a download it has paused, and resumes *that* session's tasks — the one built here was never used
                // for anything, and three faults followed from it. It was stored as the tracked session all the same, so the next pause suspended a
                // session with no tasks in it while the transfer carried on and the app was told it had stopped. It was built with
                // `URLSessionConfiguration.background(withIdentifier:)` on the identifier of the session that is still live, pausing not deleting the
                // `InboxAttachmentSession` — and two background sessions may not share an identifier. And nothing ever invalidated it, so a pause and a
                // resume leaked a session, its delegate, and that delegate's `ObvContext`.
                //
                // It has to be skipped rather than discarded afterwards: with no tasks in it, `finishTasksAndInvalidate()` invalidates at once, and the
                // delegate callback that follows deletes the `InboxAttachmentSession` — the row belonging to the session that is actually downloading.
                let urlSession: URLSession?

                if attachmentsTheCoordinatorIsAlreadyHandling.contains(attachmentId) {

                    urlSession = nil

                } else {

                    let inboxAttachmentSession: InboxAttachmentSession
                    if let existingSession = attachment.session {
                        inboxAttachmentSession = existingSession
                    } else {
                        os_log("📄 No InboxAttachmentSession exists for attachment %{public}@. We create one with a new session identifier.", log: log, type: .info, attachmentId.debugDescription)
                        guard let newInboxAttachmentSession = attachment.createSession() else {
                            return cancel(withReason: .failedToCreateInboxAttachmentSession)
                        }
                        inboxAttachmentSession = newInboxAttachmentSession
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

                    urlSession = URLSession(configuration: sessionConfiguration,
                                            delegate: sessionDelegate,
                                            delegateQueue: nil)

                }

                // Now that we have an URLSession for downloading the attachment, we determine the chunks to download
                
                let chunks = try InboxAttachmentChunk.getAllMissingAttachmentChunks(ofAttachmentId: attachmentId, within: obvContext.context)

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
        case couldNotMakeTheFileTheChunksAreWrittenIntoAgain(error: Error)

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
            case .couldNotMakeTheFileTheChunksAreWrittenIntoAgain(error: let error):
                return "The file the chunks are written into was missing and could not be made again: \(error.localizedDescription)"
            }
        }
        
    }

}
