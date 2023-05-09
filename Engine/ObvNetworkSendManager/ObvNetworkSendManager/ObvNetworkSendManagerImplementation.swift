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
import OlvidUtils
import ObvTypes
import ObvCrypto
import CoreData
import ObvMetaManager

public final class ObvNetworkSendManagerImplementation: ObvNetworkPostDelegate, ObvErrorMaker {
    
    public static let errorDomain = "ObvNetworkSendManagerImplementation"
    
    public var logSubsystem: String { return delegateManager.logSubsystem }
    
    public func prependLogSubsystem(with prefix: String) {
        delegateManager.prependLogSubsystem(with: prefix)
    }
    
    // MARK: Instance variables
    
    lazy private var log = OSLog(subsystem: logSubsystem, category: "ObvNetworkSendManagerImplementation")
    
    /// Strong reference to the delegate manager, which keeps strong references to all external and internal delegate requirements.
    let delegateManager: ObvNetworkSendDelegateManager
    
    let bootstrapWorker: BootstrapWorker
    private let appType: AppType
    
    // MARK: Computed variables
    
    var contextCreator: ObvCreateContextDelegate? {
        return delegateManager.contextCreator
    }
    
    // MARK: Initialiser
    
    public init(outbox: URL, sharedContainerIdentifier: String, appType: AppType, supportBackgroundFetch: Bool = false) {
        self.bootstrapWorker = BootstrapWorker(appType: appType, outbox: outbox)
        self.appType = appType
        let networkSendFlowCoordinator = NetworkSendFlowCoordinator(outbox: outbox)
        let uploadMessageAndGetUidsCoordinator = UploadMessageAndGetUidsCoordinator()
        let uploadAttachmentChunksCoordinator = UploadAttachmentChunksCoordinator(appType: appType, sharedContainerIdentifier: sharedContainerIdentifier, outbox: outbox)
        let tryToDeleteMessageAndAttachmentsCoordinator = TryToDeleteMessageAndAttachmentsCoordinator()
        delegateManager = ObvNetworkSendDelegateManager(sharedContainerIdentifier: sharedContainerIdentifier,
                                                        supportBackgroundFetch: supportBackgroundFetch,
                                                        networkSendFlowDelegate: networkSendFlowCoordinator,
                                                        uploadMessageAndGetUidsDelegate: uploadMessageAndGetUidsCoordinator,
                                                        uploadAttachmentChunksDelegate: uploadAttachmentChunksCoordinator,
                                                        tryToDeleteMessageAndAttachmentsDelegate: tryToDeleteMessageAndAttachmentsCoordinator)
        networkSendFlowCoordinator.delegateManager = delegateManager
        uploadMessageAndGetUidsCoordinator.delegateManager = delegateManager
        uploadAttachmentChunksCoordinator.delegateManager = delegateManager
        tryToDeleteMessageAndAttachmentsCoordinator.delegateManager = delegateManager
        bootstrapWorker.delegateManager = delegateManager
    }
}


// MARK: - Implementing ObvManager

extension ObvNetworkSendManagerImplementation {
    public func fulfill(requiredDelegate delegate: AnyObject, forDelegateType delegateType: ObvEngineDelegateType) throws {
        switch delegateType {
        case .ObvCreateContextDelegate:
            guard let delegate = delegate as? ObvCreateContextDelegate else { throw Self.makeError(message: "Implementation error with ObvCreateContextDelegate") }
            delegateManager.contextCreator = delegate
        case .ObvNotificationDelegate:
            guard let delegate = delegate as? ObvNotificationDelegate else { throw Self.makeError(message: "Implementation error with ObvNotificationDelegate") }
            delegateManager.notificationDelegate = delegate
        case .ObvChannelDelegate:
            guard let delegate = delegate as? ObvChannelDelegate else { throw Self.makeError(message: "Implementation error with ObvChannelDelegate") }
            delegateManager.channelDelegate = delegate
        case .ObvSimpleFlowDelegate:
            guard let delegate = delegate as? ObvSimpleFlowDelegate else { throw Self.makeError(message: "Implementation error with ObvSimpleFlowDelegate") }
            delegateManager.simpleFlowDelegate = delegate
        case .ObvIdentityDelegate:
            guard let delegate = delegate as? ObvIdentityDelegate else { throw Self.makeError(message: "Implementation error with ObvIdentityDelegate") }
            delegateManager.identityDelegate = delegate
        default:
            throw Self.makeError(message: "Implementation error - unexpected delegate")
        }
    }
    
