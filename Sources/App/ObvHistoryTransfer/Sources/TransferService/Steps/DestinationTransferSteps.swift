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
import OSLog
import ObvTypes
import ObvAppTypes
import ObvCrypto
import CryptoKit
import ObvAppCoreConstants


public protocol DestinationTransferStepsDataSource: AnyObject, Sendable {
    func filterKnownAndCompleteFyles(_ actor: DestinationTransferSteps, sha256s: [Data]) async throws -> [Data]
    func filterKnownMessages(_ actor: DestinationTransferSteps, discussionIdentifier: ObvDiscussionIdentifier, messagesAvailableOnSource: [ObvMessageAppIdentifier]) async throws -> [ObvMessageAppIdentifier]
}


public protocol DestinationTransferStepsActions: AnyObject, Sendable {
    
    func historyTransferRequiresToStoreSourcesMessagesOnThisDestination(
        _ actor: DestinationTransferSteps,
        messagesToStore: [ObvHistoryReceivedMessage]
    ) async throws -> (sha256ToRequestToSource: [Data : UInt64], sha256NotToBeRequestedToSource: Set<Data>)
    
    func historyTransferRequiresToStoreAttachmentOnThisDestination(
        _ actor: DestinationTransferSteps,
        sha256: Data,
        temporaryURLOfAttachment: URL,
    ) async throws
    
}

protocol TransferTransportSendJsonMessageDelegateForDestination: AnyObject, Sendable {
    func receiveSrcDiscussionList() async throws -> SrcDiscussionList
    func receiveSrcDiscussionRanges(expectedDiscussionIdentifiers: [JsonDiscussionIdentifier]) async throws -> AsyncThrowingStream<SrcDiscussionRanges, Error>
    func send(dstExpectedSha256: DstExpectedSha256) async throws
    func send(dstDiscussionExpectedRanges: DstDiscussionExpectedRanges) async throws
    func receiveStreamOfSrcMessages(numberOfExpectedMessages: Int) async throws -> AsyncThrowingStream<SrcMessages, Error>
    func send(dstRequestSha256: DstRequestSha256, expectedFileSize: UInt64, progressUpdater: any FyleProgressUpdater) async throws -> URL
    func send(dstDoNotRequestSha256: DstDoNotRequestSha256) async throws
}

