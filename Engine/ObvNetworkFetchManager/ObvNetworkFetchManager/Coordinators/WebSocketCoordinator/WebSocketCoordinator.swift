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
import os.log
import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils
import ObvServerInterface
import ObvEncoder



actor WebSocketCoordinator: NSObject, ObvErrorMaker {
    
    private weak var delegateManager: ObvNetworkFetchDelegateManager?
        
    /// For each WebSocket server, we keep a WebSocket task. This way, two identities on the same server can use the same WebSocket.
    private var webSocketTaskForWebSocketServerURL = [URL: URLSessionWebSocketTask]()
    
    /// Each owned identity much register to the server. To do so, she must provide its identity, device UID, and token.
    private var webSocketInfosForIdentity = [ObvCryptoIdentity: (deviceUid: UID?, token: Data?, webSocketServerURL: URL?)]()
    
    /// After connecting a websocket for a given `webSocketServerURL`, we need to send a register message for each identity on this `webSocketServerURL`. This table prevents sending to many of them.
    ///
    /// In order to prevent sending many register messages, we keep track of the status of the register message for each identity:
    /// - No entry means that we should send a register message.
    /// - If the status is `.registering`, we should not send a register message as one is being sent.
    /// - If the status is `.registered`, we should not send a register message as the identity is already registered.
    private var registerMessageStatusForIdentity = [ObvCryptoIdentity: RegisterMessageStatus]()

    private var disconnectTimerForUUID = [UUID: Timer]()
    
    private var receivingWebSocketTaskForURL = Set<URL>()

    private enum RegisterMessageStatus: CustomDebugStringConvertible {
        case registering
        case registered
        var debugDescription: String {
            switch self {
            case .registering: return "registering"
            case .registered: return "registered"
            }
        }
    }
    
    private let logCategory = String(describing: WebSocketCoordinator.self)
    private var log: OSLog {
        return OSLog(subsystem: delegateManager?.logSubsystem ?? "io.olvid.network.send", category: logCategory)
    }
    
    static let errorDomain = "WebSocketCoordinator"

    /// When `true`, this coordinator will always try to create, resume and register a new WebSocket when one closes/disconnects.
    /// It does this for each of the identities concerned by the closed WebSocket. If `false`, this coordinator does nothing
    /// when a WebSocket closes/disconnects.
    var alwaysReconnect = true

    private var pingRunningWebSocketsTimer: Timer?
    private let pingRunningWebSocketsInterval: TimeInterval = 120.0 // We perform a ping test on all running web socket tasks every 2 minutes
    private let maxTimeIntervalAllowedForPingTest: TimeInterval = 10.0
    
    func setDelegateManager(to delegateManager: ObvNetworkFetchDelegateManager) {
        self.delegateManager = delegateManager
    }
    
}



extension WebSocketCoordinator: WebSocketDelegate {
    
    // MARK: - Reacting the App lifecycle changes

