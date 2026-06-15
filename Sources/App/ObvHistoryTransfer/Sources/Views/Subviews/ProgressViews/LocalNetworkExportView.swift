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

import SwiftUI
import ObvDesignSystem
import ObvTypes
import ObvSystemIcon
import ObvContinuedProcessingTaskManager
import ConfettiSwiftUI


public enum DestinationOwnedDeviceDecision {
    case startTransfer
    case cancelTransfer
}

@MainActor
public protocol LocalNetworkExportViewActions {
    
    func historySourceDeviceWantsToSendTransferConfirmationRequestToDestinationOwnedDevice(
        _ view: LocalNetworkExportView,
        transferId: String,
        otherOwnedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier
    ) async throws -> DestinationOwnedDeviceDecision
    
    func userRequiresMessageHistoryTransferService(_ view: LocalNetworkExportView) async throws -> any TransferServiceForLocalNetworkExportView
    
    func userWantsToDismissView(_ view: LocalNetworkExportView)

}


@MainActor
public protocol LocalNetworkExportViewInternalActions {
    func userWantsToPopView(_ view: LocalNetworkExportView)
}

public protocol TransferServiceForLocalNetworkExportView: Sendable {
    func initiateHistoryTransfer(
        _ view: LocalNetworkExportView,
        transferTransportType: TransferTransportType,
        scope: TransferScope
    ) async throws
    
    func viewRequiresAsyncStreamOfTransferExportState(_ view: LocalNetworkExportView) async -> AsyncStream<TransferExportState>

    func userWantsToCancelExport(_ view: LocalNetworkExportView, transferId: String, localNetworkType: LocalNetworkExportView.LocalNetworkType) async
    func onDisappear(of view: LocalNetworkExportView) async
    
}


/// View shown on the source device, during a transfer, to show the export progress.
public struct LocalNetworkExportView: View {

    let localNetworkType: LocalNetworkType
    let scope: TransferScope
    let internalActions: any LocalNetworkExportViewInternalActions
    let actions: any LocalNetworkExportViewActions
    let transferId: String
    
    init(localNetorkType: LocalNetworkType,
         scope: TransferScope,
         internalActions: any LocalNetworkExportViewInternalActions,
         actions: any LocalNetworkExportViewActions
    ) {
        self.localNetworkType = localNetorkType
        self.scope = scope
        self.internalActions = internalActions
        self.actions = actions
        switch localNetorkType {
        case .webRTC:
            internalState = .waitingForTransferConfirmationFromDestination
        case .wifiAware:
            internalState = .transferring
        }
        self.transferId = UUID().uuidString
    }

    public enum LocalNetworkType: Sendable {
        case webRTC(otherOwnedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier, nameOfRemoteDevice: String?)
        case wifiAware(ownedCryptoId: ObvCryptoId, pairedDevice: ObvWAPairedDevice)
    }

    private enum InternalState {
        case waitingForTransferConfirmationFromDestination
        case transferring
        case transferRequestRejectedByDestination
    }

    @State private var internalState: InternalState // Initial value depends on the local network type
    @State private var transferService: (any TransferServiceForLocalNetworkExportView)?

    @State private var globalState: ExportingProgressInternalView.GlobalState = .inProgress

    private var nameOfRemoteDevice: String? {
        switch localNetworkType {
        case .webRTC(otherOwnedDeviceIdentifier: _, nameOfRemoteDevice: let name):
            return name
        case .wifiAware(ownedCryptoId: _, pairedDevice: let pairedDevice):
            return pairedDevice.pairingInfo?.pairingName ?? pairedDevice.pairingInfo?.modelName
        }
    }
    
    private func onTask() async {
        switch localNetworkType {
        case .webRTC(let otherOwnedDeviceIdentifier, let nameOfRemoteDevice):
            await onTaskForWebRTC(otherOwnedDeviceIdentifier: otherOwnedDeviceIdentifier, nameOfRemoteDevice: nameOfRemoteDevice)
        case .wifiAware(let ownedCryptoId, let pairedDevice):
            await onTaskForWifiAware(ownedCryptoId: ownedCryptoId, pairedDevice: pairedDevice)
        }
    }
    
    private func onTaskForWifiAware(ownedCryptoId: ObvCryptoId, pairedDevice: ObvWAPairedDevice) async {
        do {
            let transferService = try await actions.userRequiresMessageHistoryTransferService(self)
            self.transferService = transferService
            try await transferService.initiateHistoryTransfer(
                self,
                transferTransportType: .wifiAware(transferId: transferId, ownedCryptoId: ownedCryptoId, pairedDevice: pairedDevice),
                scope: scope)
        } catch {
            assertionFailure()
        }
    }
    
    private func onTaskForWebRTC(otherOwnedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier, nameOfRemoteDevice: String?) async {
        do {
            let decision = try await actions.historySourceDeviceWantsToSendTransferConfirmationRequestToDestinationOwnedDevice(
                self,
                transferId: transferId,
                otherOwnedDeviceIdentifier: otherOwnedDeviceIdentifier
            )
            switch decision {
            case .startTransfer:
                let transferService = try await actions.userRequiresMessageHistoryTransferService(self)
                self.transferService = transferService
                try await transferService.initiateHistoryTransfer(
                    self,
                    transferTransportType: .webRtcWithOwnedDevice(transferId: transferId, otherOwnedDeviceIdentifier: otherOwnedDeviceIdentifier),
                    scope: scope
                )
                withAnimation { self.internalState = .transferring }
            case .cancelTransfer:
                withAnimation { self.internalState = .transferRequestRejectedByDestination }
            }
        } catch {
            assertionFailure()
        }
    }

    private func onDisappear() {
        guard let transferService = self.transferService else { return }
        Task {
            switch globalState {
            case .inProgress:
                await transferService.userWantsToCancelExport(self, transferId: transferId, localNetworkType: localNetworkType)
            case .canceling, .done, .failed:
                break
            }
            await transferService.onDisappear(of: self)
        }
    }

