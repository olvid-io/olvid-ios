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


#if canImport(WiFiAware)
import Foundation
import OSLog
import WiFiAware
import Network
import ObvTypes
import ObvAppCoreConstants


@available(iOS 26.0, *)
public actor WifiAwareTransferTransportDelegate {
    
    let ownedCryptoId: ObvTypes.ObvCryptoId
    let wifiAwareTransferRole: WifiAwareTransferRole
    let pairedDevice: ObvWAPairedDevice
    
    /// Emits lifecycle events about the listener or browser (e.g. running, stopped).
    /// Consumed by the event handler task within `WifiAwareTransferTransportDelegate`
    /// alongside the identically-named stream from `ConnectionManager`.
    let localEvents: AsyncStream<LocalEvent>
    private let localEventsContinuation: AsyncStream<LocalEvent>.Continuation
    
    private let connectionManager = ConnectionManager()

    private let messageDispatchers = MessageDispatchers()

    private(set) var transferTransportLayerState: TransferTransportLayerState = .initializing
    private var continuationForTransferTransportLayerState: AsyncStream<TransferTransportLayerState>.Continuation?
    private var transferTransportLayerStateOnSetContinuation = [TransferTransportLayerState]()
    private var lastYieldedTransferTransportLayerState: TransferTransportLayerState?

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "WifiAwareTransferTransportDelegate")

    private let appPerformanceMode: WAPerformanceMode = .realtime

    private var connection: NetworkConnection<Coder<NetworkEvent, NetworkEvent, NetworkJSONCoder>>?
    
    private var networkState: WifiAwareState.NetworkState
    private var deviceConnection: (pairedDevice: WAPairedDevice, connectionDetail: ConnectionDetail)?

    private var eventHandlerTasks: [Task<Void, Error>] = []
    private var networkTask: Task<Void, Error>?

    private var exportWasCancelledByUser = false
    private var isDisconnectRequested = false
    
    private var startStreamingMessageReceived = false // Used on the source, when receiving the startStreaming from the destination
    
    private static let maxFileBufferSize: Int = 300_000 // 300kB
    
    private weak var delegate: WifiAwareTransferTransportDelegateDelegate?
    
    private(set) var transferId: String? // Known at init time on the source, but not on the destination
    
    var role: TransferRole {
        wifiAwareTransferRole.toTransferRole
    }
    
    init(role: WifiAwareTransferRole,
         ownedCryptoId: ObvTypes.ObvCryptoId,
         pairedDevice: ObvWAPairedDevice,
         delegate: WifiAwareTransferTransportDelegateDelegate
    ) {
        
        self.wifiAwareTransferRole = role
        self.ownedCryptoId = ownedCryptoId
        self.pairedDevice = pairedDevice
        (self.localEvents, self.localEventsContinuation) = AsyncStream.makeStream(of: LocalEvent.self)
        switch role {
        case .source:
            self.networkState = .source(.stopped)
        case .destination:
            self.networkState = .destination(.stopped)
        }
        self.delegate = delegate
        switch role {
        case .source(transferId: let transferId, scope: _):
            self.transferId = transferId
        case .destination:
            self.transferId = nil // Will be received from the source
        }
        
        Task { await setupAllEventHandlers() }

    }
    
    
    private func setupAllEventHandlers() {
        eventHandlerTasks.append(setupEventHandler(for: self.localEvents))
        eventHandlerTasks.append(setupEventHandler(for: connectionManager.localEvents))
        eventHandlerTasks.append(setupEventHandler(for: connectionManager.networkEvents))
    }
    
    
    /// Drains an `AsyncStream` in a background task and dispatches each event to the
    /// appropriate handler.
    ///
    /// Because `LocalEvent` and `NetworkEvent` share the same generic plumbing, the
    /// type is inferred from the stream's element type at call site. Called three times
    /// during initialization — once for the delegate's own local events stream, once for
    /// `ConnectionManager`'s local events, and once for `ConnectionManager`'s network events.
    private func setupEventHandler<T>(for stream: AsyncStream<T>) -> Task<Void, Error> {
        return Task {
            for await event in stream {
                if T.self == LocalEvent.self {
                    await handleLocalEvent(event as? LocalEvent)
                } else if T.self == NetworkEvent.self {
                    await handleNetworkEvent(event as? NetworkEvent)
                }
            }
        }
    }

 
    deinit {
        debugPrint("Deinit")
    }
    
    
    func sendInterruptMessage() async throws {
        try await self.send(.userWantsToCancelTransfer)
    }
    
}


