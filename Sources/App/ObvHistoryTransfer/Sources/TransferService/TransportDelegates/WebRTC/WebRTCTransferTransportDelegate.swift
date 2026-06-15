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
import WebRTC
import ObvAppCoreConstants
import ObvAppTypes

public actor WebRTCTransferTransportDelegate {
    
    private let otherOwnedDeviceIdentifier: ObvOwnedDeviceIdentifier
    let role: TransferRole
    private weak var delegate: WebRTCTransferTransportDelegateDelegate?
    private let queueForWebRTC = DispatchQueue(label: "Queue for WebRTC")
    private let internalTransferId: String
    
    private let rtcDelegate = LocalRTCDelegate()
    
    private let rtcDataBufferHandler = RTCDataBufferHandler()
    
    private(set) var transferTransportLayerState: TransferTransportLayerState = .initializing
    private var continuationForTransferTransportLayerState: AsyncStream<TransferTransportLayerState>.Continuation?
    private var transferTransportLayerStateOnSetContinuation = [TransferTransportLayerState]()
    private var lastYieldedTransferTransportLayerState: TransferTransportLayerState?

    private var peerConnection: RTCPeerConnection? {
        didSet {
            guard let peerConnection else { return }
            if let continuation = self.continuationOnPeerConnectionAvailability {
                self.continuationOnPeerConnectionAvailability = nil
                continuation.resume(returning: peerConnection)
            }
        }
    }
    
    private static let maxDataChannelMessageSize: UInt32 = 64*1024 // 65_536
    private static let maxFileBufferSize: Int = 300_000 // 300kB
    
    private var continuationOnPeerConnectionAvailability: CheckedContinuation<RTCPeerConnection, any Error>?
    
    /// Data channel of the peer connection.
    ///
    /// The sources creates the data channel and sets this property at creation.
    /// We do not explicitely create the peer connection on the destination. Instead, we wait for the peer connection following delegate call:
    /// `func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel)`
    /// This delegate call forwards the `RTCDataChannel` by calling the
    /// `func onPeerConnectionDidOpenDataChannelOnDestination(_ dataChannel: RTCDataChannel) async` on this actor.
    private var dataChannel: RTCDataChannel?
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "WebRTCTransferTransportDelegate")
    
    /// Manager allowing to batch generated ICE candidates before sending them.
    private let iceCandidatesToSendBatchManager = IceCandidatesToSendBatchManager()
    
    /// When receiving ICE candidates while the peer connection is not in the state, we store the candidates for later.
    private var pendingReceivedIceCandidates: [RTCIceCandidate] = []
    
    /// When the local peer connection generates an ICE candidate, we wait until the peer connection is in the stable state to send it.
    private var pendingGeneratedIceCandidates: [RTCIceCandidate] = []
    
    var ownedCryptoId: ObvCryptoId {
        otherOwnedDeviceIdentifier.ownedCryptoId
    }
    
    private let messageDispatchers = MessageDispatchers()
    
    init(role: TransferRole,
         otherOwnedDeviceIdentifier: ObvOwnedDeviceIdentifier,
         transferId: String,
         delegate: WebRTCTransferTransportDelegateDelegate
    ) {
        self.role = role
        self.otherOwnedDeviceIdentifier = otherOwnedDeviceIdentifier
        self.delegate = delegate
        self.internalTransferId = transferId
        self.rtcDelegate.onPeerConnectionDidOpenDataChannelOnDestination = self.onPeerConnectionDidOpenDataChannelOnDestination
        Task { await observeGeneratedIceCandidates() }
        Task { await observeSignalingStateOfPeerConnection() }
        Task { await observeDataChannelState() }
        Task { await observeRTCDataBufferReceivedOnDataChannel() }
        Task { await observeReceivedChunksToAcknowledge() }
        Task { await observeRTCIceConnectionState() }
    }

    
    private func onPeerConnectionDidOpenDataChannelOnDestination(_ dataChannel: RTCDataChannel) async {
        switch role {
        case .source:
            assertionFailure()
        case .destination:
            self.dataChannel = dataChannel
        }
    }
    
    
    /// Each time the `RTCDataBufferHandler` parses a new chunk, it streams the corresponding message number and chunk number.
    /// We observe the stream here and send an ack to the source for each received chunk
    private func observeReceivedChunksToAcknowledge() async {
        let stream = await rtcDataBufferHandler.getAsyncStreamOfReceivedChunksToAcknowledge()
        for await messageAndChunkNumber in stream {
            Self.logger.debug("📰 New ack to send \(messageAndChunkNumber)")
            do {
                try await self.sendMessage(type: .ack, serializedMessage: messageAndChunkNumber.ackData)
            } catch {
                if error is CancellationError {
                    Self.logger.debug("📰 Could not send ack as the transfer was cancelled")
                } else {
                    Self.logger.error("📰 Failed to send ack on data channel: \(error)")
                    assertionFailure()
                }
            }
        }
    }
    
    
    private func observeDataChannelState() async {
        let stream = rtcDelegate.getAsyncStreamOfRTCDataChannelState()
        for await newDataChannelState in stream {
            Self.logger.debug("📰 New data channel state: \(newDataChannelState.debugDescription)")
            switch newDataChannelState {
            case .open:
                guard !self.transferTransportLayerState.isClosed else {
                    // This happens when the transfer was quickly cancelled on the remote device
                    return
                }
                setTransferTransportLayerState(to: .ready)
            case .closing, .closed:
                // We notify the transfer service that the data channel was closed.
                // Eventually, it will call abort
                setTransferTransportLayerState(to: .closed(exportWasCancelledByUser: false))
            case .connecting:
                break
            @unknown default:
                assertionFailure()
            }
        }
    }
    
    
    private func observeRTCIceConnectionState() async {
        let stream = rtcDelegate.getAsyncStreamOfRTCIceConnectionState()
        for await rtcIceConnectionState in stream {
            Self.logger.debug("📰 New RTC ICE connection state: \(rtcIceConnectionState.debugDescription)")
            if rtcIceConnectionState == .failed {
                await self.messageDispatchers.finishAllDispatchesByThrowing(TransferTransportDelegateError.transferTransportDelegateFailed)
            }
        }
    }

    
    /// Observe the peer connection signaling states.
    ///
    /// When reaching the stable state:
    /// - We send all the ICE candidate generated while not in the stable state
    /// - We add all the ICE candidates received while not in the stable state
    private func observeSignalingStateOfPeerConnection() async {
        let stream = rtcDelegate.getAsyncStreamOfRTCSignalingState()
        for await newSignalingState in stream {
            switch newSignalingState {
            case .haveLocalOffer, .haveRemoteOffer:
                setTransferTransportLayerState(to: .connecting)
            case .stable:
                // The transferTransportLayerState is set to `.ready` when the `RTCDataChannelState` is `.open`
                do { try await sendPendingGeneratedIceCandidatesAsPeerConnectionIsStable() } catch { assertionFailure() }
                do { try addPendingReceivedIceCandidatesAsPeerConnectionIsStable() } catch { assertionFailure() }
            case .closed:
                setTransferTransportLayerState(to: .closed(exportWasCancelledByUser: false))
            default:
                assertionFailure()
            }
            if newSignalingState == .stable {
                do { try await sendPendingGeneratedIceCandidatesAsPeerConnectionIsStable() } catch { assertionFailure() }
                do { try addPendingReceivedIceCandidatesAsPeerConnectionIsStable() } catch { assertionFailure() }
            }
        }
    }
    
    
    /// Observe the generated ICE candidates
    ///
    /// We batch the generated ICE candidates (by leveraging the `IceCandidatesToSendBatchManager`). Once a batch is ready to be sent:
    /// - if the peer connection is in the stable state, we send the batch.
    /// - otherwise, we store the batch for later. It will be sent as soon as the peer connection reaches the stable state.
    private func observeGeneratedIceCandidates() async {
        let stream = rtcDelegate.getAsyncStreamOfGeneratedIceCandidates()
        for await generatedIceCandidate in stream {
            Task {
                let batchResult = await iceCandidatesToSendBatchManager.batch(generatedIceCandidate)
                switch batchResult {
                case .batchProcessedByAnotherTask:
                    break
                case .processBatch(let batch):
                    pendingGeneratedIceCandidates += batch
                    if peerConnection?.signalingState == .stable {
                        do { try await sendPendingGeneratedIceCandidatesAsPeerConnectionIsStable() } catch { assertionFailure() }
                    }
                }
            }
        }
    }
    
    
    private func observeRTCDataBufferReceivedOnDataChannel() async {
        let jsonDecoder = JSONDecoder()
        let stream = rtcDelegate.getAsyncStreamOfRTCDataBuffer()
        for await buffer in stream {
            guard !Task.isCancelled else { return }
            do {
                let result = try await self.rtcDataBufferHandler.handleReceivedRTCDataBuffer(buffer)
                switch result {
                case .expectingMoreChunks:
                    continue
                case .receivedSerializedMessage(type: let type, serializedMessage: let serializedMessage):
                    switch type {
                    case .ack:
                        do {
                            let messageAndChunkNumber = try RTCDataBufferHandler.MessageAndChunkNumber(ackData: serializedMessage)
                            await self.messageDispatchers.ackDispatcher.receivedAck(messageAndChunkNumber: messageAndChunkNumber)
                        } catch {
                            Self.logger.error("📰 Could not parse ACK message: \(error.localizedDescription)")
                            assertionFailure()
                        }
                    case .sourceDiscussionList:
                        // Received by destination. This message contains the list of available discussions on the source.
                        do {
                            let message = try jsonDecoder.decode(SrcDiscussionList.self, from: serializedMessage)
                            Self.logger.debug("📰 Destination did received SrcDiscussionList with \(message.discussions.count) discussions and \(message.sha256s.count) sha256s")
                            await messageDispatchers.srcDiscussionListMessageDispatcher.dispatchMessageToTransferSteps(message: message)
                        } catch {
                            Self.logger.error("📰 Failed to decode SrcDiscussionList message")
                            assertionFailure()
                        }
                    case .sourceDiscussionRanges:
                        do {
                            let message = try jsonDecoder.decode(SrcDiscussionRanges.self, from: serializedMessage)
                            Self.logger.debug("📰 Did received SrcDiscussionRanges for discussion \(message.discussionTitle), with \(message.rangesByThreadAndSender.count) ranges")
                            await messageDispatchers.srcDiscussionRangesMessageDispatcher.dispatchSrcDiscussionRangesToDestinationTransferSteps(srcDiscussionRanges: message)
                        } catch {
                            Self.logger.error("📰 Failed to decode SrcDiscussionRanges message")
                            assertionFailure()
                        }
                    case .destinationExpectedSha256:
                        let message = try jsonDecoder.decode(DstExpectedSha256.self, from: serializedMessage)
                        Self.logger.debug("📰 Did received DstExpectedSha256")
                        await messageDispatchers.dstExpectedSha256MessageDispatcher.dispatchMessageToTransferSteps(message: message)
                    case .destinationExpectedRanges:
                        do {
                            let message = try jsonDecoder.decode(DstDiscussionExpectedRanges.self, from: serializedMessage)
                            Self.logger.debug("📰 Did received DstDiscussionExpectedRanges")
                            await messageDispatchers.dstDiscussionExpectedRangesMessageDispatcher.dispatchDstDiscussionExpectedRangesToSourceTransferSteps(dstDiscussionExpectedRanges: message)
                        } catch {
                            Self.logger.error("📰 Failed to decode SrcDiscussionRanges message")
                            assertionFailure()
                        }
                    case .sourceMessages:
                        do {
                            let message = try jsonDecoder.decode(SrcMessages.self, from: serializedMessage)
                            Self.logger.debug("📰 Did received SrcMessages")
                            await messageDispatchers.srcMessagesDispatcher.dispatchSrcMessagesToDestinationTransferSteps(srcMessages: message)
                        } catch {
                            Self.logger.error("📰 Failed to decode SrcMessages message")
                            assertionFailure()
                        }
                    case .destinationRequestSha256:
                        // Received by the source, when the destination requests an attachment identified by its sha256
                        let message = try jsonDecoder.decode(DstRequestSha256.self, from: serializedMessage)
                        await messageDispatchers.dstRequestSha256sDispatcher.dispatchDstRequestSha256ToSourceTransferSteps(dstRequestSha256: message)
                    case .destinationDoNotRequestSha256:
                        // Received by the source, when the destination indicates it will not request a particular attachment
                        let message = try jsonDecoder.decode(DstDoNotRequestSha256.self, from: serializedMessage)
                        await messageDispatchers.dstRequestSha256sDispatcher.dispatchDstDoNotRequestSha256ToSourceTransferSteps(dstDoNotRequestSha256: message)
                    case .sourceSha256:
                        // Received by the destination. This is a chunk of an attachment.
                        Self.logger.debug("📰 Did receive sourceSha256 (i.e., an attachment chunk)")
                        await self.messageDispatchers.srcSha256Dispatcher.saveAttachmentChunkReceivedInSourceSha256Message(serializedMessage)
                    case .sourceDiscussionDone:
                        Self.logger.debug("📰 Did receive sourceDiscussionDone (for now we don't do anything with this message)")
                    case .sourceTransferDone:
                        Self.logger.debug("📰 Did receive sourceTransferDone (for now we don't do anything with this message)")
                    }
                }
            } catch {
                Self.logger.error("📰 Could not handle received RTCDataBuffer: \(error.localizedDescription)")
                assertionFailure()
            }
        }
    }
        
}


