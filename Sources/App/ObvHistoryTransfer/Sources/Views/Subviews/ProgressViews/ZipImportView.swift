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
import UniformTypeIdentifiers
import ObvTypes
import ObvDesignSystem
import ZipArchive
import ObvContinuedProcessingTaskManager
import ConfettiSwiftUI


@MainActor
public protocol ZipImportViewActions {
    func userRequiresMessageHistoryTransferService(_ view: ZipImportView) async throws -> any TransferServiceForZipImportView
    func userWantsToDismissView(_ view: ZipImportView)
}


public protocol TransferServiceForZipImportView: Sendable {
    func initiateHistoryTransfer(_ view: ZipImportView, ownedCryptoId: ObvCryptoId, zipFileURL: URL, password: String?) async throws
    func viewRequiresAsyncStreamOfTransferImportState(_ view: ZipImportView) async throws -> AsyncStream<TransferImportState>
    func onDisappear(of view: ZipImportView) async
}

/// View shown on the destination device, during a Zip import, to show the export progress.
public struct ZipImportView: View {
    
    let ownedCryptoId: ObvCryptoId
    let temporaryDirectory: URL
    let actions: any ZipImportViewActions

    private let title = String(localizedInThisBundle: "IMPORT_ZIP_TITLE")

    @State private var isPickerButtonShown: Bool = true
    @State private var transferService: (any TransferServiceForZipImportView)?
    @State private var triggerConfettiCanon = false
    
    private func requestTransferServiceIfRequired() async throws -> any TransferServiceForZipImportView {
        if let transferService { return transferService }
        let newTransferService = try await actions.userRequiresMessageHistoryTransferService(self)
        self.transferService = newTransferService
        return newTransferService
    }
    
    private func onDisappear() {
        Task {
            guard let transferService = try? await requestTransferServiceIfRequired() else { return }
            await transferService.onDisappear(of: self)
        }
    }

    public var body: some View {
        ScrollView {
            VStack {
                ObvCardView {
                    VStack {
                        Image(systemIcon: .zipperPage)
                            .font(.system(size: 72))
                            .foregroundStyle(.orange)
                        
                        HistoryTransferSectionTitle(title: title)
                            .padding(.bottom, 4)
                        
                        Text("IMPORT_ZIP_EXPLANATION")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 4)

                        if isPickerButtonShown {
                            ZipFilePickerView(temporaryDirectory: temporaryDirectory, actions: self)
                        } else {
                            ZipImportInProgressInternalView(actions: self, triggerConfettiCanon: $triggerConfettiCanon)
                        }
                        
                    } // VStack
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
                
                Spacer(minLength: 0)

            }
        }
        .background(Color(.secondarySystemBackground).ignoresSafeArea())
        .overlayPreferenceValue(ConfettiCannonAnchorKey.self) { anchor in
            if let anchor {
                GeometryReader { geo in
                    Color.clear
                        .frame(width: 1, height: 1)
                        .confettiCannon(trigger: $triggerConfettiCanon,
                                        num: 100,
                                        openingAngle: Angle(degrees: 0),
                                        closingAngle: Angle(degrees: 360),
                                        radius: 200)
                        .position(geo[anchor])
                }
            }
        }
        .onDisappear(perform: onDisappear)
    }
    
}


extension ZipImportView: ZipFilePickerViewActions {
    
    func userChoseZipFileAndEnteredValidPassword(zipFileURL: URL, password: String?) {
        withAnimation { isPickerButtonShown = false }
        Task {
            do {
                let transferService = try await requestTransferServiceIfRequired()
                try await transferService.initiateHistoryTransfer(
                    self,
                    ownedCryptoId: ownedCryptoId,
                    zipFileURL: zipFileURL,
                    password: password
                )
            } catch {
                assertionFailure()
            }
        }
    }
    
}


extension ZipImportView: ZipImportInProgressInternalViewActions {
    
    fileprivate func viewRequiresAsyncStreamOfTransferImportState(_ view: ZipImportInProgressInternalView) async throws -> AsyncStream<TransferImportState> {
        let transferService = try await requestTransferServiceIfRequired()
        return try await transferService.viewRequiresAsyncStreamOfTransferImportState(self)
    }

    fileprivate func userWantsToDismissView(_ view: ZipImportInProgressInternalView) {
        actions.userWantsToDismissView(self)
    }
    
}


extension ZipImportView {
    
    enum ObvError: Error {
        case transferServiceIsNil
    }
    
}


