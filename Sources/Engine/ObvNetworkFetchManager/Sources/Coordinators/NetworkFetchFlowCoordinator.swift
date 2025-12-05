/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OSLog
import CoreData
import ObvCrypto
import ObvTypes
import ObvMetaManager
import ObvEncoder
import Network
import OlvidUtils
import ObvServerInterface


final class NetworkFetchFlowCoordinator: NetworkFetchFlowDelegate, ObvErrorMaker {

    private static let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    private static let logCategory = "NetworkFetchFlowCoordinator"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
    private static var logger = Logger(subsystem: defaultLogSubsystem, category: logCategory)

    private let nwPathMonitor = NWPathMonitor()
    private var lastNWPathStatus: NWPath.Status?

    weak var delegateManager: ObvNetworkFetchDelegateManager?
    
    static let errorDomain = "NetworkFetchFlowCoordinator"

    private let prng: PRNGService

    init(prng: PRNGService, logPrefix: String) {
        self.prng = prng
        let logSubsystem = "\(logPrefix).\(Self.defaultLogSubsystem)"
        Self.log = OSLog(subsystem: logSubsystem, category: Self.logCategory)
        Self.logger = Logger(subsystem: logSubsystem, category: Self.logCategory)
        monitorNetworkChanges()
        Task {
            await PendingServerQuery.addObvObserver(self)
        }
    }
    
}


// MARK: - NetworkFetchFlowDelegate

extension NetworkFetchFlowCoordinator {
    
    func updatedListOfOwnedIdentites(activeOwnedCryptoIdsAndCurrentDeviceUIDs: Set<OwnedCryptoIdentityAndCurrentDeviceUID>, flowId: FlowIdentifier) async throws {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        try await delegateManager.wellKnownCacheDelegate.updatedListOfOwnedIdentites(ownedIdentities: Set(activeOwnedCryptoIdsAndCurrentDeviceUIDs.map({ $0.ownedCryptoId })), flowId: flowId)
        
        try await delegateManager.webSocketDelegate.connectUpdatedListOfOwnedIdentites(activeOwnedCryptoIdsAndCurrentDeviceUIDs: activeOwnedCryptoIdsAndCurrentDeviceUIDs, flowId: flowId)
        
    }
    
    // MARK: - Session's Challenge/Response/Token related methods
    