    func connectAll(flowId: FlowIdentifier) {
        os_log("🏓❄️ Call to connect all websockets", log: log, type: .info)
        alwaysReconnect = true
        updateListOfOwnedIdentities(flowId: flowId)
        updateListOfWebSocketServerURLs(flowId: flowId)
        startPerformingPingTestsOnRunningWebSocketsIfRequired()
        let identities = [ObvCryptoIdentity](self.webSocketInfosForIdentity.keys)
        for identity in identities {
            tryConnectToWebSocketServer(of: identity)
        }
    }
    
    
    func disconnectAll(flowId: FlowIdentifier) {
        os_log("🏓❄️ Call to disconnect all websockets", log: log, type: .info)
        self.alwaysReconnect = false
        self.stopPerformingPingTestsOnRunningWebSockets()
        let allServerURLs = webSocketTaskForWebSocketServerURL.keys.map({ $0 as URL })
        for serverURL in allServerURLs {
            disconnectFromWebSocketServerURL(serverURL)
        }
    }
    
    
    private func updateListOfWebSocketServerURLs(flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("🏓 The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("🏓 The context creator is not set", log: log, type: .fault)
            return
        }

        var urls = [(serverURL: URL, webSocketServerURL: URL)]()
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { obvContext in
            do {
                let allCachedWellKnown = try CachedWellKnown.getAllCachedWellKnown(within: obvContext)
                urls = allCachedWellKnown.compactMap({ cachedWellKnow in
                    guard let wellKnownJSON = cachedWellKnow.wellKnownJSON else { assertionFailure(); return nil }
                    return (cachedWellKnow.serverURL, wellKnownJSON.serverConfig.webSocketURL)
                })
            } catch {
                os_log("🏓 Could not get all cached well known", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
        }
        
        for (serverURL, webSocketServerURL) in urls {
            setWebSocketServerURL(for: serverURL, to: webSocketServerURL)
        }
        
    }
    
    
    private func updateListOfOwnedIdentities(flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("🏓 The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("🏓 The context creator is not set", log: log, type: .fault)
            return
        }

        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("🏓 The identity delegate is not set", log: log, type: .fault)
            return
        }

        var ownedIdentities = Set<ObvCryptoIdentity>()
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { obvContext in
            guard let _ownedIdentities = try? identityDelegate.getOwnedIdentities(within: obvContext) else {
                assertionFailure()
                return
            }
            ownedIdentities = _ownedIdentities
        }
        
        updateListOfOwnedIdentites(ownedIdentities: ownedIdentities, flowId: flowId)
        
    }
    
    
    func updateListOfOwnedIdentites(ownedIdentities: Set<ObvCryptoIdentity>, flowId: FlowIdentifier) {
        
        // When the list of owned identities is updated (which typically happens after the first onboarding), request de current device uids of the identities an synchronize this list with the `webSocketInfosForIdentity` dictionary.

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("🏓 The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("🏓 The context creator is not set", log: log, type: .fault)
            return
        }

        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("🏓 The identity delegate is not set", log: log, type: .fault)
            return
        }
        
        // We need to add the missing deviceUID values in the `webSocketInfosForIdentity` dictionary
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { obvContext in
            for ownedIdentity in ownedIdentities {
                let deviceUid: UID
                do {
                    deviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
                } catch {
                    os_log("🏓 Could not obtain the current device uid of the owned identity", log: log, type: .fault)
                    assertionFailure()
                    continue
                }
                setDeviceUid(to: deviceUid, for: ownedIdentity)
            }
        }
        
    }
        
    
    // MARK: - Getting infos about the current websockets
    