// MARK: - ZipFilePickerView

@MainActor
private protocol ZipFilePickerViewActions {
    /// Called when the user has successfully picked a zip archive and, if it was password-protected, entered the correct password.
    ///
    /// - Parameters:
    ///   - zipFileURL: URL of the archive inside the app's temporary directory (already copied from the security-scoped picker URL).
    ///   - password: The validated password, or `nil` if the archive was not password-protected.
    func userChoseZipFileAndEnteredValidPassword(zipFileURL: URL, password: String?)
}


/// Shows a button that lets the user pick a zip archive from the Files app.
///
/// After the user selects a file, the view:
/// 1. Copies the archive into `temporaryDirectory` (the picker URL is security-scoped and must not be stored).
/// 2. If the archive is password-protected, presents a SwiftUI alert with a `SecureField`. The alert loops until
///    the user enters the correct password or taps Cancel.
/// 3. On success, calls `actions.userChoseZipFileAndEnteredValidPassword(zipFileURL:password:)`.
/// 4. On cancellation at any step, deletes the copied file and re-enables the button.
private struct ZipFilePickerView: View {

    let temporaryDirectory: URL
    let actions: any ZipFilePickerViewActions

    @State private var isFileImporterPresented = false
    @State private var isDisabled: Bool = false
    @State private var pendingZipFileURL: URL?      // set after copying from picker; cleared once handed off or cancelled
    @State private var passwordInput: String = ""
    @State private var isWrongPassword: Bool = false // true after a failed password attempt; drives the alert title/message
    @State private var isPasswordAlertPresented: Bool = false

    // Copies the security-scoped picker URL into the app's temporary directory so we own the file.
    private func copyZipFileToInternalStorage(zipFileURLFromPicker: URL) async throws -> URL {
        if !FileManager.default.fileExists(atPath: temporaryDirectory.path) {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        }
        let directory = temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        CFURLStartAccessingSecurityScopedResource(zipFileURLFromPicker as CFURL)
        defer { CFURLStopAccessingSecurityScopedResource(zipFileURLFromPicker as CFURL) }
        let filename = zipFileURLFromPicker.lastPathComponent
        let zipFileURLInTemporaryDirectory = directory.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: zipFileURLFromPicker, to: zipFileURLInTemporaryDirectory)
        return zipFileURLInTemporaryDirectory
    }

    private func onFileImporterSuccess(urls: [URL]) {
        withAnimation { isDisabled = true }
        Task {
            do {
                guard let zipFileURLFromPicker = urls.first else { return }
                let zipFileURL = try await copyZipFileToInternalStorage(zipFileURLFromPicker: zipFileURLFromPicker)
                if SSZipArchive.isFilePasswordProtected(atPath: zipFileURL.path) {
                    // Archive is encrypted — ask the user for the password before proceeding.
                    pendingZipFileURL = zipFileURL
                    isPasswordAlertPresented = true
                } else {
                    actions.userChoseZipFileAndEnteredValidPassword(zipFileURL: zipFileURL, password: nil)
                }
            } catch {
                withAnimation { isDisabled = false }
                assertionFailure()
            }
        }
    }

    private func onPasswordAlertOKTapped() {
        guard let zipFileURL = pendingZipFileURL else { return }
        var error: NSError?
        if SSZipArchive.isPasswordValidForArchive(atPath: zipFileURL.path, password: passwordInput, error: &error) {
            // Password is correct — hand off and reset state.
            let password = passwordInput
            pendingZipFileURL = nil
            isWrongPassword = false
            passwordInput = ""
            actions.userChoseZipFileAndEnteredValidPassword(zipFileURL: zipFileURL, password: password)
        } else {
            // Wrong password — clear input and re-show the alert on the next run loop tick.
            // (SwiftUI sets isPresented to false when any button is tapped, so we must re-queue.)
            isWrongPassword = true
            passwordInput = ""
            Task { @MainActor in isPasswordAlertPresented = true }
        }
    }

    private func onPasswordAlertCancelTapped() {
        // User gave up — delete the copied zip file and re-enable the picker button.
        if let zipFileURL = pendingZipFileURL {
            try? FileManager.default.removeItem(at: zipFileURL)
        }
        pendingZipFileURL = nil
        isWrongPassword = false
        passwordInput = ""
        withAnimation { isDisabled = false }
    }

    var body: some View {
        OlvidButtonNew(action: { isFileImporterPresented = true }) {
            HStack {
                if isDisabled { ProgressView() }
                Label { Text("PICK_ZIP_FILE_BUTTON_TITLE") } icon: { Image(systemIcon: .folder) }
            }
        }
        .disabled(isDisabled)
        #if DEBUG
        .onChange(of: isFileImporterPresented, perform: { newValue in
            guard newValue, ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" else { return }
            isFileImporterPresented = false
            let zipFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("debug.zip", conformingTo: .zip)
            actions.userChoseZipFileAndEnteredValidPassword(zipFileURL: zipFileURL, password: nil)
        })
        #endif
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                onFileImporterSuccess(urls: urls)
            case .failure:
                break
            }
        }
        .alert(
            String(localizedInThisBundle: isWrongPassword ? "ZIP_PASSWORD_ALERT_WRONG_PASSWORD_TITLE" : "ZIP_PASSWORD_ALERT_TITLE"),
            isPresented: $isPasswordAlertPresented
        ) {
            SecureField(String(localizedInThisBundle: "ZIP_PASSWORD_ALERT_PLACEHOLDER"), text: $passwordInput)
            Button(String(localizedInThisBundle: "OK")) { onPasswordAlertOKTapped() }
            Button(String(localizedInThisBundle: "CANCEL"), role: .cancel) { onPasswordAlertCancelTapped() }
        } message: {
            Text(isWrongPassword ? "ZIP_PASSWORD_ALERT_WRONG_PASSWORD_MESSAGE" : "ZIP_PASSWORD_ALERT_MESSAGE")
        }
    }

}


