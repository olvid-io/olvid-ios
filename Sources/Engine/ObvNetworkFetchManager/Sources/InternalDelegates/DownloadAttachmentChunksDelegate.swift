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
import ObvTypes
import ObvMetaManager
import OlvidUtils

protocol DownloadAttachmentChunksDelegate {
    
    func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) async -> Bool
    func requestDownloadAttachmentProgressesUpdatedSince(date: Date) async -> [ObvAttachmentIdentifier: Float]
    func resumeDownloadOfAttachmentsNotAlreadyDownloading(downloadKind: InboxAttachmentDownloadKind, flowId: FlowIdentifier) async throws
    func appCouldNotFindFileOfDownloadedAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws
    func pauseDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws
    func cancelDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws
    func processCompletionHandler(_ handler: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier sessionIdentifier: String, withinFlowId: FlowIdentifier) async
    func cleanExistingOutboxAttachmentSessions(flowId: FlowIdentifier) async throws


    //func resumeMissingAttachmentDownloads(flowId: FlowIdentifier)
    //func resumeAttachmentDownloadIfResumeIsRequested(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier)
    //func resumeDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, forceResume: Bool, flowId: FlowIdentifier)
    //func pauseDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier)

}


/// When requesting the resuming of an attachment download, the caller must specify if she wants to resume all possible downloads or if she wants to be more specific.
/// In all cases, the download will be resumed only if not resumed already and if the corresponding `InboxAttachment` can be downloaded (which, in particular, requires that the resume was requested by the app).
enum InboxAttachmentDownloadKind: CustomDebugStringConvertible {
    case allDownloadableAttachmentsWithoutSession
    case allDownloadableAttachmentsWithoutSessionForMessage(messageId: ObvMessageIdentifier)
    case specificDownloadableAttachmentsWithoutSession(attachmentId: ObvAttachmentIdentifier, resumeRequestedByApp: Bool)
    
    var debugDescription: String {
        switch self {
        case .allDownloadableAttachmentsWithoutSession:
            return ".allDownloadableAttachmentsWithoutSession"
        case .allDownloadableAttachmentsWithoutSessionForMessage(let messageId):
            return ".allDownloadableAttachmentsWithoutSessionForMessage(messageId: \(messageId.debugDescription)"
        case .specificDownloadableAttachmentsWithoutSession(let attachmentId, let resumeRequestedByApp):
            return ".specificDownloadableAttachmentsWithoutSession(attachmentId: \(attachmentId.debugDescription), resumeRequestedByApp: \(resumeRequestedByApp.description))"
        }
    }

}
