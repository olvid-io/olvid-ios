/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OSLog
import CoreData
import OlvidUtils
import ObvUICoreData
import ObvAppCoreConstants
import ObvEngine
import ObvTypes
import ObvAppInboxTypes
import ObvAppInboxService


/// Manages all modifications to message and attachment recipient information, ensuring thread-safe and efficient updates across the application.
final class RecipientInfosCoordinator: OlvidCoordinator {
    
    static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem,
                               category: String(describing: RecipientInfosCoordinator.self))
    static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem,
                           category: String(describing: RecipientInfosCoordinator.self))

    let obvEngine: ObvEngine

    let coordinatorsQueue: OperationQueue
    let queueForComposedOperations: OperationQueue
    let queueForSyncHintsComputationOperation: OperationQueue

    private var observationTokens = [NSObjectProtocol]()

    private let receivedReturnReceiptScheduler = ReceivedReturnReceiptScheduler()

    /// Allows to keep receipts for later, when they are received before the concerned message (which happens when the message is sent from another owned device).
    /// Also allows to keep ObvMessage and ObvOwnedMessage for later, marking them as onHold at the engine level.
    private let appInboxService: ObvAppInboxService

    private let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier)

    init(obvEngine: ObvEngine,
         appInboxService: ObvAppInboxService,
         coordinatorsQueue: OperationQueue,
         queueForComposedOperations: OperationQueue,
         queueForSyncHintsComputationOperation: OperationQueue) {
        self.obvEngine = obvEngine
        self.appInboxService = appInboxService
        self.coordinatorsQueue = coordinatorsQueue
        self.queueForComposedOperations = queueForComposedOperations
        self.queueForSyncHintsComputationOperation = queueForSyncHintsComputationOperation
        listenToNotifications()
        receiveAsyncStreamOfEncryptedReceivedReturnReceipt()
    }

    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    
    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        
        if forTheFirstTime {
            await updateLegacyStatusesOfSentMessagesIfRequired()
            await deleteRecipientInfosThatHaveNoMsgIdentifierFromEngineAndAssociatedToDeletedContact()
            await processThenDeleteOldEncryptedReturnedReceiptsStoredForLater()
        }
        
    }
    
    
    private func listenToNotifications() {
        observationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeMessageWasAcknowledged(within: NotificationCenter.default) { [weak self] (ownedIdentity, messageIdentifierFromEngine, timestampFromServer, isAppMessageWithUserContent, isVoipMessage) in
                Task { [weak self] in
                    await self?.processMessageWasAcknowledgedNotification(
                        ownedIdentity: ownedIdentity,
                        messageIdentifierFromEngine: messageIdentifierFromEngine,
                        timestampFromServer: timestampFromServer,
                        isAppMessageWithUserContent: isAppMessageWithUserContent,
                        isVoipMessage: isVoipMessage)
                }
            },
            ObvEngineNotificationNew.observeOutboxMessagesAndAllTheirAttachmentsWereAcknowledged(within: NotificationCenter.default) { [weak self] messageIdsAndTimestampsFromServer in
                Task { [weak self] in
                    await self?.processOutboxMessagesAndAllTheirAttachmentsWereAcknowledgedNotification(
                        messageIdsAndTimestampsFromServer: messageIdsAndTimestampsFromServer)
                }
            },
            ObvEngineNotificationNew.observeAttachmentWasAcknowledgedByServer(within: NotificationCenter.default) { [weak self] (ownedCryptoId, messageIdentifierFromEngine, attachmentNumber) in
                Task { [weak self] in await
                    self?.processAttachmentWasAcknowledgedByServerNotification(
                        ownedCryptoId: ownedCryptoId,
                        messageIdentifierFromEngine: messageIdentifierFromEngine,
                        attachmentNumber: attachmentNumber)
                }
            },
            ObvEngineNotificationNew.observeOutboxMessageCouldNotBeSentToServer(within: NotificationCenter.default) { [weak self] (messageIdentifierFromEngine, ownedCryptoId) in
                Task { [weak self] in
                    await self?.processOutboxMessageCouldNotBeSentToServer(
                        messageIdentifierFromEngine: messageIdentifierFromEngine,
                        ownedCryptoId: ownedCryptoId)
                }
            },
            ObvEngineNotificationNew.observeContactWasDeleted(within: NotificationCenter.default) { [weak self] (ownedCryptoId, contactCryptoId) in
                Task { [weak self] in
                    await self?.processContactWasDeletedNotification(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
                }
            },
        ])
    }
    
}


// MARK: - Receiving an async stream of return receipts from the engine

extension RecipientInfosCoordinator {
    
    private func receiveAsyncStreamOfEncryptedReceivedReturnReceipt() {
        Task {
            do {
                let stream = try await obvEngine.getAsyncStreamOfEncryptedReceivedReturnReceipt()
                for await encryptedReceivedReturnReceipt in stream {
                    Self.logger.debug("🧾 Received encrypted received return receipt")
                    await processNewEncryptedReturnReceipt(encryptedReceivedReturnReceipt: encryptedReceivedReturnReceipt, source: .engine)
                }
                assertionFailure("Make sure it is ok for the stream to finish")
            } catch {
                assertionFailure()
                Self.logger.fault("Could not obtain stream of received return receipts")
            }
        }
    }
     
}