// MARK: - Implementing TransferTransportDelegate

extension WebRTCTransferTransportDelegate: TransferTransportDelegate {
    
    var transferId: String? {
        internalTransferId
    }
    
    func connect(progressUpdater: any ConnectProgressUpdater) async throws {
        
        // The progressUpdater is not used for the WebRTC method
        
        //RTCSetMinDebugLogLevel(.verbose)
        
        Self.logger.debug("📰 WebRTCTransferTransport: connecting")
        
        guard peerConnection == nil else {
            assertionFailure()
            throw ObvError.peerConnectionAlreadySet
        }
        
        let factory = RTCPeerConnectionFactory()
        let options = RTCPeerConnectionFactoryOptions()
        options.ignoreLoopbackNetworkAdapter = true
        factory.setOptions(options)
        
        guard let delegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }
        
        // Request turn credentials. Not that we might obtain nil here, which is the case when the user
        // has no subscription. In that case, the transfer will have to be performed on the same local network.
        
        let turnCredentials = try await delegate.getWellKnownTurnCredentials(self, ownedCryptoId: ownedCryptoId)
        
        // Create the peer connection
        
        let iceServer = WebRTC.RTCIceServer(urlStrings: ObvAppCoreConstants.ICEServerURLs.preferred,
                                            username: turnCredentials?.callerUsername,
                                            credential: turnCredentials?.callerPassword,
                                            tlsCertPolicy: .insecureNoCheck)
        
