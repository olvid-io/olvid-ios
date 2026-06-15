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
import ObvAppCoreConstants


public protocol SourceTransferStepsDataSource: AnyObject, Sendable {
    func historyTransferRequiresAllDiscussionIdentifiers(_ actor: SourceTransferSteps, ownedCryptoId: ObvCryptoId) async throws -> [ObvDiscussionIdentifier]
    func historyTransferRequiresAllHashAndSizesOfFyles(_ actor: SourceTransferSteps, ownedCryptoId: ObvCryptoId) async throws -> [Data: UInt64]
    func historyTransferRequiresTitleAndAllMessageIdentifiersOfDiscussion(_ actor: SourceTransferSteps, discussionIdentifier: ObvDiscussionIdentifier) async throws -> (discussionTitle: String, messageIdentifiers: [ObvMessageAppIdentifier])
    func historyTransferRequiresMessages(_ actor: SourceTransferSteps, discussionIdentifier: ObvDiscussionIdentifier, messageIdentifiers: [ObvMessageAppIdentifier]) async throws -> SourceTransferSteps.MessagesToSend
    func historyTransferRequiresSafeAttachmentURL(_ actor: SourceTransferSteps, sha256: Data) async throws -> URL
    func historyTransferNoLongerRequiresSafeAttachmentURL(_ actor: SourceTransferSteps, sha256: Data, url: URL) async throws
}

protocol TransferTransportSendJsonMessageDelegateForSource: AnyObject, Sendable {
    
    /// Sends the opening handshake of the transfer protocol.
    ///
    /// The source transmits a `SrcDiscussionList` containing:
    /// - the identifiers of all discussions it can export, and
    /// - the SHA-256 hashes and byte sizes of every locally available attachment.
    ///
    /// The destination uses this information to decide which attachments it actually needs (i.e. those
    /// it does not already hold), then replies with a `DstExpectedSha256` listing the subset it wants
    /// to receive.
    func send(srcDiscussionList: SrcDiscussionList) async throws -> DstExpectedSha256
    
    
    /// Sends the source's message ranges for a single discussion.
    ///
    /// This call is made once per discussion, after the opening handshake. The `SrcDiscussionRanges`
    /// describes which messages the source has for that discussion, expressed as compact closed ranges
    /// of sequence numbers grouped by sender identity and thread identifier.
    ///
    /// The destination compares these ranges against its own local history and replies with a
    /// `DstDiscussionExpectedRanges` containing only the ranges it is missing, using the same
    /// (sender, thread) keying scheme. The source will then send exactly those messages in
    /// subsequent `send(srcMessages:)` calls.
    func send(srcDiscussionRanges: SrcDiscussionRanges) async throws -> DstDiscussionExpectedRanges
    
    func send(srcMessages: SrcMessages) async throws

    /// Signals to the destination that all messages for a single discussion have been sent.
    ///
    /// Called once per discussion, after all `send(srcMessages:)` batches for that discussion are
    /// complete. The `SrcDiscussionDone` carries the discussion identifier and the count of messages
    /// that could not be fetched locally (`missingMessageCount`), so the destination knows the
    /// transfer for this discussion is finished and can account for any gaps.
    func send(srcDiscussionDone: SrcDiscussionDone) async throws
    func send(attachmentAtURL url: URL, sha256: Data, progressUpdater: any FyleProgressUpdater) async throws
    func send(srcTransferDone: SrcTransferDone, progressUpdater: any DoneProgressUpdater) async throws
    func getMessageBatchSize() async -> Int
    func receiveSha256sRequestedByDestination(allSha256ExpectedByDestination: DstExpectedSha256) async throws -> AsyncThrowingStream<Data, Error>
}

protocol FyleProgressUpdater: Sendable {
    func updateFyleProgress(sha256: Data, totalNumberOfFyleBytesSent: UInt64) async
}

protocol DoneProgressUpdater: Sendable {
    func updateDoneProgress(entryNumber: UInt, total: UInt, zipFileURL: URL?) async
}

