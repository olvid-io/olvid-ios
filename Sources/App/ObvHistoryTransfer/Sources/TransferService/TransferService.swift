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
import ObvAppCoreConstants


public protocol TransferServiceDelegate: AnyObject, Sendable {

    func getWellKnownTurnCredentials(_ actor: TransferService, ownedCryptoId: ObvCryptoId) async throws -> ObvTypes.ObvWellKnownTurnCredentials?
    func sendSignalingMessage(_ actor: TransferService, signalingMessage: WebrtcHistoryTransferMessage, toOtherOwnedDevice otherOwnedDevice: ObvOwnedDeviceIdentifier) async throws

    func sendInterruptMessage(_ actor: TransferService, transferId: String, toOtherOwnedDevice otherOwnedDevice: ObvOwnedDeviceIdentifier) async throws // Specific to WebRTC
    
    func userWantsToAcceptHistoryTransfer(_ actor: TransferService, sourceDeviceIdentifier: ObvOwnedDeviceIdentifier, transferIdFromSource: String) async throws // Specific to WebRTC
    func userWantsToCancelHistoryTransfer(_ actor: TransferService, sourceDeviceIdentifier: ObvOwnedDeviceIdentifier, transferIdFromSource: String) async throws  // Specific to WebRTC
    
}



public actor TransferService {
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "TransferService")
    
    private var transferTransportDelegate: (any TransferTransportDelegate)?
    
    private weak var delegate: TransferServiceDelegate?
    private let dataSources: DataSources
    private weak var actionsOnDestination: (any DestinationTransferStepsActions)?
    private var transferTransportLayerStateChangesObservationTask: Task<Void, Never>?
    
    private let temporaryDirectory: URL
    
    public struct DataSources {
        let sourceTransferStepsDataSource: any SourceTransferStepsDataSource
        let destinationTransferStepsDataSource: any DestinationTransferStepsDataSource
        let zipTransferTransportDelegateDataSource: any ZipTransferTransportDelegateDataSource
        public init(sourceTransferStepsDataSource: any SourceTransferStepsDataSource,
                    destinationTransferStepsDataSource: any DestinationTransferStepsDataSource,
                    zipTransferTransportDelegateDataSource: any ZipTransferTransportDelegateDataSource
        ) {
            self.sourceTransferStepsDataSource = sourceTransferStepsDataSource
            self.destinationTransferStepsDataSource = destinationTransferStepsDataSource
            self.zipTransferTransportDelegateDataSource = zipTransferTransportDelegateDataSource
        }
    }
    
    public init(temporaryDirectory: URL, delegate: TransferServiceDelegate, dataSources: DataSources, actionsOnDestination: any DestinationTransferStepsActions) {
        self.temporaryDirectory = temporaryDirectory
        self.delegate = delegate
        self.dataSources = dataSources
        self.actionsOnDestination = actionsOnDestination
    }
    
    private(set) var scope: TransferScope?
    private(set) var transferTransportLayerState: TransferTransportLayerState = .initial
    
    /// Continuation used to report progress to the view on the source device
    private var continuationForExportProgressReporting: AsyncStream<TransferExportState>.Continuation?
    private var bufferOfTransferExportStatesForProgressReporting = [TransferExportState]()
    
    /// Continuation used to report progress to the view on the destination device
    private var continuationForImportProgressReporting: AsyncStream<TransferImportState>.Continuation?
    private var bufferOfTransferImportStatesForProgressReporting = [TransferImportState]()
    
    private var sourceTransferSteps: SourceTransferSteps?
    private var destinationTransferSteps: DestinationTransferSteps?
    
    
    private func resetAll() async {
        Self.logger.info("📰 Call to resetAll()")
        await self.transferTransportDelegate?.disconnect()
        self.transferTransportDelegate = nil
        self.continuationForExportProgressReporting?.finish()
        self.continuationForExportProgressReporting = nil
        self.bufferOfTransferExportStatesForProgressReporting.removeAll()
        self.continuationForImportProgressReporting?.finish()
        self.continuationForImportProgressReporting = nil
        self.bufferOfTransferImportStatesForProgressReporting.removeAll()
        await self.sourceTransferSteps?.resetAll()
        self.sourceTransferSteps = nil
        await self.destinationTransferSteps?.resetAll()
        self.destinationTransferSteps = nil
        self.transferTransportLayerState = .initial
        self.scope = nil
        self.transferTransportLayerStateChangesObservationTask?.cancel()
        self.transferTransportLayerStateChangesObservationTask = nil
    }
    
    private var transferIdOfTransfersCanceledByRemoteDevice = Set<String>()
    
    /// In practice, this is called by the `AppCoordinatorsHolder` upon receiving a `WebrtcHistoryTransferMessage` sent by the other owned device.
    public func handleReceivedWebrtcHistoryTransferMessage(_ receivedMessage: WebrtcHistoryTransferMessage, otherOwnedDeviceIdentifier: ObvOwnedDeviceIdentifier) async throws {
        
        guard let transferTransportDelegate else {
            // This is certainly an "old" sdp sent during a previous transfer
            return
        }

        guard let webRTCTransferTransportDelegate = transferTransportDelegate as? WebRTCTransferTransportDelegate else {
            assertionFailure()
            throw ObvError.unableToRunTwoHistoryTransfersInParallel
        }

        switch receivedMessage {
            
        case .sdp(transferId: let transferId, sdp: let sdp):
            
            try await webRTCTransferTransportDelegate.handleReceivedSdp(transferId: transferId, receivedSdp: sdp)
            
        case .iceCandidates(transferId: let transferId, iceCandidates: let iceCandidates):
            
            try await webRTCTransferTransportDelegate.handleReceivedIceCandidates(transferId: transferId, receivedIceCandidates: iceCandidates)
            
        }
        
    }
    

    /// This is called when the transfer method is WebRTC, and we are receiving an interruption request from the other device.
    public func handleInterruptionRequestSentByOtherDeviceWithWebRTC(transferId: String) async throws {
        await self.handleInterruptionRequestSentByOtherDevice(transferId: transferId)
    }
    
    
}