    func getWebSocketState(ownedIdentity: ObvCryptoIdentity) async throws -> (URLSessionTask.State,TimeInterval?) {
        guard let webSocketServerURL = webSocketInfosForIdentity[ownedIdentity]?.webSocketServerURL,
              let task = webSocketTaskForWebSocketServerURL[webSocketServerURL] else {
            throw Self.makeError(message: "Could not find webSocket task")
        }
        let state = task.state
        switch state {
        case .running:
            let pingTime = Date()
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URLSessionTask.State,TimeInterval?), Error>) in
                task.sendPing { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    // No error
                    let interval = Date().timeIntervalSince(pingTime)
                    continuation.resume(returning: (state, interval))
                }
            }
        default:
            return (state, nil)
        }
    }
    
    
    // MARK: - Setting infos
    
    func setWebSocketServerURL(for serverURL: URL, to webSocketServerURL: URL) {

        let concernedIdentities = webSocketInfosForIdentity.keys.filter({ $0.serverURL == serverURL })

        for identity in concernedIdentities {
            
            if let infos = webSocketInfosForIdentity[identity] {
                
                guard webSocketServerURL != infos.webSocketServerURL else { continue }
                
                if let previousWebSocketServerURL = infos.webSocketServerURL, let existingTask = webSocketTaskForWebSocketServerURL.removeValue(forKey: previousWebSocketServerURL) {
                    existingTask.cancel(with: .normalClosure, reason: nil)
                }
                webSocketInfosForIdentity[identity] = (infos.deviceUid, infos.token, webSocketServerURL)
                
            } else {
                
                webSocketInfosForIdentity[identity] = (nil, nil, webSocketServerURL)
                
            }
            
            // If we reach this point, we can try to connect to the webSocketServerURL
            
            registerMessageStatusForIdentity.removeValue(forKey: identity)
            
            connectAll(flowId: FlowIdentifier())
                        
        }
                
    }


    func setDeviceUid(to deviceUid: UID, for identity: ObvCryptoIdentity) {
        let newInfos: (UID, Data?, URL?)
        if let infos = webSocketInfosForIdentity[identity] {
            guard deviceUid != infos.deviceUid else { return }
            newInfos = (deviceUid, infos.token, infos.webSocketServerURL)
        } else {
            newInfos = (deviceUid, nil, nil)
        }
        webSocketInfosForIdentity[identity] = newInfos
        registerMessageStatusForIdentity.removeValue(forKey: identity)
        tryConnectToWebSocketServer(of: identity)
    }
    
    
    func setServerSessionToken(to token: Data, for identity: ObvCryptoIdentity) {
        let newInfos: (UID?, Data, URL?)
        if let infos = webSocketInfosForIdentity[identity] {
            guard token != infos.token else { return }
            newInfos = (infos.deviceUid, token, infos.webSocketServerURL)
        } else {
            newInfos = (nil, token, nil)
        }
        webSocketInfosForIdentity[identity] = newInfos
        registerMessageStatusForIdentity.removeValue(forKey: identity)
        tryConnectToWebSocketServer(of: identity)
    }
    
    
    /// This method gets called each time a new element (deviceUid, server session, or WebSocket URL) is set for a given identity.
    /// Until all the required information is set, this method does nothing. Once all the information is available, this method creates and resumes
    /// a WebSocket (unless one is already available).
    private func tryConnectToWebSocketServer(of identity: ObvCryptoIdentity) {
                
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("🏓 The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        guard let infos = webSocketInfosForIdentity[identity] as? (deviceUid: UID, token: Data, webSocketServerURL: URL) else {

            if webSocketInfosForIdentity[identity]?.token == nil {
                Task.detached { [weak self] in
                    do {
                        let (serverSessionToken, _) = try await delegateManager.networkFetchFlowDelegate.getValidServerSessionToken(for: identity, currentInvalidToken: nil, flowId: FlowIdentifier())
                        await self?.setServerSessionToken(to: serverSessionToken, for: identity)
                    } catch {
                        assertionFailure(error.localizedDescription)
                    }
                }
            }
            
            return
        }
        
        os_log("🏓 Trying to connect to the web socket server of the owned identity %{public}@.", log: log, type: .info, identity.debugDescription)
        
        // If we reach this point, for have all the information we need to create a WebSocket for this identity. There might already be one though.
        
        if let existingTask = webSocketTaskForWebSocketServerURL[infos.webSocketServerURL] {
            switch existingTask.state {
            case .running:
                os_log("🏓 No need to connect to the websocket server, a previous already exists and is running.", log: log, type: .info)
                Task { await sendRegisterMessageForAllIdentitiesOnWebSocketServerURL(infos.webSocketServerURL) }
                return
            case .suspended:
                os_log("🏓 Resuming a suspended websocket task", log: log, type: .info)
                existingTask.resume()
                Task { await sendRegisterMessageForAllIdentitiesOnWebSocketServerURL(infos.webSocketServerURL) }
                return
            case .canceling, .completed:
                _ = webSocketTaskForWebSocketServerURL.removeValue(forKey: infos.webSocketServerURL)
                registerMessageStatusForIdentity.removeValue(forKey: identity)
            @unknown default:
                _ = webSocketTaskForWebSocketServerURL.removeValue(forKey: infos.webSocketServerURL)
                registerMessageStatusForIdentity.removeValue(forKey: identity)
                assertionFailure()
            }
        }
        
        // If we reach this point, no websocket task exist for this websocket server URL
        
        os_log("🏓 Creating a new web socket task and resume it.", log: log, type: .info)
        
        assert(webSocketTaskForWebSocketServerURL[infos.webSocketServerURL] == nil)
        
        let urlSessionConfiguration = URLSessionConfiguration.default
        urlSessionConfiguration.waitsForConnectivity = true
        let urlSession = URLSession(configuration: urlSessionConfiguration, delegate: self, delegateQueue: nil)
        let webSocketTask = urlSession.webSocketTask(with: infos.webSocketServerURL)
        webSocketTaskForWebSocketServerURL[infos.webSocketServerURL] = webSocketTask
        assert(webSocketTask.state == URLSessionTask.State.suspended)
        webSocketTask.resume()
        assert(webSocketTask.state == URLSessionTask.State.running)
        
    }
    
    
    func disconnectFromWebSocketServerURL(_ webSocketServerURL: URL) {
        
        guard let webSocketTask = webSocketTaskForWebSocketServerURL.removeValue(forKey: webSocketServerURL) else { return }
        webSocketTask.cancel()
        os_log("🏓 We just cancelled a web socket task. Number of remaining web socket tasks: %d", log: log, type: .info, webSocketTaskForWebSocketServerURL.count)
        
        // Remove the register message status of all identities concerned by the webSocketServerURL that we are disconnecting
        
        let concernedIdentities = webSocketInfosForIdentity.filter({ $1.webSocketServerURL == webSocketServerURL }).keys
        for identity in concernedIdentities {
            registerMessageStatusForIdentity.removeValue(forKey: identity)
        }

        // If `alwaysReconnect` is `true`, we try to reconnect each of the identities concerned by the socket that we just disconnected.
        if alwaysReconnect {
            os_log("🏓 Since the web sockets are marked as always reconnect, we try to reconnect the web socket that we just deconnected.", log: log, type: .info)
            let identities = webSocketInfosForIdentity.keys.filter({ webSocketInfosForIdentity[$0]?.webSocketServerURL == webSocketServerURL})
            for identity in identities {
                tryConnectToWebSocketServer(of: identity)
            }
        }
    }
    
    
    private func removeURLFromReceivingWebSocketTaskForURL(_ webSocketServerURL: URL) {
        receivingWebSocketTaskForURL.remove(webSocketServerURL)
    }
    
    

    private func continuouslyReadMessageOnWebSocketServerURL(_ webSocketServerURL: URL) {
        guard let webSocketTask = webSocketTaskForWebSocketServerURL[webSocketServerURL], webSocketTask.state == .running else { return }
        let log = self.log
        
        guard receivingWebSocketTaskForURL.insert(webSocketServerURL).inserted else { return }

        os_log("🏓 Will receive on webSocketTask for URL %{public}@", log: log, type: .info, webSocketServerURL.debugDescription)

        webSocketTask.receive { result in
            switch result {
            case .failure(let failure):
                Task { [weak self] in
                    await self?.removeURLFromReceivingWebSocketTaskForURL(webSocketServerURL)
                    await self?.logWebSocketTaskReceiveError(failure: failure)
                    await self?.disconnectFromWebSocketServerURL(webSocketServerURL)
                }
                return
            case .success(let message):
                switch message {
                case .data:
                    os_log("🏓 Data received on websocket. This is unexpected.", log: log, type: .error)
                    assertionFailure()
                    Task { [weak self] in
                        await self?.removeURLFromReceivingWebSocketTaskForURL(webSocketServerURL)
                        await self?.continuouslyReadMessageOnWebSocketServerURL(webSocketServerURL)
                    }
                    return
                case .string(let string):
                    os_log("🏓 String received on websocket: %{public}@", log: log, type: .info, string)
                    Task { [weak self] in
                        await self?.removeURLFromReceivingWebSocketTaskForURL(webSocketServerURL)
                        do {
                            try await self?.parseReceivedString(string, fromWebSocketServerURL: webSocketServerURL)
                        } catch {
                            os_log("🏓 Failed to parse received string: %{public}@", log: log, type: .error, error.localizedDescription)
                            assertionFailure(error.localizedDescription)
                            // Continue anyway
                        }
                        await self?.continuouslyReadMessageOnWebSocketServerURL(webSocketServerURL)
                    }
                    return
                @unknown default:
                    assertionFailure()
                    Task { [weak self] in
                        await self?.removeURLFromReceivingWebSocketTaskForURL(webSocketServerURL)
                        await self?.continuouslyReadMessageOnWebSocketServerURL(webSocketServerURL)
                    }
                    return
                }
            }
        }
    }
    
    
    private func logWebSocketTaskReceiveError(failure: Error) {
        let error = failure as NSError
        if error.domain == POSIXError.errorDomain {
            let posixErrorCode = POSIXErrorCode(rawValue: Int32(error.code))
            if posixErrorCode == POSIXErrorCode.ENOTCONN {
                os_log("🏓 Error while receiving on a websocket task: Socket is not connected.", log: log, type: .error)
            } else if posixErrorCode == POSIXErrorCode.ECONNABORTED {
                os_log("🏓 Error while receiving on a websocket task: Software caused connection abort.", log: log, type: .error)
            } else {
                os_log("🏓 Error while receiving on a websocket task (posix error code).", log: log, type: .error)
                assertionFailure(error.localizedDescription)
            }
        } else {
            os_log("🏓 Error while receiving on a websocket task: %{public}@ code: %d domain: %{public}@", log: log, type: .error, error.localizedDescription, error.code, error.domain)
            //assertionFailure(error.localizedDescription)
        }
    }


    private func parseReceivedString(_ string: String, fromWebSocketServerURL webSocketServerURL: URL) throws {
        
        guard let delegateManager else {
            assertionFailure()
            throw Self.makeError(message: "The delegateManager is nil")
        }
        
        if let returnReceipt = try? ReturnReceipt(string: string) {
            os_log("🏓 The server sent a ReturnReceipt", log: log, type: .info)
            if let notificationDelegate = delegateManager.notificationDelegate {
                ObvNetworkFetchNotificationNew.newReturnReceiptToProcess(returnReceipt: returnReceipt)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)
            }
        }
        if let receivedMessage = try? NewMessageAvailableMessage(string: string) {
            os_log("🏓 The server notified that a new message is available for identity %{public}@", log: log, type: .info, receivedMessage.identity.debugDescription)
            let flowId = FlowIdentifier()
            if let message = receivedMessage.message {
                Task {
                    do {
                        // As the websocket notification is sent exactly when the message is uploaded on the server, we can assume that downloadTimestampFromServer = messageUploadTimestampFromServer
                        try await delegateManager.messagesDelegate.saveMessageReceivedOnWebsocket(message: message, downloadTimestampFromServer: message.messageUploadTimestampFromServer, ownedCryptoId: receivedMessage.identity, flowId: flowId)
                    } catch {
                        os_log("🏓 Failed to save the message received through the websocket: %{public}@. We request a download message and list attachments now", log: log, type: .error, error.localizedDescription)
                        await delegateManager.messagesDelegate.downloadMessagesAndListAttachments(ownedCryptoId: receivedMessage.identity, flowId: flowId)
                    }
                }
            } else {
                Task {
                    await delegateManager.messagesDelegate.downloadMessagesAndListAttachments(ownedCryptoId: receivedMessage.identity, flowId: flowId)
                }
            }
        } else if let receivedMessage = try? ResponseToRegisterMessage(string: string) {
            os_log("🏓 We received a proper response to the register message", log: log, type: .info)
            if let error = receivedMessage.error {
                os_log("🏓 The server reported that the registration was not successful. Error code is %{public}@", log: log, type: .error, error.debugDescription)
                switch error {
                case .general:
                    disconnectFromWebSocketServerURL(webSocketServerURL)
                case .invalidServerSession:
                    // Remove the server token from the infos
                    var  requiringNewToken = [(ownedCryptoId: ObvCryptoIdentity, currentInvalidToken: Data)]()
                    for (identity, infos) in webSocketInfosForIdentity {
                        if infos.webSocketServerURL == webSocketServerURL, let token = infos.token {
                            requiringNewToken.append((identity, token))
                            webSocketInfosForIdentity[identity] = (infos.deviceUid, nil, infos.webSocketServerURL)
                        }
                    }
                    // As for a new server session token
                    for (identity, token) in requiringNewToken {
                        let flowId = FlowIdentifier()
                        let log = self.log
                        Task.detached { [weak self] in
                            do {
                                _ = try await self?.delegateManager?.networkFetchFlowDelegate.getValidServerSessionToken(for: identity, currentInvalidToken: token, flowId: flowId)
                            } catch {
                                os_log("Call to getValidServerSessionToken did fail", log: log, type: .fault)
                                assertionFailure()
                            }
                        }
                    }
                    disconnectFromWebSocketServerURL(webSocketServerURL)
                case .unknownError:
                    assert(false)
                }
            } else {
                guard let concernedIdentity = receivedMessage.identity else { assertionFailure(); return }
                os_log("🏓 The server reported that the WebSocket registration was successful for identity %{public}@.", log: log, type: .info, concernedIdentity.debugDescription)
                guard let deviceUid = webSocketInfosForIdentity[concernedIdentity]?.deviceUid else {
                    os_log("🏓 Could not determine the device UID of the identity concerned by the web socket that was just registered.", log: log, type: .error)
                    return
                }
                os_log("🏓 Notifying the flow delegate about the identity/device %{public}@ concerned by the recent web socket registration.", log: log, type: .info, concernedIdentity.debugDescription)
                Task {
                    await delegateManager.networkFetchFlowDelegate.successfulWebSocketRegistration(identity: concernedIdentity, deviceUid: deviceUid)
                }
            }
        } else if let pushTopicMessage = try? PushTopicMessage(string: string) {
            os_log("🫸🏓 The server sent a keycloak topic message: %{public}@", log: log, type: .info, pushTopicMessage.topic)
            assert(delegateManager.notificationDelegate != nil)
            if let notificationDelegate = delegateManager.notificationDelegate {
                ObvNetworkFetchNotificationNew.pushTopicReceivedViaWebsocket(pushTopic: pushTopicMessage.topic)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)
            }
        } else if let targetedKeycloakPushNotification = try? KeycloakTargetedPushNotification(string: string) {
            os_log("🫸🏓 The server sent a targeted keycloak push notification for identity: %{public}@", log: log, type: .info, targetedKeycloakPushNotification.identity.debugDescription)
            assert(delegateManager.notificationDelegate != nil)
            if let notificationDelegate = delegateManager.notificationDelegate {
                ObvNetworkFetchNotificationNew.keycloakTargetedPushNotificationReceivedViaWebsocket(ownedIdentity: targetedKeycloakPushNotification.identity)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)
            }
        } else if let ownedDeviceMessage = try? OwnedDevicesMessage(string: string) {
            os_log("🏓 The server sent an OwnedDevicesMessage for identity: %{public}@", log: log, type: .info, ownedDeviceMessage.identity.debugDescription)
            if let notificationDelegate = delegateManager.notificationDelegate {
                ObvNetworkFetchNotificationNew.ownedDevicesMessageReceivedViaWebsocket(ownedIdentity: ownedDeviceMessage.identity)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: notificationDelegate)
            }
        }
        
    }
    
    
    private func sendRegisterMessageForAllIdentitiesOnWebSocketServerURL(_ webSocketServerURL: URL) async {
        
        os_log("🏓 Calling sendRegisterMessageForAllIdentitiesOnWebSocketServerURL", log: log, type: .info)
                
        guard let webSocketTask = webSocketTaskForWebSocketServerURL[webSocketServerURL], webSocketTask.state == .running else {
            connectAll(flowId: FlowIdentifier())
            return
        }
        
        let identitiesOnThatWebSocketServerURL = webSocketInfosForIdentity.filter({ $0.value.webSocketServerURL == webSocketServerURL }).map({ $0.key })

        assert(!identitiesOnThatWebSocketServerURL.isEmpty)

        let identitiesAndInfos: [(ObvCryptoIdentity, UID, Data)] = identitiesOnThatWebSocketServerURL.compactMap({
            guard let deviceUid = self.webSocketInfosForIdentity[$0]?.deviceUid else { return nil }
            guard let token = self.webSocketInfosForIdentity[$0]?.token else { return nil }
            return ($0, deviceUid, token)
        })

        for (identity, deviceUid, token) in identitiesAndInfos {
            
            if let registerMessageStatus = registerMessageStatusForIdentity[identity] {
                os_log("🏓 No need to send a register message for identity %{public}@ a previous one exists with status %{public}@", log: log, type: .info, identity.debugDescription, registerMessageStatus.debugDescription)
                continue // Continue with the next identity
            }
            
            // If we reach this point, we need to send a register message for the identity
            
            registerMessageStatusForIdentity[identity] = .registering

            do {
                let registerMessage = try RegisterMessage(identity: identity, deviceUid: deviceUid, token: token).getURLSessionWebSocketTaskMessage()
                try await webSocketTask.send(registerMessage)
                registerMessageStatusForIdentity[identity] = .registered
                os_log("🏓✅ We successfully sent the register message for identity %{public}@", log: log, type: .info, identity.debugDescription)
            } catch {
                assertionFailure()
                registerMessageStatusForIdentity.removeValue(forKey: identity)
                os_log("🏓 We could not send a register message for identity %{public}@: %{public}@", log: log, type: .error, identity.debugDescription, error.localizedDescription)
                // Continue with the next identity
            }
        }
        
        // Ping the websocket

        startPerformingPingTestsOnRunningWebSocketsIfRequired()
        
        // Read message on websocket
        
        continuouslyReadMessageOnWebSocketServerURL(webSocketServerURL)

    }
    
    
    /// This method allows to ask the server to delete the return receipt with the specified serverUid, for the identity given in parameter.
    func sendDeleteReturnReceipt(ownedIdentity: ObvCryptoIdentity, serverUid: UID) async throws {
        guard let webSocketServerURL = webSocketInfosForIdentity[ownedIdentity]?.webSocketServerURL else {
            os_log("🏓 Could not find an appropriate webSocketServerURL for this owned identity", log: log, type: .error)
            return
        }
        guard let webSocketTask = webSocketTaskForWebSocketServerURL[webSocketServerURL] else {
            os_log("🏓 Could not find an appropriate webSocketTask for this webSocketServerURL", log: log, type: .error)
            return
        }
        let deleteReturnReceiptMessage = try DeleteReturnReceipt(identity: ownedIdentity, serverUid: serverUid).getURLSessionWebSocketTaskMessage()
        assert(webSocketTask.state == URLSessionTask.State.running)
        do {
            try await webSocketTask.send(deleteReturnReceiptMessage)
            os_log("🏓 We successfully deleted a return receipt", log: log, type: .info)
        } catch {
            os_log("🏓 A return receipt failed to be deleted on server: %{public}@", log: log, type: .error, error.localizedDescription)
        }
    }
    
}


