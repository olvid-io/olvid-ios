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
import os.log
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils


final class BackgroundTaskCoordinator: SimpleBackgroundTaskDelegate, BackgroundTaskDelegate {
    
    // MARK: Instance variables
    
    private static let logCategory = "BackgroundTaskCoordinator"

    weak var delegateManager: ObvFlowDelegateManager?
    
    private var notificationCenterTokens = [NSObjectProtocol]()
    
    private static func makeError(message: String) -> Error { NSError(domain: "BackgroundTaskCoordinator", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    private var _currentExpectationsWithinFlow = [FlowIdentifier: (expectations: Set<Expectation>, backgroundTaskId: UIBackgroundTaskIdentifier, completionHander: (() -> Void)?)]()
    private let backgroundActivitiesQueue = DispatchQueue(label: "BackgroundTaskCoordinator.CurrentExpectationsWithinFlowQueue")
    private let internalQueue = OperationQueue()
    
    private let backgroundTaskManager: ObvBackgroundTaskManager
    
    /// Called when starting the full engine. In practice, the `ObvBackgroundTaskManager` is implemented using the UIApplication object.
    init(backgroundTaskManager: ObvBackgroundTaskManager) {
        self.backgroundTaskManager = backgroundTaskManager
    }
    
    /// Called when starting a limited engine, where the UIApplication is not defined.
    init() {
        self.backgroundTaskManager = BackgroundActivityEmulator()
    }
    
    // MARK: - Init/Deinit
    
    deinit {
        if let notificationDelegate = delegateManager?.notificationDelegate {
            notificationCenterTokens.forEach {
                notificationDelegate.removeObserver($0)
            }
        }
    }

}


// MARK: - Synchronized access to the current background tasks

extension BackgroundTaskCoordinator {
    
    
    private func startFlowForBackgroundTask(with expectations: Set<Expectation>, completionHandler: (() -> Void)? = nil) throws -> FlowIdentifier {
        
        guard let delegateManager = delegateManager else {
            throw Self.makeError(message: "The delegate manager is not set")
        }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: BackgroundTaskCoordinator.logCategory)
        
        let flowId = FlowIdentifier()
        
        let backgroundTaskId = backgroundTaskManager.beginBackgroundTask { [weak self] in
            // End the activity if time expires.
            os_log("Ending background activity associated with flow %{public}@ because time expired", log: log, type: .error, flowId.debugDescription)
            self?.endBackgroundActivityAssociatedWithFlow(withId: flowId)
        }

        backgroundActivitiesQueue.sync {
            _currentExpectationsWithinFlow[flowId] = (expectations, backgroundTaskId, completionHandler)
        }
        
        os_log("Starting flow %{public}@ associated with background task %d", log: log, type: .info, flowId.debugDescription, backgroundTaskId.rawValue)
        os_log("Initial expectations of flow %{public}@: %{public}@", log: log, type: .info, flowId.debugDescription, Expectation.description(of: expectations))

        return flowId
    }

    
    private func updateExpectationsOfBackgroundActivityAssociatedWithFlow(withId flowId: FlowIdentifier, expectationsToRemove: [Expectation], expectationsToAdd: [Expectation]) {
        
        guard let delegateManager = delegateManager else { return }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: BackgroundTaskCoordinator.logCategory)
        
        backgroundActivitiesQueue.sync {
            
            // Update the flow expectations
            
            do {
                guard let (expectations, backgroundTaskId, completionHandler) = _currentExpectationsWithinFlow[flowId] else { return }
                
                os_log("Expectations of background activity associated with flow %{public}@ before update: %{public}@", log: log, type: .info, flowId.debugDescription, Expectation.description(of: expectations))
                let newExpectations = expectations.subtracting(expectationsToRemove).union(expectationsToAdd)
                os_log("Expectations of background activity associated with flowId %{public}@ after update: %{public}@", log: log, type: .info, flowId.debugDescription, Expectation.description(of: newExpectations))

                _currentExpectationsWithinFlow[flowId] = (newExpectations, backgroundTaskId, completionHandler)

            }
            
        }
        
        self.endBackgroundActivityIfItHasNoMoreExpectationsWithinFlow(withId: flowId)
    }
    
    
    /// In certain cases, we don't care about the exact flow where a certain event appened. For example, if an attachment has been taken care of by the send manager, we can considered it as "taken care of" in all flows.
    /// For all similar situations, this is the method to call instead of
    /// ``func updateExpectationsOfBackgroundActivityAssociatedWithFlow(withId flowId: FlowIdentifier, expectationsToRemove: [Expectation], expectationsToAdd: [Expectation])``
    /// This makes this coordinator more resilient to "flow changes".
    private func updateExpectationsOfAllBackgroundActivities(expectationsToRemove: [Expectation]) {
        
        guard let delegateManager = delegateManager else { assertionFailure(); return }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: BackgroundTaskCoordinator.logCategory)