// MARK: - Implementing TransferServiceForWifiAwareImportView

//extension TransferService: TransferServiceForWifiAwareImportView {
//    
//    public func initiateHistoryTransfer(
//        _ view: WifiAwareImportView,
//        ownedCryptoId: ObvCryptoId,
//        pairedDevice: ObvWAPairedDevice
//    ) async throws {
//
//        guard #available(iOS 26.0, *) else {
//            assertionFailure()
//            return
//        }
//        
//        guard transferTransportDelegate == nil else {
//            assertionFailure()
//            throw ObvError.unableToRunTwoHistoryTransfersInParallel
//        }
//
//        self.transferTransportLayerState = .initializing
//
//        transferTransportDelegate = WifiAwareTransferTransportDelegate(
//            role: .destination,
//            ownedCryptoId: ownedCryptoId,
//            pairedDevice: pairedDevice
//        )
//
//        guard let transferTransportDelegate else { assertionFailure(); throw ObvError.transferTransportDelegateIsNil }
//        observeTransferTransportLayerStateChanges(transferTransportDelegate: transferTransportDelegate)
//        
//        Task { await setTransferTransportLayerState(to: .connecting) }
//
//    }
//    
//}

// MARK: - Implementing TransferServiceForWifiAwareExportView

//extension TransferService: TransferServiceForWifiAwareExportView {
//    
//    public func initiateHistoryTransfer(
//        _ view: WifiAwareExportView,
//        transferTransportType: TransferTransportType,
//        scope: TransferScope
//    ) async throws {
//        try await self.initiateHistoryTransferOnSource(transferTransportType: transferTransportType, scope: scope)
//    }
//    
//}


// MARK: - Implementing TransferServiceForLocalNetworkExportView

