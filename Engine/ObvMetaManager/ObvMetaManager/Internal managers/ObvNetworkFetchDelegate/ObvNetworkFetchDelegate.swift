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
import CoreData
import ObvEncoder
import OlvidUtils


public protocol ObvNetworkFetchDelegate: ObvManager {

    func updatedListOfOwnedIdentites(activeOwnedCryptoIdsAndCurrentDeviceUIDs: Set<OwnedCryptoIdentityAndCurrentDeviceUID>, flowId: FlowIdentifier) async throws
    
    func downloadMessages(for ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async
    func getDecryptedMessage(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) -> ObvNetworkReceivedMessageDecrypted?
    func allAttachmentsCanBeDownloadedForMessage(withId: ObvMessageIdentifier, within: ObvContext) throws -> Bool
    func allAttachmentsHaveBeenDownloadedForMessage(withId: ObvMessageIdentifier, within: ObvContext) throws -> Bool
    func attachment(withId: ObvAttachmentIdentifier, canBeDownloadedwithin: ObvContext) throws -> Bool

    func getAttachment(withId attachmentId: ObvAttachmentIdentifier, within obvContext: ObvContext) -> ObvNetworkFetchReceivedAttachment?
    
    func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) async -> Bool
    func processCompletionHandler(_: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier: String, withinFlowId: FlowIdentifier) async

    func deleteApplicationMessageAndAttachments(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) async throws
    func markApplicationMessageForDeletionAndProcessAttachments(messageId: ObvMessageIdentifier, attachmentsProcessingRequest: ObvAttachmentsProcessingRequest, flowId: FlowIdentifier) async throws
    func markAttachmentForDeletion(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws
    func resumeDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws
    func appCouldNotFindFileOfDownloadedAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws
    func pauseDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws
    func requestDownloadAttachmentProgressesUpdatedSince(date: Date) async throws -> [ObvAttachmentIdentifier: Float]

    func registerPushNotification(_ pushNotification: ObvPushNotificationType, flowId: FlowIdentifier) async throws

    func sendDeleteReturnReceipt(ownedIdentity: ObvCryptoIdentity, serverUid: UID) async throws
    
    func getWebSocketState(ownedIdentity: ObvCryptoIdentity) async throws -> (state: URLSessionTask.State, pingInterval: TimeInterval?)
    func connectWebsockets(activeOwnedCryptoIdsAndCurrentDeviceUIDs: Set<OwnedCryptoIdentityAndCurrentDeviceUID>, flowId: FlowIdentifier) async throws
    func disconnectWebsockets(flowId: FlowIdentifier) async

    func getTurnCredentials(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> ObvTurnCredentials

    func refreshAPIPermissions(of ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> APIKeyElements
    func queryAPIKeyStatus(for identity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) async throws -> APIKeyElements
    func registerOwnedAPIKeyOnServerNow(ownedCryptoIdentity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) async throws -> ObvRegisterApiKeyResult
    func queryFreeTrial(for identity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> Bool
    func startFreeTrial(for identity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> APIKeyElements
    func verifyReceiptAndRefreshAPIPermissions(appStoreReceiptElements: ObvAppStoreReceipt, flowId: FlowIdentifier) async throws -> [ObvCryptoIdentity : ObvAppStoreReceipt.VerificationStatus]
    // func verifyReceipt(ownedCryptoIdentities: [ObvCryptoIdentity], receiptData: String, transactionIdentifier: String, flowId: FlowIdentifier)
    func queryServerWellKnown(serverURL: URL, flowId: FlowIdentifier) async throws

    func postServerQuery(_: ServerQuery, within: ObvContext)

    func prepareForOwnedIdentityDeletion(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws
    func finalizeOwnedIdentityDeletion(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws

    func performOwnedDeviceDiscoveryNow(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> EncryptedData

}