public actor DestinationTransferSteps {
    
    private let ownedCryptoId: ObvCryptoId
    private weak var dataSource: (any DestinationTransferStepsDataSource)?
    private weak var transferTransportDelegate: (any TransferTransportSendJsonMessageDelegateForDestination)?
    private weak var actions: (any DestinationTransferStepsActions)?
    
    deinit {
        debugPrint("Deinit")
    }

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "DestinationTransferSteps")
    
    private var currentStepTask: Task<Void, Error>?

    /// To request an attachment from the source, we create an internal subtask. To make it possible to cancel this subtask when cancelling the step task,
    /// we keep a reference to the currently executing subtask.
    private var currentStepSubTask: Task<(receivedAndSavedAttachmentSha256s: [Data], failedAttachmentSha256s: [Data]), any Error>?
    
    private let progressReportingHelper = ImportProgressReportingHelper()

    init(ownedCryptoId: ObvCryptoId,
         dataSource: any DestinationTransferStepsDataSource,
         transferTransportDelegate: any TransferTransportSendJsonMessageDelegateForDestination,
         actions: any DestinationTransferStepsActions) {
        self.ownedCryptoId = ownedCryptoId
        self.dataSource = dataSource
        self.transferTransportDelegate = transferTransportDelegate
        self.actions = actions
    }
    
    var transferwasSuccessfullyCompleted: Bool {
        get async {
            await self.progressReportingHelper.transferwasSuccessfullyCompleted
        }
    }

    func execute() async throws -> AsyncStream<DestinationTransferStepsState> {
        guard self.currentStepTask == nil else {
            assertionFailure()
            throw ObvError.executeCannotBeCalledTwice
        }
        self.currentStepTask = createTask() // This launches the task performing all the import steps on this destination
        let stream = await self.progressReportingHelper.getStreamOfDestinationTransferStepsState()
        return stream
    }
    
    func resetAll() {
        self.currentStepTask?.cancel()
        self.currentStepTask = nil
        self.currentStepSubTask?.cancel()
        self.currentStepSubTask = nil
    }
    
    /// Used when the user cancels an import. This continuation allows to await until the task properly handled the cancelation request.
    private var continuationOnCancel: CheckedContinuation<Void, Never>?

    
    /// Called when the user explictely cancels the transfer. Returns `true` iff the transfer was successfully completed.
    func userWantsToCancelExport(requestedFromOtherDevice: Bool) async {
        resumeContinuationOnCancelIfRequired()
        if requestedFromOtherDevice {
            currentStepTask?.cancel()
            currentStepSubTask?.cancel()
            await self.progressReportingHelper.doneAndExportWasCancelledByUser()
        } else {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                resumeContinuationOnCancelIfRequired()
                guard let currentStepTask else { continuation.resume(); return }
                guard !currentStepTask.isCancelled else { continuation.resume(); return }
                self.continuationOnCancel = continuation
                currentStepTask.cancel()
                currentStepSubTask?.cancel()
            }
        }
    }
    
    
    private func resumeContinuationOnCancelIfRequired() {
        if let continuationOnCancel {
            self.continuationOnCancel = nil
            continuationOnCancel.resume()
        }
    }

    
    private func createTask() -> Task<Void, Error> {
        return Task(name: "DestinationTransferSteps.createTask") {
            
            defer {
                // Removing the pointer to the task allows to make it clear that the Task is finished.
                self.currentStepTask = nil
                // We may be waiting for this task to finish because it was cancelled. If this is the case,
                // we must resume the corresponding continuation now as this is our last chance to do so.
                self.resumeContinuationOnCancelIfRequired()
            }

            do {
                
                guard let dataSource else {
                    assertionFailure()
                    throw ObvError.dataSourceIsNil
                }
                
                guard let transferTransportDelegate else {
                    assertionFailure()
                    throw ObvError.transferTransportDelegateIsNil
                }
                
                guard let actions else {
                    assertionFailure()
                    throw ObvError.actionsAreNil
                }
                
                // Receive the first messages sent by the source are received
                
                await self.progressReportingHelper.receiveSrcDiscussionListInProgress()

                let srcDiscussionList = try await transferTransportDelegate.receiveSrcDiscussionList()
                
                await self.progressReportingHelper.receiveSrcDiscussionListDone(
                    numberOfDiscussionsAvailableOnSource: srcDiscussionList.numberOfDiscussionsAvailableOnSource,
                    numberOfFylesAvailableOnSource: srcDiscussionList.numberOfFylesAvailableOnSource,
                    totalByteCountAvailableOnSource: srcDiscussionList.totalByteCountAvailableOnSource)
                
                // We store the discussions and sha256s available on the source
                
                let discussionsAvailableOnSource = srcDiscussionList.discussions
                let sha256sAvailableOnSource = srcDiscussionList.sha256s
                
                // Among the sha256s available on the source, determine those that are known/complete as well on this
                // destination device. Use this to compute the sha256s of the file to request to the source.
                // Send the list of expected sha256s back to the source
                
                await self.progressReportingHelper.negotiatingWhatToReceiveInProgress()

                let knownSha256: [Data] = try await dataSource.filterKnownAndCompleteFyles(self, sha256s: [Data](sha256sAvailableOnSource.keys))
                let expectedSha256: [Data: UInt64] = sha256sAvailableOnSource.filter { availableOnSource in
                    let sha256AvailableOnThisDestination = knownSha256.contains(where: { $0 == availableOnSource.key })
                    return !sha256AvailableOnThisDestination
                }
                
                let messageToSend = DstExpectedSha256(sha256s: expectedSha256)
                try await transferTransportDelegate.send(dstExpectedSha256: messageToSend)
                
                // Receive one SrcDiscussionRanges per discussion, a send one DstDiscussionExpectedRanges for each
                
                let streamOfSrcDiscussionRanges = try await transferTransportDelegate.receiveSrcDiscussionRanges(expectedDiscussionIdentifiers: discussionsAvailableOnSource)
                
                var receivedSrcDiscussionTitles = [JsonDiscussionIdentifier: String]()
                var allExpectedMessages = Set<ObvMessageAppIdentifier>()
                for try await srcDiscussionRange in streamOfSrcDiscussionRanges {
                    
                    receivedSrcDiscussionTitles[srcDiscussionRange.discussionIdentifier] = srcDiscussionRange.discussionTitle
                    
                    let discussionIdentifier = try srcDiscussionRange.discussionIdentifier.getDiscussionIdentifier(ownedCryptoId: ownedCryptoId)
                    let messagesAvailableOnSource: [ObvMessageAppIdentifier] = JsonMessagesHelpers.messageIdentifiers(discussionIdentifier: discussionIdentifier, rangesByThreadAndSender: srcDiscussionRange.rangesByThreadAndSender)
                    
                    let knownMessages = try await dataSource.filterKnownMessages(self, discussionIdentifier: discussionIdentifier, messagesAvailableOnSource: messagesAvailableOnSource)
                    let expectedMessages = Set(messagesAvailableOnSource).subtracting(knownMessages)
                    
                    let messageToSend = try DstDiscussionExpectedRanges(
                        discussionIdentifier: discussionIdentifier,
                        messageIdentifiers: [ObvMessageAppIdentifier](expectedMessages))
                    
                    try await transferTransportDelegate.send(dstDiscussionExpectedRanges: messageToSend)
                    
                    allExpectedMessages.formUnion(expectedMessages)
                    
                }
                
                await self.progressReportingHelper.negotiatingWhatToReceiveDone(
                    numberOfMessagesToTransfer: allExpectedMessages.count,
                    expectedSha256: expectedSha256)
                
                // Receive the messages and store them.
                
                Self.logger.debug("📰 Will receive a stream of \(allExpectedMessages.count) messages from the source")
                
                if !allExpectedMessages.isEmpty {
                    await self.progressReportingHelper.receivingMessagesStarting()
                }
                
                let streamOfSrcMessages = try await transferTransportDelegate.receiveStreamOfSrcMessages(numberOfExpectedMessages: allExpectedMessages.count)
                
                var missingMessageCount = 0
                var allReceivedAndFailedFilesTasks = [Task<(receivedAndSavedAttachmentSha256s: [Data], failedAttachmentSha256s: [Data]), Error>]()
                var allNotToBeRequestedFilesTasks = [Task<Void, any Error>]()
                var alreadyRequestedSha256 = Set<Data>() // Allows to avoid requesting the same sha256 twice if present in two distinct message
                for try await srcMessages in streamOfSrcMessages {
                    missingMessageCount += srcMessages.missingMessageCount
                    let suggestedDiscussionTitle = receivedSrcDiscussionTitles[srcMessages.discussionIdentifier]
                    let messagesToStore = try computeMessagesToStore(srcMessages: srcMessages, ownedCryptoId: ownedCryptoId, suggestedDiscussionTitle: suggestedDiscussionTitle)
                    Self.logger.info("📰 Did receive \(messagesToStore.count) messages from the source, we now store them")
                    let sha256RequiredByStoredMessages: [Data : UInt64]
                    var sha256NotRequiredByStoredMessages: Set<Data>
                    if Set(messagesToStore.map(\.messageIdentifier)).isSubset(of: allExpectedMessages) {
                        (sha256RequiredByStoredMessages, sha256NotRequiredByStoredMessages) = try await actions.historyTransferRequiresToStoreSourcesMessagesOnThisDestination(self, messagesToStore: messagesToStore)
                    } else {
                        Self.logger.error("📰 We received messages that we did not request")
                        assertionFailure()
                        let requestedAmongMessagesToStore = messagesToStore.filter({ allExpectedMessages.contains($0.messageIdentifier) })
                        (sha256RequiredByStoredMessages, sha256NotRequiredByStoredMessages) = try await actions.historyTransferRequiresToStoreSourcesMessagesOnThisDestination(self, messagesToStore: requestedAmongMessagesToStore)
                    }
                    let sha256ToRequestToSource: [Data : UInt64] = sha256RequiredByStoredMessages.filter { expectedSha256.keys.contains($0.key) }
                    let sha256ToIndicateAsNotRequiredToSource: Set<Data> = sha256NotRequiredByStoredMessages.filter { expectedSha256.keys.contains($0) }
                    
                    await self.progressReportingHelper.receivingMessagesInProgress(
                        partialReceivedMessageCount: messagesToStore.count,
                        partialMissingMessageCount: srcMessages.missingMessageCount)
                    
                    // The source messages were saved to database and we now know about the sha256 we need to request to the source (and those that we don't need).
                    // We request these sha256 and, for each one, receive a file URL in return (that needs to be move to and appropriate location by the data source).
                    // Since we don't want to block the stream of messages, we do so asynchronously (but keep a handle that will make it possible to eventually await the end of the attachments transfer)
                    
                    do {
                        let sha256NotYetRequested = sha256ToRequestToSource.filter({ !alreadyRequestedSha256.contains($0.key) })
                        alreadyRequestedSha256.formUnion(sha256NotYetRequested.map(\.key))
                        let task = self.requestAttachmentsToSourceTask(sha256s: sha256NotYetRequested, transferTransportDelegate: transferTransportDelegate, actions: actions)
                        allReceivedAndFailedFilesTasks.append(task)
                    }
                    do {
                        let sha256NotYetCommunicated = sha256ToIndicateAsNotRequiredToSource.filter({ !alreadyRequestedSha256.contains($0) })
                        alreadyRequestedSha256.formUnion(sha256NotYetCommunicated)
                        let task = self.indicateAttachmentNotRequiredToSourceTask(sha256s: sha256NotYetCommunicated, transferTransportDelegate: transferTransportDelegate)
                        allNotToBeRequestedFilesTasks.append(task)
                    }
                    
                }
                
                Self.logger.info("📰 Did exit the stream of messages from the source")
                
                // Wait until all the attachments tasks are done
                
                for task in allReceivedAndFailedFilesTasks {

                    assert(self.currentStepSubTask == nil)
                    self.currentStepSubTask = task
                    let (receivedAndSavedAttachmentSha256s, failedAttachmentSha256s) = try await task.value
                    self.currentStepSubTask = nil
                    
                    await self.progressReportingHelper.receivingAttachmentsInProgress(
                        receivedAndSavedAttachmentSha256s: receivedAndSavedAttachmentSha256s,
                        failedAttachmentSha256s: failedAttachmentSha256s)
                    
                }
                for task in allNotToBeRequestedFilesTasks {
                    try await task.value
                }
                
                // We might still have attachments to request to the source. This happens, e.g., in the case the source has a message with an attachment, and the destination has the same message but with a "still to be transferred" attachment.
                // In this case, the message was not transferred (as it was already known to the destination), but the attachment still needs to be requested.
                
                do {
                    let sha256NotYetRequested = expectedSha256.filter({ !alreadyRequestedSha256.contains($0.key) })
                    let task = self.requestAttachmentsToSourceTask(sha256s: sha256NotYetRequested, transferTransportDelegate: transferTransportDelegate, actions: actions)
                    
                    assert(self.currentStepSubTask == nil)
                    self.currentStepSubTask = task
                    let (receivedAndSavedAttachmentSha256s, failedAttachmentSha256s) = try await task.value
                    self.currentStepSubTask = nil

                    await self.progressReportingHelper.receivingAttachmentsInProgress(
                        receivedAndSavedAttachmentSha256s: receivedAndSavedAttachmentSha256s,
                        failedAttachmentSha256s: failedAttachmentSha256s)
                }
                
                await self.progressReportingHelper.doneAndExportWasSuccessful()

                Self.logger.info("📰✅ We successfully reached the end of the DestinationTransferSteps")
                
            } catch {
                                
                if error is CancellationError {
                    Self.logger.info("📰🛑 Destination transfer step task was cancelled. We do not propagate the error.")
                    await self.progressReportingHelper.doneAndExportWasCancelledByUser()
                } else if let error = error as? TransferTransportDelegateError {
                    Self.logger.error("📰 Destination transfer step task throwed: \(error.localizedDescription).")
                    switch error {
                    case .transferTransportDelegateFailed:
                        await self.progressReportingHelper.doneAndExportFailed()
                    case .ownedCryptoIdDoesNotMatch:
                        await self.progressReportingHelper.doneAndExportFailedAsIdentitiesDidNotMatch()
                    }
                    throw error
                } else {
                    Self.logger.error("📰 Destination transfer step task throwed: \(error.localizedDescription)")
                    await self.progressReportingHelper.doneAndExportFailed()
                    throw error
                }

                
            }
            
        }
            
    }
    
    
    private enum AttachmentResult {
        case receivedAndSaved(sha256: Data)
        case failedToReceiveOrSave(sha256: Data)
    }
    
    
        
}


