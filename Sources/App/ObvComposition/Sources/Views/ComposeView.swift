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
import CoreData
import ObvDesignSystem
import ObvAppTypes


public struct ComposeView: View {
    
    /// State shared accross views
    @ObservedObject var sharedState: ComposeView.SharedState
            
    /// DataSource View Model
    private let initialDataSourceViewModel: ComposeViewDataSourceModel?
    @State private var streamedDataSourceViewModel: ComposeViewDataSourceModel?
    var dataSourceViewModel: ComposeViewDataSourceModel? {
        streamedDataSourceViewModel ?? initialDataSourceViewModel
    }
    
    @State private var streamUUIDOfComposeSuggestionsModel: UUID?
    
    // Mentions View Model
    
    //@State private var mentionSuggestionsViewModel: ComposeSuggestionsModel?
    
    public struct DataSources {
        let dataSource: any ComposeViewDataSource
        let attachmentDataSource: any ComposeAttachmentViewDataSource
        let replyToDataSource: any ComposeReplyToViewDataSource
        let mentionsDataSource: any ComposeMentionsViewDataSource
        let avatarViewDataSource: any ObvAvatarViewDataSource
        let composeViewParametersDataSource: any ComposeViewParametersDataSource
        let composeLinkPreviewViewDataSource: any ComposeLinkPreviewViewDataSource
        public init(dataSource: any ComposeViewDataSource,
                    attachmentDataSource: any ComposeAttachmentViewDataSource,
                    replyToDataSource: any ComposeReplyToViewDataSource,
                    mentionsDataSource: any ComposeMentionsViewDataSource,
                    avatarViewDataSource: any ObvAvatarViewDataSource,
                    composeViewParametersDataSource: any ComposeViewParametersDataSource,
                    composeLinkPreviewViewDataSource: any ComposeLinkPreviewViewDataSource) {
            self.dataSource = dataSource
            self.attachmentDataSource = attachmentDataSource
            self.replyToDataSource = replyToDataSource
            self.mentionsDataSource = mentionsDataSource
            self.avatarViewDataSource = avatarViewDataSource
            self.composeViewParametersDataSource = composeViewParametersDataSource
            self.composeLinkPreviewViewDataSource = composeLinkPreviewViewDataSource
        }
    }
    
    private let dataSources: DataSources
        
    @GestureState private var isPressing = false
        
    /// Actions
    public let actions: any ComposeViewActions
    
    private var emoji: String {
        dataSourceViewModel?.emojiButtonSpecificToDiscussion ?? sharedState.parameters.defaultEmojiButton
    }
    
    @Namespace private var namespace
    
    init(sharedState: ComposeView.SharedState,
         dataSources: DataSources,
         actions: any ComposeViewActions) {
        self.sharedState = sharedState
        self.dataSources = dataSources
        self.actions = actions
        self.initialDataSourceViewModel = dataSources.dataSource.getInitialComposeViewDataSourceModel(discussionIdentifier: sharedState.discussionIdentifier)
        self.sharedState.setDelegate(to: self)
    }
    
    private var isMessageEmpty: Bool { sharedState.isTextEditorEmpty && attachments.isEmpty }
    private var attachments: [ComposeAttachmentView.AttachmentIdentifier] { dataSourceViewModel?.attachments ?? [] }
    private var hasAttachments: Bool { !attachments.isEmpty }
    private var replyTo: ObvAppTypes.ObvMessageAppIdentifier? { dataSourceViewModel?.replyTo }
    private var audioAttachment: ComposeAttachmentView.AttachmentIdentifier? { dataSourceViewModel?.audioAttachment }
        
    private var showAudioRecording: Bool {
        sharedState.recordingState == .isRecording || sharedState.recordingState == .recorded
    }
    
