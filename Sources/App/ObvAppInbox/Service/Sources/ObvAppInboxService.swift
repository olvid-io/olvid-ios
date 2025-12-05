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
import ObvTypes
import ObvAppInboxDatabase
import ObvAppInboxTypes
import OlvidUtils
import ObvAppCoreConstants
import ObvAppTypes
import ObvCrypto


public final class ObvAppInboxService {
    
    private let coordinatorsQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        queue.name = "AppCoordinatorsQueue"
        return queue
    }()
    
    let queueForComposedOperations: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Queue for composed operations"
        queue.qualityOfService = .userInteractive
        return queue
    }()
    
    /// Old database items are deleted after two days.
    private static let ttlOfDatabaseItems = TimeInterval(days: 2)

    static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ObvAppInboxService.self))
    static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ObvAppInboxService.self))
 
    public init() {}
    
}

// MARK: - Public API for return receipts

extension ObvAppInboxService {
    
    public func storeForLater(encryptedReceivedReturnReceipt: ObvEncryptedReceivedReturnReceipt) async throws {
        
        let op1 = StoreEncryptedReceivedReturnReceiptForLaterOperation(encryptedReceivedReturnReceipt: encryptedReceivedReturnReceipt)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            let reason = composedOp.reasonForCancel
            Self.logger.fault("Could not store ObvEncryptedReceivedReturnReceipt for later: \(reason.debugDescription)")
            assertionFailure()
            throw ObvError.couldNotStoreObvEncryptedReceivedReturnReceiptForLater
        }
        
    }

    
    public func fetchEncryptedReceivedReturnReceiptStoredForLater(ownedCryptoId: ObvCryptoId, nonce: Data) async throws -> [(receipt: ObvEncryptedReceivedReturnReceipt, identifier: ObvPersistedEncryptedReceivedReturnReceiptID)] {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[(receipt: ObvEncryptedReceivedReturnReceipt, identifier: ObvPersistedEncryptedReceivedReturnReceiptID)], any Error>) in
            ObvAppInboxStack.shared.performBackgroundTask { context in
                do {
                    let encryptedReceivedReturnReceipts = try PersistedEncryptedReceivedReturnReceipt.getPersistedEncryptedReceivedReturnReceipts(ownedCryptoId: ownedCryptoId, nonce: nonce, within: context)
                    return continuation.resume(returning: encryptedReceivedReturnReceipts)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    public func deleteEncryptedReceivedReturnReceiptStoredForLater(identifier: ObvPersistedEncryptedReceivedReturnReceiptID) async {
     
        let op1 = DeleteEncryptedReceivedReturnReceiptForLaterOperation(identifier: identifier)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            let reason = composedOp.reasonForCancel
            Self.logger.fault("Could not delete ObvEncryptedReceivedReturnReceipt for later: \(reason.debugDescription)")
            assertionFailure()
            return
        }
        
    }
    
    
    public func fetchEncryptedReceivedReturnReceiptStoredForLaterAboutToBeDeleted(now: Date) async throws -> [(receipt: ObvEncryptedReceivedReturnReceipt, identifier: ObvPersistedEncryptedReceivedReturnReceiptID)] {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[(receipt: ObvEncryptedReceivedReturnReceipt, identifier: ObvPersistedEncryptedReceivedReturnReceiptID)], any Error>) in
            ObvAppInboxStack.shared.performBackgroundTask { context in
                do {
                    let date = Date(timeInterval: -Self.ttlOfDatabaseItems, since: now)
                    assert(date < Date.now)
                    let encryptedReceivedReturnReceipts = try PersistedEncryptedReceivedReturnReceipt.getPersistedEncryptedReceivedReturnReceipts(createdBefore: date, within: context)
                    return continuation.resume(returning: encryptedReceivedReturnReceipts)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    
    public func deleteOldEncryptedReceivedReturnReceiptStoredForLater(now: Date) async {
        
        let date = Date(timeInterval: -Self.ttlOfDatabaseItems, since: now)

        let op1 = BatchDeleteOldEncryptedReceivedReturnReceiptStoredForLaterOperation(createdBefore: date)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            let reason = composedOp.reasonForCancel
            Self.logger.fault("Could not batch delete old ObvEncryptedReceivedReturnReceipt for later: \(reason.debugDescription)")
            assertionFailure()
            return
        }
        
    }
    
    
}

// MARK: - Public API for ObvMessages to put onHold within the engine when expecting an active discussion

extension ObvAppInboxService {
    
    /// When the `PersistedDiscussionsUpdatesCoordinator` receives an `ObvMessage` or `ObvOwnedMessage`, the corresponding discussion might not exist yet.
    /// This scenario can occur, for example, when a message is received in a group that hasn't been created yet because the protocol manager hasn't processed the necessary protocol messages.
    /// In such cases, this method is invoked to store the message identifier. The `PersistedDiscussionsUpdatesCoordinator` then notifies the engine to prevent it from being notified about this message again.
    ///
    /// Once the discussion is eventually created, the `PersistedDiscussionsUpdatesCoordinator` calls the
    /// `fetchMessageIdentifiersForLater(identifierOfExpectedDiscussion:)` method from this `ObvAppInboxService` to retrieve the stored message identifiers.
    ///
    /// Note that the process of storing the message identifier and notifying the engine are non-atomic.
    /// As a result, the `PersistedDiscussionsUpdatesCoordinator` might be called twice with the same message,
    /// causing this method to be invoked multiple times with the same message identifier.
    /// To handle this, the method simply returns if the identifier already exists.
    public func storeOrReplaceMessageIdentifierForLater(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, identifierOfExpectedDiscussion: ObvDiscussionIdentifier) async throws {
        
        let op1 = StoreOrReplaceMessageIdentifierForLaterOperation(
            messageUIDFromEngine: messageUIDFromEngine,
            messageUploadTimestampFromServer: messageUploadTimestampFromServer,
            expected: .discussion(identifierOfExpectedDiscussion: identifierOfExpectedDiscussion))
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            let reason = composedOp.reasonForCancel
            Self.logger.fault("Could not store message identifier for later: \(reason.debugDescription)")
            assertionFailure()
            return
        }

    }
    
    public func fetchMessageIdentifiersForLater(identifierOfExpectedDiscussion: ObvDiscussionIdentifier) async -> [ObvMessageIdentifier] {

        let op1 = FetchMessageIdentifiersForLaterOperation(expected: .discussion(identifierOfExpectedDiscussion: identifierOfExpectedDiscussion))
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard let messageIdentifiers = op1.messageIdentifiers else {
            let reason = composedOp.reasonForCancel
            Self.logger.fault("Could not fetch message identifiers stored for later: \(reason.debugDescription)")
            assertionFailure()
            return []
        }

        return messageIdentifiers
        
    }

}