//MARK: - Errors

extension DestinationTransferSteps {
    
    enum ObvError: Error {
        case expectingEmptyStateButFoundNonEmptyState
        case dataSourceIsNil
        case transferTransportDelegateIsNil
        case couldNotComputeDeterministicUID
        case unexpectedMessageKind
        case actionsAreNil
        case executeCannotBeCalledTwice
    }
    
}


// MARK: - Private helpers for attachments

extension DestinationTransferSteps {
    
    private func requestAttachmentsToSourceTask(
        sha256s: [Data: UInt64],
        transferTransportDelegate: any TransferTransportSendJsonMessageDelegateForDestination,
        actions: (any DestinationTransferStepsActions)
    ) -> Task<(receivedAndSavedAttachmentSha256s: [Data], failedAttachmentSha256s: [Data]), Error> {
        
        return Task {
            try await withThrowingTaskGroup(of: AttachmentResult.self, returning: (receivedAndSavedAttachmentSha256s: [Data], failedAttachmentSha256s: [Data]).self) { group in
                
                for (sha256, expectedFileSize) in sha256s {
                    await self.progressReportingHelper.receivingAttachmentsStarting() // May be called multiple times, but notifies only once
                    group.addTask {
                        do {
                            let tempURL = try await transferTransportDelegate.send(
                                dstRequestSha256: .init(sha256: sha256),
                                expectedFileSize: expectedFileSize,
                                progressUpdater: self.progressReportingHelper)
                            try await actions.historyTransferRequiresToStoreAttachmentOnThisDestination(self, sha256: sha256, temporaryURLOfAttachment: tempURL)
                            try? FileManager.default.removeItem(at: tempURL)
                            return .receivedAndSaved(sha256: sha256)
                        } catch {
                            if error is CancellationError {
                                throw error
                            } else if let error = error as? TransferTransportDelegateError {
                                switch error {
                                case .transferTransportDelegateFailed:
                                    throw error
                                case .ownedCryptoIdDoesNotMatch:
                                    throw error
                                }
                            } else {
                                return .failedToReceiveOrSave(sha256: sha256)
                            }
                        }
                    }
                }
                
                var receivedAndSavedAttachmentSha256s = [Data]()
                var failedAttachmentSha256s = [Data]()
                
                for try await result in group {
                    switch result {
                    case .receivedAndSaved(sha256: let sha256):
                        receivedAndSavedAttachmentSha256s.append(sha256)
                    case .failedToReceiveOrSave(sha256: let sha256):
                        failedAttachmentSha256s.append(sha256)
                    }
                }
                
                assert(sha256s.count == receivedAndSavedAttachmentSha256s.count + failedAttachmentSha256s.count)
                assert(Set(sha256s.map(\.key)) == Set(receivedAndSavedAttachmentSha256s).union(failedAttachmentSha256s))
                
                return (receivedAndSavedAttachmentSha256s, failedAttachmentSha256s)
                
            }
        }
        
    }
    
    
    private func indicateAttachmentNotRequiredToSourceTask(sha256s: Set<Data>, transferTransportDelegate: any TransferTransportSendJsonMessageDelegateForDestination) -> Task<Void, Error> {
        return Task {
            try await withThrowingTaskGroup(of: Void.self, returning: Void.self) { group in
                for sha256 in sha256s {
                    await self.progressReportingHelper.receivingAttachmentsStarting() // May be called multiple times, but notifies only once
                    group.addTask {
                        try await transferTransportDelegate.send(dstDoNotRequestSha256: .init(sha256: sha256))
                    }
                }
                // Wait until all dstDoNotRequestSha256 are sent
                for try await _ in group {
                }
            }
        }
    }
    
}