// MARK: - Implementing TransferTransportDelegate

@available(iOS 26.0, *)
extension WifiAwareTransferTransportDelegate: TransferTransportDelegate {
    
    func connect(progressUpdater: any ConnectProgressUpdater) async throws {
        
        // The progressUpdater is not used for the Wi-fi Aware method

        Self.logger.debug("📰 WifiAwareTransferTransportDelegate: Call to connect()")

        networkTask = Task {
            _ = try await withTaskCancellationHandler {
                switch role {
                case .source:
                    try await listen()
                case .destination:
                    try await browse()
                }
            } onCancel: {
                Task { await setNetworkStateToStopped() }
            }
            
            
        }
        
    }
    

    func getAsyncStreamOfTransferTransportLayerState() async -> AsyncStream<TransferTransportLayerState> {
        let stream = AsyncStream<TransferTransportLayerState> { (continuation: AsyncStream<TransferTransportLayerState>.Continuation) in
            continuationForTransferTransportLayerState?.finish()
            continuationForTransferTransportLayerState = continuation
            yieldAllTransferTransportLayerStates()
        }
        return stream
    }
    
    
    func userWantsToCancelTransfer(cancelSource: TransferTransportCancelSource) async {
        Self.logger.debug("📰⛔️ User wants to cancel transfer. Cancel source is \(cancelSource).")
        self.exportWasCancelledByUser = true
        await self.disconnect()
    }
    

    func disconnect() async {
        self.isDisconnectRequested = true
        if let pairedDevice = self.deviceConnection?.pairedDevice {
            await self.stopConnection(to: pairedDevice)
        }
        for task in eventHandlerTasks {
            task.cancel()
        }
        eventHandlerTasks.removeAll()
        localEventsContinuation.finish()
        continuationForTransferTransportLayerState?.finish()
        continuationForTransferTransportLayerState = nil
        networkTask?.cancel()
        networkTask = nil
    }
    
    
    func send(srcDiscussionList: SrcDiscussionList) async throws -> DstExpectedSha256 {
        try await self.send(.srcDiscussionList(srcDiscussionList))
        return try await messageDispatchers.dstExpectedSha256MessageDispatcher.receiveMessage()
    }
    
    
    func send(srcDiscussionRanges: SrcDiscussionRanges) async throws -> DstDiscussionExpectedRanges {
        let discussionIdentifier = srcDiscussionRanges.discussionIdentifier
        try await self.send(.srcDiscussionRanges(srcDiscussionRanges))
        return try await messageDispatchers.dstDiscussionExpectedRangesMessageDispatcher.receiveDstDiscussionExpectedRanges(discussionIdentifier: discussionIdentifier)
    }
    
    func send(srcMessages: SrcMessages) async throws {
        try await self.send(.srcMessages(srcMessages))
    }
    
    func send(srcDiscussionDone: SrcDiscussionDone) async throws {
        try await self.send(.srcDiscussionDone(srcDiscussionDone))
    }
    
