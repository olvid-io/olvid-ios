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
import ObvTypes
import CoreData
import OlvidUtils
import ObvCrypto


public protocol ObvNetworkPostDelegate: ObvManager {

    func post(_: ObvNetworkMessageToSend, within: ObvContext) throws
    func cancelPostOfMessage(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) throws
    
    func storeCompletionHandler(_: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier: String, withinFlowId: FlowIdentifier)
    func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) -> Bool

    func replayTransactionsHistory(transactions: [NSPersistentHistoryTransaction], within obvContext: ObvContext)
    func deleteHistoryConcerningTheAcknowledgementOfOutboxMessage(messageIdentifier: ObvMessageIdentifier, flowId: FlowIdentifier) async
    func deleteHistoryConcerningTheAcknowledgementOfOutboxMessages(withTimestampFromServerEarlierOrEqualTo referenceDate: Date, flowId: FlowIdentifier) async

    func requestUploadAttachmentProgressesUpdatedSince(date: Date) async throws -> [ObvAttachmentIdentifier: Float]

    /// Follows the upload of one attachment, for as long as the caller keeps the stream. The counterpart of the fetch manager's
    /// `getAsyncStreamOfDownloadProgress(attachmentId:flowId:)`, and the replacement for polling
    /// ``requestUploadAttachmentProgressesUpdatedSince(date:)`` — see the coordinator that implements it.
    func getAsyncStreamOfUploadProgress(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvAttachmentUploadProgress>)

    /// Ends a stream obtained above. The caller must call this: nothing here can see that the view following an upload has gone.
    func finishAsyncStreamOfUploadProgress(streamUUID: UUID) async throws


    func prepareForOwnedIdentityDeletion(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws

}