public actor SourceTransferSteps {
    
    private let ownedCryptoId: ObvCryptoId
    private let scope: TransferScope
    private weak var dataSource: SourceTransferStepsDataSource?
    private weak var transferTransportDelegate: (any TransferTransportSendJsonMessageDelegateForSource)?
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "SourceTransferSteps")

    private var currentStepTask: Task<Void, Error>?
    
    private let progressReportingHelper = ExportProgressReportingHelper()

    public enum MessagesToSend: Sendable {
        case discussionNotFound
        case messages(found: [JsonMessageInThread], notFound: [ObvMessageAppIdentifier])
    }

    init(ownedCryptoId: ObvCryptoId,
         scope: TransferScope,
         dataSource: SourceTransferStepsDataSource,
         transferTransportDelegate: any TransferTransportSendJsonMessageDelegateForSource) {
        self.ownedCryptoId = ownedCryptoId
        self.scope = scope
        self.dataSource = dataSource
        self.transferTransportDelegate = transferTransportDelegate
    }

    var transferWasSuccessfullyCompleted: Bool {
        get async {
            await self.progressReportingHelper.transferwasSuccessfullyCompleted
        }
    }

    /// First method called on the source once the transport layer is ready.
    ///
    /// This method corresponds to the `run()` method of the `SrcSendDiscussionsStep` class in the Java implementation.
    func execute() async throws -> AsyncStream<SourceTransferStepsState> {
        guard self.currentStepTask == nil else {
            assertionFailure()
            throw ObvError.executeCannotBeCalledTwice
        }
        self.currentStepTask = createTask() // This launches the task performing all the exports steps from this source
        let stream = await self.progressReportingHelper.getStreamOfSourceTransferStepsState()
        return stream
    }
    
    /// Used when the user cancels an export. This continuation allows to await until the task properly handled the cancelation request.
    private var continuationOnCancel: CheckedContinuation<Void, Never>?
    
    func resetAll() {
        self.currentStepTask?.cancel()
        self.currentStepTask = nil
    }

    /// Called when the user explictely cancels the transfer. Returns `true` iff the transfer was successfully completed.
    func userWantsToCancelExport(requestedFromOtherDevice: Bool) async {
        resumeContinuationOnCancelIfRequired()
        if requestedFromOtherDevice {
            currentStepTask?.cancel()
            await self.progressReportingHelper.doneAndExportWasCancelledByUser()
        } else {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                resumeContinuationOnCancelIfRequired()
                guard let currentStepTask else { continuation.resume(); return }
                guard !currentStepTask.isCancelled else { continuation.resume(); return }
                self.continuationOnCancel = continuation
                currentStepTask.cancel()
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
        return Task(name: "SourceTransferSteps.createTask") {
            
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
                
                // Get the list of available discussions
                
                await self.progressReportingHelper.fetchingDiscussionsListInProgress()
                
                let discussionIdentifiers: [ObvDiscussionIdentifier] = try await dataSource.historyTransferRequiresAllDiscussionIdentifiers(self, ownedCryptoId: self.ownedCryptoId)
                
                await self.progressReportingHelper.fetchingDiscussionsListDone(numberOfDiscussionsFound: discussionIdentifiers.count)
                
                // Compute then send the SrcDiscussionList message
                
                let sha256Map: [Data : UInt64]
                switch scope {
                case .messagesOnly:
                    sha256Map = [:]
                case .messagesAndAttachments:
                    await self.progressReportingHelper.fetchingAllHashAndSizesOfFylesInProgress()
                    sha256Map = try await dataSource.historyTransferRequiresAllHashAndSizesOfFyles(self, ownedCryptoId: self.ownedCryptoId)
                    await self.progressReportingHelper.fetchingAllHashAndSizesOfFylesDone(sha256Map: sha256Map)
                }
                
                await self.progressReportingHelper.negotiatingWhatToSendInProgress()
                
                let messageToSend = SrcDiscussionList(discussionIdentifiers: discussionIdentifiers, sha256Map: sha256Map)
                
                async let dstExpectedSha256 = transferTransportDelegate.send(srcDiscussionList: messageToSend)
                
                // Compute then send the SrcDiscussionRanges message for each discussion
                
                async let allDstDiscussionExpectedRanges: [DstDiscussionExpectedRanges] = withThrowingTaskGroup(of: DstDiscussionExpectedRanges.self) { group in
                    
                    var allDstDiscussionExpectedRanges = [DstDiscussionExpectedRanges]()
                    
                    for discussionIdentifier in discussionIdentifiers {
                        
                        group.addTask {
                            
                            let (discussionTitle, messageIdentifiers) = try await dataSource.historyTransferRequiresTitleAndAllMessageIdentifiersOfDiscussion(self, discussionIdentifier: discussionIdentifier)
                            
                            let messageToSend = try SrcDiscussionRanges(
                                discussionTitle: discussionTitle,
                                discussionIdentifier: discussionIdentifier,
                                messageIdentifiers: messageIdentifiers)
                            
                            let dstDiscussionExpectedRanges = try await transferTransportDelegate.send(srcDiscussionRanges: messageToSend)
                            
                            return dstDiscussionExpectedRanges
                            
                        }
                        
                        for try await dstDiscussionExpectedRanges in group {
                            allDstDiscussionExpectedRanges.append(dstDiscussionExpectedRanges)
                        }
                        
                    }
                    
                    return allDstDiscussionExpectedRanges
                    
                }
                
                // We have sent one SrcDiscussionList message, and one SrcDiscussionRanges message per discussion to the destination device.
                // We now await for the DstExpectedSha256 from the destination (resulting from the sending of the SrcDiscussionList message) and
                // for the DstDiscussionExpectedRanges messages from the destination (one per SrcDiscussionRanges message sent)
                
                let allDstDiscussionExpectedRangesReceived = try await allDstDiscussionExpectedRanges
                let allSha256ExpectedByDestination: DstExpectedSha256 = try await dstExpectedSha256
                
                await self.progressReportingHelper.negotiatingWhatToSendDone(
                    numberOfMessagesToSend: allDstDiscussionExpectedRangesReceived.numberOfMessagesToSend,
                    sha256sToSend: allSha256ExpectedByDestination.sha256s)
                
                // Send the requested messages to the destination. This corresponds to SrcSendMessagesStep in the Java version.
                // We use an `async let` to avoid awaiting for the messages to be sent, as we want to send the attachments in parallel.
                
                if allDstDiscussionExpectedRangesReceived.numberOfMessagesToSend > 0 {
                    await self.progressReportingHelper.sendingMessagesStarting()
                }
                
                async let allMessagesSent: () = withThrowingTaskGroup(of: (discussionIdentifier: JsonDiscussionIdentifier, partialMissingMessageCount: Int).self) { group in
                    
                    for (discussionIdentifier, rangesByThreadAndSender) in allDstDiscussionExpectedRangesReceived.map({($0.discussionIdentifier, $0.rangesByThreadAndSender)}) {
                        
                        let obvDiscussionIdentifier = try discussionIdentifier.getDiscussionIdentifier(ownedCryptoId: self.ownedCryptoId)
                        
                        for (sender, rangesByThread) in rangesByThreadAndSender {
                            for (senderThreadIdentifier, ranges) in rangesByThread {
                                let messageIdentifiersToSend = JsonMessagesHelpers.messageIdentifiers(discussionIdentifier: obvDiscussionIdentifier, sender: sender, senderThreadIdentifier: senderThreadIdentifier, ranges: ranges)
                                let messageBatchSize = await transferTransportDelegate.getMessageBatchSize()
                                let slicesOfMessageIdentifiersToSend = messageIdentifiersToSend.toSlices(ofMaxSize: messageBatchSize)
                                for sliceOfMessageIdentifiersToSend in slicesOfMessageIdentifiersToSend {
                                    group.addTask {
                                        let messagesToSend = try await dataSource.historyTransferRequiresMessages(self, discussionIdentifier: obvDiscussionIdentifier, messageIdentifiers: sliceOfMessageIdentifiersToSend)
                                        switch messagesToSend {
                                        case .discussionNotFound:
                                            return (discussionIdentifier, messageIdentifiersToSend.count)
                                        case .messages(found: let found, notFound: let notFound):
                                            assert(sliceOfMessageIdentifiersToSend.count == found.count + notFound.count)
                                            let messageToSend = SrcMessages(discussionIdentifier: discussionIdentifier,
                                                                            sender: sender,
                                                                            threadId: senderThreadIdentifier,
                                                                            messages: found,
                                                                            missingMessageCount: notFound.count)
                                            try await transferTransportDelegate.send(srcMessages: messageToSend)
                                            return (discussionIdentifier, notFound.count)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // At this point, all groups have been created, allowing to send all the messages for the current discussion.
                        // We await for the end of all group items, count the total number of missing messages, and send a
                        // SrcDiscussionDone for the discussion. We then loop to the next discussion.
                        
                        var missingMessageCount = 0
                        
                        for try await (_, partialMissingMessageCount) in group {
                            missingMessageCount += partialMissingMessageCount
                        }
                        
                        let messageToSend = SrcDiscussionDone(discussionIdentifier: discussionIdentifier, missingMessageCount: missingMessageCount)
                        try await transferTransportDelegate.send(srcDiscussionDone: messageToSend)
                        
                        do {
                            let partialSentMessageCount = rangesByThreadAndSender.flatMap(\.value).flatMap(\.value).reduce(0) { $0 + $1.count }
                            if partialSentMessageCount > 0 || missingMessageCount > 0 {
                                await self.progressReportingHelper.sendingMessagesInProgress(
                                    partialSentMessageCount: partialSentMessageCount,
                                    partialMissingMessageCount: missingMessageCount)
                            }
                        }
                        
                    }
                    
                }
                
                // Send the attachment when they are requested
                
                if allSha256ExpectedByDestination.sha256s.isEmpty {
                    
                    Self.logger.info("📰 There are no attachments to send. We thus don't expect any attachment request from the destination")
                    
                } else {
                    
                    Self.logger.info("📰 Will wait until all \(allSha256ExpectedByDestination.sha256s.count) attachments are requested, and send them")
                    
                    await self.progressReportingHelper.sendingAttachmentsStarting()
                    
                    let streamOfSha256sRequestedByDestination = try await transferTransportDelegate.receiveSha256sRequestedByDestination(allSha256ExpectedByDestination: allSha256ExpectedByDestination)
                    
                    for try await sha256 in streamOfSha256sRequestedByDestination {
                        do {
                            let safeAttachmentURL = try await dataSource.historyTransferRequiresSafeAttachmentURL(self, sha256: sha256)
                            try await transferTransportDelegate.send(
                                attachmentAtURL: safeAttachmentURL,
                                sha256: sha256,
                                progressUpdater: self.progressReportingHelper)
                            try await dataSource.historyTransferNoLongerRequiresSafeAttachmentURL(self, sha256: sha256, url: safeAttachmentURL)
                        } catch {
                            if error is CancellationError {
                                throw error // Catched in the global try/catch
                            } else if let error = error as? TransferTransportDelegateError {
                                switch error {
                                case .transferTransportDelegateFailed:
                                    throw error // Catched in the global try/catch
                                case .ownedCryptoIdDoesNotMatch:
                                    throw error // Catched in the global try/catch
                                }
                            } else {
                                await self.progressReportingHelper.sendingOfSpecificAttachmentFailed(sha256: sha256)
                                // We continue with the other attachments
                            }
                        }
                    }
                    
                    Self.logger.info("📰 All \(allSha256ExpectedByDestination.sha256s.count) were sent (except for those that were not required)")
                    
                }
                
                Self.logger.info("📰 Waiting until all `SrcMessages` have been sent")
                
                // Await until all `SrcMessages` have been sent
                
                let _ = try await allMessagesSent
                                
                // Send the SrcTransferDone message
                
                try await transferTransportDelegate.send(srcTransferDone: SrcTransferDone(), progressUpdater: self.progressReportingHelper)
                
                Self.logger.info("📰✅ We successfully reached the end of the SourceTransferSteps")
                
                await self.progressReportingHelper.doneAndExportWasSuccessful()

            } catch {
                
                if error is CancellationError {
                    Self.logger.info("📰🛑 Source transfer step task was cancelled. We do not propagate the error.")
                    await self.progressReportingHelper.doneAndExportWasCancelledByUser()
                } else if let error = error as? TransferTransportDelegateError {
                    Self.logger.error("📰 Source transfer step task throwed: \(error.localizedDescription).")
                    switch error {
                    case .transferTransportDelegateFailed:
                        await self.progressReportingHelper.doneAndExportFailed()
                    case .ownedCryptoIdDoesNotMatch:
                        await self.progressReportingHelper.doneAndExportFailed()
                    }
                    throw error
                } else {
                    Self.logger.error("📰 Source transfer step task throwed: \(error.localizedDescription)")
                    throw error
                }
                
            }
            
        }

    }
    
}


// MARK: - Progress reporting

private actor ExportProgressReportingHelper: FyleProgressUpdater, DoneProgressUpdater {
        
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ExportProgressReportingHelper")
    
    private var continuationForProgressReporting: AsyncStream<SourceTransferStepsState>.Continuation?
    private var bufferOfSourceTransferStepsState = [SourceTransferStepsState]()

    private var numberOfDiscussionsFound: Int?
    
    /// Represents the fyles available on this source device. The fyles that will be sent will be a subset of this set.
    private var fylesFound: [Data : UInt64]? // keys are sha256, values are fyle sizes in bytes. Once set, this does not change
    private var numberOfFylesFound: Int? { fylesFound?.count }
    private var totalByteCount: UInt64? { fylesFound?.values.reduce(0, +) }
    
    /// Represents the sending message progress
    ///
    /// - `sent` is the number of sent messages
    /// - `missing` is the number of missing messages that could not be sent
    /// - `over` is the initial total number of messages to send (once set, this value does not change)
    ///
    /// Eventually, we expect `sent + missing == over`
    private var messagesToSend: (sent: Int, missing: Int, over: Int)? // sent is the number of sent messages, message
    
    /// Sliding window used to compute the message sending rate.
    ///
    /// Each entry records the timestamp and the number of messages sent in that batch.
    /// Entries older than `messageRateWindowDuration` are pruned on each update.
    private var sentMessageWindow: [(timestamp: Date, count: Int)] = []
    private static let messageRateWindowDuration: TimeInterval = 10.0

    private(set) var transferwasSuccessfullyCompleted: Bool = false
    
    /// Returns messages per second averaged over the sliding window, or `nil` if the window is too
    /// narrow to produce a meaningful estimate (fewer than 2 data points, or less than 1 second elapsed).
    /// Used both for display and as input to `eta`.
    private var messagesPerSecond: Double? {
        guard sentMessageWindow.count >= 2 else { return nil }
        guard let first = sentMessageWindow.first, let last = sentMessageWindow.last else { return nil }
        let elapsed = last.timestamp.timeIntervalSince(first.timestamp)
        guard elapsed >= 1.0 else { return nil }
        return Double(sentMessageWindow.reduce(0) { $0 + $1.count }) / elapsed
    }

    /// Sliding window used to compute the fyle byte-sending rate.
    ///
    /// Each entry records the timestamp and the number of bytes sent since the previous update (delta, not total).
    /// Entries older than `messageRateWindowDuration` are pruned on each update.
    private var sentBytesWindow: [(timestamp: Date, byteCount: UInt64)] = []

    /// Returns bytes per second averaged over the sliding window, or `nil` if the window is too
    /// narrow to produce a meaningful estimate (fewer than 2 data points, or less than 1 second elapsed).
    /// Used both for display and as input to the fyle ETA.
    private var bytesPerSecond: Double? {
        guard sentBytesWindow.count >= 2 else { return nil }
        guard let first = sentBytesWindow.first, let last = sentBytesWindow.last else { return nil }
        let elapsed = last.timestamp.timeIntervalSince(first.timestamp)
        guard elapsed >= 1.0 else { return nil }
        return Double(sentBytesWindow.reduce(0) { $0 + $1.byteCount }) / elapsed
    }

    /// The fyles to send (a subset of `fylesFound`), known after negotiating with the destination device.
    /// Each key is a sha256. For each value:
    /// - `sent` is the number of sent bytes for the fyle
    /// - `over` is the fyle size (once set, this value does not change)
    ///
    /// Eventually, we expect `sent == over` for each non-failed fyle.
    private var fylesToSend: [Data : (sent: UInt64, over: UInt64)]? // keys are sha256, values are the number of sent bytes and file sizes
    private var numberOfFylesToSend: Int? { fylesToSend?.count }
    private var byteCountToSend: UInt64? { fylesToSend?.values.map({ $0.over }).reduce(0, +) }
    private var byteCountSent: UInt64? { fylesToSend?.values.map({ $0.sent }).reduce(0, +) }
    private var sentFylesCount: Int? { fylesToSend?.values.count(where: { $0.sent >= $0.over }) }

    /// Runs every second while message/attachment sending is active to prune stale window entries
    /// and re-report rates/ETAs even when no progress callbacks arrive.
    private var windowPruningTask: Task<Void, Never>?

    /// sha256s of fyles whose sending failed. Used for deduplication and ETA correction.
    private var failedFyleSha256s: Set<Data> = []
    private var failedFylesCount: Int { failedFyleSha256s.count }
    /// Bytes from failed fyles that will never be sent: `over - sent` for each failed fyle.
    private var byteCountFailedToSend: UInt64 {
        guard let fylesToSend else { return 0 }
        return failedFyleSha256s.compactMap { fylesToSend[$0] }.map { $0.over - $0.sent }.reduce(0, +)
    }
    
    // Methods called by the source transfer step task
    
    func getStreamOfSourceTransferStepsState() -> AsyncStream<SourceTransferStepsState> {
        assert(self.continuationForProgressReporting == nil)
        self.continuationForProgressReporting?.finish()
        let stream = AsyncStream<SourceTransferStepsState> { (continuation: AsyncStream<SourceTransferStepsState>.Continuation) in
            assert(self.continuationForProgressReporting == nil)
            self.continuationForProgressReporting?.finish()
            self.continuationForProgressReporting = continuation
            yieldAllBufferedTransferExportStatesIfPossible()
        }
        return stream
    }
    
    func fetchingDiscussionsListInProgress() {
        self.reportNewProgressToView(state: .fetchingDiscussionsList(status: .inProgress))
    }
    
    func fetchingDiscussionsListDone(numberOfDiscussionsFound: Int) {
        assert(self.numberOfDiscussionsFound == nil)
        self.numberOfDiscussionsFound = numberOfDiscussionsFound
        self.reportNewProgressToView(state: .fetchingDiscussionsList(status: .done(numberOfDiscussionsFound: numberOfDiscussionsFound)))
    }
    
    func fetchingAllHashAndSizesOfFylesInProgress() {
        reportNewProgressToView(state: .fetchingAllHashAndSizesOfFyles(status: .inProgress))
    }
    
    func fetchingAllHashAndSizesOfFylesDone(sha256Map: [Data : UInt64]) {
        assert(self.fylesFound == nil)
        self.fylesFound = sha256Map
        guard let numberOfFylesFound, let totalByteCount else { assertionFailure(); return }
        reportNewProgressToView(state: .fetchingAllHashAndSizesOfFyles(status: .done(numberOfFylesFound: numberOfFylesFound, totalByteCount: totalByteCount)))
    }
    
    func negotiatingWhatToSendInProgress() {
        reportNewProgressToView(state: .negotiatingWhatToSend(status: .inProgress))
    }
    
    func negotiatingWhatToSendDone(numberOfMessagesToSend: Int, sha256sToSend: [Data: UInt64]) {
        assert(self.messagesToSend == nil)
        self.messagesToSend = (sent: 0, missing: 0, over: numberOfMessagesToSend)
        assert(self.fylesToSend == nil)
        self.fylesToSend = Dictionary.init(sha256sToSend, keyMapping: { $0 }, valueMapping: { (sent: 0, over: $0) })
        guard let numberOfFylesToSend, let byteCountToSend else { assertionFailure(); return }
        reportNewProgressToView(state: .negotiatingWhatToSend(status: .done(
            numberOfMessagesToSend: numberOfMessagesToSend,
            numberOfFylesToSend: numberOfFylesToSend,
            byteCountToSend: byteCountToSend)))
    }
    
    func sendingMessagesStarting() {
        sentMessageWindow = [] // Reset in case this is ever called more than once
        startWindowPruningTask()
        reportNewProgressToView(state: .sendingMessages(status: .starting))
    }
    
    func sendingMessagesInProgress(partialSentMessageCount: Int, partialMissingMessageCount: Int) {
        guard let prev = messagesToSend else { assertionFailure(); return }
        self.messagesToSend = (sent: prev.sent + partialSentMessageCount, missing: prev.missing + partialMissingMessageCount, over: prev.over)

        // Feed the sliding window: append the new batch, then drop entries that have fallen outside the window.
        let now = Date.now
        sentMessageWindow.append((timestamp: now, count: partialSentMessageCount))
        sentMessageWindow.removeAll { now.timeIntervalSince($0.timestamp) > Self.messageRateWindowDuration }

        reportCurrentSendingMessagesInProgressState()
    }
    
    func sendingAttachmentsStarting() {
        sentMessageWindow = [] // Message phase is over; clear to prevent stale pruning reports
        sentBytesWindow = [] // Reset in case this is ever called more than once
        startWindowPruningTask() // No-op if already running (messages phase started it); starts it if messages were skipped
        reportNewProgressToView(state: .sendingAttachments(status: .starting))
    }

    func updateFyleProgress(sha256: Data, totalNumberOfFyleBytesSent: UInt64) async {
        guard let fylesToSend else { assertionFailure(); return }
        guard let (previouslySent, over) = fylesToSend[sha256] else { assertionFailure(); return }
        assert(previouslySent < totalNumberOfFyleBytesSent)
        assert(totalNumberOfFyleBytesSent <= over)
        self.fylesToSend?[sha256] = (totalNumberOfFyleBytesSent, over)

        // Feed the sliding window with the byte delta, then prune stale entries.
        let delta = totalNumberOfFyleBytesSent - previouslySent
        let now = Date.now
        sentBytesWindow.append((timestamp: now, byteCount: delta))
        sentBytesWindow.removeAll { now.timeIntervalSince($0.timestamp) > Self.messageRateWindowDuration }

        reportCurrentSendingAttachmentsInProgressState()
    }

    
    func updateDoneProgress(entryNumber: UInt, total: UInt, zipFileURL: URL?) async {
        Self.logger.debug("📰 The export progress reporting helper has a new done progress \(entryNumber)/\(total)")
        windowPruningTask?.cancel()
        windowPruningTask = nil
        if let zipFileURL {
            reportNewProgressToView(state: .computingZipFile(status: .done(zipFileURL: zipFileURL)))
        } else {
            reportNewProgressToView(state: .computingZipFile(status: .inProgress(entryNumber: entryNumber, total: total)))
        }
    }
        
    
    func sendingOfSpecificAttachmentFailed(sha256: Data) {
        guard let fylesToSend else { assertionFailure(); return }
        guard fylesToSend[sha256] != nil else { assertionFailure(); return }
        // Guard against double-counting the same failed attachment.
        guard failedFyleSha256s.insert(sha256).inserted else { return }
        reportCurrentSendingAttachmentsInProgressState()
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

    // Private methods

    private func startWindowPruningTask() {
        Self.logger.debug("📰 Call to startWindowPruningTask")
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
    /// Also injects a synthetic "stall" entry when the latest entry is older than 1 second, so
    /// that the ETA shrinks toward zero rather than staying frozen while the connection is stalled.
    private func pruneWindowsAndReportIfChanged() {
        
        Self.logger.debug("📰 Call to pruneWindowsAndReportIfChanged")
        
        let now = Date.now

        // If the newest message-window entry is older than 1 s, duplicate it at `now` so the
        // computed rate decays toward zero instead of remaining frozen.
        var messageWindowChanged = false
        do {
            if let latest = sentMessageWindow.last, now.timeIntervalSince(latest.timestamp) > 1 {
                sentMessageWindow.append((timestamp: now, count: latest.count))
                messageWindowChanged = true
            }
            let messageCountBefore = sentMessageWindow.count
            sentMessageWindow.removeAll { now.timeIntervalSince($0.timestamp) > Self.messageRateWindowDuration }
            messageWindowChanged = messageWindowChanged || sentMessageWindow.count != messageCountBefore
        }
        if messageWindowChanged {
            reportCurrentSendingMessagesInProgressState()
        }

        // Same stall-detection for the bytes window.
        var bytesWindowChanged = false
        do {
            if let latest = sentBytesWindow.last, now.timeIntervalSince(latest.timestamp) > 1 {
                sentBytesWindow.append((timestamp: now, byteCount: latest.byteCount))
                bytesWindowChanged = true
            }
            let bytesCountBefore = sentBytesWindow.count
            sentBytesWindow.removeAll { now.timeIntervalSince($0.timestamp) > Self.messageRateWindowDuration }
            bytesWindowChanged = bytesWindowChanged || sentBytesWindow.count != bytesCountBefore
        }
        if bytesWindowChanged {
            reportCurrentSendingAttachmentsInProgressState()
        }
    }

    private func reportCurrentSendingMessagesInProgressState() {
        guard let messagesToSend else { assertionFailure(); return }
        let remaining = messagesToSend.over - messagesToSend.sent - messagesToSend.missing
        // Avoid division by zero: a zero rate (all batches were empty) produces no ETA.
        let eta: TimeInterval? = messagesPerSecond.flatMap { $0 > 0 ? Double(remaining) / $0 : nil }
        reportNewProgressToView(state: .sendingMessages(status: .inProgress(
            sentMessageCount: messagesToSend.sent,
            missingMessageCount: messagesToSend.missing,
            numberOfMessagesToSend: messagesToSend.over,
            messagesPerSecond: messagesPerSecond,
            eta: eta)))
    }

    private func reportCurrentSendingAttachmentsInProgressState() {
        guard let fylesToSend, let sentFylesCount, let byteCountSent, let byteCountToSend else { assertionFailure(); return }
        let bytesRemaining = byteCountToSend - byteCountSent - byteCountFailedToSend
        // Avoid division by zero: a zero rate produces no ETA.
        let eta: TimeInterval? = bytesPerSecond.flatMap { $0 > 0 ? Double(bytesRemaining) / $0 : nil }
        Self.logger.debug("📰 Will report sendingAttachments in progress state")
        reportNewProgressToView(state: .sendingAttachments(status: .inProgress(
            sentFylesCount: sentFylesCount,
            failedFylesCount: failedFylesCount,
            byteCountSent: byteCountSent,
            byteCountFailedToSend: byteCountFailedToSend,
            numberOfFylesToSend: fylesToSend.count,
            byteCountToSend: byteCountToSend,
            bytesPerSecond: bytesPerSecond,
            eta: eta)))
    }

    private func reportNewProgressToView(state: SourceTransferStepsState) {
        self.bufferOfSourceTransferStepsState.insert(state, at: 0)
        yieldAllBufferedTransferExportStatesIfPossible()
    }

    
    private func yieldAllBufferedTransferExportStatesIfPossible() {
        guard let continuationForProgressReporting else { return }
        while let state = bufferOfSourceTransferStepsState.popLast() {
            continuationForProgressReporting.yield(state)
        }
    }

}


// MARK: - Errors

extension SourceTransferSteps {
    
    enum ObvError: Error {
        case delegateIsNil
        case dataSourceIsNil
        case transferTransportDelegateIsNil
        case executeCannotBeCalledTwice
    }
    
}


// MARK: - Helpers

enum AttachmentRequirementFromSource {
    case requested(Data)
    case notRequested(Data)
}


private extension [DstDiscussionExpectedRanges] {
    
    var numberOfMessagesToSend: Int {
        return self.reduce(0) { $0 + $1.numberOfMessagesToSend }
    }
    
}


private extension DstDiscussionExpectedRanges {
    
    var numberOfMessagesToSend: Int {
        let allRanges = self.rangesByThreadAndSender.flatMap(\.value).flatMap(\.value)
        return allRanges.reduce(0, { $0 + $1.count })
    }
    
}


private extension DstExpectedSha256 {
    
    var numberOfFylesToSend: Int {
        return self.sha256s.count
    }
    
    var totalByteCountToSend: UInt64 {
        return self.sha256s.values.reduce(0, +)
    }
    
}