extension TransferService: TransferServiceForLocalNetworkExportView {
    
    /// Called by the `LocalNetworkExportView` (shown on the source device) when it is time to actually start the transfer.
    ///
    /// This method is called **after** the source device receives the confirmation from the destination device that the user
    /// accepted the transfer.
    public func initiateHistoryTransfer(
        _ view: LocalNetworkExportView,
        transferTransportType: TransferTransportType,
        scope: TransferScope
    ) async throws {
        try await self.initiateHistoryTransferOnSource(transferTransportType: transferTransportType, scope: scope)
    }
    
    
    /// Called when the user explictely cancels the transfer on the source device.
    public func userWantsToCancelExport(_ view: LocalNetworkExportView, transferId: String, localNetworkType: LocalNetworkExportView.LocalNetworkType) async {
        
        self.reportNewProgressToView(exportState: .canceling)
        
        // Send interrupt message to destination device
        
        switch localNetworkType {
        case .webRTC(otherOwnedDeviceIdentifier: let otherOwnedDeviceIdentifier, nameOfRemoteDevice: _):
            do {
                try await delegate?.sendInterruptMessage(self, transferId: transferId, toOtherOwnedDevice: otherOwnedDeviceIdentifier)
            } catch {
                assertionFailure()
                Self.logger.fault("📰 Could not send interrupt message: \(error)")
            }
        case .wifiAware:
            #if !targetEnvironment(macCatalyst) // For some reason, #if canImport(WiFiAware) does not work for iPad here
            if #available(iOS 26.0, *), let wifiAwareTransferTransportDelegate = transferTransportDelegate as? WifiAwareTransferTransportDelegate {
                do {
                    try await wifiAwareTransferTransportDelegate.sendInterruptMessage()
                } catch {
                    assertionFailure()
                    Self.logger.fault("📰 Could not send interrupt message: \(error)")
                }
            }
            #else
            assertionFailure()
            #endif
        }
        
        await self.sourceTransferSteps?.userWantsToCancelExport(requestedFromOtherDevice: false)
        
        await self.transferTransportDelegate?.userWantsToCancelTransfer(cancelSource: .currentDevice)
        
        await self.resetAll()
        
    }
    
    
    public func onDisappear(of view: LocalNetworkExportView) async {
        await self.resetAll()
    }
    
    public func viewRequiresAsyncStreamOfTransferExportState(_ view: LocalNetworkExportView) async -> AsyncStream<TransferExportState> {
        return self.viewRequiresAsyncStreamOfTransferExportState()
    }
    
}


// MARK: - Implementing TransferServiceForLocalNetworkImportView

extension TransferService: TransferServiceForLocalNetworkImportView {
    
    public func viewRequiresAsyncStreamOfTransferImportState(_ view: LocalNetworkImportView) async -> AsyncStream<TransferImportState> {
        return self.viewRequiresAsyncStreamOfTransferImportState()
    }
    
    
    public func userWantsToCancelImport(_ view: LocalNetworkImportView, localNetworkType: LocalNetworkImportView.LocalNetworkType) async {

        self.reportNewProgressToView(exportState: .canceling)
        
        // Send interrupt message to source device
        
        switch localNetworkType {
        case .webRTC(sourceDeviceIdentifier: let otherOwnedDeviceIdentifier, sourceDeviceName: _, transferIdFromSource: let transferId):
            do {
                try await delegate?.sendInterruptMessage(self, transferId: transferId, toOtherOwnedDevice: otherOwnedDeviceIdentifier)
            } catch {
                assertionFailure()
                Self.logger.fault("📰 Could not send interrupt message: \(error)")
            }
        case .wifiAware:
            #if !targetEnvironment(macCatalyst) // For some reason, #if canImport(WiFiAware) does not work for iPad here
            if #available(iOS 26.0, *), let wifiAwareTransferTransportDelegate = transferTransportDelegate as? WifiAwareTransferTransportDelegate {
                do {
                    try await wifiAwareTransferTransportDelegate.sendInterruptMessage()
                } catch {
                    assertionFailure()
                    Self.logger.fault("📰 Could not send interrupt message: \(error)")
                }
            }
            #else
            assertionFailure()
            #endif
        }

