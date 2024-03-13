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
import ObvCrypto
import OlvidUtils


public protocol ObvFlowDelegate: ObvSimpleFlowDelegate {
    
    // MARK: - Background Tasks
    
    func startNewFlow(completionHandler: (() -> Void)?) throws -> FlowIdentifier

    // Posting message and attachments
    
    func addBackgroundActivityForPostingApplicationMessageAttachmentsWithinFlow(withFlowId flowId: FlowIdentifier, messageId: ObvMessageIdentifier, attachmentIds: [ObvAttachmentIdentifier]) throws
    
    // Resuming a protocol
    
    func startBackgroundActivityForStartingOrResumingProtocol() throws -> FlowIdentifier
    
    // Posting a return receipt (for message or an attachment)

    func startBackgroundActivityForPostingReturnReceipt(messageId: ObvMessageIdentifier, attachmentNumber: Int?) throws -> FlowIdentifier
    func stopBackgroundActivityForPostingReturnReceipt(messageId: ObvMessageIdentifier, attachmentNumber: Int?) throws

    // Downloading messages, downloading/pausing attachment
    
    func startBackgroundActivityForDownloadingMessages(ownedIdentity: ObvCryptoIdentity) throws -> (flowId: FlowIdentifier, completionHandler: () -> Void)
    
    // Deleting a message or an attachment
    
    func startBackgroundActivityForMarkingMessageForDeletionAndProcessingAttachments(messageId: ObvMessageIdentifier) throws -> (flowId: FlowIdentifier, completionHandler: () -> Void)
    func startBackgroundActivityForMarkingAttachmentForDeletion(attachmentId: ObvAttachmentIdentifier) throws -> (flowId: FlowIdentifier, completionHandler: () -> Void)

}