    private func onTaskForComposeViewParameters() async {
        do {
            let (streamUUID, stream) = try await dataSources.composeViewParametersDataSource.getAsyncStreamOfComposeViewParameters(self)
            for await parameters in stream {
                withAnimation { self.sharedState.onNewComposeViewParameters(parameters)  }
            }
            dataSources.composeViewParametersDataSource.finishAsyncStreamOfComposeViewParameters(streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
    
    
    private func onChangeOfHasAttachments(_ newValue: Bool) {
        self.sharedState.setDraftHasAttachments(to: newValue)
    }
    
    
    public var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            content
        }
        .onDisappear {
            ComposeAudioPlayer.shared.stop()
        }
        .task(onTaskForComposeViewParameters)
        .onChange(of: hasAttachments, perform: onChangeOfHasAttachments)
        .task { onChangeOfHasAttachments(self.hasAttachments) } // Ensures sharedState.draftHasAttachments is properly reset when showing this view
    }
    
    private func sendEmoji(count: Int = 1) async {
        guard sharedState.isTextEditorEmpty else { assertionFailure(); return }
        var textToSend: String = ""
        for _ in 0..<count {
            textToSend.append(emoji)
        }
        guard !textToSend.isEmpty else { return }
        do {
            try sharedState.userWantsToSendDraft(request: .specificAttributedText(attributedText: AttributedString(textToSend)))
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }
    

    private func handleKeyboardAction(action: KeyboardActionType) -> KeyboardResult {
        switch action {

        case .up:
            return sharedState.suggestPreviousMentionIfAppropriate()

        case .down:
            return sharedState.suggestNextMentionIfAppropriate()

        case .enter:
            
            // If the user is currently navigating through mentions, typing Enter should insert the mention
            
            let result = sharedState.acceptCurrentlySelectedMentionIfAppropriate()
            switch result {
            case .handled:
                return .handled
            case .ignored:
                break
            }
            
            // If we reach this point, there was no mention to insert. We might have to send the message
            
            switch sharedState.parameters.sendMessageShortcutType {
            case .enter:
                if !self.isMessageEmpty {
                    do { try sharedState.userWantsToSendDraft(request: .currentDraft) } catch { assertionFailure(error.localizedDescription) }
                    return .handled
                }
            case .commandEnter:
                break
            }
            
            // If we reach this point the enter key should be handled at the text editor level
            
            return .ignored
            
        }
    }
    
    
    private static let buttonSize: CGFloat = 48.0
    private static let paddingBetweenPlusAndPasteButtons: CGFloat = 10.0
    
    private static var horizontalPadding: CGFloat {
        #if targetEnvironment(macCatalyst)
        return 16.0
        #else
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 16.0
        } else {
            return 12.0
        }
        #endif
    }

    /// Used by the `NewSingleDiscussionViewController` when performing a hit testing in order to determine
    /// whether the hit should be transferred to this view.
    @MainActor
    public struct PasteButtonGeometry {
        public static var maxY: CGFloat { horizontalPadding + buttonSize }
        public static var minY: CGFloat { horizontalPadding }
        public static var heightPlusBottomPadding: CGFloat { paddingBetweenPlusAndPasteButtons + buttonSize }
    }
    
    @State private var emojiButtonTapCount: Int = 0
    @State private var emojiButtonTapTimer: Timer?

    private func emojiButtonTapped() {
        emojiButtonTapCount += 1
        emojiButtonTapTimer?.invalidate()
        emojiButtonTapTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            Task { @MainActor in
                let tapCount = emojiButtonTapCount
                emojiButtonTapCount = 0
                await sendEmoji(count: min(3, tapCount))
            }
        }
    }
    