        await self.destinationTransferSteps?.userWantsToCancelExport(requestedFromOtherDevice: false)
        
        await transferTransportDelegate?.userWantsToCancelTransfer(cancelSource: .currentDevice)
        
        await self.resetAll()
        
    }

    
    public func onDisappear(of view: LocalNetworkImportView) async {
        await self.resetAll()
    }
    
    
    /// Called when the user accepts, on the destination, the request to accept the history transfer sent by the source.
    ///
    /// We immediately create the `WebRTCTransferTransportDelegate` and then send the acceptation message to the source.
    public func userWantsToAcceptHistoryTransfer(
        _ view: LocalNetworkImportView,
        localNetorkType: LocalNetworkImportView.LocalNetworkType
    ) async throws {
        
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        
        assert(self.transferTransportDelegate == nil)
        
        switch localNetorkType {

        case .webRTC(let sourceDeviceIdentifier, _, let transferIdFromSource):
            
            self.transferTransportDelegate = WebRTCTransferTransportDelegate(
                role: .destination,
                otherOwnedDeviceIdentifier: sourceDeviceIdentifier,
                transferId: transferIdFromSource,
                delegate: self)
            guard let transferTransportDelegate else { assertionFailure(); return }
            observeTransferTransportLayerStateChanges(transferTransportDelegate: transferTransportDelegate)

            Task { await setTransferTransportLayerState(to: .connecting) }

            try await delegate.userWantsToAcceptHistoryTransfer(self, sourceDeviceIdentifier: sourceDeviceIdentifier, transferIdFromSource: transferIdFromSource)

        case .wifiAware(let ownedCryptoId, let pairedDevice):
            
            #if !targetEnvironment(macCatalyst) // For some reason, #if canImport(WiFiAware) does not work for iPad here

            guard #available(iOS 26.0, *) else {
                assertionFailure()
                return
            }
            
            self.transferTransportDelegate = WifiAwareTransferTransportDelegate(
                role: .destination,
                ownedCryptoId: ownedCryptoId,
                pairedDevice: pairedDevice,
                delegate: self)
            
            guard let transferTransportDelegate else { assertionFailure(); return }
            observeTransferTransportLayerStateChanges(transferTransportDelegate: transferTransportDelegate)

            Task { await setTransferTransportLayerState(to: .connecting) }
            
            #else
            
            assertionFailure()
            
            #endif // canImport(WifiAware)

        }
                
    }
    
    
    public func userWantsToCancelHistoryTransfer(
        _ view: LocalNetworkImportView,
        localNetorkType: LocalNetworkImportView.LocalNetworkType
    ) async throws {
        
        switch localNetorkType {
            
        case .webRTC(sourceDeviceIdentifier: let sourceDeviceIdentifier, sourceDeviceName: _, transferIdFromSource: let transferIdFromSource):
            
            guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
            try await delegate.userWantsToCancelHistoryTransfer(self, sourceDeviceIdentifier: sourceDeviceIdentifier, transferIdFromSource: transferIdFromSource)
            
        case .wifiAware(ownedCryptoId: _, pairedDevice: _):
            
            assertionFailure("Not expected to be called. This method is only called when the destination device rejects the initial webRTC transfer request")

        }
        
    }
    
}


// MARK: - Implementing WifiAwareTransferTransportDelegateDelegate

#if !targetEnvironment(macCatalyst) // For some reason, #if canImport(WiFiAware) does not work for iPad here
extension TransferService: WifiAwareTransferTransportDelegateDelegate {
    
    @available(iOS 26.0, *)
    func handleInterruptionRequestSentByOtherDevice(_ wifiAwareTransferTransportDelegate: WifiAwareTransferTransportDelegate, transferId: String) async {
        await self.handleInterruptionRequestSentByOtherDevice(transferId: transferId)
    }
    
}
#endif // canImport(WifiAware)