        var flowsToUpdate = Set<FlowIdentifier>()
        
        backgroundActivitiesQueue.sync {
            
            flowsToUpdate = Set(_currentExpectationsWithinFlow.compactMap { (flowId, value) in
                value.expectations.intersection(expectationsToRemove).isEmpty ? nil : flowId
            })
            
            for flowId in flowsToUpdate {
                guard let value = _currentExpectationsWithinFlow[flowId] else { assertionFailure(); continue }
                os_log("Expectations of background activity associated with flow %{public}@ before update: %{public}@", log: log, type: .info, flowId.debugDescription, Expectation.description(of: value.expectations))
                let newExpectations = value.expectations.subtracting(expectationsToRemove)
                os_log("Expectations of background activity associated with flowId %{public}@ after update: %{public}@", log: log, type: .info, flowId.debugDescription, Expectation.description(of: newExpectations))
                _currentExpectationsWithinFlow[flowId] = (newExpectations, value.backgroundTaskId, value.completionHander)
            }
            
        }

        for flowId in flowsToUpdate {
            self.endBackgroundActivityIfItHasNoMoreExpectationsWithinFlow(withId: flowId)
        }
        
    }
    
    
    private func endBackgroundActivityAssociatedWithFlow(withId flowId: FlowIdentifier) {
        guard let delegateManager = delegateManager else { return }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: BackgroundTaskCoordinator.logCategory)
        backgroundActivitiesQueue.sync {

            guard let (expectations, backgroundTaskId, completionHandler) = _currentExpectationsWithinFlow.removeValue(forKey: flowId) else { return }
            if !expectations.isEmpty {
                os_log("We are about to end the background activity associated with flow %{public}@ although there are still expectations: %{public}@", log: log, type: .error, flowId.debugDescription, Expectation.description(of: expectations))
            }
            os_log("Ending flow %{public}@ associated with background task %d", log: log, type: .info, flowId.debugDescription, backgroundTaskId.rawValue)
            
            backgroundTaskManager.endBackgroundTask(backgroundTaskId, completionHandler: completionHandler)

        }
        
    }
    
    
    private func endBackgroundActivityIfItHasNoMoreExpectationsWithinFlow(withId flowId: FlowIdentifier) {
        var backgroundActivityHasNoMoreExpectations = false
        backgroundActivitiesQueue.sync {
            guard let (expectations, _, _) = _currentExpectationsWithinFlow[flowId] else { return }
            backgroundActivityHasNoMoreExpectations = expectations.isEmpty
        }
        if backgroundActivityHasNoMoreExpectations {
            endBackgroundActivityAssociatedWithFlow(withId: flowId)
        }
    }
    
}

// MARK: - Receiving and processing notifications related to background activities

extension BackgroundTaskCoordinator {
    