// MARK: - ZipImportInProgressInternalView

@MainActor
private protocol ZipImportInProgressInternalViewActions {
    func viewRequiresAsyncStreamOfTransferImportState(_ view: ZipImportInProgressInternalView) async throws -> AsyncStream<TransferImportState>
    func userWantsToDismissView(_ view: ZipImportInProgressInternalView)
}

private struct ZipImportInProgressInternalView: View {
    
    let actions: any ZipImportInProgressInternalViewActions
    
    @State private var initializingStatus: InitializingStatusOnDestinationDevice = .inProgress
    @State private var receivingDiscussionsListStatus: ReceivingDiscussionsListStatus?
    @State private var negotiatingWhatToReceiveStatus: NegotiatingWhatToReceiveStatus?
    @State private var receivingMessagesStatus: ReceivingMessagesStatus?
    @State private var receivingAttachmentstatus: ReceivingAttachmentstatus?
    @State private var receivingDoneStatus: ReceivingDoneStatus?

    @State private var bgProgressUnzip: Int64 = 0 // Between 0.0 and 50
    @State private var bgProgressFiles: Int64 = 0 // Between 0.0 and 50
    
    private func onTask() async {
        ObvContinuedProcessingTaskManager.run(taskKind: .historyTransfer) { bgContinuedProcessingTask in
            
            bgContinuedProcessingTask?.expirationHandler = {
                self.dismissButtonTapped()
            }

            do {
                let stream = try await actions.viewRequiresAsyncStreamOfTransferImportState(self)
                for await newState in stream {
                    withAnimation {
                        switch newState {
                            
                        case .initializing(let initializingStatusOnDestinationDevice):
                            
                            self.initializingStatus = initializingStatusOnDestinationDevice
                            
                            if let bgContinuedProcessingTask {
                                switch initializingStatusOnDestinationDevice {
                                case .inProgress:
                                    break
                                case .connectingToSourceDeviceOrUnzippingFile(progress: let progress):
                                    // Half of the progress is dedicated to the initialization (where the unzipping occurs)
                                    let initialisationProgress = progress * 0.5
                                    self.bgProgressUnzip = Int64(initialisationProgress * 100)
                                case .connectedToSourceDeviceOrFileUnzipped:
                                    bgProgressUnzip = 50
                                }
                                bgContinuedProcessingTask.progress.totalUnitCount = 100
                                bgContinuedProcessingTask.progress.completedUnitCount = bgProgressUnzip + bgProgressFiles
                            }
                            
                        case .destinationTransferStepsState(let destinationTransferStepsState):
                            
                            switch destinationTransferStepsState {
                            case .receivingDiscussionsList(status: let status):
                                receivingDiscussionsListStatus = status
                            case .negotiatingWhatToReceive(status: let status):
                                negotiatingWhatToReceiveStatus = status
                            case .receivingMessages(status: let status):
                                receivingMessagesStatus = status
                            case .receivingAttachment(status: let status):
                                
                                receivingAttachmentstatus = status
                                
                                if let bgContinuedProcessingTask, let filesProgress = status.progress {
                                    // Half of the progress is dedicated to files progress
                                    self.bgProgressFiles = Int64(filesProgress * 50)
                                    bgContinuedProcessingTask.progress.totalUnitCount = 100
                                    bgContinuedProcessingTask.progress.completedUnitCount = bgProgressUnzip + bgProgressFiles
                                }

                            case .done(status: let status):
                                receivingDoneStatus = status
                                switch status {
                                case .exportWasSuccessful(let failedFylesCount):
                                    if failedFylesCount == 0 {
                                        Task {
                                            try await Task.sleep(seconds: 0.3)
                                            triggerConfettiCanon = true
                                        }
                                    }
                                case .exportWasCancelledByUser, .exportFailed, .exportFailedAsIdentitiesDidNotMatch:
                                    break
                                }
                            }
                            
                        case .canceling:
                            break
                        }
                    }
                }
            } catch {
                assertionFailure()
            }
        }
    }
    