// MARK: - Processing user's calls, relayed by the RootViewController

extension RecipientInfosCoordinator {
    
    /// Called when a user views details of a sent message in a discussion.
    /// Checks for any stored receipts "saved for later" related to this message and processes them if found.
    func userWantsToProcessReceiptsStoredForLater(ownedCryptoId: ObvCryptoId, returnReceiptElements: Set<ObvReturnReceiptElements>) async {
        for elements in returnReceiptElements {
            await decryptAndProcessReceiptsStoredForLater(ownedCryptoId: ownedCryptoId, elements: elements)
        }
    }

}


// MARK: -

extension RecipientInfosCoordinator {
    
    /// Fetches and attempts to decrypt stored encrypted return receipts that were "saved for later" using the provided nonce and decryption key.
    /// Processes all successfully decrypted return receipts.
    ///
    /// Also called from the `AppCoordinatorsHolder` when storing a 'sent'  message (sent from another owned device).
    func decryptAndProcessReceiptsStoredForLater(ownedCryptoId: ObvCryptoId, elements: ObvReturnReceiptElements) async {
        
        let decryptedReceivedReturnReceiptsAndIDs: [(receipt: ObvDecryptedReceivedReturnReceipt, identifier: ObvPersistedEncryptedReceivedReturnReceiptID)]
        do {
            decryptedReceivedReturnReceiptsAndIDs = try await decryptEncryptedReceiptsStoredForLater(ownedCryptoId: ownedCryptoId, elements: elements)
        } catch {
            Self.logger.fault("Could not fetch/decrypt encrypted receipts stored for later: \(error)")
            assertionFailure()
            return
        }
        
        for decryptedReceivedReturnReceiptAndID in decryptedReceivedReturnReceiptsAndIDs {
            let decryptedReceivedReturnReceipt = decryptedReceivedReturnReceiptAndID.receipt
            let identifier = decryptedReceivedReturnReceiptAndID.identifier
            await processDecryptedReturnReceipt(decryptedReceivedReturnReceipt: decryptedReceivedReturnReceipt, source: .appInboxService(identifier: identifier))
        }

    }
    
    
    private func decryptEncryptedReceiptsStoredForLater(ownedCryptoId: ObvCryptoId, elements: ObvReturnReceiptElements) async throws -> [(receipt: ObvDecryptedReceivedReturnReceipt, identifier: ObvPersistedEncryptedReceivedReturnReceiptID)] {
        
        var decryptedReceivedReturnReceipts = [(receipt: ObvDecryptedReceivedReturnReceipt, identifier: ObvPersistedEncryptedReceivedReturnReceiptID)]()
                
        let encryptedReceiptsAndIDsStoredForLater = try await self.appInboxService.fetchEncryptedReceivedReturnReceiptStoredForLater(ownedCryptoId: ownedCryptoId, nonce: elements.nonce)
        
        for encryptedReceiptAndIDStoredForLater in encryptedReceiptsAndIDsStoredForLater {
            let encryptedReceivedReturnReceipt = encryptedReceiptAndIDStoredForLater.receipt
            if let decryptedReceivedReturnReceipt = try obvEngine.decryptPayloadOfObvReturnReceipt(encryptedReceivedReturnReceipt, decryptionKeyCandidates: [elements.key]) {
                let identifier = encryptedReceiptAndIDStoredForLater.identifier
                decryptedReceivedReturnReceipts.append((decryptedReceivedReturnReceipt, identifier))
            }
        }
        
        decryptedReceivedReturnReceipts.sort(by: \.receipt.timestamp)
        
        return decryptedReceivedReturnReceipts
        
    }

    
}

// MARK: -

extension RecipientInfosCoordinator {
    
    /// If the network manager fails to send a message during 30 days, it deletes the outbos message and sends a notification that we catch here.
    private func processOutboxMessageCouldNotBeSentToServer(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId) async {
        var retryIteration = 0
        var success = false

        while !success && retryIteration < 10 {
            retryIteration += 1
            do {
                let result = try await computeChangesRequiredToProcessOutboxMessageCouldNotBeSentToServer(
                    ownedCryptoId: ownedCryptoId,
                    messageIdentifierFromEngine: messageIdentifierFromEngine)
                switch result {
                case .contextHasNoChanges:
                    success = true
                case .contextHasChanges(contextToSave: let contextToSave):
                    try await self.saveChanges(contextToSave: contextToSave)
                    success = true
                }
            } catch {
                Self.logger.warning("🧾 Failed to process the outbox message that could not be sent to the server during iteration \(retryIteration + 1): \(error)")
            }
        }
        
        if success {
            Self.logger.debug("🧾 Did successfully process the outbox message that could not be sent to the server")
        } else {
            Self.logger.error("🧾 Failed to process the outbox message that could not be sent to the server after 10 iterations")
            assertionFailure()
        }
        
    }
    
    
    private func computeChangesRequiredToProcessOutboxMessageCouldNotBeSentToServer(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data) async throws -> ContextualContinuationResult {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<ContextualContinuationResult, any Error>, context) in
            try PersistedMessageSentRecipientInfos.markSentMessageAsCouldNotBeSentToServer(
                ownedCryptoId: ownedCryptoId,
                messageIdentifierFromEngine: messageIdentifierFromEngine,
                within: context)
            return context.hasChanges ? continuation.resume(returning: .contextHasChanges(contextToSave: context)) : continuation.resume(returning: .contextHasNoChanges)
        }
    }
    
}


