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
import CoreData
import OlvidUtils
import ObvCrypto


public protocol ObvNetworkPostDelegate: ObvManager {

    func post(_: ObvNetworkMessageToSend, within: ObvContext) throws
    func cancelPostOfMessage(messageId: MessageIdentifier, flowId: FlowIdentifier) throws
    
    func storeCompletionHandler(_: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier: String, withinFlowId: FlowIdentifier)
    func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) -> Bool

    func replayTransactionsHistory(transactions: [NSPersistentHistoryTransaction], within obvContext: ObvContext)
    func deleteHistoryConcerningTheAcknowledgementOfOutboxMessage(messageIdentifier: MessageIdentifier, flowId: FlowIdentifier) async
    func deleteHistoryConcerningTheAcknowledgementOfOutboxMessages(withTimestampFromServerEarlierOrEqualTo referenceDate: Date, flowId: FlowIdentifier) async

    func requestUploadAttachmentProgressesUpdatedSince(date: Date) async throws -> [AttachmentIdentifier: Float]

    func prepareForOwnedIdentityDeletion(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws

}
