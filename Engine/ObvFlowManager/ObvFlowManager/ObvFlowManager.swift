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


public final class ObvFlowManager: ObvFlowDelegate {
        
    // MARK: Instance variables
    
    public var logSubsystem: String { return delegateManager.logSubsystem }
    
    public func prependLogSubsystem(with prefix: String) {
        delegateManager.prependLogSubsystem(with: prefix)
    }
    
    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {}

    lazy private var log = OSLog(subsystem: logSubsystem, category: "ObvFlowManagerImplementation")
    
    let prng: PRNGService
    
    private static func makeError(message: String) -> Error {
        NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }

    /// Strong reference to the delegate manager, which keeps strong references to all external and internal delegate requirements.
    let delegateManager: ObvFlowDelegateManager
    
    // MARK: Initialisers
    
    public init(backgroundTaskManager: ObvBackgroundTaskManager, prng: PRNGService) {
        self.prng = prng
        let backgroundTaskCoordinator = BackgroundTaskCoordinator(backgroundTaskManager: backgroundTaskManager)
        let remoteNotificationCoordinator = RemoteNotificationCoordinator()
        self.delegateManager = ObvFlowDelegateManager(simpleBackgroundTaskDelegate: backgroundTaskCoordinator,
                                                      backgroundTaskDelegate: backgroundTaskCoordinator,
                                                      remoteNotificationDelegate: remoteNotificationCoordinator)
        backgroundTaskCoordinator.delegateManager = delegateManager
        remoteNotificationCoordinator.delegateManager = delegateManager
    }
    
    public init(prng: PRNGService) {
        self.prng = prng
        let backgroundTaskCoordinator = BackgroundTaskCoordinator()
        let remoteNotificationCoordinator = RemoteNotificationCoordinator()
        self.delegateManager = ObvFlowDelegateManager(simpleBackgroundTaskDelegate: backgroundTaskCoordinator,
                                                      backgroundTaskDelegate: backgroundTaskCoordinator,
                                                      remoteNotificationDelegate: remoteNotificationCoordinator)
        remoteNotificationCoordinator.delegateManager = delegateManager
        backgroundTaskCoordinator.delegateManager = delegateManager
    }

}


// MARK: - Implementing ObvFlowDelegate

extension ObvFlowManager {
    
    // MARK: - Background Tasks
    
    // Handling simple situations
    
    public func simpleBackgroundTask(withReason reason: String, using block: @escaping (Bool) -> Void) {
        delegateManager.simpleBackgroundTaskDelegate.simpleBackgroundTask(withReason: reason, using: block)
    }
    
    // Posting message and attachments
    
    public func startNewFlow(completionHandler: (() -> Void)?) throws -> FlowIdentifier {
        guard let backgroundTaskDelegate = delegateManager.backgroundTaskDelegate else {
            throw Self.makeError(message: "The backgroundTaskDelegate is not set")
        }
        return try backgroundTaskDelegate.startNewFlow(completionHandler: completionHandler)
    }
    
    public func addBackgroundActivityForPostingApplicationMessageAttachmentsWithinFlow(withFlowId flowId: FlowIdentifier, messageId: MessageIdentifier, attachmentIds: [AttachmentIdentifier]) throws {
        guard let backgroundTaskDelegate = delegateManager.backgroundTaskDelegate else {
            throw Self.makeError(message: "The backgroundTaskDelegate is not set")
        }
        backgroundTaskDelegate.addBackgroundActivityForPostingApplicationMessageAttachmentsWithinFlow(withFlowId: flowId, messageId: messageId, attachmentIds: attachmentIds)
    }
    

    // Resuming a protocol
    
    public func startBackgroundActivityForStartingOrResumingProtocol() throws -> FlowIdentifier {
        guard let backgroundTaskDelegate = delegateManager.backgroundTaskDelegate else {
            throw Self.makeError(message: "The backgroundTaskDelegate is not set")
        }
        return try backgroundTaskDelegate.startBackgroundActivityForStartingOrResumingProtocol()
    }
    

    // Posting a return receipt (for message or an attachment)

    public func startBackgroundActivityForPostingReturnReceipt(messageId: MessageIdentifier, attachmentNumber: Int?) throws -> FlowIdentifier {
        guard let backgroundTaskDelegate = delegateManager.backgroundTaskDelegate else {
            throw Self.makeError(message: "The backgroundTaskDelegate is not set")
        }
        return try backgroundTaskDelegate.startBackgroundActivityForPostingReturnReceipt(messageId: messageId, attachmentNumber: attachmentNumber)
    }
    
    public func stopBackgroundActivityForPostingReturnReceipt(messageId: MessageIdentifier, attachmentNumber: Int?) throws {
        guard let backgroundTaskDelegate = delegateManager.backgroundTaskDelegate else {
            throw Self.makeError(message: "The backgroundTaskDelegate is not set")
        }
        try backgroundTaskDelegate.stopBackgroundActivityForPostingReturnReceipt(messageId: messageId, attachmentNumber: attachmentNumber)
    }
    
    // Downloading messages, downloading/pausing attachment
    
    public func startBackgroundActivityForDownloadingMessages(ownedIdentity: ObvCryptoIdentity) -> FlowIdentifier? {
        return self.delegateManager.backgroundTaskDelegate?.startBackgroundActivityForDownloadingMessages(ownedIdentity: ownedIdentity)
    }
    
    
    // Deleting a message or an attachment
    
    public func startBackgroundActivityForDeletingAMessage(messageId: MessageIdentifier) -> FlowIdentifier? {
        return self.delegateManager.backgroundTaskDelegate?.startBackgroundActivityForDeletingAMessage(messageId: messageId)
    }
    
    
    public func startBackgroundActivityForDeletingAnAttachment(attachmentId: AttachmentIdentifier) -> FlowIdentifier? {
        return self.delegateManager.backgroundTaskDelegate?.startBackgroundActivityForDeletingAnAttachment(attachmentId: attachmentId)
    }
    
    
    // Handling the completion handler received together with a remote push notification
    
    public func startBackgroundActivityForHandlingRemoteNotification(ownedCryptoIds: Set<ObvCryptoIdentity>, withCompletionHandler handler: @escaping (UIBackgroundFetchResult) -> Void) throws -> FlowIdentifier {
        try self.delegateManager.remoteNotificationDelegate.startBackgroundActivityForHandlingRemoteNotification(ownedCryptoIds: ownedCryptoIds, withCompletionHandler: handler)
    }

    public func attachmentDownloadDecisionHasBeenTaken(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier) {
        self.delegateManager.remoteNotificationDelegate.attachmentDownloadDecisionHasBeenTaken(attachmentId: attachmentId, flowId: flowId)
    }

}


// MARK: - Implementing ObvManager

extension ObvFlowManager {
    
    public var requiredDelegates: [ObvEngineDelegateType] {
        return [ObvEngineDelegateType.ObvNotificationDelegate]
    }
    
    public func fulfill(requiredDelegate delegate: AnyObject, forDelegateType delegateType: ObvEngineDelegateType) throws {
        switch delegateType {
        case .ObvNotificationDelegate:
            guard let delegate = delegate as? ObvNotificationDelegate else { throw Self.makeError(message: "The ObvNotificationDelegate is not set") }
            delegateManager.notificationDelegate = delegate
        default:
            throw Self.makeError(message: "Unexpected delegate type")
        }
    }
    
    static public var bundleIdentifier: String { return "io.olvid.ObvFlowManager" }
    static public var dataModelNames: [String] { return [] }
    
    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {}
}
