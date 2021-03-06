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
import ObvTypes
import ObvCrypto
import CoreData
import ObvEncoder
import OlvidUtils


public protocol ObvNetworkFetchDelegate: ObvManager {

    func updatedListOfOwnedIdentites(ownedIdentities: Set<ObvCryptoIdentity>, flowId: FlowIdentifier)
    
    func downloadMessages(for ownedIdentity: ObvCryptoIdentity, andDeviceUid deviceUid: UID, flowId: FlowIdentifier)
    func getEncryptedMessage(messageId: MessageIdentifier, flowId: FlowIdentifier) -> ObvNetworkReceivedMessageEncrypted?
    func getDecryptedMessage(messageId: MessageIdentifier, flowId: FlowIdentifier) -> ObvNetworkReceivedMessageDecrypted?
    func allAttachmentsCanBeDownloadedForMessage(withId: MessageIdentifier, within: ObvContext) throws -> Bool
    func allAttachmentsHaveBeenDownloadedForMessage(withId: MessageIdentifier, within: ObvContext) throws -> Bool
    func attachment(withId: AttachmentIdentifier, canBeDownloadedwithin: ObvContext) throws -> Bool

    func set(remoteCryptoIdentity: ObvCryptoIdentity, messagePayload: Data, extendedMessagePayloadKey: AuthenticatedEncryptionKey?, andAttachmentsInfos: [ObvNetworkFetchAttachmentInfos], forApplicationMessageWithmessageId: MessageIdentifier, within obvContext: ObvContext) throws
    
    func getAttachment(withId: AttachmentIdentifier, flowId: FlowIdentifier) -> ObvNetworkFetchReceivedAttachment?
    func requestProgressesOfAllInboxAttachmentsOfMessage(withIdentifier messageIdentifier: MessageIdentifier, flowId: FlowIdentifier)
    
    func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) -> Bool
    func processCompletionHandler(_: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier: String, withinFlowId: FlowIdentifier)

    func deleteMessageAndAttachments(messageId: MessageIdentifier, within: ObvContext)
    func markMessageForDeletion(messageId: MessageIdentifier, within: ObvContext)
    func markAttachmentForDeletion(attachmentId: AttachmentIdentifier, within: ObvContext)
    func resumeDownloadOfAttachment(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier)

    func register(pushNotificationType: ObvPushNotificationType, for: ObvCryptoIdentity, withDeviceUid: UID, within: ObvContext)
    func registerIfRequired(pushNotificationType: ObvPushNotificationType, for: ObvCryptoIdentity, withDeviceUid: UID, within: ObvContext)
    func unregisterPushNotification(for: ObvCryptoIdentity, within: ObvContext)
    func forceRegisterToPushNotification(identity: ObvCryptoIdentity, within obvContext: ObvContext) throws

    func sendDeleteReturnReceipt(ownedIdentity: ObvCryptoIdentity, serverUid: UID) throws
    
    func getWebSocketState(ownedIdentity: ObvCryptoIdentity, completionHander: @escaping (Result<(URLSessionTask.State,TimeInterval?),Error>) -> Void)
    func connectWebsockets(flowId: FlowIdentifier)
    func disconnectWebsockets(flowId: FlowIdentifier)

    func getTurnCredentials(ownedIdenty: ObvCryptoIdentity, callUuid: UUID, username1: String, username2: String, flowId: FlowIdentifier)

    func queryAPIKeyStatus(for identity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier)
    func resetServerSession(for identity: ObvCryptoIdentity, within obvContext: ObvContext) throws
    func queryFreeTrial(for identity: ObvCryptoIdentity, retrieveAPIKey: Bool, flowId: FlowIdentifier)
    func verifyReceipt(ownedIdentity: ObvCryptoIdentity, receiptData: String, transactionIdentifier: String, flowId: FlowIdentifier)
    func queryServerWellKnown(serverURL: URL, flowId: FlowIdentifier)

    func postServerQuery(_: ServerQuery, within: ObvContext)

}
