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
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils


final class BackgroundTaskCoordinator: SimpleBackgroundTaskDelegate, BackgroundTaskDelegate {
    
    // MARK: Instance variables
    
    private static let logCategory = "BackgroundTaskCoordinator"

    weak var delegateManager: ObvFlowDelegateManager?
    
    private var notificationCenterTokens = [NSObjectProtocol]()
    
    private var _currentExpectationsWithinFlow = [FlowIdentifier: (expectations: Set<Expectation>, backgroundTaskId: UIBackgroundTaskIdentifier, completionHander: (() -> Void)?)]()
    private let backgroundActivitiesQueue = DispatchQueue(label: "BackgroundTaskCoordinator.CurrentExpectationsWithinFlowQueue")
    private let internalQueue = OperationQueue()
    
    weak var uiApplication: UIApplication?
    private let backgroundActivityEmulator = BackgroundActivityEmulator()
    private var expiringActivityPerformer: ExpiringActivityPerformer {
        return uiApplication ?? backgroundActivityEmulator
    }
    
    init(uiApplication: UIApplication) {
        self.uiApplication = uiApplication
    }
    
    init() {
        self.uiApplication = nil
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
    
    
    private func startFlowForBackgroundTask(with expectations: Set<Expectation>, completionHandler: (() -> Void)? = nil) -> FlowIdentifier? {
        
        guard let delegateManager = delegateManager else { return nil }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: BackgroundTaskCoordinator.logCategory)
        
        let flowId = FlowIdentifier()
        
        backgroundActivitiesQueue.sync {
                        
            let backgroundTaskId = expiringActivityPerformer.beginBackgroundTask { [weak self] in
                // End the activity if time expires.
                guard let _self = self else { return }
                os_log("Ending background activity associated with flow %{public}@ because time expired", log: log, type: .error, flowId.debugDescription)
                _self.endBackgroundActivityAssociatedWithFlow(withId: flowId)
            }
            
            _currentExpectationsWithinFlow[flowId] = (expectations, backgroundTaskId, completionHandler)
            
            os_log("Starting flow %{public}@ associated with background task %d", log: log, type: .info, flowId.debugDescription, backgroundTaskId.rawValue)
            os_log("Initial expectations of flow %{public}@: %{public}@", log: log, type: .info, flowId.debugDescription, Expectation.description(of: expectations))
            
        }
        
        return flowId
    }

    
    private func updateExpectationsOfBackgroundActivityAssociatedWithFlow(withId flowId: FlowIdentifier, expectationsToRemove: [Expectation], expectationsToAdd: [Expectation]) {
        
        guard let delegateManager = delegateManager else { return }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: BackgroundTaskCoordinator.logCategory)
        
        backgroundActivitiesQueue.sync {
            
            // Update the flow expectations
            
            do {
                guard let (expectations, backgroundTaskId, completionHandler) = _currentExpectationsWithinFlow[flowId] else { return }
                
                os_log("Expectations of background activity associated with flow %{public}@ before update: %{public}@", log: log, type: .debug, flowId.debugDescription, Expectation.description(of: expectations))
                let newExpectations = expectations.subtracting(expectationsToRemove).union(expectationsToAdd)
                os_log("Expectations of background activity associated with flowId %{public}@ after update: %{public}@", log: log, type: .debug, flowId.debugDescription, Expectation.description(of: newExpectations))

                _currentExpectationsWithinFlow[flowId] = (newExpectations, backgroundTaskId, completionHandler)

            }
            
        }
        
        self.endBackgroundActivityIfItHasNoMoreExpectationsWithinFlow(withId: flowId)
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
            
            expiringActivityPerformer.endBackgroundTask(backgroundTaskId, completionHandler: completionHandler)
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
        