    func send(attachmentAtURL url: URL, sha256: Data, progressUpdater: any FyleProgressUpdater) async throws {
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        var totalNumberOfFyleBytesSent: UInt64 = 0
        while let dataReadFromFile = try fh.read(upToCount: Self.maxFileBufferSize), !dataReadFromFile.isEmpty {
            try Task.checkCancellation()
            let currentOffset: Data = totalNumberOfFyleBytesSent.to8Bytes()
            let serializedMessage = sha256 + currentOffset + dataReadFromFile
            try await send(.sourceSha256(serializedMessage: serializedMessage))
            totalNumberOfFyleBytesSent += UInt64(dataReadFromFile.count)
            await progressUpdater.updateFyleProgress(sha256: sha256, totalNumberOfFyleBytesSent: totalNumberOfFyleBytesSent)
        }
    }
    
    func send(srcTransferDone: SrcTransferDone, progressUpdater: any DoneProgressUpdater) async throws {
        try await self.send(.srcTransferDone(srcTransferDone))
    }
    
    func getMessageBatchSize() async -> Int {
        return 10
    }
    
    func receiveSha256sRequestedByDestination(allSha256ExpectedByDestination: DstExpectedSha256) async throws -> AsyncThrowingStream<Data, any Error> {
        return await self.messageDispatchers.dstRequestSha256sDispatcher.receiveSha256sRequestedByDestination(allSha256ExpectedByDestination: allSha256ExpectedByDestination)
    }
    
    func receiveSrcDiscussionList() async throws -> SrcDiscussionList {
        return try await self.messageDispatchers.srcDiscussionListMessageDispatcher.receiveMessage()
    }
    
    func receiveSrcDiscussionRanges(expectedDiscussionIdentifiers: [JsonDiscussionIdentifier]) async throws -> AsyncThrowingStream<SrcDiscussionRanges, any Error> {
        return await self.messageDispatchers.srcDiscussionRangesMessageDispatcher.destinationTransferStepsRequestsStreamOfSrcDiscussionRanges(expectedDiscussionIdentifiers: expectedDiscussionIdentifiers)
    }
    
    func send(dstExpectedSha256: DstExpectedSha256) async throws {
        try await self.send(.dstExpectedSha256(dstExpectedSha256))
    }
    
    func send(dstDiscussionExpectedRanges: DstDiscussionExpectedRanges) async throws {
        try await self.send(.dstDiscussionExpectedRanges(dstDiscussionExpectedRanges))
    }
    
    func receiveStreamOfSrcMessages(numberOfExpectedMessages: Int) async throws -> AsyncThrowingStream<SrcMessages, any Error> {
        return await self.messageDispatchers.srcMessagesDispatcher.destinationTransferStepsRequestsStreamOfSrcMessages(numberOfExpectedMessages: numberOfExpectedMessages)
    }
    
    func send(dstRequestSha256: DstRequestSha256, expectedFileSize: UInt64, progressUpdater: any FyleProgressUpdater) async throws -> URL {
        try await self.send(.dstRequestSha256(dstRequestSha256))
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
        try await send(.dstDoNotRequestSha256(dstDoNotRequestSha256))
    }
    
}


// MARK: - Private helpers

@available(iOS 26.0, *)
extension WifiAwareTransferTransportDelegate {
    
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


    /// Tears down the Wi-Fi Aware connection to a specific paired device.
    ///
    /// Looks up the active connection for the given `WAPairedDevice` and delegates
    /// to `ConnectionManager.stop(_:)`. The subsequent `.cancelled` state change
    /// in `setupStateUpdateHandler` will emit `.connection(.stopped(...))`, which
    /// cleans up `deviceConnections` and updates the UI.
    private func stopConnection(to device: WAPairedDevice) async {
        if let connection = self.deviceConnection?.connectionDetail.connection {
            await connectionManager.stop(connection)
        } else {
            Self.logger.error("📰 Unable to find the connection for \(device)")
        }
    }

}


// MARK: - Errors

@available(iOS 26.0, *)
extension WifiAwareTransferTransportDelegate {
    
    enum ObvError: Error {
        case chatHistoryTransferServiceWAPublishableServiceIsNil
        case chatHistoryTransferServiceWASubscribableService
        case attachmentReceptionFailed
        case noConnectionToPairedDevice
        case connectedToWrongDevice
    }
    
}


