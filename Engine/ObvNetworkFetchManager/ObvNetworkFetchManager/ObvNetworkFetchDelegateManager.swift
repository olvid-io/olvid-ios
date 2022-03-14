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
import CoreData
import ObvMetaManager

final class ObvNetworkFetchDelegateManager {
    
    let sharedContainerIdentifier: String
    let supportBackgroundFetch: Bool
    
    static let defaultLogSubsystem = "io.olvid.network.fetch"
    private(set) var logSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    
    func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
    }
    
    let inbox: URL
    
    let internalNotificationCenter = NotificationCenter()

    // MARK: Instance variables (internal delegates)
    
    let networkFetchFlowDelegate: NetworkFetchFlowDelegate
    let getAndSolveChallengeDelegate: GetAndSolveChallengeDelegate
    let getTokenDelegate: GetTokenDelegate
    let messagesDelegate: MessagesDelegate
    let downloadAttachmentChunksDelegate: DownloadAttachmentChunksDelegate
    let deleteMessageAndAttachmentsFromServerDelegate: DeleteMessageAndAttachmentsFromServerDelegate
    let processRegisteredPushNotificationsDelegate: ProcessRegisteredPushNotificationsDelegate
    let webSocketDelegate: WebSocketDelegate
    let getTurnCredentialsDelegate: GetTurnCredentialsDelegate?
    let queryApiKeyStatusDelegate: QueryApiKeyStatusDelegate?
    let freeTrialQueryDelegate: FreeTrialQueryDelegate?
    let verifyReceiptDelegate: VerifyReceiptDelegate?
    let serverQueryDelegate: ServerQueryDelegate
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
    
    init(inbox: URL, sharedContainerIdentifier: String, supportBackgroundFetch: Bool, networkFetchFlowDelegate: NetworkFetchFlowDelegate, getAndSolveChallengeDelegate: GetAndSolveChallengeDelegate, getTokenDelegate: GetTokenDelegate, downloadMessagesAndListAttachmentsDelegate: MessagesDelegate, downloadAttachmentChunksDelegate: DownloadAttachmentChunksDelegate, deleteMessageAndAttachmentsFromServerDelegate: DeleteMessageAndAttachmentsFromServerDelegate, processRegisteredPushNotificationsDelegate: ProcessRegisteredPushNotificationsDelegate, webSocketDelegate: WebSocketDelegate, getTurnCredentialsDelegate: GetTurnCredentialsDelegate?, queryApiKeyStatusDelegate: QueryApiKeyStatusDelegate, freeTrialQueryDelegate: FreeTrialQueryDelegate, verifyReceiptDelegate: VerifyReceiptDelegate, serverQueryDelegate: ServerQueryDelegate, serverUserDataDelegate: ServerUserDataDelegate, wellKnownCacheDelegate: WellKnownCacheDelegate) {

        self.inbox = inbox
        self.sharedContainerIdentifier = sharedContainerIdentifier
        self.supportBackgroundFetch = supportBackgroundFetch
        
        self.networkFetchFlowDelegate = networkFetchFlowDelegate
        self.getAndSolveChallengeDelegate = getAndSolveChallengeDelegate
        self.getTokenDelegate = getTokenDelegate
        self.messagesDelegate = downloadMessagesAndListAttachmentsDelegate
        self.downloadAttachmentChunksDelegate = downloadAttachmentChunksDelegate
        self.deleteMessageAndAttachmentsFromServerDelegate = deleteMessageAndAttachmentsFromServerDelegate
        self.processRegisteredPushNotificationsDelegate = processRegisteredPushNotificationsDelegate
        self.webSocketDelegate = webSocketDelegate
        self.getTurnCredentialsDelegate = getTurnCredentialsDelegate
        self.queryApiKeyStatusDelegate = queryApiKeyStatusDelegate
        self.freeTrialQueryDelegate = freeTrialQueryDelegate
        self.verifyReceiptDelegate = verifyReceiptDelegate
        self.serverQueryDelegate = serverQueryDelegate
        self.serverUserDataDelegate = serverUserDataDelegate
        self.wellKnownCacheDelegate = wellKnownCacheDelegate
    }
}