// MARK: - URLSessionWebSocketDelegate


extension WebSocketCoordinator: URLSessionWebSocketDelegate, URLSessionTaskDelegate {

    nonisolated
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol _protocol: String?) {
        Task {
            await urlSessionAsync(session, webSocketTask: webSocketTask, didOpenWithProtocol: _protocol)
        }
    }
    
    
    private func urlSessionAsync(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol _protocol: String?) async {
        os_log("🏓 Session WebSocket task did open", log: log, type: .info)
        
        // A websocket task was opened. We send a "register" message to the server for each identity concerned  by the server URL of this socket
        
        let webSocketServerURLCandidates = self.webSocketTaskForWebSocketServerURL.keys.compactMap {
            webSocketTaskForWebSocketServerURL[$0] == webSocketTask ? $0 : nil
        }
        
        let webSocketServerURL: URL
        do {
            guard webSocketServerURLCandidates.count == 1 else {
                os_log("🏓 Unexpected number of WebSocket server URL candidate(s) for the given WebSocket. Expected 1, got %d", log: log, type: .error, webSocketServerURLCandidates.count)
                return
            }
            webSocketServerURL = webSocketServerURLCandidates.first!
        }
        
        let identities = webSocketInfosForIdentity.keys.filter({ webSocketInfosForIdentity[$0]?.webSocketServerURL == webSocketServerURL})
        
        guard !identities.isEmpty else {
            os_log("🏓 Could not find any identity concerned by the opened WebSocket", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        await sendRegisterMessageForAllIdentitiesOnWebSocketServerURL(webSocketServerURL)
        
    }
    
    
    nonisolated
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        Task {
            await urlSessionAsync(session, webSocketTask: webSocketTask, didCloseWith: closeCode, reason: reason)
        }
    }
    
    
    private func urlSessionAsync(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        os_log("🏓 Session WebSocket task did close with code %{public}d and reason: %{public}@", log: log, type: .info, closeCode.rawValue, reason?.debugDescription ?? "None")
        guard let webSocketServerURL = webSocketTaskForWebSocketServerURL.first(where: { (_, task) in task == webSocketTask })?.key else {
            os_log("🏓 Could not determine the server URL of the web socket that closed.", log: log, type: .error)
            return
        }
        disconnectFromWebSocketServerURL(webSocketServerURL)
    }

    
    nonisolated
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task {
            await urlSessionAsync(session, task: task, didCompleteWithError: error)
        }
    }
    
    
    private func urlSessionAsync(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            os_log("🏓 Session WebSocket task did close with error: %{public}@", log: log, type: .info, error.localizedDescription)
        } else {
            os_log("🏓 Session WebSocket task did close without error", log: log, type: .info)
        }
        guard let webSocketServerURL = webSocketTaskForWebSocketServerURL.first(where: { (_, _task) in _task == task })?.key else {
            os_log("🏓 Could not determine the server URL of the web socket that closed.", log: log, type: .error)
            return
        }
        disconnectFromWebSocketServerURL(webSocketServerURL)
    }

}


