/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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


@available(iOS 13, *)
final class WebSocketCoordinator: NSObject {
    
    weak var delegateManager: ObvNetworkFetchDelegateManager?
        
    /// For each WebSocket server, we keep a WebSocket task. This way, two identities on the same server can use the same WebSocket.
    private var webSocketTaskForWebSocketServerURL = [URL: URLSessionWebSocketTask]()

    private var webSocketInfosForIdentity = [ObvCryptoIdentity: (deviceUid: UID?, token: Data?, webSocketServerURL: URL?)]()
        
    private let internalQueue = DispatchQueue(label: "Queue for WebSockets")
    private let notificationQueue = DispatchQueue(label: "Queue for notifications from WebSocketCoordinator")
        
    private let logCategory = String(describing: WebSocketCoordinator.self)
    private var log: OSLog {
        return OSLog(subsystem: delegateManager?.logSubsystem ?? "io.olvid.network.send", category: logCategory)
    }
    
    private static let errorDomain = "WebSocketCoordinator"
    private static func makeError(message: String) -> Error { NSError(domain: WebSocketCoordinator.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    /// When `true`, this coordinator will always try to create, resume and register a new WebSocket when one closes/disconnects.
    /// It does this for each of the identities concerned by the closed WebSocket. If `false`, this coordinator does nothing
    /// when a WebSocket closes/disconnects.
    var alwaysReconnect = true

    private var pingRunningWebSocketsTimer: Timer?
    private let pingRunningWebSocketsInterval: TimeInterval = 120.0 // We perform a ping test on all running web socket tasks every 2 minutes
    private let maxTimeIntervalAllowedForPingTest: TimeInterval = 10.0
    
}


@available(iOS 13, *)
extension WebSocketCoordinator: WebSocketDelegate {
    
    // MARK: - Reacting the App lifecycle changes

    func applicationDidStartRunning(flowId: FlowIdentifier) {
        self.alwaysReconnect = true
        self.updateListOfOwnedIdentities(flowId: flowId)
        self.updateListOfWebSocketServerURLs(flowId: flowId)
        self.startPerformingPingTestsOnRunningWebSockets()
        connectAll()
    }
    
    
    func applicationDidEnterBackground() {
        self.alwaysReconnect = false
        self.stopPerformingPingTestsOnRunningWebSockets()
        disconnectAll()
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
            updateWebSocketServerURL(for: serverURL, to: webSocketServerURL)
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
        
        guard !ownedIdentities.isEmpty else { return }
        
        updatedListOfOwnedIdentites(ownedIdentities: ownedIdentities, flowId: flowId)
        
    }
    
    func updatedListOfOwnedIdentites(ownedIdentities: Set<ObvCryptoIdentity>, flowId: FlowIdentifier) {
        
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

        // We first clean the `webSocketInfosForIdentity` dictionary and cancel all related websocket tasks
        
        AssertCurrentQueue.notOnQueue(internalQueue)
        internalQueue.sync {
            let knownOwnedIdentities = Set<ObvCryptoIdentity>(webSocketInfosForIdentity.keys)
            let identitiesToRemove = knownOwnedIdentities.subtracting(ownedIdentities)
            for ownedIdentity in identitiesToRemove {
                if let infos = webSocketInfosForIdentity.removeValue(forKey: ownedIdentity),
                   let webSocketServerURL = infos.webSocketServerURL,
                   let task = webSocketTaskForWebSocketServerURL.removeValue(forKey: webSocketServerURL) {
                    task.cancel()
                }
            }
        }
        
        // We need add the missing values in the `webSocketInfosForIdentity` dictionary
        
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
    

    func connectAll() {
        var identities = [ObvCryptoIdentity]()
        AssertCurrentQueue.notOnQueue(internalQueue)
        internalQueue.sync {
            identities = [ObvCryptoIdentity](self.webSocketInfosForIdentity.keys)
        }
        for identity in identities {
            tryConnectToWebSocketServer(of: identity)
        }
    }
    
    
    private func disconnectAll() {
        var allServerURLs = [URL]()
        AssertCurrentQueue.notOnQueue(internalQueue)
        internalQueue.sync {
            allServerURLs = webSocketTaskForWebSocketServerURL.keys.map({ $0 as URL })
        }
        for serverURL in allServerURLs {
            disconnectFromWebSocketServerURL(serverURL)
        }
    }
    
    // MARK: - Getting infos about the current websockets
    
    func getWebSocketState(ownedIdentity: ObvCryptoIdentity, completionHander: @escaping (Result<(URLSessionTask.State,TimeInterval?),Error>) -> Void) {
        internalQueue.async { [weak self] in
            guard let webSocketServerURL = self?.webSocketInfosForIdentity[ownedIdentity]?.webSocketServerURL,
                  let task = self?.webSocketTaskForWebSocketServerURL[webSocketServerURL] else {
                DispatchQueue.main.async {
                    completionHander(.failure(WebSocketCoordinator.makeError(message: "Could not find webSocket task")))
                }
                return
            }
            let state = task.state
            switch state {
            case .running:
                let pingTime = Date()
                task.sendPing { (error) in
                    let interval = Date().timeIntervalSince(pingTime)
                    DispatchQueue.main.async {
                        completionHander(.success((state, interval)))
                    }
                }
            default:
                DispatchQueue.main.async {
                    completionHander(.success((state, nil)))
                }
            }
        }
    }
    
    // MARK: - Setting infos

    func updateWebSocketServerURL(for serverURL: URL, to webSocketServerURL: URL) {
        var concernedIdentities = [ObvCryptoIdentity]()
        AssertCurrentQueue.notOnQueue(internalQueue)
        internalQueue.sync {
            concernedIdentities = webSocketInfosForIdentity.keys.filter({ $0.serverURL == serverURL })
            if let existingTask = webSocketTaskForWebSocketServerURL.removeValue(forKey: webSocketServerURL) {
                existingTask.cancel(with: .normalClosure, reason: nil)
            }
        }
        for identity in concernedIdentities {
            setWebSocketServerURL(to: webSocketServerURL, for: identity)
            tryConnectToWebSocketServer(of: identity)
        }
        
    }

    func setWebSocketServerURL(to webSocketServerURL: URL, for identity: ObvCryptoIdentity) {
        
        AssertCurrentQueue.notOnQueue(internalQueue)
        internalQueue.sync { [weak self] in
            let newInfos: (UID?, Data?, URL)
            if let infos = self?.webSocketInfosForIdentity[identity] {
                newInfos = (infos.deviceUid, infos.token, webSocketServerURL)
            } else {
                newInfos = (nil, nil, webSocketServerURL)
            }
            self?.webSocketInfosForIdentity[identity] = newInfos
        }
        
        tryConnectToWebSocketServer(of: identity)
        
    }
    
    
    func setDeviceUid(to deviceUid: UID, for identity: ObvCryptoIdentity) {

        AssertCurrentQueue.notOnQueue(internalQueue)
        internalQueue.sync { [weak self] in
            let newInfos: (UID, Data?, URL?)
            if let infos = self?.webSocketInfosForIdentity[identity] {
                newInfos = (deviceUid, infos.token, infos.webSocketServerURL)
            } else {
                newInfos = (deviceUid, nil, nil)
            }
            self?.webSocketInfosForIdentity[identity] = newInfos
        }

        tryConnectToWebSocketServer(of: identity)
    }
    
    
    func setServerSessionToken(to token: Data, for identity: ObvCryptoIdentity) {

        AssertCurrentQueue.notOnQueue(internalQueue)
        internalQueue.sync { [weak self] in
            let newInfos: (UID?, Data, URL?)
            if let infos = self?.webSocketInfosForIdentity[identity] {
                newInfos = (infos.deviceUid, token, infos.webSocketServerURL)
            } else {
                newInfos = (nil, token, nil)
            }
            self?.webSocketInfosForIdentity[identity] = newInfos
        }

        tryConnectToWebSocketServer(of: identity)
    }
    
    
    /// This method gets called each time a new element (deviceUid, server session, or WebSocket URL) is set for a given identity.
    /// Until all the required information is set, this method does nothing. Once all the information is available, this method creates and resumes
    /// a WebSocket (unless one is already available).
    private func tryConnectToWebSocketServer(of identity: ObvCryptoIdentity) {
        
        os_log("🏓 Trying to connect to the web socket server of an owned identity.", log: log, type: .info)
        
        AssertCurrentQueue.notOnQueue(internalQueue)
        internalQueue.sync {
                        
            guard let _infos = webSocketInfosForIdentity[identity] as? (deviceUid: UID, token: Data, webSocketServerURL: URL) else {
                return
            }
            
            // If we reach this point, for have all the information we need to create a WebSocket for this identity. There might already be one though.

            if let existingTask = webSocketTaskForWebSocketServerURL[_infos.webSocketServerURL] {
                switch existingTask.state {
                case .running:
                    os_log("🏓 No need to connect to the websocket server, a previous already exists and is running. We perform a ping test on this web socket.", log: log, type: .info)
                    pingTest(webSocketTask: existingTask)
                    return
                case .suspended:
                    os_log("🏓 Resuming a suspended websocket task", log: log, type: .info)
                    existingTask.resume()
                    return
                case .canceling, .completed:
                    _ = webSocketTaskForWebSocketServerURL.removeValue(forKey: _infos.webSocketServerURL)
                @unknown default:
                    _ = webSocketTaskForWebSocketServerURL.removeValue(forKey: _infos.webSocketServerURL)
                    assertionFailure()
                }
            }
            
            // If we reach this point, no websocket task exist for this websocket server URL
            
            os_log("🏓 Creating a new web socket task and resume it.", log: log, type: .info)

            assert(webSocketTaskForWebSocketServerURL[_infos.webSocketServerURL] == nil)

            let urlSessionConfiguration = URLSessionConfiguration.default
            urlSessionConfiguration.waitsForConnectivity = true
            let urlSession = URLSession(configuration: urlSessionConfiguration, delegate: self, delegateQueue: nil)
            let webSocketTask = urlSession.webSocketTask(with: _infos.webSocketServerURL)
            webSocketTaskForWebSocketServerURL[_infos.webSocketServerURL] = webSocketTask
            assert(webSocketTask.state == URLSessionTask.State.suspended)
            webSocketTask.resume()
            assert(webSocketTask.state == URLSessionTask.State.running)
        }
        
    }
    
    
    func disconnectFromWebSocketServerURL(_ webSocketServerURL: URL) {

        AssertCurrentQueue.notOnQueue(internalQueue)
        internalQueue.sync { [weak self] in
            guard let _self = self else { return }
            guard let webSocketTask = _self.webSocketTaskForWebSocketServerURL.removeValue(forKey: webSocketServerURL) else { return }
            webSocketTask.cancel()
            os_log("🏓 We just cancelled a web socket task. Number of remaining web socket tasks: %d", log: log, type: .info, _self.webSocketTaskForWebSocketServerURL.count)

        }
        
        // If `alwaysReconnect` is `true`, we try to reconnect each of the identities concerned by the socket that we just disconnected.
        if alwaysReconnect {
            os_log("🏓 Since the web sockets are marked as always reconnect, we try to reconnect the web socket that we just deconnected.", log: log, type: .fault)
            var identities = [ObvCryptoIdentity]()
            AssertCurrentQueue.notOnQueue(internalQueue)
            internalQueue.sync {
                identities = webSocketInfosForIdentity.keys.filter({ webSocketInfosForIdentity[$0]?.webSocketServerURL == webSocketServerURL})
            }
            for identity in identities {
                tryConnectToWebSocketServer(of: identity)
            }
        }
    }
    

    private func readMessageOnWebSocketServerURL(_ webSocketServerURL: URL) throws {
        var webSocketTask: URLSessionWebSocketTask?
        AssertCurrentQueue.notOnQueue(internalQueue)
        internalQueue.sync {
            webSocketTask = webSocketTaskForWebSocketServerURL[webSocketServerURL]
        }
        let log = self.log
        webSocketTask?.receive { [weak self] result in
            do {
                try self?.receive(result, fromWebSocketServerURL: webSocketServerURL)
            } catch {
                os_log("🏓 Could not receive message on web socket", log: log, type: .fault)
                assertionFailure()
            }
        }
    }
    
    
    
    private func receive(_ result: Result<URLSessionWebSocketTask.Message, Error>, fromWebSocketServerURL webSocketServerURL: URL) throws {
    
        switch result {
        case .failure(let error):
            os_log("🏓 Could not receive data on WebSocket: %{public}@. Disconnecting the WebSocket.", log: log, type: .error, error.localizedDescription)
            self.disconnectFromWebSocketServerURL(webSocketServerURL)
        case .success(let message):
            switch message {
            case .data:
                os_log("🏓 Data received on websocket. This is unexpected.", log: log, type: .error)
                assert(false)
                try self.readMessageOnWebSocketServerURL(webSocketServerURL)
            case .string(let string):
                os_log("🏓 String received on websocket: %{public}@", log: log, type: .info, string)
                try parseReceivedString(string, fromWebSocketServerURL: webSocketServerURL)
                try self.readMessageOnWebSocketServerURL(webSocketServerURL)
            @unknown default:
                fatalError()
            }
        }

    }
    
    
    private func parseReceivedString(_ string: String, fromWebSocketServerURL webSocketServerURL: URL) throws {
        
        if let returnReceipt = try? ReturnReceipt(string: string) {
            os_log("🏓 The server sent a ReturnReceipt", log: log, type: .info)
            let NotificationType = ObvNetworkFetchNotification.NewReturnReceiptToProcess.self
            let userInfo = [NotificationType.Key.returnReceipt: returnReceipt]
            notificationQueue.async { [weak self] in
                self?.delegateManager?.notificationDelegate?.post(name: NotificationType.name, userInfo: userInfo)
            }
        }
        if let receivedMessage = try? NewMessageAvailableMessage(string: string) {
            os_log("🏓 The server notified that a new message is available for identity %{public}@", log: log, type: .info, receivedMessage.identity.debugDescription)
            guard let deviceUid = self.webSocketInfosForIdentity[receivedMessage.identity]?.deviceUid else {
                os_log("🏓 Could not recover the device uid of the identity", log: log, type: .fault)
                assert(false)
                return
            }
            let flowId = FlowIdentifier()
            if let message = receivedMessage.message {
                do {
                    // As the websocket notification is sent exactly when the message is uploaded on the server, we can assume that downloadTimestampFromServer = messageUploadTimestampFromServer
                    try delegateManager?.messagesDelegate.saveMessageReceivedOnWebsocket(message: message, downloadTimestampFromServer: message.messageUploadTimestampFromServer, ownedIdentity: receivedMessage.identity, flowId: flowId)
                } catch {
                    os_log("🏓 Failed to save the message received through the websocket: %{public}@. We request a download message and list attachments now", log: log, type: .error, error.localizedDescription)
                    delegateManager?.messagesDelegate.downloadMessagesAndListAttachments(for: receivedMessage.identity, andDeviceUid: deviceUid, flowId: flowId)
                }
            } else {
                delegateManager?.messagesDelegate.downloadMessagesAndListAttachments(for: receivedMessage.identity, andDeviceUid: deviceUid, flowId: flowId)
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
                    var identityRequiringNewToken: ObvCryptoIdentity?
                    AssertCurrentQueue.notOnQueue(internalQueue)
                    internalQueue.sync {
                        for (identity, infos) in webSocketInfosForIdentity {
                            if infos.webSocketServerURL == webSocketServerURL {
                                webSocketInfosForIdentity[identity] = (infos.deviceUid, nil, infos.webSocketServerURL)
                                identityRequiringNewToken = identity
                            }
                        }
                    }
                    // As for a new server session token
                    if let identity = identityRequiringNewToken {
                        let flowId = FlowIdentifier()
                        try delegateManager?.networkFetchFlowDelegate.serverSessionRequired(for: identity, flowId: flowId)
                    }
                    disconnectFromWebSocketServerURL(webSocketServerURL)
                case .unknownError:
                    assert(false)
                }
            } else {
                os_log("🏓 The server reported that the WebSocket registration was successful.", log: log, type: .info)
                internalQueue.async { [weak self] in
                    guard let _self = self else { return }
                    let concernedIdentities = _self.webSocketInfosForIdentity.filter({ $1.webSocketServerURL == webSocketServerURL }).keys
                    for identity in concernedIdentities {
                        guard let deviceUid = _self.webSocketInfosForIdentity[identity]?.deviceUid else {
                            os_log("🏓 Could not determine the device UID of the identity concerned by the web socket that was just registered.", log: _self.log, type: .error)
                            return
                        }
                        os_log("🏓 Notifying the flow delegate about the identity/device concerned by the recent web socket registration.", log: _self.log, type: .info)
                        _self.notificationQueue.async {
                            _self.delegateManager?.networkFetchFlowDelegate.successfulWebSocketRegistration(identity: identity, deviceUid: deviceUid)
                        }
                    }
                }
            }
        }
        
    }
    
    
    private func sendRegisterMessageOnWebSocketTask(_ webSocketTask: URLSessionWebSocketTask, for identity: ObvCryptoIdentity, withDeviceUid deviceUid: UID, andToken token: Data) throws {
        let registerMessage = try RegisterMessage(identity: identity, deviceUid: deviceUid, token: token).getURLSessionWebSocketTaskMessage()
        
        assert(webSocketTask.state == URLSessionTask.State.running)
        
        webSocketTask.send(registerMessage) { [weak self] (error) in
            guard let _self = self else { return }
            if let error = error {
                os_log("🏓 We could not send a register message: %{public}@", log: _self.log, type: .error, error.localizedDescription)
            } else {
                os_log("🏓 We successfully sent the register message", log: _self.log, type: .info)
                return
            }
        }
    }
    
    
    /// This method allows to ask the server to delete the return receipt with the specified serverUid, for the identity given in parameter.
    func sendDeleteReturnReceipt(ownedIdentity: ObvCryptoIdentity, serverUid: UID) throws {
        guard let webSocketServerURL = webSocketInfosForIdentity[ownedIdentity]?.webSocketServerURL else {
            os_log("🏓 Could not find an appropriate webSocketServerURL for this owned identity", log: log, type: .error)
            return
        }
        AssertCurrentQueue.notOnQueue(internalQueue)
        try internalQueue.sync {
            guard let webSocketTask = webSocketTaskForWebSocketServerURL[webSocketServerURL] else {
                os_log("🏓 Could not find an appropriate webSocketTask for this webSocketServerURL", log: log, type: .error)
                return
            }
            let deleteReturnReceiptMessage = try DeleteReturnReceipt(identity: ownedIdentity, serverUid: serverUid).getURLSessionWebSocketTaskMessage()
            assert(webSocketTask.state == URLSessionTask.State.running)
            webSocketTask.send(deleteReturnReceiptMessage) { [weak self] (error) in
                guard let _self = self else { return }
                if let error = error {
                    os_log("🏓 A return receipt failed to be deleted on server: %{public}@", log: _self.log, type: .error, error.localizedDescription)
                } else {
                    os_log("🏓 We successfully deleted a return receipt", log: _self.log, type: .info)
                    return
                }
            }
        }
    }
    
}


@available(iOS 13, *)
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

@available(iOS 13, *)
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

// MARK: - ReturnReceipt

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


// MARK: - ResponseToRegisterMessage

@available(iOS 13, *)
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


// MARK: - NewMessageAvailableMessage

@available(iOS 13, *)
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


// MARK: - URLSessionWebSocketDelegate

@available(iOS 13, *)
extension WebSocketCoordinator: URLSessionWebSocketDelegate, URLSessionTaskDelegate {

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol _protocol: String?) {
        if let _protocol = _protocol {
            os_log("🏓 Session WebSocket task did open with protocol %{public}@", log: log, type: .info, _protocol)
        } else {
            os_log("🏓 Session WebSocket task did open without specifing a protocol", log: log, type: .info)
        }

        // A websocket task was opened. We send a "register" message to the server for each identity concerned  by the server URL of this socket
        
        var webSocketServerURLCandidates = [URL]()
        AssertCurrentQueue.notOnQueue(internalQueue)
        internalQueue.sync {
            webSocketServerURLCandidates = self.webSocketTaskForWebSocketServerURL.keys.compactMap {
                webSocketTaskForWebSocketServerURL[$0] == webSocketTask ? $0 : nil
            }
        }
        
        let webSocketServerURL: URL
        do {
            guard webSocketServerURLCandidates.count == 1 else {
                os_log("🏓 Unexpected number of WebSocket server URL candidate(s) for the given WebSocket. Expected 1, got %d", log: log, type: .error, webSocketServerURLCandidates.count)
                return
            }
            webSocketServerURL = webSocketServerURLCandidates.first!
        }
         
        var identities = [ObvCryptoIdentity]()
        AssertCurrentQueue.notOnQueue(internalQueue)
        internalQueue.sync { [weak self] in
            guard let _self = self else { return }
            identities = _self.webSocketInfosForIdentity.keys.filter({ webSocketInfosForIdentity[$0]?.webSocketServerURL == webSocketServerURL})
        }
        
        guard !identities.isEmpty else {
            os_log("🏓 Could not find any identity concerned by the opened WebSocket", log: log, type: .fault)
            assert(false)
            return
        }
        
        var identitiesAndInfos = [(ObvCryptoIdentity, UID, Data)]()
        AssertCurrentQueue.notOnQueue(internalQueue)
        internalQueue.sync {
            identitiesAndInfos = identities.compactMap({
                guard let deviceUid = self.webSocketInfosForIdentity[$0]?.deviceUid else { return nil }
                guard let token = self.webSocketInfosForIdentity[$0]?.token else { return nil }
                return ($0, deviceUid, token)
            })
        }

        guard !identitiesAndInfos.isEmpty else {
            os_log("🏓 Could not find any appropriate identity infos concerned by the opened WebSocket", log: log, type: .fault)
            assert(false)
            return
        }
        
        do {
            try readMessageOnWebSocketServerURL(webSocketServerURL)
        } catch {
            os_log("🏓 Call to readMessageOnWebSocketServerURL failed", log: log, type: .fault)
            assertionFailure()
        }

        for (identity, deviceUid, token) in identitiesAndInfos {
            do {
                try sendRegisterMessageOnWebSocketTask(webSocketTask, for: identity, withDeviceUid: deviceUid, andToken: token)
            } catch let error {
                os_log("🏓 Could not send register message: %{public}@", log: log, type: .error, error.localizedDescription)
            }
        }

    }
    
    
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        os_log("🏓 Session WebSocket task did close with code %{public}d and reason: %{public}@", log: log, type: .info, closeCode.rawValue, reason?.debugDescription ?? "None")
        var webSocketServerURL: URL?
        AssertCurrentQueue.notOnQueue(internalQueue)
        internalQueue.sync {
            guard let _webSocketServerURL = webSocketTaskForWebSocketServerURL.first(where: { (_, task) in task == webSocketTask })?.key else {
                os_log("🏓 Could not determine the server URL of the web socket that closed.", log: log, type: .error)
                return
            }
            webSocketServerURL = _webSocketServerURL
        }
        if let webSocketServerURL = webSocketServerURL {
            disconnectFromWebSocketServerURL(webSocketServerURL)
        }
    }

    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            os_log("🏓 Session WebSocket task did close with error: %{public}@", log: log, type: .info, error.localizedDescription)
        } else {
            os_log("🏓 Session WebSocket task did close without error", log: log, type: .info)
        }
        var webSocketServerURL: URL?
        AssertCurrentQueue.notOnQueue(internalQueue)
        internalQueue.sync {
            guard let _webSocketServerURL = webSocketTaskForWebSocketServerURL.first(where: { (_, _task) in _task == task })?.key else {
                os_log("🏓 Could not determine the server URL of the web socket that closed.", log: log, type: .error)
                return
            }
            webSocketServerURL = _webSocketServerURL
        }
        if let webSocketServerURL = webSocketServerURL {
            disconnectFromWebSocketServerURL(webSocketServerURL)
        }
    }

}


