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
import ObvCrypto
import ConfettiSwiftUI
import ObvContinuedProcessingTaskManager

@MainActor
public protocol ZipExportViewDataSource: ComputingExportZipFileSizeViewDataSource {}

@MainActor
public protocol ZipExportViewActions {
    func userRequiresMessageHistoryTransferService(_ view: ZipExportView) async throws -> any TransferServiceForZipExportView
}

public protocol TransferServiceForZipExportView: Sendable {
    func initiateHistoryTransfer(_ view: ZipExportView, transferTransportType: TransferTransportType, scope: TransferScope) async throws
    func viewRequiresAsyncStreamOfTransferExportState(_ view: ZipExportView) async -> AsyncStream<TransferExportState>
    func onDisappear(of view: ZipExportView) async
}

@MainActor
public protocol ZipExportViewInternalActions {
    func userWantsToPopView(_ view: ZipExportView)
}

/// View shown on the source device, during a Zip export, to show the export progress.
public struct ZipExportView: View {
    
    let ownedCryptoId: ObvCryptoId
    let scope: TransferScope
    let dataSource: any ZipExportViewDataSource
    let internalActions: any ZipExportViewInternalActions
    let actions: any ZipExportViewActions

    private enum InternalState {
        case computingExportFileSize
        case computingZipAsUserConfirmed
        case userCancelled
    }
    
    @State private var internalState: InternalState = .computingExportFileSize
    @State private var transferService: (any TransferServiceForZipExportView)?

    private let title = String(localizedInThisBundle: "COMPUTING_ZIP_SIZE_TITLE")
    private let explanation = String(localizedInThisBundle: "COMPUTING_ZIP_SIZE_EXPLANATION")
    
    private func onTask() async {
        do {
            self.transferService = try await actions.userRequiresMessageHistoryTransferService(self)
        } catch {
            assertionFailure()
        }
    }

    private func onDisappear() {
        guard let transferService = self.transferService else { return }
        Task {
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
                        
                        Text(explanation)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        
                        ComputingExportZipFileSizeView(
                            ownedCryptoId: ownedCryptoId,
                            scope: scope,
                            dataSource: dataSource,
                            internalActions: self
                        )
                        .padding(.bottom)
                        
                        switch internalState {
                        case .computingExportFileSize:
                            EmptyView()
                        case .computingZipAsUserConfirmed:
                            ComputingZipView(actions: self)
                        case .userCancelled:
                            EmptyView()
                        }
                    } // VStack
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
                
                Spacer(minLength: 0)

            }
        }
        .background(Color(.secondarySystemBackground).ignoresSafeArea())
        .task(onTask)
        .onDisappear(perform: onDisappear)
    }
}


extension ZipExportView {
    
    enum ObvError: Error {
        case transferServiceIsNil
    }
    
}


extension ZipExportView: ComputingZipViewActions {
        
    fileprivate func viewRequiresAsyncStreamOfTransferExportState(_ view: ComputingZipView) async throws -> AsyncStream<TransferExportState> {
        guard let transferService else { assertionFailure(); throw ObvError.transferServiceIsNil }
        return await transferService.viewRequiresAsyncStreamOfTransferExportState(self)
    }
    
    fileprivate func userWantsToPopView(_view: ComputingZipView) {
        internalActions.userWantsToPopView(self)
    }
    
    fileprivate func userWantsToCancelExportFromBackground(_ view: ComputingZipView) async {
        internalActions.userWantsToPopView(self)
    }

}


extension ZipExportView: ComputingExportZipFileSizeViewInternalActions {

    func launchZipping(_ view: ComputingExportZipFileSizeView, password: String?) async throws {
        guard let transferService else { assertionFailure(); throw ObvError.transferServiceIsNil }
        withAnimation { internalState = .computingZipAsUserConfirmed }
        try await transferService.initiateHistoryTransfer(
            self,
            transferTransportType: .zipFile(ownedCryptoId: self.ownedCryptoId, password: password),
            scope: self.scope)
    }

}


// MARK: - ComputingExportZipFileSizeView

@MainActor
public protocol ComputingExportZipFileSizeViewDataSource {
    /// Provides the data needed to evaluate what will be included in the ZIP export before the user confirms.
    func evaluateZipFileContentToExpect(_ view: ComputingExportZipFileSizeView, ownedCryptoId: ObvTypes.ObvCryptoId, scope: TransferScope) async throws -> ComputingExportZipFileSizeView.ZipFileContentToExpect
}

@MainActor
private protocol ComputingExportZipFileSizeViewInternalActions {
    func launchZipping(_ view: ComputingExportZipFileSizeView, password: String?) async throws
}

/// First step of the ZIP export flow.
///
/// Shown while the app asynchronously computes what the ZIP will contain. Once the result is
/// available, the `ProgressView` spinner is replaced by a summary of the export content
/// (message count, file count, total size) and one action button appears at the bottom:
/// - "Create ZIP file" — triggers the actual zipping
public struct ComputingExportZipFileSizeView: View {

    let ownedCryptoId: ObvCryptoId
    let scope: TransferScope
    let dataSource: any ComputingExportZipFileSizeViewDataSource
    fileprivate let internalActions: any ComputingExportZipFileSizeViewInternalActions

    /// Set once `onTask` completes. Drives the transition from spinner to summary + buttons.
    @State private var zipFileContentToExpect: ZipFileContentToExpect?

    /// Controls whether the password selection sheet is presented.
    @State private var showPasswordSheet = false
    