    func observeEngineNotifications() {
        
        guard let delegateManager = delegateManager else { return }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: BackgroundTaskCoordinator.logCategory)
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }
        
        notificationCenterTokens.append(contentsOf: [

            // NewOutboxMessageAndAttachmentsToUpload
            ObvNetworkPostNotification.observeNewOutboxMessageAndAttachmentsToUpload(within: notificationDelegate) { [weak self] (messageId, attachmentIds, flowId) in
                os_log("NewOutboxMessageAndAttachmentsToUpload notification received within flow %{public}@", log: log, type: .debug, flowId.debugDescription)
                if attachmentIds.isEmpty {
                    self?.updateExpectationsOfBackgroundActivityAssociatedWithFlow(withId: flowId,
                                                                                   expectationsToRemove: [],
                                                                                   expectationsToAdd: [.deletionOfOutboxMessage(withId: messageId)])
                } else {
                    let expectationsToAdd = attachmentIds.map { Expectation.attachmentUploadRequestIsTakenCareOfForAttachment(withId: $0) }
                    self?.updateExpectationsOfBackgroundActivityAssociatedWithFlow(withId: flowId,
                                                                                   expectationsToRemove: [],
                                                                                   expectationsToAdd: expectationsToAdd)
                }
            },

            // OutboxMessageWasUploaded
            ObvNetworkPostNotification.observeOutboxMessageWasUploaded(within: notificationDelegate, queue: internalQueue) { [weak self] (messageId, _, _, _, flowId) in
                os_log("OutboxMessageWasUploaded notification received within flow %{public}@ for messageId %{public}@", log: log, type: .debug, flowId.debugDescription, messageId.debugDescription)
                self?.updateExpectationsOfAllBackgroundActivities(expectationsToRemove: [.outboxMessageWasUploaded(messageId: messageId)])
            },
            
            // AttachmentUploadRequestIsTakenCareOf
            ObvNetworkPostNotification.observeAttachmentUploadRequestIsTakenCareOf(within: notificationDelegate) { [weak self] (attachmentId, flowId) in
                os_log("AttachmentUploadRequestIsTakenCareOf notification received within flow %{public}@ for attachmentId %{public}@", log: log, type: .debug, flowId.debugDescription, attachmentId.debugDescription)
                self?.updateExpectationsOfAllBackgroundActivities(expectationsToRemove: [.attachmentUploadRequestIsTakenCareOfForAttachment(withId: attachmentId)])
            },
            
            // OutboxMessageAndAttachmentsDeleted
            ObvNetworkPostNotification.observeOutboxMessageAndAttachmentsDeleted(within: notificationDelegate) { [weak self] (messageId, flowId) in
                os_log("OutboxMessageAndAttachmentsDeleted notification received within flow %{public}@ for messageId %{public}@", log: log, type: .debug, flowId.debugDescription, messageId.debugDescription)
                self?.updateExpectationsOfAllBackgroundActivities(expectationsToRemove: [.deletionOfOutboxMessage(withId: messageId)])
            },
            
            // ProtocolMessageToProcess
            ObvProtocolNotification.observeProtocolMessageToProcess(within: notificationDelegate) { [weak self] (protocolMessageId, flowId) in
                os_log("ProtocolMessageToProcess notification received within flow %{public}@", log: log, type: .debug, flowId.debugDescription)
                self?.updateExpectationsOfBackgroundActivityAssociatedWithFlow(withId: flowId,
                                                                               expectationsToRemove: [.protocolMessageToProcess, .uidsOfMessagesToProcess(ownedCryptoIdentity: protocolMessageId.ownedCryptoIdentity)],
                                                                               expectationsToAdd: [.endOfProcessingOfProtocolMessage(withId: protocolMessageId)])
            },
            
            // ProtocolMessageProcessed
            ObvProtocolNotification.observeProtocolMessageProcessed(within: notificationDelegate) { [weak self] (protocolMessageId, flowId) in
                os_log("ProtocolMessageProcessed notification received within flow %{public}@", log: log, type: .debug, flowId.debugDescription)
                self?.updateExpectationsOfAllBackgroundActivities(expectationsToRemove: [.endOfProcessingOfProtocolMessage(withId: protocolMessageId)])
            },
            
        ])
        
    }
    
}

// MARK: - API

extension BackgroundTaskCoordinator {
    
    // Simple situations
    
    func simpleBackgroundTask(withReason reason: String, using block: @escaping (Bool) -> Void) {
        let log = OSLog(subsystem: "io.olvid.protocol", category: BackgroundTaskCoordinator.logCategory)
        let backgroundTaskId = backgroundTaskManager.beginBackgroundTask(expirationHandler: nil)
        os_log("Starting simple background task %d with reason %{public}@", log: log, type: .debug, backgroundTaskId.rawValue, reason)
        block(false)
        os_log("Ending simple background task %d with reason %{public}@", log: log, type: .debug, backgroundTaskId.rawValue, reason)
        backgroundTaskManager.endBackgroundTask(backgroundTaskId, completionHandler: nil)
    }

    // Posting message and attachments
    
    /// For now, this method is used when starting a flow for sending an application message. Since one application message can result in multiple net work messages (when the contacts of the
    /// message are on distinct servers), we first create a flow with no expectations, then add the expectations one at a time.
    func startNewFlow(completionHandler: (() -> Void)? = nil) throws -> FlowIdentifier {
        try startFlowForBackgroundTask(with: Set<Expectation>(), completionHandler: completionHandler)
    }
    