// MARK: -

extension RecipientInfosCoordinator {
    
    private func processAttachmentWasAcknowledgedByServerNotification(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int) async {
        
        var retryIteration = 0
        var success = false
        
        while !success && retryIteration < 10 {
            retryIteration += 1
            do {
                let result = try await self.computeChangesRequiredToProcessAttachmentWasAcknowledgedByServerNotification(
                    ownedCryptoId: ownedCryptoId,
                    messageIdentifierFromEngine: messageIdentifierFromEngine,
                    attachmentNumber: attachmentNumber)
                switch result {
                case .contextHasNoChanges:
                    success = true
                case .contextHasChanges(contextToSave: let contextToSave):
                    try await self.saveChanges(contextToSave: contextToSave)
                    success = true
                }
            } catch {
                Self.logger.warning("🧾 Failed to process the message that was acknowledged by the server during iteration \(retryIteration + 1): \(error)")
            }
        }
        
        if success {
            Self.logger.debug("🧾 Did process a message that was acknowledged by the server")
        } else {
            Self.logger.error("🧾 Failed to process a message that was acknowledged by the server")
            assertionFailure()
        }
        
    }

    
    /// Helper method for `processAttachmentWasAcknowledgedByServerNotification(ownedCryptoId:messageIdentifierFromEngine:attachmentNumber:)`
    private func computeChangesRequiredToProcessAttachmentWasAcknowledgedByServerNotification(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int) async throws -> ContextualContinuationResult {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<ContextualContinuationResult, any Error>, context: NSManagedObjectContext) in
            
            try PersistedMessageSentRecipientInfos.markSentFyleMessageJoinWithStatusAsFullyUploadedByCurrentDevice(
                ownedCryptoId: ownedCryptoId,
                messageIdentifierFromEngineAndAttachmentNumbersToRestrictTo: [(messageIdentifierFromEngine, restrictToAttachmentNumbers: [attachmentNumber])],
                within: context)
            
            try PersistedMessageSentRecipientInfos.setTimestampAllAttachmentsSentIfPossibleOfPersistedMessageSentRecipientInfos(
                ownedCryptoId: ownedCryptoId,
                messageIdentifiersFromEngine: [messageIdentifierFromEngine],
                within: context)
            
            return context.hasChanges ? continuation.resume(returning: .contextHasChanges(contextToSave: context)) : continuation.resume(returning: .contextHasNoChanges)

        }
    }
    
}


// MARK: -

extension RecipientInfosCoordinator {
    
    /// The OutboxMessagesAndAllTheirAttachmentsWereAcknowledged notification is sent during the bootstrap of the engine, when replaying the list of deleted outbox messages, so as to make sure the app didn't miss any important notification.
    /// It is sent for each deleted outbox message, that exist when the message has been fully sent to the server (unless they were cancelled by the user by deleting the message).
    private func processOutboxMessagesAndAllTheirAttachmentsWereAcknowledgedNotification(messageIdsAndTimestampsFromServer: [(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, timestampFromServer: Date)]) async {
        
        // We need to deal with the case where we receive a huge list of messageIds. To do so, we proceed by batches.
        
        let allSortedIdsAndTimestamps = messageIdsAndTimestampsFromServer.sorted { $0.timestampFromServer < $1.timestampFromServer }
        let batchSize = 50
        
        for index in stride(from: 0, to: allSortedIdsAndTimestamps.count, by: batchSize) {
            
            let batch = allSortedIdsAndTimestamps[index..<min(allSortedIdsAndTimestamps.count, index+batchSize)]
            
            // Each batch is treated on a per owned identity basis
            
            let batchPerOwnedIdentity = Dictionary(grouping: batch, by: { $0.ownedCryptoId })
            
            for (ownedCryptoId, idsAndTimestamps) in batchPerOwnedIdentity {
                
                var retryIteration = 0
                var success = false
                
                while !success && retryIteration < 10 {
                    
                    retryIteration += 1
                    
                    do {
                        
                        let result = try await computeChangesRequiredToProcessOutboxMessagesAndAllTheirAttachmentsWereAcknowledgedNotification(
                            ownedCryptoId: ownedCryptoId,
                            idsAndTimestamps: idsAndTimestamps)
                        
                        switch result {
                        case .contextHasNoChanges:
                            success = true
                        case .contextHasChanges(let contextToSave):
                            try await self.saveChanges(contextToSave: contextToSave)
                            success = true
                        }
                        
                    } catch {
                        
                        Self.logger.warning("🧾 Failed to process the outbox messages and all their attachments were acknowledged notification during the \(retryIteration+1): \(error)")
                        continue // loop
                        
                    }
                    
                }
                
                if success {
                    Self.logger.debug("🧾 Did process batch of outbox messages and all their attachments that were acknowledged")
                } else {
                    Self.logger.error("🧾 Failed to process batch of outbox messages and all their attachments that were acknowledged")
                    assertionFailure()
                }
                
            }
            
            // If the batch is properly processed, we notify the engine (even if the composed operation cancelled)
            
            guard let maxTimestampFromServer = batch.last?.timestampFromServer else { assertionFailure(); return }
            Task { [weak self] in await self?.obvEngine.deleteHistoryConcerningTheAcknowledgementOfOutboxMessages(withTimestampFromServerEarlierOrEqualTo: maxTimestampFromServer) }
            
        }

    }
    
    
    /// Helper method for `processOutboxMessagesAndAllTheirAttachmentsWereAcknowledgedNotification(messageIdsAndTimestampsFromServer:)`
    private func computeChangesRequiredToProcessOutboxMessagesAndAllTheirAttachmentsWereAcknowledgedNotification(
        ownedCryptoId: ObvCryptoId,
        idsAndTimestamps: [(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, timestampFromServer: Date)]) async throws -> ContextualContinuationResult {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<ContextualContinuationResult, any Error>, context: NSManagedObjectContext) in

