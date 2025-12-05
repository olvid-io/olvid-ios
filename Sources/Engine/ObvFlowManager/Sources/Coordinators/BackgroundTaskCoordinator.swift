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
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils


final class BackgroundTaskCoordinator: SimpleBackgroundTaskDelegate, BackgroundTaskDelegate {
    
    // MARK: Instance variables
    
    private static let logCategory = "BackgroundTaskCoordinator"

    private let debugUUID = UUID().uuidString.prefix(4)
    
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


extension BackgroundTaskCoordinator {
    
    private func getCurrentExpectationsWithinFlow(flowId: FlowIdentifier, logger: Logger) -> (expectations: Set<Expectation>, backgroundTaskId: UIBackgroundTaskIdentifier, completionHander: (() -> Void)?)? {
        logger.info("[\(self.debugUUID)] Call to getCurrentExpectationsWithinFlow")
        return _currentExpectationsWithinFlow[flowId]
    }

    private func setCurrentExpectationsWithinFlow(flowId: FlowIdentifier, logger: Logger, to newValues: (expectations: Set<Expectation>, backgroundTaskId: UIBackgroundTaskIdentifier, completionHander: (() -> Void)?)) {
        logger.info("[\(self.debugUUID)] Call to setCurrentExpectationsWithinFlow")
        _currentExpectationsWithinFlow[flowId] = newValues
    }
    
    private func removeCurrentExpectationsWithinFlow(flowId: FlowIdentifier, logger: Logger) -> (expectations: Set<Expectation>, backgroundTaskId: UIBackgroundTaskIdentifier, completionHander: (() -> Void)?)? {
        let removedValue = _currentExpectationsWithinFlow.removeValue(forKey: flowId)
        logger.info("[\(self.debugUUID)] Call to removeCurrentExpectationsWithinFlow (removing value \(removedValue.debugDescription)")
        return removedValue
    }
    
}


// MARK: - Synchronized access to the current background tasks

extension BackgroundTaskCoordinator {
    
    
    private func startFlowForBackgroundTask(with expectations: Set<Expectation>, completionHandler: (() -> Void)? = nil) throws -> FlowIdentifier {
        
        guard let delegateManager = delegateManager else {
            throw Self.makeError(message: "The delegate manager is not set")
        }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: BackgroundTaskCoordinator.logCategory)
        let logger = Logger(subsystem: delegateManager.logSubsystem, category: BackgroundTaskCoordinator.logCategory)
        
        let flowId = FlowIdentifier()
        
        let backgroundTaskId = backgroundTaskManager.beginBackgroundTask(withName: "startFlowForBackgroundTask with expectations \(expectations.map({ $0.debugDescription }).joined(separator: ","))") { [weak self] in
            // End the activity if time expires.
            os_log("Ending background activity associated with flow %{public}@ because time expired", log: log, type: .error, flowId.debugDescription)
            self?.endBackgroundActivityAssociatedWithFlow(withId: flowId)
        }

        backgroundActivitiesQueue.sync {
            setCurrentExpectationsWithinFlow(flowId: flowId, logger: logger, to: (expectations, backgroundTaskId, completionHandler))
        }
        
        logger.info("[\(self.debugUUID)] Starting flow \(flowId.debugDescription, privacy: .public) associated with background task \(backgroundTaskId.rawValue)")
        logger.info("[\(self.debugUUID)] Initial expectations of flow \(flowId.debugDescription, privacy: .public): \(Expectation.description(of: expectations), privacy: .public)")