    /// Refreshes the `APIKeyElements` for the specified owned identity.
    ///
    /// This method performs the following steps:
    /// 1. Deletes the existing server session associated with the owned identity.
    /// 2. Requests a new session from the server. This session contains the lastest `APIKeyElements`.
    /// 3. Triggers a notification to the app, prompting it to persist the new `APIKeyElements` in the local database.
    ///
    /// - Parameter ownedIdentity: The identity whose `APIKeyElements` will be refreshed.
    func refreshAPIPermissions(of ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws {

        guard let delegateManager else {
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        try await delegateManager.serverSessionDelegate.deleteServerSession(of: ownedCryptoIdentity, flowId: flowId)

        _ = try await getValidServerSessionToken(for: ownedCryptoIdentity, currentInvalidToken: nil, flowId: flowId)
        
    }
    
    
    func getValidServerSessionToken(for ownedCryptoIdentity: ObvCryptoIdentity, currentInvalidToken: Data?, flowId: FlowIdentifier) async throws -> (serverSessionToken: Data, apiKeyElements: APIKeyElements) {
        guard let delegateManager else {
            assertionFailure()
            throw Self.makeError(message: "The delegate manager is not set")
        }
        let (serverSessionToken, apiKeyElements) = try await delegateManager.serverSessionDelegate.getValidServerSessionToken(for: ownedCryptoIdentity, currentInvalidToken: currentInvalidToken, flowId: flowId)
        
        newAPIKeyElementsForCurrentAPIKeyOf(ownedCryptoIdentity, apiKeyStatus: apiKeyElements.status, apiPermissions: apiKeyElements.permissions, apiKeyExpirationDate: apiKeyElements.expirationDate, flowId: flowId)
        
        return (serverSessionToken, apiKeyElements)
    }
    

    func verifyReceiptAndRefreshAPIPermissions(appStoreReceiptElements: ObvAppStoreReceipt, environment: ObvAppStoreEnvironment, flowId: FlowIdentifier) async throws -> [ObvCryptoIdentity : ObvAppStoreReceipt.VerificationStatus] {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw Self.makeError(message: "The Delegate Manager is not set")
        }
        
        guard let verifyReceiptDelegate = delegateManager.verifyReceiptDelegate else {
            os_log("The verifyReceiptDelegate delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw Self.makeError(message: "The verifyReceiptDelegate delegate is not set")
        }

        let receiptVerificationResults = try await verifyReceiptDelegate.verifyReceipt(appStoreReceiptElements: appStoreReceiptElements, environment: environment, flowId: flowId)
        
        for result in receiptVerificationResults {
            switch result.value {
            case .failed:
                break
            case .succeededAndSubscriptionIsValid, .succeededButSubscriptionIsExpired:
                switch environment {
                case .production, .sandbox:
                    // In production/sandbox, refresh the API permissions by calling the Olvid server
                    _ = try await refreshAPIPermissions(of: result.key, flowId: flowId)
                case .xcode:
                    // When the receipt is generated by Xcode, it is not sent to the server, so refreshing the permissions makes no sens. We simulate
                    // a change of the api permissions for UI testing purposes. We give some time to the subscription manager to update its current subscription.
                    newAPIKeyElementsForCurrentAPIKeyOf(result.key, apiKeyStatus: .valid, apiPermissions: [.canCall, .multidevice], apiKeyExpirationDate: Date.now.addingTimeInterval(.init(days: 1)), flowId: flowId)
                }
            }
        }
        
        return receiptVerificationResults
        
    }
    
    
    enum ObvError: LocalizedError {
        case theDelegateManagerIsNotSet
        case theContextCreatorIsNotSet
        case theIdentityDelegateIsNotSet
        case invalidServerResponse
        case serverReturnedGeneralError
        case couldNotProcessMessageMarkedForDeletion
        case registerAPIKeyFailedAsTheAPIKeyIsInvalid
        case registerAPIKeyFailedWithGeneralError
        case registerAPIKeyFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .theDelegateManagerIsNotSet:
                return "The delegate manager is not set"
            case .theIdentityDelegateIsNotSet:
                return "The identity delegate is not set"
            case .invalidServerResponse:
                return "Invalid server response"
            case .serverReturnedGeneralError:
                return "The server returned a general error"
            case .theContextCreatorIsNotSet:
                return "The context creator is not set"
            case .couldNotProcessMessageMarkedForDeletion:
                return "Could not process message marked for deletion"
            case .registerAPIKeyFailedAsTheAPIKeyIsInvalid:
                return "The API key is invalid"
            case .registerAPIKeyFailed(let error):
                return "The API key registration failed with the following error: \(error)"
            case .registerAPIKeyFailedWithGeneralError:
                return "The API key registration failed with a general error"
            }
        }
    }
    
    
    func queryAPIKeyStatus(for ownedCryptoIdentity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) async throws -> APIKeyElements {
        
        let method = QueryApiKeyStatusServerMethod(ownedIdentity: ownedCryptoIdentity, apiKey: apiKey, flowId: flowId)
        let (data, response) = try await URLSession.shared.data(for: method.getURLRequest())

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ObvError.invalidServerResponse
        }
        
        let result = QueryApiKeyStatusServerMethod.parseObvServerResponse(responseData: data, using: Self.log)
        