        let rtcConfiguration = RTCConfiguration()
        rtcConfiguration.iceServers = [iceServer]
        rtcConfiguration.iceTransportPolicy = .all
        rtcConfiguration.sdpSemantics = .unifiedPlan
        rtcConfiguration.continualGatheringPolicy = .gatherContinually
        
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        
        guard let peerConnection = factory.peerConnection(with: rtcConfiguration,
                                                          constraints: constraints,
                                                          delegate: rtcDelegate) else {
            assertionFailure()
            throw ObvError.peerConnectionCreationFailed
        }
        
        // Keep a strong pointer on the peer connection
        
        self.peerConnection = peerConnection
        
        // If we are the source, create the data channel, keep a strong pointer to it, create offer, set it locally and send it.
        
        switch role {
        case .destination:
            break
        case .source:
            
            let configuration = Self.createRTCDataChannelConfiguration()
            guard let dataChannel = peerConnection.dataChannel(forLabel: "data-channel-1", configuration: configuration) else {
                assertionFailure()
                throw ObvError.dataChannelCreationFailed
            }
            dataChannel.delegate = rtcDelegate
            self.dataChannel = dataChannel
            
            let offer: RTCSessionDescription = try await peerConnection.offer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
            
            Self.logger.debug("📰 Offer:\n\(offer.sdp)")
            
            queueForWebRTC.sync {
                Self.logger.debug("📰 Will set local description")
                peerConnection.setLocalDescription(offer) { error in
                    assert(error == nil)
                    Self.logger.debug("📰 Did set local description")
                }
            }
            
            Task {
                guard !Task.isCancelled else { return }
                do {
                    try await delegate.sendSignalingMessage(
                        self,
                        signalingMessage: .sdp(transferId: self.internalTransferId, sdp: .init(sdp: offer)),
                        toOtherOwnedDevice: otherOwnedDeviceIdentifier)
                } catch {
                    assertionFailure()
                }
            }
            
        }
        
    }
    
    
    func getAsyncStreamOfTransferTransportLayerState() -> AsyncStream<TransferTransportLayerState> {
        let stream = AsyncStream<TransferTransportLayerState> { (continuation: AsyncStream<TransferTransportLayerState>.Continuation) in
            continuationForTransferTransportLayerState?.finish()
            continuationForTransferTransportLayerState = continuation
            yieldAllTransferTransportLayerStates()
        }
        return stream
    }
    
    
    func userWantsToCancelTransfer(cancelSource: TransferTransportCancelSource) async {
        Self.logger.debug("📰⛔️ User wants to cancel transfer. Cancel source is \(cancelSource).")
        if let continuation = continuationOnPeerConnectionAvailability {
            self.continuationOnPeerConnectionAvailability = nil
            continuation.resume(throwing: CancellationError())
        }
        self.closeEverything()
        setTransferTransportLayerState(to: .closed(exportWasCancelledByUser: true))
    }
    
    
    func disconnect() {
        Self.logger.debug("📰 Call to resetAll on WebRTC.")
        self.closeEverything()
        setTransferTransportLayerState(to: .closed(exportWasCancelledByUser: false))
    }

}