// MARK: - Implementing WebRTCTransferTransportDelegateDelegate

extension TransferService: WebRTCTransferTransportDelegateDelegate {
    
    public func getWellKnownTurnCredentials(_ actor: WebRTCTransferTransportDelegate, ownedCryptoId: ObvCryptoId) async throws -> ObvWellKnownTurnCredentials? {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.getWellKnownTurnCredentials(self, ownedCryptoId: ownedCryptoId)
    }
    
    
    public func sendSignalingMessage(_ actor: WebRTCTransferTransportDelegate, signalingMessage: WebrtcHistoryTransferMessage, toOtherOwnedDevice otherOwnedDevice: ObvOwnedDeviceIdentifier) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await delegate.sendSignalingMessage(self, signalingMessage: signalingMessage, toOtherOwnedDevice: otherOwnedDevice)
    }
    
}


// MARK: - Implementing TransferServiceForZipExportView

extension TransferService: TransferServiceForZipExportView {
    
    public func initiateHistoryTransfer(
        _ view: ZipExportView,
        transferTransportType: TransferTransportType,
        scope: TransferScope
    ) async throws {
        try await self.initiateHistoryTransferOnSource(transferTransportType: transferTransportType, scope: scope)
    }
    
    public func viewRequiresAsyncStreamOfTransferExportState(_ view: ZipExportView) async -> AsyncStream<TransferExportState> {
        return self.viewRequiresAsyncStreamOfTransferExportState()
    }
    
    public func onDisappear(of view: ZipExportView) async {
        _ = await self.sourceTransferSteps?.userWantsToCancelExport(requestedFromOtherDevice: false)
        await (transferTransportDelegate as? ZipTransferTransportDelegate)?.deleteTemporaryFilesAndZipFile()
        await self.resetAll()
    }
    
}


// MARK: - Implementing TransferServiceForZipImportView

extension TransferService: TransferServiceForZipImportView {
    
    /// Called on the destination device right after the user chooses the zip file.
    public func initiateHistoryTransfer(
        _ view: ZipImportView,
        ownedCryptoId: ObvCryptoId,
        zipFileURL: URL,
        password: String?
    ) async throws {
        
        guard transferTransportDelegate == nil else {
            assertionFailure()
            throw ObvError.unableToRunTwoHistoryTransfersInParallel
        }

        self.transferTransportLayerState = .initializing

        transferTransportDelegate = ZipTransferTransportDelegate(
            ownedCryptoId: ownedCryptoId,
            password: password,
            role: .destination(zipFileURL: zipFileURL),
            temporaryDirectory: temporaryDirectory
        )

        guard let transferTransportDelegate else { assertionFailure(); throw ObvError.transferTransportDelegateIsNil }
        observeTransferTransportLayerStateChanges(transferTransportDelegate: transferTransportDelegate)
        
        Task { await setTransferTransportLayerState(to: .connecting) }
        
    }
    
    
    public func viewRequiresAsyncStreamOfTransferImportState(_ view: ZipImportView) async throws -> AsyncStream<TransferImportState> {
        return self.viewRequiresAsyncStreamOfTransferImportState()
    }
    
    
    public func onDisappear(of view: ZipImportView) async {
        _ = await self.destinationTransferSteps?.userWantsToCancelExport(requestedFromOtherDevice: false)
        await (transferTransportDelegate as? ZipTransferTransportDelegate)?.deleteTemporaryFilesAndZipFile()
        await self.resetAll()
    }
    
}


// MARK: - Observing/publishing the transport layer state

extension TransferService {
    