// MARK: - Public API for ObvMessages to put onHold within the engine when expecting a group

extension ObvAppInboxService {
    
    public func storeOrReplaceMessageIdentifierForLater(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, identifierOfExpectedGroup: ObvGroupIdentifier, cryptoIdOfExpectedContact: ObvCryptoId) async throws {
        
        let op1 = StoreOrReplaceMessageIdentifierForLaterOperation(
            messageUIDFromEngine: messageUIDFromEngine,
            messageUploadTimestampFromServer: messageUploadTimestampFromServer,
            expected: .contactInGroup(identifierOfExpectedGroup: identifierOfExpectedGroup,
                                      cryptoIdOfExpectedContact: cryptoIdOfExpectedContact))
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            let reason = composedOp.reasonForCancel
            Self.logger.fault("Could not store message identifier for later: \(reason.debugDescription)")
            assertionFailure()
            return
        }

    }
    
    
    public func fetchMessageIdentifiersForLater(identifierOfExpectedGroup: ObvGroupIdentifier, cryptoIdOfExpectedContact: ObvCryptoId?) async -> [ObvMessageIdentifier] {

        let op1 = FetchMessageIdentifiersForLaterOperation(
            expected: .contactInGroup(identifierOfExpectedGroup: identifierOfExpectedGroup, cryptoIdOfExpectedContact: cryptoIdOfExpectedContact)
        )
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard let messageIdentifiers = op1.messageIdentifiers else {
            let reason = composedOp.reasonForCancel
            Self.logger.fault("Could not fetch message identifiers stored for later: \(reason.debugDescription)")
            assertionFailure()
            return []
        }

        return messageIdentifiers
        
    }

}

// MARK: - Public API for ObvMessages to put onHold within the engine when expecting a message

extension ObvAppInboxService {
    
    public func storeOrReplaceMessageIdentifierForLater(messageUIDFromEngine: UID, messageUploadTimestampFromServer: Date, identifierOfExpectedMessage: ObvMessageAppIdentifier) async throws {
        
        let op1 = StoreOrReplaceMessageIdentifierForLaterOperation(
            messageUIDFromEngine: messageUIDFromEngine,
            messageUploadTimestampFromServer: messageUploadTimestampFromServer,
            expected: .message(messageIdentifier: identifierOfExpectedMessage))
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            let reason = composedOp.reasonForCancel
            Self.logger.fault("Could not store message identifier for later: \(reason.debugDescription)")
            assertionFailure()
            return
        }

    }

    
    public func fetchMessageIdentifiersForLater(identifierOfExpectedMessage: ObvMessageAppIdentifier) async -> [ObvMessageIdentifier] {

        let op1 = FetchMessageIdentifiersForLaterOperation(expected: .message(messageIdentifier: identifierOfExpectedMessage))
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard let messageIdentifiers = op1.messageIdentifiers else {
            let reason = composedOp.reasonForCancel
            Self.logger.fault("Could not fetch message identifiers stored for later: \(reason.debugDescription)")
            assertionFailure()
            return []
        }

        return messageIdentifiers
        
    }

}