// MARK: - Implementing TransferTransportSendJsonMessageDelegateForSource

extension WebRTCTransferTransportDelegate: TransferTransportSendJsonMessageDelegateForSource {
    
    func send(srcTransferDone: SrcTransferDone, progressUpdater: any DoneProgressUpdater) async throws {
        let jsonEncoder = JSONEncoder()
        let serializedMessage: Data = try jsonEncoder.encode(srcTransferDone)
        try await self.sendMessage(type: .sourceTransferDone, serializedMessage: serializedMessage)
    }
    
    
    func send(srcDiscussionList: SrcDiscussionList) async throws -> DstExpectedSha256 {
        
        let jsonEncoder = JSONEncoder()
        let serializedMessage: Data = try jsonEncoder.encode(srcDiscussionList)
        try await self.sendMessage(type: .sourceDiscussionList, serializedMessage: serializedMessage)
        
        return try await messageDispatchers.dstExpectedSha256MessageDispatcher.receiveMessage()

    }
    
    
    func send(srcDiscussionRanges: SrcDiscussionRanges) async throws -> DstDiscussionExpectedRanges {

        let discussionIdentifier = srcDiscussionRanges.discussionIdentifier

        let jsonEncoder = JSONEncoder()
        let serializedMessage: Data = try jsonEncoder.encode(srcDiscussionRanges)
        try await self.sendMessage(type: .sourceDiscussionRanges, serializedMessage: serializedMessage)
        
        return try await messageDispatchers.dstDiscussionExpectedRangesMessageDispatcher.receiveDstDiscussionExpectedRanges(discussionIdentifier: discussionIdentifier)

    }

    
    func send(srcMessages: SrcMessages) async throws {
        let jsonEncoder = JSONEncoder()
        let serializedMessage: Data = try jsonEncoder.encode(srcMessages)
        try await self.sendMessage(type: .sourceMessages, serializedMessage: serializedMessage)
    }

    
    func send(srcDiscussionDone: SrcDiscussionDone) async throws {
        let jsonEncoder = JSONEncoder()
        let serializedMessage: Data = try jsonEncoder.encode(srcDiscussionDone)
        try await self.sendMessage(type: .sourceDiscussionDone, serializedMessage: serializedMessage)
    }

    
    
    /// The progress updater should be passed the latest total number of bytes sent
    func send(attachmentAtURL url: URL, sha256: Data, progressUpdater: any FyleProgressUpdater) async throws {
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        var totalNumberOfFyleBytesSent: UInt64 = 0
        while let dataReadFromFile = try fh.read(upToCount: Self.maxFileBufferSize), !dataReadFromFile.isEmpty {
            try Task.checkCancellation()
            let currentOffset: Data = totalNumberOfFyleBytesSent.to8Bytes()
            let serializedMessage = sha256 + currentOffset + dataReadFromFile
            try await self.sendMessage(type: .sourceSha256, serializedMessage: serializedMessage)
            totalNumberOfFyleBytesSent += UInt64(dataReadFromFile.count)
            await progressUpdater.updateFyleProgress(sha256: sha256, totalNumberOfFyleBytesSent: totalNumberOfFyleBytesSent)
        }
    }


    func getMessageBatchSize() async -> Int {
        return 10
    }
    
    
    /// When the source knows about all the attachments the destination is expecting, it calls this method, which returns a stream of the sha256 that should be sent immediately.
    func receiveSha256sRequestedByDestination(allSha256ExpectedByDestination: DstExpectedSha256) async throws -> AsyncThrowingStream<Data, Error> {
        return await self.messageDispatchers.dstRequestSha256sDispatcher.receiveSha256sRequestedByDestination(allSha256ExpectedByDestination: allSha256ExpectedByDestination)
    }


    private func sendMessage(type: TransferMessageType, serializedMessage: Data) async throws {
        
        let sentMessageUuid = UUID()
        
        Self.logger.debug("📰 Will send message \(type)")
        
        let stream = await rtcDataBufferHandler.createRTCDataBuffersToSend(type: type, serializedMessage: serializedMessage)
        
        for await (messageAndChunkNumber, rtcDataBuffer) in stream {
            if type != .ack {
                await self.messageDispatchers.ackDispatcher.newUnackedSentMessages(
                    sentMessageUuid: sentMessageUuid,
                    messageAndChunkNumber: messageAndChunkNumber)
            }
            Self.logger.debug("📰 Will send chunk \(type)")
            try await sendOnDataChannel(rtcDataBuffer)
            Self.logger.debug("📰 Did send chunk \(type)")
        }
                
        if type != .ack {
            Self.logger.debug("📰 Did send message \(type), will wait until all acks are received")
            try await self.messageDispatchers.ackDispatcher.waitUntilAllSentMessageAcksAreReceived(sentMessageUuid: sentMessageUuid)
            Self.logger.debug("📰 Did send message \(type), all acks were received")
        } else {
            Self.logger.debug("📰 Did send message \(type)")
        }

    }

}


// MARK: - Implementing TransferTransportSendJsonMessageDelegateForDestination

extension WebRTCTransferTransportDelegate: TransferTransportSendJsonMessageDelegateForDestination {
        
    func receiveSrcDiscussionList() async throws -> SrcDiscussionList {
        return try await self.messageDispatchers.srcDiscussionListMessageDispatcher.receiveMessage()
    }
    