    private func observeTransferTransportLayerStateChanges(transferTransportDelegate: any TransferTransportDelegate) {
        assert(transferTransportLayerStateChangesObservationTask == nil)
        transferTransportLayerStateChangesObservationTask?.cancel()
        transferTransportLayerStateChangesObservationTask = Task {
            let stream = await transferTransportDelegate.getAsyncStreamOfTransferTransportLayerState()
            for await newTransferTransportLayerState in stream {
                await setTransferTransportLayerState(to: newTransferTransportLayerState)
            }
        }
    }
    
    
    private func setTransferTransportLayerState(to newTransferTransportLayerState: TransferTransportLayerState) async {

        guard self.transferTransportLayerState != newTransferTransportLayerState else { return }

        Self.logger.info("📰 New Transport layer state: \(newTransferTransportLayerState)")

        self.transferTransportLayerState = newTransferTransportLayerState

        switch newTransferTransportLayerState {
        case .initial:
            assertionFailure()
            return
        case .initializing:
            guard let transferTransportDelegate else { assertionFailure(); return }
            switch await transferTransportDelegate.role {
            case .source:
                self.reportNewProgressToView(exportState: .initializing(.inProgress))
            case .destination:
                self.reportNewProgressToView(importState: .initializing(.inProgress))
            }
        case .connecting:
            guard let transferTransportDelegate else { assertionFailure(); return }
            switch await transferTransportDelegate.role {
            case .source:
                self.reportNewProgressToView(exportState: .initializing(.connectingToDestinationDevice))
            case .destination:
                self.reportNewProgressToView(importState: .initializing(.connectingToSourceDeviceOrUnzippingFile(progress: 0.0)))
            }
            do {
                try await transferTransportDelegate.connect(progressUpdater: self)
            } catch {
                assertionFailure()
            }
        case .ready:
            Self.logger.info("📰✅ Transport layer is ready")
            guard let transferTransportDelegate else { assertionFailure(); return }
            switch await transferTransportDelegate.role {
            case .source:
                self.reportNewProgressToView(exportState: .initializing(.connectedToDestinationDevice))
                guard let scope else { assertionFailure(); return }
                let src = await SourceTransferSteps(
                    ownedCryptoId: transferTransportDelegate.ownedCryptoId,
                    scope: scope,
                    dataSource: self.dataSources.sourceTransferStepsDataSource,
                    transferTransportDelegate: transferTransportDelegate)
                self.sourceTransferSteps = src
                do {
                    let stream = try await src.execute()
                    continouslyUpdateProgressOnUpdatesStreamedBySourceTransferSteps(stream: stream)
                } catch {
                    assertionFailure()
                }
            case .destination:
                self.reportNewProgressToView(importState: .initializing(.connectedToSourceDeviceOrFileUnzipped))
                guard let actionsOnDestination else { assertionFailure(); return }
                let dst = await DestinationTransferSteps(
                    ownedCryptoId: transferTransportDelegate.ownedCryptoId,
                    dataSource: self.dataSources.destinationTransferStepsDataSource,
                    transferTransportDelegate: transferTransportDelegate,
                    actions: actionsOnDestination)
                self.destinationTransferSteps = dst
                do {
                    let stream = try await dst.execute()
                    continouslyUpdateProgressOnUpdatesStreamedByDestinationTransferSteps(stream: stream)
                } catch {
                    assertionFailure()
                }
            }
        case .closed(exportWasCancelledByUser: let exportWasCancelledByUser):
            if exportWasCancelledByUser {
                guard let transferTransportDelegate else { assertionFailure(); return }
                switch await transferTransportDelegate.role {
                case .source:
                    self.reportNewProgressToView(exportState: .sourceTransferStepsState(.done(status: .exportWasCancelledByUser)))
                case .destination:
                    self.reportNewProgressToView(importState: .destinationTransferStepsState(.done(status: .exportWasCancelledByUser)))
                }
            }
        }
                
    }
    
    
    private func continouslyUpdateProgressOnUpdatesStreamedBySourceTransferSteps(stream: AsyncStream<SourceTransferStepsState>) {
        Task {
            for await stateFromSourceTransferSteps in stream {
                reportNewProgressToView(exportState: .sourceTransferStepsState(stateFromSourceTransferSteps))
            }
        }
    }

    
    private func continouslyUpdateProgressOnUpdatesStreamedByDestinationTransferSteps(stream: AsyncStream<DestinationTransferStepsState>) {
        Task {
            for await stateFromDestinationTransferSteps in stream {
                reportNewProgressToView(importState: .destinationTransferStepsState(stateFromDestinationTransferSteps))
            }
        }
    }

}


