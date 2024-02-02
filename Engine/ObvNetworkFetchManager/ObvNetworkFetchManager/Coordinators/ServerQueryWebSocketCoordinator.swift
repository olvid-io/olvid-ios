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
import CoreData
import os.log
import OlvidUtils
import ObvCrypto
import ObvMetaManager
import ObvTypes


/// This coordinator is, for now, only used to perform the message exchanges between two devices performing an owned device transfer protocol.
/// The device with the identity to transfer is called the *source device*, while the other is called the *target device*.
///
///     ┌──────┐                           ┌──────┐                           ┌──────┐
///     │Source│                           │Server│                           │Target│
///     └──┬───┘                           └──┬───┘                           └──┬───┘
///        │              Get SN              │                                  │
///        │ ─────────────────────────────────>                                  │
///        │                                  │                                  │
///        │             SN | CIDs            │                                  │
///        │ <─────────────────────────────────                                  │
///        │                                  │                                  │
///        │                                  SN                                 │
///        │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─>
///        │                                  │                                  │
///        │                                  │          SN | payload_1          │
///        │                                  │ <─────────────────────────────────
///        │                                  │                                  │
///        │          CIDt | payload1         │                                  │
///        │ <─────────────────────────────────                                  │
///        │                                  │                                  │
///        │ CIDt | payload2 (containing CIDs)│                                  │
///        │ ─────────────────────────────────>                                  │
///        │                                  │                                  │
///        │                                  │ CIDs | payload2 (containing CIDs)│
///        │                                  │ ─────────────────────────────────>
///        │                                  │                                  │
///        │                                  │                                  │────┐
///        │                                  │                                  │    │ Checks equality between CIDs received from server and in the payload
///        │                                  │                                  │<───┘
///     ┌──┴───┐                           ┌──┴───┐                           ┌──┴───┐
///     │Source│                           │Server│                           │Target│
///     └──────┘                           └──────┘                           └──────┘
///
///
actor ServerQueryWebSocketCoordinator: ServerQueryWebSocketDelegate {

    private static let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    private static let logCategory = "ServerPushNotificationsCoordinator"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)

    weak var delegateManager: ObvNetworkFetchDelegateManager?

    private var webSocketTaskForProtocolInstanceUID = [UID: URLSessionWebSocketTask]()
    
    init(logPrefix: String) {
        let logSubsystem = "\(logPrefix).\(Self.defaultLogSubsystem)"
        Self.log = OSLog(subsystem: logSubsystem, category: Self.logCategory)
    }
    
    func setDelegateManager(_ delegateManager: ObvNetworkFetchDelegateManager) {
        self.delegateManager = delegateManager
    }
    
    
    func handleServerQuery(pendingServerQueryObjectId: NSManagedObjectID, flowId: FlowIdentifier) throws {
        
        guard let delegateManager else { assertionFailure(); throw ObvError.theDelegateManagerIsNil }
        guard let contextCreator = delegateManager.contextCreator else { assertionFailure(); throw ObvError.theContextCreatorIsNil }
        
        contextCreator.performBackgroundTask(flowId: flowId) { [weak self] obvContext in
            do {

                guard let pendingServerQuery = try PendingServerQuery.get(objectId: pendingServerQueryObjectId, delegateManager: delegateManager, within: obvContext) else {
                    assertionFailure()
                    return
                }

                guard pendingServerQuery.isWebSocket else {
                    assertionFailure()
                    return
                }
                
                switch pendingServerQuery.queryType {
                    
                case .deviceDiscovery,
                        .putUserData,
                        .getUserData,
                        .checkKeycloakRevocation,
                        .createGroupBlob,
                        .getGroupBlob,
                        .deleteGroupBlob,
                        .putGroupLog,
                        .requestGroupBlobLock,
                        .updateGroupBlob,
                        .getKeycloakData,
                        .ownedDeviceDiscovery,
                        .setOwnedDeviceName,
                        .deactivateOwnedDevice,
                        .setUnexpiringOwnedDevice:
                    assertionFailure("This serverquery is handled by another coordinator. This one should not have been called.")
                    return
                    
                case .sourceGetSessionNumber(protocolInstanceUID: let protocolInstanceUID):
                    Task { [weak self] in
                        guard let self else { return }
                        do {
                            
                            let response = try await handleSourceGetSessionNumberMessage(pendingServerQueryObjectId: pendingServerQueryObjectId, protocolInstanceUID: protocolInstanceUID)
                            
                            let sourceConnectionId = response.sourceConnectionId
                            let sessionNumber = try ObvOwnedIdentityTransferSessionNumber(sessionNumber: response.sessionNumber)
                            
                            try obvContext.performAndWaitOrThrow {
                                pendingServerQuery.responseType = ServerResponse.ResponseType.sourceGetSessionNumberMessage(result:
                                        .requestSucceeded(sourceConnectionId: sourceConnectionId, sessionNumber: sessionNumber))
                                try obvContext.save(logOnFailure: Self.log)
                                delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: pendingServerQueryObjectId, flowId: flowId)
                            }
                        } catch {
                            
                            await closeCachedWebSocket(protocolInstanceUID: protocolInstanceUID)

                            try? obvContext.performAndWaitOrThrow {
                                pendingServerQuery.responseType = ServerResponse.ResponseType.sourceGetSessionNumberMessage(result: .requestFailed)
                                try obvContext.save(logOnFailure: Self.log)
                                delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: pendingServerQueryObjectId, flowId: flowId)
                            }

                        }
                    }
                    
                case .sourceWaitForTargetConnection(protocolInstanceUID: let protocolInstanceUID):
                    
                    Task { [weak self] in
                        guard let self else { return }
                        do {
                            
                            let response = try await handleSourceWaitForTargetConnectionMessage(protocolInstanceUID: protocolInstanceUID)
                            let targetConnectionId = response.otherConnectionId
                            let payload = response.payload
                            
                            try obvContext.performAndWaitOrThrow {
                                pendingServerQuery.responseType = ServerResponse.ResponseType.sourceWaitForTargetConnection(result: .requestSucceeded(targetConnectionId: targetConnectionId, payload: payload))
                                try obvContext.save(logOnFailure: Self.log)
                                delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: pendingServerQueryObjectId, flowId: flowId)
                            }
                            
                        } catch {
                            
                            await closeCachedWebSocket(protocolInstanceUID: protocolInstanceUID)

                            try? obvContext.performAndWaitOrThrow {
                                pendingServerQuery.responseType = ServerResponse.ResponseType.sourceWaitForTargetConnection(result: .requestFailed)
                                try obvContext.save(logOnFailure: Self.log)
                                delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: pendingServerQueryObjectId, flowId: flowId)
                            }

                        }
                    }

                case .targetSendEphemeralIdentity(protocolInstanceUID: let protocolInstanceUID, transferSessionNumber: let transferSessionNumber, payload: let payload):
                    
                    Task { [weak self] in
                        guard let self else { return }
                        do {
                            
                            let response = try await handleTargetSendEphemeralIdentity(
                                pendingServerQueryObjectId: pendingServerQueryObjectId,
                                protocolInstanceUID: protocolInstanceUID,
                                transferSessionNumber: transferSessionNumber,
                                payload: payload)
                            
                            switch response {
                                
                            case .success((let otherConnectionId, let payload)):
                                
                                try obvContext.performAndWaitOrThrow {
                                    pendingServerQuery.responseType = ServerResponse.ResponseType.targetSendEphemeralIdentity(result: .requestSucceeded(otherConnectionId: otherConnectionId, payload: payload))
                                    try obvContext.save(logOnFailure: Self.log)
                                    delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: pendingServerQueryObjectId, flowId: flowId)
                                }

                            case .failure:
                                
                                // This happens when the transfer session number is incorrect
                                
                                try obvContext.performAndWaitOrThrow {
                                    pendingServerQuery.responseType = ServerResponse.ResponseType.targetSendEphemeralIdentity(result: .incorrectTransferSessionNumber)
                                    try obvContext.save(logOnFailure: Self.log)
                                    delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: pendingServerQueryObjectId, flowId: flowId)
                                }

                            }
                            
                        } catch {
                            
                            await closeCachedWebSocket(protocolInstanceUID: protocolInstanceUID)
                            
                            try obvContext.performAndWaitOrThrow {
                                pendingServerQuery.responseType = ServerResponse.ResponseType.targetSendEphemeralIdentity(result: .requestDidFail)
                                try obvContext.save(logOnFailure: Self.log)
                                delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: pendingServerQueryObjectId, flowId: flowId)
                            }

                        }
                    }

                case .transferRelay(protocolInstanceUID: let protocolInstanceUID, connectionIdentifier: let connectionIdentifier, payload: let payload, thenCloseWebSocket: let thenCloseWebSocket):
                    
                    Task { [weak self] in
                        guard let self else { return }
                        do {

                            let responsePayload = try await handleTransferRelay(
                                protocolInstanceUID: protocolInstanceUID,
                                connectionIdentifier: connectionIdentifier,
                                payload: payload)

                            try obvContext.performAndWaitOrThrow {
                                pendingServerQuery.responseType = ServerResponse.ResponseType.transferRelay(result: .requestSucceeded(payload: responsePayload))
                                try obvContext.save(logOnFailure: Self.log)
                                delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: pendingServerQueryObjectId, flowId: flowId)
                            }

                            if thenCloseWebSocket {
                                await closeCachedWebSocket(protocolInstanceUID: protocolInstanceUID)
                            }
                            
                        } catch {

                            await closeCachedWebSocket(protocolInstanceUID: protocolInstanceUID)

                            try? obvContext.performAndWaitOrThrow {
                                pendingServerQuery.responseType = ServerResponse.ResponseType.transferRelay(result: .requestFailed)
                                try obvContext.save(logOnFailure: Self.log)
                                delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: pendingServerQueryObjectId, flowId: flowId)
                            }

                        }
                    }
                    
                case .transferWait(protocolInstanceUID: let protocolInstanceUID, connectionIdentifier: let connectionIdentifier):
                    
                    Task { [weak self] in
                        guard let self else { return }
                        do {

                            let responsePayload = try await handleTransferWait(protocolInstanceUID: protocolInstanceUID, connectionIdentifier: connectionIdentifier)

                            try obvContext.performAndWaitOrThrow {
                                pendingServerQuery.responseType = ServerResponse.ResponseType.transferWait(result: .requestSucceeded(payload: responsePayload))
                                try obvContext.save(logOnFailure: Self.log)
                                delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: pendingServerQueryObjectId, flowId: flowId)
                            }

                        } catch {
                            
                            await closeCachedWebSocket(protocolInstanceUID: protocolInstanceUID)
                            
                            try? obvContext.performAndWaitOrThrow {
                                pendingServerQuery.responseType = ServerResponse.ResponseType.transferWait(result: .requestFailed)
                                try obvContext.save(logOnFailure: Self.log)
                                delegateManager.networkFetchFlowDelegate.successfullProcessOfServerQuery(withObjectId: pendingServerQueryObjectId, flowId: flowId)
                            }

                        }
                    }
                    
                case .closeWebsocketConnection(protocolInstanceUID: let protocolInstanceUID):
                    
                    Task { [weak self] in
                        do {
                            
                            guard let self else { return }
                            
                            await closeCachedWebSocket(protocolInstanceUID: protocolInstanceUID)

                            try obvContext.performAndWaitOrThrow {
                                pendingServerQuery.deletePendingServerQuery(within: obvContext)
                                try obvContext.save(logOnFailure: Self.log)
                            }
                            
                        } catch {
                            assertionFailure(error.localizedDescription)
                        }
                    }
                    
                }
                
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
        
    }
    
    
    /// The source device sends the first message to the server, and receives a response back, containing the session number SN.
    private func handleSourceGetSessionNumberMessage(pendingServerQueryObjectId: NSManagedObjectID, protocolInstanceUID: UID) async throws -> JsonRequestSourceResponse {
        
        // We do not expect the WebSocket to exist at this point, this is the first possible query made by the source device
        
        guard webSocketTaskForProtocolInstanceUID[protocolInstanceUID] == nil else {
            assertionFailure()
            throw ObvError.unexpectedNonNilWebSocketTask
        }
        
        // Create, cache, and connect the WebScoket
        
        let webSocketTask = getOrCreateAndCacheWebSocket(protocolInstanceUID: protocolInstanceUID)
        
        // Send the JsonRequestSource message
        
        assert(webSocketTask.state == .running)
        let message = try JsonRequestSource().getURLSessionWebSocketTaskMessage()
        try await webSocketTask.send(message)
        
        // Wait for the response
        
        while true {
            
            let serverMessage = try await webSocketTask.receive()
            
            guard try !serverMessage.isEmptyMessage else {
                // The message is empty (e.g., has an empty string), we wait for the next one
                continue
            }

            guard let requestSourceResponse = try? JsonRequestSourceResponse(serverMessage) else {
                assertionFailure()
                throw ObvError.responseParsingFailed
            }
        
            return requestSourceResponse

        }
        
    }

    
    private func handleSourceWaitForTargetConnectionMessage(protocolInstanceUID: UID) async throws -> JsonRequestTargetResponse {
        
        // At this point, we expect the WebSocket to exist already
        
        guard let webSocketTask = webSocketTaskForProtocolInstanceUID[protocolInstanceUID] else {
            assertionFailure()
            throw ObvError.unexpectedNilWebSocketTask
        }

        // No message to send, we only wait for a message sent by the target device
        
        while true {
            
            let serverMessage = try await webSocketTask.receive()
            
            guard try !serverMessage.isEmptyMessage else {
                // The message is empty (e.g., has an empty string), we wait for the next one
                continue
            }

            if let requestTargetResponse = try? JsonRequestTargetResponse(serverMessage) {
                
                // The message is an appropriate response structure
                // At this point, we have no connection identifier to check against, since it is the first time we receive the target connection identifier
                // We can safely return the response
                
                return requestTargetResponse
                
            }

        }
        
    }
    
    
    /// The handled server query is sent by the owned identity transfer protocol on the target device
    /// The transfer session number we got as a parameter was read by the user on the source device and entered by the user on this target device.
    /// We send it to the server in the JsonRequestTarget message. We then receive a response. If the session number was incorrect, we return this information to the protocol.
    /// If it is correct, we wait until we receive a JsonRequestTargetResponse from the source device.
    private func handleTargetSendEphemeralIdentity(pendingServerQueryObjectId: NSManagedObjectID, protocolInstanceUID: UID, transferSessionNumber: ObvOwnedIdentityTransferSessionNumber, payload: Data) async throws -> Result<(otherConnectionId: String, payload: Data), ObvError> {
        
        // We do not expect the WebSocket to exist at this point, this is the first possible query made by the target device
        
        guard webSocketTaskForProtocolInstanceUID[protocolInstanceUID] == nil else {
            assertionFailure()
            throw ObvError.unexpectedNonNilWebSocketTask
        }

        // Create, cache, and connect the WebScoket
        
        let webSocketTask = getOrCreateAndCacheWebSocket(protocolInstanceUID: protocolInstanceUID)

        // Send the JsonRequestTarget message
        
        assert(webSocketTask.state == .running)
        
        if payload.count > ObvConstants.transferMaxPayloadSize {
            let (fragments, totalFragments) = try Self.createPayloadFragmentsFromLargePayload(payload: payload, transferMaxPayloadSize: ObvConstants.transferMaxPayloadSize)
            for (fragmentNumber, payloadFragment) in fragments {
                let message = try JsonRequestTarget(sessionNumber: transferSessionNumber.sessionNumber, payload: payloadFragment, fragmentNumber: fragmentNumber, totalFragments: totalFragments).getURLSessionWebSocketTaskMessage()
                try await webSocketTask.send(message)
            }
        } else {
            let message = try JsonRequestTarget(sessionNumber: transferSessionNumber.sessionNumber, payload: payload, fragmentNumber: nil, totalFragments: nil).getURLSessionWebSocketTaskMessage()
            try await webSocketTask.send(message)
        }

        // Wait for an appropriate response

        var fragments = [Int: JsonRequestTargetResponse]() // Just in case the response appends to be fragmented
        var otherConnectionId: String?

        while true {
            
            let serverMessage = try await webSocketTask.receive()

            guard try !serverMessage.isEmptyMessage else {
                // The message is empty (e.g., has an empty string), we wait for the next one
                continue
            }

            if (try? JsonError(serverMessage)) != nil {
                return .failure(ObvError.wrongSessionNumberIdentifier)
            }

            if let requestTargetResponse = try? JsonRequestTargetResponse(serverMessage) {
                
                if otherConnectionId == nil {
                    otherConnectionId = requestTargetResponse.otherConnectionId
                } else {
                    guard otherConnectionId == requestTargetResponse.otherConnectionId else {
                        assertionFailure()
                        throw ObvError.errorReceivedFromServer
                    }
                }
                
                // If the response is fragmented, accumulate the fragments until they are all available.
                // Otherwise, return the payload
                
                if let fragmentNumber = requestTargetResponse.fragmentNumber, let totalFragments = requestTargetResponse.totalFragments {
                    fragments[fragmentNumber] = requestTargetResponse
                    if fragments.count == totalFragments {
                        // We have all the fragments. We concatenate the payloads and return the resulting payload
                        let payload = fragments.concatenatePayloads()
                        let otherConnectionId = otherConnectionId ?? requestTargetResponse.otherConnectionId
                        return .success((otherConnectionId: otherConnectionId, payload: payload))
                    } else {
                        // Wait for more fragments
                        continue
                    }
                } else {
                    let payload = requestTargetResponse.payload
                    let otherConnectionId = otherConnectionId ?? requestTargetResponse.otherConnectionId
                    return .success((otherConnectionId: otherConnectionId, payload: payload))
                }

            }
                        
        }
        
    }
    
    
    /// Returns the payload of the JsonRequestTargetResponse
    private func handleTransferRelay(protocolInstanceUID: UID, connectionIdentifier: String, payload: Data) async throws -> Data {
        
        // At this point, we expect the WebSocket to exist already
        
        guard let webSocketTask = webSocketTaskForProtocolInstanceUID[protocolInstanceUID] else {
            assertionFailure()
            throw ObvError.unexpectedNilWebSocketTask
        }

        // Send the message to transfer to the other device
        
        assert(webSocketTask.state == .running)

        if payload.count > ObvConstants.transferMaxPayloadSize {
            let (fragments, totalFragments) = try Self.createPayloadFragmentsFromLargePayload(payload: payload, transferMaxPayloadSize: ObvConstants.transferMaxPayloadSize)
            for (fragmentNumber, payloadFragment) in fragments {
                let message = try JsonRequestRelay(relayConnectionId: connectionIdentifier, payload: payloadFragment, fragmentNumber: fragmentNumber, totalFragments: totalFragments).getURLSessionWebSocketTaskMessage()
                try await webSocketTask.send(message)
            }
        } else {
            let message = try JsonRequestRelay(relayConnectionId: connectionIdentifier, payload: payload, fragmentNumber: nil, totalFragments: nil).getURLSessionWebSocketTaskMessage()
            try await webSocketTask.send(message)
        }
        
        // Wait for the response

        var fragments = [Int: JsonRequestTargetResponse]() // Just in case the response appends to be fragmented
        
        while true {
            
            let serverMessage = try await webSocketTask.receive()

            guard try !serverMessage.isEmptyMessage else {
                // The message is empty (e.g., has an empty string), we wait for the next one
                continue
            }
            
            if (try? JsonError(serverMessage)) != nil {
                throw ObvError.errorReceivedFromServer
            }
            
            if let requestTargetResponse = try? JsonRequestTargetResponse(serverMessage) {
                
                // The message is an appropriate response structure
                
                // We check that the connection identifier is the one we expect
                guard requestTargetResponse.otherConnectionId == connectionIdentifier else {
                    assertionFailure()
                    continue
                }
                
                // If the response is fragmented, accumulate the fragments until they are all available.
                // Otherwise, return the payload
                
                if let fragmentNumber = requestTargetResponse.fragmentNumber, let totalFragments = requestTargetResponse.totalFragments {
                    fragments[fragmentNumber] = requestTargetResponse
                    if fragments.count == totalFragments {
                        // We have all the fragments. We concatenate the payloads and return the resulting payload
                        let payload = fragments.concatenatePayloads()
                        return payload
                    } else {
                        // Wait for more fragments
                        continue
                    }
                } else {
                    return requestTargetResponse.payload
                }
                                
            }
            
        }
        
    }
    
    
    /// Returns the payload of the JsonRequestTargetResponse
    private func handleTransferWait(protocolInstanceUID: UID, connectionIdentifier: String) async throws -> Data {
        
        // At this point, we expect the WebSocket to exist already
        
        guard let webSocketTask = webSocketTaskForProtocolInstanceUID[protocolInstanceUID] else {
            assertionFailure()
            throw ObvError.unexpectedNilWebSocketTask
        }

        // Wait for the response

        var fragments = [Int: JsonRequestTargetResponse]() // Just in case the response appends to be fragmented

        while true {
            
            let serverMessage = try await webSocketTask.receive()

            guard try !serverMessage.isEmptyMessage else {
                // The message is empty (e.g., has an empty string), we wait for the next one
                continue
            }
            
            if (try? JsonError(serverMessage)) != nil {
                throw ObvError.errorReceivedFromServer
            }

            if let requestTargetResponse = try? JsonRequestTargetResponse(serverMessage) {
                
                // The message is an appropriate response structure
                
                // We check that the connection identifier is the one we expect
                guard requestTargetResponse.otherConnectionId == connectionIdentifier else {
                    assertionFailure()
                    continue
                }
                
                // If the response is fragmented, accumulate the fragments until they are all available.
                // Otherwise, return the payload
                
                if let fragmentNumber = requestTargetResponse.fragmentNumber, let totalFragments = requestTargetResponse.totalFragments {
                    fragments[fragmentNumber] = requestTargetResponse
                    if fragments.count == totalFragments {
                        // We have all the fragments. We concatenate the payloads and return the resulting payload
                        let payload = fragments.concatenatePayloads()
                        return payload
                    } else {
                        // Wait for more fragments
                        continue
                    }
                } else {
                    return requestTargetResponse.payload
                }

            }
                        
        }

    }

    
    private func getOrCreateAndCacheWebSocket(protocolInstanceUID: UID) -> URLSessionWebSocketTask {
        if let webSocketTask = webSocketTaskForProtocolInstanceUID[protocolInstanceUID] {
            return webSocketTask
        } else {
            let webSocketTask = URLSession.shared.webSocketTask(with: ObvConstants.transferWSServerURL)
            webSocketTask.resume()
            webSocketTaskForProtocolInstanceUID[protocolInstanceUID] = webSocketTask
            return webSocketTask
        }
    }
    
    
    private func closeCachedWebSocket(protocolInstanceUID: UID) {
        guard let webSocketTask = webSocketTaskForProtocolInstanceUID.removeValue(forKey: protocolInstanceUID) else { return }
        webSocketTask.cancel(with: .normalClosure, reason: nil)
    }
    
    
    
    // Errors
    
    enum ObvError: Error {
        case theDelegateManagerIsNil
        case theContextCreatorIsNil
        case unexpectedNonNilWebSocketTask
        case unexpectedNilWebSocketTask
        case responseParsingFailed
        case wrongSessionNumberIdentifier
        case errorReceivedFromServer
        case overflow
    }
    
}



