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
    func getDecryptedMessage(messageId: MessageIdentifier, flowId: FlowIdentifier) -> ObvNetworkReceivedMessageDecrypted?
    func allAttachmentsCanBeDownloadedForMessage(withId: MessageIdentifier, within: ObvContext) throws -> Bool
    func allAttachmentsHaveBeenDownloadedForMessage(withId: MessageIdentifier, within: ObvContext) throws -> Bool
    func attachment(withId: AttachmentIdentifier, canBeDownloadedwithin: ObvContext) throws -> Bool

    func setRemoteCryptoIdentity(_ remoteCryptoIdentity: ObvCryptoIdentity, messagePayload: Data, extendedMessagePayloadKey: AuthenticatedEncryptionKey?, andAttachmentsInfos: [ObvNetworkFetchAttachmentInfos], forApplicationMessageWithmessageId: MessageIdentifier, within obvContext: ObvContext) throws
    
    func getAttachment(withId attachmentId: AttachmentIdentifier, within obvContext: ObvContext) -> ObvNetworkFetchReceivedAttachment?
    
    func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) -> Bool
    func processCompletionHandler(_: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier: String, withinFlowId: FlowIdentifier)

    func deleteMessageAndAttachments(messageId: MessageIdentifier, within: ObvContext)
    func markMessageForDeletion(messageId: MessageIdentifier, within: ObvContext)
    func markAttachmentForDeletion(attachmentId: AttachmentIdentifier, within: ObvContext)
    func resumeDownloadOfAttachment(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier)
    func pauseDownloadOfAttachment(attachmentId: AttachmentIdentifier, flowId: FlowIdentifier)
    func requestDownloadAttachmentProgressesUpdatedSince(date: Date) async throws -> [AttachmentIdentifier: Float]

    func registerPushNotification(_ pushNotification: ObvPushNotificationType, flowId: FlowIdentifier)
    func getServerPushNotification(ownedCryptoId: ObvCryptoIdentity, within obvContext: ObvContext) throws -> ObvPushNotificationType?

    func sendDeleteReturnReceipt(ownedIdentity: ObvCryptoIdentity, serverUid: UID) async throws
    
    func getWebSocketState(ownedIdentity: ObvCryptoIdentity) async throws -> (URLSessionTask.State,TimeInterval?)
    func connectWebsockets(flowId: FlowIdentifier) async
    func disconnectWebsockets(flowId: FlowIdentifier) async

    func getTurnCredentials(ownedIdenty: ObvCryptoIdentity, callUuid: UUID, username1: String, username2: String, flowId: FlowIdentifier)

    func queryAPIKeyStatus(for identity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier)
    func resetServerSession(for identity: ObvCryptoIdentity, within obvContext: ObvContext) throws
    func queryFreeTrial(for identity: ObvCryptoIdentity, retrieveAPIKey: Bool, flowId: FlowIdentifier)
    func verifyReceipt(ownedCryptoIdentities: [ObvCryptoIdentity], receiptData: String, transactionIdentifier: String, flowId: FlowIdentifier)
    func queryServerWellKnown(serverURL: URL, flowId: FlowIdentifier)

    func postServerQuery(_: ServerQuery, within: ObvContext)

    func prepareForOwnedIdentityDeletion(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws

}
