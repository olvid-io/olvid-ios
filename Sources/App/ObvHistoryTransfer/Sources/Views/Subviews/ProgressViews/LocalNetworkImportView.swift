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
import ObvContinuedProcessingTaskManager
import ConfettiSwiftUI


@MainActor
public protocol LocalNetworkImportViewActions: AnyObject {
    func userRequiresMessageHistoryTransferService(_ view: LocalNetworkImportView) async throws -> any TransferServiceForLocalNetworkImportView
    func userWantsToDismissView(_ view: LocalNetworkImportView)
}

public protocol TransferServiceForLocalNetworkImportView: Sendable {
    func viewRequiresAsyncStreamOfTransferImportState(_ view: LocalNetworkImportView) async -> AsyncStream<TransferImportState>
    func userWantsToCancelImport(_ view: LocalNetworkImportView, localNetworkType: LocalNetworkImportView.LocalNetworkType) async
    
    func userWantsToAcceptHistoryTransfer(
        _ view: LocalNetworkImportView,
        localNetorkType: LocalNetworkImportView.LocalNetworkType
    ) async throws
    
    func userWantsToCancelHistoryTransfer(
        _ view: LocalNetworkImportView,
        localNetorkType: LocalNetworkImportView.LocalNetworkType
    ) async throws
    
    func onDisappear(of view: LocalNetworkImportView) async
    
}
    
public struct LocalNetworkImportView: View {

    let localNetworkType: LocalNetworkType
    let actions: any LocalNetworkImportViewActions
    
    init(localNetworkType: LocalNetworkType,
         actions: any LocalNetworkImportViewActions
    ) {
        self.localNetworkType = localNetworkType
        self.actions = actions
        switch localNetworkType {
        case .webRTC:
            self.interfaceState = .acceptingOrRejectingTransferRequestFromSource
        case .wifiAware:
            self.interfaceState = .transferAccepted
        }
    }
    
    public enum LocalNetworkType: Sendable {
        case webRTC(sourceDeviceIdentifier: ObvOwnedDeviceIdentifier, sourceDeviceName: String?, transferIdFromSource: String)
        case wifiAware(ownedCryptoId: ObvCryptoId, pairedDevice: ObvWAPairedDevice)
    }

    @State private var interfaceState: InterfaceState // Initial value depends on the local network type
    @State private var globalState: ImportInProgressInternalView.GlobalState = .inProgress
    @State private var transferService: (any TransferServiceForLocalNetworkImportView)?

    private var sourceDeviceName: String? {
        switch localNetworkType {
        case .webRTC(sourceDeviceIdentifier: _, sourceDeviceName: let name, transferIdFromSource: _):
            return name
        case .wifiAware(ownedCryptoId: _, pairedDevice: let pairedDevice):
            return pairedDevice.pairingInfo?.pairingName ?? pairedDevice.pairingInfo?.modelName
        }
    }
    
    private enum InterfaceState {
        case acceptingOrRejectingTransferRequestFromSource
        case transferAccepted
    }
    
    private func getTransferService() async throws -> any TransferServiceForLocalNetworkImportView {
        if let transferService {
            return transferService
        } else {
            let transferService = try await actions.userRequiresMessageHistoryTransferService(self)
            self.transferService = transferService
            return transferService
        }
    }
    
    private func onDisappear() {
        Task {
            assert(transferService != nil)
            switch globalState {
            case .inProgress:
                await transferService?.userWantsToCancelImport(self, localNetworkType: localNetworkType)
            case .canceling, .done:
                break
            }
            await transferService?.onDisappear(of: self)
        }
    }
    
