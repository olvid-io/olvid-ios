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
import ObvMetaManager
import ObvTypes
import ObvCrypto
import OlvidUtils

protocol NetworkSendFlowDelegate {
    
    func post(_: ObvNetworkMessageToSend, within: ObvContext) throws
    
    func newOutboxMessage(messageId: MessageIdentifier, flowId: FlowIdentifier)
    
    func failedUploadAndGetUidOfMessage(messageId: MessageIdentifier, flowId: FlowIdentifier)
    func successfulUploadOfMessage(messageId: MessageIdentifier, flowId: FlowIdentifier)
    func messageAndAttachmentsWereExternallyCancelledAndCanSafelyBeDeletedNow(messageId: MessageIdentifier, flowId: FlowIdentifier)

    func newProgressForAttachment(attachmentId: AttachmentIdentifier)
    func storeCompletionHandler(_: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier: String, withinFlowId: FlowIdentifier)
    func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) -> Bool
    func signedURLsDownloadFailedForAttachment(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier)
    func acknowledgedAttachment(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier)
    func attachmentFailedToUpload(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier)

    func requestUploadAttachmentProgressesUpdatedSince(date: Date) async throws -> [AttachmentIdentifier: Float]

    func messageAndAttachmentsWereDeletedFromTheirOutboxes(messageId: MessageIdentifier, flowId: FlowIdentifier)
    
    func sendNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)

    // MARK: - Finalizing the initialization and handling lifecycle events
    
    func resetAllFailedSendAttempsCountersAndRetrySending()

}