        return flowId
    }

    
    private func updateExpectationsOfBackgroundActivityAssociatedWithFlow(withId flowId: FlowIdentifier, expectationsToRemove: [Expectation], expectationsToAdd: [Expectation]) {
        
        guard let delegateManager = delegateManager else { return }
        let logger = Logger(subsystem: delegateManager.logSubsystem, category: BackgroundTaskCoordinator.logCategory)
        
        var numberOfExpectationsLeft = 0

        backgroundActivitiesQueue.sync {
            
            // Update the flow expectations
            
            guard let (expectations, backgroundTaskId, completionHandler) = getCurrentExpectationsWithinFlow(flowId: flowId, logger: logger) else { return }
            
            logger.info("[\(self.debugUUID)] Expectations of background activity associated with flow \(flowId.debugDescription, privacy: .public) before update: \(Expectation.description(of: expectations), privacy: .public)")
            let newExpectations = expectations.subtracting(expectationsToRemove).union(expectationsToAdd)
            logger.info("[\(self.debugUUID)] Expectations of background activity associated with flowId \(flowId.debugDescription, privacy: .public) after update: \(Expectation.description(of: expectations), privacy: .public)")
            
            setCurrentExpectationsWithinFlow(flowId: flowId, logger: logger, to: (newExpectations, backgroundTaskId, completionHandler))
            
            numberOfExpectationsLeft = self._currentExpectationsWithinFlow.count

        }
        
        self.endBackgroundActivityIfItHasNoMoreExpectationsWithinFlow(withId: flowId, numberOfExpectationsLeft: numberOfExpectationsLeft)
    }
    
    
    /// In certain cases, we don't care about the exact flow where a certain event appened. For example, if an attachment has been taken care of by the send manager, we can considered it as "taken care of" in all flows.
    /// For all similar situations, this is the method to call instead of
    /// ``func updateExpectationsOfBackgroundActivityAssociatedWithFlow(withId flowId: FlowIdentifier, expectationsToRemove: [Expectation], expectationsToAdd: [Expectation])``
    /// This makes this coordinator more resilient to "flow changes".
    private func updateExpectationsOfAllBackgroundActivities(expectationsToRemove: [Expectation]) {
        
        guard let delegateManager = delegateManager else { assertionFailure(); return }
        let logger = Logger(subsystem: delegateManager.logSubsystem, category: BackgroundTaskCoordinator.logCategory)

        var flowsToUpdate = Set<FlowIdentifier>()
        
        var numberOfExpectationsLeft = 0
        
        backgroundActivitiesQueue.sync {
            
            flowsToUpdate = Set(_currentExpectationsWithinFlow.compactMap { (flowId, value) in
                value.expectations.intersection(expectationsToRemove).isEmpty ? nil : flowId
            })
            
            let currentNumberOfFlows = _currentExpectationsWithinFlow.count
            logger.info("[\(self.debugUUID)] Among the \(currentNumberOfFlows, privacy: .public) flows, there are \(flowsToUpdate.count) flows to update")
            
            for flowId in flowsToUpdate {
                guard let value = getCurrentExpectationsWithinFlow(flowId: flowId, logger: logger) else { assertionFailure(); continue }
                logger.info("[\(self.debugUUID)] Expectations of background activity associated with flow \(flowId.debugDescription, privacy: .public) before update: \(Expectation.description(of: value.expectations), privacy: .public)")
                let newExpectations = value.expectations.subtracting(expectationsToRemove)
                logger.info("[\(self.debugUUID)] Expectations of background activity associated with flowId \(flowId.debugDescription, privacy: .public) after update: \(Expectation.description(of: newExpectations), privacy: .public)")
                setCurrentExpectationsWithinFlow(flowId: flowId, logger: logger, to: (newExpectations, value.backgroundTaskId, value.completionHander))
            }
            
            numberOfExpectationsLeft = self._currentExpectationsWithinFlow.count

        }

        for flowId in flowsToUpdate {
            self.endBackgroundActivityIfItHasNoMoreExpectationsWithinFlow(withId: flowId, numberOfExpectationsLeft: numberOfExpectationsLeft)
        }
        
    }
    
    
    private func endBackgroundActivityAssociatedWithFlow(withId flowId: FlowIdentifier) {
        guard let delegateManager = delegateManager else { return }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: BackgroundTaskCoordinator.logCategory)
        let logger = Logger(subsystem: delegateManager.logSubsystem, category: BackgroundTaskCoordinator.logCategory)
        backgroundActivitiesQueue.sync {

            guard let (expectations, backgroundTaskId, completionHandler) = removeCurrentExpectationsWithinFlow(flowId: flowId, logger: logger) else { return }
            logger.info("Did remove the flow \(flowId.debugDescription, privacy: .public)")
            if !expectations.isEmpty {
                os_log("We are about to end the background activity associated with flow %{public}@ although there are still expectations: %{public}@", log: log, type: .error, flowId.debugDescription, Expectation.description(of: expectations))
            }
            os_log("Ending flow %{public}@ associated with background task %d", log: log, type: .info, flowId.debugDescription, backgroundTaskId.rawValue)
            
            backgroundTaskManager.endBackgroundTask(backgroundTaskId, completionHandler: completionHandler)

        }
        
    }
    
    
    private func endBackgroundActivityIfItHasNoMoreExpectationsWithinFlow(withId flowId: FlowIdentifier, numberOfExpectationsLeft: Int) {
        
        guard let delegateManager = delegateManager else { assertionFailure(); return }
        let logger = Logger(subsystem: delegateManager.logSubsystem, category: BackgroundTaskCoordinator.logCategory)
        
        var backgroundActivityHasNoMoreExpectations = false
        backgroundActivitiesQueue.sync {
            guard let (expectations, _, _) = getCurrentExpectationsWithinFlow(flowId: flowId, logger: logger) else { return }
            backgroundActivityHasNoMoreExpectations = expectations.isEmpty
        }
        if backgroundActivityHasNoMoreExpectations {
            logger.info("[\(self.debugUUID)] Will end flow \(flowId.debugDescription, privacy: .public) as it has no more expectations")
            endBackgroundActivityAssociatedWithFlow(withId: flowId)
        } else {
            logger.info("[\(self.debugUUID)] Not ending flow \(flowId.debugDescription, privacy: .public) as it still has expectations")
            logger.info("[\(self.debugUUID)] Debug \(numberOfExpectationsLeft) expectations left")
        }
        
    }
    
}