    public var content: some View {
        HStack(alignment: .bottom, spacing: 8.0) {
            
            // *****************************************************
            // MARK: - MORE OPTIONS
            // *****************************************************
            
            if !showAudioRecording { ///Don't show menu button if is it in recording state.
                                
                Menu {
                    menuContent
                } label: {
                    Image(systemIcon: .plus)
                        .font(.system(size: Self.buttonSize/2))
                        .frame(width: Self.buttonSize, height: Self.buttonSize)
                }
                .disabled(sharedState.isPreventingEdition)
                .glassButtonStyle()
                .transition(.move(edge: .leading))
                
            } else if let audioAttachment { /// If we should show audio recording, if there is an attachment (meaning a record has been performed), we show a button to delete the audio
                AsyncButton {
                    ComposeAudioPlayer.shared.stop()
                    do {
                        try await self.actions.userWantsToDeleteDraftAttachment(self, attachmentIdentifier: audioAttachment)
                    } catch {
                        assertionFailure()
                    }
                } label: {
                    Image(systemIcon: .xmark)
                        .imageScale(.large)
                        .padding(12.0)
                        .frame(width: Self.buttonSize, height: Self.buttonSize)
                }
                .disabled(sharedState.isPreventingEdition)
                .glassButtonStyle()
                .padding(.bottom, 6.0)
            }
            
            VStack(alignment: .leading, spacing: 0.0) {
                
                // *****************************************************
                // MARK: - REPLYTO VIEW
                // *****************************************************
                
                VStack(alignment: .leading, spacing: 0) {
                    if let replyTo {
                        ComposeReplyToView(replyToMessageIdentifier: replyTo,
                                           dataSource: dataSources.replyToDataSource,
                                           hasReplyViewDisplayedAbove: sharedState.hasReplyViewDisplayedAbove,
                                           actions: self.actions)
                        .transition(.move(edge: .bottom))
                    }
                }
                .disabled(sharedState.isPreventingEdition)
                .frame(height: (replyTo != nil) ? 70.0 : 0.0)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .animation(.linear(duration: 0.25), value: replyTo != nil)
                .animation(.linear(duration: 0.25), value: isMessageEmpty)
                .clipped()
                
                // *****************************************************
                // MARK: - PREVIEW VIEW
                // *****************************************************
                
                VStack(alignment: .leading, spacing: 0) {
                    if let linkPreviewIdentifier = dataSourceViewModel?.linkPreviewIdentifier {
                        ComposeLinkPreviewView(linkPreviewIdentifier: linkPreviewIdentifier,
                                               dataSource: dataSources.composeLinkPreviewViewDataSource,
                                               actions: self.actions)
                        .transition(.move(edge: .bottom))
                    }
                }
                .disabled(sharedState.isPreventingEdition)
                //.frame(maxHeight: dataSourceViewModel?.linkPreviewIdentifier != nil ? 200 : 0)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .animation(.linear(duration: 0.25), value: dataSourceViewModel?.linkPreviewIdentifier != nil)
                .clipped()

                // *****************************************************
                // MARK: - ATTACHMENTS VIEW
                // *****************************************************
                
                VStack(alignment: .leading, spacing: 0) {
                    if !attachments.isEmpty {
                        ComposeAttachmentsView(viewModel: sharedState,
                                               attachments: attachments,
                                               attachmentDataSource: dataSources.attachmentDataSource,
                                               actions: self.actions)
                        .transition(.move(edge: .bottom))
                        Divider()
                            .padding(.horizontal, 12.0)
                    }
                }
                .disabled(sharedState.isPreventingEdition)
                .frame(height: !attachments.isEmpty ? 125 : 0)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .animation(.linear(duration: 0.25), value: !attachments.isEmpty)
                .clipped()
                
                // *****************************************************
                // MARK: - MENTIONS
                // *****************************************************

                ComposeMentionsView(
                    sharedState: self.sharedState.mentionViewSharedState,
                    dataSource: self.dataSources.mentionsDataSource,
                    avatarViewDataSource: self.dataSources.avatarViewDataSource)
                .disabled(sharedState.isPreventingEdition)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .transition(.move(edge: .bottom))
                .clipped()

                HStack(alignment: .bottom, spacing: 8) {
                    
                    // *****************************************************
                    // MARK: - AUDIO RECORDER
                    // *****************************************************
                    
                    if showAudioRecording {
                        
                        HStack(alignment: .center) {
                            
                            /// Audio Recording
                            if sharedState.recordingState == .isRecording {
                                ComposeAudioRecorderView()
                                
                                AsyncButton(action: {
                                    if let audioURL = sharedState.stopRecording() {
                                        try? await actions.userDidRecordAudio(at: audioURL, discussionIdentifier: sharedState.discussionIdentifier)
                                    }
                                }) {
                                    Image(systemIcon: .stopFill)
                                        .imageScale(.small)
                                        .padding(10.0)
                                }
                                .glassButtonStyle(tintColor: .red)
                            } else { /// Audio Recorded
                                if let audioAttachment {
                                    ComposeAudioPlayerView(viewModel: sharedState,
                                                           audioAttachment: audioAttachment,
                                                           attachmentDataSource: dataSources.attachmentDataSource)
                                } else {
                                    Spacer()
                                    ProgressView()
                                    Spacer()
                                }
                                
                                AsyncButton(action: {
                                    ComposeAudioPlayer.shared.stop()
                                    do { try sharedState.userWantsToSendDraft(request: .audioMessage) } catch { assertionFailure(error.localizedDescription) }
                                }) {
                                    Image(systemIcon: .arrowUp)
                                        .fontWeight(.bold)
                                        .imageScale(.medium)
                                }
                                .buttonStyle(.borderedProminent)
                                .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                                        removal: .move(edge: .leading).combined(with: .opacity)))
                            }
                        }
                        .disabled(sharedState.isPreventingEdition)
                        .frame(height: 60.0)
                        
                    } else {
                        
                        // **************************************************************
                        // MARK: - HSTACK containing text field and send or record button
                        // **************************************************************

                        HStack(alignment: .bottom, spacing: 0.0) {
                            
                            // *****************************************************
                            // MARK: - TEXTFIELD
                            // *****************************************************
                            
                            ZStack(alignment: .center) {
                                
                                ComposeTextField(sharedState: self.sharedState.textFieldSharedState,
                                                 keyboardAction: self.handleKeyboardAction(action:))
                                .fixedSize(horizontal: false, vertical: true) // Ensures the height is independent of the "plus"/"emoji" button sizes
                                .opacity(sharedState.recordingState == .longPressing ? 0.0 : 1.0)
                                .opacity(sharedState.isPreventingEdition ? 0.1 : 1.0)
                                .padding(.bottom, 4.0)
                                
                                if sharedState.isPreventingEdition {
                                    ProgressView()
                                }
                                
                                if sharedState.recordingState == .longPressing {
                                    Text("PLACEHOLDER_RECORDING")
                                        .font(.caption)
                                        .lineLimit(2)
                                        .foregroundStyle(.secondary)
                                }
                                
                            }
                            .frame(minHeight: 50)
                            .animation(.linear(duration: 0.25), value: (sharedState.recordingState == .longPressing))
                            
                            // *****************************************************
                            // MARK: - ACTION BUTTON (SEND OR RECORD)
                            // *****************************************************
                            
                            Group {
                                
                                if isMessageEmpty {
                                    
                                    VStack {
                                        Spacer(minLength: 0)
                                        Button(action: {
                                            #if targetEnvironment(macCatalyst)
                                            sharedState.setAudioRecorderState(to: .isRecording)
                                            #endif
                                        }) { // No action on tap
                                            Image(systemIcon: .waveform)
                                                .imageScale(.large)
                                                .foregroundStyle(Color(uiColor: .label).opacity(0.5))
                                        }
                                        #if !targetEnvironment(macCatalyst)
                                        .simultaneousGesture(
                                            LongPressGesture()
                                                .updating($isPressing) { value, state, _ in
                                                    state = value
                                                }
                                                .onChanged { _ in sharedState.setAudioRecorderState(to: .longPressing) }
                                                .onEnded { _ in sharedState.setAudioRecorderState(to: .isRecording) }
                                        )
                                        .onChange(of: isPressing) { pressed in
                                            if !pressed {
                                                // Button released, even the duration was not reached
                                                if sharedState.recordingState == .longPressing {
                                                    let delay: TimeInterval = 1.0
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                                        sharedState.setAudioRecorderState(to: .notRecording)
                                                    }
                                                }
                                            }
                                        }
                                        #endif
                                        .transition(.asymmetric(insertion: .opacity,
                                                                removal: .opacity))
                                        Spacer(minLength: 0)
                                    }
                                    
                                } else {
                                    
                                    ZStack {
                                        
                                        Spacer(minLength: 0)
                                        
                                        AsyncButton {
                                            do { try sharedState.userWantsToSendDraft(request: .currentDraft) } catch { assertionFailure(error.localizedDescription) }
                                        } label: {
                                            Image(systemIcon: .arrowUp)
                                                .fontWeight(.bold)
                                                .imageScale(.medium)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                                                removal: .move(edge: .leading).combined(with: .opacity)))
                                        .padding(.bottom, Self.buttonSize / 4.0)
                                        
                                    }
                                        
                                }
                                
                            }
                            .disabled(sharedState.isPreventingEdition)
                            .animation(.linear(duration: 0.25), value: isMessageEmpty)
                            
                        }
                            
                    }
                }
                .padding(.horizontal, 12)
                .onChange(of: sharedState.recordingState) { newState in
                    if newState == .isRecording {
                        sharedState.startRecording()
                    }
                }
            }
            .glassTextFieldStyle(namespace: namespace, cornerRadius: sharedState.globalCornerRadius)
            .ephemeralStyle(isEphemeral: dataSourceViewModel?.hasSomeExpiration ?? false, cornerRadius: sharedState.globalCornerRadius)
            .frame(minHeight: 50)
            
            // *****************************************************
            // MARK: - EMOJI SHORTCUT
            // *****************************************************
            
            if isMessageEmpty && !showAudioRecording {
                
                Button(action: emojiButtonTapped) {
                    Text(emoji)
                        .font(.system(size: 20))
                        .padding(14)
                        .frame(width: Self.buttonSize, height: Self.buttonSize)
                }
                .glassButtonStyle()
                .transition(.move(edge: .trailing))
                .disabled(sharedState.isPreventingEdition)
            }
            
        }
        .padding(.horizontal, Self.horizontalPadding)
        .glassEffectContainer(spacing: 8.0)
        .task(onTaskForAsyncStreamOfComposeViewDataSourceModel)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.linear(duration: 0.25), value: showAudioRecording)
        .alert("ALERT_VOICE_MESSAGE_FAILED_USER_DENIED_RECORDING", isPresented: $sharedState.showNoRecordPermissionAlert, actions: {})
    }
}