enum NetworkEvent: Codable, Sendable {
    case startStreaming // Sent by the destination to the source
    case transferId(transferId: String) // Sent by the source to the destination
    case srcDiscussionList(SrcDiscussionList)
    case srcDiscussionRanges(SrcDiscussionRanges)
    case srcMessages(SrcMessages)
    case srcDiscussionDone(SrcDiscussionDone)
    case sourceSha256(serializedMessage: Data)
    case srcTransferDone(SrcTransferDone)
    case dstExpectedSha256(DstExpectedSha256)
    case dstDiscussionExpectedRanges(DstDiscussionExpectedRanges)
    case dstRequestSha256(DstRequestSha256)
    case dstDoNotRequestSha256(DstDoNotRequestSha256)
    case userWantsToCancelTransfer
}


// MARK: - NetworkListener (Publisher) used by the source device

@available(iOS 26.0, *)
extension WifiAwareTransferTransportDelegate {
 
    /// Starts a Wi-Fi Aware `NetworkListener` that accepts incoming connections
    /// from the destination device.
    ///
    /// Called by `connect()` on the source device. The listener advertises the
    /// `chatHistoryTransferService` to all previously-paired devices, using TCP
    /// with realtime performance mode and `interactiveVideo` QoS. It suspends
    /// until the listener is cancelled or fails.
    ///
    /// State changes are translated into `LocalEvent.listenerRunning` or
    /// `.listenerStopped(error)` so the transfer state machine can update.
    /// Each accepted connection is handed to `ConnectionManager.add(_:)`, which starts
    /// listening for messages and monitoring the link.
    ///
    /// **Message flow once the destination connects:**
    /// The source does not send first. It waits for the destination to send `startStreaming`,
    /// after which the source is considered ready and can begin sending history transfer data.
    private func listen() async throws {
        
        assert(self.role == .source)
        
        Self.logger.info("📰 Start NetworkListener (Publisher) on the source device")

        // Constructs a `NetworkListener` to publish the service and accept connections from the selected paired device.
        guard let chatHistoryTransferService = WAPublishableService.chatHistoryTransferService else {
            assertionFailure()
            throw ObvError.chatHistoryTransferServiceWAPublishableServiceIsNil
        }
        try await NetworkListener(for:
            .wifiAware(.connecting(to: chatHistoryTransferService, from: .allPairedDevices)),
        using: .parameters {
            Coder(receiving: NetworkEvent.self, sending: NetworkEvent.self, using: NetworkJSONCoder()) {
                TCP()
            }
        }
        .wifiAware { $0.performanceMode = appPerformanceMode }
        .serviceClass(appServiceClass))
        .onStateUpdate { [weak self] listener, state in
            guard let self else { return }
            Self.logger.info("📰 \(String(describing: listener), privacy: .public): \(String(describing: state), privacy: .public)")

            switch state {
            case .setup, .waiting: break
            case .ready: self.localEventsContinuation.yield(.listenerRunning)
            case .failed(let error): self.localEventsContinuation.yield(.listenerStopped(error.wifiAware))
            case .cancelled: self.localEventsContinuation.yield(.listenerStopped(nil))
            default: break
            }
        }
        .run { connection in
            Self.logger.info("📰 Received connection: \(String(describing: connection), privacy: .public)")
            await self.connectionManager.add(connection)
        }
    }

}


// MARK: - NetworkBrowser (Subscriber) used by the destination device

@available(iOS 26.0, *)
extension WifiAwareTransferTransportDelegate {
    