// MARK: - Private helpers


extension DestinationTransferSteps {
    
    private func computeMessagesToStore(srcMessages: SrcMessages, ownedCryptoId: ObvCryptoId, suggestedDiscussionTitle: String?) throws -> [ObvHistoryReceivedMessage] {
        let discussionIdentifier = try srcMessages.discussionIdentifier.getDiscussionIdentifier(ownedCryptoId: ownedCryptoId)
        let sender = srcMessages.sender
        let threadId = srcMessages.threadId
        let messagesToStore: [ObvHistoryReceivedMessage] = try srcMessages.messages.map { jsonMessageInThread in
            try ObvHistoryReceivedMessage(
                discussionIdentifier: discussionIdentifier,
                sender: sender,
                threadId: threadId,
                jsonMessageInThread: jsonMessageInThread,
                suggestedDiscussionTitle: suggestedDiscussionTitle)
        }
        return messagesToStore
    }
    
}


private extension ObvHistoryReceivedMessage {
    
    init(discussionIdentifier: ObvDiscussionIdentifier,
         sender: ObvCryptoId,
         threadId: UUID,
         jsonMessageInThread: JsonMessageInThread,
         suggestedDiscussionTitle: String?
    ) throws {
        
        let kind = try ObvHistoryReceivedMessage.Kind(
            discussionIdentifier: discussionIdentifier,
            sender: sender,
            threadId: threadId,
            senderSequenceNumber: jsonMessageInThread.senderSequenceNumber,
            kind: jsonMessageInThread.kind)
        
        self.init(kind: kind,
                  messageIdentifierFromEngine: .init(jsonMessageInThread.messageIdentifierFromEngine),
                  timestamp: jsonMessageInThread.timestamp,
                  bodyAndMentions: jsonMessageInThread.bodyAndMentions,
                  replyTo: jsonMessageInThread.replyTo,
                  expirationLimitedExistence: jsonMessageInThread.expirationLimitedExistence,
                  forwarded: jsonMessageInThread.forwarded,
                  edited: jsonMessageInThread.edited,
                  location: jsonMessageInThread.location,
                  poll: jsonMessageInThread.poll,
                  reactions: jsonMessageInThread.reactions.map({ .init($0) }),
                  pollVotes: jsonMessageInThread.pollVotes.map({ .init($0) }),
                  attachments: jsonMessageInThread.attachments.map({ .init($0) }),
                  suggestedDiscussionTitle: suggestedDiscussionTitle)

    }
    
}


