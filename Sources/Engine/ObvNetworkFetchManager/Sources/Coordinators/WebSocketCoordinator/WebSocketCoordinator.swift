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
import os.log
import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils
import ObvServerInterface
import ObvEncoder


actor WebSocketCoordinator: NSObject {
    
    private weak var delegateManager: ObvNetworkFetchDelegateManager?
    
    private var alwaysReconnect = false
            
    private let logCategory = String(describing: WebSocketCoordinator.self)
    private var log: OSLog {
        return OSLog(subsystem: delegateManager?.logSubsystem ?? "io.olvid.network.send", category: logCategory)
    }
        
    private var failedAttemptsCounterManager = FailedAttemptsCounterManager()
    private var retryManager = FetchRetryManager()

    enum ObvError: Error {
        case theDelegateManagerIsNil
        case couldNotFindWebSocketTaskForOwnedIdentity
    }
    
    func setDelegateManager(to delegateManager: ObvNetworkFetchDelegateManager) {
        self.delegateManager = delegateManager
    }

    
    private enum TaskForDeterminingWebSocketURLs {
        case inProgress(ownedCryptoIds: Set<OwnedCryptoIdentityAndCurrentDeviceUID>, task: Task<[URL: Set<OwnedCryptoIdentityAndCurrentDeviceUID>], Never>)
        case completed(ownedCryptoIds: Set<OwnedCryptoIdentityAndCurrentDeviceUID>, ownedCryptoIdsForWebSocketServerURL: [URL: Set<OwnedCryptoIdentityAndCurrentDeviceUID>])
        var ownedCryptoIds: Set<OwnedCryptoIdentityAndCurrentDeviceUID> {
            switch self {
            case .inProgress(let ownedCryptoIds, _), .completed(let ownedCryptoIds, _):
                return ownedCryptoIds
            }
        }
    }
    
    
    private enum TaskForConnectingWebSocket {
        case inProgress(webSocketServerURL: URL, task: Task<URLSessionWebSocketTask, Never>)
        case connected(webSocketServerURL: URL, runningWebSocketTask: URLSessionWebSocketTask)
        var webSocketServerURL: URL {
            switch self {
            case .inProgress(let webSocketServerURL, _), .connected(let webSocketServerURL, _):
                return webSocketServerURL
            }
        }
        var webSocketTask: URLSessionWebSocketTask? {
            switch self {
            case .inProgress:
                return nil
            case .connected(webSocketServerURL: _, runningWebSocketTask: let runningWebSocketTask):
                return runningWebSocketTask
            }
        }
    }
    
    
    private enum TaskForSendingRegisterMessage {
        case inProgress(ownedCryptoId: OwnedCryptoIdentityAndCurrentDeviceUID, webSocketTask: URLSessionWebSocketTask, task: Task<Void, Error>)
        case sent(ownedCryptoId: OwnedCryptoIdentityAndCurrentDeviceUID, webSocketTask: URLSessionWebSocketTask)
        var ownedCryptoId: OwnedCryptoIdentityAndCurrentDeviceUID {
            switch self {
            case .inProgress(ownedCryptoId: let ownedCryptoId, webSocketTask: _, task: _), .sent(ownedCryptoId: let ownedCryptoId, webSocketTask: _):
                return ownedCryptoId
            }
        }
        var webSocketTask: URLSessionWebSocketTask {
            switch self {
            case .inProgress(ownedCryptoId: _, webSocketTask: let webSocketTask, task: _), .sent(ownedCryptoId: _, webSocketTask: let webSocketTask):
                return webSocketTask
            }
        }
    }
    
    
    private var tasksForSendingRegisterMessage = [TaskForSendingRegisterMessage]()
    
    private var taskForConnectingWebSocketWithServerURL = [TaskForConnectingWebSocket]()
    
    private var ownedCryptoIdsAndCurrentDeviceUIDsForWebSocketTask = [URLSessionWebSocketTask: Set<OwnedCryptoIdentityAndCurrentDeviceUID>]()
    
    private var taskForDeterminingWebSocketURLsForOwnedCryptoIds = [TaskForDeterminingWebSocketURLs]()

    /// Used when the registration of an owned identity failed because the session is invalid
    private var serverSessionTokenUsedForRegisteringOwnedCryptoId = [ObvCryptoIdentity: Data]()
    
    /// Allows to determine the appropriate ``URLSessionWebSocketTask`` when sending a message for an owned identity
    private var webSocketTaskForOwnedCryptoId = [ObvCryptoIdentity: URLSessionWebSocketTask]()
    
    private var currentlyPingedWebSocketURL = [URLSessionWebSocketTask: Timer]()
    private let pingRunningWebSocketsInterval = TimeInterval(minutes: 2) // We perform a ping test on all running web socket tasks every 2 minutes

    /// Each time we receive a set of owned crypto ids and associated current device UIDs, we add them to this set.
    /// This makes it easy to perform a reconnect.
    private var ownedCryptoIdsToReconnect = Set<OwnedCryptoIdentityAndCurrentDeviceUID>()

}


// MARK: - WebSocketDelegate

extension WebSocketCoordinator: WebSocketDelegate {
    
