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

protocol UploadAttachmentChunksDelegate {
    
    func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) -> Bool
    func processAllAttachmentsOfMessage(messageId: MessageIdentifier, flowId: FlowIdentifier)
    func downloadSignedURLsForAttachments(attachmentIds: [AttachmentIdentifier], flowId: FlowIdentifier)
    func resumeMissingAttachmentUploads(flowId: FlowIdentifier)
    func processCompletionHandler(_ handler: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier identifer: String, withinFlowId flowId: FlowIdentifier)
    func cleanExistingOutboxAttachmentSessionsCreatedBy(_ creatorAppType: AppType, flowId: FlowIdentifier)
    func requestProgressOfAttachment(withIdentifier attachmentId: AttachmentIdentifier) -> Progress?
    func queryServerOnSessionsTasksCreatedByShareExtension(flowId: FlowIdentifier)
    func cancelAllAttachmentsUploadOfMessage(messageId: MessageIdentifier, flowId: FlowIdentifier) throws

}