// MARK: - Pinging running websockets


extension WebSocketCoordinator {
    
    private func startPerformingPingTestsOnRunningWebSocketsIfRequired() {
        guard pingRunningWebSocketsTimer == nil else { return }
        let log = self.log
        let timer = Timer(timeInterval: pingRunningWebSocketsInterval, repeats: true) { [weak self] timer in
            guard timer.isValid else { return }
            Task { [weak self] in
                guard let _self = self else { return }
                os_log("🏓 Performing a ping test on all running websockets", log: log, type: .info)
                let runningWebSocketTasks = await _self.webSocketTaskForWebSocketServerURL.values.filter({ $0.state == .running })
                os_log("🏓 There are %d web socket tasks to ping", log: log, type: .info, runningWebSocketTasks.count)
                for task in runningWebSocketTasks {
                    await _self.pingTest(webSocketTask: task)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pingRunningWebSocketsTimer = timer
    }
    
    
    private func stopPerformingPingTestsOnRunningWebSockets() {
        pingRunningWebSocketsTimer?.invalidate()
        pingRunningWebSocketsTimer = nil
    }
    
        
    /// This method executes a ping test for the web scoket task passed as a parameter.
    ///
    /// A ping test consists in sending a ping to the task. If the corresponding pong takes too much time to come back,
    /// we consider that the web socket cannot be used anymore and we disconnect it. If the pong is received with an error,
    /// we also disconnect the websocket. If the pong is received without error, nothing more happens.
    private func pingTest(webSocketTask: URLSessionWebSocketTask) async {
        let log = self.log
        guard let webSocketServerURL = webSocketTaskForWebSocketServerURL.first(where: { (_, task) in task == webSocketTask })?.key else {
            os_log("🏓 Could not determine the server URL of the web socket on which we were asked to perform a ping test.", log: log, type: .error)
            return
        }
        let timerUUID = UUID()
        let disconnectTimer = Timer(timeInterval: maxTimeIntervalAllowedForPingTest, repeats: false) { [weak self] timer in
            guard timer.isValid else { return }
            os_log("🏓 The disconnect timer fired, we disconnect the corresponding web socket task.", log: log, type: .error)
            Task { [weak self] in
                await self?.disconnectFromWebSocketServerURL(webSocketServerURL)
            }
        }
        disconnectTimerForUUID[timerUUID] = disconnectTimer
        RunLoop.main.add(disconnectTimer, forMode: .common)
        
        webSocketTask.sendPing { [weak self] error in
            if let error {
                os_log("🏓 Ping failed with error: %{public}@. We disconnect the web socket task.", log: log, type: .error, error.localizedDescription)
                Task { [weak self] in await self?.disconnectFromWebSocketServerURL(webSocketServerURL) }
                return
            }
            // No error
            os_log("🏓 One pong received", log: log, type: .info)
            Task { [weak self] in await self?.invalidateTimerWithUUID(timerUUID) }
        }
        
    }
    
    
    private func invalidateTimerWithUUID(_ timerUUID: UUID) {
        guard let timer = disconnectTimerForUUID.removeValue(forKey: timerUUID) else { return }
        timer.invalidate()
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


/// This extension makes the `DeleteReturnReceipt` Encodable. The actual definition of this type belongs to the Meta Manager since this is the type we use
/// to notify the engine that a new return receipt is available for one of the messages that we sent.
extension ReturnReceipt: Decodable {
        
    private static let errorDomain = String(describing: ReturnReceipt.self)

    enum CodingKeys: String, CodingKey {
        case action = "action"
        case identity = "identity"
        case serverUid = "serverUid"
        case nonce = "nonce"
        case encryptedPayload = "encryptedPayload"
        case timestamp = "timestamp"
    }

    
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let action = try values.decode(String.self, forKey: .action)
        guard action == "return_receipt" else {
            let message = "The received JSON is not a return receipt"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: ReturnReceipt.errorDomain, code: 0, userInfo: userInfo)
        }
        let identityAsString = try values.decode(String.self, forKey: .identity)
        guard let identityAsData = Data(base64Encoded: identityAsString) else {
            let message = "Could not parse the received identity"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: ReturnReceipt.errorDomain, code: 0, userInfo: userInfo)
        }
        guard let identity = ObvCryptoIdentity(from: identityAsData) else {
            let message = "Could not parse the received JSON"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: ReturnReceipt.errorDomain, code: 0, userInfo: userInfo)
        }
        let serverUidInBase64 = try values.decode(String.self, forKey: .serverUid)
        guard let serverUidAsData = Data(base64Encoded: serverUidInBase64) else {
            let message = "Could not parse the server uid in the received JSON (1)"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: ReturnReceipt.errorDomain, code: 0, userInfo: userInfo)
        }
        guard let serverUid = UID(uid: serverUidAsData) else {
            let message = "Could not parse the server uid in the received JSON (2)"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: ReturnReceipt.errorDomain, code: 0, userInfo: userInfo)
        }
        let nonceInBase64 = try values.decode(String.self, forKey: .nonce)
        guard let nonce = Data(base64Encoded: nonceInBase64) else {
            let message = "Could not parse the nonce in the received JSON"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: ReturnReceipt.errorDomain, code: 0, userInfo: userInfo)
        }
        let encryptedPayloadInBase64 = try values.decode(String.self, forKey: .encryptedPayload)
        guard let encryptedPayloadAsData = Data(base64Encoded: encryptedPayloadInBase64) else {
            let message = "Could not parse the encrypted payload"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: ReturnReceipt.errorDomain, code: 0, userInfo: userInfo)
        }
        let encryptedPayload = EncryptedData(data: encryptedPayloadAsData)
        let timestampInMilliseconds = try values.decode(Int.self, forKey: .timestamp)
        let timestamp = Date(timeIntervalSince1970: Double(timestampInMilliseconds)/1000.0)
        self.init(identity: identity, serverUid: serverUid, nonce: nonce, encryptedPayload: encryptedPayload, timestamp: timestamp)
    }
    
    
    init(string: String) throws {
        guard let data = string.data(using: .utf8) else {
            let message = "The received JSON is not UTF8 encoded"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: ReturnReceipt.errorDomain, code: 0, userInfo: userInfo)
        }
        let decoder = JSONDecoder()
        self = try decoder.decode(ReturnReceipt.self, from: data)
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