    func connectUpdatedListOfOwnedIdentites(activeOwnedCryptoIdsAndCurrentDeviceUIDs: Set<OwnedCryptoIdentityAndCurrentDeviceUID>, flowId: FlowIdentifier) async throws {
        
        os_log("🏓 Call to connectAll(ownedCryptoIdsAndCurrentDeviceUIDs:flowId:)", log: log, type: .info)

        // If the known set of owned identities to reconnect differs from the new set of active identities, we disconnect/reconnect.
        // This happens when an owned identity is deleted, or when importing a new identity. In the later case, this allows to make sure that
        // we connect the websocket of this new identity, even if her websocket server is the same as the one of the previous existing identity.
        if ownedCryptoIdsToReconnect != activeOwnedCryptoIdsAndCurrentDeviceUIDs {
            os_log("🏓 Disconnecting/reconnecting all websocket as the set of owned identities changed", log: log, type: .debug)
            await disconnectAll(flowId: flowId)
        }

        os_log("🏓 Setting alwaysReconnect to true", log: log, type: .debug)

        alwaysReconnect = true
        
        ownedCryptoIdsToReconnect = activeOwnedCryptoIdsAndCurrentDeviceUIDs
        
        guard let delegateManager else {
            assertionFailure()
            throw ObvError.theDelegateManagerIsNil
        }
        
        await connectAll(delegateManager: delegateManager, flowId: flowId)
                
    }
    
    
    func disconnectAll(flowId: FlowIdentifier) async {

        os_log("🏓 Call to disconnectAll(flowId:) and setting alwaysReconnect to false", log: log, type: .info)
        
        alwaysReconnect = false
        
        let webSocketTasks = currentlyPingedWebSocketURL.keys
        for webSocketTask in webSocketTasks {
            disconnect(webSocketTask: webSocketTask, flowId: flowId)
        }

    }

    
    func disconnectThenReconnectOnSatisfiedNetworkPathStatus(flowId: FlowIdentifier) async {
        os_log("🏓 Call to disconnectThenReconnectOnChangeIfNetworkPath(flowId:)", log: log, type: .debug)
        guard let delegateManager else { return }
        await disconnectAll(flowId: flowId)
        await connectAll(delegateManager: delegateManager, flowId: flowId)
    }
    
    
    /// This method allows to ask the server to delete the return receipt with the specified serverUid, for the identity given in parameter.
    func sendDeleteReturnReceipt(ownedIdentity: ObvCryptoIdentity, serverUid: UID) async throws {
        guard let webSocketTask = webSocketTaskForOwnedCryptoId[ownedIdentity] else {
            os_log("🏓 Could not find an appropriate webSocketServerURL for this owned identity", log: log, type: .error)
            assertionFailure()
            return
        }
        guard webSocketTask.state == .running else {
            os_log("🏓 The WebSocket task associated with the owned identity is not in a running state", log: log, type: .error)
            assertionFailure()
            return
        }
        
        let deleteReturnReceiptMessage = try DeleteReturnReceipt(identity: ownedIdentity, serverUid: serverUid).getURLSessionWebSocketTaskMessage()
        assert(webSocketTask.state == URLSessionTask.State.running)
        do {
            try await webSocketTask.send(deleteReturnReceiptMessage)
            os_log("🏓 We successfully deleted a return receipt", log: log, type: .info)
        } catch {
            os_log("🏓 A return receipt failed to be deleted on server: %{public}@", log: log, type: .error, error.localizedDescription)
            assertionFailure()
        }
    }
    
    
    func getWebSocketState(ownedIdentity: ObvCryptoIdentity) async throws -> (state: URLSessionTask.State, pingInterval: TimeInterval?) {
        
        guard let webSocketTask = webSocketTaskForOwnedCryptoId[ownedIdentity] else {
            os_log("🏓 Could not find an appropriate webSocketServerURL for this owned identity", log: log, type: .error)
            assertionFailure()
            throw ObvError.couldNotFindWebSocketTaskForOwnedIdentity
        }

        let state = webSocketTask.state
        
        switch state {
        case .running:
            let pingTime = Date()
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URLSessionTask.State,TimeInterval?), Error>) in
                webSocketTask.sendPing { error in
                    if let error {
                        return continuation.resume(throwing: error)
                    } else {
                        let interval = Date().timeIntervalSince(pingTime)
                        return continuation.resume(returning: (state, interval))
                    }
                }
            }
        default:
            return (state, nil)
        }
        
    }


}


// MARK: - Connecting a WebSocket

extension WebSocketCoordinator {
    
    private func connectAll(delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) async {
        
        os_log("🏓 Call to connect all WebSockets", log: log, type: .info)
        
        let ownedCryptoIdsForWebSocketServerURL = await determineWebSocketURLs(for: ownedCryptoIdsToReconnect, delegateManager: delegateManager, flowId: flowId)
        
        for (webSocketServerURL, ownedCryptoIds) in ownedCryptoIdsForWebSocketServerURL {
            await connectWebSocket(with: webSocketServerURL, for: ownedCryptoIds, delegateManager: delegateManager, flowId: flowId)
            // The newConnectedAndRunningWebSocketTask(webSocketTask:) method will be called once the WebSocket is connected and running
        }
        
    }

    
    private func newConnectedAndRunningWebSocketTask(webSocketTask: URLSessionWebSocketTask) async {
        
        guard let delegateManager else { assertionFailure("This cannot happen"); return }

        failedAttemptsCounterManager.reset(counter: .webSocketTask(webSocketServerURL: webSocketTask.originalRequest?.url))

        let flowId = FlowIdentifier()

        guard let ownedCryptoIds = ownedCryptoIdsAndCurrentDeviceUIDsForWebSocketTask[webSocketTask] else {
            assertionFailure()
            return
        }
        
        continuouslyReadMessages(on: webSocketTask, flowId: flowId)
        continuouslyPingWebSocket(on: webSocketTask, flowId: flowId)

        var failedToSendAtLeastOneRegisterMessage = false
        
        for ownedCryptoId in ownedCryptoIds {
            do {
                try await sendRegisterMessage(for: ownedCryptoId, on: webSocketTask, delegateManager: delegateManager, flowId: flowId)
            } catch {
                failedToSendAtLeastOneRegisterMessage = true
                clearAllCache(for: ownedCryptoId, webSocketTask: webSocketTask, flowId: flowId)
            }
        }
        
        if failedToSendAtLeastOneRegisterMessage {
            let delay = failedAttemptsCounterManager.incrementAndGetDelay(.sendingWebSocketRegisterMessage)
            os_log("🏓 Will retry the call to connectAll in %f seconds", log: log, type: .error, Double(delay) / 1000.0)
            await retryManager.waitForDelay(milliseconds: delay)
            await connectAll(delegateManager: delegateManager, flowId: flowId)
        } else {
            failedAttemptsCounterManager.reset(counter: .sendingWebSocketRegisterMessage)
        }

    }
 
    
    /// Helper method for ``newConnectedAndRunningWebSocketTask(webSocketTask:)``
    private func clearAllCache(for ownedCryptoIdAndCurrentDeviceUID: OwnedCryptoIdentityAndCurrentDeviceUID, webSocketTask: URLSessionWebSocketTask, flowId: FlowIdentifier) {
        taskForDeterminingWebSocketURLsForOwnedCryptoIds.removeAll(where: { $0.ownedCryptoIds.contains(ownedCryptoIdAndCurrentDeviceUID) })
        disconnect(webSocketTask: webSocketTask, flowId: flowId)
    }
    
}