    /// Starts a Wi-Fi Aware `NetworkBrowser` to discover and connect to the source device.
    ///
    /// Called by `connect()` on the destination device. The browser scans for paired devices
    /// advertising the `chatHistoryTransferService`. As soon as the first endpoint is found
    /// the browser stops, a `.connecting` event is emitted, and
    /// `ConnectionManager.setupConnection(to:)` creates the outbound TCP connection.
    ///
    /// Browser lifecycle changes are reported via `LocalEvent.browserRunning` and
    /// `.browserStopped(error)`. The method suspends until the first endpoint is found
    /// or an error occurs.
    ///
    /// **Message flow once connected:**
    /// The destination sends first: a single `startStreaming` message is sent immediately
    /// after the connection becomes ready (see `handleConnectionEvent(.ready(...))`).
    /// This signals to the source that the destination is ready to receive history transfer data.
    private func browse() async throws {
        Self.logger.info("📰 Start NetworkBrowser")

        guard let chatHistoryTransferService = WASubscribableService.chatHistoryTransferService else {
            assertionFailure()
            throw ObvError.chatHistoryTransferServiceWAPublishableServiceIsNil
        }

        let browser = NetworkBrowser(for:
            .wifiAware(.connecting(to: .allPairedDevices, from: chatHistoryTransferService))
        )
        .onStateUpdate { browser, state in
            Self.logger.info("📰 \(String(describing: browser), privacy: .public): \(String(describing: state), privacy: .public)")

            switch state {
            case .setup, .waiting: break
            case .ready: self.localEventsContinuation.yield(.browserRunning)
            case .failed(let error): self.localEventsContinuation.yield(.browserStopped(error.wifiAware))
            case .cancelled: self.localEventsContinuation.yield(.browserStopped(nil))
            default: break
            }
        }

        // Connect to the first discovered endpoint.
        let endpoint = try await browser.run { waEndpoints in
            Self.logger.info("📰 Discovered: \(waEndpoints, privacy: .public)")
            if let firstEndpoint = waEndpoints.first {
                return .finish(firstEndpoint)
            } else {
                return .continue
            }
        }

        Self.logger.info("📰 Attempting connection to: \(endpoint, privacy: .public)")
        localEventsContinuation.yield(.connecting)
        await connectionManager.setupConnection(to: endpoint)
    }

}


// MARK: - Sending Wi-Fi Aware messages

@available(iOS 26.0, *)
extension WifiAwareTransferTransportDelegate {
    
    // MARK: - Send

    /// Forwards a `NetworkEvent` to a specific connection via `ConnectionManager`.
    ///
    /// Used when the destination needs to send `startStreaming` to the source
    /// to signal that it is ready to receive history transfer data.
    private func send(_ event: NetworkEvent) async throws {
        guard let deviceConnection = self.deviceConnection else {
            throw ObvError.noConnectionToPairedDevice
        }
        guard deviceConnection.pairedDevice.id == self.pairedDevice.id else {
            assertionFailure()
            throw ObvError.connectedToWrongDevice
        }
        try await connectionManager.send(event, to: deviceConnection.connectionDetail.connection)
    }

}


// MARK: - Local Events handler

@available(iOS 26.0, *)
extension WifiAwareTransferTransportDelegate {
    