    /// We expect to receive one `SrcDiscussionRanges` message from the source per discussion identifier.
    func receiveSrcDiscussionRanges(expectedDiscussionIdentifiers: [JsonDiscussionIdentifier]) async throws -> AsyncThrowingStream<SrcDiscussionRanges, Error> {
        return await self.messageDispatchers.srcDiscussionRangesMessageDispatcher.destinationTransferStepsRequestsStreamOfSrcDiscussionRanges(expectedDiscussionIdentifiers: expectedDiscussionIdentifiers)
    }
    
    
    func send(dstExpectedSha256: DstExpectedSha256) async throws {
        let jsonEncoder = JSONEncoder()
        let serializedMessage: Data = try jsonEncoder.encode(dstExpectedSha256)
        try await self.sendMessage(
            type: .destinationExpectedSha256,
            serializedMessage: serializedMessage)
    }
    
    
    func send(dstDiscussionExpectedRanges: DstDiscussionExpectedRanges) async throws {
        let jsonEncoder = JSONEncoder()
        let serializedMessage: Data = try jsonEncoder.encode(dstDiscussionExpectedRanges)
        try await self.sendMessage(
            type: .destinationExpectedRanges,
            serializedMessage: serializedMessage)
    }
    
    
    func receiveStreamOfSrcMessages(numberOfExpectedMessages: Int) async throws -> AsyncThrowingStream<SrcMessages, Error> {
        return await self.messageDispatchers.srcMessagesDispatcher.destinationTransferStepsRequestsStreamOfSrcMessages(numberOfExpectedMessages: numberOfExpectedMessages)
    }

    
    /// Sent by the source, when requesting an attachment. The URL returned is a temporary URL pointing to the attachment.
    func send(dstRequestSha256: DstRequestSha256, expectedFileSize: UInt64, progressUpdater: any FyleProgressUpdater) async throws -> URL {
        let jsonEncoder = JSONEncoder()
        let serializedMessage: Data = try jsonEncoder.encode(dstRequestSha256)
        try await self.sendMessage(
            type: .destinationRequestSha256,
            serializedMessage: serializedMessage)
        let stream = await self.messageDispatchers.srcSha256Dispatcher.getStreamOfReceivedFileProgress(
            sha256: dstRequestSha256.sha256,
            expectedFileSize: expectedFileSize)
        for try await fileReceptionProgress in stream {
            switch fileReceptionProgress {
            case .inProgress(sha256: let sha256, currentFileSize: let currentFileSize):
                try Task.checkCancellation()
                Task { await progressUpdater.updateFyleProgress(sha256: sha256, totalNumberOfFyleBytesSent: currentFileSize) }
            case .fileReceived(sha256: _, url: let url):
                return url
            }
        }
        try Task.checkCancellation()
        assertionFailure("Unexpected. The stream should not finish without returning a URL or throwing (unless the task is cancelled).")
        throw ObvError.attachmentReceptionFailed
    }

    
    func send(dstDoNotRequestSha256: DstDoNotRequestSha256) async throws {
        let jsonEncoder = JSONEncoder()
        let serializedMessage: Data = try jsonEncoder.encode(dstDoNotRequestSha256)
        try await self.sendMessage(
            type: .destinationDoNotRequestSha256,
            serializedMessage: serializedMessage)
    }

}

// MARK: - Methods called by the TransferService, specific to WebRTC

extension WebRTCTransferTransportDelegate {
    
    private func awaitPeerConnection() async throws -> RTCPeerConnection {
        if let peerConnection { return peerConnection }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RTCPeerConnection, any Error>) in
            if let peerConnection { return continuation.resume(returning: peerConnection) }
            // The peer connection is not available, we store the continuation.
            self.continuationOnPeerConnectionAvailability = continuation
        }
    }
    
    func handleReceivedSdp(transferId: String, receivedSdp: WebrtcHistoryTransferMessage.Sdp) async throws {
        
        Self.logger.debug("📰 handleReceivedSdp")
        
        guard self.internalTransferId == transferId else { assertionFailure(); return }
        
        guard let delegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }
        
        guard !self.transferTransportLayerState.isClosed else { return }
        
        // Make sure we receive the appropriate SDP type given our role

        guard receivedSdpIsAppropriateForOurRole(sdp: receivedSdp) else {
            //assertionFailure()
            throw ObvError.receivedWrongTypeOfSdp
        }

        // Make sure we have a peerConnection (which is always the case, provided that
        // `func connect() async throws` was called, as appropriate)
        
        let peerConnection = try await awaitPeerConnection()
        
        // Set the remote sdp
        
        Self.logger.debug("📰 Received SDP:\n\(receivedSdp.sdp)")

        let rtcSessionDescription = RTCSessionDescription(type: .init(receivedSdp.type), sdp: receivedSdp.sdp)
        queueForWebRTC.sync {
            Self.logger.debug("📰 Will set remote description")
            peerConnection.setRemoteDescription(rtcSessionDescription) { error in
                assert(error == nil)
                Self.logger.debug("📰 Did set remote description")
            }
        }

        // If we are the destination, create an answer, set it locally, and send it back to the source
        
        switch role {
        case .source:
            break
        case .destination:
            let answer = try await peerConnection.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
            queueForWebRTC.sync {
                Self.logger.debug("📰 Will set local description")
                peerConnection.setLocalDescription(answer) { error in
                    assert(error == nil)
                    Self.logger.debug("📰 Did set local description")
                }
            }
            // At this point, the state should transition to RTCSignalingState.stable (and thus, we will have ICE candidates to send)
            // We send the answer back to the source.
            Task {
                guard !Task.isCancelled else { return }
                do {
                    try await delegate.sendSignalingMessage(
                        self,
                        signalingMessage: .sdp(transferId: self.internalTransferId, sdp: .init(sdp: answer)),
                        toOtherOwnedDevice: otherOwnedDeviceIdentifier)
                } catch {
                    assertionFailure()
                }
            }
        }
        
    }
    
    
    /// Handles a received batch of ICE candidates.
    ///
    /// If the peer connection is in the stable state, we add all the ICE candidates immediately. If not, we store the candidates for later. They will be added
    /// as soon as the peer connection reaches the stable state.
    func handleReceivedIceCandidates(transferId: String, receivedIceCandidates: [WebrtcHistoryTransferMessage.ICECandidate]) async throws {
        guard self.internalTransferId == transferId else { assertionFailure(); return }
        try Task.checkCancellation()
        Self.logger.debug("📰 Did receive \(receivedIceCandidates.count) ICE candidates")
        let iceCandidates: [RTCIceCandidate] = receivedIceCandidates.map { .init($0) }
        let peerConnection = try await awaitPeerConnection()
        // If the peer connection is in the signaling state, we add the received ICE candidates.
        // Otherwise, we store them for later.
        pendingReceivedIceCandidates = iceCandidates.reversed() + pendingReceivedIceCandidates
        if peerConnection.signalingState == .stable {
            try addPendingReceivedIceCandidatesAsPeerConnectionIsStable()
        }
    }
    
}