// MARK: - Disconnecting/Reconnecting a WebSocket

extension WebSocketCoordinator {
    
    private func disconnect(webSocketTask: URLSessionWebSocketTask, flowId: FlowIdentifier) {
        
        webSocketTask.cancel(with: .normalClosure, reason: nil)
        // Remove cache from tasksForSendingRegisterMessage
        tasksForSendingRegisterMessage.removeAll(where: { $0.webSocketTask == webSocketTask })
        
        // Remove cache from taskForConnectingWebSocketWithServerURL
        taskForConnectingWebSocketWithServerURL.removeAll(where: { $0.webSocketTask == webSocketTask })
        
        // Remove cache from ownedCryptoIdsAndCurrentDeviceUIDsForWebSocketTask
        ownedCryptoIdsAndCurrentDeviceUIDsForWebSocketTask.removeValue(forKey: webSocketTask)
        
        // Remove cache from webSocketTaskForOwnedCryptoId
        // Rember that dictionaries are value types in Swift, so the following method works
        webSocketTaskForOwnedCryptoId
            .filter { $0.value == webSocketTask }
            .forEach { webSocketTaskForOwnedCryptoId.removeValue(forKey: $0.key) }
        
        // Remove cache from currentlyPingedWebSocketURL
        stopContinuouslyPingWebSocket(on: webSocketTask)
        currentlyPingedWebSocketURL.removeValue(forKey: webSocketTask)
        
    }
    
    
    private func disconnectThenReconnect(webSocketTask: URLSessionWebSocketTask, flowId: FlowIdentifier) {
        disconnect(webSocketTask: webSocketTask, flowId: flowId)
        guard let delegateManager else { assertionFailure("Cannot happen"); return  }
        Task { await connectAll(delegateManager: delegateManager, flowId: flowId) }
    }
    
    
    private func disconnectThenReconnectIfAppropriate(webSocketTask: URLSessionWebSocketTask, flowId: FlowIdentifier) {
        os_log("🏓 Call to disconnectThenReconnectIfAppropriate(webSocketTask:flowId:) for WebSocket with server URL %{public}@", log: log, type: .info, String(describing: webSocketTask.originalRequest?.url))
        disconnect(webSocketTask: webSocketTask, flowId: flowId)
        guard alwaysReconnect else { return }
        guard let delegateManager else { assertionFailure("Cannot happen"); return  }
        Task { await connectAll(delegateManager: delegateManager, flowId: flowId) }
    }
    
    
    private func disconnectThenReconnectIfAppropriateAfterDelay(webSocketTask: URLSessionWebSocketTask, flowId: FlowIdentifier) async {
        assert(webSocketTask.originalRequest?.url != nil)
        let delay = failedAttemptsCounterManager.incrementAndGetDelay(.webSocketTask(webSocketServerURL: webSocketTask.originalRequest?.url))
        os_log("🏓 Will wait for %f seconds before calling disconnectThenReconnectIfAppropriate(webSocketTask:flowId:)", log: log, type: .info, Double(delay) / 1000.0)
        await retryManager.waitForDelay(milliseconds: delay)
        if webSocketTaskForOwnedCryptoId.values.contains(where: { $0 != webSocketTask && $0.originalRequest?.url == webSocketTask.originalRequest?.url && $0.state == .running }) {
            os_log("🏓 Another WebSocket is already handling the same URL as the WebSocket waiting for reconnection. Nothing left to do.", log: log, type: .info, Double(delay) / 1000.0)
            return
        }
        disconnectThenReconnectIfAppropriate(webSocketTask: webSocketTask, flowId: flowId)
    }
    
}


// MARK: - Continuously read messages on a WebSocket

extension WebSocketCoordinator {
    