// MARK: - Implementing ConnectProgressUpdater

extension TransferService: ConnectProgressUpdater {
    
    func updateConnectProgress(entryNumber: Int, total: Int) async {
        guard total > 0 else { return }
        let progress = min(1.0, Double(entryNumber) / Double(total))
        self.reportNewProgressToView(importState: .initializing(.connectingToSourceDeviceOrUnzippingFile(progress: progress)))
    }
    
}


// MARK: - Reporting progress on the source device

extension TransferService {
    
    /// Called by the view when it is ready to display a progress report
    private func viewRequiresAsyncStreamOfTransferExportState() -> AsyncStream<TransferExportState> {
        let stream = AsyncStream<TransferExportState> { (continuation: AsyncStream<TransferExportState>.Continuation) in
            self.continuationForExportProgressReporting?.finish()
            self.continuationForExportProgressReporting = continuation
            yieldAllBufferedTransferExportStatesIfPossible()
        }
        return stream
    }
    
    
    private func yieldAllBufferedTransferExportStatesIfPossible() {
        guard let continuationForExportProgressReporting else { return }
        while let state = bufferOfTransferExportStatesForProgressReporting.popLast() {
            continuationForExportProgressReporting.yield(state)
            finishExportProgressReportingIfDone(lastYieldedState: state)
        }
    }
    
    private func finishExportProgressReportingIfDone(lastYieldedState: TransferExportState) {
        assert(self.continuationForExportProgressReporting != nil)
        switch lastYieldedState {
        case .sourceTransferStepsState(let state):
            switch state {
            case .done:
                self.continuationForExportProgressReporting?.finish()
                self.continuationForExportProgressReporting = nil
            default:
                return
            }
        default:
            return
        }
    }

    private func reportNewProgressToView(exportState: TransferExportState) {
        self.bufferOfTransferExportStatesForProgressReporting.insert(exportState, at: 0)
        yieldAllBufferedTransferExportStatesIfPossible()
    }

}


// MARK: - Reporting progress on the destination device

extension TransferService {
    
    /// Called by the view when it is ready to display a progress report
    private func viewRequiresAsyncStreamOfTransferImportState() -> AsyncStream<TransferImportState> {
        let stream = AsyncStream<TransferImportState> { (continuation: AsyncStream<TransferImportState>.Continuation) in
            self.continuationForImportProgressReporting?.finish()
            self.continuationForImportProgressReporting = continuation
            yieldAllBufferedTransferImportStatesIfPossible()
        }
        return stream
    }
    
    
    private func yieldAllBufferedTransferImportStatesIfPossible() {
        guard let continuationForImportProgressReporting else { return }
        while let state = bufferOfTransferImportStatesForProgressReporting.popLast() {
            continuationForImportProgressReporting.yield(state)
            finishImportProgressReportingIfDone(lastYieldedState: state)
        }
    }

    private func finishImportProgressReportingIfDone(lastYieldedState: TransferImportState) {
        assert(self.continuationForImportProgressReporting != nil)
        switch lastYieldedState {
        case .destinationTransferStepsState(let state):
            switch state {
            case .done:
                self.continuationForImportProgressReporting?.finish()
                self.continuationForImportProgressReporting = nil
            default:
                return
            }
        default:
            return
        }
    }

    private func reportNewProgressToView(importState: TransferImportState) {
        self.bufferOfTransferImportStatesForProgressReporting.insert(importState, at: 0)
        yieldAllBufferedTransferImportStatesIfPossible()
    }

}


