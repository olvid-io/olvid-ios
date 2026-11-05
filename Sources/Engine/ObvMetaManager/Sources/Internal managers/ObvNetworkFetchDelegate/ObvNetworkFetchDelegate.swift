/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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

    func updatedListOfOwnedIdentites(activeOwnedCryptoIdsAndCurrentDeviceUIDs: Set<OwnedCryptoIdentityAndCurrentDeviceUID>, flowId: FlowIdentifier) async throws
    
    /// - Parameter trigger: what provoked this listing, recorded with its timing. The app knows things the engine cannot infer — whether a listing is one a
    /// reader is waiting for or one a background processing task asked for — and this is how it says so.
    func downloadMessages(for ownedIdentity: ObvCryptoIdentity, trigger: ObvServerRequestTiming.Trigger, flowId: FlowIdentifier) async

    /// How much work the inbox still holds: a handful of counts over one context, materialising nothing.
    ///
    /// Cheap on purpose. The same numbers are among the figures of ``getAsyncStreamOfEngineDiagnostics(flowId:)``, whose pass takes seconds and cannot be
    /// interrupted once begun — usable for a screen, useless for a caller that must ask every half second whether anything is still moving.
    ///
    /// - Parameter alsoCountingMessagesWaitingForAManualDownload: whether to answer ``ObvInboxCounts/numberOfMessagesWaitingForAManualDownload`` as well as
    /// the four cheap counts, at the price of a subquery over every message's attachments — 72ms against 12–14ms apiece for the others, on a store of 81'210
    /// messages carrying one attachment each. Pass `false` where the answer is asked for many times a second and is not read.
    /// - Parameter alsoCountingMessagesOfInactiveProfiles: whether to answer ``ObvInboxCounts/numberOfMessagesBelongingToAnInactiveOwnedIdentity`` as well.
    /// It is a *negated* membership test, so no index narrows it and it scans the table — and the figure cannot change while a drain runs, nothing being
    /// able to move a message of an inactive profile. Pass `true` where it is shown to somebody, `false` on a poll.
    func getInboxCounts(alsoCountingMessagesWaitingForAManualDownload: Bool, alsoCountingMessagesOfInactiveProfiles: Bool, flowId: FlowIdentifier) async throws -> ObvInboxCounts

    /// How long the listing has been failing to reach the server, counting only what happened since `since`, or nil if it is reaching it.
    ///
    /// **This is the only way out of the engine for a fact the listing otherwise keeps to itself.** `downloadMessages(for:trigger:flowId:)` waits out an
    /// uncapped back-off and tries again for ever rather than reporting a failure, so a caller watching a drain cannot tell a large backlog from a server
    /// that has gone. The timings the listing records on its way past say which it is.
    func howLongTheListingHasBeenUnableToReachTheServer(since: Date, now: Date) async -> TimeInterval?
    func allAttachmentsCanBeDownloadedForMessage(withId: ObvMessageIdentifier, within: NSManagedObjectContext) throws -> Bool
    func allAttachmentsHaveBeenDownloadedForMessage(withId: ObvMessageIdentifier, within: NSManagedObjectContext) throws -> Bool
    func attachment(withId: ObvAttachmentIdentifier, canBeDownloadedwithin context: NSManagedObjectContext) throws -> Bool

    func getAttachment(withId attachmentId: ObvAttachmentIdentifier, within context: NSManagedObjectContext) -> ObvNetworkFetchReceivedAttachment?
    
    func backgroundURLSessionIdentifierIsAppropriate(backgroundURLSessionIdentifier: String) async -> Bool
    func processCompletionHandler(_: @escaping () -> Void, forHandlingEventsForBackgroundURLSessionWithIdentifier: String, withinFlowId: FlowIdentifier) async

    /// Same contract as ``markApplicationMessageForDeletionAndProcessAttachments(messageId:attachmentsProcessingRequest:flowId:)`` below, of which this is
    /// the `.deleteAll` form: the returned task cancels the downloads of the attachments being deleted, and is still running when this returns.
    func deleteApplicationMessageAndAttachments(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) async throws -> Task<Void, Never>

    /// The bulk form of ``deleteApplicationMessageAndAttachments(messageId:flowId:)``: one context, one save and one kick of the batch-delete sweep for the
    /// whole page.
    func deleteApplicationMessagesAndAttachments(messageIds: [ObvMessageIdentifier], flowId: FlowIdentifier) async throws
    /// Returns once the message and its attachments are marked, handing back the task that cancels the downloads of the attachments being deleted and resumes
    /// the ones the app asked for. That task is still running when this returns, so a caller holding a background activity for this work must keep that
    /// activity until the task ends.
    func markApplicationMessageForDeletionAndProcessAttachments(messageId: ObvMessageIdentifier, attachmentsProcessingRequest: ObvAttachmentsProcessingRequest, flowId: FlowIdentifier) async throws -> Task<Void, Never>
    /// Same contract as the method above: the returned task cancels the download of the attachment being deleted, and is still running when this returns.
    func markAttachmentForDeletion(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws -> Task<Void, Never>
    func resumeDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws
    func appCouldNotFindFileOfDownloadedAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws
    func appFoundACorruptFileForDownloadedAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws
    func pauseDownloadOfAttachment(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws
    func requestDownloadAttachmentProgressesUpdatedSince(date: Date) async throws -> [ObvAttachmentIdentifier: Float]
    func getAsyncStreamOfDownloadProgress(attachmentId: ObvAttachmentIdentifier, flowId: FlowIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvAttachmentDownloadProgress>)
    func finishAsyncStreamOfDownloadProgress(streamUUID: UUID) async throws

    func registerPushNotification(_ pushNotification: ObvPushNotificationType, flowId: FlowIdentifier) async throws

    func sendDeleteReturnReceipt(ownedIdentity: ObvCryptoIdentity, serverUid: UID) async throws
    
    func getWebSocketState(ownedIdentity: ObvCryptoIdentity, handler: @escaping @Sendable (Result<(URLSessionTask.State, TimeInterval?), Error>) -> Void) async
    func connectWebsockets(activeOwnedCryptoIdsAndCurrentDeviceUIDs: Set<OwnedCryptoIdentityAndCurrentDeviceUID>, flowId: FlowIdentifier) async throws
    func disconnectWebsockets(flowId: FlowIdentifier) async

    func getWellKnownTurnCredentials(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> ObvWellKnownTurnCredentials

    func refreshAPIPermissions(of ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws
    func queryAPIKeyStatus(for identity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) async throws -> APIKeyElements
    func registerOwnedAPIKeyOnServerNow(ownedCryptoIdentity: ObvCryptoIdentity, apiKey: UUID, flowId: FlowIdentifier) async throws
    func queryFreeTrial(for identity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> Bool
    func startFreeTrial(for identity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws
    func verifyReceiptAndRefreshAPIPermissions(appStoreReceiptElements: ObvAppStoreReceipt, environment: ObvAppStoreEnvironment, flowId: FlowIdentifier) async throws -> [ObvCryptoIdentity : ObvAppStoreReceipt.VerificationStatus]
    // func verifyReceipt(ownedCryptoIdentities: [ObvCryptoIdentity], receiptData: String, transactionIdentifier: String, flowId: FlowIdentifier)
    func queryServerWellKnown(serverURL: URL, flowId: FlowIdentifier) async throws

    func postServerQuery(_ serverQuery: ServerQuery, within context: NSManagedObjectContext) throws

    func prepareForOwnedIdentityDeletion(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier)
    func deleteServerSessionsAssociatedToNonExistingOwnedIdentity(existingOwnedCryptoIds: Set<ObvCryptoIdentity>, flowId: FlowIdentifier) async throws
    func deleteInboxMessagesAssociatedToNonExistingOwnedIdentity(existingOwnedCryptoIds: Set<ObvCryptoIdentity>, flowId: FlowIdentifier) async throws

    func performOwnedDeviceDiscoveryNow(ownedCryptoId: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> EncryptedData
    
    func remoteIdentityIsNowAContact(contactIdentifier: ObvContactIdentifier, flowId: FlowIdentifier) async throws

    func getUserDataNow(cryptoId: ObvCryptoId, serverLabel: UID, flowId: FlowIdentifier) async throws -> EncryptedData?

    func getAPIKeyElementsDuringNewBackupRestore(cryptoId: ObvCryptoId, privateKeyForAuthentication: any PrivateKeyForAuthentication, flowId: FlowIdentifier) async throws -> APIKeyElements
    
    func getAsyncStreamOfEncryptedReceivedReturnReceipt() async -> AsyncStream<ObvTypes.ObvEncryptedReceivedReturnReceipt>
    
    func getAsyncStreamOfObvMessageOrObvOwnedMessages() async -> AsyncStream<[ObvTypes.ObvMessageOrObvOwnedMessage]>

    func putMessageOnHold(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) async throws
    func fetchOnHoldMessage(messageId: ObvMessageIdentifier, flowId: FlowIdentifier) async throws -> ObvMessageOrObvOwnedMessage?

    /// The payloads of a page of on-hold messages, keyed by identifier. The bulk form of ``fetchOnHoldMessage(messageId:flowId:)``, vending payloads rather
    /// than messages because deciding what one carries is an app-side question and building the messages would materialise every row.
    func getPayloadsOfMessagesOnHold(messageIds: [ObvMessageIdentifier], flowId: FlowIdentifier) async throws -> [ObvMessageIdentifier: Data]

    /// Figures describing the state of the inbox, streamed one at a time so that a screen showing them fills as they are found rather than waiting for the
    /// slowest. A fresh stream on each call; it finishes when the last figure has been sent.
    func getAsyncStreamOfEngineDiagnostics(flowId: FlowIdentifier) -> AsyncStream<ObvEngineDiagnostic>

}