    @State private var passwordChosenState: ZipContentSummaryView.PasswordChosenState = .notChosen

    /// Asks the data source to evaluate the ZIP content, then stores the result with animation.
    private func onTask() async {
        do {
            let zipFileContentToExpect = try await dataSource.evaluateZipFileContentToExpect(self, ownedCryptoId: ownedCryptoId, scope: scope)
            withAnimation {
                self.zipFileContentToExpect = zipFileContentToExpect
            }
        } catch {
            assertionFailure()
        }
    }

    /// Describes what will be packaged into the ZIP file.
    public struct ZipFileContentToExpect: Sendable, Equatable, Hashable {
        let numberOfMessages: Int
        let numberOfDiscussions: Int
        let numberOfFiles: Int
        let fileSizeInBytes: UInt64
        public init(numberOfMessages: Int, numberOfDiscussions: Int, numberOfFiles: Int, fileSizeInBytes: UInt64) {
            self.numberOfMessages = numberOfMessages
            self.numberOfFiles = numberOfFiles
            self.numberOfDiscussions = numberOfDiscussions
            self.fileSizeInBytes = fileSizeInBytes
        }
    }

    /// Shows the password selection sheet. Called when the user taps "Create ZIP file".
    private func requestPasswordThenLaunch() {
        showPasswordSheet = true
    }

    private func onPasswordChosen(_ password: String?) {
        withAnimation {
            if let password {
                passwordChosenState = .userChosePassword(password: password)
            } else {
                passwordChosenState = .userChoseNotToUsePassword
            }
        }
        Task {
            do {
                try await internalActions.launchZipping(self, password: password)
            } catch {
                assertionFailure()
            }
        }
    }

    public var body: some View {

        VStack(spacing: 16) {

            if let content = zipFileContentToExpect {
                Divider()
                ZipContentSummaryView(content: content, passwordChosenState: passwordChosenState)
            } else {
                ProgressView()
            }

        }
        .frame(maxWidth: .infinity)
        .safeAreaInset(edge: .bottom) {
            if zipFileContentToExpect != nil && !passwordChosenState.isPasswordChosen {
                HStack {
                    OlvidButtonNew(action: requestPasswordThenLaunch) {
                        Label(title: { Text("COMPUTING_ZIP_SIZE_BUTTON_TITLE_CREATE_ZIP") }, icon: { Image(systemIcon: .rectangleCompressVertical) })
                    }
                }
                .padding(.top)
            }
        }
        .sheet(isPresented: $showPasswordSheet) {
            ChooseZipPasswordView(isPresented: $showPasswordSheet, onPasswordChosen: onPasswordChosen)
        }
        .task(onTask)
    }

}


// MARK: - ChooseZipPasswordView

/// Sheet allowing the user to choose how to protect the ZIP export with a password.
/// Presents three options: generate a password automatically, create one manually, or skip.
/// On completion, calls `onPasswordChosen` with the selected password (or `nil` to skip),
/// then sets `isPresented` to `false` to dismiss itself.
private struct ChooseZipPasswordView: View {

    @Binding var isPresented: Bool
    let onPasswordChosen: (String?) -> Void

    private enum SheetState {
        case choosingMethod
        case showingGeneratedPassword(String)
        case creatingPassword
    }

    @State private var state: SheetState = .choosingMethod
    @State private var contentHeight: CGFloat = 0

    private func generateStrongPassword() -> String {
        let prng = ObvCryptoSuite.sharedInstance.prngService()
        let password = ZipPassword.generate(with: prng)
        return password
    }

    private func dismissSheet() {
        isPresented = false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 20) {
                    
                    ZipPasswordIconView()

                    switch state {
                    case .choosingMethod:
                        ZipPasswordMethodChooserContent(actions: self)
                    case .showingGeneratedPassword(let password):
                        ZipGeneratedPasswordContent(password: password, actions: self)
                    case .creatingPassword:
                        ZipCreatePasswordContent(actions: self)
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .presentationDetents([.medium, .large])
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ObvButtonWithCancelRole(action: dismissSheet)
                }
            }
        }
    }

}


extension ChooseZipPasswordView: ZipPasswordMethodChooserContentActions {

    func userTappedGeneratePassword(_ view: ZipPasswordMethodChooserContent) {
        withAnimation { state = .showingGeneratedPassword(generateStrongPassword()) }
    }

    func userTappedCreatePassword(_ view: ZipPasswordMethodChooserContent) {
        withAnimation { state = .creatingPassword }
    }

    func userTappedContinueWithoutPassword(_ view: ZipPasswordMethodChooserContent) {
        isPresented = false
        onPasswordChosen(nil)
    }

}


extension ChooseZipPasswordView: ZipGeneratedPasswordContentActions {

    func userConfirmedGeneratedPassword(_ view: ZipGeneratedPasswordContent, password: String) {
        isPresented = false
        onPasswordChosen(password)
    }

}


extension ChooseZipPasswordView: ZipCreatePasswordContentActions {

    func userConfirmedCreatedPassword(_ view: ZipCreatePasswordContent, password: String) {
        isPresented = false
        onPasswordChosen(password)
    }

}


// MARK: - ZipPasswordMethodChooserContent

@MainActor
private protocol ZipPasswordMethodChooserContentActions {
    func userTappedGeneratePassword(_ view: ZipPasswordMethodChooserContent)
    func userTappedCreatePassword(_ view: ZipPasswordMethodChooserContent)
    func userTappedContinueWithoutPassword(_ view: ZipPasswordMethodChooserContent)
}