private extension ObvHistoryReceivedMessage.Attachment {
    
    init(_ attachment: JsonAttachment) {
        self.init(sha256: attachment.sha256,
                  number: attachment.number,
                  size: attachment.size,
                  mimeType: attachment.mimeType,
                  filename: attachment.filename)
    }
    
}


private extension ObvHistoryReceivedMessage.PollVote {
    
    init(_ vote: JsonPollVoteForMessage) {
        self.init(candidate: vote.candidate,
                  voted: vote.voted,
                  version: vote.version,
                  sender: vote.sender,
                  timestamp: vote.timestamp)
    }
    
}


private extension ObvHistoryReceivedMessage.Reaction {
    
    init(_ reaction: JsonReactionToMessage) {
        self.init(emoji: reaction.emoji,
                  sender: reaction.sender,
                  timestamp: reaction.timestamp)
    }
    
}


private extension ObvHistoryReceivedMessage.UidFromServer {
    
    init(_ messageIdentifierFromEngine: JsonMessageInThread.UidFromServer) {
        switch messageIdentifierFromEngine {
        case .unknown: self = .unknown
        case .known(let data): self = .known(data)
        }
    }
    
}


private extension ObvHistoryReceivedMessage.Kind {
    
    init(discussionIdentifier: ObvDiscussionIdentifier, sender: ObvCryptoId, threadId: UUID, senderSequenceNumber: Int, kind: JsonMessageInThread.Kind) throws {
        
        if sender.getIdentity() == discussionIdentifier.ownedCryptoId.getIdentity() {
            
            let messageIdentifier = ObvMessageSentAppIdentifier(
                discussionIdentifier: discussionIdentifier,
                senderThreadIdentifier: threadId,
                senderSequenceNumber: senderSequenceNumber)
            let status: JsonMessageInThread.Kind.SentMessageStatus
            switch kind {
            case .sent(let _status):
                status = _status
            case .received:
                assertionFailure()
                throw DestinationTransferSteps.ObvError.unexpectedMessageKind
            }
            self = .sent(messageIdentifier: messageIdentifier,
                         status: .init(status: status))
            
        } else {
            
            switch kind {
            case .sent:
                assertionFailure()
                throw DestinationTransferSteps.ObvError.unexpectedMessageKind
            case .received:
                break
            }
            let messageIdentifier = ObvMessageReceivedAppIdentifier(
                discussionIdentifier: discussionIdentifier,
                senderIdentifier: sender.getIdentity(),
                senderThreadIdentifier: threadId,
                senderSequenceNumber: senderSequenceNumber)
            self = .received(messageIdentifier: messageIdentifier)
            
        }
    }
    
}


private extension ObvHistoryReceivedMessage.Kind.SentMessageStatus {
    
    init(status: JsonMessageInThread.Kind.SentMessageStatus) {
        switch status {
        case .sentFromAnotherOwnedDevice: self = .sentFromAnotherOwnedDevice
        case .sent: self = .sent
        case .partiallyDeliveredNotRead: self = .partiallyDeliveredNotRead
        case .partiallyDeliveredAndPartiallyRead: self = .partiallyDeliveredAndPartiallyRead
        case .couldNotBeSentToOneOrMoreRecipients: self = .couldNotBeSentToOneOrMoreRecipients
        case .fullyDeliveredAndNotRead: self = .fullyDeliveredAndNotRead
        case .fullyDeliveredAndPartiallyRead: self = .fullyDeliveredAndPartiallyRead
        case .fullyDeliveredAndFullyRead: self = .fullyDeliveredAndFullyRead
        }
    }
    
}


