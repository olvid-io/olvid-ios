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
import os.log
import CoreData
import ObvMetaManager
import ObvTypes
import OlvidUtils


final class RecreateURLSessionForCallingUIKitCompletionHandlerOperation: ContextualOperationWithSpecificReasonForCancel<RecreateURLSessionForCallingUIKitCompletionHandlerOperation.ReasonForCancel> {
    
    private let urlSessionIdentifier: String
    private let tracker: AttachmentChunkDownloadProgressTracker
    private let delegateManager: ObvNetworkFetchDelegateManager
    private let log: OSLog
    private let logCategory = String(describing: RecreateURLSessionForCallingUIKitCompletionHandlerOperation.self)

    init(urlSessionIdentifier: String, tracker: AttachmentChunkDownloadProgressTracker, delegateManager: ObvNetworkFetchDelegateManager) {
        self.urlSessionIdentifier = urlSessionIdentifier
        self.tracker = tracker
        self.delegateManager = delegateManager
        self.log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        
        do {
            
            guard let attachmentSession = try InboxAttachmentSession.getWithSessionIdentifier(urlSessionIdentifier, within: obvContext) else {
                return cancel(withReason: .couldNotFindInboxAttachmentSessionInDatabase)
            }
            
            guard let attachment = attachmentSession.attachment else {
                return cancel(withReason: .cannotFindAttachmentInDatabase)
            }

            guard let attachmentId = attachment.attachmentId else { assertionFailure(); return }

            guard let decryptedAttachmentURL = attachment.getURL(withinInbox: delegateManager.inbox) else {
                assertionFailure()
                return cancel(withReason: .cannotDetermineDecryptedAttachmentURL)
            }

            let cleartextChunkLengths = attachment.chunks.compactMap { $0.cleartextChunkLength }
            guard cleartextChunkLengths.count == attachment.chunks.count else {
                assertionFailure()
                return cancel(withReason: .cannotDetermineCleartextChunkLengths)
            }

            guard let decryptionKey = attachment.key else {
                assertionFailure()
                return cancel(withReason: .decryptionKeyIsNotAvailable)
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

            os_log("👑 The delegate created for calling the UIKit handler has the following UID: %{public}@", log: log, type: .info, sessionDelegate.uuid.uuidString)

            let sessionConfiguration = URLSessionConfiguration.background(withIdentifier: urlSessionIdentifier)
            sessionConfiguration.waitsForConnectivity = true
            sessionConfiguration.isDiscretionary = false
            sessionConfiguration.allowsCellularAccess = true
            sessionConfiguration.sessionSendsLaunchEvents = true
            sessionConfiguration.shouldUseExtendedBackgroundIdleMode = true
            sessionConfiguration.allowsConstrainedNetworkAccess = true
            sessionConfiguration.allowsExpensiveNetworkAccess = true

            _ = URLSession(configuration: sessionConfiguration,
                           delegate: sessionDelegate,
                           delegateQueue: nil)

        } catch {
            assertionFailure()
            return cancel(withReason: .coreDataError(error: error))
        }
        
    }
    
    
    public enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case coreDataError(error: Error)
        case couldNotFindInboxAttachmentSessionInDatabase
        case cannotFindAttachmentInDatabase
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
            case .couldNotFindInboxAttachmentSessionInDatabase:
                return "Could not find InboxAttachmentSession in database"
            case .cannotFindAttachmentInDatabase:
                return "Could not find attachment in database"
            case .cannotDetermineDecryptedAttachmentURL:
                return "Cannot determine decrypted attachment URL"
            case .cannotDetermineCleartextChunkLengths:
                return "Cannot determine cleartext chunk lengths"
            case .decryptionKeyIsNotAvailable:
                return "Decryption key is not available"
            case .contextCreatorIsNil:
                return "Context creator is nil"
            }
        }

    }

}
