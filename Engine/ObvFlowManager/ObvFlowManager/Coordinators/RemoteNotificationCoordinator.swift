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
import ObvMetaManager
import ObvCrypto
import ObvTypes
import OlvidUtils


final class RemoteNotificationCoordinator: RemoteNotificationDelegate {

    // MARK: Instance variables

    private static let logCategory = "RemoteNotificationCoordinator"

    weak var delegateManager: ObvFlowDelegateManager?

    private var notificationCenterTokens = [NSObjectProtocol]()

    private typealias CompletionHandler = (UIBackgroundFetchResult) -> Void
    
    private var _currentExpectationsWithinFlow = [FlowIdentifier: (expectations: Set<Expectation>, completionHandler: CompletionHandler, timer: Timer)]()
    private let backgroundActivitiesQueue = DispatchQueue(label: "RemoteNotificationCoordinator.backgroundActivitiesQueue")
    private let backgroundQueueForExpiringTimers = DispatchQueue(label: "RemoteNotificationCoordinator.backgroundQueueForExpiringTimers")
    private let queueForTimerBlocks = DispatchQueue(label: "RemoteNotificationCoordinator queue for timer blocks", qos: .background)

    // MARK: - Init/Deinit

    deinit {
        if let notificationDelegate = delegateManager?.notificationDelegate {
            notificationCenterTokens.forEach {
                notificationDelegate.removeObserver($0)
            }
        }
    }

}


// MARK: - Synchronized access to the expectations within flows

extension RemoteNotificationCoordinator {

    private func startFlow(completionHandler: @escaping CompletionHandler) -> FlowIdentifier? {
        
        guard let delegateManager = delegateManager else { return nil }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: RemoteNotificationCoordinator.logCategory)
        
        let flowId = FlowIdentifier()
        
        let initalExpectations = Set([Expectation.uidsOfMessagesThatWillBeDownloaded])
        
        backgroundActivitiesQueue.sync {
            
            os_log("🌊 Setting a timer for background activity %{public}@", log: log, type: .debug, flowId.debugDescription)
            
            let timer = Timer(timeInterval: ObvConstants.maxAllowedTimeForProcessingReceivedRemoteNotification, repeats: false) { [weak self] timer in
                self?.queueForTimerBlocks.async {
                    os_log("🌊 Firing timer within flow %{public}@", log: log, type: .error, flowId.debugDescription)
                    self?.backgroundActivitiesQueue.sync {
                        if let expectations = self?._currentExpectationsWithinFlow[flowId]?.expectations {
                            os_log("🌊🌊 Calling endBackgroundActivity for flow %{public}@ as the timer expired. These expectations were not met: %{public}@", log: log, type: .error, flowId.debugDescription, Expectation.description(of: expectations))
                        } else {
                            os_log("🌊🌊 Calling endBackgroundActivity for flow %{public}@ as the timer expired. No expectations were found, which probably means this flow was not initiated du to a remove notification.", log: log, type: .error, flowId.debugDescription)
                        }
                    }
                    self?.endFlow(withId: flowId, with: .failed)
                }
            }

            RunLoop.main.add(timer, forMode: .default)
                        
            _currentExpectationsWithinFlow[flowId] = (initalExpectations, completionHandler, timer)
            
        }
        
        os_log("🌊 The timer was set withinth flow %{public}@", log: log, type: .debug, flowId.debugDescription)
        
        
        os_log("🌊🌊 Starting flow %{public}@", log: log, type: .info, flowId.debugDescription)
        os_log("🌊 Initial expectations of flow %{public}@: %{public}@", log: log, type: .debug, flowId.debugDescription, Expectation.description(of: initalExpectations))