    func addBackgroundActivityForPostingApplicationMessageAttachmentsWithinFlow(withFlowId flowId: FlowIdentifier, messageId: MessageIdentifier, attachmentIds: [AttachmentIdentifier]) {
        
        let expectations: Set<Expectation>
        if attachmentIds.isEmpty {
            expectations = Set<Expectation>([Expectation.outboxMessageWasUploaded(messageId: messageId)])
        } else {
            expectations = Set<Expectation>(attachmentIds.map { Expectation.attachmentUploadRequestIsTakenCareOfForAttachment(withId: $0) })
        }

        updateExpectationsOfBackgroundActivityAssociatedWithFlow(withId: flowId, expectationsToRemove: [], expectationsToAdd: Array(expectations))
        
    }
    
    // Posting a return receipt (for message or an attachment)
    
    /// This method allows to start a flow allowing to make sure the system gives us enough time to post the return receipt corresponding to a fully received message or attachment.
    ///
    /// In practice, this method is called by the engine when receiving a notification of the network fetch manager that a message / attachment is available.
    /// It is called *before* notifying the app. The app will eventually post a return receipt. To do that, it will make a request to the engine that will eventually call the
    /// ``stopBackgroundActivityForPostingReturnReceipt(messageId: MessageIdentifier, attachmentNumber: Int?)`` bellow.
    ///
    func startBackgroundActivityForPostingReturnReceipt(messageId: MessageIdentifier, attachmentNumber: Int?) throws -> FlowIdentifier {
        guard let delegateManager = delegateManager else {
            assertionFailure()
            throw Self.makeError(message: "🧾 The delegate manager is not set")
        }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: BackgroundTaskCoordinator.logCategory)
        let expectations: Set<Expectation>
        if let attachmentNumber = attachmentNumber {
            let attachmentId = AttachmentIdentifier(messageId: messageId, attachmentNumber: attachmentNumber)
            os_log("🧾 Starting background activity for attachmentId %{public}@", log: log, type: .debug, attachmentId.debugDescription)
            expectations = Set([.returnReceiptWasPostedForAttachment(attachmentId: attachmentId)])
        } else {
            os_log("🧾 Starting background activity for messageId %{public}@", log: log, type: .debug, messageId.debugDescription)
            expectations = Set([.returnReceiptWasPostedForMessage(messageId: messageId)])
        }
        return try startFlowForBackgroundTask(with: expectations)
    }
    
    /// This method allows to stop the flow allowing to wait until a return receipt is posted. See the comment for the
    /// ``startBackgroundActivityForPostingReturnReceipt(messageId: MessageIdentifier, attachmentNumber: Int?) throws``
    /// method above.
    func stopBackgroundActivityForPostingReturnReceipt(messageId: MessageIdentifier, attachmentNumber: Int?) throws {
        guard let delegateManager = delegateManager else {
            assertionFailure()
            throw Self.makeError(message: "The delegate manager is not set")
        }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: BackgroundTaskCoordinator.logCategory)
        let expectationsToRemove: [Expectation]
        if let attachmentNumber = attachmentNumber {
            let attachmentId = AttachmentIdentifier(messageId: messageId, attachmentNumber: attachmentNumber)
            os_log("🧾 Stopping background activity for attachmentId %{public}@", log: log, type: .debug, attachmentId.debugDescription)
            expectationsToRemove = [.returnReceiptWasPostedForAttachment(attachmentId: attachmentId)]
        } else {
            os_log("🧾 Stopping background activity for messageId %{public}@", log: log, type: .debug, messageId.debugDescription)
            expectationsToRemove = [.returnReceiptWasPostedForMessage(messageId: messageId)]
        }
        updateExpectationsOfAllBackgroundActivities(expectationsToRemove: expectationsToRemove)
    }
    
    // Resuming a protocol
    
    func startBackgroundActivityForStartingOrResumingProtocol() throws -> FlowIdentifier {
        let expectations = Set([Expectation.protocolMessageToProcess])
        return try startFlowForBackgroundTask(with: expectations)
    }
    
    
    // Downloading messages, downloading/pausing attachment
    
    func startBackgroundActivityForDownloadingMessages(ownedIdentity: ObvCryptoIdentity) -> FlowIdentifier? {
        return FlowIdentifier()
    }
    

    // Deleting a message or an attachment
    
    func startBackgroundActivityForDeletingAMessage(messageId: MessageIdentifier) -> FlowIdentifier? {
        return FlowIdentifier()
    }
    
    func startBackgroundActivityForDeletingAnAttachment(attachmentId: AttachmentIdentifier) -> FlowIdentifier? {
        return FlowIdentifier()
    }
    
}