// MARK: - Pinging running websockets

@available(iOS 13, *)
extension WebSocketCoordinator {
    
    private func startPerformingPingTestsOnRunningWebSockets() {
        internalQueue.async { [weak self] in
            guard let _self = self else { return }
            guard _self.pingRunningWebSocketsTimer == nil else { return }
            let timer = Timer(timeInterval: _self.pingRunningWebSocketsInterval, repeats: true) { [weak self] timer in
                self?.internalQueue.async { [weak self] in
                    self?.performPingTestForAllRunningWebSockets(timer)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            _self.pingRunningWebSocketsTimer = timer
        }
    }
    
    
    private func stopPerformingPingTestsOnRunningWebSockets() {
        internalQueue.async { [weak self] in
            guard let _self = self else { return }
            guard let timer = _self.pingRunningWebSocketsTimer else { assertionFailure(); return }
            timer.invalidate()
            _self.pingRunningWebSocketsTimer = nil
        }
    }
    
    
    /// This method is executed when the `pingRunningWebSocketsTimer` timer fires. It must be executed on the
    /// `internalQueue`. It executes a ping test for each running web socket task.
    ///
    /// This method must be called on the `internalQueue`.
    private func performPingTestForAllRunningWebSockets(_ timer: Timer) {
        AssertCurrentQueue.onQueue(internalQueue)
        guard timer.isValid else { return }
        os_log("🏓 Performing a ping test on all running websockets", log: log, type: .info)
        let runningWebSocketTasks = Set(webSocketTaskForWebSocketServerURL.values.filter({ $0.state == .running }))
        os_log("🏓 There are %d web socket tasks to ping", log: log, type: .info, runningWebSocketTasks.count)
        for task in runningWebSocketTasks {
            self.pingTest(webSocketTask: task)
        }
    }
    
    
    /// This method executes a ping test for the web scoket task passed as a parameter.
    ///
    /// A ping test consists in sending a ping to the task. If the corresponding pong takes too much time to come back,
    /// we consider that the web socket cannot be used anymore and we disconnect it. If the pong is received with an error,
    /// we also disconnect the websocket. If the pong is received without error, nothing more happens.
    ///
    /// This method must be called on the `internalQueue`
    private func pingTest(webSocketTask: URLSessionWebSocketTask) {
        AssertCurrentQueue.onQueue(internalQueue)
        let log = self.log
        guard let webSocketServerURL = webSocketTaskForWebSocketServerURL.first(where: { (_, task) in task == webSocketTask })?.key else {
            os_log("🏓 Could not determine the server URL of the web socket on which we were asked to perform a ping test.", log: log, type: .error)
            return
        }
        let disconnectTimer = Timer(timeInterval: maxTimeIntervalAllowedForPingTest, repeats: false) { [weak self] timer in
            guard timer.isValid else { return }
            os_log("🏓 The disconnect timer fired, we disconnect the corresponding web socket task.", log: log, type: .error)
            DispatchQueue(label: "Queue for disconnecting web socket (1)").async {
                self?.disconnectFromWebSocketServerURL(webSocketServerURL)
            }
        }
        RunLoop.main.add(disconnectTimer, forMode: .common)
        webSocketTask.sendPing { [weak self] error in
            disconnectTimer.invalidate()
            guard let error = error else {
                os_log("🏓 One pong received", log: log, type: .info)
                return
            }
            // If we reach this point, there is an issue with the websocket task
            os_log("🏓 Ping failed with error: %{public}@. We disconnect the web socket task.", log: log, type: .error, error.localizedDescription)
            DispatchQueue(label: "Queue for disconnecting web socket (2)").async {
                self?.disconnectFromWebSocketServerURL(webSocketServerURL)
            }
        }
    }
    
}
