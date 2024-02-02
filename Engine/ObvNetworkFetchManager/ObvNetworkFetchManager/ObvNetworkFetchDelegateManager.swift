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
import ObvMetaManager

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

    // MARK: Instance variables (internal delegates)
    
    let networkFetchFlowDelegate: NetworkFetchFlowDelegate
    let serverSessionDelegate: ServerSessionDelegate
    let messagesDelegate: MessagesDelegate
    let downloadAttachmentChunksDelegate: DownloadAttachmentChunksDelegate
    let deleteMessageAndAttachmentsFromServerDelegate: DeleteMessageAndAttachmentsFromServerDelegate
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
    
    init(inbox: URL, sharedContainerIdentifier: String, supportBackgroundFetch: Bool, logPrefix: String, networkFetchFlowDelegate: NetworkFetchFlowDelegate, serverSessionDelegate: ServerSessionDelegate, downloadMessagesAndListAttachmentsDelegate: MessagesDelegate, downloadAttachmentChunksDelegate: DownloadAttachmentChunksDelegate, deleteMessageAndAttachmentsFromServerDelegate: DeleteMessageAndAttachmentsFromServerDelegate, serverPushNotificationsDelegate: ServerPushNotificationsDelegate, webSocketDelegate: WebSocketDelegate, getTurnCredentialsDelegate: GetTurnCredentialsDelegate?, freeTrialQueryDelegate: FreeTrialQueryDelegate, verifyReceiptDelegate: VerifyReceiptDelegate, serverQueryDelegate: ServerQueryDelegate, serverQueryWebSocketDelegate: ServerQueryWebSocketDelegate, serverUserDataDelegate: ServerUserDataDelegate, wellKnownCacheDelegate: WellKnownCacheDelegate) {

        self.logSubsystem = "\(logPrefix).\(logSubsystem)"
        self.inbox = inbox
        self.sharedContainerIdentifier = sharedContainerIdentifier
        self.supportBackgroundFetch = supportBackgroundFetch
        
        self.networkFetchFlowDelegate = networkFetchFlowDelegate
        self.serverSessionDelegate = serverSessionDelegate
        self.messagesDelegate = downloadMessagesAndListAttachmentsDelegate
        self.downloadAttachmentChunksDelegate = downloadAttachmentChunksDelegate
        self.deleteMessageAndAttachmentsFromServerDelegate = deleteMessageAndAttachmentsFromServerDelegate
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
