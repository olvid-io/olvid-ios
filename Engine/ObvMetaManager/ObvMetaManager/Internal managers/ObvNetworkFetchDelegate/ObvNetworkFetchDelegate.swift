/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import CoreData
import ObvEncoder
import OlvidUtils


public protocol ObvNetworkFetchDelegate: ObvManager {

    func updatedListOfOwnedIdentites(ownedIdentities: Set<ObvCryptoIdentity>, flowId: FlowIdentifier)
    
    func downloadMessages(for ownedIdentity: ObvCryptoIdentity, andDeviceUid deviceUid: UID, flowId: FlowIdentifier)
    func getDecryptedMessage(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) -> ObvNetworkReceivedMessageDecrypted?
    func allAttachmentsCanBeDownloadedForMessage(withId: ObvMessageIdentifier, within: ObvContext) throws -> Bool
    func allAttachmentsHaveBeenDownloadedForMessage(withId: ObvMessageIdentifier, within: ObvContext) throws -> Bool
    func attachment(withId: ObvAttachmentIdentifier, canBeDownloadedwithin: ObvContext) throws -> Bool

    func setRemoteCryptoIdentity(_ remoteCryptoIdentity: ObvCryptoIdentity, messagePayload: Data, extendedMessagePayloadKey: AuthenticatedEncryptionKey?, andAttachmentsInfos: [ObvNetworkFetchAttachmentInfos], forApplicationMessageWithmessageId: ObvMessageIdentifier, within obvContext: ObvContext) throws
    
    func getAttachment(withId attachmentId: ObvAttachmentIdentifier, within obvContext: ObvContext) -> ObvNetworkFetchReceivedAttachment?
    
    func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) -> Bool
    func processCompletionHandler(_: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier: String, withinFlowId: FlowIdentifier)

    func deleteMessageAndAttachments(messageId: ObvMessageIdentifier, within: ObvContext)
    func markMessageForDeletion(messageId: ObvMessageIdentifier, within: ObvContext)
    func markAttachmentForDeletion(attachmentId: ObvAttachmentIdentifier, within: ObvContext)
    func resumeDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, forceResume: Bool, flowId: FlowIdentifier)
    func pauseDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier)
    func requestDownloadAttachmentProgressesUpdatedSince(date: Date) async throws -> [ObvAttachmentIdentifier: Float]

    func registerPushNotification(_ pushNotification: ObvPushNotificationType, flowId: FlowIdentifier) async throws

    func sendDeleteReturnReceipt(ownedIdentity: ObvCryptoIdentity, serverUid: UID) async throws
    
    func getWebSocketState(ownedIdentity: ObvCryptoIdentity) async throws -> (URLSessionTask.State,TimeInterval?)
    func connectWebsockets(flowId: FlowIdentifier) async
    func disconnectWebsockets(flowId: FlowIdentifier) async

    func getTurnCredentials(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> ObvTurnCredentials

    func refreshAPIPermissions(of ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> APIKeyElements
    func queryAPIKeyStatus(for identity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) async throws -> APIKeyElements
    func registerOwnedAPIKeyOnServerNow(ownedCryptoIdentity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) async throws -> ObvRegisterApiKeyResult
    func queryFreeTrial(for identity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> Bool
    func startFreeTrial(for identity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> APIKeyElements
    func verifyReceiptAndRefreshAPIPermissions(appStoreReceiptElements: ObvAppStoreReceipt, flowId: FlowIdentifier) async throws -> [ObvCryptoIdentity : ObvAppStoreReceipt.VerificationStatus]
    // func verifyReceipt(ownedCryptoIdentities: [ObvCryptoIdentity], receiptData: String, transactionIdentifier: String, flowId: FlowIdentifier)
    func queryServerWellKnown(serverURL: URL, flowId: FlowIdentifier)

    func postServerQuery(_: ServerQuery, within: ObvContext)

    func prepareForOwnedIdentityDeletion(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws
    func finalizeOwnedIdentityDeletion(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws

    func performOwnedDeviceDiscoveryNow(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> EncryptedData

}