            try PersistedMessageSentRecipientInfos.markMessageWasSentNoLaterThan(
                ownedCryptoId: ownedCryptoId,
                messageIdentifierFromEngineAndTimestampFromServer: idsAndTimestamps.map { ($0.messageIdentifierFromEngine, $0.timestampFromServer) },
                alsoMarkAttachmentsAsSent: true,
                within: context)

            try PersistedMessageSentRecipientInfos.markSentFyleMessageJoinWithStatusAsFullyUploadedByCurrentDevice(
                ownedCryptoId: ownedCryptoId,
                messageIdentifierFromEngineAndAttachmentNumbersToRestrictTo: idsAndTimestamps.map { ($0.messageIdentifierFromEngine, nil) },
                within: context)

            try PersistedMessageSentRecipientInfos.setTimestampAllAttachmentsSentIfPossibleOfPersistedMessageSentRecipientInfos(
                ownedCryptoId: ownedCryptoId,
                messageIdentifiersFromEngine: idsAndTimestamps.map { $0.messageIdentifierFromEngine },
                within: context)

            return context.hasChanges ? continuation.resume(returning: .contextHasChanges(contextToSave: context)) : continuation.resume(returning: .contextHasNoChanges)

        }

    }

}


// MARK: -

extension RecipientInfosCoordinator {
    
    /// Deletes old encrypted return receipts stored in the app inbox.
    /// Before deletion, ensures that these receipts cannot be processed.
    /// Receipts are deleted regardless of the processing outcome.
    private func processThenDeleteOldEncryptedReturnedReceiptsStoredForLater() async {
        let now = Date.now
        // If there are old receipts to process, do it now before they are deleted
        do {
            let encryptedReceiptsAndIDsStoredForLater = try await appInboxService.fetchEncryptedReceivedReturnReceiptStoredForLaterAboutToBeDeleted(now: now)
            for encryptedReceiptAndID in encryptedReceiptsAndIDsStoredForLater {
                await processNewEncryptedReturnReceipt(encryptedReceivedReturnReceipt: encryptedReceiptAndID.receipt, source: .appInboxService(identifier: encryptedReceiptAndID.identifier))
            }
            await appInboxService.deleteOldEncryptedReceivedReturnReceiptStoredForLater(now: now)
        } catch {
            await appInboxService.deleteOldEncryptedReceivedReturnReceiptStoredForLater(now: now)
            assertionFailure()
        }
        // Delete old receipts
        await appInboxService.deleteOldEncryptedReceivedReturnReceiptStoredForLater(now: now)
    }
    
    
    private func processNewEncryptedReturnReceipt(encryptedReceivedReturnReceipt: ObvEncryptedReceivedReturnReceipt, source: ReturnReceiptSource) async {
        
        let obvEngine = self.obvEngine

        // Try to decrypt the received encrypted return receipt.
        
        let decryptedReceivedReturnReceipt: ObvDecryptedReceivedReturnReceipt? = try? await self.decryptReceivedReturnReceipt(encryptedReceivedReturnReceipt: encryptedReceivedReturnReceipt)
        
        guard let decryptedReceivedReturnReceipt else {
            // The receipt could not be decrypted. We probably are in the case where the our message was sent from another owned device.
            // Consequently, we store the encrypted receipt for later, when we are able to decrypt it (i.e., when receiving the message comming
            // from our other owned device).
            Self.logger.error("🧾 Could not decrypt the received encrypted return receipt")
            switch source {
            case .engine:
                Task {
                    do {
                        try await appInboxService.storeForLater(encryptedReceivedReturnReceipt: encryptedReceivedReturnReceipt)
                    } catch {
                        Self.logger.fault("Could not store the encrypted return receipt for later")
                        assertionFailure() // In production, we delete the receipt anyway
                    }
                    await obvEngine.deleteObvReturnReceipt(withServerUID: encryptedReceivedReturnReceipt.serverUid, ownedCryptoId: encryptedReceivedReturnReceipt.ownedCryptoId)
                }
            case .appInboxService:
                return
            }
            return
        }
        
        Self.logger.debug("🧾 Did decrypt the received encrypted return receipt")
        
        await processDecryptedReturnReceipt(decryptedReceivedReturnReceipt: decryptedReceivedReturnReceipt, source: .engine)

    }

    
    /// Helper method for `processNewEncryptedReturnReceipt(encryptedReceivedReturnReceipt:source:)`
    private func decryptReceivedReturnReceipt(encryptedReceivedReturnReceipt: ObvEncryptedReceivedReturnReceipt) async throws -> ObvDecryptedReceivedReturnReceipt? {
        let decryptionKeyCandidates = try await self.getDecryptionKeyCandidatesForReceivedReturnReceipt(encryptedReceivedReturnReceipt: encryptedReceivedReturnReceipt)
        let decryptedReceivedReturnReceipt = try obvEngine.decryptPayloadOfObvReturnReceipt(encryptedReceivedReturnReceipt, decryptionKeyCandidates: decryptionKeyCandidates)
        return decryptedReceivedReturnReceipt
    }

    
    /// Helper method for `decryptReceivedReturnReceipt(encryptedReceivedReturnReceipt:)`
    private func getDecryptionKeyCandidatesForReceivedReturnReceipt(encryptedReceivedReturnReceipt: ObvEncryptedReceivedReturnReceipt) async throws -> Set<Data> {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<Data>, any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let decryptionKeyCandidates = try PersistedMessageSentRecipientInfos.getDecryptionKeyCandidatesForReceivedReturnReceipt(
                        nonce: encryptedReceivedReturnReceipt.nonce,
                        ownedCryptoId: encryptedReceivedReturnReceipt.ownedCryptoId,
                        within: context)
                    return continuation.resume(returning: decryptionKeyCandidates)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }

}


