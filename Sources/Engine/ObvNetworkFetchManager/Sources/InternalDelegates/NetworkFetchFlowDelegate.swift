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
import CoreData
import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils

protocol NetworkFetchFlowDelegate {
    
    func updatedListOfOwnedIdentites(activeOwnedCryptoIdsAndCurrentDeviceUIDs: Set<OwnedCryptoIdentityAndCurrentDeviceUID>, flowId: FlowIdentifier) async throws

    // MARK: - Session's Challenge/Response/Token related methods
    
    func refreshAPIPermissions(of ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> APIKeyElements
    func getValidServerSessionToken(for ownedCryptoIdentity: ObvCryptoIdentity, currentInvalidToken: Data?, flowId: FlowIdentifier) async throws -> (serverSessionToken: Data, apiKeyElements: APIKeyElements)
    
    func verifyReceiptAndRefreshAPIPermissions(appStoreReceiptElements: ObvAppStoreReceipt, flowId: FlowIdentifier) async throws -> [ObvCryptoIdentity : ObvAppStoreReceipt.VerificationStatus]
    func queryAPIKeyStatus(for ownedCryptoIdentity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) async throws -> APIKeyElements
    func registerOwnedAPIKeyOnServerNow(ownedCryptoIdentity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) async throws -> ObvRegisterApiKeyResult

    // MARK: - Attachment's related methods
    
    func resumeDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws
    func pauseDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws
    func attachmentWasDownloaded(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier)
    func attachmentWasCancelledByServer(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier)
    func requestDownloadAttachmentProgressesUpdatedSince(date: Date) async throws -> [ObvAttachmentIdentifier: Float]
    
    // MARK: - Push notification's related methods
    
    func serverReportedThatThisDeviceIsNotRegistered(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
    func fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)

    // MARK: - Handling Server Queries

    func post(_: ServerQuery, within: ObvContext)
    func newPendingServerQueryToProcessWithObjectId(_: NSManagedObjectID, isWebSocket: Bool, flowId: FlowIdentifier) async

    // MARK: - Forwarding urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) and notifying successfull/failed listing (for performing fetchCompletionHandlers within the engine)

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession)

    // MARK: - Reacting to changes within the WellKnownCoordinator
    
    func newWellKnownWasCached(server: URL, newWellKnownJSON: WellKnownJSON, flowId: FlowIdentifier)
    func cachedWellKnownWasUpdated(server: URL, newWellKnownJSON: WellKnownJSON, flowId: FlowIdentifier)
    func currentCachedWellKnownCorrespondToThatOnServer(server: URL, wellKnownJSON: WellKnownJSON, flowId: FlowIdentifier)
    //func failedToQueryServerWellKnown(serverURL: URL, flowId: FlowIdentifier) async
    
    // MARK: - Reacting to web socket changes
    
    func successfulWebSocketRegistration(identity: ObvCryptoIdentity) async

}