extension ComposeView: SharedStateDelegate {
    
    func composeViewHasChangedTextAndMentions(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, attributedText: AttributedString) async throws {
        try await actions.composeViewHasChangedTextAndMentions(self, discussionIdentifier: discussionIdentifier, attributedText: attributedText)
    }
    
    func userWantsToSendDraft(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, attributedText: AttributedString) async throws {
        try await actions.userWantsToSendDraft(self, discussionIdentifier: discussionIdentifier, attributedText: attributedText)
    }
    
    func userWantsToAddAttachmentsToDraft(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, itemProviders: [NSItemProvider]) async throws {
        try await actions.userWantsToAddAttachmentsToDraft(self, discussionIdentifier: discussionIdentifier, itemProviders: itemProviders)
    }

}

extension ComposeView {
    
    private func onTaskForAsyncStreamOfComposeViewDataSourceModel() async {
        do {
            let (streamUUID, stream) = try await dataSources.dataSource.getAsyncStreamOfComposeViewDataSourceModel(self, discussionIdentifier: sharedState.discussionIdentifier)
            for await receivedDataSourceViewModel in stream {
                                
                let hasInsertionToPerform = self.streamedDataSourceViewModel?.hasInsertionToPerform(compareTo: receivedDataSourceViewModel) ?? false
                
                if receivedDataSourceViewModel.audioAttachment != nil {
                    sharedState.setAudioRecorderState(to: .recorded)
                } else {
                    sharedState.setAudioRecorderState(to: .notRecording)
                }
                
                // This test prevents a potential animation glitch
                if hasInsertionToPerform {
                    self.streamedDataSourceViewModel = receivedDataSourceViewModel
                } else {
                    withAnimation {
                        self.streamedDataSourceViewModel = receivedDataSourceViewModel
                    }
                }
            }
            dataSources.dataSource.finishAsyncStreamOfComposeViewDataSourceModel(self, streamUUID: streamUUID)
        } catch {
            assertionFailure()
        }
    }
    
}