// MARK: - Messages to send and receive on the WebSocket handling "WebSocket" server queries

private struct JsonRequestSource: Encodable {
    private let action = "source"
    func getURLSessionWebSocketTaskMessage() throws -> URLSessionWebSocketTask.Message {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        let string = String(data: data, encoding: .utf8)!
        return URLSessionWebSocketTask.Message.string(string)
    }
}


private struct JsonRequestSourceResponse: Decodable {
    let sessionNumber: Int
    let sourceConnectionId: String
    enum CodingKeys: String, CodingKey {
        case sessionNumber = "sessionNumber"
        case sourceConnectionId = "awsConnectionId"
    }
    init(_ message: URLSessionWebSocketTask.Message) throws {
        let decoder = JSONDecoder()
        let receivedData: Data
        switch message {
        case .data(let data):
            receivedData = data
        case .string(let string):
            guard let _receivedData = string.data(using: .utf8) else {
                throw ObvError.couldNotParseString
            }
            receivedData = _receivedData
        @unknown default:
            assertionFailure()
            throw ObvError.unexpectedType
        }
        self = try decoder.decode(Self.self, from: receivedData)
    }
    enum ObvError: Error {
        case couldNotParseString
        case unexpectedType
    }
}


private struct JsonRequestTarget: Encodable {
    private let action = "target"
    let sessionNumber: Int
    let payload: Data
    let fragmentNumber: Int?
    let totalFragments: Int?

