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
import CoreData
import OSLog
import Intents
import UserNotifications
import OlvidUtils
import ObvEngine
import ObvCrypto
import ObvUICoreData
import ObvUserNotificationsContent
import ObvUserNotificationsDatabase
import ObvAppTypes
import ObvTypes
import ObvAppCoreConstants
import ObvSettings
import ObvSiriReadIntents

actor IntentCoordinator {

    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "IntentCoordinator")
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "IntentCoordinator")

    private let coordinatorsQueue = OperationQueue.createSerialQueue(name: "IntentCoordinator coordinators queue", qualityOfService: .userInitiated)

    private static let queueForComposedOperations = OperationQueue.createSerialQueue(name: "IntentCoordinator queue for composed operations", qualityOfService: .userInitiated)

    private var obvEngine: ObvEngine?
    private var initializationInProgress = false
    private var continuationsOnInitializationDone = [CheckedContinuation<ObvEngine, Error>]()
    private let runningLog: RunningLogError

    init(runningLog: RunningLogError) {
        self.runningLog = runningLog
    }


    // MARK: - Initialization

    /// Lazily initializes the `ObvEngine`. Concurrent callers are coalesced via continuations so a
    /// single engine instance is shared.
    func initialize() async throws -> ObvEngine {

        if let obvEngine {
            return obvEngine
        }

        if initializationInProgress {
            return try await withCheckedThrowingContinuation { continuation in
                if let obvEngine {
                    continuation.resume(returning: obvEngine)
                } else {
                    self.continuationsOnInitializationDone.insert(continuation, at: 0)
                }
            }
        }

        initializationInProgress = true
        defer { initializationInProgress = false }

        do {

            let engine = try await ObvEngine.startLimitedToSending(
                logPrefix: "LimitedEngine",
                sharedContainerIdentifier: ObvAppCoreConstants.appGroupIdentifier,
                mainContainerURL: ObvUICoreDataConstants.ContainerURL.mainEngineContainer.url,
                supportBackgroundTasks: ObvMessengerConstants.isRunningOnRealDevice,
                remoteNotificationByteIdentifierForServer: ObvAppCoreConstants.remoteNotificationByteIdentifierForServer,
                appType: .intentExtension,
                runningLog: runningLog)

            self.obvEngine = engine

            while let continuation = self.continuationsOnInitializationDone.popLast() {
                continuation.resume(returning: engine)
            }

            return engine

        } catch {
            while let continuation = self.continuationsOnInitializationDone.popLast() {
                continuation.resume(throwing: error)
            }
            throw error
        }

    }


    // MARK: - Send message

    enum SendMessageError: Error {
        case couldNotCreateMessage
        case couldNotSendMessage
    }

    /// Sends `textBody` and/or `audioFile` to each `ObvDiscussionIdentifier` in `discussionIdentifiers`.
    /// Returns one outcome per discussion. The transcode of an audio attachment happens once,
    /// regardless of recipient count. If the engine cannot be initialized, every discussion receives
    /// the same `.failure(error)`. If the audio transcode fails, every discussion receives the same
    /// transcode error. Per-recipient send failures are isolated and reported individually.
    func sendMessage(discussionIdentifiers: [ObvDiscussionIdentifier],
                     textBody: String?,
                     audioFile: INFile? = nil) async -> [ObvDiscussionIdentifier: Result<Void, Error>] {

        var outcomes: [ObvDiscussionIdentifier: Result<Void, Error>] = [:]

        let obvEngine: ObvEngine
        do {
            obvEngine = try await initialize()
        } catch {
            for discussionIdentifier in discussionIdentifiers {
                outcomes[discussionIdentifier] = .failure(error)
            }
            return outcomes
        }

        Self.logger.info("📤 Sending message to \(discussionIdentifiers.count) discussion(s)")

        // Transcode once, outside the per-recipient loop. If the transcode fails every recipient fails with that error.
        let transcodedAudioFile: INFile?
        if let audioFile {
            do {
                transcodedAudioFile = try await audioFile.transcodeToM4A()
            } catch {
                Self.logger.fault("📤 Audio transcode failed: \(error)")
                for discussionIdentifier in discussionIdentifiers {
                    outcomes[discussionIdentifier] = .failure(error)
                }
                return outcomes
            }
        } else {
            transcodedAudioFile = nil
        }

        for discussionIdentifier in discussionIdentifiers {
            do {
                let messageSentPermanentID: MessageSentPermanentID
                if let transcodedAudioFile {
                    messageSentPermanentID = try await createAudioMessage(
                        discussionIdentifier: discussionIdentifier,
                        textBody: textBody,
                        transcodedAudioFile: transcodedAudioFile)
                } else if let textBody {
                    messageSentPermanentID = try await createTextMessage(
                        discussionIdentifier: discussionIdentifier,
                        textBody: textBody)
                } else {
                    throw SendMessageError.couldNotCreateMessage
                }
                try await sendUnprocessedMessage(
                    messageSentPermanentID: messageSentPermanentID,
                    obvEngine: obvEngine)
                outcomes[discussionIdentifier] = .success(())
            } catch {
                Self.logger.error("📤 Failed to send to discussion: \(error)")
                outcomes[discussionIdentifier] = .failure(error)
            }
        }

        return outcomes
    }


    private func createTextMessage(discussionIdentifier: ObvDiscussionIdentifier,
                                   textBody: String) async throws -> MessageSentPermanentID {
        let op1 = CreateUnprocessedPersistedMessageSent(
            body: textBody,
            discussionIdentifier: discussionIdentifier)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard !composedOp.isCancelled, let messageSentPermanentID = op1.messageSentPermanentID else {
            throw SendMessageError.couldNotCreateMessage
        }
        return messageSentPermanentID
    }


    private func createAudioMessage(discussionIdentifier: ObvDiscussionIdentifier,
                                    textBody: String?,
                                    transcodedAudioFile: INFile) async throws -> MessageSentPermanentID {
        let op1 = CreateFyleFromINFileOperation(file: transcodedAudioFile)
        let op2 = CreateUnprocessedPersistedMessageSent(
            body: textBody,
            fyleJoinsProvider: op1,
            discussionIdentifier: discussionIdentifier)
        let composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard !composedOp.isCancelled, let messageSentPermanentID = op2.messageSentPermanentID else {
            throw SendMessageError.couldNotCreateMessage
        }
        return messageSentPermanentID
    }
    

    // MARK: - Mark message as read

    enum MarkMessageAsReadError: Error {
        case failed
    }


    /// Handles "mark as read" requested via Siri (`INSetMessageAttributeIntent`).
    ///
    /// The implementation branches on whether the message is present in the app database. Siri may
    /// have read a message sourced from the user-notification database (decrypted by the NSE but not
    /// yet drained into the app DB), in which case there is no `PersistedMessageReceived` to mark.
    /// Each branch lives in its own helper:
    ///
    /// - Message present in the app database → ``handleMarkAsReadForMessageInAppDatabase(messageAppIdentifier:obvEngine:)``.
    /// - Message missing from the app database → ``handleMarkAsReadForMessageMissingFromAppDatabase(messageAppIdentifier:obvEngine:)``.
    func markMessageAsRead(messageAppIdentifier: ObvMessageAppIdentifier) async throws {

        let obvEngine = try await initialize()

        let existsInAppDatabase = try await receivedMessageExistsInAppDatabase(messageAppIdentifier: messageAppIdentifier)
        if existsInAppDatabase {
            try await handleMarkAsReadForMessageInAppDatabase(messageAppIdentifier: messageAppIdentifier, obvEngine: obvEngine)
        } else {
            await handleMarkAsReadForMessageMissingFromAppDatabase(messageAppIdentifier: messageAppIdentifier, obvEngine: obvEngine)
        }
    }


    /// Existing mark-as-read pipeline for a message that lives in the app database. Branches further
    /// on attachment presence:
    ///
    /// - At least one attachment in the `FyleMessageJoinWithStatus` relationship (including wiped
    ///   joins) → no-op. Siri voices the body but never the attachments, so we don't claim the
    ///   message as fully consumed. Nothing is written to Core Data, no read receipt is sent, no
    ///   companion device is notified, the delivered user notification stays, and the app badge is
    ///   left untouched. The caller still returns `.success` to Siri so the user gets a coherent
    ///   confirmation.
    /// - Pure text message → full pipeline runs: the received message is marked as read in Core Data
    ///   (which triggers the return-receipt observer when allowed), companion owned devices are
    ///   informed via `PostDiscussionReadJSONEngineOperation`, the delivered user notification for
    ///   that message is removed, and the app badge is recomputed and applied directly (extensions
    ///   can't rely on the main app's badge manager being alive).
    private func handleMarkAsReadForMessageInAppDatabase(messageAppIdentifier: ObvMessageAppIdentifier, obvEngine: ObvEngine) async throws {

        let hasAttachments = try await receivedMessageHasAttachments(messageAppIdentifier: messageAppIdentifier)
        guard !hasAttachments else {
            Self.logger.info("✅ Message has at least one attachment, skipping the mark-as-read pipeline")
            return
        }

        Self.logger.info("✅ Marking message as read")

        let op1 = MarkReceivedMessageAsReadFromCurrentDeviceOperation(
            .messageAppIdentifier(messageAppIdentifier))
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard !composedOp.isCancelled else {
            throw MarkMessageAsReadError.failed
        }

        if op1.ownedIdentityHasAnotherReachableDevice {
            let postOp = PostDiscussionReadJSONEngineOperation(op: op1, obvEngine: obvEngine)
            await coordinatorsQueue.addAndAwaitOperation(postOp)
        }

        if let readReceiptToSend = op1.readReceiptToSend {
            // This extension is about to finish, and only the app sweeps the store, so it waits for the receipt to
            // leave rather than leaving it for the reader's next foreground.
            await obvEngine.postReturnReceiptsWithElements(returnReceiptsToSend: [readReceiptToSend], waitUntilSent: true)
        }

        await removeDeliveredUserNotification(messageAppIdentifier: messageAppIdentifier)

        await refreshAppBadge()

    }


    /// Mark-as-read path when the message has no `PersistedMessageReceived` in the app database —
    /// typical for messages Siri found via the user-notification database, or for messages the
    /// engine hasn't fetched yet at all.
    ///
    /// Always records the intent in ``SiriReadIntentStore`` so the app honours it on next launch
    /// (and at every point where a `PersistedMessageReceived` is later created — drain from the NSE
    /// database, engine fetch, etc.). When the NSE database does carry a matching row and the user
    /// has opted into read receipts for this discussion, the read receipt is posted directly via the
    /// engine so the sender's devices see "read" without waiting for the app to launch. The
    /// delivered user notification is removed in either case, and the app badge is refreshed.
    private func handleMarkAsReadForMessageMissingFromAppDatabase(messageAppIdentifier: ObvMessageAppIdentifier, obvEngine: ObvEngine) async {

        Self.logger.info("✅ Message is not in the app database, recording the Siri-read intent and sending the read receipt if allowed")

        await SiriReadIntentStore.shared.markAsReadBySiri(messageAppIdentifier)

        if ObvUserNotificationsStack.isInitialized {
            do {
                if let pending = try await fetchPendingMessageForReadReceipt(messageAppIdentifier: messageAppIdentifier) {
                    await sendReadReceiptForMessageMissingFromAppDatabase(
                        discussionIdentifier: pending.discussionIdentifier,
                        obvMessage: pending.obvMessage,
                        obvEngine: obvEngine)
                } else {
                    Self.logger.info("✅ No matching user-notification row found, deferring read-receipt send to the app drain")
                }
            } catch {
                Self.logger.error("✅ Failed to fetch matching user-notification row, deferring read-receipt send to the app drain: \(error.localizedDescription)")
            }
        } else {
            Self.logger.info("✅ User-notification stack is not initialized, deferring read-receipt send to the app drain")
        }

        await removeDeliveredUserNotification(messageAppIdentifier: messageAppIdentifier)

        await refreshAppBadge()

    }


    /// Looks up the pending user-notification row for `messageAppIdentifier` in the NSE database.
    /// Returns the row's discussion identifier and the original `ObvMessage` (whose `messagePayload`
    /// carries the return-receipt element from the sender — updates aren't used here because the
    /// element is set at original send time, not on edits). Caller must check
    /// ``ObvUserNotificationsStack.isInitialized`` before calling.
    private func fetchPendingMessageForReadReceipt(messageAppIdentifier: ObvMessageAppIdentifier) async throws -> (discussionIdentifier: ObvDiscussionIdentifier, obvMessage: ObvMessage)? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(ObvDiscussionIdentifier, ObvMessage)?, any Error>) in
            ObvUserNotificationsStack.shared.performBackgroundTask { context in
                do {
                    guard let row = try PersistedUserNotification.getPendingReceivedMessageForIntents(messageAppIdentifier: messageAppIdentifier, within: context) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: (row.discussionIdentifier, row.obvMessage))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }


    /// Builds and posts an `ObvReturnReceiptToSend(.read)` for a message that lives only in the NSE
    /// database. Gates on the per-discussion `doSendReadReceipt` override (when the discussion is in
    /// the app DB) and the global `ObvMessengerSettings.Discussions.doSendReadReceipt` fallback.
    /// Resolves all of the sender's device UIDs via `PersistedObvContactIdentity.devices` so all of
    /// their devices learn about the read, matching the app-side
    /// `PersistedMessageReceived.sendObvReturnReceipt` behaviour.
    private func sendReadReceiptForMessageMissingFromAppDatabase(
        discussionIdentifier: ObvDiscussionIdentifier,
        obvMessage: ObvMessage,
        obvEngine: ObvEngine
    ) async {
        guard await shouldSendReadReceipt(discussionIdentifier: discussionIdentifier) else {
            Self.logger.info("✅ Read receipts are disabled for this discussion, not sending")
            return
        }
        guard let payload = try? PersistedItemJSON.jsonDecode(obvMessage.messagePayload),
              let returnReceipt = payload.returnReceipt else {
            Self.logger.info("✅ Message payload carries no return-receipt element, nothing to send")
            return
        }
        let toSend = ObvReturnReceiptToSend(
            elements: returnReceipt.elements,
            status: .read,
            contactIdentifier: obvMessage.fromContactIdentity,
            attachmentNumber: nil)
        // This extension is about to finish, and only the app sweeps the store, so it waits for the receipt to leave
        // rather than leaving it for the reader's next foreground.
        await obvEngine.postReturnReceiptsWithElements(returnReceiptsToSend: [toSend], waitUntilSent: true)
        Self.logger.info("✅ Posted read receipt for message found only in the user-notification database")
    }


    /// Returns whether read receipts are enabled for `discussionIdentifier`. Honours the
    /// per-discussion `PersistedDiscussionLocalConfiguration.doSendReadReceipt` override when the
    /// discussion is found in the app database; otherwise falls back to
    /// `ObvMessengerSettings.Discussions.doSendReadReceipt`. Errors during the lookup also fall back
    /// to the global setting (treating an unreadable per-discussion override as absent).
    private func shouldSendReadReceipt(discussionIdentifier: ObvDiscussionIdentifier) async -> Bool {
        do {
            return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<Bool, any Error>, context: NSManagedObjectContext) in
                if let discussion = try PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: discussionIdentifier, within: context) {
                    let value = discussion.localConfiguration.doSendReadReceipt ?? ObvMessengerSettings.Discussions.doSendReadReceipt
                    continuation.resume(returning: value)
                } else {
                    continuation.resume(returning: ObvMessengerSettings.Discussions.doSendReadReceipt)
                }
            }
        } catch {
            Self.logger.error("✅ Failed to read discussion read-receipt setting, falling back to global: \(error.localizedDescription)")
            return ObvMessengerSettings.Discussions.doSendReadReceipt
        }
    }



    /// Returns `true` iff a `PersistedMessageReceived` exists in the app database for
    /// `messageAppIdentifier`. Does *not* throw on missing-message (that's the returned value);
    /// reserved for Core Data errors during the fetch itself.
    private func receivedMessageExistsInAppDatabase(messageAppIdentifier: ObvMessageAppIdentifier) async throws -> Bool {
        try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<Bool, any Error>, context: NSManagedObjectContext) in
            let exists = try PersistedMessage.getMessage(messageAppIdentifier: messageAppIdentifier, within: context) is PersistedMessageReceived
            continuation.resume(returning: exists)
        }
    }

    
    private func sendUnprocessedMessage(messageSentPermanentID: MessageSentPermanentID,
                                        obvEngine: ObvEngine) async throws {
        let op1 = SendUnprocessedPersistedMessageSentOperation(
            messageSentPermanentID: messageSentPermanentID,
            alsoPostToOtherOwnedDevices: true,
            extendedPayloadProvider: nil,
            obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard !composedOp.isCancelled else {
            throw SendMessageError.couldNotSendMessage
        }
    }

    
    /// Reads the `PersistedMessageReceived` and returns `true` iff its
    /// `FyleMessageJoinWithStatus` relationship is non-empty (wiped joins are not filtered out —
    /// a message whose attachments have all been wiped is still considered "has attachment" here).
    /// Throws if the message cannot be found.
    private func receivedMessageHasAttachments(messageAppIdentifier: ObvMessageAppIdentifier) async throws -> Bool {
        try await withCheckedThrowingContextualContinuation { continuation, context in
            guard let receivedMessage = try PersistedMessage.getMessage(messageAppIdentifier: messageAppIdentifier, within: context) as? PersistedMessageReceived else {
                continuation.resume(throwing: MarkMessageAsReadError.failed)
                return
            }
            continuation.resume(returning: !receivedMessage.fyleMessageJoinWithStatuses.isEmpty)
        }
    }


    /// Removes any delivered user notification whose `userInfo` carries our `messageAppIdentifier`.
    /// Lookup goes through the typed `messageAppIdentifier` accessor from `ObvUserNotificationsContent`,
    /// so the underlying userInfo key remains a single source of truth in that module. Touching the
    /// `PersistedUserNotification` table is unnecessary: the source of truth for what is on screen is
    /// the notification centre.
    private func removeDeliveredUserNotification(messageAppIdentifier: ObvMessageAppIdentifier) async {
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        let identifiersToRemove = delivered.compactMap { notification -> String? in
            guard notification.request.content.messageAppIdentifier == messageAppIdentifier else { return nil }
            return notification.request.identifier
        }
        guard !identifiersToRemove.isEmpty else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiersToRemove)
    }


    /// Recomputes the unread-driven app badge from Core Data and applies it via
    /// `UNUserNotificationCenter.setBadgeCount` (iOS 16+, extension-safe). We do this from the
    /// extension itself because the main app's `UserNotificationsBadgesManager` is not guaranteed
    /// to be running when Siri triggers a mark-as-read.
    private func refreshAppBadge() async {
        do {
            let newBadgeValue: Int = try await withCheckedThrowingContextualContinuation { continuation, context in
                let value = try PersistedObvOwnedIdentity.computeAppBadgeValue(within: context)
                continuation.resume(returning: value)
            }
            UNUserNotificationCenter.current().setBadgeCount(newBadgeValue) { error in
                if let error {
                    Self.logger.error("✅ Failed to set app badge: \(error.localizedDescription)")
                }
            }
        } catch {
            Self.logger.error("✅ Could not refresh app badge: \(error.localizedDescription)")
        }
    }

}