// MARK: - Receiving and processing notifications related to background activities

extension BackgroundTaskCoordinator {
    
    func observeEngineNotifications() {
        
        guard let delegateManager = delegateManager else { assertionFailure(); return }
        let logger = Logger(subsystem: delegateManager.logSubsystem, category: BackgroundTaskCoordinator.logCategory)
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            logger.fault("[\(self.debugUUID)] The notification delegate is not set")
            return
        }
        
        let debugUUID = self.debugUUID
        
        notificationCenterTokens.append(contentsOf: [

            // NewOutboxMessageAndAttachmentsToUpload
            ObvNetworkPostNotification.observeNewOutboxMessageAndAttachmentsToUpload(within: notificationDelegate) { [weak self] (messageId, attachmentIds, flowId) in
                logger.debug("[\(debugUUID)] NewOutboxMessageAndAttachmentsToUpload notification received within flow \(flowId.debugDescription, privacy: .public)")
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
                logger.debug("[\(debugUUID)] OutboxMessageWasUploaded notification received within flow \(flowId.debugDescription, privacy: .public) for messageId \(messageId.debugDescription, privacy: .public)")
                self?.updateExpectationsOfAllBackgroundActivities(expectationsToRemove: [.outboxMessageWasUploaded(messageId: messageId)])
            },
            
            // AttachmentUploadRequestIsTakenCareOf
            ObvNetworkPostNotification.observeAttachmentUploadRequestIsTakenCareOf(within: notificationDelegate) { [weak self] (attachmentId, flowId) in
                logger.debug("[\(debugUUID)] AttachmentUploadRequestIsTakenCareOf notification received within flow \(flowId.debugDescription, privacy: .public) for attachmentId \(attachmentId.debugDescription, privacy: .public)")
                self?.updateExpectationsOfAllBackgroundActivities(expectationsToRemove: [.attachmentUploadRequestIsTakenCareOfForAttachment(withId: attachmentId)])
            },
            
            // OutboxMessageAndAttachmentsDeleted
            ObvNetworkPostNotification.observeOutboxMessageAndAttachmentsDeleted(within: notificationDelegate) { [weak self] (messageId, flowId) in
                logger.debug("[\(debugUUID)] OutboxMessageAndAttachmentsDeleted notification received within flow \(flowId.debugDescription, privacy: .public) for messageId \(messageId.debugDescription, privacy: .public)")
                self?.updateExpectationsOfAllBackgroundActivities(expectationsToRemove: [.deletionOfOutboxMessage(withId: messageId)])
            },
            
            // ProtocolMessageToProcess
            ObvProtocolNotification.observeProtocolMessageToProcess(within: notificationDelegate) { [weak self] (protocolMessageId, flowId) in
                logger.debug("[\(debugUUID)] ProtocolMessageToProcess notification received within flow \(flowId.debugDescription, privacy: .public)")
                self?.updateExpectationsOfBackgroundActivityAssociatedWithFlow(withId: flowId,
                                                                               expectationsToRemove: [.protocolMessageToProcess, .uidsOfMessagesToProcess(ownedCryptoIdentity: protocolMessageId.ownedCryptoIdentity)],
                                                                               expectationsToAdd: [.endOfProcessingOfProtocolMessage(withId: protocolMessageId)])
            },
            
            // ProtocolMessageProcessed
            ObvProtocolNotification.observeProtocolMessageProcessed(within: notificationDelegate) { [weak self] (protocolMessageId, flowId) in
                logger.debug("[\(debugUUID)] ProtocolMessageProcessed notification received within flow \(flowId.debugDescription, privacy: .public)")
                self?.updateExpectationsOfAllBackgroundActivities(expectationsToRemove: [.endOfProcessingOfProtocolMessage(withId: protocolMessageId)])
            },
            
            // DeletedOutboxMessageWasCreated
            ObvNetworkPostNotification.observeDeletedOutboxMessageWasCreated(within: notificationDelegate) { [weak self] (messageId, flowId) in
                logger.debug("[\(debugUUID)] DeletedOutboxMessageWasCreated notification received within flow \(flowId.debugDescription, privacy: .public)")
                self?.updateExpectationsOfAllBackgroundActivities(expectationsToRemove: [.deletedOutboxMessageWasCreated(messageId: messageId)])
            },
            
        ])
        
    }
    
}