    @ViewBuilder
    private var content: some View {
        Group {
            switch interfaceState {
            case .acceptingOrRejectingTransferRequestFromSource:
                AcceptingOrRejectingTransferRequestFromSourceView(
                    sourceDeviceName: sourceDeviceName,
                    internalActions: self)
            case .transferAccepted:
                ImportInProgressInternalView(localNetworkType: localNetworkType, actions: self, globalState: $globalState)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onDisappear(perform: onDisappear)
    }

    private func onTaskForWifiAware() async {
        do {
            try await self.userWantsToAcceptHistoryTransferRequest()
        } catch {
            assertionFailure()
        }
    }
    
    public var body: some View {
        switch localNetworkType {
        case .webRTC:
            NavigationStack {
                content
            }
        case .wifiAware:
            content
                .task(onTaskForWifiAware)
        }
    }

}


extension LocalNetworkImportView {
    
    enum ObvError: Error {
        case transferServiceIsNil
    }
    
}


extension LocalNetworkImportView: AcceptingOrRejectingTransferRequestFromSourceViewInternalActions {
    
    fileprivate func userWantsToAcceptHistoryTransferRequest(_ view: AcceptingOrRejectingTransferRequestFromSourceView) async throws {
        try await userWantsToAcceptHistoryTransferRequest()
    }
    
    
    fileprivate func userWantsToAcceptHistoryTransferRequest() async throws {
        let transferService = try await self.getTransferService()
        try await transferService.userWantsToAcceptHistoryTransfer(self, localNetorkType: localNetworkType)
        withAnimation { interfaceState = .transferAccepted }
    }
    
    fileprivate func userWantsToRejectHistoryTransferRequest(_ view: AcceptingOrRejectingTransferRequestFromSourceView) async throws {
        let transferService = try await self.getTransferService()
        try await transferService.userWantsToCancelHistoryTransfer(self, localNetorkType: localNetworkType)
    }
    
}


extension LocalNetworkImportView: ImportInProgressInternalViewActions {
        
    fileprivate func viewRequiresAsyncStreamOfTransferImportState(_ view: ImportInProgressInternalView) async throws -> AsyncStream<TransferImportState> {
        let transferService = try await self.getTransferService()
        return await transferService.viewRequiresAsyncStreamOfTransferImportState(self)
    }
    
    
    fileprivate func userWantsToCancelImport(_ view: ImportInProgressInternalView) async {
        assert(transferService != nil)
        await transferService?.userWantsToCancelImport(self, localNetworkType: localNetworkType)
    }
    
    
    fileprivate func userWantsToDismissView(_ view: ImportInProgressInternalView) {
        actions.userWantsToDismissView(self)
    }

}


// MARK: - Internal view: AcceptingOrRejectingTransferRequestFromSourceView

@MainActor
private protocol AcceptingOrRejectingTransferRequestFromSourceViewInternalActions {
    func userWantsToAcceptHistoryTransferRequest(_ view: AcceptingOrRejectingTransferRequestFromSourceView) async throws
    func userWantsToRejectHistoryTransferRequest(_ view: AcceptingOrRejectingTransferRequestFromSourceView) async throws
}

private struct AcceptingOrRejectingTransferRequestFromSourceView: View {

    let sourceDeviceName: String?
    let internalActions: any AcceptingOrRejectingTransferRequestFromSourceViewInternalActions

    @State private var isInterfaceDisabled = false

    private var confirmationString: String {
        if let sourceDeviceName {
            return String(localizedInThisBundle: "CONFIRM_HISTORY_TRANSFER_DESCRIPTION_\(sourceDeviceName)")
        } else {
            return String(localizedInThisBundle: "CONFIRM_HISTORY_TRANSFER_DESCRIPTION")
        }
    }
    
    private func acceptButtonTapped() {
        isInterfaceDisabled = true
        Task {
            defer { isInterfaceDisabled = false }
            try await internalActions.userWantsToAcceptHistoryTransferRequest(self)
        }
    }
    
    private func cancelButtonTapped() {
        isInterfaceDisabled = true
        Task {
            defer { isInterfaceDisabled = false }
            try await internalActions.userWantsToRejectHistoryTransferRequest(self)
        }
    }
    

    var body: some View {
        Form {
            
            ExplanationsSectionView(explanation: nil)
            
            Section {
                HStack {
                    Spacer(minLength: 0)
                    Text(confirmationString)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .listRowSeparator(.hidden)
            }
            
        }
        .safeAreaInset(edge: .bottom) {
            VStack {
                OlvidButtonNew(action: acceptButtonTapped, style: .glassOrBorderedProminent) {
                    Text("BUTTON_TITLE_START_TRANSFER")
                }
                OlvidButtonNew(action: cancelButtonTapped, style: .glassOrBordered) {
                    Text("BUTTON_TITLE_CANCEL")
                }
            }
            .padding()
        }
    }
    
}


// MARK: - Internal view: ImportInProgressInternalView

@MainActor
private protocol ImportInProgressInternalViewActions {
    func viewRequiresAsyncStreamOfTransferImportState(_ view: ImportInProgressInternalView) async throws -> AsyncStream<TransferImportState>
    func userWantsToCancelImport(_ view: ImportInProgressInternalView) async
    func userWantsToDismissView(_ view: ImportInProgressInternalView)
}

private struct ImportInProgressInternalView: View {

    let localNetworkType: LocalNetworkImportView.LocalNetworkType
    let actions: any ImportInProgressInternalViewActions
    @Binding var globalState: GlobalState
    
    @State private var initializingStatus: InitializingStatusOnDestinationDevice = .inProgress
    @State private var receivingDiscussionsListStatus: ReceivingDiscussionsListStatus?
    @State private var negotiatingWhatToReceiveStatus: NegotiatingWhatToReceiveStatus?
    @State private var receivingMessagesStatus: ReceivingMessagesStatus?
    @State private var receivingAttachmentstatus: ReceivingAttachmentstatus?
    @State private var receivingDoneStatus: ReceivingDoneStatus?

    fileprivate enum GlobalState {
        case inProgress
        case canceling
        case done
    }
    
    @State private var isInterfaceDisabled: Bool = false

    private func onTask() async {
        ObvContinuedProcessingTaskManager.run(taskKind: .historyTransfer) { bgContinuedProcessingTask in
            
            bgContinuedProcessingTask?.expirationHandler = {
                Task { await self.actions.userWantsToCancelImport(self) }
            }
            
            let stream = try await self.actions.viewRequiresAsyncStreamOfTransferImportState(self)
            
            for await newState in stream {
                
                try withAnimation {
                    
                    switch newState {
                        
                    case .initializing(let status):
                        
                        globalState = .inProgress
                        initializingStatus = status
                        
                    case .destinationTransferStepsState(let destinationTransferStepsState):
                        
                        globalState = .inProgress
                        switch destinationTransferStepsState {
                        case .receivingDiscussionsList(status: let status):
                            receivingDiscussionsListStatus = status
                        case .negotiatingWhatToReceive(status: let status):
                            negotiatingWhatToReceiveStatus = status
                        case .receivingMessages(status: let status):
                            receivingMessagesStatus = status
                        case .receivingAttachment(status: let status):
                            receivingAttachmentstatus = status
                            if let bgContinuedProcessingTask, let unitCount = status.unitCount {
                                bgContinuedProcessingTask.progress.totalUnitCount = unitCount.total
                                bgContinuedProcessingTask.progress.completedUnitCount = unitCount.completed
                            }
                        case .done(status: let status):
                            receivingDoneStatus = status
                            globalState = .done
                            switch status {
                            case .exportWasSuccessful(let failedFylesCount):
                                guard failedFylesCount == 0 else {
                                    throw ObvError.certainFilesCouldNotBeTransferred
                                }
                                triggerConfettiCanon = true
                            case .exportWasCancelledByUser:
                                throw ObvError.exportWasCancelled
                            case .exportFailed, .exportFailedAsIdentitiesDidNotMatch:
                                throw ObvError.exportFailed
                            }
                        }
                        
                    case .canceling:
                        
                        globalState = .canceling
                        
                    }
                                        
                } // end of withAnimation

            } // end of stream
         
            debugPrint("📰✅ ImportInProgressInternalView stream is finished")
            
        }
    }
    
    
    enum ObvError: Error {
        case certainFilesCouldNotBeTransferred
        case exportWasCancelled
        case exportFailed
    }
    
    
    private func buttonTapped() {
        switch globalState {
        case .inProgress:
            isInterruptConfirmationDialogPresented = true
        case .canceling:
            return
        case .done:
            actions.userWantsToDismissView(self)
        }
    }
    
    private var buttonTitle: String {
        switch globalState {
        case .inProgress:
            return String(localizedInThisBundle: "INTERRUPT_TRANSFER_AND_CONTINUE_LATER")
        case .canceling:
            return String(localizedInThisBundle: "BUTTON_TITLE_CANCELING")
        case .done:
            return String(localizedInThisBundle: "DISMISS")
        }
    }

    private func userWantsToInterruptImport() {
        self.isInterfaceDisabled = true
        Task {
            defer { self.isInterfaceDisabled = false }
            await actions.userWantsToCancelImport(self)
            // We force the view to show a cancelled state
            withAnimation {
                self.receivingDoneStatus = .exportWasCancelledByUser
                self.globalState = .done
            }
        }
    }

    
    @State private var isInterruptConfirmationDialogPresented = false
    private var interruptConfirmationDialogTitle: String { String(localizedInThisBundle: "INTERRUPT_IMPORT_CONFIRMATION_DIALOG_TITLE") }

    private enum ScrollAnchor: Hashable {
        case receivingDiscussionsList
        case negotiatingWhatToReceive
        case receivingMessages
        case receivingAttachment
        case done
    }

    @State private var triggerConfettiCanon = false

    var body: some View {
        ScrollView {
            ScrollViewReader { proxy in

                ObvCardView {
                    VStack(alignment: .leading, spacing: 0) {

                        InitializationStatusView(
                            initializingStatus: initializingStatus,
                            localNetworkType: localNetworkType,
                            showLine: receivingDiscussionsListStatus != nil || receivingDoneStatus != nil)

                        if let receivingDiscussionsListStatus {
                            ReceivingDiscussionsListStatusView(
                                receivingDiscussionsListStatus: receivingDiscussionsListStatus,
                                showLine: negotiatingWhatToReceiveStatus != nil || receivingDoneStatus != nil,
                                transferMethod: .webRTC)
                            .id(ScrollAnchor.receivingDiscussionsList)
                            .onAppear { withAnimation { proxy.scrollTo(ScrollAnchor.receivingDiscussionsList, anchor: .bottom) } }
                        }

                        if let negotiatingWhatToReceiveStatus {
                            NegotiatingWhatToReceiveStatusView(
                                negotiatingWhatToReceiveStatus: negotiatingWhatToReceiveStatus,
                                showLine: receivingMessagesStatus != nil || receivingAttachmentstatus != nil || receivingDoneStatus != nil)
                            .id(ScrollAnchor.negotiatingWhatToReceive)
                            .onAppear { withAnimation { proxy.scrollTo(ScrollAnchor.negotiatingWhatToReceive, anchor: .bottom) } }
                        }

                        if let receivingMessagesStatus {
                            ReceivingMessagesStatusView(
                                receivingMessagesStatus: receivingMessagesStatus,
                                showLine: receivingAttachmentstatus != nil || receivingDoneStatus != nil)
                            .id(ScrollAnchor.receivingMessages)
                            .onAppear { withAnimation { proxy.scrollTo(ScrollAnchor.receivingMessages, anchor: .bottom) } }
                        }

                        if let receivingAttachmentstatus {
                            ReceivingAttachmentsStatusView(
                                receivingAttachmentstatus: receivingAttachmentstatus,
                                showLine: receivingDoneStatus != nil)
                            .id(ScrollAnchor.receivingAttachment)
                            .onAppear { withAnimation { proxy.scrollTo(ScrollAnchor.receivingAttachment, anchor: .bottom) } }
                        }

                        if let receivingDoneStatus {
                            DoneImportView(receivingDoneStatus: receivingDoneStatus)
                                .id(ScrollAnchor.done)
                                .onAppear { withAnimation { proxy.scrollTo(ScrollAnchor.done, anchor: .bottom) } }
                        }

                    }
                }
                .padding()

            }
        }
        .navigationTitle(String(localizedInThisBundle: "IMPORT_STATUS_TITLE"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            VStack {
                OlvidButtonNew(action: buttonTapped, style: .glassOrBorderedProminent) {
                    Text(buttonTitle)
                }
                .confirmationDialog(interruptConfirmationDialogTitle, isPresented: $isInterruptConfirmationDialogPresented, titleVisibility: .visible, actions: {
                    Button(String(localizedInThisBundle: "BUTTON_TITLE_CONTINUE_TRANSFER"), action: {})
                    Button(String(localizedInThisBundle: "BUTTON_TITLE_INTERRUPT_TRANSFER"), role: .destructive, action: userWantsToInterruptImport)
                })
                .confettiCannon(trigger: $triggerConfettiCanon,
                                num: 100,
                                openingAngle: Angle(degrees: 0),
                                closingAngle: Angle(degrees: 360),
                                radius: 200)
            }
            .padding()
        }
        .interactiveDismissDisabled(true)
        .disabled(isInterfaceDisabled)
        .task(onTask)
    }
    
}


// MARK: - Views using ProgressItemRowView

struct ReceivingAttachmentsStatusView: View {
    
    let receivingAttachmentstatus: ReceivingAttachmentstatus
    let showLine: Bool
    
    private var progressItemState: ProgressItemState {
        switch receivingAttachmentstatus {
        case .starting:
            return .inProgress
        case .inProgress(receivedFylesCount: let receivedFylesCount, failedFylesCount: let failedFylesCount, byteCountReceived: _, byteCountFailedToReceive: _, numberOfFylesToReceive: let numberOfFylesToReceive, byteCountToReceive: _, bytesPerSecond: _, eta: _):
            if receivedFylesCount + failedFylesCount >= numberOfFylesToReceive {
                return failedFylesCount > 0 ? .warning : .success
            } else {
                return .inProgress
            }
        }
    }

    private var progress: (value: Double, total: Double)? {
        switch receivingAttachmentstatus {
        case .starting:
            return nil
        case .inProgress(receivedFylesCount: _, failedFylesCount: _, byteCountReceived: let byteCountReceived, byteCountFailedToReceive: _, numberOfFylesToReceive: _, byteCountToReceive: let byteCountToReceive, bytesPerSecond: _, eta: _):
            if byteCountReceived < byteCountToReceive {
                return (Double(min(byteCountReceived, byteCountToReceive)), Double(byteCountToReceive))
            } else {
                return nil
            }
        }
    }

    private var subtitle: String? {
        switch receivingAttachmentstatus {
        case .starting:
            return String(localizedInThisBundle: "STARTING")
        case .inProgress(receivedFylesCount: let receivedFylesCount, failedFylesCount: _, byteCountReceived: _, byteCountFailedToReceive: _, numberOfFylesToReceive: let numberOfFylesToReceive, byteCountToReceive: _, bytesPerSecond: _, eta: _):
            if receivedFylesCount < numberOfFylesToReceive {
                return String(localizedInThisBundle: "RECEIVING_ATTACHMENTS_STATUS_VIEW_RECEIVING_\(numberOfFylesToReceive)_ATTACHMENTS")
            } else {
                return String(localizedInThisBundle: "RECEIVING_ATTACHMENTS_STATUS_VIEW_DID_RECEIVE_\(numberOfFylesToReceive)_ATTACHMENTS")
            }
        }
    }

    private var subtitleForFailedAttachments: String? {
        switch receivingAttachmentstatus {
        case .starting:
            return nil
        case .inProgress(receivedFylesCount: _, failedFylesCount: let failedFylesCount, byteCountReceived: _, byteCountFailedToReceive: _, numberOfFylesToReceive: _, byteCountToReceive: _, bytesPerSecond: _, eta: _):
            guard failedFylesCount > 0 else { return nil }
            return String(localizedInThisBundle: "RECEIVING_ATTACHMENTS_STATUS_VIEW_\(failedFylesCount)_ATTACHMENTS_COULD_NOT_BE_TRANSFERRED")
        }
    }

    private var progressPercentage: String? {
        guard let progress else { return nil }
        let percentage = Int(round(100 * progress.value / progress.total))
        return "\(percentage)%"
    }

    private var eta: TimeInterval? {
        switch receivingAttachmentstatus {
        case .starting:
            return nil
        case .inProgress(receivedFylesCount: _, failedFylesCount: _, byteCountReceived: _, byteCountFailedToReceive: _, numberOfFylesToReceive: _, byteCountToReceive: _, bytesPerSecond: _, eta: let eta):
            return progressItemState == .inProgress ? eta : nil
        }
    }

    private var bytesPerSecond: Double? {
        switch receivingAttachmentstatus {
        case .starting:
            return nil
        case .inProgress(receivedFylesCount: _, failedFylesCount: _, byteCountReceived: _, byteCountFailedToReceive: _, numberOfFylesToReceive: _, byteCountToReceive: _, bytesPerSecond: let bytesPerSecond, eta: _):
            return bytesPerSecond
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
        switch receivingAttachmentstatus {
        case .starting:
            return String(localizedInThisBundle: "RECEIVING_ATTACHMENTS_VIEW_TITLE")
        case .inProgress(let receivedFylesCount, let failedFylesCount, _, _, let numberOfFylesToReceive, _, _, _):
            if receivedFylesCount + failedFylesCount >= numberOfFylesToReceive {
                return String(localizedInThisBundle: "RECEIVING_ATTACHMENTS_VIEW_TITLE_DONE")
            } else {
                return String(localizedInThisBundle: "RECEIVING_ATTACHMENTS_VIEW_TITLE")
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


struct ReceivingMessagesStatusView: View {
    
    let receivingMessagesStatus: ReceivingMessagesStatus
    let showLine: Bool

    @State private var isProgressShown = false

    private var progressItemState: ProgressItemState {
        switch receivingMessagesStatus {
        case .starting:
            return .inProgress
        case .inProgress(receivedMessageCount: let receivedMessageCount, missingMessageCount: let missingMessageCount, numberOfMessagesToReceive: let numberOfMessagesToReceive, messagesPerSecond: _, eta: _):
            return receivedMessageCount + missingMessageCount >= numberOfMessagesToReceive ? .success : .inProgress
        }
    }

    private var progress: (value: Double, total: Double)? {
        switch receivingMessagesStatus {
        case .starting:
            return nil
        case .inProgress(receivedMessageCount: let receivedMessageCount, missingMessageCount: let missingMessageCount, numberOfMessagesToReceive: let numberOfMessagesToReceive, messagesPerSecond: _, eta: _):
            if receivedMessageCount + missingMessageCount < numberOfMessagesToReceive {
                return (Double(min(receivedMessageCount+missingMessageCount, numberOfMessagesToReceive)), Double(numberOfMessagesToReceive))
            } else {
                return nil
            }
        }
    }

    private var subtitle1: String? {
        switch receivingMessagesStatus {
        case .starting:
            return String(localizedInThisBundle: "RECEIVING_MESSAGES_STATUS_VIEW_01_STARTING")
        case .inProgress(receivedMessageCount: let receivedMessageCount, missingMessageCount: let missingMessageCount, numberOfMessagesToReceive: let numberOfMessagesToReceive, messagesPerSecond: _, eta: _):
            if receivedMessageCount + missingMessageCount < numberOfMessagesToReceive {
                return String(localizedInThisBundle: "RECEIVING_MESSAGES_STATUS_VIEW_02_RECEIVING_\(numberOfMessagesToReceive)_MESSAGES")
            } else {
                return String(localizedInThisBundle: "RECEIVING_MESSAGES_STATUS_VIEW_03_DID_RECEIVE_\(receivedMessageCount)_MESSAGES")
            }
        }
    }

    private var subtitle2: String? {
        switch receivingMessagesStatus {
        case .starting:
            return nil
        case .inProgress(receivedMessageCount: let receivedMessageCount, missingMessageCount: let missingMessageCount, numberOfMessagesToReceive: let numberOfMessagesToReceive, messagesPerSecond: _, eta: _):
            if receivedMessageCount + missingMessageCount < numberOfMessagesToReceive {
                return nil
            } else {
                if missingMessageCount > 0 {
                    return String(localizedInThisBundle: "RECEIVING_MESSAGES_STATUS_VIEW_03_\(missingMessageCount)_MESSAGES_COULD_NOT_BE_RECEIVED")
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
        switch receivingMessagesStatus {
        case .starting:
            return nil
        case .inProgress(receivedMessageCount: _, missingMessageCount: _, numberOfMessagesToReceive: _, messagesPerSecond: _, eta: let eta):
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
        switch receivingMessagesStatus {
        case .starting:
            return String(localizedInThisBundle: "RECEIVING_MESSAGES_STATUS_VIEW_TITLE")
        case .inProgress(let receivedMessageCount, let missingMessageCount, let numberOfMessagesToReceive, _, _):
            if receivedMessageCount + missingMessageCount >= numberOfMessagesToReceive {
                return String(localizedInThisBundle: "RECEIVING_MESSAGES_STATUS_VIEW_TITLE_DONE")
            } else {
                return String(localizedInThisBundle: "RECEIVING_MESSAGES_STATUS_VIEW_TITLE")
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


private struct NegotiatingWhatToReceiveStatusView: View {

    let negotiatingWhatToReceiveStatus: NegotiatingWhatToReceiveStatus
    let showLine: Bool

    private var progressItemState: ProgressItemState {
        switch negotiatingWhatToReceiveStatus {
        case .inProgress:
            return .inProgress
        case .done:
            return .success
        }
    }

    private var subtitle: String {
        switch negotiatingWhatToReceiveStatus {
        case .inProgress:
            return String(localizedInThisBundle: "NEGOTIATING_WHAT_TO_SEND_VIEW_01_IN_PROGRESS")
        case .done:
            return String(localizedInThisBundle: "NEGOTIATING_WHAT_TO_RECEIVE_VIEW_02_WILL_TRANSFER_RESULT")
        }
    }

    private var subtitleMessagesToTransfer: String? {
        switch negotiatingWhatToReceiveStatus {
        case .inProgress:
            return nil
        case .done(numberOfMessagesToTransfer: let numberOfMessagesToReceive, numberOfFylesToTransfer: _, totalByteCountToTransfer: _):
            return String(localizedInThisBundle: "NEGOTIATING_WHAT_TO_RECEIVE_VIEW_02_WILL_TRANSFER_\(numberOfMessagesToReceive)_MESSAGES")
        }
    }
    
    private var subTitleAttachmentsToTransfer: String? {
        switch negotiatingWhatToReceiveStatus {
        case .inProgress:
            return nil
        case .done(numberOfMessagesToTransfer: _, numberOfFylesToTransfer: let numberOfFylesToReceive, totalByteCountToTransfer: let byteCountToReceive):
            if byteCountToReceive > 0 {
                return String(localizedInThisBundle: "NEGOTIATING_WHAT_TO_RECEIVE_VIEW_02_WILL_TRANSFER_\(numberOfFylesToReceive)_ATTACHMENTS_FOR_\(byteCountToReceive.formatted(.byteCount(style: .file)))")
            } else {
                return nil
            }
        }
    }

    private var title: String {
        switch negotiatingWhatToReceiveStatus {
        case .inProgress:
            return String(localizedInThisBundle: "NEGOTIATING_WHAT_TO_RECEIVE_VIEW_TITLE")
        case .done:
            return String(localizedInThisBundle: "NEGOTIATING_WHAT_TO_RECEIVE_VIEW_TITLE_DONE")
        }
    }

    var body: some View {
        ProgressItemRowView(state: progressItemState, showLine: showLine, title: title) {
            VStack(alignment: .leading) {
                Text(subtitle)
                if let subtitleMessagesToTransfer {
                    Label(title: { Text(subtitleMessagesToTransfer) }, icon: { Image(systemIcon: .circleFill) })
                        .labelStyle(BulletLabelStyle())
                }
                if let subTitleAttachmentsToTransfer {
                    Label(title: { Text(subTitleAttachmentsToTransfer) }, icon: { Image(systemIcon: .circleFill) })
                        .labelStyle(BulletLabelStyle())
                }
            }
        }
    }
    
}


/// First progress item view.
private struct InitializationStatusView: View {

    let initializingStatus: InitializingStatusOnDestinationDevice
    let localNetworkType: LocalNetworkImportView.LocalNetworkType
    let showLine: Bool
    
    private var subtitle: LocalizedStringKey {
        switch initializingStatus {
        case .inProgress:
            return "INIT_STATUS_VIEW_01_IN_PROGRESS"
        case .connectingToSourceDeviceOrUnzippingFile(progress: _):
            switch localNetworkType {
            case .webRTC:
                return "INIT_STATUS_VIEW_02_CONNECTING_TO_SOURCE_DEVICE"
            case .wifiAware(ownedCryptoId: _, pairedDevice: let pairedDevice):
                let pairedDeviceName = pairedDevice.pairingInfo?.pairingName ?? pairedDevice.pairingInfo?.modelName
                if let pairedDeviceName {
                    return "INIT_STATUS_VIEW_02_CONNECTING_TO_SOURCE_DEVICE_WIFI_AWARE_\(pairedDeviceName)"
                } else {
                    return "INIT_STATUS_VIEW_02_CONNECTING_TO_SOURCE_DEVICE_WIFI_AWARE"
                }
            }
        case .connectedToSourceDeviceOrFileUnzipped:
            return "INIT_STATUS_VIEW_03_CONNECTED_TO_SOURCE_DEVICE"
        }
    }
    
    private var progressItemState: ProgressItemState {
        switch initializingStatus {
        case .inProgress, .connectingToSourceDeviceOrUnzippingFile(progress: _):
            return .inProgress
        case .connectedToSourceDeviceOrFileUnzipped:
            return .success
        }
    }
    
    private var title: String {
        switch initializingStatus {
        case .inProgress, .connectingToSourceDeviceOrUnzippingFile:
            return String(localizedInThisBundle: "INIT_STATUS_VIEW_TITLE_INITIALIZING_LOCAL_NETWORK")
        case .connectedToSourceDeviceOrFileUnzipped:
            return String(localizedInThisBundle: "INIT_STATUS_VIEW_TITLE_INITIALIZED_LOCAL_NETWORK")
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

private actor MockTransferServiceForNetworkImportView {
    
}


extension MockTransferServiceForNetworkImportView: TransferServiceForLocalNetworkImportView {
    
    func viewRequiresAsyncStreamOfTransferImportState(_ view: LocalNetworkImportView) async -> AsyncStream<TransferImportState> {
        let stream = AsyncStream<TransferImportState> { (continuation: AsyncStream<TransferImportState>.Continuation) in
            continuation.yield(.initializing(.inProgress))
            Task {
                do {
                    
                    try await Task.sleep(for: .seconds(1))
                    
                    continuation.yield(.initializing(.connectingToSourceDeviceOrUnzippingFile(progress: 0.0)))
                    
                    try await Task.sleep(for: .seconds(1))
                    
                    continuation.yield(.initializing(.connectedToSourceDeviceOrFileUnzipped))
                    
                    try await Task.sleep(for: .seconds(1))
                    
                    continuation.yield(.destinationTransferStepsState(.receivingDiscussionsList(status: .inProgress)))
                    
                    try await Task.sleep(for: .seconds(1))
                    let numberOfDiscussionsAvailableOnSource = 123
                    let numberOfFylesAvailableOnSource = 42
                    let totalByteCountAvailableOnSource: UInt64 = 10_000
                    continuation.yield(.destinationTransferStepsState(
                        .receivingDiscussionsList(
                            status: .done(
                                numberOfDiscussionsAvailableOnSource: numberOfDiscussionsAvailableOnSource,
                                numberOfFylesAvailableOnSource: numberOfFylesAvailableOnSource,
                                totalByteCountAvailableOnSource: totalByteCountAvailableOnSource
                            )
                        )
                    ))
                    
                    try await Task.sleep(for: .seconds(1))
                    
                    continuation.yield(.destinationTransferStepsState(.negotiatingWhatToReceive(status: .inProgress)))
                    
                    try await Task.sleep(for: .seconds(1))
                    
                    let numberOfMessagesToTransfer = 100
                    let numberOfFylesToTransfer = 21
                    let totalByteCountToTransfer = UInt64(5_000)
                    continuation.yield(.destinationTransferStepsState(
                        .negotiatingWhatToReceive(
                            status: .done(
                                numberOfMessagesToTransfer: numberOfMessagesToTransfer,
                                numberOfFylesToTransfer: numberOfFylesToTransfer,
                                totalByteCountToTransfer: totalByteCountToTransfer
                            )
                        )
                    ))
                    
                    try await Task.sleep(for: .seconds(1))

                    // Simulate receiving messages

                    continuation.yield(.destinationTransferStepsState(.receivingMessages(status: .starting)))

                    try await Task.sleep(for: .seconds(1))
                    
                    var receivedMessageCount = 0
                    let messagesPerSecondToSimulate = 10.0
                    let sleepInterval: TimeInterval = 0.5
                    let messagesToReceiveAfterEachSleep = Int(messagesPerSecondToSimulate / sleepInterval)

                    while receivedMessageCount < numberOfMessagesToTransfer {
                        try await Task.sleep(for: sleepInterval)
                        receivedMessageCount = min(receivedMessageCount + messagesToReceiveAfterEachSleep, numberOfMessagesToTransfer)
                        let eta: TimeInterval? = Double(numberOfMessagesToTransfer - receivedMessageCount) / messagesPerSecondToSimulate
                        continuation.yield(.destinationTransferStepsState(.receivingMessages(
                            status: .inProgress(
                                receivedMessageCount: receivedMessageCount,
                                missingMessageCount: 0,
                                numberOfMessagesToReceive: numberOfMessagesToTransfer,
                                messagesPerSecond: messagesPerSecondToSimulate,
                                eta: eta
                            )
                        )))
                    }
                    
                    try await Task.sleep(for: .seconds(1))

                    // Simulate receiving attachments
                    
                    continuation.yield(.destinationTransferStepsState(.receivingAttachment(status: .starting)))

                    try await Task.sleep(for: .seconds(1))

                    var receivedFylesCount = 0
                    var byteCountReceived: UInt64 = 0
                    let progressPerSecondToSimulate: Double = 0.1
                    let sleepIntervalForAttachments: TimeInterval = 0.5
                    let progressPerSleepInterval: Double = progressPerSecondToSimulate * sleepIntervalForAttachments
                    let bytesPerSecondToSimulate = Double(totalByteCountToTransfer) * progressPerSecondToSimulate

                    while receivedFylesCount < numberOfFylesToTransfer {
                        try await Task.sleep(for: sleepIntervalForAttachments)
                        byteCountReceived = min(totalByteCountToTransfer, byteCountReceived + UInt64((progressPerSleepInterval * Double(totalByteCountToTransfer))))
                        receivedFylesCount = Int(Double(numberOfFylesToTransfer) * Double(byteCountReceived) / Double(totalByteCountToTransfer))
                        let bytesRemaining = totalByteCountToTransfer - byteCountReceived
                        let eta: TimeInterval? = bytesPerSecondToSimulate > 0 ? Double(bytesRemaining) / bytesPerSecondToSimulate : nil
                        continuation.yield(.destinationTransferStepsState(.receivingAttachment(
                            status: .inProgress(
                                receivedFylesCount: receivedFylesCount,
                                failedFylesCount: 0,
                                byteCountReceived: byteCountReceived,
                                byteCountFailedToReceive: 0,
                                numberOfFylesToReceive: numberOfFylesToTransfer,
                                byteCountToReceive: totalByteCountToTransfer,
                                bytesPerSecond: bytesPerSecondToSimulate,
                                eta: eta
                            )
                        )))
                    }
                    
                    continuation.yield(.destinationTransferStepsState(.done(status: .exportWasSuccessful(failedFylesCount: 0))))

                    continuation.finish()
                    
                } catch {
                    assertionFailure()
                }
            }
        }
        return stream
    }
    
    func userWantsToCancelImport(_ view: LocalNetworkImportView, localNetworkType: LocalNetworkImportView.LocalNetworkType) async {
        print("User cancelled import")
    }
 
    func userWantsToAcceptHistoryTransfer(_ view: LocalNetworkImportView, localNetorkType: LocalNetworkImportView.LocalNetworkType) async throws {
        print("User wants to accept history transfer")
    }

    func userWantsToCancelHistoryTransfer(_ view: LocalNetworkImportView, localNetorkType: LocalNetworkImportView.LocalNetworkType) async throws {
        print("User wants to cancel history transfer")
    }

    func onDisappear(of view: LocalNetworkImportView) async {
        print("On disappear")
    }
    
}

@MainActor
private final class ActionsForPreviews {
    let mockTransferService = MockTransferServiceForNetworkImportView()
}


extension ActionsForPreviews: LocalNetworkImportViewActions {
    func userWantsToDismissView(_ view: LocalNetworkImportView) {}
    
    func userRequiresMessageHistoryTransferService(_ view: LocalNetworkImportView) async throws -> any TransferServiceForLocalNetworkImportView {
        return self.mockTransferService
    }
}


private let actionsForPreviews = ActionsForPreviews()

#Preview("WebRTC - With device name") {
    LocalNetworkImportView(
        localNetworkType: .webRTC(sourceDeviceIdentifier: .sampleDatas[0],
                                 sourceDeviceName: "iPhone de Romain",
                                 transferIdFromSource: "preview-transfer-id"),
        actions: actionsForPreviews
    )
}

#Preview("WebRTC - Without device name") {
    LocalNetworkImportView(
        localNetworkType: .webRTC(sourceDeviceIdentifier: .sampleDatas[0],
                                 sourceDeviceName: nil,
                                 transferIdFromSource: "preview-transfer-id"),
        actions: actionsForPreviews
    )
}


@MainActor
private final class InternalActionsForPreviews {}

extension InternalActionsForPreviews: AcceptingOrRejectingTransferRequestFromSourceViewInternalActions {
    
    func userWantsToAcceptHistoryTransferRequest(_ view: AcceptingOrRejectingTransferRequestFromSourceView) async throws {
        print("User wants to accept history transfer request")
    }
    
    func userWantsToRejectHistoryTransferRequest(_ view: AcceptingOrRejectingTransferRequestFromSourceView) async throws {
        print("User wants to reject history transfer request")
    }

}

@MainActor
private let internalActionsForPreviews = InternalActionsForPreviews()

#Preview {
    NavigationStack {
        Group {
            AcceptingOrRejectingTransferRequestFromSourceView(
                sourceDeviceName: "iPhone de Romain",
                internalActions: internalActionsForPreviews)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

}

#endif