// MARK: - Progress reporting

private actor ImportProgressReportingHelper: FyleProgressUpdater {
    
    private var continuationForProgressReporting: AsyncStream<DestinationTransferStepsState>.Continuation?
    private var bufferOfDestinationTransferStepsState = [DestinationTransferStepsState]()

    private var numberOfDiscussionsAvailableOnSource: Int? // Once set, this does not change
    private var numberOfFylesAvailableOnSource: Int? // Once set, this does not change
    private var totalByteCountAvailableOnSource: UInt64? // Once set, this does not change
    
    deinit {
        debugPrint("Deinit")
    }
    
    /// Represents all the Fyles we expect to be receiving from the source
    ///
    /// The represented fyles are missing from this destination device and we expect them to be transferred.
    /// Once set, this does not change
    private var fylesToReceive: [Data : (received: UInt64, over: UInt64)]?
    
    /// Number of fyles to transfer.
    ///
    /// This number is necessarily less or equal to `numberOfFylesAvailableOnSource`.
    private var numberOfFylesToReceive: Int? { fylesToReceive?.count }
    
    /// Total byte count of fyles to transfer.
    ///
    /// This number is necessarily less or equal to `totalByteCountAvailableOnSource`.
    private var byteCountToReceive: UInt64? { fylesToReceive?.reduce(0, { $0 + $1.value.over }) }
    
    /// The number of bytes received so far.
    ///
    /// Expected to be less or equal to `byteCountToReceive`.
    private var byteCountReceived: UInt64? { fylesToReceive?.values.map({ $0.received }).reduce(0, +) }
    
    /// The number of attachments received so far.
    ///
    /// Expected to be less or equal to `numberOfFylesToReceive`.
    private var receivedFylesCount: Int? { fylesToReceive?.values.count(where: { $0.received >= $0.over }) }

    /// Represents the receiving message progress
    ///
    /// - `received` is the number of received messages until now
    /// - `missing` is the number of missing messages on the source (e.g., messages that were deleted during the transfer, after the negotiation)
    /// - `over` is the initial total number of messages to receive (once set, this value does not change)
    ///
    /// Eventually, we expect `received + missing == over`
    private var messagesToReceive: (received: Int, missing: Int, over: Int)?

    /// Sliding window used to compute the message receiving rate.
    ///
    /// Each entry records the timestamp and the number of messages received in that batch.
    /// Entries older than `messageRateWindowDuration` are pruned on each update.
    private var receivedMessageWindow: [(timestamp: Date, count: Int)] = []
    private static let messageRateWindowDuration: TimeInterval = 10.0
    
    private(set) var transferwasSuccessfullyCompleted: Bool = false

    /// Returns messages per second averaged over the sliding window, or `nil` if the window is too
    /// narrow to produce a meaningful estimate (fewer than 2 data points, or less than 1 second elapsed).
    private var messagesPerSecond: Double? {
        guard receivedMessageWindow.count >= 2 else { return nil }
        guard let first = receivedMessageWindow.first, let last = receivedMessageWindow.last else { return nil }
        let elapsed = last.timestamp.timeIntervalSince(first.timestamp)
        guard elapsed >= 1.0 else { return nil }
        return Double(receivedMessageWindow.reduce(0) { $0 + $1.count }) / elapsed
    }

    /// Sliding window used to compute the fyle byte-receiving rate.
    ///
    /// Each entry records the timestamp and the number of bytes received since the previous update (delta, not total).
    /// Entries older than `messageRateWindowDuration` are pruned on each update.
    private var receivedBytesWindow: [(timestamp: Date, byteCount: UInt64)] = []

    /// Returns bytes per second averaged over the sliding window, or `nil` if the window is too
    /// narrow to produce a meaningful estimate (fewer than 2 data points, or less than 1 second elapsed).
    private var bytesPerSecond: Double? {
        guard receivedBytesWindow.count >= 2 else { return nil }
        guard let first = receivedBytesWindow.first, let last = receivedBytesWindow.last else { return nil }
        let elapsed = last.timestamp.timeIntervalSince(first.timestamp)
        guard elapsed >= 1.0 else { return nil }
        return Double(receivedBytesWindow.reduce(0) { $0 + $1.byteCount }) / elapsed
    }

    private var receivingAttachmentsStartingWasNotified = false

    /// sha256s of fyles whose receiving failed. Used for deduplication and ETA correction.
    private var failedFyleSha256s: Set<Data> = []
    private var failedFylesCount: Int { failedFyleSha256s.count }
    /// Bytes from failed fyles that will never be received: `over - received` for each failed fyle.
    private var byteCountFailedToReceive: UInt64 {
        guard let fylesToReceive else { return 0 }
        return failedFyleSha256s.compactMap { fylesToReceive[$0] }.map { $0.over - $0.received }.reduce(0, +)
    }

    /// Runs every second while message/attachment receiving is active to prune stale window entries
    /// and re-report rates/ETAs even when no progress callbacks arrive.
    private var windowPruningTask: Task<Void, Never>?

    // Methods called by the destination transfer step task

    func getStreamOfDestinationTransferStepsState() -> AsyncStream<DestinationTransferStepsState> {
        assert(self.continuationForProgressReporting == nil)
        self.continuationForProgressReporting?.finish()
        let stream = AsyncStream<DestinationTransferStepsState> { (continuation: AsyncStream<DestinationTransferStepsState>.Continuation) in
            assert(self.continuationForProgressReporting == nil)
            self.continuationForProgressReporting?.finish()
            self.continuationForProgressReporting = continuation
            yieldAllBufferedTransferImportStatesIfPossible()
        }
        return stream
    }
    
    func receiveSrcDiscussionListInProgress() {
        self.reportNewProgressToView(state: .receivingDiscussionsList(status: .inProgress))
    }
    
    func receiveSrcDiscussionListDone(
        numberOfDiscussionsAvailableOnSource: Int,
        numberOfFylesAvailableOnSource: Int,
        totalByteCountAvailableOnSource: UInt64
    ) {
        self.numberOfDiscussionsAvailableOnSource = numberOfDiscussionsAvailableOnSource
        self.numberOfFylesAvailableOnSource = numberOfFylesAvailableOnSource
        self.totalByteCountAvailableOnSource = totalByteCountAvailableOnSource
        self.reportNewProgressToView(state: .receivingDiscussionsList(
            status: .done(numberOfDiscussionsAvailableOnSource: numberOfDiscussionsAvailableOnSource,
                          numberOfFylesAvailableOnSource: numberOfFylesAvailableOnSource,
                          totalByteCountAvailableOnSource: totalByteCountAvailableOnSource)))
    }
        
    func negotiatingWhatToReceiveInProgress() {
        reportNewProgressToView(state: .negotiatingWhatToReceive(status: .inProgress))
    }
    
    func negotiatingWhatToReceiveDone(numberOfMessagesToTransfer: Int, expectedSha256: [Data: UInt64]) {
        assert(self.messagesToReceive == nil)
        self.messagesToReceive = (received: 0, missing: 0, over: numberOfMessagesToTransfer)
        assert(self.fylesToReceive == nil)
        self.fylesToReceive = Dictionary(expectedSha256, keyMapping: { $0 }, valueMapping: { (received: 0, over: $0) })
        guard let numberOfFylesToReceive, let byteCountToReceive else { assertionFailure(); return }
        reportNewProgressToView(state: .negotiatingWhatToReceive(status: .done(
            numberOfMessagesToTransfer: numberOfMessagesToTransfer,
            numberOfFylesToTransfer: numberOfFylesToReceive,
            totalByteCountToTransfer: byteCountToReceive)))
    }
    
    func receivingMessagesStarting() {
        receivedMessageWindow = [] // Reset in case this is ever called more than once
        startWindowPruningTask()
        reportNewProgressToView(state: .receivingMessages(status: .starting))
    }

    func receivingMessagesInProgress(partialReceivedMessageCount: Int, partialMissingMessageCount: Int) {
        guard let prev = messagesToReceive else { assertionFailure(); return }
        self.messagesToReceive = (received: prev.received + partialReceivedMessageCount, missing: prev.missing + partialMissingMessageCount, over: prev.over)

        // Feed the sliding window: append the new batch, then drop entries that have fallen outside the window.
        let now = Date.now
        receivedMessageWindow.append((timestamp: now, count: partialReceivedMessageCount))
        receivedMessageWindow.removeAll { now.timeIntervalSince($0.timestamp) > Self.messageRateWindowDuration }

        reportCurrentReceivingMessagesInProgressState()
    }

    func receivingAttachmentsStarting() {
        guard !receivingAttachmentsStartingWasNotified else { return }
        defer { receivingAttachmentsStartingWasNotified = true }
        receivedBytesWindow = [] // Reset in case this is ever called more than once
        startWindowPruningTask() // No-op if already running (messages phase started it); starts it if messages were skipped
        reportNewProgressToView(state: .receivingAttachment(status: .starting))
    }

    func updateFyleProgress(sha256: Data, totalNumberOfFyleBytesSent: UInt64) async {
        guard let fylesToReceive else { assertionFailure(); return }
        guard let (previouslyReceived, over) = fylesToReceive[sha256] else { assertionFailure(); return }
        assert(previouslyReceived <= totalNumberOfFyleBytesSent)
        assert(totalNumberOfFyleBytesSent <= over)
        self.fylesToReceive?[sha256] = (totalNumberOfFyleBytesSent, over)

        // Feed the sliding window with the byte delta, then prune stale entries.
        let delta = totalNumberOfFyleBytesSent - previouslyReceived
        let now = Date.now
        receivedBytesWindow.append((timestamp: now, byteCount: delta))
        receivedBytesWindow.removeAll { now.timeIntervalSince($0.timestamp) > Self.messageRateWindowDuration }

        reportCurrentReceivingAttachmentsInProgressState()
    }

    func receivingAttachmentsInProgress(receivedAndSavedAttachmentSha256s: [Data], failedAttachmentSha256s: [Data]) {
        guard let fylesToReceive else { assertionFailure(); return }
        for sha256 in receivedAndSavedAttachmentSha256s {
            guard let (previouslyReceived, over) = fylesToReceive[sha256] else { assertionFailure(); continue }
            guard previouslyReceived < over else { continue }
            self.fylesToReceive?[sha256] = (over, over)
            reportCurrentReceivingAttachmentsInProgressState()
        }
        for sha256 in failedAttachmentSha256s {
            guard fylesToReceive[sha256] != nil else { assertionFailure(); continue }
            // Guard against double-counting the same failed attachment.
            guard failedFyleSha256s.insert(sha256).inserted else { continue }
            reportCurrentReceivingAttachmentsInProgressState()
        }
    }
    
    func doneAndExportWasSuccessful() {
        self.transferwasSuccessfullyCompleted = true
        windowPruningTask?.cancel()
        windowPruningTask = nil
        reportNewProgressToView(state: .done(status: .exportWasSuccessful(failedFylesCount: failedFylesCount)))
    }

    func doneAndExportWasCancelledByUser() {
        windowPruningTask?.cancel()
        windowPruningTask = nil
        reportNewProgressToView(state: .done(status: .exportWasCancelledByUser))
    }
    
    func doneAndExportFailed() {
        windowPruningTask?.cancel()
        windowPruningTask = nil
        reportNewProgressToView(state: .done(status: .exportFailed))
    }

    func doneAndExportFailedAsIdentitiesDidNotMatch() {
        windowPruningTask?.cancel()
        windowPruningTask = nil
        reportNewProgressToView(state: .done(status: .exportFailedAsIdentitiesDidNotMatch))
    }

    // Private methods

    private func startWindowPruningTask() {
        guard windowPruningTask == nil else { return }
        windowPruningTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                pruneWindowsAndReportIfChanged()
            }
        }
    }

    /// Drops stale entries from both sliding windows and, for each window that shrank,
    /// re-reports the current state so the UI reflects the updated (possibly nil) rate and ETA.
    private func pruneWindowsAndReportIfChanged() {
        let now = Date.now

        var messageWindowChanged = false
        do {
            if let latest = receivedMessageWindow.last, now.timeIntervalSince(latest.timestamp) > 1 {
                receivedMessageWindow.append((timestamp: now, count: latest.count))
                messageWindowChanged = true
            }
            let messageCountBefore = receivedMessageWindow.count
            receivedMessageWindow.removeAll { now.timeIntervalSince($0.timestamp) > Self.messageRateWindowDuration }
            messageWindowChanged = messageWindowChanged || receivedMessageWindow.count != messageCountBefore
        }
        if messageWindowChanged {
            reportCurrentReceivingMessagesInProgressState()
        }

        var bytesWindowChanged = false
        do {
            if let latest = receivedBytesWindow.last, now.timeIntervalSince(latest.timestamp) > 1 {
                receivedBytesWindow.append((timestamp: now, byteCount: latest.byteCount))
                bytesWindowChanged = true
            }
            let bytesCountBefore = receivedBytesWindow.count
            receivedBytesWindow.removeAll { now.timeIntervalSince($0.timestamp) > Self.messageRateWindowDuration }
            bytesWindowChanged = bytesWindowChanged || receivedBytesWindow.count != bytesCountBefore
        }
        if bytesWindowChanged {
            reportCurrentReceivingAttachmentsInProgressState()
        }
    }

    private func reportCurrentReceivingMessagesInProgressState() {
        guard let messagesToReceive else { return }
        let remaining = messagesToReceive.over - messagesToReceive.received - messagesToReceive.missing
        // Avoid division by zero: a zero rate (all batches were empty) produces no ETA.
        let eta: TimeInterval? = messagesPerSecond.flatMap { $0 > 0 ? Double(remaining) / $0 : nil }
        reportNewProgressToView(state: .receivingMessages(status: .inProgress(
            receivedMessageCount: messagesToReceive.received,
            missingMessageCount: messagesToReceive.missing,
            numberOfMessagesToReceive: messagesToReceive.over,
            messagesPerSecond: messagesPerSecond,
            eta: eta)))
    }

    private func reportCurrentReceivingAttachmentsInProgressState() {
        guard let fylesToReceive, let receivedFylesCount, let byteCountReceived, let byteCountToReceive else { return }
        let bytesRemaining = byteCountToReceive - byteCountReceived - byteCountFailedToReceive
        // Avoid division by zero: a zero rate produces no ETA.
        let eta: TimeInterval? = bytesPerSecond.flatMap { $0 > 0 ? Double(bytesRemaining) / $0 : nil }
        reportNewProgressToView(state: .receivingAttachment(
            status: .inProgress(
                receivedFylesCount: receivedFylesCount,
                failedFylesCount: failedFylesCount,
                byteCountReceived: byteCountReceived,
                byteCountFailedToReceive: byteCountFailedToReceive,
                numberOfFylesToReceive: fylesToReceive.count,
                byteCountToReceive: byteCountToReceive,
                bytesPerSecond: bytesPerSecond,
                eta: eta
            )
        ))
    }

    private func reportNewProgressToView(state: DestinationTransferStepsState) {
        self.bufferOfDestinationTransferStepsState.insert(state, at: 0)
        yieldAllBufferedTransferImportStatesIfPossible()
    }

    
    private func yieldAllBufferedTransferImportStatesIfPossible() {
        guard let continuationForProgressReporting else { return }
        while let state = bufferOfDestinationTransferStepsState.popLast() {
            continuationForProgressReporting.yield(state)
        }
    }

}


// MARK: - Helpers


private extension SrcDiscussionList {
    
    var numberOfDiscussionsAvailableOnSource: Int {
        self.discussions.count
    }
    
    var numberOfFylesAvailableOnSource: Int {
        self.sha256s.count
    }
    
    var totalByteCountAvailableOnSource: UInt64 {
        self.sha256s.reduce(0, { $0 + $1.value })
    }
    
}