    func getURLSessionWebSocketTaskMessage() throws -> URLSessionWebSocketTask.Message {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        let string = String(data: data, encoding: .utf8)!
        return URLSessionWebSocketTask.Message.string(string)
    }
}


private struct JsonRequestTargetResponse: Decodable {
    let otherConnectionId: String
    let payload: Data
    let fragmentNumber: Int?
    let totalFragments: Int?
    init(_ message: URLSessionWebSocketTask.Message) throws {
        let decoder = JSONDecoder()
        let receivedData: Data
        switch message {
        case .data(let data):
            receivedData = data
        case .string(let string):
            guard let _receivedData = string.data(using: .utf8) else {
                throw ObvError.couldNotParseString
            }
            receivedData = _receivedData
        @unknown default:
            assertionFailure()
            throw ObvError.unexpectedType
        }
        self = try decoder.decode(Self.self, from: receivedData)
    }
    enum ObvError: Error {
        case couldNotParseString
        case unexpectedType
    }
}


private struct JsonRequestRelay: Encodable {
    private let action = "relay"
    let relayConnectionId: String
    let payload: Data
    let fragmentNumber: Int?
    let totalFragments: Int?
    func getURLSessionWebSocketTaskMessage() throws -> URLSessionWebSocketTask.Message {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        let string = String(data: data, encoding: .utf8)!
        return URLSessionWebSocketTask.Message.string(string)
    }
}