// MARK: -

extension RecipientInfosCoordinator {
    
    private enum ReturnReceiptSource {
        case engine
        case appInboxService(identifier: ObvPersistedEncryptedReceivedReturnReceiptID)
    }
    

    /// This method is invoked in two scenarios:
    /// 1. Upon receiving and successfully decrypting an encrypted receipt from the engine, allowing it to be processed.
    /// 2. Upon receiving a message from another owned device, enabling the decryption of previously received encrypted receipts that were stored temporarily in the App Inbox.
    private func processDecryptedReturnReceipt(decryptedReceivedReturnReceipt: ObvDecryptedReceivedReturnReceipt, source: ReturnReceiptSource, retryNumber: Int = 0) async {
        
        // If we reach this point, we successfully decrypted the encrypted return receipt.
        // We will compute hints about the what we should do with it.
        
        // Note that since processing a return receipt is a two-step process (hints computing then, when appropriate, hints processing)
        // we want both steps to be atomic. This is ensured by the receivedReturnReceiptScheduler.
        
        guard retryNumber < 10 else {
            assertionFailure()
            Self.logger.warning("🧾 Failed to process decrypted return receipt. We delete it.")
            Task {
                await deleteReceipt(decryptedReceivedReturnReceipt: decryptedReceivedReturnReceipt, source: source)
            }
            return
        }
        
        await receivedReturnReceiptScheduler.waitForTurn()
        defer { Task { await receivedReturnReceiptScheduler.endOfTurn() } }
        
        do {
            let result = try await computeChangesRequiredToProcessDecryptedReturnReceipt(decryptedReceivedReturnReceipt: decryptedReceivedReturnReceipt)
            switch result {
            case .contextHasNoChanges:
                break
            case .contextHasChanges(let contextToSave):
                try await self.saveChanges(contextToSave: contextToSave)
            }
            // We are done with the return receipt
            Self.logger.debug("🧾 Successfully processed decrypted return receipt")
            Task { await deleteReceipt(decryptedReceivedReturnReceipt: decryptedReceivedReturnReceipt, source: source) }
        } catch {
            Self.logger.error("🧾 Failed to process decrypted return receipt during iteration \(retryNumber): \(error)")
            Task { await processDecryptedReturnReceipt(decryptedReceivedReturnReceipt: decryptedReceivedReturnReceipt, source: source, retryNumber: retryNumber + 1) }
            return
        }
        
    }

    
    /// Deletes a processed returned receipt. If the receipt originated from the engine, a deletion request is sent to the engine.
    /// If the receipt was temporarily stored in the app inbox, it is deleted from there.
    private func deleteReceipt(decryptedReceivedReturnReceipt: ObvDecryptedReceivedReturnReceipt, source: ReturnReceiptSource) async {
        switch source {
        case .engine:
            await obvEngine.deleteObvReturnReceipt(withServerUID: decryptedReceivedReturnReceipt.serverUID, ownedCryptoId: decryptedReceivedReturnReceipt.ownedCryptoId)
        case .appInboxService(identifier: let identifier):
            await appInboxService.deleteEncryptedReceivedReturnReceiptStoredForLater(identifier: identifier)
        }
    }

    
    /// Helper method for `processDecryptedReturnReceipt(decryptedReceivedReturnReceipt:source:retryNumber:)`
    ///
    /// When handling an encrypted return receipt, we first decrypt it and then execute this operation aiming at identifying necessary database modifications for accurate processing of the receipt.
    /// This operation can run on a separate queue from the coordinator's, as it does not alter the database. However, it provides instructions by returning an instance of
    /// `[ObvManagedObjectChanges]`. This list will be utilized in another operation to effectively manage the received return receipt and update the database.
    private func computeChangesRequiredToProcessDecryptedReturnReceipt(decryptedReceivedReturnReceipt: ObvDecryptedReceivedReturnReceipt) async throws -> ContextualContinuationResult {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<ContextualContinuationResult, any Error>, context: NSManagedObjectContext) in
            