// MARK: - Private helpers


extension WebRTCTransferTransportDelegate {
    
    private func closeEverything() {
        queueForWebRTC.sync {
            dataChannel?.close()
            peerConnection?.close()
            dataChannel = nil
            peerConnection = nil
        }
    }
    
}

extension WebRTCTransferTransportDelegate {
    
    private func sendOnDataChannel(_ rtcDataBuffer: RTCDataBuffer) async throws {
        try Task.checkCancellation()
        guard !self.transferTransportLayerState.isClosed else { throw CancellationError() }
        // Wait until sending more data if our buffer is already encumbered
        guard let dataChannel else {
            assertionFailure()
            throw ObvError.dataChannelCreationFailed
        }
        while !Task.isCancelled && dataChannel.bufferedAmount > 50 * Self.maxDataChannelMessageSize {
            try await Task.sleep(milliseconds: 30)
        }
        try Task.checkCancellation()
        dataChannel.sendData(rtcDataBuffer)
    }
    
    
    private func addPendingReceivedIceCandidatesAsPeerConnectionIsStable() throws {
        guard let peerConnection else {
            assertionFailure()
            throw ObvError.connectWasNotCalledAsPeerConnectionIsNil
        }
        while let receivedIceCandidate = pendingReceivedIceCandidates.popLast() {
            //Self.logger.debug("📰 Will add a received ICE candidate")
            queueForWebRTC.sync {
                peerConnection.add(receivedIceCandidate) { error in
                    assert(error == nil)
                    //Self.logger.debug("📰 Did add a received ICE candidate")
                }
            }
        }
    }
 
    
    private func sendPendingGeneratedIceCandidatesAsPeerConnectionIsStable() async throws {
        try Task.checkCancellation()
        guard !pendingGeneratedIceCandidates.isEmpty else { return }
        guard let delegate else {
            assertionFailure()
            throw ObvError.connectWasNotCalledAsPeerConnectionIsNil
        }
        let iceCandidates: [WebrtcHistoryTransferMessage.ICECandidate] = pendingGeneratedIceCandidates.map { .init(candidate: $0) }
        pendingGeneratedIceCandidates = []
        Self.logger.debug("📰 Will send \(iceCandidates.count) generated ICE candidates")
        do {
            try Task.checkCancellation()
            try await delegate.sendSignalingMessage(
                self,
                signalingMessage: .iceCandidates(transferId: self.internalTransferId, iceCandidates: iceCandidates),
                toOtherOwnedDevice: otherOwnedDeviceIdentifier)
        } catch {
            assertionFailure()
        }
    }
    
    
    private func setTransferTransportLayerState(to newTransferTransportLayerState: TransferTransportLayerState) {
        guard self.transferTransportLayerState != newTransferTransportLayerState else { return }
        guard !self.transferTransportLayerState.isClosed else { return }
        transferTransportLayerState = newTransferTransportLayerState
        transferTransportLayerStateOnSetContinuation.insert(newTransferTransportLayerState, at: 0)
        yieldAllTransferTransportLayerStates()
    }
    
    
    /// Called when the continuation is set, and whenever the transfer transport layer state changes.
    private func yieldAllTransferTransportLayerStates() {
        if let lastYieldedTransferTransportLayerState {
            guard !lastYieldedTransferTransportLayerState.isClosed else { return }
        }
        guard let continuationForTransferTransportLayerState else { return }
        while let state = transferTransportLayerStateOnSetContinuation.popLast() {
            if self.lastYieldedTransferTransportLayerState != state {
                self.lastYieldedTransferTransportLayerState = state
                continuationForTransferTransportLayerState.yield(state)
            }
        }
    }

}


// MARK: - Helpers

extension WebRTCTransferTransportDelegate {
    
    private static func createRTCDataChannelConfiguration() -> RTCDataChannelConfiguration {
        let configuration = RTCDataChannelConfiguration()
        configuration.isOrdered = true
        configuration.isNegotiated = false
        configuration.channelId = 1
        return configuration
    }

}


// MARK: - Implementing a local RTCPeerConnectionDelegate and RTCDataChannelDelegate

/// This class serves as an `RTCPeerConnectionDelegate` for the peer connection created by the `WebRTCTransferTransportDelegate` and
/// as an `RTCDataChannelDelegate` for the data channel of the peer connection.
///
/// The `WebRTCTransferTransportDelegate` cannot be a delegate of the data channel its peer connection as WebRTC imposes that a data channel
/// delegate is a subclass of `NSObject`. This class servers as an intermediary and forwards certain delegate calls to the
/// `WebRTCTransferTransportDelegate` actor.
///
/// The `WebRTCTransferTransportDelegate` cannot be a delegate of its peer connection as WebRTC imposes that a peer
/// connection delegate is a subclass of `NSObject`. This class servers as an intermediary and forwards certain delegate calls to the
/// `WebRTCTransferTransportDelegate` actor.
///
private final class LocalRTCDelegate: NSObject, @unchecked Sendable {