    public var body: some View {
        Group {
            switch internalState {
            case .waitingForTransferConfirmationFromDestination:
                WaitingForDestinationDeviceView(nameOfRemoteDevice: nameOfRemoteDevice)
            case .transferring:
                ExportingProgressInternalView(actions: self, scope: scope, localNetworkType: localNetworkType, globalState: $globalState)
            case .transferRequestRejectedByDestination:
                TransferRequestWasRejectedByDestinationView(internalActions: self)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .task(onTask)
        .onDisappear(perform: onDisappear)
    }

}


extension LocalNetworkExportView: TransferRequestWasRejectedByDestinationViewInternalActions {

    fileprivate func userWantsToPopView(_ view: TransferRequestWasRejectedByDestinationView) {
        self.internalActions.userWantsToPopView(self)
    }
    
}


extension LocalNetworkExportView {
    
    enum ObvError: Error {
        case transferServiceIsNil
    }
    
}


extension LocalNetworkExportView: ExportingProgressInternalViewActions {
    
    fileprivate func viewRequiresAsyncStreamOfTransferExportState(_ view: ExportingProgressInternalView) async throws -> AsyncStream<TransferExportState> {
        guard let transferService else { assertionFailure(); throw ObvError.transferServiceIsNil }
        return await transferService.viewRequiresAsyncStreamOfTransferExportState(self)
    }

    fileprivate func userWantsToCancelExport(_ view: ExportingProgressInternalView) async {
        guard let transferService else { assertionFailure(); return }
        await transferService.userWantsToCancelExport(self, transferId: transferId, localNetworkType: localNetworkType)
    }
    
    fileprivate func userWantsToDismissView(_ view: ExportingProgressInternalView) {
        actions.userWantsToDismissView(self)
    }
    
    fileprivate func userWantsToPopView(_ view: ExportingProgressInternalView) {
        internalActions.userWantsToPopView(self)
    }

}


// MARK: - TransferRequestWasRejectedByDestinationView

@MainActor
private protocol TransferRequestWasRejectedByDestinationViewInternalActions {
    func userWantsToPopView(_ view: TransferRequestWasRejectedByDestinationView)
}

private struct TransferRequestWasRejectedByDestinationView: View {
    
    let internalActions: any TransferRequestWasRejectedByDestinationViewInternalActions

    private let explanation = String(localizedInThisBundle: "TRANSFER_REQUEST_WAS_REJECTED_BY_DESTINATION_DEVICE_EXPLANATION")
    
    private func userWantsToPopView() {
        internalActions.userWantsToPopView(self)
    }

    var body: some View {
        Form {
            
            ExplanationsSectionView(explanation: nil)
            
            Section {
                HStack {
                    Spacer(minLength: 0)
                    Text(explanation)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .listRowSeparator(.hidden)
            }
            
        }
        .safeAreaInset(edge: .bottom) {
            VStack {
                OlvidButtonNew(action: userWantsToPopView, style: .glassOrBorderedProminent) {
                    Label {
                        Text("BACK")
                    } icon: {
                        Image(systemIcon: .arrowshapeTurnUpBackwardFill)
                    }
                }
            }
            .padding()
        }
    }

}

// MARK: - WaitingForDestinationDeviceView

/// View shown while this source device is waiting for the user to confirm the transfer on the destination device.
private struct WaitingForDestinationDeviceView: View {

    let nameOfRemoteDevice: String?
    
    private var title: String {
        if let nameOfRemoteDevice {
            return String(localizedInThisBundle: "WAITING_FOR_DESTINATION_DEVICE_\(nameOfRemoteDevice)")
        } else {
            return String(localizedInThisBundle: "WAITING_FOR_DESTINATION_DEVICE")
        }
    }

    private var explanation: String {
        if let nameOfRemoteDevice {
            return String(localizedInThisBundle: "WAITING_FOR_DESTINATION_DEVICE_\(nameOfRemoteDevice)_EXPLANATION")
        } else {
            return String(localizedInThisBundle: "WAITING_FOR_DESTINATION_DEVICE_EXPLANATION")
        }
    }
    
    var body: some View {
        VStack {

            Spacer(minLength: 0)

            ObvCardView {
                VStack(spacing: 16) {
                    
                    Image(systemIcon: .macbookAndIphone)
                        .font(.system(size: 72))
                        .foregroundStyle(.orange)

                    HistoryTransferSectionTitle(title: title)

                    Text(explanation)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    ProgressView()
                    
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)

            Spacer(minLength: 0)

        }
    }

}


// MARK: - ExportingProgressInternalView

@MainActor
private protocol ExportingProgressInternalViewActions {
    func viewRequiresAsyncStreamOfTransferExportState(_ view: ExportingProgressInternalView) async throws -> AsyncStream<TransferExportState>
    func userWantsToCancelExport(_ view: ExportingProgressInternalView) async
    func userWantsToDismissView(_ view: ExportingProgressInternalView)
    func userWantsToPopView(_ view: ExportingProgressInternalView)
}


/// View that encompasses the export progress timeline on the source device.
private struct ExportingProgressInternalView: View {

    let actions: any ExportingProgressInternalViewActions
    let scope: TransferScope
    let localNetworkType: LocalNetworkExportView.LocalNetworkType
    @Binding var globalState: GlobalState

    @State private var initializingStatus: InitializingStatusOnSourceDevice = .inProgress
    @State private var fetchingDiscussionsListStatus: FetchingDiscussionsListStatus?
    @State private var fetchingAllHashAndSizesOfFylesStatus: FetchingAllHashAndSizesOfFylesStatus?
    @State private var negotiatingWhatToSendStatus: NegotiatingWhatToSendStatus?
    @State private var sendingMessagesStatus: SendingMessagesStatus?
    @State private var sendingAttachmentsStatus: SendingAttachmentsStatus?
    @State private var sendingDoneStatus: SendingDoneStatus?
    
    fileprivate enum GlobalState {
        case inProgress
        case canceling
        case done // Final state
        case failed // Final state
    }
    
    @State private var isInterfaceDisabled: Bool = false
    
    @State private var triggerConfettiCanon = false

    private func onTask() async {
        ObvContinuedProcessingTaskManager.run(taskKind: .historyTransfer) { bgContinuedProcessingTask in
            
            bgContinuedProcessingTask?.expirationHandler = {
                Task { await self.actions.userWantsToCancelExport(self) }
            }

            let stream = try await self.actions.viewRequiresAsyncStreamOfTransferExportState(self)
            
            for await newState in stream {
                
                try withAnimation {
                    
                    switch newState {
                        
                    case .initializing(let status):
                        
                        self.globalState = .inProgress
                        self.initializingStatus = status
                        
                    case .sourceTransferStepsState(let sourceTransferStepsState):
                        
                        self.globalState = .inProgress
                        switch sourceTransferStepsState {
                        case .fetchingDiscussionsList(status: let status):
                            fetchingDiscussionsListStatus = status
                        case .fetchingAllHashAndSizesOfFyles(status: let status):
                            fetchingAllHashAndSizesOfFylesStatus = status
                        case .negotiatingWhatToSend(status: let status):
                            negotiatingWhatToSendStatus = status
                        case .sendingMessages(status: let status):
                            sendingMessagesStatus = status
                        case .sendingAttachments(status: let status):
                            sendingAttachmentsStatus = status
                            if let bgContinuedProcessingTask, let unitCount = status.unitCount {
                                bgContinuedProcessingTask.progress.totalUnitCount = unitCount.total
                                bgContinuedProcessingTask.progress.completedUnitCount = unitCount.completed
                            }
                        case .computingZipFile:
                            // Not used when using WebRTC for the transfer
                            break
                        case .done(status: let status):
                            sendingDoneStatus = status
                            globalState = .done
                            switch status {
                            case .exportWasSuccessful(failedFylesCount: let failedFylesCount):
                                guard failedFylesCount == 0 else {
                                    throw ObvError.certainFilesCouldNotBeTransferred
                                }
                                triggerConfettiCanon = true
                            case .exportWasCancelledByUser:
                                throw ObvError.exportWasCancelled
                            case .exportFailed:
                                throw ObvError.exportFailed
                            }
                        }
                        
                    case .canceling:
                        
                        globalState = .canceling
                        
                    case .failed:
                        
                        globalState = .failed
                        throw ObvError.exportFailed
                        
                    }
                                        
                } // end of withAnimation
                
            } // end of stream
            
            debugPrint("📰✅ ExportingProgressInternalView stream is finished")

        }
    }
    
    
    enum ObvError: Error {
        case certainFilesCouldNotBeTransferred
        case exportWasCancelled
        case exportFailed
    }
    

    private func userWantsToCancelExport() {
        self.isInterfaceDisabled = true
        Task {
            defer { self.isInterfaceDisabled = false }
            await actions.userWantsToCancelExport(self)
            // We force the view to show a cancelled state
            withAnimation {
                self.sendingDoneStatus = .exportWasCancelledByUser
                self.globalState = .done
            }
        }
    }
    
    @State private var isInterruptConfirmationDialogPresented = false
    private var interruptConfirmationDialogTitle: String { String(localizedInThisBundle: "INTERRUPT_EXPORT_CONFIRMATION_DIALOG_TITLE") }
        
    private var isInteractiveDismissDisabled: Bool {
        switch globalState {
        case .inProgress, .canceling:
            return true
        case .done, .failed:
            return false
        }
    }
    
    private func buttonTapped() {
        switch globalState {
        case .inProgress:
            isInterruptConfirmationDialogPresented = true
        case .canceling:
            return
        case .done, .failed:
            actions.userWantsToDismissView(self)
        }
    }
    
    private func backButtonTapped() {
        switch globalState {
        case .inProgress:
            isInterruptConfirmationDialogPresented = true
        case .canceling, .done, .failed:
            actions.userWantsToPopView(self)
        }
    }
    
    private var buttonTitle: String {
        switch globalState {
        case .inProgress:
            return String(localizedInThisBundle: "INTERRUPT_TRANSFER_AND_CONTINUE_LATER")
        case .canceling:
            return String(localizedInThisBundle: "BUTTON_TITLE_CANCELING")
        case .done, .failed:
            return String(localizedInThisBundle: "DISMISS")
        }
    }
    
    private enum ScrollAnchor: Hashable {
        case fetchingDiscussionsList
        case fetchingAllHashAndSizesOfFyles
        case negotiatingWhatToSend
        case sendingMessages
        case sendingAttachments
        case done
    }

    public var body: some View {
        ScrollView {
            ScrollViewReader { proxy in

                ObvCardView {
                    VStack(alignment: .leading, spacing: 0) {

                        InitializationStatusView(
                            initializingStatus: initializingStatus,
                            localNetworkType: localNetworkType,
                            showLine: fetchingDiscussionsListStatus != nil || sendingDoneStatus != nil
                        )

                        if let fetchingDiscussionsListStatus {
                            FetchingDiscussionsListStatusView(fetchingDiscussionsListStatus: fetchingDiscussionsListStatus, showLine: fetchingAllHashAndSizesOfFylesStatus != nil || negotiatingWhatToSendStatus != nil || sendingDoneStatus != nil)
                                .id(ScrollAnchor.fetchingDiscussionsList)
                                .onAppear { withAnimation { proxy.scrollTo(ScrollAnchor.fetchingDiscussionsList, anchor: .bottom) } }
                        }

                        if let fetchingAllHashAndSizesOfFylesStatus {
                            FetchingAllHashAndSizesOfFylesStatusView(
                                fetchingAllHashAndSizesOfFylesStatus: fetchingAllHashAndSizesOfFylesStatus,
                                showLine: negotiatingWhatToSendStatus != nil || sendingMessagesStatus != nil || sendingAttachmentsStatus != nil || sendingDoneStatus != nil)
                            .id(ScrollAnchor.fetchingAllHashAndSizesOfFyles)
                            .onAppear { withAnimation { proxy.scrollTo(ScrollAnchor.fetchingAllHashAndSizesOfFyles, anchor: .bottom) } }
                        }

                        if let negotiatingWhatToSendStatus {
                            NegotiatingWhatToSendStatusView(
                                negotiatingWhatToSendStatus: negotiatingWhatToSendStatus,
                                showLine: sendingMessagesStatus != nil || sendingAttachmentsStatus != nil || sendingDoneStatus != nil,
                                scope: scope)
                            .id(ScrollAnchor.negotiatingWhatToSend)
                            .onAppear { withAnimation { proxy.scrollTo(ScrollAnchor.negotiatingWhatToSend, anchor: .bottom) } }
                        }

                        if let sendingMessagesStatus {
                            SendingMessagesStatusView(
                                sendingMessagesStatus: sendingMessagesStatus,
                                showLine: sendingAttachmentsStatus != nil || sendingDoneStatus != nil)
                            .id(ScrollAnchor.sendingMessages)
                            .onAppear { withAnimation { proxy.scrollTo(ScrollAnchor.sendingMessages, anchor: .bottom) } }
                        }

                        if let sendingAttachmentsStatus {
                            SendingAttachmentsStatusView(
                                sendingAttachmentsStatus: sendingAttachmentsStatus,
                                showLine: sendingDoneStatus != nil)
                            .id(ScrollAnchor.sendingAttachments)
                            .onAppear { withAnimation { proxy.scrollTo(ScrollAnchor.sendingAttachments, anchor: .bottom) } }
                        }

                        if let sendingDoneStatus {
                            DoneView(sendingDoneStatus: sendingDoneStatus)
                                .id(ScrollAnchor.done)
                                .onAppear { withAnimation { proxy.scrollTo(ScrollAnchor.done, anchor: .bottom) } }
                        }

                    }
                }
                .padding()

            }
        } // ScrollView
        .navigationTitle(String(localizedInThisBundle: "EXPORT_STATUS_TITLE"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                // We replace the standard back button by a button that looks exactly the same
                // but allows to display the same confirmation request than the one we would have
                // when interrupting the transfer.
                Button(action: backButtonTapped) {
                    Image(systemIcon: .chevronLeft)
                        .fontWeight(.semibold)
                }
                .disabled(isInterfaceDisabled)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack {
                OlvidButtonNew(action: buttonTapped, style: .glassOrBorderedProminent) {
                    Text(buttonTitle)
                }
                .confirmationDialog(interruptConfirmationDialogTitle, isPresented: $isInterruptConfirmationDialogPresented, titleVisibility: .visible, actions: {
                    Button(String(localizedInThisBundle: "BUTTON_TITLE_CONTINUE_TRANSFER"), action: {})
                    Button(String(localizedInThisBundle: "BUTTON_TITLE_INTERRUPT_TRANSFER"), role: .destructive, action: userWantsToCancelExport)
                })
                .confettiCannon(trigger: $triggerConfettiCanon,
                                num: 100,
                                openingAngle: Angle(degrees: 0),
                                closingAngle: Angle(degrees: 360),
                                radius: 200)
            }
            .padding()
        }
        .interactiveDismissDisabled(isInteractiveDismissDisabled)
        .disabled(isInterfaceDisabled)
        .task(onTask)
    }

}


// MARK: - Views using ProgressItemRowView

private struct DoneView: View {
    
    let sendingDoneStatus: SendingDoneStatus
        
    private var title: String {
        switch sendingDoneStatus {
        case .exportWasSuccessful:
            return String(localizedInThisBundle: "DONE_EXPORT_VIEW_TITLE_EXPORT_WAS_SUCCESSFUL")
        case .exportWasCancelledByUser:
            return String(localizedInThisBundle: "DONE_EXPORT_VIEW_TITLE_EXPORT_CANCELLED_BY_USER")
        case .exportFailed:
            return String(localizedInThisBundle: "DONE_EXPORT_VIEW_TITLE_EXPORT_FAILED")
        }
    }
    
    private var subtitle: String {
        switch sendingDoneStatus {
        case .exportWasSuccessful:
            return String(localizedInThisBundle: "DONE_EXPORT_VIEW_SUBTITLE_EXPORT_WAS_SUCCESSFUL")
        case .exportWasCancelledByUser:
            return String(localizedInThisBundle: "DONE_EXPORT_VIEW_SUBTITLE_EXPORT_CANCELLED_BY_USER")
        case .exportFailed:
            return String(localizedInThisBundle: "DONE_EXPORT_VIEW_SUBTITLE_EXPORT_FAILED")
        }
    }
    
    private var subtitleFailedAttachments: String? {
        switch sendingDoneStatus {
        case .exportWasSuccessful(failedFylesCount: let failedFylesCount):
            if failedFylesCount > 0 {
                return String(localizedInThisBundle: "DONE_EXPORT_VIEW_SUBTITLE_EXPORT_\(failedFylesCount)_ATTACHMENTS_COULD_NOT_BE_SENT")
            } else {
                return nil
            }
        case .exportWasCancelledByUser, .exportFailed:
            return nil
        }
    }
    
    private var state: ProgressItemState {
        switch sendingDoneStatus {
        case .exportWasSuccessful:
            return .success
        case .exportWasCancelledByUser:
            return .warning
        case .exportFailed:
            return .error
        }
    }
        
    var body: some View {
        ProgressItemRowView(state: state, showLine: false, title: title) {
            Text(subtitle)
            if let subtitleFailedAttachments {
                Text(subtitleFailedAttachments)
            }
        }
    }

}


private struct SendingAttachmentsStatusView: View {

    let sendingAttachmentsStatus: SendingAttachmentsStatus
    let showLine: Bool

    private var progressItemState: ProgressItemState {
        switch sendingAttachmentsStatus {
        case .starting:
            return .inProgress
        case .inProgress(sentFylesCount: let sentFylesCount, failedFylesCount: let failedFylesCount, byteCountSent: _, byteCountFailedToSend: _, numberOfFylesToSend: let numberOfFylesToSend, byteCountToSend: _, bytesPerSecond: _, eta: _):
            if sentFylesCount + failedFylesCount >= numberOfFylesToSend {
                return failedFylesCount > 0 ? .warning : .success
            } else {
                return .inProgress
            }
        }
    }
    
    private var progress: (value: Double, total: Double)? {
        switch sendingAttachmentsStatus {
        case .starting:
            return nil
        case .inProgress(sentFylesCount: _, failedFylesCount: _, byteCountSent: let byteCountSent, byteCountFailedToSend: let byteCountFailedToSend, numberOfFylesToSend: _, byteCountToSend: let byteCountToSend, bytesPerSecond: _, eta: _):
            let byteCountDone = byteCountSent + byteCountFailedToSend
            if byteCountDone < byteCountToSend {
                return (Double(byteCountDone), Double(byteCountToSend))
            } else {
                return nil
            }
        }
    }

    private var subtitle: String? {
        switch sendingAttachmentsStatus {
        case .starting:
            return String(localizedInThisBundle: "STARTING")
        case .inProgress(sentFylesCount: let sentFylesCount, failedFylesCount: let failedFylesCount, byteCountSent: _, byteCountFailedToSend: _, numberOfFylesToSend: let numberOfFylesToSend, byteCountToSend: _, bytesPerSecond: _, eta: _):
            if sentFylesCount + failedFylesCount < numberOfFylesToSend {
                return String(localizedInThisBundle: "SENDING_ATTACHMENTS_STATUS_VIEW_SENDING_\(numberOfFylesToSend)_ATTACHMENTS")
            } else {
                return String(localizedInThisBundle: "SENDING_ATTACHMENTS_STATUS_VIEW_DID_SEND_\(numberOfFylesToSend)_ATTACHMENTS")
            }
        }
    }
    
    private var subtitleForFailedAttachments: String? {
        switch sendingAttachmentsStatus {
        case .starting:
            return nil
        case .inProgress(sentFylesCount: _, failedFylesCount: let failedFylesCount, byteCountSent: _, byteCountFailedToSend: _, numberOfFylesToSend: _, byteCountToSend: _, bytesPerSecond: _, eta: _):
            guard failedFylesCount > 0 else { return nil }
            return String(localizedInThisBundle: "SENDING_ATTACHMENTS_STATUS_VIEW_\(failedFylesCount)_ATTACHMENTS_COULD_NOT_BE_SENT")
        }
    }

    private var progressPercentage: String? {
        guard let progress else { return nil }
        let percentage = Int(round(100 * progress.value / progress.total))
        return "\(percentage)%"
    }
    
    private var eta: TimeInterval? {
        switch sendingAttachmentsStatus {
        case .starting:
            return nil
        case .inProgress(sentFylesCount: _, failedFylesCount: _, byteCountSent: _, byteCountFailedToSend: _, numberOfFylesToSend: _, byteCountToSend: _, bytesPerSecond: _, eta: let eta):
            return progressItemState == .inProgress ? eta : nil
        }
    }
    
    private var bytesPerSecond: Double? {
        switch sendingAttachmentsStatus {
        case .starting:
            return nil
        case .inProgress(sentFylesCount: _, failedFylesCount: _, byteCountSent: _, byteCountFailedToSend: _, numberOfFylesToSend: _, byteCountToSend: _, bytesPerSecond: let bytesPerSecond, eta: _):
            return progressItemState == .inProgress ? bytesPerSecond : nil
        }
    }
    
    private var etaString: String? {
        guard let eta, let bytesPerSecond else { return nil }
        let durationFormatter = DateComponentsFormatter()
        durationFormatter.allowedUnits = [.hour, .minute, .second]
        durationFormatter.unitsStyle = .abbreviated
        guard let formattedDuration = durationFormatter.string(from: eta) else { return nil }
        let rateFormatter = ByteCountFormatter()
        rateFormatter.allowedUnits = [.useKB, .useMB, .useGB]
        rateFormatter.countStyle = .decimal // 1 KB = 1000 bytes, conventional for transfer rates
        let formattedRate = rateFormatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
        return String(localizedInThisBundle: "ABOUT_\(formattedDuration)_REMAINING_AT_\(formattedRate)")
    }


    private var title: String {
        switch sendingAttachmentsStatus {
        case .starting:
            return String(localizedInThisBundle: "SENDING_ATTACHMENTS_VIEW_TITLE")
        case .inProgress(let sentFylesCount, let failedFylesCount, _, _, let numberOfFylesToSend, _, _, _):
            if sentFylesCount + failedFylesCount >= numberOfFylesToSend {
                return String(localizedInThisBundle: "SENDING_ATTACHMENTS_VIEW_TITLE_DONE")
            } else {
                return String(localizedInThisBundle: "SENDING_ATTACHMENTS_VIEW_TITLE")
            }
        }
    }

    var body: some View {
        ProgressItemRowView(state: progressItemState, showLine: showLine, title: title) {
            if let subtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
                if let subtitleForFailedAttachments {
                    Text(subtitleForFailedAttachments)
                        .foregroundStyle(.secondary)
                }
            }
            if let progress {
                ProgressView(value: progress.value, total: progress.total)
                ProgressAndETATextsView(etaString: etaString, progressPercentage: progressPercentage)
            }
        }
    }

}


private struct SendingMessagesStatusView: View {

    let sendingMessagesStatus: SendingMessagesStatus
    let showLine: Bool

    @State private var isProgressShown = false

    private var progressItemState: ProgressItemState {
        switch sendingMessagesStatus {
        case .starting:
            return .inProgress
        case .inProgress(sentMessageCount: let sentMessageCount, missingMessageCount: let missingMessageCount, numberOfMessagesToSend: let numberOfMessagesToSend, messagesPerSecond: _, eta: _):
            return sentMessageCount + missingMessageCount >= numberOfMessagesToSend ? .success : .inProgress
        }
    }

    private var progress: (value: Double, total: Double)? {
        switch sendingMessagesStatus {
        case .starting:
            return nil
        case .inProgress(sentMessageCount: let sentMessageCount, missingMessageCount: let missingMessageCount, numberOfMessagesToSend: let numberOfMessagesToSend, messagesPerSecond: _, eta: _):
            if sentMessageCount + missingMessageCount < numberOfMessagesToSend {
                return (Double(min(sentMessageCount+missingMessageCount, numberOfMessagesToSend)), Double(numberOfMessagesToSend))
            } else {
                return nil
            }
        }
    }
    
    private var subtitle1: String? {
        switch sendingMessagesStatus {
        case .starting:
            return String(localizedInThisBundle: "SENDING_MESSAGES_STATUS_VIEW_01_STARTING")
        case .inProgress(sentMessageCount: let sentMessageCount, missingMessageCount: let missingMessageCount, numberOfMessagesToSend: let numberOfMessagesToSend, messagesPerSecond: _, eta: _):
            if sentMessageCount + missingMessageCount < numberOfMessagesToSend {
                return String(localizedInThisBundle: "SENDING_MESSAGES_STATUS_VIEW_02_SENDING_\(numberOfMessagesToSend)_MESSAGES")
            } else {
                return String(localizedInThisBundle: "SENDING_MESSAGES_STATUS_VIEW_03_DID_SEND_\(sentMessageCount)_MESSAGES")
            }
        }
    }
    
    private var subtitle2: String? {
        switch sendingMessagesStatus {
        case .starting:
            return nil
        case .inProgress(sentMessageCount: let sentMessageCount, missingMessageCount: let missingMessageCount, numberOfMessagesToSend: let numberOfMessagesToSend, messagesPerSecond: _, eta: _):
            if sentMessageCount + missingMessageCount < numberOfMessagesToSend {
                return nil
            } else {
                if missingMessageCount > 0 {
                    return String(localizedInThisBundle: "SENDING_MESSAGES_STATUS_VIEW_03_\(missingMessageCount)_MESSAGES_COULD_NOT_BE_SENT")
                } else {
                    return nil
                }
            }
        }
    }
    
    private var progressPercentage: String? {
        guard let progress else { return nil }
        let percentage = Int(round(100 * progress.value / progress.total))
        return "\(percentage)%"
    }
    
    
    private var eta: TimeInterval? {
        switch sendingMessagesStatus {
        case .starting:
            return nil
        case .inProgress(sentMessageCount: _, missingMessageCount: _, numberOfMessagesToSend: _, messagesPerSecond: _, eta: let eta):
            return progressItemState == .inProgress ? eta : nil
        }
    }
    
    
    private var etaString: String? {
        guard let eta else { return nil }
        let duration = DateComponentsFormatter()
        duration.allowedUnits = [.hour, .minute, .second]
        duration.unitsStyle = .abbreviated
        guard let formattedDuration = duration.string(from: eta) else { return nil }
        return String(localizedInThisBundle: "ABOUT_\(formattedDuration)_REMAINING")
    }
    
    
    private var title: String {
        switch sendingMessagesStatus {
        case .starting:
            return String(localizedInThisBundle: "SENDING_MESSAGES_STATUS_VIEW_TITLE")
        case .inProgress(let sentMessageCount, let missingMessageCount, let numberOfMessagesToSend, _, _):
            if sentMessageCount + missingMessageCount >= numberOfMessagesToSend {
                return String(localizedInThisBundle: "SENDING_MESSAGES_STATUS_VIEW_TITLE_DONE")
            } else {
                return String(localizedInThisBundle: "SENDING_MESSAGES_STATUS_VIEW_TITLE")
            }
        }
    }

    var body: some View {
        ProgressItemRowView(state: progressItemState, showLine: showLine, title: title) {
            if let subtitle1 {
                Text(subtitle1)
                if let subtitle2 {
                    Text(subtitle2)
                }
            }
            if let progress {
                ProgressView(value: progress.value, total: progress.total)
                ProgressAndETATextsView(etaString: etaString, progressPercentage: progressPercentage)
            }
        }
    }

}


/// Fourth progress item view.
private struct NegotiatingWhatToSendStatusView: View {

    let negotiatingWhatToSendStatus: NegotiatingWhatToSendStatus
    let showLine: Bool
    let scope: TransferScope

    private var progressItemState: ProgressItemState {
        switch negotiatingWhatToSendStatus {
        case .inProgress:
            return .inProgress
        case .done:
            return .success
        }
    }

    private var subtitle1: String {
        switch negotiatingWhatToSendStatus {
        case .inProgress:
            return String(localizedInThisBundle: "NEGOTIATING_WHAT_TO_SEND_VIEW_01_IN_PROGRESS")
        case .done(numberOfMessagesToSend: let numberOfMessagesToSend, numberOfFylesToSend: _, byteCountToSend: _):
            return String(localizedInThisBundle: "NEGOTIATING_WHAT_TO_SEND_VIEW_02_WILL_TRANSFER_\(numberOfMessagesToSend)_MESSAGES")
        }
    }
    
    private var subtitle2: String? {
        switch negotiatingWhatToSendStatus {
        case .inProgress:
            return nil
        case .done(numberOfMessagesToSend: _, numberOfFylesToSend: let numberOfFylesToSend, byteCountToSend: let byteCountToSend):
            if numberOfFylesToSend > 0 {
                return String(localizedInThisBundle: "NEGOTIATING_WHAT_TO_SEND_VIEW_02_WILL_TRANSFER_\(numberOfFylesToSend)_ATTACHMENTS_FOR_\(byteCountToSend.formatted(.byteCount(style: .file)))")
            } else {
                return nil
            }
        }
    }
    
    private var title: String {
        switch scope {
        case .messagesOnly:
            switch negotiatingWhatToSendStatus {
            case .inProgress:
                return String(localizedInThisBundle: "NEGOTIATING_MESSAGES_TO_SEND_VIEW_TITLE")
            case .done:
                return String(localizedInThisBundle: "NEGOTIATING_MESSAGES_TO_SEND_VIEW_TITLE_DONE")
            }
        case .messagesAndAttachments:
            switch negotiatingWhatToSendStatus {
            case .inProgress:
                return String(localizedInThisBundle: "NEGOTIATING_MESSAGES_AND_ATTACHMENTS_TO_SEND_VIEW_TITLE")
            case .done:
                return String(localizedInThisBundle: "NEGOTIATING_MESSAGES_AND_ATTACHMENTS_TO_SEND_VIEW_TITLE_DONE")
            }
        }
    }

    var body: some View {
        ProgressItemRowView(state: progressItemState, showLine: showLine, title: title) {
            VStack(alignment: .leading) {
                Text(subtitle1)
                if let subtitle2 {
                    Text(subtitle2)
                        .lineLimit(2, reservesSpace: true)
                }
            }
        }
    }

}


/// Third progress item view.
private struct FetchingAllHashAndSizesOfFylesStatusView: View {
    
    let fetchingAllHashAndSizesOfFylesStatus: FetchingAllHashAndSizesOfFylesStatus
    let showLine: Bool

    private var progressItemState: ProgressItemState {
        switch fetchingAllHashAndSizesOfFylesStatus {
        case .inProgress:
            return .inProgress
        case .done:
            return .success
        }
    }
    
    private var subtitle: String {
        switch fetchingAllHashAndSizesOfFylesStatus {
        case .inProgress:
            return String(localizedInThisBundle: "FETCHING_ATTACHMENTS_VIEW_01_IN_PROGRESS")
        case .done(numberOfFylesFound: let numberOfFylesFound, totalByteCount: let totalByteCount):
            if totalByteCount > 0 {
                return String(localizedInThisBundle: "FETCHING_ATTACHMENTS_VIEW_02_FOUND_\(numberOfFylesFound)_ATTACHMENTS_REPRESENTING_\(totalByteCount.formatted(.byteCount(style: .file)))_BYTES")
            } else {
                return String(localizedInThisBundle: "FETCHING_ATTACHMENTS_VIEW_02_FOUND_\(numberOfFylesFound)_ATTACHMENTS_REPRESENTING_ZERO_BYTES")
            }
        }
    }

    private var title: String {
        switch fetchingAllHashAndSizesOfFylesStatus {
        case .inProgress:
            return String(localizedInThisBundle: "FETCHING_ATTACHMENTS_VIEW_TITLE")
        case .done:
            return String(localizedInThisBundle: "FETCHING_ATTACHMENTS_VIEW_TITLE_DONE")
        }
    }

    var body: some View {
        ProgressItemRowView(state: progressItemState, showLine: showLine, title: title) {
            Text(subtitle)
        }
    }

}


/// Second progress item view.
private struct FetchingDiscussionsListStatusView: View {

    let fetchingDiscussionsListStatus: FetchingDiscussionsListStatus
    let showLine: Bool

    private var progressItemState: ProgressItemState {
        switch fetchingDiscussionsListStatus {
        case .inProgress:
            return .inProgress
        case .done:
            return .success
        }
    }
    
    private var subtitle: String {
        switch fetchingDiscussionsListStatus {
        case .inProgress:
            return String(localizedInThisBundle: "FETCHING_DISCUSSION_LIST_01_IN_PROGRESS")
        case .done(numberOfDiscussionsFound: let numberOfDiscussionsFound):
            return String(localizedInThisBundle: "FETCHING_DISCUSSION_LIST_01_FOUND_\(numberOfDiscussionsFound)_DISCUSSIONS")
        }
    }

    private var title: String {
        switch fetchingDiscussionsListStatus {
        case .inProgress:
            return String(localizedInThisBundle: "FETCHING_DISCUSSION_LIST_TITLE")
        case .done:
            return String(localizedInThisBundle: "FETCHING_DISCUSSION_LIST_TITLE_DONE")
        }
    }

    var body: some View {
        ProgressItemRowView(state: progressItemState, showLine: showLine, title: title) {
            Text(subtitle)
        }
    }

}


/// First progress item view.
private struct InitializationStatusView: View {

    let initializingStatus: InitializingStatusOnSourceDevice
    let localNetworkType: LocalNetworkExportView.LocalNetworkType
    let showLine: Bool
    
    private var subtitle: LocalizedStringKey {
        switch initializingStatus {
        case .inProgress:
            return "INIT_STATUS_VIEW_01_IN_PROGRESS"
        case .connectingToDestinationDevice:
            switch localNetworkType {
            case .webRTC:
                return "INIT_STATUS_VIEW_02_CONNECTING_TO_DESTINATION_DEVICE"
            case .wifiAware(ownedCryptoId: _, pairedDevice: let pairedDevice):
                let pairedDeviceName = pairedDevice.pairingInfo?.pairingName ?? pairedDevice.pairingInfo?.modelName
                if let pairedDeviceName {
                    return "INIT_STATUS_VIEW_02_SUBTITLE_WIFI_AWARE_\(pairedDeviceName)"
                } else {
                    return "INIT_STATUS_VIEW_02_SUBTITLE_WIFI_AWARE"
                }
            }
        case .connectedToDestinationDevice:
            return "INIT_STATUS_VIEW_03_CONNECTED_TO_DESTINATION_DEVICE"
        }
    }
    
    private var progressItemState: ProgressItemState {
        switch initializingStatus {
        case .inProgress, .connectingToDestinationDevice:
            return .inProgress
        case .connectedToDestinationDevice:
            return .success
        }
    }
    
    private var title: String {
        switch initializingStatus {
        case .inProgress, .connectingToDestinationDevice:
            return String(localizedInThisBundle: "INIT_STATUS_VIEW_TITLE_INITIALIZING_WEBRTC")
        case .connectedToDestinationDevice:
            return String(localizedInThisBundle: "INIT_STATUS_VIEW_TITLE_INITIALIZED_WEBRTC")
        }
    }

    var body: some View {
        ProgressItemRowView(state: progressItemState, showLine: showLine, title: title) {
            Text(subtitle)
        }
    }

}


// MARK: - Previews

#if DEBUG

private actor MockTransferServiceForLocalNetworkExportView {
    private let mockTransferId = UUID().uuidString
}

extension MockTransferServiceForLocalNetworkExportView: TransferServiceForLocalNetworkExportView {
        
    var transferId: String { mockTransferId }
    
    func initiateHistoryTransfer(_ view: LocalNetworkExportView, transferTransportType: TransferTransportType, scope: TransferScope) async throws {
        // Nothing to do in previews
    }
    
    func userWantsToCancelExport(_ view: LocalNetworkExportView, transferId: String, localNetworkType: LocalNetworkExportView.LocalNetworkType) async {
        // Nothing to do in previews
    }
    
    func onDisappear(of view: LocalNetworkExportView) async {
        // Nothing to do in previews
    }
    
    func viewRequiresAsyncStreamOfTransferExportState(_ view: LocalNetworkExportView) async -> AsyncStream<TransferExportState> {
        let stream = AsyncStream<TransferExportState> { (continuation: AsyncStream<TransferExportState>.Continuation) in
            continuation.yield(.initializing(.inProgress))
            Task {
                do {
                    try await Task.sleep(for: .seconds(0))
                    continuation.yield(.initializing(.connectingToDestinationDevice))
                    try await Task.sleep(for: .seconds(0))
                    continuation.yield(.initializing(.connectedToDestinationDevice))
                    try await Task.sleep(for: .seconds(0))
                    continuation.yield(.sourceTransferStepsState(.fetchingDiscussionsList(status: .inProgress)))
                    try await Task.sleep(for: .seconds(0))
                    continuation.yield(.sourceTransferStepsState(.fetchingDiscussionsList(status: .done(numberOfDiscussionsFound: 123))))
                    try await Task.sleep(for: .seconds(0))
                    continuation.yield(.sourceTransferStepsState(.fetchingAllHashAndSizesOfFyles(status: .inProgress)))
                    try await Task.sleep(for: .seconds(0))
                    continuation.yield(.sourceTransferStepsState(.fetchingAllHashAndSizesOfFyles(status: .done(numberOfFylesFound: 42, totalByteCount: 10_000))))
                    try await Task.sleep(for: .seconds(0))
                    continuation.yield(.sourceTransferStepsState(.negotiatingWhatToSend(status: .inProgress)))
                    let numberOfMessagesToSend = 100
                    let numberOfFylesToSend = 21
                    let byteCountToSend = UInt64(5_000)
                    continuation.yield(.sourceTransferStepsState(.negotiatingWhatToSend(status: .done(numberOfMessagesToSend: numberOfMessagesToSend, numberOfFylesToSend: numberOfFylesToSend, byteCountToSend: byteCountToSend))))
                    try await Task.sleep(for: .seconds(1))
                    continuation.yield(.sourceTransferStepsState(.sendingMessages(status: .starting)))
                    
                    // Simulate message sending
                    
                    var sentMessageCount = 0
                    let messagesPerSecondToSimulate = 10.0
                    let sleepInterval: TimeInterval = 0.5
                    let messagesToSendAfterEachSleep = Int(messagesPerSecondToSimulate / sleepInterval)
                    
                    while sentMessageCount < numberOfMessagesToSend {
                        try await Task.sleep(for: sleepInterval)
                        sentMessageCount = min(sentMessageCount + messagesToSendAfterEachSleep, numberOfMessagesToSend)
                        let eta: TimeInterval? = Double(numberOfMessagesToSend - sentMessageCount) / messagesPerSecondToSimulate
                        continuation.yield(.sourceTransferStepsState(.sendingMessages(status: .inProgress(sentMessageCount: sentMessageCount, missingMessageCount: 1, numberOfMessagesToSend: numberOfMessagesToSend, messagesPerSecond: messagesPerSecondToSimulate, eta: eta))))
                    }
                    
                    // Simulate attachment sending

                    var sentFylesCount = 0
                    var byteCountSent: UInt64 = 0
                    let progressPerSecondToSimulate: Double = 0.1
                    let sleepIntervalForAttachments: TimeInterval = 0.5
                    let progressPerSleepInterval: Double = progressPerSecondToSimulate * sleepIntervalForAttachments
                    let bytesPerSecondToSimulate = Double(byteCountToSend) * progressPerSecondToSimulate

                    continuation.yield(.sourceTransferStepsState(.sendingAttachments(status: .starting)))
                    while sentFylesCount < numberOfFylesToSend {
                        try await Task.sleep(for: sleepIntervalForAttachments)
                        byteCountSent = min(byteCountToSend, byteCountSent + UInt64((progressPerSleepInterval * Double(byteCountToSend))))
                        sentFylesCount = Int(Double(numberOfFylesToSend) * Double(byteCountSent) / Double(byteCountToSend))
                        let eta: TimeInterval? = Double(byteCountToSend - byteCountSent) / bytesPerSecondToSimulate
                        continuation.yield(.sourceTransferStepsState(.sendingAttachments(
                            status: .inProgress(sentFylesCount: sentFylesCount,
                                                failedFylesCount: 0,
                                                byteCountSent: byteCountSent,
                                                byteCountFailedToSend: 0,
                                                numberOfFylesToSend: numberOfFylesToSend,
                                                byteCountToSend: byteCountToSend,
                                                bytesPerSecond: bytesPerSecondToSimulate,
                                                eta: eta
                                               )
                        )))
                    }

                    continuation.yield(.sourceTransferStepsState(.done(status: .exportWasSuccessful(failedFylesCount: 0))))

                    continuation.finish()
                    
                } catch {
                    assertionFailure()
                }
            }
        }
        return stream
    }
    
}

private final class ActionsForPreviews {
    let mockTransferServiceForLocalNetworkExportView = MockTransferServiceForLocalNetworkExportView()
}

extension ActionsForPreviews: LocalNetworkExportViewActions {
        
    func historySourceDeviceWantsToSendTransferConfirmationRequestToDestinationOwnedDevice(
        _ view: LocalNetworkExportView,
        transferId: String,
        otherOwnedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier
    ) async throws -> DestinationOwnedDeviceDecision {
        try await Task.sleep(seconds: 1) // Simultates the time required for the user to accept the transfer on the destination device
        return .startTransfer
    }

    func userRequiresMessageHistoryTransferService(_ view: LocalNetworkExportView) async throws -> any TransferServiceForLocalNetworkExportView {
        return mockTransferServiceForLocalNetworkExportView
    }
    
    func userWantsToDismissView(_ view: LocalNetworkExportView) {
        print("User wants to dismiss the view")
    }
    
}

extension ActionsForPreviews: LocalNetworkExportViewInternalActions {
    
    func userWantsToPopView(_ view: LocalNetworkExportView) {
        print("User wants to pop the view")
    }
    
}

@MainActor
private let actionsForPreviews = ActionsForPreviews()

#Preview("WebRTC") {
    LocalNetworkExportView(
        localNetorkType: .webRTC(otherOwnedDeviceIdentifier: .sampleDatas[0], nameOfRemoteDevice: "iPhone 17"),
        scope: .messagesAndAttachments,
        internalActions: actionsForPreviews,
        actions: actionsForPreviews
    )
}


@MainActor
private final class InternalActionsForPreviews {}

extension InternalActionsForPreviews: TransferRequestWasRejectedByDestinationViewInternalActions {
    
    func userWantsToPopView(_ view: TransferRequestWasRejectedByDestinationView) {
        print("User wants to pop view")
    }
    
}

@MainActor
private let internalActionsForPreviews = InternalActionsForPreviews()

#Preview {
    TransferRequestWasRejectedByDestinationView(internalActions: internalActionsForPreviews)
}

#endif
