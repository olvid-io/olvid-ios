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


/// This actor allows the engine to post a protocol message and to wait until it is fully processed (i.e., deleted from the `ReceivedMessage` database of the protocol manager).
/// Note that the fact that a protocol message is deleted does not necessarily mean that the protocol step did succeed (or even that a protocol step was executed).
/// This actor was created while implementing the bind/unbind to keycloak protocol, making it possible to make sure the message allowing to bind the owned identity was processed before
/// registering the owned identity (at the app level).
actor ProtocolWaiter {
    
    private weak var delegateManager: ObvMetaManager?
    private let prng: PRNGService

    init(delegateManager: ObvMetaManager, prng: PRNGService) {
        self.delegateManager = delegateManager
        self.prng = prng
    }
    
    private var createContextDelegate: ObvCreateContextDelegate? {
        delegateManager?.createContextDelegate
    }
    
    private var channelDelegate: ObvChannelDelegate? {
        delegateManager?.channelDelegate
    }

    private var flowDelegate: ObvFlowDelegate? {
        delegateManager?.flowDelegate
    }
    
    private var notificationDelegate: ObvNotificationDelegate? {
        delegateManager?.notificationDelegate
    }

    /// Stores the continuations created in ``waitUntilEndOfProcessingOfProtocolMessage(_:log:)``. When a protocol ``ReceivedMessage`` is deleted, a notification is send.
    /// We process this notification in this actor and check whether the received `messageId` corresponds to some store completion. If it is the case, we remove the `messageId` from the list of Ids.
    /// Once the list is empty, we call the completion.
    private var storedContinuations = [(continuation: CheckedContinuation<Void, Error>, messageIds: [ObvMessageIdentifier])]()
    
    private var token: NSObjectProtocol?
    
    
    private func observeProtocolReceivedMessageWasDeletedNotificationsIfRequired() throws {
        guard token == nil else { return }
        guard let notificationDelegate else { assertionFailure(); throw ObvError.notificationDelegateIsNil }
        token = ObvProtocolNotification.observeProtocolReceivedMessageWasDeleted(within: notificationDelegate) {  messageId in
            Task { [weak self] in await self?.processProtocolReceivedMessageWasDeleted(messageId: messageId) }
        }
    }
    
    
    private func processProtocolReceivedMessageWasDeleted(messageId: ObvMessageIdentifier) {
        var continuationsToKeep = [(continuation: CheckedContinuation<Void, Error>, messageIds: [ObvMessageIdentifier])]()
        while let storedContinuation = storedContinuations.popLast() {
            let continuation = storedContinuation.continuation
            var messagesIds = storedContinuation.messageIds
            messagesIds.removeAll(where: { $0 == messageId })
            if messagesIds.isEmpty {
                storedContinuation.continuation.resume()
            } else {
                continuationsToKeep.append((continuation, messagesIds))
            }
        }
        storedContinuations = continuationsToKeep
    }
    
    
    func waitUntilEndOfProcessingOfProtocolMessage(_ message: ObvChannelProtocolMessageToSend, log: OSLog) async throws {
        
        guard let createContextDelegate = createContextDelegate else { assertionFailure(); throw ObvError.createContextDelegateIsNil }
        guard let channelDelegate else { assertionFailure(); throw ObvError.channelDelegateIsNil }
        guard let flowDelegate else { assertionFailure(); throw ObvError.flowDelegateIsNil }

        try observeProtocolReceivedMessageWasDeletedNotificationsIfRequired()
        
        let flowId = try flowDelegate.startBackgroundActivityForStartingOrResumingProtocol()
        let prng = self.prng

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            createContextDelegate.performBackgroundTask(flowId: flowId) { obvContext in
                let messageIds: [ObvMessageIdentifier]
                do {
                    messageIds = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext).map({ $0.key })
                } catch {
                    assertionFailure()
                    continuation.resume(throwing: error)
                    return
                }
                self.storedContinuations.append((continuation, messageIds))
                do {
                    try obvContext.save(logOnFailure: log)
                } catch {
                    assertionFailure()
                    continuation.resume(throwing: error)
                    return
                }
            }
        }
        
    }
    
    // MARK: - Errors
    
    enum ObvError: LocalizedError {
        
        case createContextDelegateIsNil
        case channelDelegateIsNil
        case flowDelegateIsNil
        case notificationDelegateIsNil
        
        var errorDescription: String? {
            switch self {
            case .createContextDelegateIsNil:
                return "Create context delegate is nil"
            case .flowDelegateIsNil:
                return "Flow delegate is nil"
            case .channelDelegateIsNil:
                return "Channel delegate is nil"
            case .notificationDelegateIsNil:
                return "Notification delegate is nil"
            }
        }

    }
}