private struct JsonError: Decodable {
    let errorCode: Int
    init(_ message: URLSessionWebSocketTask.Message) throws {
        let decoder = JSONDecoder()
        let receivedData: Data
        switch message {
        case .data(let data):
            receivedData = data
        case .string(let string):
            guard let _receivedData = string.data(using: .utf8) else {
                throw ObvError.couldNotParseString
            }
            receivedData = _receivedData
        @unknown default:
            assertionFailure()
            throw ObvError.unexpectedType
        }
        do {
            self = try decoder.decode(Self.self, from: receivedData)
        } catch {
            throw error
        }
    }
    enum ObvError: Error {
        case couldNotParseString
        case unexpectedType
    }
}


// MARK: - Private Helpers

fileprivate extension  URLSessionWebSocketTask.Message {
    
    var isEmptyMessage: Bool {
        get throws {
            switch self {
            case .data(let data):
                return data.isEmpty
            case .string(let string):
                return string.isEmpty
            @unknown default:
                assertionFailure()
                throw ObvError.unknownMessageKind
            }
        }
    }
    
    enum ObvError: Error {
        case unknownMessageKind
    }
    
}


fileprivate extension [Int : JsonRequestTargetResponse] {
    
    func concatenatePayloads() -> Data {
        let payload = self
            .sorted(by: { $0.key < $1.key })
            .map(\.value)
            .map(\.payload)
            .reduce(Data(), { $0 + $1 })
        return payload
    }
    
}