    private func continuouslyReadMessages(on webSocketTask: URLSessionWebSocketTask, flowId: FlowIdentifier) {
        
        os_log("🏓✅ Will receive on webSocketTask %d for URL %{public}@", log: log, type: .info, webSocketTask.taskIdentifier, String(describing: webSocketTask.originalRequest?.url))
        let log = self.log

        webSocketTask.receive { result in
            switch result {
            case .failure(let error):
                os_log("🏓 Failed to receive a result on a WebSocket: %{public}@", log: log, type: .error, error.localizedDescription)
                Task { [weak self] in await self?.failedToReadMessage(on: webSocketTask, flowId: flowId) }
                return
            case .success(let message):
                switch message {
                case .data:
                    os_log("🏓 Data received on websocket. This is unexpected.", log: log, type: .error)
                    assertionFailure()
                    Task { [weak self] in await self?.continuouslyReadMessages(on: webSocketTask, flowId: flowId) }
                    return
                case .string(let string):
                    os_log("🏓 String received on websocket: %{public}@", log: log, type: .info, string)
                    Task { [weak self] in
                        do {
                            try await self?.parseString(string, receivedOn: webSocketTask, flowId: flowId)
                        } catch {
                            os_log("🏓 Failed to parse received string: %{public}@", log: log, type: .error, error.localizedDescription)
                            assertionFailure(error.localizedDescription)
                            // Continue anyway
                        }
                        await self?.continuouslyReadMessages(on: webSocketTask, flowId: flowId)
                    }
                    return
                @unknown default:
                    assertionFailure()
                    Task { [weak self] in await self?.failedToReadMessage(on: webSocketTask, flowId: flowId) }
                    return
                }
            }
        }
        
    }
    
    
    private func failedToReadMessage(on webSocketTask: URLSessionWebSocketTask, flowId: FlowIdentifier) {
        disconnectThenReconnect(webSocketTask: webSocketTask, flowId: flowId)
    }
    
    
    private func parseString(_ stringReceived: String, receivedOn webSocketTask: URLSessionWebSocketTask, flowId: FlowIdentifier) throws {
        
        guard let delegateManager else {
            assertionFailure("This cannot happen")
            throw ObvError.theDelegateManagerIsNil
        }
        
        
        if let encryptedReceivedReturnReceipt = try? ObvEncryptedReceivedReturnReceipt(string: stringReceived) {
            
            // Case #1: ReturnReceipt
            
            os_log("🏓 The server sent a ReturnReceipt", log: log, type: .info)
            if let notificationDelegate = delegateManager.notificationDelegate {
                ObvNetworkFetchNotificationNew.newReturnReceiptToProcess(encryptedReceivedReturnReceipt: encryptedReceivedReturnReceipt)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)
            }
            
        } else if let receivedMessage = try? NewMessageAvailableMessage(string: stringReceived) {
            
            // Case #2: NewMessageAvailableMessage
            
            os_log("🏓 The server notified that a new message is available for identity %{public}@", log: log, type: .info, receivedMessage.identity.debugDescription)
            if let message = receivedMessage.message {
                Task {
                    do {
                        // As the websocket notification is sent exactly when the message is uploaded on the server, we can assume that downloadTimestampFromServer = messageUploadTimestampFromServer
                        try await delegateManager.messagesDelegate.saveMessageReceivedOnWebsocket(message: message, downloadTimestampFromServer: message.messageUploadTimestampFromServer, ownedCryptoId: receivedMessage.identity, flowId: flowId)
                    } catch {
                        os_log("🏓 Failed to save the message received through the websocket: %{public}@. We request a download message and list attachments now", log: log, type: .error, error.localizedDescription)
                        await delegateManager.messagesDelegate.downloadAllMessagesAndListAttachments(ownedCryptoId: receivedMessage.identity, flowId: flowId)
                    }
                }
            } else {
                Task {
                    await delegateManager.messagesDelegate.downloadAllMessagesAndListAttachments(ownedCryptoId: receivedMessage.identity, flowId: flowId)
                }
            }
            
        } else if let receivedMessage = try? ResponseToRegisterMessage(string: stringReceived) {
            
            // Case #3: ResponseToRegisterMessage
            
            os_log("🏓 We received a proper response to the register message", log: log, type: .info)
            if let error = receivedMessage.error {
                os_log("🏓 The server reported that the registration was not successful. Error code is %{public}@", log: log, type: .error, error.debugDescription)
                switch error {
                case .general:
                    disconnectThenReconnect(webSocketTask: webSocketTask, flowId: flowId)
                case .invalidServerSession:
                    guard let ownedCryptoId = receivedMessage.identity else { assertionFailure("We expect the server to return the identity in case the server session is invalid"); return }
                    guard let serverSessionToken = serverSessionTokenUsedForRegisteringOwnedCryptoId[ownedCryptoId] else { assertionFailure("This cannot happen"); return }
                    // Make sure the server session delegate knows that this server session token is invalid
                    Task {
                        _ = try? await delegateManager.serverSessionDelegate.getValidServerSessionToken(for: ownedCryptoId, currentInvalidToken: serverSessionToken, flowId: flowId)
                        disconnectThenReconnect(webSocketTask: webSocketTask, flowId: flowId)
                    }
                case .unknownError:
                    assert(false)
                }
            } else {
                guard let concernedIdentity = receivedMessage.identity else { assertionFailure(); return }
                os_log("🏓 The server reported that the WebSocket registration was successful for identity %{public}@.", log: log, type: .info, concernedIdentity.debugDescription)
                os_log("🏓 Notifying the flow delegate about the identity/device %{public}@ concerned by the recent web socket registration.", log: log, type: .info, concernedIdentity.debugDescription)
                Task {
                    await delegateManager.networkFetchFlowDelegate.successfulWebSocketRegistration(identity: concernedIdentity)
                }
            }
            
        } else if let pushTopicMessage = try? PushTopicMessage(string: stringReceived) {
            
            // Case #4: PushTopicMessage
            
            os_log("🫸🏓 The server sent a keycloak topic message: %{public}@", log: log, type: .info, pushTopicMessage.topic)
            assert(delegateManager.notificationDelegate != nil)
            if let notificationDelegate = delegateManager.notificationDelegate {
                ObvNetworkFetchNotificationNew.pushTopicReceivedViaWebsocket(pushTopic: pushTopicMessage.topic)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)
            }
            
        } else if let targetedKeycloakPushNotification = try? KeycloakTargetedPushNotification(string: stringReceived) {
            
            // Case #5: KeycloakTargetedPushNotification
            
            os_log("🫸🏓 The server sent a targeted keycloak push notification for identity: %{public}@", log: log, type: .info, targetedKeycloakPushNotification.identity.debugDescription)
            assert(delegateManager.notificationDelegate != nil)
            if let notificationDelegate = delegateManager.notificationDelegate {
                ObvNetworkFetchNotificationNew.keycloakTargetedPushNotificationReceivedViaWebsocket(ownedIdentity: targetedKeycloakPushNotification.identity)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)
            }
            
        } else if let ownedDeviceMessage = try? OwnedDevicesMessage(string: stringReceived) {
            
            // Case #6: OwnedDevicesMessage
            
            os_log("🏓 The server sent an OwnedDevicesMessage for identity: %{public}@", log: log, type: .info, ownedDeviceMessage.identity.debugDescription)
            if let notificationDelegate = delegateManager.notificationDelegate {
                ObvNetworkFetchNotificationNew.ownedDevicesMessageReceivedViaWebsocket(ownedIdentity: ownedDeviceMessage.identity)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)
            }
            
        } else if (try? InternalServerErrorMessage(string: stringReceived)) != nil {
            
            os_log("🏓 The server returned an internal server error. We disconnect then reconnect.", log: log, type: .fault)
            disconnectThenReconnect(webSocketTask: webSocketTask, flowId: flowId)

        } else {
            
            assertionFailure("Unknown message type")
            
        }
        
    }
    
}


// MARK: - Registering owned identities

extension WebSocketCoordinator {
    