    private func dismissButtonTapped() {
        actions.userWantsToDismissView(self)
    }
    
    @State private var isInterruptConfirmationDialogPresented = false

    /// Called when the user taps the back button.
    private func backButtonTapped() {
        switch receivingDoneStatus {
        case .exportWasSuccessful, .exportWasCancelledByUser, .exportFailed, .exportFailedAsIdentitiesDidNotMatch:
            actions.userWantsToDismissView(self)
        case nil:
            isInterruptConfirmationDialogPresented = true
        }
    }
    
    private func userConfirmedToInterrupt() {
        actions.userWantsToDismissView(self)
    }
    
    private let interruptConfirmationDialogTitle = String(localizedInThisBundle: "INTERRUPT_ZIP_IMPORT_CONFIRMATION_TITLE")
    private let interruptConfirmationButtonTitle = String(localizedInThisBundle: "INTERRUPT_ZIP_IMPORT_CONFIRMATION_BUTTON_TITLE")
    private let stayHereButtonTitle = String(localizedInThisBundle: "DO_NO_INTERRUPT_ZIP_IMPORT_BUTTON_TITLE")

    @Binding var triggerConfettiCanon: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            Divider()
                .padding(.bottom)
            
            ZipInitializingStatusRowView(
                initializingStatus: initializingStatus,
                showLine: receivingDoneStatus != nil)
            
            if let receivingDiscussionsListStatus {
                ReceivingDiscussionsListStatusView(
                    receivingDiscussionsListStatus: receivingDiscussionsListStatus,
                    showLine: negotiatingWhatToReceiveStatus != nil || receivingDoneStatus != nil,
                    transferMethod: .zip)
            }

            if let receivingMessagesStatus {
                ReceivingMessagesStatusView(
                    receivingMessagesStatus: receivingMessagesStatus,
                    showLine: receivingAttachmentstatus != nil || receivingDoneStatus != nil)
            }

            if let receivingAttachmentstatus {
                ReceivingAttachmentsStatusView(
                    receivingAttachmentstatus: receivingAttachmentstatus,
                    showLine: receivingDoneStatus != nil)
            }

            if let receivingDoneStatus {
                DoneImportView(receivingDoneStatus: receivingDoneStatus)
                    .padding(.bottom)
                OlvidButtonNew(action: dismissButtonTapped) {
                    Text("DISMISS")
                }
                .anchorPreference(key: ConfettiCannonAnchorKey.self, value: .center) { $0 }
            }


        }
        .task(onTask)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                // We replace the standard back button by a button that looks exactly the same
                // but allows to display a confirmation request.
                Button(action: backButtonTapped) {
                    Image(systemIcon: .chevronLeft)
                        .fontWeight(.semibold)
                }
                .confirmationDialog(interruptConfirmationDialogTitle, isPresented: $isInterruptConfirmationDialogPresented, titleVisibility: .visible) {
                    Button(interruptConfirmationButtonTitle, role: .destructive, action: userConfirmedToInterrupt)
                    Button(stayHereButtonTitle, role: .cancel, action: {})
                }
            }
        }
    }
    
}


/// First progress item view.
private struct ZipInitializingStatusRowView: View {

    let initializingStatus: InitializingStatusOnDestinationDevice
    let showLine: Bool
       