extension TransferService {
    
    enum ObvError: Error {
        case unableToRunTwoHistoryTransfersInParallel
        case delegateIsNil
        case transferTransportDelegateIsNil
        case transferWasCanceledByRemoteDevice
        case unexpectedTransferTransportType
    }
    
}


// MARK: - Private methods

extension TransferService {
    
    /// Used both for WebRTC and Wi-Fi aware methods
    private func handleInterruptionRequestSentByOtherDevice(transferId: String) async {
        
        self.transferIdOfTransfersCanceledByRemoteDevice.insert(transferId)
        
        guard destinationTransferSteps != nil || sourceTransferSteps != nil else {
            // We probaly are receiving an old interruption request (or a request made very quickly)
            await transferTransportDelegate?.userWantsToCancelTransfer(cancelSource: .otherDevice(transferId: transferId))
            return
        }
        assert((destinationTransferSteps == nil) != (sourceTransferSteps == nil)) // Exactly one must be non-nil
        
        guard let transferIdFromDelegate = await transferTransportDelegate?.transferId else {
            return
        }
        
        guard transferIdFromDelegate == transferId else {
            return
        }
        
        self.reportNewProgressToView(exportState: .canceling)
        
        await self.destinationTransferSteps?.userWantsToCancelExport(requestedFromOtherDevice: true)
        await self.sourceTransferSteps?.userWantsToCancelExport(requestedFromOtherDevice: true)
        
        await transferTransportDelegate?.userWantsToCancelTransfer(cancelSource: .otherDevice(transferId: transferId))

        await self.resetAll()
        
    }

    
    public func initiateHistoryTransferOnSource(
        transferTransportType: TransferTransportType,
        scope: TransferScope
    ) async throws {
        
        guard transferTransportDelegate == nil else {
            assertionFailure()
            throw ObvError.unableToRunTwoHistoryTransfersInParallel
        }
        self.scope = scope
        self.transferTransportLayerState = .initializing

        switch transferTransportType {
            
        case .webRtcWithOwnedDevice(transferId: let transferId, otherOwnedDeviceIdentifier: let otherOwnedDeviceIdentifier):
            
            guard !self.transferIdOfTransfersCanceledByRemoteDevice.contains(transferId) else {
                assertionFailure()
                throw ObvError.transferWasCanceledByRemoteDevice
            }
            
            transferTransportDelegate = WebRTCTransferTransportDelegate(
                role: .source,
                otherOwnedDeviceIdentifier: otherOwnedDeviceIdentifier,
                transferId: transferId,
                delegate: self)
        
        case .zipFile(ownedCryptoId: let ownedCryptoId, password: let password):
            
            transferTransportDelegate = ZipTransferTransportDelegate(
                ownedCryptoId: ownedCryptoId,
                password: password,
                role: .source(dataSource: self.dataSources.zipTransferTransportDelegateDataSource),
                temporaryDirectory: temporaryDirectory
            )
            
        case .wifiAware(transferId: let transferId, ownedCryptoId: let ownedCryptoId, pairedDevice: let pairedDevice):
            
            #if !targetEnvironment(macCatalyst) // For some reason, #if canImport(WiFiAware) does not work for iPad here
            
            if #available(iOS 26.0, *) {
                transferTransportDelegate = WifiAwareTransferTransportDelegate(
                    role: .source(transferId: transferId, scope: scope),
                    ownedCryptoId: ownedCryptoId,
                    pairedDevice: pairedDevice,
                    delegate: self)
            } else {
                assertionFailure()
            }
            
            #else
            
            assertionFailure()
            
            #endif // canImport(WifiAware)

        }
        
        guard let transferTransportDelegate else { assertionFailure(); throw ObvError.transferTransportDelegateIsNil }
        observeTransferTransportLayerStateChanges(transferTransportDelegate: transferTransportDelegate)
        
        Task { await setTransferTransportLayerState(to: .connecting) }
        
    }
    
}