    /// The central dispatcher for all local (non-network) events.
    ///
    /// Receives events from two sources: `WifiAwareTransferTransportDelegate` itself
    /// (browser/listener lifecycle) and `ConnectionManager` (connection events).
    /// Updates `networkState`.
    private func handleLocalEvent(_ event: LocalEvent?) async {
        guard let event else { return }

        switch event {
        case .listenerRunning, .browserRunning:
            switch role {
            case .source:
                self.setWifiAwareNetworkState(to: .source(.publishing))
            case .destination:
                self.setWifiAwareNetworkState(to: .destination(.browsing))
            }

        case .connecting:
            assert(self.role == .destination)
            self.setWifiAwareNetworkState(to: .destination(.connecting))

        case .browserStopped(_), .listenerStopped(_):
            switch role {
            case .source:
                self.setWifiAwareNetworkState(to: .source(.stopped))
            case .destination:
                self.setWifiAwareNetworkState(to: .destination(.stopped))
            }

        case .connection(let conectionEvent):
            await handleConnectionEvent(conectionEvent)

        }
    }

    
    /// Helper of the `func handleLocalEvent(_ event: LocalEvent?) async` method. Handles the lifecycle events of an individual peer connection.
    ///
    /// - `.ready`: A connection is fully established. On the destination side this cancels
    ///   the browse task (no longer needed) and sends `startStreaming` to tell the source
    ///   that the destination is ready to receive history transfer data.
    /// - `.performance`: Updated metrics arrived; the `deviceConnections` dictionary is updated.
    /// - `.stopped`: The connection was torn down (by the user or due to an error).
    ///   Cleans up state and calls `invalidate` to release the state-update task.
    private func handleConnectionEvent(_ event: LocalEvent.ConnectionEvent) async {
        switch event {
        case .ready(let device, let connectionDetail):
            guard device.id == self.pairedDevice.id else {
                assertionFailure()
                Self.logger.fault("📰 Connected to wrong device. Not handling the event.")
                return
            }
            self.deviceConnection = (device, connectionDetail)
            switch wifiAwareTransferRole {
            case .source(transferId: let transferId, scope: _):
                do {
                    try await self.send(.transferId(transferId: transferId))
                } catch {
                    Self.logger.fault("📰 Could not send transferId: \(error)")
                    assertionFailure()
                    return
                }
                self.setWifiAwareNetworkStateOnSourceToPublishingAndDestinationIsConnectedIfPossible()
            case .destination:
                networkTask?.cancel()
                networkTask = nil
                Self.logger.info("📰 Sending startStreaming to \(String(describing: device), privacy: .public)")
                do {
                    try await self.send(.startStreaming)
                } catch {
                    Self.logger.fault("📰 Could not send startStreaming: \(error)")
                    assertionFailure()
                    return
                }
                Self.logger.info("📰 Sent startStreaming to \(String(describing: device), privacy: .public)")
                self.setWifiAwareNetworkState(to: .destination(.connected))
            }

        case .performance(let device, let connectionDetail):
            guard device.id == self.pairedDevice.id else {
                assertionFailure()
                Self.logger.fault("📰 Connected to wrong device. Not handling the event.")
                return
            }
            self.deviceConnection = (device, connectionDetail)

        case .stopped(let device, let connectionID, _):
            guard self.deviceConnection?.pairedDevice.id == device.id else {
                assertionFailure()
                return
            }
            self.deviceConnection = nil
            await connectionManager.invalidate(connectionID)
            switch role {
            case .source:
                break
            case .destination:
                self.setWifiAwareNetworkState(to: .destination(.stopped))
            }
        }
    }

}


// MARK: - Network Events handler

@available(iOS 26.0, *)
extension WifiAwareTransferTransportDelegate {
    