    public var requiredDelegates: [ObvEngineDelegateType] {
        return [ObvEngineDelegateType.ObvCreateContextDelegate,
                ObvEngineDelegateType.ObvNotificationDelegate,
                ObvEngineDelegateType.ObvChannelDelegate,
                ObvEngineDelegateType.ObvSimpleFlowDelegate,
                ObvEngineDelegateType.ObvIdentityDelegate]
    }
    

    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {}
    
    
    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {
        if forTheFirstTime {
            delegateManager.networkSendFlowDelegate.resetAllFailedSendAttempsCountersAndRetrySending()
        }
        await bootstrapWorker.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime, flowId: flowId)
    }


}


// MARK: - Implementing ObvNetworkPostDelegate

extension ObvNetworkSendManagerImplementation {
    
    public func post(_ message: ObvNetworkMessageToSend, within context: ObvContext) throws {
        try delegateManager.networkSendFlowDelegate.post(message, within: context)
    }
    
    
    public func cancelPostOfMessage(messageId: MessageIdentifier, flowId: FlowIdentifier) throws {
        
        try delegateManager.uploadMessageAndGetUidsDelegate.cancelMessageUpload(messageId: messageId, flowId: flowId)
        try delegateManager.uploadAttachmentChunksDelegate.cancelAllAttachmentsUploadOfMessage(messageId: messageId, flowId: flowId)

        // The URLSession uploading the attachments will eventually invalidate. At that point, the delegate will see that message/attachments are marked for deletion and will tell the server about it.
        
    }

    public func storeCompletionHandler(_ handler: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier identifier: String, withinFlowId flowId: FlowIdentifier) {
        delegateManager.networkSendFlowDelegate.storeCompletionHandler(handler, forHandlingEventsForBackgroundURLSessionWithIdentifier: identifier, withinFlowId: flowId)
    }

    
    public func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) -> Bool {
        return delegateManager.networkSendFlowDelegate.backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: backgroundURLSessionIdentifier)
    }

    public func requestUploadAttachmentProgressesUpdatedSince(date: Date) async throws -> [AttachmentIdentifier: Float] {
        return try await delegateManager.networkSendFlowDelegate.requestUploadAttachmentProgressesUpdatedSince(date: date)
    }

    public func replayTransactionsHistory(transactions: [NSPersistentHistoryTransaction], within obvContext: ObvContext) {
        bootstrapWorker.replayTransactionsHistory(transactions: transactions, within: obvContext)
    }
    
    public func deleteHistoryConcerningTheAcknowledgementOfOutboxMessages(messageIdentifiers: [MessageIdentifier], flowId: FlowIdentifier) {
        bootstrapWorker.deleteHistoryConcerningTheAcknowledgementOfOutboxMessages(messageIdentifiers: messageIdentifiers, flowId: flowId)
    }
    
    /// Called when an owned identity is about to be deleted.
    public func prepareForOwnedIdentityDeletion(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        
        // Delete all outbox messages relating to the owned identity
        
        try OutboxMessage.deleteAllForOwnedIdentity(ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext)
        
        // Delete all `DeletedOutboxMessage` relating to the owned identity
        
        try DeletedOutboxMessage.batchDelete(ownedCryptoIdentity: ownedCryptoIdentity, within: obvContext)

    }
    
}