fileprivate extension ServerQueryWebSocketCoordinator {
    
    static func createPayloadFragmentsFromLargePayload(payload: Data, transferMaxPayloadSize: Int) throws -> (fragments: [Int : Data], totalFragments: Int) {
        var fragments = [Int : Data]()
        let totalFragments = 1 + (payload.count - 1) / ObvConstants.transferMaxPayloadSize
        for fragmentNumber in 0..<totalFragments {
            let lowerBound: Int = fragmentNumber     * ObvConstants.transferMaxPayloadSize
            let upperBound: Int = (fragmentNumber+1) * ObvConstants.transferMaxPayloadSize
            let startIndex: Int = payload.startIndex + lowerBound
            let upperIndex: Int = payload.startIndex + min(upperBound, payload.count)
            guard startIndex >= payload.startIndex, upperIndex <= payload.endIndex, startIndex <= upperIndex else {
                assertionFailure()
                throw ObvError.overflow
            }
            let payloadFragment = payload[startIndex..<upperIndex]
            fragments[fragmentNumber] = payloadFragment
        }
        // Sanity checks
        for value in 0..<totalFragments {
            assert(fragments.keys.contains(where: { $0 == value }))
            assert(fragments.count == totalFragments)
        }
        return (fragments, totalFragments)
    }

}