    private func sendRegisterMessage(for ownedCryptoIdAndCurrentDeviceUID: OwnedCryptoIdentityAndCurrentDeviceUID, on webSocketTask: URLSessionWebSocketTask, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) async throws {
        
        os_log("🏓 Call to sendRegisterMessage(for:on:delegateManager:flowId:) on WebSocket task %d", log: log, type: .info, webSocketTask.taskIdentifier)

        if let cached = tasksForSendingRegisterMessage.first(where: { $0.ownedCryptoId == ownedCryptoIdAndCurrentDeviceUID && $0.webSocketTask == webSocketTask }) {
            switch cached {
            case .inProgress(ownedCryptoId: _, webSocketTask: _, task: let task):
                try await task.value
            case .sent(ownedCryptoId: _, webSocketTask: _):
                return
            }
        } else {
            let task = createTaskForSendingRegisterMessage(on: webSocketTask, for: ownedCryptoIdAndCurrentDeviceUID, currentInvalidToken: nil, delegateManager: delegateManager, flowId: flowId)
            tasksForSendingRegisterMessage.append(.inProgress(ownedCryptoId: ownedCryptoIdAndCurrentDeviceUID, webSocketTask: webSocketTask, task: task))
            do {
                try await task.value
            } catch {
                tasksForSendingRegisterMessage.removeAll(where: { $0.ownedCryptoId == ownedCryptoIdAndCurrentDeviceUID && $0.webSocketTask == webSocketTask })
                throw error
            }
            tasksForSendingRegisterMessage.removeAll(where: { $0.ownedCryptoId == ownedCryptoIdAndCurrentDeviceUID && $0.webSocketTask == webSocketTask })
            tasksForSendingRegisterMessage.append(.sent(ownedCryptoId: ownedCryptoIdAndCurrentDeviceUID, webSocketTask: webSocketTask))
        }
        
    }
    
    
    /// If an error is thrown, it is an ``InternalErrorOnSendingRegisterMessage``.
    private func createTaskForSendingRegisterMessage(on webSocketTask: URLSessionWebSocketTask, for ownedCryptoIdAndCurrentDeviceUID: OwnedCryptoIdentityAndCurrentDeviceUID, currentInvalidToken: Data?, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) -> Task<Void, Error> {
        
        let serverSessionDelegate = delegateManager.serverSessionDelegate
        
        let ownedCryptoId = ownedCryptoIdAndCurrentDeviceUID.ownedCryptoId
        let currentDeviceUID = ownedCryptoIdAndCurrentDeviceUID.currentDeviceUID
        
        return Task {
            
            switch webSocketTask.state {
            case .running:
                break
            case .suspended:
                webSocketTask.resume()
            case .canceling, .completed:
                throw InternalErrorOnSendingRegisterMessage.registerMessageCouldNotBeSent
            @unknown default:
                throw InternalErrorOnSendingRegisterMessage.registerMessageCouldNotBeSent
            }

            do {
                let serverSessionToken = try await serverSessionDelegate.getValidServerSessionToken(for: ownedCryptoId, currentInvalidToken: currentInvalidToken, flowId: flowId).serverSessionToken
                serverSessionTokenUsedForRegisteringOwnedCryptoId[ownedCryptoId] = serverSessionToken
                let registerMessage = try RegisterMessage(identity: ownedCryptoId, deviceUid: currentDeviceUID, token: serverSessionToken).getURLSessionWebSocketTaskMessage()
                try await webSocketTask.send(registerMessage)
                os_log("🏓✅ We successfully sent the register message for identity %{public}@", log: log, type: .info, ownedCryptoId.debugDescription)
            } catch {
                assertionFailure()
                os_log("🏓 We could not send a register message for identity %{public}@: %{public}@", log: log, type: .error, ownedCryptoId.debugDescription, error.localizedDescription)
                throw InternalErrorOnSendingRegisterMessage.registerMessageCouldNotBeSent
            }
            
        }

    }
    
    
    private enum InternalErrorOnSendingRegisterMessage: Error {
        case registerMessageCouldNotBeSent
    }
    
}


// MARK: - Continuously ping a WebSocket

extension WebSocketCoordinator {
    
    private func continuouslyPingWebSocket(on webSocketTask: URLSessionWebSocketTask, flowId: FlowIdentifier) {
        
        guard !currentlyPingedWebSocketURL.keys.contains(webSocketTask) else { return }
        
        let log = self.log
        
        let timer = Timer(timeInterval: pingRunningWebSocketsInterval, repeats: true) { [weak self] timer in
            guard timer.isValid else { return }
            Task { [weak self] in
                guard let self else { return }
                os_log("🏓 Performing a ping test on  websocket at url %{public}@", log: log, type: .info, String(describing: webSocketTask.currentRequest?.url?.description))
                switch webSocketTask.state {
                case .running:
                    await pingTest(webSocketTask: webSocketTask, flowId: flowId)
                case .suspended:
                    webSocketTask.resume()
                case .canceling, .completed:
                    return await failedPingTest(webSocketTask: webSocketTask, flowId: flowId)
                @unknown default:
                    return await failedPingTest(webSocketTask: webSocketTask, flowId: flowId)
                }
                await pingTest(webSocketTask: webSocketTask, flowId: flowId)
            }
        }

        currentlyPingedWebSocketURL[webSocketTask] = timer

        RunLoop.main.add(timer, forMode: .common)

    }
    
    
    private func pingTest(webSocketTask: URLSessionWebSocketTask, flowId: FlowIdentifier) {
        let log = self.log
        webSocketTask.sendPing { [weak self] error in
            if let error {
                os_log("🏓 Ping failed with error: %{public}@. We disconnect the web socket task.", log: log, type: .error, error.localizedDescription)
                Task { [weak self] in await self?.failedPingTest(webSocketTask: webSocketTask, flowId: flowId) }
            } else {
                os_log("🏓 One pong received", log: log, type: .info)
            }
        }
    }

    
    private func failedPingTest(webSocketTask: URLSessionWebSocketTask, flowId: FlowIdentifier) {
        disconnectThenReconnect(webSocketTask: webSocketTask, flowId: flowId)
    }
    
    
    private func stopContinuouslyPingWebSocket(on webSocketTask: URLSessionWebSocketTask) {
        let timer = currentlyPingedWebSocketURL.removeValue(forKey: webSocketTask)
        timer?.invalidate()
    }
    
}



// MARK: - Connecting a WebSocket and obtaining its URLSessionWebSocketTask

extension WebSocketCoordinator {
    
