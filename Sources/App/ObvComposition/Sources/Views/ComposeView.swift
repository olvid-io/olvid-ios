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
        /// Public, as the owner of the view needs it to compute the initial model, exactly as `ShareExtensionView.DataSources` does.
        public let dataSource: any ComposeViewDataSource
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
    
    /// `initialDataSourceViewModel` is the seed of the first frame, and is expected to be computed by the owner of this view, typically the screen
    /// embedding the composition view. It used to be fetched here, which was acceptable as long as a `UIHostingController` was the only way to create
    /// this view, hence created it once. It is not, as soon as this view is embedded in a SwiftUI hierarchy: `init` then runs on every evaluation of the
    /// body of the parent, so the fetch would be repeated.
    /// How much empty space is kept between this bar and whatever is below it — the bottom of the window on a Mac, where a bar flush with the
    /// edge looks wrong. Nothing by default, which is what a screen that spaces the bar itself wants.
    ///
    /// **It is part of the bar, and that is the point of it being here** rather than padding applied by whoever places the bar: the space is
    /// inside the drop target, so a file let go in the gap under the bar is taken as readily as one let go on it. See
    /// ``TakesWhateverIsDroppedOnTheBar``.
    ///
    /// The legacy screen keeps this space with a constraint of its own (`constantForComposeMessageContainerViewbottomAnchorConstraintToKeyboardConstant`),
    /// which is why the default is zero: it would otherwise be spaced twice.
    private let spaceKeptBelowTheBar: CGFloat

    /// What ``spaceKeptBelowTheBar`` should be on the platform this is running on, for a screen that does not space the bar itself.
    ///
    /// The legacy screen's own numbers, transcribed: **20pt on a Mac**, and nothing elsewhere — where the home indicator already provides the
    /// margin. Legacy has a third case this does not, `-16` when the bottom safe area is zero, as on an iPhone SE; that one is still open on
    /// the SwiftUI screen.
    public static var spaceKeptBelowTheBarOnThisPlatform: CGFloat {
        #if targetEnvironment(macCatalyst)
        return 20
        #else
        return 0
        #endif
    }

    /// Whether this bar may **animate a change of its own height** — the attachment panel opening or closing, a link preview appearing.
    ///
    /// **True by default, which is the legacy screen**, and it is not a preference: it depends on how the host reserves the space below the
    /// messages, and the two screens do it differently.
    ///
    /// The legacy screen writes `contentInset.bottom` on its collection view by hand, so an animated height change here costs it nothing. The
    /// SwiftUI screen places this bar in a `safeAreaInset`, and **SwiftUI answers an *animated* change of that content's height by
    /// reparameterising the scroll view** — shortening it and zeroing the whole bottom inset, then animating the frame back. An **un-animated**
    /// change of the same height does not provoke it at all, which is what makes this a workable answer rather than a compromise.
    ///
    /// **Removed on 2026-08-24 and restored the same evening, which is the part worth keeping.** It was removed because Step 46g had made the
    /// simplest case clean: an attachment removed at the *end* of a discussion with no keyboard, where the reparameterisation costs fifteen frames
    /// in which the transcript rides smoothly with the panel and nothing is wrong. That measurement was true and far too narrow. With a keyboard
    /// up the inset is 526 rather than 84, so the list is reparameterised to **348pt**; and sending a message with an attachment starts a
    /// scroll-to-the-end *through* that. Measured: 667 frames out of 781 with the list at some height other than its own, a 7,357pt scroll running
    /// for **3.3 seconds** inside a viewport growing from 348 to 472 with `inset=0` throughout, every position it computed answering a geometry
    /// that was wrong and still moving.
    ///
    /// So the rule stands as it was first written: **no scroll offset can repair a reparameterisation**, and the only reliable answer is not to
    /// provoke one. What would buy the animation back is making the panel *slide under a clip* while the height this reports changes in one step —
    /// content that follows without geometry that rides. Not attempted.
    private let theBarsHeightMayBeAnimated: Bool

    public init(sharedState: ComposeView.SharedState,
                dataSources: DataSources,
                actions: any ComposeViewActions,
                initialDataSourceViewModel: ComposeViewDataSourceModel?,
                spaceKeptBelowTheBar: CGFloat = 0,
                theBarsHeightMayBeAnimated: Bool = true) {
        self.sharedState = sharedState
        self.dataSources = dataSources
        self.actions = actions
        self.initialDataSourceViewModel = initialDataSourceViewModel
        self.spaceKeptBelowTheBar = spaceKeptBelowTheBar
        self.theBarsHeightMayBeAnimated = theBarsHeightMayBeAnimated
        // The shared state calls the actions directly, and holds them weakly. It used to hold *this view* as its delegate, purely so that it could pass a
        // `ComposeView` to each action — and since a view holds the state through its `@ObservedObject`, the two retained each other and nothing was ever
        // deallocated. Idempotent, and thus harmless when `init` is evaluated repeatedly.
        self.sharedState.setActions(to: actions)
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
    
    
    private func onTaskForTheProgressOfTheVideosBeingPrepared() async {
        let stream = dataSources.dataSource.getAsyncStreamOfTheProgressOfTheVideosBeingPrepared(discussionIdentifier: sharedState.discussionIdentifier)
        for await fractionCompleted in stream {
            sharedState.setFractionOfTheVideosBeingPrepared(fractionCompleted)
        }
    }


    private func onChangeOfHasAttachments(_ newValue: Bool) {
        self.sharedState.setDraftHasAttachments(to: newValue)
    }


    private func onChangeOfQuotesAMessage(_ newValue: Bool) {
        self.sharedState.setDraftQuotesAMessage(to: newValue)
    }


    /// The reader picked the size this draft's photographs are to be sent at.
    ///
    /// Not awaited, and nothing here waits on the answer: the choice is recorded on the draft and comes back through the model stream
    /// like everything else this bar shows, so the menu's checkmark moves when the draft says so rather than when this returns.
    private func photoFormatTapped(_ format: ObvMediaFormat) {
        guard format != dataSourceViewModel?.mediaFormatSelection?.selected else { return }
        Task {
            do {
                try await actions.userWantsToChangeTheMediaFormatOfTheDraft(self, discussionIdentifier: sharedState.discussionIdentifier, format: format)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
    
    public var body: some View {
        // This view sizes itself to its content, as a bar should. It used to be wrapped in a `VStack` starting with a `Spacer`, which made it take
        // whatever height it was offered and show its content at the bottom of that. Harmless as long as a `UIHostingController` was the only host, its
        // view being pinned by constraints — but a SwiftUI host offering it the height of the screen, as `safeAreaInset` does, then got a bar an entire
        // screen tall. `content` being a single view, no container is needed around it.
        content
        .onDisappear {
            ComposeAudioPlayer.shared.stop()
            // A mention request is left waiting on every change of the text selection, and a suspended `async` method keeps its `self` alive — see
            // `resumeAnyPendingMentionRequest()`. Without this, the shared state of every discussion ever opened stays in memory.
            sharedState.resumeAnyPendingMentionRequest()
        }
        .task(onTaskForComposeViewParameters)
        .task(onTaskForTheProgressOfTheVideosBeingPrepared)
        .onChange(of: hasAttachments, perform: onChangeOfHasAttachments)
        .onChange(of: attachments) { _ in sharedState.draftAttachmentsDidChange() }
        .task { onChangeOfHasAttachments(self.hasAttachments) } // Ensures sharedState.draftHasAttachments is properly reset when showing this view
        // The same two lines for the quote, for the same reason: the shared state answers the screen's Esc, and must know what the bar shows.
        .onChange(of: replyTo != nil, perform: onChangeOfQuotesAMessage)
        .task { onChangeOfQuotesAMessage(self.replyTo != nil) }
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
    

    /// What the text editors are given to report the keys this view is interested in.
    ///
    /// It captures the shared state **weakly**, and nothing else — in particular not this view. SwiftUI keeps the handlers of `onKeyPress` alive well past
    /// the life of the view that installed them, and the editors have three of them; handing them `self.handleKeyboardAction(action:)`, a bound method,
    /// therefore captured this whole view struct — and with it the shared state and the actions object — for good. Found in a memory graph: three
    /// `KeyPress.Handler`s, each holding a closure context whose backtrace ran through `ComposeView.content.getter`.
    private var keyboardAction: (KeyboardActionType) -> KeyboardResult {
        { [weak sharedState] action in
            sharedState?.handleKeyboardAction(action: action) ?? .ignored
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
    
    @State var showActionsPanel: Bool = false
    
    /// The entry chosen in the `+` card, carried out once the card has gone. See ``ComposeView/theCardHasGone()``.
    @State var actionAwaitingTheCardsDeparture: ComposeViewParameters.Action?
    
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
            
            if !showAudioRecording { ///Don't show the plus button if it is in recording state.
                
                Button {
                    showActionsPanel = true
                } label: {
                    Image(systemIcon: .plus)
                        .font(.system(size: Self.buttonSize/2))
                        .frame(width: Self.buttonSize, height: Self.buttonSize)
                }
                /// **No `arrowEdge`.** It names the edge the arrow sits on, so `.top` hangs the card *below* the button —
                /// which, the button being at the bottom of the screen, put all but two rows of it past the screen edge.
                /// Left unsaid, the system places the card itself and flips it to wherever it fits.
                .popover(isPresented: $showActionsPanel, attachmentAnchor: .rect(.bounds)) {
                    ComposeActionsPanelView(actions: availableActionsForPanel,
                                            drawsItsOwnCard: false,
                                            titleForAction: { dataSourceViewModel?.actionTitle(for: $0) ?? $0.title },
                                            actionTapped: { panelActionTapped($0) })
                    /// Without this an iPhone turns the popover into a sheet, which is a different control: a sheet comes
                    /// from the bottom of the screen and says nothing about what opened it, where the point here is that
                    /// the card belongs to the plus button.
                    .presentationCompactAdaptationOniOS16Dot4(.popover)
                    .onDisappear(perform: theCardHasGone)
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
                        // The size menu sits inside this row, whose height is pinned below, so that it cannot change the bar's height
                        // (see ``ComposeMediaFormatButton``). A sibling of the thumbnails rather than an overlay, so that the scrolling
                        // strip never passes under it. Its 6pt top padding matches the thumbnails', so their tops line up.
                        HStack(alignment: .top, spacing: 8.0) {
                            if let mediaFormatSelection = dataSourceViewModel?.mediaFormatSelection {
                                ComposeMediaFormatButton(selection: mediaFormatSelection,
                                                         isDisabled: sharedState.isPreventingEdition,
                                                         formatTapped: photoFormatTapped)
                                .padding(.leading, 12.0)
                                .padding(.top, 6.0)
                            }
                            ComposeAttachmentsView(viewModel: sharedState,
                                                   isCurrentlySendingMessage: sharedState.isCurrentlySendingMessage,
                                                   videosAreBeingPrepared: sharedState.fractionOfTheVideosBeingPrepared != nil,
                                                   theSentAttachmentsAreStillListed: sharedState.theSentAttachmentsAreStillListed,
                                                   attachments: attachments,
                                                   attachmentDataSource: dataSources.attachmentDataSource,
                                                   actions: self.actions)
                        }
                        .transition(.move(edge: .bottom))
                        Divider()
                            .padding(.horizontal, 12.0)
                    }
                }
                .disabled(sharedState.isPreventingEdition)
                // **Step 46j, stage 1: the animation governs the content and not the height.** It sat *after* the frame, so the one thing it could
                // have animated was the height — which is the one thing on this screen that must never animate, a `safeAreaInset` answering an
                // animated height change by reparameterising the scroll view beneath it. Above the frame it reaches the panel's own transition and
                // nothing else, so the bar's reported height still changes in a single step while the content slides under the clip.
                //
                // **It was recorded as "demonstrably inert and nobody knows why", and 46l explains it.** The panel used to pop when an attachment
                // was added and slide when one was removed — and the direction that slid is exactly the direction that went through
                // `withAnimation`, the insertion having been excluded by `hasInsertionToPerform`. This modifier was never what animated anything;
                // the ambient transaction was. Which also means moving it cannot cost the legacy screen its slide, that coming from `withAnimation`
                // and not from here.
                .animation(.linear(duration: 0.25), value: !attachments.isEmpty)
                .frame(height: !attachments.isEmpty ? 125 : 0)
                .frame(maxWidth: .infinity, alignment: .topLeading)
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
                                                 keyboardAction: self.keyboardAction)
                                .fixedSize(horizontal: false, vertical: true) // Ensures the height is independent of the "plus"/"emoji" button sizes
                                .opacity(sharedState.recordingState == .longPressing ? 0.0 : 1.0)
                                .opacity(sharedState.isPreventingEdition ? 0.1 : 1.0)
                                .padding(.bottom, 4.0)
                                
                                if sharedState.isPreventingEdition {
                                    // A caption and a progress bar while attachments load or a send waits for the draft's videos, both of
                                    // which can take tens of seconds. For any other reason the bar is shut, a plain spinner.
                                    if sharedState.attachmentsLoadingFractionCompleted != nil {
                                        AttachmentsLoadingProgressView(caption: "ATTACHMENTS_LOADING_PROGRESS_CAPTION",
                                                                       fractionCompleted: sharedState.attachmentsLoadingFractionCompleted)
                                            .padding(.horizontal, 12.0)
                                    } else if sharedState.isCurrentlySendingMessage, let fractionOfTheVideosBeingPrepared = sharedState.fractionOfTheVideosBeingPrepared {
                                        AttachmentsLoadingProgressView(caption: "VIDEOS_BEING_PREPARED_FOR_SENDING_PROGRESS_CAPTION",
                                                                       fractionCompleted: fractionOfTheVideosBeingPrepared)
                                            .padding(.horizontal, 12.0)
                                    } else {
                                        ProgressView()
                                    }
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
                                        // Reported on a Mac: only the arrow glyph answered a click, the rest of the
                                        // tinted capsule doing nothing -- a thing a finger forgives and a pointer does
                                        // not, and the third instance on this screen after the trash of Step 42 and the
                                        // search bar. The read is that the capsule is drawn by the *style* rather than
                                        // by the label, and SwiftUI hit-tests what is drawn; unlike the buttons beside
                                        // it, this label carries no frame of its own, so nothing but the glyph was
                                        // there to hit. That mechanism is the read and not a measurement -- if the
                                        // whole capsule still refuses a click, it is something above taking it and
                                        // this line is not the fix.
                                        // Placed before the padding below, so the target is the control and not the gap.
                                        .contentShape(Rectangle())
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
        // The space below the bar, kept **above** the drop target on purpose, so that the gap is part of what takes a drop rather than a dead
        // strip under it. See ``spaceKeptBelowTheBar``.
        .padding(.bottom, spaceKeptBelowTheBar)
        // Whatever is dropped on this bar goes into the draft — the whole bar, the trailing button and the space below it, and both discussion
        // screens with it. See ``TakesWhateverIsDroppedOnTheBar``, which also says why this is `onDrop`, and why the messages of the SwiftUI
        // screen take theirs through the `List`'s own collection view rather than through anything here.
        .modifier(TakesWhateverIsDroppedOnTheBar(sharedState: sharedState))
        .glassEffectContainer(spacing: 8.0)
        .task(onTaskForAsyncStreamOfComposeViewDataSourceModel)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.linear(duration: 0.25), value: showAudioRecording)
        .alert("ALERT_VOICE_MESSAGE_FAILED_USER_DENIED_RECORDING", isPresented: $sharedState.showNoRecordPermissionAlert, actions: {})
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
                
                // **A host that cannot afford an animated height change gets none, in either direction** — see ``theBarsHeightMayBeAnimated``. The
                // insertion is suppressed for everybody, which it already was; only the removal is conditional.
                let theBarMustNotAnimateItsHeight = !theBarsHeightMayBeAnimated
                    && (self.streamedDataSourceViewModel?.mayChangeTheHeightOfTheBar(comparedTo: receivedDataSourceViewModel) ?? false)

                // This test prevents a potential animation glitch
                if hasInsertionToPerform || theBarMustNotAnimateItsHeight {
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
                                      actions: dataSourceAndActionsForPreviews,
                                      initialDataSourceViewModel: dataSourceAndActionsForPreviews.getInitialComposeViewDataSourceModel(discussionIdentifier: .sampleDataForOneToOne))

#Preview {
    composeView
}

#endif

