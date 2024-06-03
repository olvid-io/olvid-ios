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
import ObvMetaManager
import ObvTypes
import ObvCrypto
import OlvidUtils

protocol NetworkSendFlowDelegate {
    
    func post(_: ObvNetworkMessageToSend, within: ObvContext) throws
    
    func requestBatchUploadMessagesWithoutAttachment(serverURL: URL, flowId: FlowIdentifier) async throws
    func newOutboxMessageWithAttachments(messageId: ObvMessageIdentifier, flowId: FlowIdentifier)
    
    func failedUploadAndGetUidOfMessage(messageId: ObvMessageIdentifier, flowId: FlowIdentifier)
    func successfulUploadOfMessage(messageId: ObvMessageIdentifier, flowId: FlowIdentifier)
    func messageAndAttachmentsWereExternallyCancelledAndCanSafelyBeDeletedNow(messageId: ObvMessageIdentifier, flowId: FlowIdentifier)

    func newProgressForAttachment(attachmentId: ObvAttachmentIdentifier)
    func storeCompletionHandler(_: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier: String, withinFlowId: FlowIdentifier)
    func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) -> Bool
    func signedURLsDownloadFailedForAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier)
    func acknowledgedAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier)
    func attachmentFailedToUpload(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier)

    func requestUploadAttachmentProgressesUpdatedSince(date: Date) async throws -> [ObvAttachmentIdentifier: Float]

    func messageAndAttachmentsWereDeletedFromTheirOutboxes(messageId: ObvMessageIdentifier, flowId: FlowIdentifier)
    
    func sendNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)

    // MARK: - Finalizing the initialization and handling lifecycle events
    
    func resetAllFailedSendAttempsCountersAndRetrySending()

}