        return flowId
        
    }


    private func updateExpectationsOfFlow(withId flowId: FlowIdentifier, expectationsToRemove: [Expectation], expectationsToAdd: [Expectation]) {
        
        guard let delegateManager = delegateManager else { return }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: RemoteNotificationCoordinator.logCategory)

        backgroundActivitiesQueue.sync {
            
            guard let (expectations, completionHandler, timer) = _currentExpectationsWithinFlow[flowId] else {
                os_log("🌊 Could not find any expectation for flow %{public}@", log: log, type: .info, flowId.debugDescription)
                return
            }
            
            os_log("🌊 Expectations of flow %{public}@ before update: %{public}@", log: log, type: .info, flowId.debugDescription, Expectation.description(of: expectations))
            let newExpectations = expectations.subtracting(expectationsToRemove).union(expectationsToAdd)
            os_log("🌊 Expectations of flow %{public}@ after update : %{public}@", log: log, type: .info, flowId.debugDescription, Expectation.description(of: newExpectations))
            
            _currentExpectationsWithinFlow[flowId] = (newExpectations, completionHandler, timer)
            
        }
        
        endFlowIfItHasNoMoreExpectations(flowId: flowId, result: .newData)

    }


    private func endFlow(withId flowId: FlowIdentifier, with result: UIBackgroundFetchResult) {
                
        guard let delegateManager = delegateManager else { return }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: RemoteNotificationCoordinator.logCategory)
        
        os_log("🌊 Call to endFlow for flow %{public}@", log: log, type: .debug, flowId.debugDescription)

        var completionHandler: ((UIBackgroundFetchResult) -> Void)?
        backgroundActivitiesQueue.sync {
            guard let (expectations, _completionHandler, timer) = _currentExpectationsWithinFlow.removeValue(forKey: flowId) else { return }
            os_log("🌊 Invalidating timer within flow %{public}@", log: log, type: .info, flowId.debugDescription)
            timer.invalidate()
            completionHandler = _completionHandler
            if !expectations.isEmpty {
                os_log("🌊🌊 We are about to end the flow %{public}@ although there are still expectations: %{public}@", log: log, type: .error, flowId.debugDescription, Expectation.description(of: expectations))
            }
        }
        
        if let completionHandler = completionHandler {
            let logType: OSLogType
            switch result {
            case .failed:
                logType = .fault
            case .noData:
                logType = .error
            case .newData:
                logType = .info
            @unknown default:
                logType = .error
            }
            os_log("🌊🌊 Calling the completion handler of the flow %{public}@ with fetch result: %{public}@", log: log, type: logType, flowId.debugDescription, result.debugDescription)
            completionHandler(result)
        } else {
            os_log("🌊🌊 Since the completion handler is nil, we do *not* call it with fetch result: %{public}@", log: log, type: .fault, result.debugDescription)
        }
        
    }


    private func endFlowIfItHasNoMoreExpectations(flowId: FlowIdentifier, result: UIBackgroundFetchResult) {
        
        var backgroundActivityHasNoMoreExpectations = false
        backgroundActivitiesQueue.sync {
            guard let (expectations, _, _) = _currentExpectationsWithinFlow[flowId] else { return }
            backgroundActivityHasNoMoreExpectations = expectations.isEmpty
        }
        
        if backgroundActivityHasNoMoreExpectations {
            endFlow(withId: flowId, with: result)
        }
        
    }

}


// MARK: - Receiving and processing notifications related to background activities

extension RemoteNotificationCoordinator {