#if DEBUG

@MainActor
private let dataSourceAndActionsForPreviews = DataSourceAndActionsForPreviews()

@MainActor
private let parameters = ComposeViewParameters(
    sortableActions: ComposeViewParameters.SortableAction.allCases,
    unsortableActions: ComposeViewParameters.UnsortableAction.allCases,
    defaultEmojiButton: "👍",
    sendMessageShortcutType: .enter)

@MainActor
private let sharedState = ComposeView.SharedState(discussionIdentifier: .sampleDataForOneToOne,
                                                  initialBody: nil, //AttributedString("Initial body"),
                                                  containerURLforTempFiles: URL.temporaryDirectory,
                                                  initialParameters: parameters)

@MainActor
private var composeView = ComposeView(sharedState: sharedState,
                                      dataSources: .init(dataSource: dataSourceAndActionsForPreviews,
                                                         attachmentDataSource: dataSourceAndActionsForPreviews,
                                                         replyToDataSource: dataSourceAndActionsForPreviews,
                                                         mentionsDataSource: dataSourceAndActionsForPreviews,
                                                         avatarViewDataSource: dataSourceAndActionsForPreviews,
                                                         composeViewParametersDataSource: dataSourceAndActionsForPreviews,
                                                         composeLinkPreviewViewDataSource: dataSourceAndActionsForPreviews),
                                      actions: dataSourceAndActionsForPreviews)

#Preview {
    composeView
}

#endif