// MARK: - API

extension BackgroundTaskCoordinator {
    
    // Simple situations
    
    func simpleBackgroundTask(withReason reason: String, using block: @escaping (Bool) -> Void) {
        let log = OSLog(subsystem: "io.olvid.protocol", category: BackgroundTaskCoordinator.logCategory)
        let backgroundTaskId = backgroundTaskManager.beginBackgroundTask(withName: "simpleBackgroundTask with reason \(reason)", expirationHandler: nil)
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
    
    func addBackgroundActivityForPostingApplicationMessageAttachmentsWithinFlow(withFlowId flowId: FlowIdentifier, messageId: ObvMessageIdentifier, attachmentIds: [ObvAttachmentIdentifier], waitUntilMessageAndAttachmentsAreSent: Bool) {
        
        let expectations: Set<Expectation>
        if waitUntilMessageAndAttachmentsAreSent {
            expectations = Set<Expectation>([Expectation.deletedOutboxMessageWasCreated(messageId: messageId)])
        } else {
            if attachmentIds.isEmpty {
                expectations = Set<Expectation>([Expectation.outboxMessageWasUploaded(messageId: messageId)])
            } else {
                expectations = Set<Expectation>(attachmentIds.map { Expectation.attachmentUploadRequestIsTakenCareOfForAttachment(withId: $0) })
            }
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
//    func startBackgroundActivityForPostingReturnReceipt(messageId: ObvMessageIdentifier, attachmentNumber: Int?) throws -> FlowIdentifier {
//        guard let delegateManager = delegateManager else {
//            assertionFailure()
//            throw Self.makeError(message: "🧾 The delegate manager is not set")
//        }
//        let log = OSLog(subsystem: delegateManager.logSubsystem, category: BackgroundTaskCoordinator.logCategory)
//        let expectations: Set<Expectation>
//        if let attachmentNumber = attachmentNumber {
//            let attachmentId = ObvAttachmentIdentifier(messageId: messageId, attachmentNumber: attachmentNumber)
//            os_log("🧾 Starting background activity for attachmentId %{public}@", log: log, type: .debug, attachmentId.debugDescription)
//            expectations = Set([.returnReceiptWasPostedForAttachment(attachmentId: attachmentId)])
//        } else {
//            os_log("🧾 Starting background activity for messageId %{public}@", log: log, type: .debug, messageId.debugDescription)
//            expectations = Set([.returnReceiptWasPostedForMessage(messageId: messageId)])
//        }
//        return try startFlowForBackgroundTask(with: expectations)
//    }
    
    /// This method allows to stop the flow allowing to wait until a return receipt is posted. See the comment for the
    /// ``startBackgroundActivityForPostingReturnReceipt(messageId: MessageIdentifier, attachmentNumber: Int?) throws``
    /// method above.
//    func stopBackgroundActivityForPostingReturnReceipt(messageId: ObvMessageIdentifier, attachmentNumber: Int?) throws {
//        guard let delegateManager = delegateManager else {
//            assertionFailure()
//            throw Self.makeError(message: "The delegate manager is not set")
//        }
//        let log = OSLog(subsystem: delegateManager.logSubsystem, category: BackgroundTaskCoordinator.logCategory)
//        let expectationsToRemove: [Expectation]
//        if let attachmentNumber = attachmentNumber {
//            let attachmentId = ObvAttachmentIdentifier(messageId: messageId, attachmentNumber: attachmentNumber)
//            os_log("🧾 Stopping background activity for attachmentId %{public}@", log: log, type: .debug, attachmentId.debugDescription)
//            expectationsToRemove = [.returnReceiptWasPostedForAttachment(attachmentId: attachmentId)]
//        } else {
//            os_log("🧾 Stopping background activity for messageId %{public}@", log: log, type: .debug, messageId.debugDescription)
//            expectationsToRemove = [.returnReceiptWasPostedForMessage(messageId: messageId)]
//        }
//        updateExpectationsOfAllBackgroundActivities(expectationsToRemove: expectationsToRemove)
//    }
    
    // Resuming a protocol
    
    func startBackgroundActivityForStartingOrResumingProtocol() throws -> FlowIdentifier {
        let expectations = Set([Expectation.protocolMessageToProcess])
        return try startFlowForBackgroundTask(with: expectations)
    }
    
    
    // Downloading messages, downloading/pausing attachment
    
    /// Since the downloading of messages is performed using an async/await method of the network fetch manager, we do not need to set any expectations. Instead, we return
    /// a completion handler (togthether with the flow identifier) that the caller of this method is responsible for calling after when the download method returns.
    func startBackgroundActivityForDownloadingMessages(ownedIdentity: ObvCryptoIdentity) -> (flowId: FlowIdentifier, completionHandler: () -> Void) {
        let backgroundTaskIdentifier = backgroundTaskManager.beginBackgroundTask(withName: "startBackgroundActivityForDownloadingMessages", expirationHandler: nil)
        let completionHander: () -> Void = { [weak self] in
            self?.backgroundTaskManager.endBackgroundTask(backgroundTaskIdentifier, completionHandler: nil)
        }
        let flowId = FlowIdentifier()
        return (flowId, completionHander)
    }
    

    // Deleting a message or an attachment
    
    /// Since the marking a message for deletion is performed using an async/await method of the network fetch manager, we do not need to set any expectations. Instead, we return
    /// a completion handler (togthether with the flow identifier) that the caller of this method is responsible for calling after when the fetch manager's method returns.
    func startBackgroundActivityForMarkingMessageForDeletionAndProcessingAttachments(messageId: ObvMessageIdentifier) -> (flowId: FlowIdentifier, completionHandler: () -> Void) {
        let backgroundTaskIdentifier = backgroundTaskManager.beginBackgroundTask(withName: "startBackgroundActivityForMarkingMessageForDeletionAndProcessingAttachments", expirationHandler: nil)
        let completionHander: () -> Void = { [weak self] in
            self?.backgroundTaskManager.endBackgroundTask(backgroundTaskIdentifier, completionHandler: nil)
        }
        let flowId = FlowIdentifier()
        return (flowId, completionHander)
    }
    

    /// Since the marking an attachment for deletion is performed using an async/await method of the network fetch manager, we do not need to set any expectations. Instead, we return
    /// a completion handler (togthether with the flow identifier) that the caller of this method is responsible for calling after when the fetch manager's method returns.
    func startBackgroundActivityForMarkingAttachmentForDeletion(attachmentId: ObvAttachmentIdentifier) -> (flowId: FlowIdentifier, completionHandler: () -> Void) {
        let backgroundTaskIdentifier = backgroundTaskManager.beginBackgroundTask(withName: "startBackgroundActivityForMarkingAttachmentForDeletion", expirationHandler: nil)
        let completionHander: () -> Void = { [weak self] in
            self?.backgroundTaskManager.endBackgroundTask(backgroundTaskIdentifier, completionHandler: nil)
        }
        let flowId = FlowIdentifier()
        return (flowId, completionHander)
    }
    
    
    func endFlow(flowId: FlowIdentifier) {
        endBackgroundActivityAssociatedWithFlow(withId: flowId)
    }
    
}