private struct ZipPasswordMethodChooserContent: View {

    let actions: any ZipPasswordMethodChooserContentActions

    private func generatePassword() { actions.userTappedGeneratePassword(self) }
    private func createPassword() { actions.userTappedCreatePassword(self) }
    private func continueWithoutPassword() { actions.userTappedContinueWithoutPassword(self) }

    var body: some View {
        VStack(spacing: 20) {
            
            Text("ZIP_PASSWORD_PROTECT_EXPLANATION")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                OlvidButtonNew(action: generatePassword) {
                    Label(title: { Text("ZIP_PASSWORD_BUTTON_TITLE_GENERATE") }, icon: { Image(systemIcon: .ellipsisRectangle) })
                }

                OlvidButtonNew(action: createPassword, style: .glassOrBordered) {
                    Label(title: { Text("ZIP_PASSWORD_BUTTON_TITLE_CREATE") }, icon: { Image(systemIcon: .rectangleAndPencilAndEllipsis) })
                }

                OlvidButtonNew(action: continueWithoutPassword, style: .glassOrBordered) {
                    Label(title: { Text("ZIP_PASSWORD_BUTTON_TITLE_CONTINUE_WITHOUT") }, icon: { Image(systemIcon: .shieldSlash) })
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(String(localizedInThisBundle: "ZIP_PASSWORD_PROTECT_TITLE"))
        .navigationBarTitleDisplayMode(.inline)
    }

}


// MARK: - ZipGeneratedPasswordContent

@MainActor
private protocol ZipGeneratedPasswordContentActions {
    func userConfirmedGeneratedPassword(_ view: ZipGeneratedPasswordContent, password: String)
}

private struct ZipGeneratedPasswordContent: View {

    let password: String
    let actions: any ZipGeneratedPasswordContentActions

    @State private var isPasswordVisible: Bool = true
    @State private var isConfirmationShown: Bool = false

    private func createPasswordButtonTapped() {
        isConfirmationShown = true
    }
    
    private func createPasswordConfirmed() {
        actions.userConfirmedGeneratedPassword(self, password: password)
    }
    
    private func copyPassword() {
        UIPasteboard.general.setObjects([password], localOnly: true, expirationDate: nil)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    var body: some View {
        VStack(spacing: 20) {

            VStack(alignment: .leading, spacing: 6) {
                Text("ZIP_PASSWORD_FIELD_LABEL")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ZipPasswordDisplayField(text: password, isVisible: $isPasswordVisible)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            OlvidButtonNew(action: copyPassword, style: .glassOrBordered) {
                Label(title: { Text("ZIP_PASSWORD_COPY_BUTTON_TITLE") }, icon: { Image(systemIcon: .docOnClipboard) })
            }

            OlvidButtonNew(action: createPasswordButtonTapped) {
                Label(title: { Text("ZIP_PASSWORD_BUTTON_TITLE_CONFIRM") }, icon: { Image(systemIcon: .rectangleCompressVertical) })
            }
            .confirmationDialog(String(localizedInThisBundle: "ZIP_PASSWORD_COPIED_CONFIRMATION_TITLE"),
                                isPresented: $isConfirmationShown,
                                titleVisibility: .visible,
                                actions: {
                if #available(iOS 26.0, *) {
                    Button(String(localizedInThisBundle: "ZIP_PASSWORD_BUTTON_TITLE_CONFIRM"),
                           role: .confirm,
                           action: createPasswordConfirmed)
                } else {
                    Button(String(localizedInThisBundle: "ZIP_PASSWORD_BUTTON_TITLE_CONFIRM"),
                           action: createPasswordConfirmed)
                }
                Button(String(localizedInThisBundle: "BACK"), role: .cancel) {
                    isConfirmationShown = false
                }
            }, message: {
                Text("ZIP_PASSWORD_COPIED_CONFIRMATION_MESSAGE")
            })
        }
        .navigationTitle(String(localizedInThisBundle: "ZIP_PASSWORD_GENERATED_TITLE"))
        .navigationBarTitleDisplayMode(.inline)
    }

}


// MARK: - ZipCreatePasswordContent

@MainActor
private protocol ZipCreatePasswordContentActions {
    func userConfirmedCreatedPassword(_ view: ZipCreatePasswordContent, password: String)
}

private struct ZipCreatePasswordContent: View {

    let actions: any ZipCreatePasswordContentActions

    @State private var password: String = ""
    @State private var isPasswordVisible: Bool = false

    private func confirm() { actions.userConfirmedCreatedPassword(self, password: password) }

    var body: some View {
        VStack(spacing: 20) {

            VStack(alignment: .leading, spacing: 6) {
                Text("ZIP_PASSWORD_FIELD_LABEL")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ZipPasswordInputField(text: $password, isVisible: $isPasswordVisible)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            OlvidButtonNew(action: confirm) {
                Text("ZIP_PASSWORD_BUTTON_TITLE_CREATE")
            }
            .disabled(password.isEmpty)
        }
        .padding(.vertical, 8)
        .navigationTitle(String(localizedInThisBundle: "ZIP_PASSWORD_CREATE_TITLE"))
        .navigationBarTitleDisplayMode(.inline)
    }

}


// MARK: - ZipPasswordIconView

private struct ZipPasswordIconView: View {

    var body: some View {
        Image(systemIcon: .keyFill)
            .font(.system(size: 28, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(Color.green)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

}


// MARK: - ZipPasswordDisplayField

/// Read-only display of a password with a show/hide toggle.
private struct ZipPasswordDisplayField: View {

    let text: String
    @Binding var isVisible: Bool

    private func toggleVisibility() { isVisible.toggle() }

    var body: some View {
        HStack {
            if isVisible {
                Text(verbatim: text)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(verbatim: String(repeating: "•", count: text.count))
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: toggleVisibility) {
                Image(systemIcon: isVisible ? .eyeSlash : .eye)
                    .frame(width: 20)
            }
        }
        .padding(.horizontal)
        .padding(.vertical)
        .background(Color(.systemFill))
        .clipShape(RoundedRectangle(cornerRadius: ObvCardViewParameters.defaultCornerRadius, style: .continuous))
    }

}


// MARK: - ZipPasswordInputField

/// Editable password field with a show/hide toggle.
private struct ZipPasswordInputField: View {

    @Binding var text: String
    @Binding var isVisible: Bool

    private func toggleVisibility() { isVisible.toggle() }

    var body: some View {
        HStack {
            if isVisible {
                TextField(String(localizedInThisBundle: "ZIP_PASSWORD_FIELD_PLACEHOLDER"), text: $text)
                    .textContentType(.newPassword)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } else {
                SecureField(String(localizedInThisBundle: "ZIP_PASSWORD_FIELD_PLACEHOLDER"), text: $text)
                    .textContentType(.newPassword)
            }
            Button(action: toggleVisibility) {
                Image(systemIcon: isVisible ? .eyeSlash : .eye)
                    .frame(height: 20)
            }
        }
        .padding(.horizontal)
        .padding(.vertical)
        .background(Color(.systemFill))
        .clipShape(RoundedRectangle(cornerRadius: ObvCardViewParameters.defaultCornerRadius, style: .continuous))
    }

}


// MARK: - ZipContentSummaryView

/// Displays a three-row summary of the ZIP export content: message count, file count, and total
/// attachment size. Shown inside the card once `ZipFileContentToExpect` is available.
private struct ZipContentSummaryView: View {

    let content: ComputingExportZipFileSizeView.ZipFileContentToExpect
    let passwordChosenState: PasswordChosenState
    
    enum PasswordChosenState {
        case notChosen
        case userChosePassword(password: String)
        case userChoseNotToUsePassword
        var isPasswordChosen: Bool {
            switch self {
            case .notChosen: return false
            case .userChosePassword, .userChoseNotToUsePassword: return true
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemIcon: .textBubble)
                    .foregroundStyle(.blue)
                    .frame(width: 24, alignment: .center)
                Text(String(localizedInThisBundle: "COMPUTING_ZIP_SIZE_SUMMARY_\(content.numberOfMessages)_MESSAGES"))
                    .font(.body)
            }
            HStack(spacing: 8) {
                Image(systemIcon: .bubbleLeftAndBubbleRight)
                    .foregroundStyle(.green)
                    .frame(width: 24, alignment: .center)
                Text(String(localizedInThisBundle: "COMPUTING_ZIP_SIZE_SUMMARY_\(content.numberOfDiscussions)_DISCUSSIONS"))
                    .font(.body)
            }
            if content.numberOfFiles > 0 {
                HStack(spacing: 8) {
                    Image(systemIcon: .paperclip)
                        .foregroundStyle(.gray)
                        .frame(width: 24, alignment: .center)
                    Text(String(localizedInThisBundle: "COMPUTING_ZIP_SIZE_SUMMARY_\(content.numberOfFiles)_FILES"))
                        .font(.body)
                }
            }
            if content.fileSizeInBytes > 0 {
                HStack(spacing: 8) {
                    Image(systemIcon: .zipperPage)
                        .foregroundStyle(.orange)
                        .frame(width: 24, alignment: .center)
                    Text(String(localizedInThisBundle: "COMPUTING_ZIP_SIZE_SUMMARY_TOTAL_SIZE_\(content.fileSizeInBytes.formatted(.byteCount(style: .file)))"))
                        .font(.body)
                }
            }
            switch passwordChosenState {
            case .notChosen:
                EmptyView()
            case .userChosePassword(password: _):
                HStack(spacing: 8) {
                    Image(systemIcon: .checkmarkShieldFill)
                        .foregroundStyle(.green)
                        .frame(width: 24, alignment: .center)
                    Text("ZIP_PROTECTED_WITH_PASSWORD")
                        .font(.body)
                }
            case .userChoseNotToUsePassword:
                HStack(spacing: 8) {
                    Image(systemIcon: .checkmarkShieldFill)
                        .foregroundStyle(.red)
                        .frame(width: 24, alignment: .center)
                    Text("ZIP_NOT_PROTECTED_WITH_PASSWORD")
                        .font(.body)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}


// MARK: - ComputingZipView

@MainActor
private protocol ComputingZipViewActions {
    func viewRequiresAsyncStreamOfTransferExportState(_ view: ComputingZipView) async throws -> AsyncStream<TransferExportState>
    func userWantsToPopView(_view: ComputingZipView)
    func userWantsToCancelExportFromBackground(_ view: ComputingZipView) async
}

private struct ComputingZipView: View {

    let actions: any ComputingZipViewActions

    @State private var initializingStatus: InitializingStatusOnSourceDevice = .inProgress
    @State private var fetchingDiscussionsListStatus: FetchingDiscussionsListStatus?
    @State private var fetchingAllHashAndSizesOfFylesStatus: FetchingAllHashAndSizesOfFylesStatus?
    @State private var sendingMessagesStatus: SendingMessagesStatus?
    @State private var sendingAttachmentsStatus: SendingAttachmentsStatus?
    @State private var computingZipFileStatus: ComputingZipFileStatus?
    @State private var sendingDoneStatus: SendingDoneStatus?

    private func onTask() async {
        ObvContinuedProcessingTaskManager.run(taskKind: .historyTransfer) { bgContinuedProcessingTask in
            
            bgContinuedProcessingTask?.expirationHandler = {
                Task { await self.actions.userWantsToCancelExportFromBackground(self) }
            }

            do {
                let stream = try await actions.viewRequiresAsyncStreamOfTransferExportState(self)
                for await newState in stream {
                    withAnimation {
                        switch newState {
                        case .initializing(let status):
                            initializingStatus = status
                        case .sourceTransferStepsState(let state):
                            switch state {
                            case .fetchingDiscussionsList(let status):
                                fetchingDiscussionsListStatus = status
                            case .fetchingAllHashAndSizesOfFyles(let status):
                                fetchingAllHashAndSizesOfFylesStatus = status
                            case .negotiatingWhatToSend:
                                break
                            case .sendingMessages(let status):
                                sendingMessagesStatus = status
                            case .sendingAttachments(let status):
                                sendingAttachmentsStatus = status
                            case .computingZipFile(let status):
                                computingZipFileStatus = status
                                switch status {
                                case .inProgress(let entryNumber, let total):
                                    if let bgContinuedProcessingTask {
                                        bgContinuedProcessingTask.progress.totalUnitCount = Int64(total)
                                        bgContinuedProcessingTask.progress.completedUnitCount = Int64(entryNumber)
                                    }
                                case .done:
                                    break
                                }
                            case .done(let status):
                                sendingDoneStatus = status
                            }
                        case .canceling:
                            break
                        case .failed:
                            break
                        }
                    }
                }
            } catch {
                assertionFailure()
            }
            
        }
    }
    
    private var zipFileURL: URL? {
        guard let computingZipFileStatus else { return nil }
        switch computingZipFileStatus {
        case .inProgress: return nil
        case .done(let zipFileURL): return zipFileURL
        }
    }

    private enum ScrollAnchor: Hashable {
        case fetchingDiscussionsList
        case fetchingAllHashAndSizesOfFyles
        case sendingMessages
        case sendingAttachments
        case computingZipFile
        case sendingDone
    }
    
    @State private var isInterruptConfirmationDialogPresented = false
    
    /// Called when the user taps the back button.
    ///
    /// If the share link was tapped, we assume the zip file was saved and we go back.
    /// If not, we request a confirmation before going back, as this will delete the zip file.
    private func backButtonTapped() {
        if shareLinkWasTapped {
            actions.userWantsToPopView(_view: self)
        } else {
            isInterruptConfirmationDialogPresented = true
        }
    }
    
    private var interruptConfirmationDialogTitle: String {
        switch sendingDoneStatus {
        case .none:
            return String(localizedInThisBundle: "INTERRUPT_ZIP_COMPUTATION_CONFIRMATION_DIALOG_TITLE")
        case .exportFailed, .exportWasCancelledByUser, .exportWasSuccessful:
            return String(localizedInThisBundle: "ZIP_WILL_BE_DELETED_CONFIRMATION_DIALOG_TITLE")
        }
    }
    
    private var interruptConfirmationButtonTitle: String {
        switch sendingDoneStatus {
        case .none:
            return String(localizedInThisBundle: "INTERRUPT_ZIP_COMPUTATION_CONFIRMATION_BUTTON_TITLE")
        case .exportFailed, .exportWasCancelledByUser, .exportWasSuccessful:
            return String(localizedInThisBundle: "ZIP_WILL_BE_DELETED_CONFIRMATION_BUTTON_TITLE")
        }
    }
    
    private var stayHereButtonTitle: String {
        switch sendingDoneStatus {
        case .none:
            return String(localizedInThisBundle: "DO_NO_INTERRUPT_ZIP_COMPUTATION_BUTTON_TITLE")
        case .exportFailed, .exportWasCancelledByUser, .exportWasSuccessful:
            return String(localizedInThisBundle: "DO_NOT_LEAVE_BUTTON_TITLE")
        }
    }
    
    private func userConfirmedToInterrupt() {
        actions.userWantsToPopView(_view: self)
    }
    
    @State private var shareLinkWasTapped = false

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {

                Divider()
                    .padding(.bottom)

                ZipInitializingStatusRowView(
                    status: initializingStatus,
                    showLine: fetchingDiscussionsListStatus != nil || sendingDoneStatus != nil)

                if let fetchingDiscussionsListStatus {
                    ZipFetchingDiscussionsListStatusRowView(
                        status: fetchingDiscussionsListStatus,
                        showLine: fetchingAllHashAndSizesOfFylesStatus != nil || sendingDoneStatus != nil)
                    .id(ScrollAnchor.fetchingDiscussionsList)
                    .onAppear { withAnimation { proxy.scrollTo(ScrollAnchor.fetchingDiscussionsList, anchor: .bottom) } }
                }

                if let fetchingAllHashAndSizesOfFylesStatus {
                    ZipFetchingFilesStatusRowView(
                        status: fetchingAllHashAndSizesOfFylesStatus,
                        showLine: sendingMessagesStatus != nil || sendingDoneStatus != nil)
                    .id(ScrollAnchor.fetchingAllHashAndSizesOfFyles)
                    .onAppear { withAnimation { proxy.scrollTo(ScrollAnchor.fetchingAllHashAndSizesOfFyles, anchor: .bottom) } }
                }

                if let sendingMessagesStatus {
                    ZipWritingMessagesStatusRowView(
                        status: sendingMessagesStatus,
                        showLine: sendingAttachmentsStatus != nil || computingZipFileStatus != nil || sendingDoneStatus != nil)
                    .id(ScrollAnchor.sendingMessages)
                    .onAppear { withAnimation { proxy.scrollTo(ScrollAnchor.sendingMessages, anchor: .bottom) } }
                }

                if let sendingAttachmentsStatus {
                    ZipWritingAttachmentsStatusRowView(
                        status: sendingAttachmentsStatus,
                        showLine: computingZipFileStatus != nil || sendingDoneStatus != nil)
                    .id(ScrollAnchor.sendingAttachments)
                    .onAppear { withAnimation { proxy.scrollTo(ScrollAnchor.sendingAttachments, anchor: .bottom) } }
                }

                if let computingZipFileStatus {
                    ZipComputingZipFileStatusRowView(
                        computingZipFileStatus: computingZipFileStatus,
                        showLine: sendingDoneStatus != nil)
                    .id(ScrollAnchor.computingZipFile)
                    .onAppear { withAnimation { proxy.scrollTo(ScrollAnchor.computingZipFile, anchor: .bottom) } }
                }

                if let sendingDoneStatus, let zipFileURL {
                    ZipDoneStatusRowView(status: sendingDoneStatus, zipFileURL: zipFileURL, shareLinkWasTapped: $shareLinkWasTapped)
                        .id(ScrollAnchor.sendingDone)
                        .onAppear { withAnimation { proxy.scrollTo(ScrollAnchor.sendingDone, anchor: .bottom) } }
                }

                Spacer(minLength: 0)

            }
        }
        .task(onTask)
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
                .confirmationDialog(interruptConfirmationDialogTitle, isPresented: $isInterruptConfirmationDialogPresented, titleVisibility: .visible) {
                    Button(interruptConfirmationButtonTitle, role: .destructive, action: userConfirmedToInterrupt)
                    Button(stayHereButtonTitle, role: .cancel, action: {})
                }
            }
        }
    }

}


// MARK: - Row views for ComputingZipView

private struct ZipInitializingStatusRowView: View {

    let status: InitializingStatusOnSourceDevice
    let showLine: Bool

    private var progressItemState: ProgressItemState {
        switch status {
        case .inProgress, .connectingToDestinationDevice:
            return .inProgress
        case .connectedToDestinationDevice:
            return .success
        }
    }

    private var title: String {
        switch status {
        case .inProgress, .connectingToDestinationDevice:
            return String(localizedInThisBundle: "INIT_STATUS_VIEW_TITLE_INITIALIZING_ZIP_EXPORT")
        case .connectedToDestinationDevice:
            return String(localizedInThisBundle: "INIT_STATUS_VIEW_TITLE_INITIALIZED_ZIP_EXPORT")
        }
    }

    var body: some View {
        ProgressItemRowView(state: progressItemState, showLine: showLine, title: title) {
            EmptyView()
        }
    }

}


private struct ZipFetchingDiscussionsListStatusRowView: View {

    let status: FetchingDiscussionsListStatus
    let showLine: Bool

    private var progressItemState: ProgressItemState {
        switch status {
        case .inProgress: return .inProgress
        case .done: return .success
        }
    }

    private var subtitle: String {
        switch status {
        case .inProgress:
            return String(localizedInThisBundle: "FETCHING_DISCUSSION_LIST_01_IN_PROGRESS")
        case .done(let numberOfDiscussionsFound):
            return String(localizedInThisBundle: "FETCHING_DISCUSSION_LIST_01_FOUND_\(numberOfDiscussionsFound)_DISCUSSIONS")
        }
    }

    private var title: String {
        switch status {
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


private struct ZipFetchingFilesStatusRowView: View {

    let status: FetchingAllHashAndSizesOfFylesStatus
    let showLine: Bool

    private var progressItemState: ProgressItemState {
        switch status {
        case .inProgress: return .inProgress
        case .done: return .success
        }
    }

    private var subtitle: String {
        switch status {
        case .inProgress:
            return String(localizedInThisBundle: "FETCHING_ATTACHMENTS_VIEW_01_IN_PROGRESS")
        case .done(let numberOfFylesFound, let totalByteCount):
            if totalByteCount > 0 {
                return String(localizedInThisBundle: "FETCHING_ATTACHMENTS_VIEW_02_FOUND_\(numberOfFylesFound)_ATTACHMENTS_REPRESENTING_\(totalByteCount.formatted(.byteCount(style: .file)))_BYTES")
            } else {
                return String(localizedInThisBundle: "FETCHING_ATTACHMENTS_VIEW_02_FOUND_\(numberOfFylesFound)_ATTACHMENTS_REPRESENTING_ZERO_BYTES")
            }
        }
    }

    private var title: String {
        switch status {
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



private struct ZipWritingMessagesStatusRowView: View {

    let status: SendingMessagesStatus
    let showLine: Bool

    private var progressItemState: ProgressItemState {
        switch status {
        case .starting:
            return .inProgress
        case .inProgress(let sentMessageCount, let missingMessageCount, let numberOfMessagesToSend, _, _):
            return sentMessageCount + missingMessageCount >= numberOfMessagesToSend ? .success : .inProgress
        }
    }

    private var progress: (value: Double, total: Double)? {
        switch status {
        case .starting:
            return nil
        case .inProgress(let sentMessageCount, let missingMessageCount, let numberOfMessagesToSend, _, _):
            let done = sentMessageCount + missingMessageCount
            return done < numberOfMessagesToSend ? (Double(done), Double(numberOfMessagesToSend)) : nil
        }
    }

    private var subtitle: String? {
        switch status {
        case .starting:
            return String(localizedInThisBundle: "STARTING")
        case .inProgress(let sentMessageCount, let missingMessageCount, let numberOfMessagesToSend, _, _):
            if sentMessageCount + missingMessageCount < numberOfMessagesToSend {
                return String(localizedInThisBundle: "SENDING_MESSAGES_STATUS_VIEW_02_ADDING_\(numberOfMessagesToSend)_MESSAGES_TO_ZIP")
            } else {
                return String(localizedInThisBundle: "SENDING_MESSAGES_STATUS_VIEW_03_DID_ADD_\(sentMessageCount)_MESSAGES_TO_ZIP")
            }
        }
    }

    private var progressPercentage: String? {
        guard let progress else { return nil }
        return "\(Int(round(100 * progress.value / progress.total)))%"
    }

    private var title: String {
        switch status {
        case .starting:
            return String(localizedInThisBundle: "ADDING_MESSAGES_TO_ZIP_STATUS_VIEW_TITLE")
        case .inProgress(let sentMessageCount, let missingMessageCount, let numberOfMessagesToSend, _, _):
            if sentMessageCount + missingMessageCount >= numberOfMessagesToSend {
                return String(localizedInThisBundle: "ADDING_MESSAGES_TO_ZIP_STATUS_VIEW_TITLE_DONE")
            } else {
                return String(localizedInThisBundle: "ADDING_MESSAGES_TO_ZIP_STATUS_VIEW_TITLE")
            }
        }
    }

    var body: some View {
        ProgressItemRowView(state: progressItemState, showLine: showLine, title: title) {
            if let subtitle { Text(subtitle) }
            if let progress {
                ProgressView(value: progress.value, total: progress.total)
                ProgressAndETATextsView(etaString: nil, progressPercentage: progressPercentage)
            }
        }
    }

}


private struct ZipWritingAttachmentsStatusRowView: View {

    let status: SendingAttachmentsStatus
    let showLine: Bool

    private var progressItemState: ProgressItemState {
        switch status {
        case .starting:
            return .inProgress
        case .inProgress(let sentFylesCount, let failedFylesCount, _, _, let numberOfFylesToSend, _, _, _):
            if sentFylesCount + failedFylesCount >= numberOfFylesToSend {
                return failedFylesCount > 0 ? .warning : .success
            } else {
                return .inProgress
            }
        }
    }

    private var progress: (value: Double, total: Double)? {
        switch status {
        case .starting:
            return nil
        case .inProgress(_, _, let byteCountSent, let byteCountFailedToSend, _, let byteCountToSend, _, _):
            let done = byteCountSent + byteCountFailedToSend
            return done < byteCountToSend ? (Double(done), Double(byteCountToSend)) : nil
        }
    }

    private var subtitle: String? {
        switch status {
        case .starting:
            return String(localizedInThisBundle: "STARTING")
        case .inProgress(let sentFylesCount, let failedFylesCount, _, _, let numberOfFylesToSend, _, _, _):
            if sentFylesCount + failedFylesCount < numberOfFylesToSend {
                return String(localizedInThisBundle: "ADDING_ATTACHMENTS_STATUS_VIEW_SENDING_\(numberOfFylesToSend)_ATTACHMENTS")
            } else {
                return String(localizedInThisBundle: "ADDING_ATTACHMENTS_STATUS_VIEW_DID_SEND_\(numberOfFylesToSend)_ATTACHMENTS")
            }
        }
    }

    private var progressPercentage: String? {
        guard let progress else { return nil }
        return "\(Int(round(100 * progress.value / progress.total)))%"
    }

    private var title: String {
        switch status {
        case .starting:
            return String(localizedInThisBundle: "ADDING_ATTACHMENTS_TO_ZIP_VIEW_TITLE")
        case .inProgress(let sentFylesCount, let failedFylesCount, _, _, let numberOfFylesToSend, _, _, _):
            if sentFylesCount + failedFylesCount >= numberOfFylesToSend {
                return String(localizedInThisBundle: "ADDING_ATTACHMENTS_TO_ZIP_VIEW_TITLE_DONE")
            } else {
                return String(localizedInThisBundle: "ADDING_ATTACHMENTS_TO_ZIP_VIEW_TITLE")
            }
        }
    }

    var body: some View {
        ProgressItemRowView(state: progressItemState, showLine: showLine, title: title) {
            if let subtitle { Text(subtitle) }
            if let progress {
                ProgressView(value: progress.value, total: progress.total)
                ProgressAndETATextsView(etaString: nil, progressPercentage: progressPercentage)
            }
        }
    }

}


private struct ZipComputingZipFileStatusRowView: View {

    let computingZipFileStatus: ComputingZipFileStatus
    let showLine: Bool

    private var progressItemState: ProgressItemState {
        switch computingZipFileStatus {
        case .inProgress:
            return .inProgress
        case .done:
            return .success
        }
    }

    var body: some View {
        ProgressItemRowView(state: progressItemState, showLine: showLine, title: String(localizedInThisBundle: "ZIP_COMPUTING_ZIP_FILE_STATUS_VIEW_TITLE")) {
            switch computingZipFileStatus {
            case .inProgress(let entryNumber, let total):
                ProgressView(value: Double(entryNumber), total: Double(total))
                ProgressAndETATextsView(etaString: nil, progressPercentage: computingZipFileStatus.progressPercentage)
            case .done:
                EmptyView()
            }
        }
    }

}


private struct ZipDoneStatusRowView: View {

    let status: SendingDoneStatus
    let zipFileURL: URL
    @Binding var shareLinkWasTapped: Bool

    private var progressItemState: ProgressItemState {
        switch status {
        case .exportWasSuccessful: return .success
        case .exportWasCancelledByUser: return .warning
        case .exportFailed: return .error
        }
    }

    private var title: String {
        switch status {
        case .exportWasSuccessful:
            return String(localizedInThisBundle: "DONE_ZIP_VIEW_TITLE_EXPORT_WAS_SUCCESSFUL")
        case .exportWasCancelledByUser:
            return String(localizedInThisBundle: "DONE_ZIP_VIEW_TITLE_EXPORT_CANCELLED_BY_USER")
        case .exportFailed:
            return String(localizedInThisBundle: "DONE_ZIP_VIEW_TITLE_EXPORT_FAILED")
        }
    }
    
    @State private var triggerConfettiCanon = false
    
    private func onAppear() {
        triggerConfettiCanon = true
    }
    
    var body: some View {
        VStack {
            ProgressItemRowView(state: progressItemState, showLine: false, title: title) {
                EmptyView()
            }
            if #available(iOS 26.0, *) {
                ShareLink(item: zipFileURL) {
                    Label { Text("SHARE_ZIP_FILE_BUTTON_TITLE") } icon: { Image(systemIcon: .squareAndArrowUp) }
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .buttonSizing(.flexible)
                .simultaneousGesture(TapGesture().onEnded { shareLinkWasTapped = true })
            } else {
                ShareLink(item: zipFileURL) {
                    HStack {
                        Spacer(minLength: 0)
                        Label { Text("SHARE_ZIP_FILE_BUTTON_TITLE") } icon: { Image(systemIcon: .squareAndArrowUp) }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .simultaneousGesture(TapGesture().onEnded { shareLinkWasTapped = true })
            }
        }
        .onAppear(perform: onAppear)
        .confettiCannon(trigger: $triggerConfettiCanon,
                        num: 100,
                        openingAngle: Angle(degrees: 0),
                        closingAngle: Angle(degrees: 360),
                        radius: 200)
        .edgesIgnoringSafeArea(.all)
    }

}



// MARK: - Previews

#if DEBUG

private final class DataSourceForPreviews {}

extension DataSourceForPreviews: ZipExportViewDataSource {
    
    func evaluateZipFileContentToExpect(
        _ view: ComputingExportZipFileSizeView,
        ownedCryptoId: ObvTypes.ObvCryptoId,
        scope: TransferScope
    ) async throws -> ComputingExportZipFileSizeView.ZipFileContentToExpect {
        try await Task.sleep(seconds: 0)
        return .init(numberOfMessages: 230, numberOfDiscussions: 10, numberOfFiles: 42, fileSizeInBytes: 10_000)
    }
    
    
}


extension DataSourceForPreviews: TransferServiceForZipExportView {
    
    func onDisappear(of view: ZipExportView) async {
        print("On disappear")
    }
        
    func initiateHistoryTransfer(_ view: ZipExportView, transferTransportType: TransferTransportType, scope: TransferScope) async throws {
        print("Initiate transfer")
    }
    
    func viewRequiresAsyncStreamOfTransferExportState(_ view: ZipExportView) async -> AsyncStream<TransferExportState> {
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
                    let sleepInterval: TimeInterval = 0.2
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
                    
                    // Simulate the zip compression step
                    
                    do {
                        let sleepIntervalForZipCompression: TimeInterval = 0.1
                        var progress: Double = 0.0
                        while progress <= 1.0 {
                            try await Task.sleep(for: sleepIntervalForZipCompression)
                            continuation.yield(.sourceTransferStepsState(.computingZipFile(status: .inProgress(entryNumber: UInt(progress * 100), total: 100))))
                            progress += 0.05
                        }
                    }
                    continuation.yield(.sourceTransferStepsState(.computingZipFile(status: .done(zipFileURL: .temporaryDirectory))))

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


extension DataSourceForPreviews: ZipExportViewActions {
    
    func userRequiresMessageHistoryTransferService(_ view: ZipExportView) async throws -> any TransferServiceForZipExportView {
        return self
    }
    
}


extension DataSourceForPreviews: ZipExportViewInternalActions {
    
    func userWantsToPopView(_ view: ZipExportView) {
        print("User wants to pop view")
    }
    
}


@MainActor
private let dataSourceForPreviews = DataSourceForPreviews()

#Preview {
    ZipExportView(ownedCryptoId: .sampleDatasForOwnedCryptoId[0],
                          scope: .messagesAndAttachments,
                          dataSource: dataSourceForPreviews,
                          internalActions: dataSourceForPreviews,
                          actions: dataSourceForPreviews)
}


#Preview {
    VStack {
        ZipDoneStatusRowView(status: .exportWasSuccessful(failedFylesCount: 0),
                             zipFileURL: .temporaryDirectory.appendingPathComponent("test.zip", conformingTo: .zip), shareLinkWasTapped: .constant(false))
        .padding(.horizontal)
    }
    .frame(height: 100)
}

#endif