    private func connectWebSocket(with webSocketServerURL: URL, for ownedCryptoIds: Set<OwnedCryptoIdentityAndCurrentDeviceUID>, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) async {
        
        if let cached = taskForConnectingWebSocketWithServerURL.first(where: { $0.webSocketServerURL == webSocketServerURL }) {
            let runningWebSocketTask: URLSessionWebSocketTask
            switch cached {
            case .inProgress(webSocketServerURL: _, task: let task):
                runningWebSocketTask = await task.value
            case .connected(webSocketServerURL: _, runningWebSocketTask: let _runningWebSocketTask):
                runningWebSocketTask = _runningWebSocketTask
            }
            switch runningWebSocketTask.state {
            case .running:
                return
            case .suspended:
                runningWebSocketTask.resume()
                return
            case .canceling, .completed:
                taskForConnectingWebSocketWithServerURL.removeAll(where: { $0.webSocketServerURL == webSocketServerURL })
                return await connectWebSocket(with: webSocketServerURL, for: ownedCryptoIds, delegateManager: delegateManager, flowId: flowId)
            @unknown default:
                taskForConnectingWebSocketWithServerURL.removeAll(where: { $0.webSocketServerURL == webSocketServerURL })
                return await connectWebSocket(with: webSocketServerURL, for: ownedCryptoIds, delegateManager: delegateManager, flowId: flowId)
            }
        } else {
            let task = createTaskForConnectingWebSocket(with: webSocketServerURL, for: ownedCryptoIds, delegateManager: delegateManager, flowId: flowId)
            taskForConnectingWebSocketWithServerURL.append(.inProgress(webSocketServerURL: webSocketServerURL, task: task))
            let runningWebSocketTask = await task.value
            taskForConnectingWebSocketWithServerURL.removeAll(where: { $0.webSocketServerURL == webSocketServerURL })
            taskForConnectingWebSocketWithServerURL.append(.connected(webSocketServerURL: webSocketServerURL, runningWebSocketTask: runningWebSocketTask))
            return
        }
        
    }
    
    
    private func createTaskForConnectingWebSocket(with webSocketServerURL: URL, for ownedCryptoIds: Set<OwnedCryptoIdentityAndCurrentDeviceUID>, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) -> Task<URLSessionWebSocketTask, Never> {
        return Task {
            
            let urlSessionConfiguration = URLSessionConfiguration.default
            let urlSession = URLSession(configuration: urlSessionConfiguration, delegate: self, delegateQueue: nil)
            let webSocketTask = urlSession.webSocketTask(with: webSocketServerURL)
            assert(webSocketTask.state == .suspended)
            ownedCryptoIdsAndCurrentDeviceUIDsForWebSocketTask[webSocketTask] = ownedCryptoIds
            ownedCryptoIds.map({ $0.ownedCryptoId }) .forEach { ownedCryptoId in
                webSocketTaskForOwnedCryptoId[ownedCryptoId] = webSocketTask
            }
            webSocketTask.resume()
            assert(webSocketTask.state == .running)

            return webSocketTask
            
        }
    }
        
}


// MARK: - URLSessionWebSocketDelegate

extension WebSocketCoordinator: URLSessionWebSocketDelegate {
    
    nonisolated
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol _protocol: String?) {
        assert(webSocketTask.state == .running)
        Task {
            let log = await self.log
            os_log("🏓 Call to the URLSessionWebSocketDelegate method urlSession(_:webSocketTask:didOpenWithProtocol:) for webSocketTask %{public}d", log: log, type: .debug, webSocketTask.taskIdentifier)
            await newConnectedAndRunningWebSocketTask(webSocketTask: webSocketTask)
        }
    }
    
    
    nonisolated
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let flowId = FlowIdentifier()
        Task {
            let log = await self.log
            os_log("🏓 Call to the URLSessionWebSocketDelegate method urlSession(_:webSocketTask:didCloseWith:reason:)", log: log, type: .debug)
            await disconnectThenReconnectIfAppropriateAfterDelay(webSocketTask: webSocketTask, flowId: flowId)
        }
    }

    
    nonisolated
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error != nil, let webSocketTask = task as? URLSessionWebSocketTask else { return }
        let flowId = FlowIdentifier()
        Task {
            let log = await self.log
            os_log("🏓 Call to the URLSessionWebSocketDelegate method urlSession(_:task:didCompleteWithError:)", log: log, type: .debug)
            await disconnectThenReconnectIfAppropriateAfterDelay(webSocketTask: webSocketTask, flowId: flowId)
        }
    }


}


// MARK: - Determining the WebSocket URLs of a set of owned crypto Ids and device UIDs

extension WebSocketCoordinator {
    
    private func determineWebSocketURLs(for ownedCryptoIdsAndCurrentDeviceUIDs: Set<OwnedCryptoIdentityAndCurrentDeviceUID>, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) async -> [URL: Set<OwnedCryptoIdentityAndCurrentDeviceUID>] {
        
        if let cached = taskForDeterminingWebSocketURLsForOwnedCryptoIds.first(where: { $0.ownedCryptoIds == ownedCryptoIdsAndCurrentDeviceUIDs }) {
            switch cached {
            case .inProgress(ownedCryptoIds: _, task: let task):
                return await task.value
            case .completed(ownedCryptoIds: _, ownedCryptoIdsForWebSocketServerURL: let ownedCryptoIdsForWebSocketServerURL):
                return ownedCryptoIdsForWebSocketServerURL
            }
        } else {
            let task = createTaskForDeterminingWebSocketURLs(for: ownedCryptoIdsAndCurrentDeviceUIDs, delegateManager: delegateManager, flowId: flowId)
            taskForDeterminingWebSocketURLsForOwnedCryptoIds.append(.inProgress(ownedCryptoIds: ownedCryptoIdsAndCurrentDeviceUIDs, task: task))
            let result = await task.value
            taskForDeterminingWebSocketURLsForOwnedCryptoIds.removeAll(where: { $0.ownedCryptoIds == ownedCryptoIdsAndCurrentDeviceUIDs })
            taskForDeterminingWebSocketURLsForOwnedCryptoIds.append(.completed(ownedCryptoIds: ownedCryptoIdsAndCurrentDeviceUIDs, ownedCryptoIdsForWebSocketServerURL: result))
            return result
        }
        
    }
    
    
    private func createTaskForDeterminingWebSocketURLs(for ownedCryptoIdsAndCurrentDeviceUIDs: Set<OwnedCryptoIdentityAndCurrentDeviceUID>, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) -> Task<[URL: Set<OwnedCryptoIdentityAndCurrentDeviceUID>], Never> {
        return Task {
            
            var ownedCryptoIdsForWebSocketServerURL = [URL: Set<OwnedCryptoIdentityAndCurrentDeviceUID>]()
            
            let wellKnownCacheDelegate = delegateManager.wellKnownCacheDelegate
            
            for idAndDeviceUID in ownedCryptoIdsAndCurrentDeviceUIDs {
                let ownedCryptoId = idAndDeviceUID.ownedCryptoId
                let webSocketURL: URL
                do {
                    webSocketURL = try await wellKnownCacheDelegate.getWebSocketURL(for: ownedCryptoId.serverURL, flowId: flowId)
                } catch {
                    os_log("🏓 Could not get WebSocket URL for an owned identity", log: log, type: .fault)
                    assertionFailure()
                    continue
                }
                var ownedCryptoIds = ownedCryptoIdsForWebSocketServerURL[webSocketURL, default: Set<OwnedCryptoIdentityAndCurrentDeviceUID>()]
                ownedCryptoIds.insert(idAndDeviceUID)
                ownedCryptoIdsForWebSocketServerURL[webSocketURL] = ownedCryptoIds
            }
            
            return ownedCryptoIdsForWebSocketServerURL
            
        }
    }
        
}