            try PersistedMessageSentRecipientInfos.processDecryptedReceivedReturnReceipt(decryptedReceivedReturnReceipt: decryptedReceivedReturnReceipt, within: context)
            return context.hasChanges ? continuation.resume(returning: .contextHasChanges(contextToSave: context)) : continuation.resume(returning: .contextHasNoChanges)

        }
    }

}


// MARK: -

extension RecipientInfosCoordinator {
    
    private func processMessageWasAcknowledgedNotification(ownedIdentity: ObvCryptoId, messageIdentifierFromEngine: Data, timestampFromServer: Date, isAppMessageWithUserContent: Bool, isVoipMessage: Bool) async {
        
        if isAppMessageWithUserContent {

            var retryIteration = 0
            var success = false

            while !success && retryIteration < 10 {
                retryIteration += 1
                do {
                    let result = try await computeChangesRequiredToProcessMessageWasAcknowledgedNotification(ownedCryptoId: ownedIdentity, messageIdentifierFromEngine: messageIdentifierFromEngine, timestampFromServer: timestampFromServer)
                    switch result {
                    case .contextHasNoChanges:
                        success = true
                    case .contextHasChanges(let contextToSave):
                        try await self.saveChanges(contextToSave: contextToSave)
                        success = true
                    }
                } catch {
                    Self.logger.warning("🧾 Failed to process message was acknowledged notification during iteration \(retryIteration+1): \(error)")
                }
            }
            
            if success {
                Self.logger.debug("🧾 Did process message was acknowledged notification")
            } else {
                Self.logger.error("🧾 Failed to process message was acknowledged notification")
                assertionFailure()
            }
            
        }
        
        await obvEngine.deleteHistoryConcerningTheAcknowledgementOfOutboxMessage(
            messageIdentifierFromEngine:messageIdentifierFromEngine,
            ownedIdentity:ownedIdentity)
        
    }
    
    
    /// Helper method for `processMessageWasAcknowledgedNotification(ownedIdentity:messageIdentifierFromEngine:timestampFromServer:isAppMessageWithUserContent:isVoipMessage:)`
    private func computeChangesRequiredToProcessMessageWasAcknowledgedNotification(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, timestampFromServer: Date) async throws -> ContextualContinuationResult {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<ContextualContinuationResult, any Error>, context: NSManagedObjectContext) in
            try PersistedMessageSentRecipientInfos.markMessageWasSentNoLaterThan(
                ownedCryptoId: ownedCryptoId,
                messageIdentifierFromEngineAndTimestampFromServer: [(messageIdentifierFromEngine, timestampFromServer)],
                alsoMarkAttachmentsAsSent: true,
                within: context)
            return context.hasChanges ? continuation.resume(returning: .contextHasChanges(contextToSave: context)) : continuation.resume(returning: .contextHasNoChanges)
        }
    }
    
}


extension RecipientInfosCoordinator {
    
    /// When a contact is deleted, we look for all associated `PersistedMessageSentRecipientInfos` instance with no message identifier from engine and delete these instances.
    /// For each of these instances, we also recompute the status of the associated `PersistedMessageSent` (since the absence of a particular `PersistedMessageSentRecipientInfos`
    /// may have an influence on the result of the computation).
    ///
    /// Those `PersistedMessageSentRecipientInfos` instances are created when sending a message to this contact. In the case we have no channel
    /// with this contact at that point in time, the message won't be accepted by the engine
    /// and will prevent the message to be marked as sent. In practice, the user sees a "rabbit" that cannot go away. Deleting these instances and recomputing the `PersistedMessageSent`
    /// statues allow to prevent this bad user experience. Moreover, the message would never be sent anyway.
    private func processContactWasDeletedNotification(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId) async {
        
        var retryIteration = 0
        var success = false

        while !success && retryIteration < 10 {
            retryIteration += 1
            do {
                let contactIdentifier = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
                let result = try await computeChangesRequiredToDeletePersistedMessageSentRecipientInfosWithoutMessageIdentifierFromEngineAndAssociatedToContactIdentity(contactIdentifier: contactIdentifier)
                switch result {
                case .contextHasNoChanges:
                    success = true
                case .contextHasChanges(let contextToSave):
                    try await self.saveChanges(contextToSave: contextToSave)
                    success = true
                }
            } catch {
                Self.logger.warning("🧾 Failed to processContactWasDeletedNotification during iteration \(retryIteration+1): \(error)")
            }
        }
        
        if success {
            Self.logger.debug("🧾 Did processContactWasDeletedNotification successfully")
        } else {
            Self.logger.error("🧾 Did not processContactWasDeletedNotification after 10 iterations, giving up")
            assertionFailure()
        }
        
    }

    
    private func computeChangesRequiredToDeletePersistedMessageSentRecipientInfosWithoutMessageIdentifierFromEngineAndAssociatedToContactIdentity(contactIdentifier: ObvContactIdentifier) async throws -> ContextualContinuationResult {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<ContextualContinuationResult, any Error>, context: NSManagedObjectContext) in
            try PersistedMessageSentRecipientInfos.deletePersistedMessageSentRecipientInfosWithoutMessageIdentifierFromEngineAndAssociatedToContactIdentity(
                contactIdentifier: contactIdentifier,
                within: context)
            return context.hasChanges ? continuation.resume(returning: .contextHasChanges(contextToSave: context)) : continuation.resume(returning: .contextHasNoChanges)
        }
    }
    
}


