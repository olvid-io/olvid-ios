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
    
    
    private func startFlowForBackgroundTask(with expectations: Set<Expectation>, completionHandler: (() -> Void)? = nil) throws -> FlowIdentifier {
        
        guard let delegateManager = delegateManager else {
            throw Self.makeError(message: "The delegate manager is not set")
        }
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
                
                os_log("Expectations of background activity associated with flow %{public}@ before update: %{public}@", log: log, type: .info, flowId.debugDescription, Expectation.description(of: expectations))
                let newExpectations = expectations.subtracting(expectationsToRemove).union(expectationsToAdd)
                os_log("Expectations of background activity associated with flowId %{public}@ after update: %{public}@", log: log, type: .info, flowId.debugDescription, Expectation.description(of: newExpectations))

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