    private let internalQueue = DispatchQueue(label: "LocalRTCDataChannelDelegate internal queue")
    
    private var continuationForGeneratedIceCandidates: AsyncStream<RTCIceCandidate>.Continuation?
    private var pendingGeneratedIceCandidates = [RTCIceCandidate]()

    private var continuationPeerConnectionSignalingState: AsyncStream<RTCSignalingState>.Continuation?
    private var peerConnectionSignalingStatesOnSetContinuation = [RTCSignalingState]()
    private var lastYieldedPeerConnectionSignalingState: RTCSignalingState?
    
    private var continuationDataChannelState: AsyncStream<RTCDataChannelState>.Continuation?
    private var dataChannelStatesOnSetContinuation = [RTCDataChannelState]()
    private var lastYieldedDataChannelState: RTCDataChannelState?
    
    private var continuationForReceivedRTCDataBuffer: AsyncStream<RTCDataBuffer>.Continuation?
    private var rtcDataBufferOnSetContinuation = [RTCDataBuffer]()
    
    private var continuationForRTCIceConnectionState: AsyncStream<RTCIceConnectionState>.Continuation?
    private var rtcIceConnectionStateBuffer = [RTCIceConnectionState]()
    
    private let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "LocalRTCDelegate")
    
    fileprivate var onPeerConnectionDidOpenDataChannelOnDestination: ((RTCDataChannel) async -> Void)?
    
    func getAsyncStreamOfRTCDataBuffer() -> AsyncStream<RTCDataBuffer> {
        let stream = AsyncStream<RTCDataBuffer> { (continuation: AsyncStream<RTCDataBuffer>.Continuation) in
            internalQueue.async { [weak self] in
                guard let self else { return }
                continuationForReceivedRTCDataBuffer?.finish()
                continuationForReceivedRTCDataBuffer = continuation
                while let rtcDataBuffer = rtcDataBufferOnSetContinuation.popLast() {
                    continuation.yield(rtcDataBuffer)
                }
            }
        }
        return stream
    }
    
        
    func getAsyncStreamOfGeneratedIceCandidates() -> AsyncStream<RTCIceCandidate> {
        let stream = AsyncStream<RTCIceCandidate> { (continuation: AsyncStream<RTCIceCandidate>.Continuation) in
            internalQueue.async { [weak self] in
                guard let self else { return }
                continuationForGeneratedIceCandidates?.finish()
                continuationForGeneratedIceCandidates = continuation
                while let previousCandidate = pendingGeneratedIceCandidates.popLast() {
                    continuation.yield(previousCandidate)
                }
            }
        }
        return stream
    }
    
    
    func getAsyncStreamOfRTCSignalingState() -> AsyncStream<RTCSignalingState> {
        let stream = AsyncStream<RTCSignalingState> { (continuation: AsyncStream<RTCSignalingState>.Continuation) in
            internalQueue.async { [weak self] in
                guard let self else { return }
                continuationPeerConnectionSignalingState?.finish()
                continuationPeerConnectionSignalingState = continuation
                while let previousState = peerConnectionSignalingStatesOnSetContinuation.popLast() {
                    continuation.yield(previousState)
                }
            }
        }
        return stream
    }
    
    
    func getAsyncStreamOfRTCDataChannelState() -> AsyncStream<RTCDataChannelState> {
        let stream = AsyncStream<RTCDataChannelState> { (continuation: AsyncStream<RTCDataChannelState>.Continuation) in
            internalQueue.async { [weak self] in
                guard let self else { return }
                continuationDataChannelState?.finish()
                continuationDataChannelState = continuation
                while let previousState = dataChannelStatesOnSetContinuation.popLast() {
                    if lastYieldedDataChannelState != previousState {
                        lastYieldedDataChannelState = previousState
                        continuation.yield(previousState)
                    }
                }
            }
        }
        return stream
    }
    
    
    func getAsyncStreamOfRTCIceConnectionState() -> AsyncStream<RTCIceConnectionState> {
        let stream = AsyncStream<RTCIceConnectionState> { (continuation: AsyncStream<RTCIceConnectionState>.Continuation) in
            internalQueue.async { [weak self] in
                guard let self else { return }
                self.continuationForRTCIceConnectionState?.finish()
                self.continuationForRTCIceConnectionState = continuation
                yieldAllRTCIceConnectionStatesIfPossible()
            }
        }
        return stream
    }
    
    
    private func yieldAllRTCIceConnectionStatesIfPossible() {
        guard let continuationForRTCIceConnectionState else { return }
        while let rtcIceConnectionState = self.rtcIceConnectionStateBuffer.popLast() {
            continuationForRTCIceConnectionState.yield(rtcIceConnectionState)
        }
    }

}


extension LocalRTCDelegate: RTCDataChannelDelegate {
    
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        logger.debug("📰 DataChannel did change state: \(dataChannel.readyState.description)")
        let readyState = dataChannel.readyState
        internalQueue.async { [weak self] in
            guard let self else { return }
            if let continuationDataChannelState {
                if lastYieldedDataChannelState != readyState {
                    lastYieldedDataChannelState = readyState
                    continuationDataChannelState.yield(readyState)
                }
            } else {
                dataChannelStatesOnSetContinuation.insert(readyState, at: 0)
            }
        }
    }

    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        logger.debug("📰 dataChannel didReceiveMessageWith")
        internalQueue.async { [weak self] in
            guard let self else { return }
            if let continuationForReceivedRTCDataBuffer {
                continuationForReceivedRTCDataBuffer.yield(buffer)
            } else {
                rtcDataBufferOnSetContinuation.insert(buffer, at: 0)
            }
        }
    }

}