        switch result {
        case .failure:
            throw ObvError.invalidServerResponse
        case .success(let serverReturnStatus):
            switch serverReturnStatus {
            case .generalError:
                throw ObvError.serverReturnedGeneralError
            case .ok(apiKeyElements: let apiKeyElements):
                return apiKeyElements
            }
        }
        
    }
    
    
    
    func registerOwnedAPIKeyOnServerNow(ownedCryptoIdentity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) async throws {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theIdentityDelegateIsNotSet
        }

        let serverSessionToken = try await getValidServerSessionToken(for: ownedCryptoIdentity, currentInvalidToken: nil, flowId: flowId).serverSessionToken
        
        let method = ObvRegisterAPIKeyServerMethod(ownedIdentity: ownedCryptoIdentity, serverSessionToken: serverSessionToken, apiKey: apiKey, identityDelegate: identityDelegate, flowId: flowId)
        let (data, response) = try await URLSession.shared.data(for: method.getURLRequest())
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ObvError.invalidServerResponse
        }
        
        let result = ObvRegisterAPIKeyServerMethod.parseObvServerResponse(responseData: data, using: Self.log)
        
        switch result {
        case .failure(let error):
            os_log("The call to ObvRegisterAPIKeyServerMethod did fail: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            throw ObvError.registerAPIKeyFailed(error)
        case .success(let serverReturnStatus):
            switch serverReturnStatus {
            case .ok:
                // After registering a new API key on the server, we force the refresh of the session to make sure the API keys elements (permissions) are refreshed
                _ = try? await getValidServerSessionToken(for: ownedCryptoIdentity, currentInvalidToken: serverSessionToken, flowId: flowId)
                return
            case .invalidSession:
                _ = try await getValidServerSessionToken(for: ownedCryptoIdentity, currentInvalidToken: serverSessionToken, flowId: flowId)
                return try await registerOwnedAPIKeyOnServerNow(ownedCryptoIdentity: ownedCryptoIdentity, apiKey: apiKey, flowId: flowId)
            case .invalidAPIKey:
                throw ObvError.registerAPIKeyFailedAsTheAPIKeyIsInvalid
            case .generalError:
                throw ObvError.registerAPIKeyFailedWithGeneralError
            }
        }
        
    }
    
    
    private func newAPIKeyElementsForCurrentAPIKeyOf(_ ownedIdentity: ObvCryptoIdentity, apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?, flowId: FlowIdentifier) {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            return
        }

        ObvNetworkFetchNotificationNew.newAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(ownedIdentity: ownedIdentity,
                                                                                        apiKeyStatus: apiKeyStatus,
                                                                                        apiPermissions: apiPermissions,
                                                                                        apiKeyExpirationDate: apiKeyExpirationDate)
        .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)

    }
    
    
    // MARK: - Attachment's related methods
    
    func resumeDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws {

        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        try await delegateManager.downloadAttachmentChunksDelegate.resumeDownloadOfAttachmentsNotAlreadyDownloading(downloadKind: .specificDownloadableAttachmentsWithoutSession(attachmentId: attachmentId, resumeRequestedByApp: true), flowId: flowId)
        
    }

    
    func pauseDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws {

        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        try await delegateManager.downloadAttachmentChunksDelegate.pauseDownloadOfAttachment(attachmentId: attachmentId, flowId: flowId)
        
    }
    
    func requestDownloadAttachmentProgressesUpdatedSince(date: Date) async throws -> [ObvAttachmentIdentifier: Float] {

        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            throw Self.makeError(message: "The Delegate Manager is not set")
        }
        
        return await delegateManager.downloadAttachmentChunksDelegate.requestDownloadAttachmentProgressesUpdatedSince(date: date)
        
    }

    func attachmentWasCancelledByServer(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            return
        }
        
        ObvNetworkFetchNotificationNew.inboxAttachmentDownloadCancelledByServer(attachmentId: attachmentId, flowId: flowId)
            .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)

    }

    func attachmentWasDownloaded(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) {
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            return
        }
        ObvNetworkFetchNotificationNew.inboxAttachmentWasDownloaded(attachmentId: attachmentId, flowId: flowId)
            .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)

    }
        

    // MARK: - Push notification's related methods

    func serverReportedThatThisDeviceIsNotRegistered(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
     
        os_log("We need to re-register to push notifications since the server reported that this device is not registered", log: Self.log, type: .info)

        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            return
        }

        ObvNetworkFetchNotificationNew.serverRequiresThisDeviceToRegisterToPushNotifications(ownedIdentity: ownedIdentity, flowId: flowId)
            .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)

    }
    
    
    func fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            return
        }
        
        ObvNetworkFetchNotificationNew.fetchNetworkOperationFailedSinceOwnedIdentityIsNotActive(ownedIdentity: ownedIdentity, flowId: flowId)
            .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)

    }

    // MARK: - Handling Server Queries

    func postServerQuery(_ serverQuery: ServerQuery, within context: NSManagedObjectContext) {
        _ = PendingServerQuery.createPendingServerQuery(serverQuery: serverQuery, within: context)
        // Note that since we are a `PendingServerQueryObserver`, we will process the new `PendingServerQuery` once the context is saved
    }


    // MARK: - Forwarding urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) and notifying successfull/failed listing (for performing fetchCompletionHandlers within the engine)

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    }

    // MARK: - Monitor Network Path Status
    
    private func monitorNetworkChanges() {
        nwPathMonitor.start(queue: DispatchQueue(label: "NetworkFetchMonitor"))
        nwPathMonitor.pathUpdateHandler = self.networkPathDidChange
    }

    
    private func networkPathDidChange(nwPath: NWPath) {
        // The nwPath status changes very early during the network status change. This is the reason why we wait before trying to reconnect. This is not bullet proof though, as the `networkPathDidChange` method does not seem to be called at every network change... This is unfortunate. Last but not least, it is very hard to work with nwPath.status so we don't even look at it.
        guard lastNWPathStatus != nwPath.status else { return }
        lastNWPathStatus = nwPath.status
        Task {
            debugPrint("🏓 nwPath.status = \(nwPath.status)")
            let flowId = FlowIdentifier()
            if nwPath.status == .satisfied {
                await delegateManager?.webSocketDelegate.disconnectThenReconnectOnSatisfiedNetworkPathStatus(flowId: flowId)
            }
        }
    }

    
    // MARK: - Reacting to changes within the WellKnownCoordinator
    
    func newWellKnownWasCached(server: URL, newWellKnownJSON: WellKnownJSON, flowId: FlowIdentifier) {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }

        os_log("New well known was cached", log: Self.log, type: .info)

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
        
        Task {
            // On Android, this notification is not sent when `wellKnownHasBeenUpdated` is sent. But we agreed that this is better ;-)
            ObvNetworkFetchNotificationNew.wellKnownHasBeenDownloaded(serverURL: server, appInfo: newWellKnownJSON.appInfo, flowId: flowId)
                .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)
        }

    }
    
    
    func cachedWellKnownWasUpdated(server: URL, newWellKnownJSON: WellKnownJSON, flowId: FlowIdentifier) {

        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            return
        }

        Task {
            ObvNetworkFetchNotificationNew.wellKnownHasBeenUpdated(serverURL: server, appInfo: newWellKnownJSON.appInfo, flowId: flowId)
                .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)
        }
        
    }
    
    
    func currentCachedWellKnownCorrespondToThatOnServer(server: URL, wellKnownJSON: WellKnownJSON, flowId: FlowIdentifier) {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            return
        }

        ObvNetworkFetchNotificationNew.wellKnownHasBeenDownloaded(serverURL: server, appInfo: wellKnownJSON.appInfo, flowId: flowId)
            .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)

    }
    
    
    // MARK: - Reacting to web socket changes
    
    func successfulWebSocketRegistration(identity: ObvCryptoIdentity) async {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }

        let flowId = FlowIdentifier()
        
        ObvDisplayableLogs.shared.log("[🚩][\(flowId.shortDebugDescription)] Will call downloadMessagesAndListAttachments on successful web socket registration")
        
        await delegateManager.messagesDelegate.downloadAllMessagesAndListAttachments(ownedCryptoId: identity, flowId: flowId)
        
    }

}


// MARK: - Implementing PendingServerQueryObserver

extension NetworkFetchFlowCoordinator: PendingServerQueryObserver {
    
    func aPendingServerQueryWasInserted(objectID: NSManagedObjectID, isWebSocket: Bool) async {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            return
        }
        
        let flowId = FlowIdentifier()

        if isWebSocket {
            do {
                try await delegateManager.serverQueryWebSocketDelegate.handleServerQuery(
                    pendingServerQueryObjectId: objectID,
                    flowId: flowId)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        } else {
            do {
                try await delegateManager.serverQueryDelegate.processPendingServerQuery(
                    pendingServerQueryObjectID: objectID,
                    flowId: flowId)
            } catch {
                assertionFailure()
            }
        }

    }
    
}