    /// Handles messages received from the remote peer over Wi-Fi Aware.
    ///
    /// - `.startStreaming`: Received by the source from the destination. Transitions the
    ///   source state to `.publishingAndDestinationIsConnected`, signalling that the
    ///   transfer can now proceed.
    /// - Transfer messages (`.srcDiscussionList`, `.srcDiscussionRanges`, etc.): Dispatched
    ///   to the appropriate message dispatcher for the transfer steps to consume.
    /// - `.userWantsToCancelTransfer`: The remote peer cancelled; triggers local disconnect.
    private func handleNetworkEvent(_ event: NetworkEvent?) async {
        guard let event else { return }
        guard !isDisconnectRequested else {
            Self.logger.error("📰 Not sending any more messages, because disconnect was requested")
            return
        }

        Self.logger.debug("📰🗯️ Received network event: \(String(describing: event), privacy: .public)")
        
        switch event {
        case .startStreaming:
            assert(self.role == .source, "We expect the startStreaming message to be sent by the destination, to the source")
            Self.logger.info("📰 Received Start streaming")
            self.startStreamingMessageReceived = true
            self.setWifiAwareNetworkStateOnSourceToPublishingAndDestinationIsConnectedIfPossible()
        case .transferId(transferId: let transferId):
            assert(self.role == .destination, "We expect the transferId message to be sent by the source to the destination")
            assert(self.transferId == nil)
            self.transferId = transferId
        case .srcDiscussionList(let message):
            // Received by destination. This message contains the list of available discussions on the source.
            assert(self.role == .destination)
            Self.logger.debug("📰 Destination did receive SrcDiscussionList with \(message.discussions.count) discussions and \(message.sha256s.count) sha256s")
            await messageDispatchers.srcDiscussionListMessageDispatcher.dispatchMessageToTransferSteps(message: message)
        case .srcDiscussionRanges(let message):
            Self.logger.debug("📰 Did receive SrcDiscussionRanges for discussion \(message.discussionTitle), with \(message.rangesByThreadAndSender.count) ranges")
            await messageDispatchers.srcDiscussionRangesMessageDispatcher.dispatchSrcDiscussionRangesToDestinationTransferSteps(srcDiscussionRanges: message)
        case .srcMessages(let message):
            Self.logger.debug("📰 Did receive srcMessages")
            await messageDispatchers.srcMessagesDispatcher.dispatchSrcMessagesToDestinationTransferSteps(srcMessages: message)
        case .srcDiscussionDone(_):
            Self.logger.debug("📰 Did receive sourceDiscussionDone (for now we don't do anything with this message)")
        case .sourceSha256(serializedMessage: let serializedMessage):
            // Received by the destination. This is a chunk of an attachment.
            Self.logger.debug("📰 Did receive sourceSha256 (i.e., an attachment chunk)")
            await self.messageDispatchers.srcSha256Dispatcher.saveAttachmentChunkReceivedInSourceSha256Message(serializedMessage)
        case .srcTransferDone(_):
            Self.logger.debug("📰 Did receive sourceTransferDone (for now we don't do anything with this message)")
        case .dstExpectedSha256(let message):
            Self.logger.debug("📰 Did receive DstExpectedSha256")
            await messageDispatchers.dstExpectedSha256MessageDispatcher.dispatchMessageToTransferSteps(message: message)
        case .dstDiscussionExpectedRanges(let message):
            Self.logger.debug("📰 Did receive DstDiscussionExpectedRanges")
            await messageDispatchers.dstDiscussionExpectedRangesMessageDispatcher.dispatchDstDiscussionExpectedRangesToSourceTransferSteps(dstDiscussionExpectedRanges: message)
        case .dstRequestSha256(let message):
            Self.logger.debug("📰 Did receive dstRequestSha256")
            await messageDispatchers.dstRequestSha256sDispatcher.dispatchDstRequestSha256ToSourceTransferSteps(dstRequestSha256: message)
        case .dstDoNotRequestSha256(let message):
            // Received by the source, when the destination indicates it will not request a particular attachment
            await messageDispatchers.dstRequestSha256sDispatcher.dispatchDstDoNotRequestSha256ToSourceTransferSteps(dstDoNotRequestSha256: message)
        case .userWantsToCancelTransfer:
            let transferId = self.transferId
            Self.logger.debug("📰 Did receive userWantsToCancelTransfer. TransferId is \(String(describing: transferId))")
            self.exportWasCancelledByUser = true
            if let delegate, let transferId {
                #if !targetEnvironment(macCatalyst) // For some reason, #if canImport(WiFiAware) does not work for iPad here
                await delegate.handleInterruptionRequestSentByOtherDevice(self, transferId: transferId)
                #endif
            } else {
                await self.disconnect()
            }
        }
    }
    
}


// MARK: - Private helpers

@available(iOS 26.0, *)
extension WifiAwareTransferTransportDelegate {
    
    private func setNetworkStateToStopped() {
        switch role {
        case .source:
            self.setWifiAwareNetworkState(to: .source(.stopped))
        case .destination:
            self.setWifiAwareNetworkState(to: .destination(.stopped))
        }
    }
    
    private func setWifiAwareNetworkStateOnSourceToPublishingAndDestinationIsConnectedIfPossible() {
        guard self.startStreamingMessageReceived else { return }
        guard self.deviceConnection != nil else { return }
        self.setWifiAwareNetworkState(to: .source(.publishingAndDestinationIsConnected))
    }
    