// MARK: - Messages exchanged on the websocket


fileprivate struct DeleteReturnReceipt: Encodable {
    
    enum CodingKeys: String, CodingKey {
        case action = "action"
        case serverUid = "serverUid"
        case identity = "identity"
    }

    let identity: ObvCryptoIdentity
    let serverUid: UID
    
    init(identity: ObvCryptoIdentity, serverUid: UID) {
        self.identity = identity
        self.serverUid = serverUid
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identity.getIdentity().base64EncodedString(), forKey: .identity)
        try container.encode(serverUid.raw.base64EncodedString(), forKey: .serverUid)
        try container.encode("delete_return_receipt", forKey: .action)
    }

    func getURLSessionWebSocketTaskMessage() throws -> URLSessionWebSocketTask.Message {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        let string = String(data: data, encoding: .utf8)!
        return URLSessionWebSocketTask.Message.string(string)
    }

}


fileprivate struct RegisterMessage: Encodable {
    
    enum CodingKeys: String, CodingKey {
        case action = "action"
        case token = "token"
        case identity = "identity"
        case deviceUid = "deviceUid"
    }

    let token: Data
    let identity: ObvCryptoIdentity
    let deviceUid: UID
    
    init(identity: ObvCryptoIdentity, deviceUid: UID, token: Data) {
        self.identity = identity
        self.deviceUid = deviceUid
        self.token = token
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(token.base64EncodedString(), forKey: .token)
        try container.encode(identity.getIdentity().base64EncodedString(), forKey: .identity)
        try container.encode(deviceUid.raw.base64EncodedString(), forKey: .deviceUid)
        try container.encode("register", forKey: .action)
    }

    func getURLSessionWebSocketTaskMessage() throws -> URLSessionWebSocketTask.Message {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        let string = String(data: data, encoding: .utf8)!
        return URLSessionWebSocketTask.Message.string(string)
    }
}


fileprivate struct ResponseToRegisterMessage: Decodable {
    
    let identity: ObvCryptoIdentity?
    private let errorCode: Int?
    
    var error: Error? {
        guard let errorCode = self.errorCode else { return nil }
        return Error(rawValue: errorCode) ?? .unknownError
    }
    
    enum Error: Int, CustomDebugStringConvertible {
        
        case general = 255
        case invalidServerSession = 4
        case unknownError = -1
        
        var debugDescription: String {
            switch self {
            case .general: return "General error"
            case .invalidServerSession: return "Invalid server session"
            case .unknownError: return "Unknown error"
            }
        }

    }
    
    private static let errorDomain = String(describing: ResponseToRegisterMessage.self)
    
    enum CodingKeys: String, CodingKey {
        case action = "action"
        case identity = "identity"
        case errorCode = "err"
    }

    private init(identity: ObvCryptoIdentity?, errorCode: Int?) throws {
        guard (identity, errorCode) != (nil, nil) else {
            let message = "Could not parse the JSON. Identity and Error cannot be both nil at the same time. This is a server error."
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: ResponseToRegisterMessage.errorDomain, code: 0, userInfo: userInfo)
        }
        self.identity = identity
        self.errorCode = errorCode
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let action = try values.decode(String.self, forKey: .action)
        guard action == "register" else {
            let message = "The received JSON is not a response to a Register Message"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: ResponseToRegisterMessage.errorDomain, code: 0, userInfo: userInfo)
        }
        let errorCode = try values.decodeIfPresent(Int.self, forKey: .errorCode)
        if let identityAsString = try values.decodeIfPresent(String.self, forKey: .identity) {
            guard let identityAsData = Data(base64Encoded: identityAsString) else {
                let message = "Could not parse the received identity"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: ResponseToRegisterMessage.errorDomain, code: 0, userInfo: userInfo)
            }
            guard let identity = ObvCryptoIdentity(from: identityAsData) else {
                let message = "Could not parse the received JSON"
                let userInfo = [NSLocalizedFailureReasonErrorKey: message]
                throw NSError(domain: ResponseToRegisterMessage.errorDomain, code: 0, userInfo: userInfo)
            }
            try self.init(identity: identity, errorCode: errorCode)
        } else {
            try self.init(identity: nil, errorCode: errorCode)
        }
    }
    
    
    init(string: String) throws {
        guard let data = string.data(using: .utf8) else {
            let message = "The received JSON is not UTF8 encoded"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: ResponseToRegisterMessage.errorDomain, code: 0, userInfo: userInfo)
        }
        let decoder = JSONDecoder()
        self = try decoder.decode(ResponseToRegisterMessage.self, from: data)
    }
    
}