// MARK: - Composition helpers

extension IntentCoordinator {
    
    private func createCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(
        op1: ContextualOperationWithSpecificReasonForCancel<T>
    ) -> CompositionOfOneContextualOperation<T> {
        let composedOp = CompositionOfOneContextualOperation(
            op1: op1,
            contextCreator: ObvStack.shared,
            queueForComposedOperations: Self.queueForComposedOperations,
            log: Self.log,
            flowId: FlowIdentifier())
        composedOp.completionBlock = { [weak composedOp] in
            composedOp?.logReasonIfCancelled(log: Self.log)
        }
        return composedOp
    }


    private func createCompositionOfTwoContextualOperation<T1: LocalizedErrorWithLogType,
                                                           T2: LocalizedErrorWithLogType>(
        op1: ContextualOperationWithSpecificReasonForCancel<T1>,
        op2: ContextualOperationWithSpecificReasonForCancel<T2>
    ) -> CompositionOfTwoContextualOperations<T1, T2> {
        let composedOp = CompositionOfTwoContextualOperations(
            op1: op1,
            op2: op2,
            contextCreator: ObvStack.shared,
            queueForComposedOperations: Self.queueForComposedOperations,
            log: Self.log,
            flowId: FlowIdentifier())
        composedOp.completionBlock = { [weak composedOp] in
            composedOp?.logReasonIfCancelled(log: Self.log)
        }
        return composedOp
    }

}