// MARK: - Public APIs when syncing message identifiers saved for later that expect a discussion, group member, or message

extension ObvAppInboxService {
    
    public func getAllExpectedDiscussionIdentifiers() async throws -> [ObvDiscussionIdentifier] {

        let op1 = GetAllExpectedDiscussionIdentifiersOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard let allExpectedDiscussionIdentifiers = op1.allExpectedDiscussionIdentifiers else {
            let reason = composedOp.reasonForCancel
            Self.logger.fault("Could not fetch identifiers of all expected discussions: \(reason.debugDescription)")
            assertionFailure()
            return []
        }

        return allExpectedDiscussionIdentifiers
        
    }

    public func getAllExpectedGroupMembersIdentifiers() async throws -> [ObvGroupMemberIdentifier] {

        let op1 = GetAllExpectedGroupMembersIdentifiersOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard let allExpectedDiscussionAndContactIdentifiers = op1.allExpectedDiscussionAndContactIdentifiers else {
            let reason = composedOp.reasonForCancel
            Self.logger.fault("Could not fetch identifiers of all expected discussions group members: \(reason.debugDescription)")
            assertionFailure()
            return []
        }

        return allExpectedDiscussionAndContactIdentifiers

    }

    // ok
    public func getAllExpectedMessageIdentifiers() async throws -> [ObvMessageAppIdentifier] {
        
        let op1 = GetAllExpectedMessageIdentifiersOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard let allExpectedMessageIdentifiers = op1.allExpectedMessageIdentifiers else {
            let reason = composedOp.reasonForCancel
            Self.logger.fault("Could not fetch identifiers of all expected messages: \(reason.debugDescription)")
            assertionFailure()
            return []
        }

        return allExpectedMessageIdentifiers

    }

}


// MARK: - Other public APIs for ObvMessages to put onHold within the engine

extension ObvAppInboxService {
    
    public func deleteMessageIdentifiersForLater(messageId: ObvMessageIdentifier) async {
        
        let op1 = DeleteMessageIdentifiersForLaterOperation(input: .messageId(messageId))
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            let reason = composedOp.reasonForCancel
            Self.logger.fault("Could not delete message identifier saved for later: \(reason.debugDescription)")
            assertionFailure()
            return
        }

    }
 
    
    /// Called when an owned identity is deleted
    public func deleteMessageIdentifiersForLater(ownedCryptoId: ObvCryptoId) async {
        
        let op1 = DeleteMessageIdentifiersForLaterOperation(input: .ownedCryptoId(ownedCryptoId))
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            let reason = composedOp.reasonForCancel
            Self.logger.fault("Could not delete message identifier saved for later: \(reason.debugDescription)")
            assertionFailure()
            return
        }

    }

    /// When a non-truncated listing is performed by the fetch manager, the app is notified and this method is called. This allows to set
    /// the `timestampOfFirstNonTruncatedListingAfterInsertion` for all `MessageIdentifierForLater` that still
    /// have a `nil` value for this attribute. After a certain TTL, entries that have a non-nil value for that attribute are deleted.
    public func setTimestampOfFirstNonTruncatedListingAfterInsertion(ownedCryptoId: ObvCryptoId) async {
        
        let op1 = SetTimestampOfFirstNonTruncatedListingAfterInsertionOperation(ownedCryptoId: ownedCryptoId)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            let reason = composedOp.reasonForCancel
            Self.logger.fault("Could not set timestamp of first non truncated listing after insertion: \(reason.debugDescription)")
            assertionFailure()
            return
        }

    }
    
    
    public func fetchObsoleteMessageIdentifiersForLater(ownedCryptoId: ObvCryptoId) async -> [ObvMessageIdentifier] {
        
        let op1 = FetchObsoleteMessageIdentifiersForLaterOperation(ownedCryptoId: ownedCryptoId)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard let obsoleteMessageIdentifiers = op1.obsoleteMessageIdentifiers else {
            let reason = composedOp.reasonForCancel
            Self.logger.fault("Could not set timestamp of first non truncated listing after insertion: \(reason.debugDescription)")
            assertionFailure()
            return []
        }

        return obsoleteMessageIdentifiers
        
    }
    
}


// MARK: - Errors

extension ObvAppInboxService {
    
    enum ObvError: Error {
        case couldNotStoreObvEncryptedReceivedReturnReceiptForLater
    }
    
}



// MARK: - Creating compositions of contextual operations

extension ObvAppInboxService {
    
    func createCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>) -> CompositionOfOneContextualOperation<T> {
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvAppInboxStack.shared, queueForComposedOperations: queueForComposedOperations, log: Self.log, flowId: FlowIdentifier())
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: Self.log)
        }
        return composedOp
    }
    
}