extension LocalRTCDelegate: RTCPeerConnectionDelegate {
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        logger.debug("📰 peerConnection didChange RTCSignalingState to \(stateChanged.debugDescription)")
        internalQueue.async { [weak self] in
            guard let self else { return }
            if let continuationPeerConnectionSignalingState {
                if lastYieldedPeerConnectionSignalingState != stateChanged {
                    lastYieldedPeerConnectionSignalingState = stateChanged
                    continuationPeerConnectionSignalingState.yield(stateChanged)
                }
            } else {
                peerConnectionSignalingStatesOnSetContinuation.insert(stateChanged, at: 0)
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        logger.debug("📰 peerConnection didAdd RTCMediaStream")
        // TODO
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        logger.debug("📰 peerConnection didRemove RTCMediaStream")
        // TODO
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        logger.debug("📰 peerConnectionShouldNegotiate")
        // TODO
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        logger.debug("📰 peerConnection didChange RTCIceConnectionState: \(newState.debugDescription)")
        internalQueue.async { [weak self] in
            guard let self else { return }
            self.rtcIceConnectionStateBuffer.insert(newState, at: 0)
            self.yieldAllRTCIceConnectionStatesIfPossible()
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        logger.debug("📰 peerConnection didChange RTCIceGatheringState")
        // TODO
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        //logger.debug("📰 peerConnection didGenerate RTCIceCandidate")
        if let continuationForGeneratedIceCandidates {
            internalQueue.async { [weak self] in
                guard let self else { return }
                while let previousCandidate = pendingGeneratedIceCandidates.popLast() {
                    continuationForGeneratedIceCandidates.yield(previousCandidate)
                }
                continuationForGeneratedIceCandidates.yield(candidate)
            }
        } else {
            internalQueue.async { [weak self] in
                guard let self else { return }
                pendingGeneratedIceCandidates.insert(candidate, at: 0)
            }
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        logger.debug("📰 peerConnection didRemove [RTCIceCandidate]")
        // TODO
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        logger.debug("📰 peerConnection didOpen RTCDataChannel (called on the destination only)")
        assert(onPeerConnectionDidOpenDataChannelOnDestination != nil)
        dataChannel.delegate = self
        Task {
            await onPeerConnectionDidOpenDataChannelOnDestination?(dataChannel)
        }
    }

}


// MARK: - Errors

extension WebRTCTransferTransportDelegate {
    
    enum ObvError: Error {
        case delegateIsNil
        case peerConnectionCreationFailed
        case peerConnectionAlreadySet
        case dataChannelCreationFailed
        case receivedWrongTypeOfSdp
        case connectWasNotCalledAsPeerConnectionIsNil
        case attachmentReceptionFailed
    }
    
}


// MARK: - Helpers

extension RTCIceCandidate: @retroactive @unchecked(Sendable) {}
//extension RTCSessionDescription: @retroactive @unchecked(Sendable) {}


extension WebrtcHistoryTransferMessage.ICECandidate {
    
    init(candidate: RTCIceCandidate) {
        self.init(sdp: candidate.sdp,
                  sdpMLineIndex: Int(candidate.sdpMLineIndex),
                  sdpMid: candidate.sdpMid)
    }
    
}


extension RTCSdpType {
    
    init(_ type: WebrtcHistoryTransferMessage.Sdp.SdpType) {
        switch type {
        case .answer: self = .answer
        case .offer: self = .offer
        }
    }
    
}


fileprivate extension RTCSignalingState {
    
    var debugDescription: String {
        switch self {
        case .stable: return "stable"
        case .haveLocalOffer: return "haveLocalOffer"
        case .haveLocalPrAnswer: return "haveLocalPrAnswer"
        case .haveRemoteOffer: return "haveRemoteOffer"
        case .haveRemotePrAnswer: return "haveRemotePrAnswer"
        case .closed: return "closed"
        @unknown default:
            return "Unknown RTCSignalingState: \(rawValue)"
        }
    }
    
}


fileprivate extension RTCDataChannelState {

    var description: String {
        switch self {
        case .connecting: return "connecting"
        case .closed: return "closed"
        case .closing: return "closing"
        case .open: return "open"
        default:
            assertionFailure()
            return "unknown"
        }
    }

}


extension WebRTCTransferTransportDelegate {
    
    private func receivedSdpIsAppropriateForOurRole(sdp: WebrtcHistoryTransferMessage.Sdp) -> Bool {
        
        switch sdp.type {
        case .offer:
            switch role {
            case .source:
                return false
            case .destination:
                return true
            }
        case .answer:
            switch role {
            case .source:
                return true
            case .destination:
                return false
            }
        }

    }
    
}


extension RTCIceCandidate {
    
    convenience init(_ iceCandidate: WebrtcHistoryTransferMessage.ICECandidate) {
        self.init(sdp: iceCandidate.sdp, sdpMLineIndex: Int32(iceCandidate.sdpMLineIndex), sdpMid: iceCandidate.sdpMid)
    }
    
}


fileprivate extension RTCIceConnectionState {
    
    var debugDescription: String {
        switch self {
        case .new: return "new"
        case .checking: return "checking"
        case .connected: return "connected"
        case .completed: return "completed"
        case .failed: return "failed"
        case .disconnected: return "disconnected"
        case .closed: return "closed"
        case .count: return "count"
        @unknown default:
            return "Unknown state \(rawValue)"
        }
    }
    
}


extension RTCDataChannel: @unchecked @retroactive Sendable {}

extension RTCDataBuffer: @unchecked @retroactive Sendable {}

extension RTCPeerConnection: @unchecked @retroactive Sendable {}

extension  RTCDataChannelState {
    
    var debugDescription: String {
        switch self {
        case .connecting: return "connecting"
        case .open: return "open"
        case .closing: return "closing"
        case .closed: return "closed"
        @unknown default:  return "unknown default"
        }
        
    }
    
}

//    private func transferTransportLayerStateFrom(dataChannelState: RTCDataChannelState) -> TransferTransportLayerState {
//        switch dataChannelState {
//        case .open: return .ready
//        case .closing: return .closed
//        case .closed: return .closed
//        case .connecting: return .connecting
//        @unknown default:
//            assertionFailure()
//            return .connecting
//        }
//    }


