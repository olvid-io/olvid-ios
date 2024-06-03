/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import CoreData
import ObvMetaManager
import OlvidUtils

final class ObvNetworkFetchDelegateManager {
    
    let sharedContainerIdentifier: String
    let supportBackgroundFetch: Bool
    
    static let defaultLogSubsystem = "io.olvid.network.fetch"
    private(set) var logSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    
    let inbox: URL
    
    let internalNotificationCenter = NotificationCenter()

    // MARK: - Queues allowing to execute Core Data operations
    
    let queueSharedAmongCoordinators = OperationQueue.createSerialQueue(name: "Queue shared among coordinators of ObvNetworkFetchManagerImplementation", qualityOfService: .default)
    let queueForComposedOperations = {
        let queue = OperationQueue()
        queue.name = "Queue for composed operations"
        queue.qualityOfService = .default
        return queue
    }()

    let queueForDecryptingChunks = OperationQueue.createSerialQueue(name: "Queue for decrypting chunks", qualityOfService: .default)

    let queueForPostingNotifications = DispatchQueue(label: "ObvNetworkFetchDelegateManager queue for posting notifications")

    // MARK: Instance variables (internal delegates)
    
    let networkFetchFlowDelegate: NetworkFetchFlowDelegate
    let serverSessionDelegate: ServerSessionDelegate
    let messagesDelegate: MessagesDelegate
    let downloadAttachmentChunksDelegate: DownloadAttachmentChunksDelegate
    let batchDeleteAndMarkAsListedDelegate: BatchDeleteAndMarkAsListedDelegate
    let serverPushNotificationsDelegate: ServerPushNotificationsDelegate
    let webSocketDelegate: WebSocketDelegate
    let getTurnCredentialsDelegate: GetTurnCredentialsDelegate?
    let freeTrialQueryDelegate: FreeTrialQueryDelegate?
    let verifyReceiptDelegate: VerifyReceiptDelegate?
    let serverQueryDelegate: ServerQueryDelegate
    let serverQueryWebSocketDelegate: ServerQueryWebSocketDelegate
    let serverUserDataDelegate: ServerUserDataDelegate
    let wellKnownCacheDelegate: WellKnownCacheDelegate

    // MARK: Instance variables (external delegates)
    
    weak var contextCreator: ObvCreateContextDelegate?
    weak var processDownloadedMessageDelegate: ObvProcessDownloadedMessageDelegate?
    weak var solveChallengeDelegate: ObvSolveChallengeDelegate?
    weak var notificationDelegate: ObvNotificationDelegate?
    weak var identityDelegate: ObvIdentityDelegate?
    weak var simpleFlowDelegate: ObvSimpleFlowDelegate?
    weak var channelDelegate: ObvChannelDelegate?

    // MARK: Initialiazer
    