    func observeEngineNotifications() {

        guard let delegateManager = delegateManager else { return }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: RemoteNotificationCoordinator.logCategory)

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }
        
        
        // NewOutboxMessageAndAttachmentsToUpload
        do {
            let NotificationType = ObvNetworkPostNotification.NewOutboxMessageAndAttachmentsToUpload.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (messageId, attachmentIds, flowId) = NotificationType.parse(notification) else { return }
                os_log("%{public}@ notification received within flow %{public}@", log: log, type: .debug, NotificationType.name.rawValue, flowId.debugDescription)
                
                if attachmentIds.isEmpty {
                    self?.updateExpectationsOfFlow(withId: flowId,
                                                   expectationsToRemove: [],
                                                   expectationsToAdd: [.deletionOfOutboxMessage(withId: messageId)])
                } else {
                    let expectationsToAdd = attachmentIds.map { Expectation.attachmentUploadRequestIsTakenCareOfForAttachment(withId: $0) }
                    self?.updateExpectationsOfFlow(withId: flowId,
                                                   expectationsToRemove: [],
                                                   expectationsToAdd: expectationsToAdd)
                }
                
                
            }
            notificationCenterTokens.append(token)
        }

        
        // NoInboxMessageToProcess
        do {
            notificationCenterTokens.append(ObvNetworkFetchNotificationNew.observeNoInboxMessageToProcess(within: notificationDelegate) { [weak self] (flowId) in
                self?.updateExpectationsOfFlow(withId: flowId,
                                               expectationsToRemove: [.uidsOfMessagesThatWillBeDownloaded],
                                               expectationsToAdd: [])

            })
        }
        
        
        // NewInboxMessageToProcess
        do {
            notificationCenterTokens.append(ObvNetworkFetchNotificationNew.observeNewInboxMessageToProcess(within: notificationDelegate, block: { [weak self] (messageId, _, flowId) in
                self?.updateExpectationsOfFlow(withId: flowId,
                                               expectationsToRemove: [.uidsOfMessagesThatWillBeDownloaded],
                                               expectationsToAdd: [.networkReceivedMessageWasProcessed(messageId: messageId)])
            }))            
        }

        
        // NetworkReceivedMessageWasProcessed
        // At the time we receive this notification, we expect the expectations to contain either .processingOfProtocolMessage or .decisionToDownloadAttachmentOrNotHasBeenTaken
        do {
            let NotificationType = ObvChannelNotification.NetworkReceivedMessageWasProcessed.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                os_log("Received a notification: %{public}@", log: log, type: .info, NotificationType.name.rawValue)
                guard let (messageId, flowId) = NotificationType.parse(notification) else { return }
                self?.updateExpectationsOfFlow(withId: flowId,
                                               expectationsToRemove: [.networkReceivedMessageWasProcessed(messageId: messageId)],
                                               expectationsToAdd: [])
            }
            notificationCenterTokens.append(token)
        }
        
        
        // ApplicationMessageDecrypted
        do {
            notificationCenterTokens.append(ObvNetworkFetchNotificationNew.observeApplicationMessageDecrypted(within: notificationDelegate) { [weak self] (messageId, attachmentIds, hasEncryptedExtendedMessagePayload, flowId) in
                os_log("Received a notification: ApplicationMessageDecrypted messageId: %{public}@", log: log, type: .info, messageId.debugDescription)

                var expectationsToAdd = [Expectation]()
                if hasEncryptedExtendedMessagePayload {
                    expectationsToAdd.append(.extendedMessagePayloadWasDownloaded(messageId: messageId))
                }
                if !attachmentIds.isEmpty {
                    expectationsToAdd = attachmentIds.map { Expectation.decisionToDownloadAttachmentOrNotHasBeenTaken(attachmentId: $0) }
                }
                if expectationsToAdd.isEmpty {
                    expectationsToAdd.append(.deletionOfInboxMessage(withId: messageId))
                }
                self?.updateExpectationsOfFlow(withId: flowId,
                                               expectationsToRemove: [.applicationMessageDecrypted(messageId: messageId), .uidsOfMessagesThatWillBeDownloaded],
                                               expectationsToAdd: expectationsToAdd)
            })
        }
        
        
        // InboxMessageDeletedFromServerAndInboxesWithinBackgroundActivity
        do {
            let NotificationType = ObvNetworkFetchNotification.InboxMessageDeletedFromServerAndInboxes.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (messageId, flowId) = NotificationType.parse(notification) else { return }
                os_log("Received a notification: %{public}@ for messageId %{public}@", log: log, type: .info, NotificationType.name.rawValue, messageId.debugDescription)

                self?.updateExpectationsOfFlow(withId: flowId,
                                               expectationsToRemove: [.deletionOfInboxMessage(withId: messageId)],
                                               expectationsToAdd: [])
                
            }
            notificationCenterTokens.append(token)
        }

        
        // ProtocolMessageToProcessWithinBackgroundActivity
        do {
            let NotificationType = ObvProtocolNotification.ProtocolMessageToProcess.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                os_log("Received a notification: %{public}@", log: log, type: .info, NotificationType.name.rawValue)
                guard let (protocolMessageId, flowId) = NotificationType.parse(notification) else { return }
                
                self?.updateExpectationsOfFlow(withId: flowId,
                                               expectationsToRemove: [.uidsOfMessagesThatWillBeDownloaded],
                                               expectationsToAdd: [.processingOfProtocolMessage(withId: protocolMessageId)])
                
            }
            notificationCenterTokens.append(token)
        }
        
        
        // ProtocolMessageProcessedWithinBackgroundActivity
        do {
            let NotificationType = ObvProtocolNotification.ProtocolMessageProcessed.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                os_log("Received a notification: %{public}@", log: log, type: .info, NotificationType.name.rawValue)
                guard let (protocolMessageId, flowId) = NotificationType.parse(notification) else { return }
                
                self?.updateExpectationsOfFlow(withId: flowId,
                                               expectationsToRemove: [.processingOfProtocolMessage(withId: protocolMessageId)],
                                               expectationsToAdd: [])
                
            }
            notificationCenterTokens.append(token)
        }
        
        
        // OutboxMessageAndAttachmentsDeleted
        do {
            let NotificationType = ObvNetworkPostNotification.OutboxMessageAndAttachmentsDeleted.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                os_log("Received a notification: %{public}@", log: log, type: .info, NotificationType.name.rawValue)
                guard let (messageId, flowId) = NotificationType.parse(notification) else { return }
                
                self?.updateExpectationsOfFlow(withId: flowId,
                                               expectationsToRemove: [.deletionOfOutboxMessage(withId: messageId)],
                                               expectationsToAdd: [])
                
            }
            notificationCenterTokens.append(token)
        }
        
        
        // AttachmentsUploadsRequestIsTakenCareOf
        do {
            let NotificationType = ObvNetworkPostNotification.AttachmentUploadRequestIsTakenCareOf.self
            let token = notificationDelegate.addObserver(forName: NotificationType.name) { [weak self] (notification) in
                guard let (attachmentId, flowId) = NotificationType.parse(notification) else { return }
                os_log("%{public}@ notification received within flow %{public}@", log: log, type: .debug, NotificationType.name.rawValue, flowId.debugDescription)
                
                self?.updateExpectationsOfFlow(withId: flowId,
                                               expectationsToRemove: [.attachmentUploadRequestIsTakenCareOfForAttachment(withId: attachmentId)],
                                               expectationsToAdd: [])
            }
            notificationCenterTokens.append(token)
        }
        
        
        // InboxAttachmentWasTakenCareOf
        do {
            let token = ObvNetworkFetchNotificationNew.observeInboxAttachmentWasTakenCareOf(within: notificationDelegate) { [weak self] (attachmentId, flowId) in
                self?.attachmentDownloadDecisionHasBeenTaken(attachmentId: attachmentId, flowId: flowId)
            }
            notificationCenterTokens.append(token)
        }
        
        
        // DownloadingMessageExtendedPayloadFailed
        notificationCenterTokens.append(ObvNetworkFetchNotificationNew.observeDownloadingMessageExtendedPayloadFailed(within: notificationDelegate) { [weak self] (messageId, flowId) in
            self?.updateExpectationsOfFlow(withId: flowId,
                                           expectationsToRemove: [.extendedMessagePayloadWasDownloaded(messageId: messageId)],
                                           expectationsToAdd: [])
        })

        // DownloadingMessageExtendedPayloadWasPerformed
        notificationCenterTokens.append(ObvNetworkFetchNotificationNew.observeDownloadingMessageExtendedPayloadWasPerformed(within: notificationDelegate) { [weak self] (messageId, _, flowId) in
            self?.updateExpectationsOfFlow(withId: flowId,
                                           expectationsToRemove: [.extendedMessagePayloadWasDownloaded(messageId: messageId)],
                                           expectationsToAdd: [])
        })

    }
    
}


extension RemoteNotificationCoordinator {

    func startBackgroundActivityForHandlingRemoteNotification(withCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) -> FlowIdentifier? {
        return self.startFlow(completionHandler: completionHandler)
    }
    
    public func attachmentDownloadDecisionHasBeenTaken(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else { return }
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: RemoteNotificationCoordinator.logCategory)
        
        os_log("🌊 attachmentDownloadDecisionHasBeenTaken was called within flow %{public}@", log: log, type: .info, flowId.debugDescription)
        
        self.updateExpectationsOfFlow(withId: flowId,
                                      expectationsToRemove: [Expectation.decisionToDownloadAttachmentOrNotHasBeenTaken(attachmentId: attachmentId)],
                                      expectationsToAdd: [])
        
    }
}

extension UIBackgroundFetchResult: CustomDebugStringConvertible {
    
    public var debugDescription: String {
        switch self {
        case .failed:
            return ".failed"
        case .noData:
            return ".noData"
        case .newData:
            return ".newData"
        @unknown default:
            return "unknown default"
        }
    }


}