extension RecipientInfosCoordinator {
    
    /// Update the legacy sent message statutes of previously sent messages to update them if required. This method also consolidates the timestamps in sent message infos as, before v3.1,
    /// we could end up in a situation where a sent info could have a non-nil delivered timestamp, with a nil sent timestamp (which makes no sense).
    private func updateLegacyStatusesOfSentMessagesIfRequired() async {

        guard let userDefaults else { assertionFailure(); return }

        // We only allow the commit of 50 changes at once per operation. This is to make sure that saving the Core Data context doesn't take too long.
        let maxNumberOfChanges = 50
                
        do {
            
            let userDefaultsKey = "BootstrapCoordinator.ConsolidateLegacyTimestampsOfPersistedMessageSentRecipientInfosOperation.wasFullyPerformed"
            defer {
                userDefaults.setValue(true, forKey: userDefaultsKey)
            }

            if userDefaults.value(forKey: userDefaultsKey) == nil {
                
                var operationDidSaveSomeChanges = true

                while operationDidSaveSomeChanges {
                    
                    let op1 = ConsolidateLegacyTimestampsOfPersistedMessageSentRecipientInfosOperation(maxNumberOfChanges: maxNumberOfChanges)
                    let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                    composedOp.queuePriority = .veryHigh
                    await coordinatorsQueue.addAndAwaitOperation(composedOp)
                    
                    guard op1.isFinished && !op1.isCancelled else {
                        assertionFailure()
                        return
                    }
                    
                    operationDidSaveSomeChanges = op1.didSaveSomeChanges
                    
                }
                
                userDefaults.setValue(true, forKey: userDefaultsKey)
                                
            }
            
        }
        
        do {
            
            let userDefaultsKey = "BootstrapCoordinator.UpdateLegacyStatusesOfSentMessagesOperation.wasFullyPerformed"
            defer {
                userDefaults.setValue(true, forKey: userDefaultsKey)
            }

            if userDefaults.value(forKey: userDefaultsKey) == nil {
                
                var operationDidSaveSomeChanges = true

                while operationDidSaveSomeChanges {
                    
                    let op1 = UpdateLegacyStatusesOfSentMessagesOperation(maxNumberOfChanges: maxNumberOfChanges)
                    let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                    composedOp.queuePriority = .veryHigh
                    await coordinatorsQueue.addAndAwaitOperation(composedOp)
                    
                    guard op1.isFinished && !op1.isCancelled else {
                        assertionFailure()
                        return
                    }
                    
                    operationDidSaveSomeChanges = op1.didSaveSomeChanges
                    
                }
                
                userDefaults.setValue(true, forKey: userDefaultsKey)
                
            }
            
        }
        
    }

}


extension RecipientInfosCoordinator {
    
    private func deleteRecipientInfosThatHaveNoMsgIdentifierFromEngineAndAssociatedToDeletedContact() async {
        var retryIteration = 0
        var success = false

        while !success && retryIteration < 10 {
            retryIteration += 1
            do {
                let result = try await computeChangesRequiredToDeleteRecipientInfosThatHaveNoMsgIdentifierFromEngineAndAssociatedToDeletedContact()
                switch result {
                case .contextHasNoChanges:
                    success = true
                case .contextHasChanges(let contextToSave):
                    try await self.saveChanges(contextToSave: contextToSave)
                    success = true
                }
            } catch {
                Self.logger.warning("🧾 Failed to delete recipient infos that have no msg identifier from the database during iteration \(retryIteration+1): \(error)")
            }
        }
        
        if success {
            Self.logger.debug("🧾 Did successfully delete recipient infos that have no msg identifier from the database")
        } else {
            Self.logger.error("🧾 Failed to delete recipient infos that have no msg identifier from the database")
            assertionFailure()
        }
        
    }
    
    
    private func computeChangesRequiredToDeleteRecipientInfosThatHaveNoMsgIdentifierFromEngineAndAssociatedToDeletedContact() async throws -> ContextualContinuationResult {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<ContextualContinuationResult, any Error>, context: NSManagedObjectContext) in
            try PersistedMessageSentRecipientInfos.deleteRecipientInfosThatHaveNoMsgIdentifierFromEngineAndAssociatedToDeletedContact(within: context)
            return context.hasChanges ? continuation.resume(returning: .contextHasChanges(contextToSave: context)) : continuation.resume(returning: .contextHasNoChanges)
        }
    }

}


// MARK: - Implementing ExpirationMessagesManagerDelegate

extension RecipientInfosCoordinator: ExpirationMessagesManagerDelegate {
    