    init(inbox: URL, sharedContainerIdentifier: String, supportBackgroundFetch: Bool, logPrefix: String, networkFetchFlowDelegate: NetworkFetchFlowDelegate, serverSessionDelegate: ServerSessionDelegate, downloadMessagesAndListAttachmentsDelegate: MessagesDelegate, downloadAttachmentChunksDelegate: DownloadAttachmentChunksDelegate, batchDeleteAndMarkAsListedDelegate: BatchDeleteAndMarkAsListedDelegate, serverPushNotificationsDelegate: ServerPushNotificationsDelegate, webSocketDelegate: WebSocketDelegate, getTurnCredentialsDelegate: GetTurnCredentialsDelegate?, freeTrialQueryDelegate: FreeTrialQueryDelegate, verifyReceiptDelegate: VerifyReceiptDelegate, serverQueryDelegate: ServerQueryDelegate, serverQueryWebSocketDelegate: ServerQueryWebSocketDelegate, serverUserDataDelegate: ServerUserDataDelegate, wellKnownCacheDelegate: WellKnownCacheDelegate) {

        self.logSubsystem = "\(logPrefix).\(logSubsystem)"
        self.inbox = inbox
        self.sharedContainerIdentifier = sharedContainerIdentifier
        self.supportBackgroundFetch = supportBackgroundFetch
        
        self.networkFetchFlowDelegate = networkFetchFlowDelegate
        self.serverSessionDelegate = serverSessionDelegate
        self.messagesDelegate = downloadMessagesAndListAttachmentsDelegate
        self.downloadAttachmentChunksDelegate = downloadAttachmentChunksDelegate
        self.batchDeleteAndMarkAsListedDelegate = batchDeleteAndMarkAsListedDelegate
        self.serverPushNotificationsDelegate = serverPushNotificationsDelegate
        self.webSocketDelegate = webSocketDelegate
        self.getTurnCredentialsDelegate = getTurnCredentialsDelegate
        //self.queryApiKeyStatusDelegate = queryApiKeyStatusDelegate
        self.verifyReceiptDelegate = verifyReceiptDelegate
        self.serverQueryDelegate = serverQueryDelegate
        self.serverQueryWebSocketDelegate = serverQueryWebSocketDelegate
        self.serverUserDataDelegate = serverUserDataDelegate
        self.wellKnownCacheDelegate = wellKnownCacheDelegate
        self.freeTrialQueryDelegate = freeTrialQueryDelegate
    }
}


// MARK: - Errors

extension ObvNetworkFetchDelegateManager {
    
    enum ObvError: Error {
        case contextCreatorIsNil
        case composedOperationCancelled
    }
    
}


// MARK: - Helpers

extension ObvNetworkFetchDelegateManager {
    
    func createCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>, log: OSLog, flowId: FlowIdentifier) throws -> CompositionOfOneContextualOperation<T> {
        
        guard let contextCreator else {
            assertionFailure("The context creator manager is not set")
            throw ObvError.contextCreatorIsNil
        }
        
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: contextCreator, queueForComposedOperations: queueForComposedOperations, log: log, flowId: flowId)
        
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: log)
        }
        return composedOp
        
    }
    
    func createCompositionOfTwoContextualOperation<T1: LocalizedErrorWithLogType, T2: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T1>, op2: ContextualOperationWithSpecificReasonForCancel<T2>, log: OSLog, flowId: FlowIdentifier) throws -> CompositionOfTwoContextualOperations<T1, T2> {
        
        guard let contextCreator else {
            assertionFailure("The context creator manager is not set")
            throw ObvError.contextCreatorIsNil
        }

        let composedOp = CompositionOfTwoContextualOperations(op1: op1, op2: op2, contextCreator: contextCreator, queueForComposedOperations: queueForComposedOperations, log: log, flowId: flowId)
        
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: log)
        }
        return composedOp
    }
    
    func queueAndAwaitCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>, log: OSLog, flowId: FlowIdentifier) async throws {
        
        let composedOp = try createCompositionOfOneContextualOperation(op1: op1, log: log, flowId: flowId)
        await queueSharedAmongCoordinators.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            if let reasonForCancel = op1.reasonForCancel as? ObvNetworkFetchManager.GetPendingServerQueryTypeOperation.ReasonForCancel {
                switch reasonForCancel {
                case .ownedIdentityIsNotActive:
                    break
                case .pendingServerQueryNotFound:
                    break
                default:
                    assertionFailure()
                }
            } else {
                assertionFailure()
            }
            throw ObvError.composedOperationCancelled
        }

    }
    
    func queueAndAwaitCompositionOfTwoContextualOperation<T1: LocalizedErrorWithLogType, T2: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T1>, op2: ContextualOperationWithSpecificReasonForCancel<T2>, log: OSLog, flowId: FlowIdentifier) async throws {
     
        let composedOp = try createCompositionOfTwoContextualOperation(op1: op1, op2: op2, log: log, flowId: flowId)
        await queueSharedAmongCoordinators.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw ObvError.composedOperationCancelled
        }

    }
    
}