        // PoWChallengeMethodWasRequested
        do {
            let NotificationType = ObvNetworkPostNotification.PoWChallengeMethodWasRequested.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (messageId, flowId) = NotificationType.parse(notification) else { return }
                os_log("%{public}@ notification received within flow %{public}@", log: log, type: .debug, NotificationType.name.rawValue, flowId.debugDescription)
                
                self?.updateExpectationsOfBackgroundActivityAssociatedWithFlow(withId: flowId,
                                                                               expectationsToRemove: [.powWasRequestedToTheServer(messageId: messageId)],
                                                                               expectationsToAdd: [])
                
            }
            notificationCenterTokens.append(token)
        }

        
        // NewOutboxMessageAndAttachmentsToUpload
        do {
            let NotificationType = ObvNetworkPostNotification.NewOutboxMessageAndAttachmentsToUpload.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (messageId, attachmentIds, flowId) = NotificationType.parse(notification) else { return }
                os_log("%{public}@ notification received within flow %{public}@", log: log, type: .debug, NotificationType.name.rawValue, flowId.debugDescription)
                
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
                
                
            }
            notificationCenterTokens.append(token)
        }
        
        
        // OutboxMessageWasUploaded
        notificationCenterTokens.append(ObvNetworkPostNotificationNew.observeOutboxMessageWasUploaded(within: notificationDelegate, queue: internalQueue) { [weak self] (messageId, _, _, _, flowId) in
            os_log("%{public}@ notification received within flow %{public}@", log: log, type: .debug, ObvNetworkPostNotificationNew.outboxMessageWasUploadedName.rawValue, flowId.debugDescription)
            self?.updateExpectationsOfBackgroundActivityAssociatedWithFlow(withId: flowId,
                                                                           expectationsToRemove: [.outboxMessageWasUploaded(messageId: messageId)],
                                                                           expectationsToAdd: [])
        })
        
        
        // AttachmentsUploadsRequestIsTakenCareOf
        do {
            let NotificationType = ObvNetworkPostNotification.AttachmentUploadRequestIsTakenCareOf.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (attachmentId, flowId) = NotificationType.parse(notification) else { return }
                os_log("%{public}@ notification received within flow %{public}@", log: log, type: .debug, NotificationType.name.rawValue, flowId.debugDescription)
                
                self?.updateExpectationsOfBackgroundActivityAssociatedWithFlow(withId: flowId,
                                                                               expectationsToRemove: [.attachmentUploadRequestIsTakenCareOfForAttachment(withId: attachmentId)],
                                                                               expectationsToAdd: [])
            }
            notificationCenterTokens.append(token)
        }

        
        // OutboxMessageAndAttachmentsDeleted
        do {
            let NotificationType = ObvNetworkPostNotification.OutboxMessageAndAttachmentsDeleted.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (messageId, flowId) = NotificationType.parse(notification) else { return }
                os_log("%{public}@ notification received within flow %{public}@", log: log, type: .debug, NotificationType.name.rawValue, flowId.debugDescription)
                
                self?.updateExpectationsOfBackgroundActivityAssociatedWithFlow(withId: flowId,
                                                                               expectationsToRemove: [.deletionOfOutboxMessage(withId: messageId)],
                                                                               expectationsToAdd: [])
                
            }
            notificationCenterTokens.append(token)
        }
        
        
        // ProtocolMessageToProcess
        do {
            let NotificationType = ObvProtocolNotification.ProtocolMessageToProcess.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (protocolMessageId, flowId) = NotificationType.parse(notification) else { return }
                os_log("%{public}@ notification received within flow %{public}@", log: log, type: .debug, NotificationType.name.rawValue, flowId.debugDescription)
                
                self?.updateExpectationsOfBackgroundActivityAssociatedWithFlow(withId: flowId,
                                                                               expectationsToRemove: [.protocolMessageToProcess, .uidsOfMessagesThatWillBeDownloaded],
                                                                               expectationsToAdd: [.processingOfProtocolMessage(withId: protocolMessageId)])
                
            }
            notificationCenterTokens.append(token)
        }
        
        
        // ProtocolMessageProcessed
        do {
            let NotificationType = ObvProtocolNotification.ProtocolMessageProcessed.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (protocolMessageId, flowId) = NotificationType.parse(notification) else { return }
                os_log("%{public}@ notification received within flow %{public}@", log: log, type: .debug, NotificationType.name.rawValue, flowId.debugDescription)
                
                self?.updateExpectationsOfBackgroundActivityAssociatedWithFlow(withId: flowId,
                                                                               expectationsToRemove: [.processingOfProtocolMessage(withId: protocolMessageId)],
                                                                               expectationsToAdd: [])
                
            }
            notificationCenterTokens.append(token)
        }
        
        
    }
    
}

// MARK: - API

extension BackgroundTaskCoordinator {
    
    // Simple situations
    
    func simpleBackgroundTask(withReason reason: String, using block: @escaping (Bool) -> Void) {
        let log = OSLog(subsystem: "io.olvid.protocol", category: BackgroundTaskCoordinator.logCategory)
        let backgroundTaskId = expiringActivityPerformer.beginBackgroundTask(expirationHandler: nil)
        os_log("Starting simple background task %d with reason %{public}@", log: log, type: .debug, backgroundTaskId.rawValue, reason)
        block(false)
        os_log("Ending simple background task %d with reason %{public}@", log: log, type: .debug, backgroundTaskId.rawValue, reason)
        expiringActivityPerformer.endBackgroundTask(backgroundTaskId, completionHandler: nil)
    }

    // Posting message and attachments
    
    /// This methods starts a background activity for posting an application message with (or without) attachments. Optionally, a completion handler can be specified. It is called when the flow ends. Optionally, a maximum time interval can be specified. In that case, the flow starts a timer as soon as essentials events occured and ends the flow after this interval
    /// (if the flow has not ended yet). Note that ending the flow always performs a call to the completion handler, even if the flow was ended because the time exceed the maximum time interval.
    /// This mechanism is used, in particular, in order to automatically  dismiss the share extension after a certain time interval, in case where there is zero bandwith (in which case, it is not possible to meet all the expectations of the flow).
    /// - Parameter messageId: The message identifier.
    /// - Parameter attachmentIds: The array of all the attachment identifiers.
    /// - Parameter maxTimeIntervalAndHandler: The time interval after which the flow should be ended. The time starts *after* essential expections have been met. The associated (optional) handler is fired right after the timer starts.
    /// - Parameter completionHandler: The completion handler.
    func startBackgroundActivityForPostingApplicationMessageAttachments(messageId: MessageIdentifier, attachmentIds: [AttachmentIdentifier], completionHandler: (() -> Void)? = nil) -> FlowIdentifier? {
        
        // In case the message has no attachment, this flow ends when the outbox message was uploaded. In there are attachments, the flow ends when all attachments have been uploaded.
        let expectations: Set<Expectation>
        if attachmentIds.isEmpty {
            expectations = Set<Expectation>([Expectation.outboxMessageWasUploaded(messageId: messageId)])
        } else {
            expectations = Set<Expectation>(attachmentIds.map { Expectation.attachmentUploadRequestIsTakenCareOfForAttachment(withId: $0) })
        }
        let flowId = startFlowForBackgroundTask(with: expectations, completionHandler: completionHandler)
        
        return flowId
    }
    
    
    func startBackgroundActivityForStoringBackgroundURLSessionCompletionHandler() -> FlowIdentifier? {
        return FlowIdentifier()
    }

    // Resuming a protocol
    
    func startBackgroundActivityForStartingOrResumingProtocol() -> FlowIdentifier? {
        let expectations = Set([Expectation.protocolMessageToProcess])
        return startFlowForBackgroundTask(with: expectations)
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
