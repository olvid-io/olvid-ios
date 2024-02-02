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
import ObvTypes
import ObvMetaManager
import OlvidUtils

protocol DownloadAttachmentChunksDelegate {
    
    func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) -> Bool
    func processAllAttachmentsOfMessage(messageId: ObvMessageIdentifier, flowId: FlowIdentifier)
    func resumeMissingAttachmentDownloads(flowId: FlowIdentifier)
    func resumeAttachmentDownloadIfResumeIsRequested(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier)
    func resumeDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, forceResume: Bool, flowId: FlowIdentifier)
    func pauseDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier)
    func requestDownloadAttachmentProgressesUpdatedSince(date: Date) async -> [ObvAttachmentIdentifier: Float]
    func processCompletionHandler(_: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier: String, withinFlowId: FlowIdentifier)
    func cleanExistingOutboxAttachmentSessions(flowId: FlowIdentifier)

}