fileprivate struct NewMessageAvailableMessage: Decodable {
    
    let identity: ObvCryptoIdentity
    let message: ObvServerDownloadMessagesAndListAttachmentsMethod.MessageAndAttachmentsOnServer?
    
    private static let errorDomain = String(describing: NewMessageAvailableMessage.self)
    
    enum CodingKeys: String, CodingKey {
        case action = "action"
        case identity = "identity"
        case message = "message"
    }

    private init(identity: ObvCryptoIdentity, message: ObvServerDownloadMessagesAndListAttachmentsMethod.MessageAndAttachmentsOnServer?) {
        self.identity = identity
        self.message = message
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let action = try values.decode(String.self, forKey: .action)
        guard action == "message" else {
            let message = "The received JSON is not a notification of a new message available on server"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: NewMessageAvailableMessage.errorDomain, code: 0, userInfo: userInfo)
        }
        let identityAsString = try values.decode(String.self, forKey: .identity)
        guard let identityAsData = Data(base64Encoded: identityAsString) else {
            let message = "Could not parse the received identity"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: NewMessageAvailableMessage.errorDomain, code: 0, userInfo: userInfo)
        }
        guard let identity = ObvCryptoIdentity(from: identityAsData) else {
            let message = "Could not parse the received JSON"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: NewMessageAvailableMessage.errorDomain, code: 0, userInfo: userInfo)
        }
        let message: ObvServerDownloadMessagesAndListAttachmentsMethod.MessageAndAttachmentsOnServer?
        if let messageAsString = try values.decodeIfPresent(String.self, forKey: .message),
           let messageAsData = Data(base64Encoded: messageAsString),
           let messageAsObvEncoded = ObvEncoded(withRawData: messageAsData),
           let unparsedMessageAndAttachments = [ObvEncoded](messageAsObvEncoded),
           let _message = ObvServerDownloadMessagesAndListAttachmentsMethod.parse(unparsedMessageAndAttachments: unparsedMessageAndAttachments) {
            message = _message
        } else {
            message = nil
        }
        self.init(identity: identity, message: message)
    }
    
    
    init(string: String) throws {
        guard let data = string.data(using: .utf8) else {
            let message = "The received JSON is not UTF8 encoded"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: NewMessageAvailableMessage.errorDomain, code: 0, userInfo: userInfo)
        }
        let decoder = JSONDecoder()
        self = try decoder.decode(NewMessageAvailableMessage.self, from: data)
    }

}


fileprivate struct PushTopicMessage: Decodable, ObvErrorMaker {
    
    static let errorDomain = "PushTopicMessage"
    let topic: String

    enum CodingKeys: String, CodingKey {
        case action = "action"
        case topic = "topic"
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let action = try values.decode(String.self, forKey: .action)
        guard action == "push_topic" else {
            throw Self.makeError(message: "Unexpected action. Expecting push_topic, got \(action)")
        }
        let topic = try values.decode(String.self, forKey: .topic)
        self.topic = topic
    }

    init(string: String) throws {
        guard let data = string.data(using: .utf8) else { assertionFailure(); throw Self.makeError(message: "The received JSON is not UTF8 encoded") }
        let decoder = JSONDecoder()
        self = try decoder.decode(PushTopicMessage.self, from: data)
    }
    
}


fileprivate struct KeycloakTargetedPushNotification: Decodable, ObvErrorMaker {
    
    static let errorDomain = "KeycloakTargetedPushNotification"
    let identity: ObvCryptoIdentity

    enum CodingKeys: String, CodingKey {
        case action = "action"
        case identity = "identity"
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let action = try values.decode(String.self, forKey: .action)
        guard action == "keycloak" else {
            throw Self.makeError(message: "Unexpected action. Expecting keycloak, got \(action)")
        }
        let identityAsString = try values.decode(String.self, forKey: .identity)
        guard let identityAsData = Data(base64Encoded: identityAsString) else {
            throw Self.makeError(message: "Could not parse the received identity")
        }
        guard let identity = ObvCryptoIdentity(from: identityAsData) else {
            throw Self.makeError(message: "Could not parse the received JSON")
        }
        self.identity = identity
    }

    init(string: String) throws {
        guard let data = string.data(using: .utf8) else { assertionFailure(); throw Self.makeError(message: "The received JSON is not UTF8 encoded") }
        let decoder = JSONDecoder()
        self = try decoder.decode(KeycloakTargetedPushNotification.self, from: data)
    }
    
}


fileprivate struct OwnedDevicesMessage: Decodable, ObvErrorMaker {

    static let errorDomain = "OwnedDevicesMessage"
    let identity: ObvCryptoIdentity

    enum CodingKeys: String, CodingKey {
        case action = "action"
        case identity = "identity"
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let action = try values.decode(String.self, forKey: .action)
        guard action == "ownedDevices" else {
            throw Self.makeError(message: "Unexpected action. Expecting ownedDevices, got \(action)")
        }
        let identityAsString = try values.decode(String.self, forKey: .identity)
        guard let identityAsData = Data(base64Encoded: identityAsString) else {
            throw Self.makeError(message: "Could not parse the received identity")
        }
        guard let identity = ObvCryptoIdentity(from: identityAsData) else {
            throw Self.makeError(message: "Could not parse the received JSON")
        }
        self.identity = identity
    }

    init(string: String) throws {
        guard let data = string.data(using: .utf8) else { assertionFailure(); throw Self.makeError(message: "The received JSON is not UTF8 encoded") }
        let decoder = JSONDecoder()
        self = try decoder.decode(OwnedDevicesMessage.self, from: data)
    }

}


fileprivate struct InternalServerErrorMessage: Decodable, ObvErrorMaker {
    
    static let errorDomain = "InternalServerErrorMessage"

    private let message: String
    private let connectionId: String
    private let requestId: String

    enum CodingKeys: String, CodingKey {
        case message = "message"
        case connectionId = "connectionId"
        case requestId = "requestId"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.message = try values.decode(String.self, forKey: .message)
        guard self.message == "Internal server error" else {
            throw Self.makeError(message: "Unexpected message. Expecting Internal server error, got \(message)")
        }
        self.connectionId = try values.decode(String.self, forKey: .connectionId)
        self.requestId = try values.decode(String.self, forKey: .requestId)
    }

    init(string: String) throws {
        guard let data = string.data(using: .utf8) else { assertionFailure(); throw Self.makeError(message: "The received JSON is not UTF8 encoded") }
        let decoder = JSONDecoder()
        self = try decoder.decode(InternalServerErrorMessage.self, from: data)
    }

}
