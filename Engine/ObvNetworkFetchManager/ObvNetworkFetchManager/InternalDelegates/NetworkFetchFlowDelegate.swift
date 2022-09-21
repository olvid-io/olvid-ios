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
import CoreData
import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils

protocol NetworkFetchFlowDelegate {
    
    func updatedListOfOwnedIdentites(ownedIdentities: Set<ObvCryptoIdentity>, flowId: FlowIdentifier)

    // MARK: - Session's Challenge/Response/Token related methods
    
    func resetServerSession(for identity: ObvCryptoIdentity, within obvContext: ObvContext) throws
    func serverSessionRequired(for: ObvCryptoIdentity, flowId: FlowIdentifier) throws
    func serverSession(of: ObvCryptoIdentity, hasInvalidToken: Data, flowId: FlowIdentifier) throws
    func getAndSolveChallengeWasNotNeeded(for: ObvCryptoIdentity, flowId: FlowIdentifier)
    func failedToGetOrSolveChallenge(for: ObvCryptoIdentity, flowId: FlowIdentifier)
    
    func newChallengeResponse(for: ObvCryptoIdentity, flowId: FlowIdentifier) throws
    func getTokenWasNotNeeded(for: ObvCryptoIdentity, flowId: FlowIdentifier)
    func failedToGetToken(for: ObvCryptoIdentity, flowId: FlowIdentifier)
    func newToken(_ token: Data, for: ObvCryptoIdentity, flowId: FlowIdentifier)
    func newAPIKeyElementsForCurrentAPIKeyOf(_ ownedIdentity: ObvCryptoIdentity, apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?, flowId: FlowIdentifier)
    func newAPIKeyElementsForAPIKey(serverURL: URL, apiKey: UUID, apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?, flowId: FlowIdentifier)
    func verifyReceipt(ownedIdentity: ObvCryptoIdentity, receiptData: String, transactionIdentifier: String, flowId: FlowIdentifier)
    func apiKeyStatusQueryFailed(ownedIdentity: ObvCryptoIdentity, apiKey: UUID)

    func newFreeTrialAPIKeyForOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier)
    func noMoreFreeTrialAPIKeyAvailableForOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
    func freeTrialIsStillAvailableForOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)

    // MARK: - Downloading message and listing attachments
    
    func downloadingMessagesAndListingAttachmentFailed(for: ObvCryptoIdentity, andDeviceUid: UID, flowId: FlowIdentifier)
    func downloadingMessagesAndListingAttachmentWasNotNeeded(for: ObvCryptoIdentity, andDeviceUid: UID, flowId: FlowIdentifier)
    func downloadingMessagesAndListingAttachmentWasPerformed(for: ObvCryptoIdentity, andDeviceUid: UID, flowId: FlowIdentifier)
    func aMessageReceivedThroughTheWebsocketWasSavedByTheMessageDelegate(flowId: FlowIdentifier)
    func processUnprocessedMessages(flowId: FlowIdentifier)
    func messagePayloadAndFromIdentityWereSet(messageId: MessageIdentifier, attachmentIds: [AttachmentIdentifier], hasEncryptedExtendedMessagePayload: Bool, flowId: FlowIdentifier)
    
    // MARK: - Downloading encrypted extended message payload
    
    func downloadingMessageExtendedPayloadFailed(messageId: MessageIdentifier, flowId: FlowIdentifier)
    func downloadingMessageExtendedPayloadWasPerformed(messageId: MessageIdentifier, extendedMessagePayload: Data, flowId: FlowIdentifier)
    
    // MARK: - Attachment's related methods
    
    func resumeDownloadOfAttachment(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier)
    func pauseDownloadOfAttachment(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier)
    func attachmentWasDownloaded(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier)
    func attachmentWasCancelledByServer(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier)
    func requestDownloadAttachmentProgressesUpdatedSince(date: Date) async throws -> [AttachmentIdentifier: Float]

    // MARK: - Deletion related methods
    
    func newPendingDeleteToProcessForMessage(messageId: MessageIdentifier, flowId: FlowIdentifier)
    func failedToProcessPendingDeleteFromServer(messageId: MessageIdentifier, flowId: FlowIdentifier)
    func messageAndAttachmentsWereDeletedFromServerAndInboxes(messageId: MessageIdentifier, flowId: FlowIdentifier)
    
    // MARK: - Push notification's related methods
    
    func newRegisteredPushNotificationToProcess(for: ObvCryptoIdentity, withDeviceUid: UID, flowId: FlowIdentifier) throws
    func failedToProcessRegisteredPushNotification(for: ObvCryptoIdentity, withDeviceUid: UID, flowId: FlowIdentifier)
    func pollingRequested(for: ObvCryptoIdentity, withDeviceUid: UID, andPollingIdentifier: UUID, flowId: FlowIdentifier)
    func serverReportedThatAnotherDeviceIsAlreadyRegistered(forOwnedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
    func serverReportedThatThisDeviceWasSuccessfullyRegistered(forOwnedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
    func serverReportedThatThisDeviceIsNotRegistered(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
    func fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)

    // MARK: - Handling Server Queries

    func post(_: ServerQuery, within: ObvContext)
    func newPendingServerQueryToProcessWithObjectId(_: NSManagedObjectID, flowId: FlowIdentifier)
    func failedToProcessServerQuery(withObjectId: NSManagedObjectID, flowId: FlowIdentifier)
    func successfullProcessOfServerQuery(withObjectId: NSManagedObjectID, flowId: FlowIdentifier)
    func pendingServerQueryWasDeletedFromDatabase(objectId: NSManagedObjectID, flowId: FlowIdentifier)

    // MARK: - Handling user data

    func failedToProcessServerUserData(input: ServerUserDataInput, flowId: FlowIdentifier)

    // MARK: - Finalizing the initialization and handling events
    
    func resetAllFailedFetchAttempsCountersAndRetryFetching()
    
    // MARK: - Forwarding urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) and notifying successfull/failed listing (for performing fetchCompletionHandlers within the engine)

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession)

    // MARK: - Reacting to changes within the WellKnownCoordinator
    
    func newWellKnownWasCached(server: URL, newWellKnownJSON: WellKnownJSON, flowId: FlowIdentifier)
    func cachedWellKnownWasUpdated(server: URL, newWellKnownJSON: WellKnownJSON, flowId: FlowIdentifier)
    func currentCachedWellKnownCorrespondToThatOnServer(server: URL, wellKnownJSON: WellKnownJSON, flowId: FlowIdentifier)
    func failedToQueryServerWellKnown(serverURL: URL, flowId: FlowIdentifier)
    
    // MARK: - Reacting to web socket changes
    
    func successfulWebSocketRegistration(identity: ObvCryptoIdentity, deviceUid: UID)

}