    private var subtitle: String {
        switch initializingStatus {
        case .inProgress:
            return String(localizedInThisBundle: "ZIP_IMPORT_INIT_STATUS_VIEW_01_IN_PROGRESS")
        case .connectingToSourceDeviceOrUnzippingFile(progress: _):
            return String(localizedInThisBundle: "ZIP_IMPORT_INIT_STATUS_VIEW_02_UNZIPPING_FILE")
        case .connectedToSourceDeviceOrFileUnzipped:
            return String(localizedInThisBundle: "ZIP_IMPORT_INIT_STATUS_VIEW_03_ZIP_FILE_UNZIPPED")
        }
    }
    
    private var progressItemState: ProgressItemState {
        switch initializingStatus {
        case .inProgress:
            return .inProgress
        case .connectingToSourceDeviceOrUnzippingFile:
            return .inProgress
        case .connectedToSourceDeviceOrFileUnzipped:
            return .success
        }
    }
    
    private var progress: Double? {
        switch initializingStatus {
        case .inProgress:
            return nil
        case .connectingToSourceDeviceOrUnzippingFile(progress: let progress):
            return progress
        case .connectedToSourceDeviceOrFileUnzipped:
            return nil
        }
    }
    
    private var progressPercentage: String? {
        guard let progress else { return nil }
        return "\(Int(progress*100))%"
    }
    
    private var title: String {
        switch initializingStatus {
        case .inProgress, .connectingToSourceDeviceOrUnzippingFile:
            return String(localizedInThisBundle: "INIT_STATUS_VIEW_TITLE_INITIALIZING_ZIP_IMPORT")
        case .connectedToSourceDeviceOrFileUnzipped:
            return String(localizedInThisBundle: "INIT_STATUS_VIEW_TITLE_INITIALIZED_ZIP_IMPORT")
        }
    }

    var body: some View {
        ProgressItemRowView(state: progressItemState, showLine: showLine, title: title) {
            Text(subtitle)
            if let progress {
                ProgressView(value: progress, total: 1.0)
                ProgressAndETATextsView(etaString: nil, progressPercentage: progressPercentage)
            }
        }
    }

}


// MARK: - Preference key for confetti cannon anchor

private struct ConfettiCannonAnchorKey: PreferenceKey {
    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = nextValue() ?? value
    }
}


#if DEBUG

@MainActor
private final class ActionsForPreviews {}

extension ActionsForPreviews: ZipImportViewActions {
    
    func userRequiresMessageHistoryTransferService(_ view: ZipImportView) async throws -> any TransferServiceForZipImportView {
        return self
    }
    
    func userWantsToDismissView(_ view: ZipImportView) {
        print("User wants to dismiss view")
    }
    
}

extension ActionsForPreviews: TransferServiceForZipImportView {
        
    func initiateHistoryTransfer(_ view: ZipImportView, ownedCryptoId: ObvTypes.ObvCryptoId, zipFileURL: URL, password: String?) async throws {
        // The zip file URL is the one obtained from the picker. It's a fake URL in our case, so we don't do anything.
    }
    
    
    func viewRequiresAsyncStreamOfTransferImportState(_ view: ZipImportView) async -> AsyncStream<TransferImportState> {
        let stream = AsyncStream<TransferImportState> { (continuation: AsyncStream<TransferImportState>.Continuation) in
            Task {
                try await Task.sleep(seconds: 1)
                continuation.yield(.initializing(.connectingToSourceDeviceOrUnzippingFile(progress: 0.0)))
                try await Task.sleep(seconds: 1)
                continuation.yield(.initializing(.connectingToSourceDeviceOrUnzippingFile(progress: 0.5)))
                try await Task.sleep(seconds: 1)
                continuation.yield(.initializing(.connectedToSourceDeviceOrFileUnzipped))
                
                try await Task.sleep(seconds: 1)
                continuation.yield(.destinationTransferStepsState(.done(status: .exportWasSuccessful(failedFylesCount: 0))))
                
            }
        }
        return stream
    }
    
    
    func onDisappear(of view: ZipImportView) async {
        print("ZipImportView did disappear")
    }

}

@MainActor
private let actionsForPreviews = ActionsForPreviews()

#Preview {
    ZipImportView(
        ownedCryptoId: .sampleDatasForOwnedCryptoId[0],
        temporaryDirectory: FileManager.default.temporaryDirectory,
        actions: actionsForPreviews
    )
}

#endif