    func wipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask: Bool) async throws {
        
        for _ in 0..<10 {
            do {
                let (contextToSave, infosForNotification) = try await self.computeChangesRequiredToWipeExpiredMessagesOperation()
                try await self.saveChanges(contextToSave: contextToSave)
                if !infosForNotification.isEmpty {
                    // We wiped/deleted some persisted messages. We notify about that.
                    InfoAboutWipedOrDeletedPersistedMessage.notifyThatMessagesWereWipedOrDeleted(infosForNotification)
                    // Refresh objects in the view context
                    InfoAboutWipedOrDeletedPersistedMessage.refresh(viewContext: ObvStack.shared.viewContext, infosForNotification)
                }
                return
            } catch {
                Self.logger.warning("🧾 Will retry to wipe messages that expired earlier than now: \(error)")
            }
        }
        
        assertionFailure()
        
    }
    
    
    /// Helper method for `wipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask:)`
    private func computeChangesRequiredToWipeExpiredMessagesOperation() async throws -> (context: NSManagedObjectContext, infosForNotification: [InfoAboutWipedOrDeletedPersistedMessage]) {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(context: NSManagedObjectContext, infosForNotification: [InfoAboutWipedOrDeletedPersistedMessage]), any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    
                    var infos = [InfoAboutWipedOrDeletedPersistedMessage]()
                    
                    // Deal with sent messages
                    
                    do {
                        let now = Date.now
                        let expiredMessages = try PersistedMessageSent.getSentMessagesThatExpired(before: now, within: context)
                        for message in expiredMessages {
                            if let expirationForSentLimitedExistence = message.expirationForSentLimitedExistence, expirationForSentLimitedExistence.expirationDate < now {
                                let info = try message.deleteExpiredMessage()
                                infos += [info]
                            } else if let expirationForSentLimitedVisibility = message.expirationForSentLimitedVisibility, expirationForSentLimitedVisibility.expirationDate < now {
                                do {
                                    let info = try message.wipeOrDeleteExpiredMessageSent()
                                    infos += [info]
                                } catch {
                                    Self.logger.fault("Could not wipe a message sent with expired visibility")
                                    assertionFailure()
                                    // Continue anyway
                                }
                            } else {
                                assertionFailure("A message that we fetched because it expired has not expiration before now. Weird.")
                            }
                        }
                    }
                    
                    // Deal with received messages
                    
                    do {
                        let expiredMessages = try PersistedMessageReceived.getReceivedMessagesThatExpired(within: context)
                        for message in expiredMessages {
                            let info = try message.deleteExpiredMessage()
                            infos += [info]
                        }
                    }
                    
                    return continuation.resume(returning: (context, infos))
                    
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
        
    }
    
}


// MARK: - Performing changes

extension RecipientInfosCoordinator {
    
    private func saveChanges(contextToSave: NSManagedObjectContext) async throws {
        let op = ObvSaveContextOperation(contextToSave: contextToSave)
        await self.coordinatorsQueue.addAndAwaitOperation(op)
        guard op.isFinished && !op.isCancelled else {
            throw ObvError.saveContextOperationCancelled
        }
    }
    
}


fileprivate final class ObvSaveContextOperation: OperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    let contextToSave: NSManagedObjectContext
    
    init(contextToSave: NSManagedObjectContext) {
        self.contextToSave = contextToSave
    }

    override func main() {
//        let signpostID = signposter.makeSignpostID()
//        let state = signposter.beginInterval("ObvSaveContextOperation", id: signpostID)
        contextToSave.performAndWait {
            do {
                guard contextToSave.hasChanges else {
//                    signposter.endInterval("ObvSaveContextOperation", state)
                    return
                }
                try contextToSave.save()
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
//            signposter.endInterval("ObvSaveContextOperation", state)
        }
    }
    
}


// MARK: - Errors

extension RecipientInfosCoordinator {
    
    enum ObvError: Error {
        case failedToPerformManagedObjectChangeOnQueueForProcessingReturnReceipts(reason: CoreDataOperationReasonForCancel?)
        case failedToPerformManagedObjectChangeOnCoordinatorsQueue(reason: CoreDataOperationReasonForCancel?)
        case saveContextOperationCancelled
    }
    
}


// MARK: - ReceivedReturnReceiptScheduler

/// This scheduler guarantees atomic processing of a received return receipt.
///
/// This scheduler guarantees atomic processing of a received return receipt by ensuring two sequential steps:
/// 1. determining required tasks for complete processing and
/// 2. applying these tasks based on previously processed return receipts.
///
/// The atomic nature of this group of two operations prevents discrepancies in the process, thus maintaining data consistency.
fileprivate actor ReceivedReturnReceiptScheduler {
    
    private var continuationsOfWaitingReceipts = [CheckedContinuation<Void, Never>]()
    private var isProcessingReceipt = false
    
    func waitForTurn() async {
        
        if isProcessingReceipt {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if isProcessingReceipt {
                    continuationsOfWaitingReceipts.insert(continuation, at: 0)
                } else {
                    isProcessingReceipt = true
                    continuation.resume()
                }
            }
        } else {
            isProcessingReceipt = true
        }
        
    }
    
    func endOfTurn() {
        if let continuation = continuationsOfWaitingReceipts.popLast() {
            continuation.resume()
        } else {
            isProcessingReceipt = false
        }
    }
    
}