    private func setWifiAwareNetworkState(to newState: WifiAwareState.NetworkState) {
        guard self.networkState != newState else { return }
        Self.logger.info("📰 \(newState, privacy: .public)")
        self.networkState = newState
        updateTransferTransportLayerStateOnChangeOfWifiAwareNetworkState()
    }
    
}


// MARK: - WifiAware network state to Transport layer state

@available(iOS 26.0, *)
extension WifiAwareTransferTransportDelegate {
    
    private func updateTransferTransportLayerStateOnChangeOfWifiAwareNetworkState() {
        switch self.networkState {
        case .source(let sourceState):
            switch sourceState {
            case .stopped:
                setTransferTransportLayerState(to: .closed(exportWasCancelledByUser: exportWasCancelledByUser))
            case .publishing:
                setTransferTransportLayerState(to: .connecting)
            case .publishingAndDestinationIsConnected:
                setTransferTransportLayerState(to: .ready)
            }
        case .destination(let destinationState):
            switch destinationState {
            case .stopped:
                if exportWasCancelledByUser || isDisconnectRequested {
                    setTransferTransportLayerState(to: .closed(exportWasCancelledByUser: exportWasCancelledByUser))
                }
            case .browsing:
                setTransferTransportLayerState(to: .initializing)
            case .connecting:
                setTransferTransportLayerState(to: .connecting)
            case .connected:
                setTransferTransportLayerState(to: .ready)
            }
        }
    }
    
    private func setTransferTransportLayerState(to newTransferTransportLayerState: TransferTransportLayerState) {
        guard self.transferTransportLayerState != newTransferTransportLayerState else { return }
        guard !self.transferTransportLayerState.isClosed else { return }
        transferTransportLayerState = newTransferTransportLayerState
        transferTransportLayerStateOnSetContinuation.insert(newTransferTransportLayerState, at: 0)
        yieldAllTransferTransportLayerStates()
    }

}


// MARK: - WifiAwareState

private struct WifiAwareState {
    
    /// The possible networking states for the source device.
    /// `.stopped` means the listener is not running; `.publishing` means
    /// the `NetworkListener` is active and accepting incoming connections;
    /// `.publishingAndDestinationIsConnected` means the destination has connected and
    /// signalled readiness via `startStreaming`.
    enum SourceState {
        case stopped
        case publishing
        case publishingAndDestinationIsConnected
    }

    /// The possible networking states for the destination device.
    /// Progresses from `.stopped` → `.browsing` (browser running) →
    /// `.connecting` (endpoint found, dialling) → `.connected` (link up).
    enum DestinationState {
        case stopped
        case browsing
        case connecting
        case connected
    }

    /// The combined networking state of the Wi-Fi Aware connection,
    /// driving the transfer transport layer state transitions.
    enum NetworkState: Equatable {
        case source(SourceState)
        case destination(DestinationState)
    }

}


extension WifiAwareState.NetworkState: CustomStringConvertible {
    
    var description: String {
        switch self {
        case .source(let sourceState):
            return "WifiAwareNetworkState<Source>(\(sourceState))"
        case .destination(let destinationState):
            return "WifiAwareNetworkState<Destination>(\(destinationState))"
        }
    }
    
}


extension WifiAwareState.SourceState: CustomStringConvertible {
    
    var description: String {
        switch self {
        case .stopped: return "stopped"
        case .publishing: return "publishing"
        case .publishingAndDestinationIsConnected: return "publishingAndDestinationIsConnected"
        }
    }
    
}

extension WifiAwareState.DestinationState: CustomStringConvertible {
    
    var description: String {
        switch self {
        case .stopped: return "stopped"
        case .browsing: return "browsing"
        case .connecting: return "connecting"
        case .connected: return "connected"
        }
    }
    
}

#endif // canImport(WiFiAware)
