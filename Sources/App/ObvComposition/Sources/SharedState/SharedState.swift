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

@preconcurrency import Foundation
import SwiftUI
import ObvSettings
import Combine
import ObvAppTypes
import UniformTypeIdentifiers
import AVFoundation
import OSLog
import ObvAppCoreConstants
import ObvSystemIcon
import ObvTypes
import ObvDesignSystem


/// In pratice, this is implemented by the `ComposeView`
@MainActor
protocol SharedStateDelegate {
    func userWantsToSendDraft(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, attributedText: AttributedString) async throws
    func composeViewHasChangedTextAndMentions(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, attributedText: AttributedString) async throws
    func userWantsToAddAttachmentsToDraft(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, itemProviders: [NSItemProvider]) async throws
}


extension ComposeView {
    
    /// State shared among the main view and the subviews of the composition view.
    @MainActor
    final class SharedState: ObservableObject {
        
        private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: SharedState.self))

        init(discussionIdentifier: ObvDiscussionIdentifier,
             initialBody: AttributedString?,
             containerURLforTempFiles: URL,
             initialParameters: ComposeViewParameters) {
            
            self.discussionIdentifier = discussionIdentifier
            self.containerURLforTempFiles = containerURLforTempFiles
            self.parameters = initialParameters
            self.textFieldSharedState = .init(discussionIdentifier: discussionIdentifier,
                                              initialBody: initialBody,
                                              initialSendMessageShortcutType: initialParameters.sendMessageShortcutType)
            self.mentionViewSharedState = .init(discussionIdentifier: discussionIdentifier)
            
            self.mentionViewSharedState.globalSharedState = self
            self.textFieldSharedState.globalSharedState = self
            
        }
        
        deinit {
            debugPrint("Deinit")
        }

        let discussionIdentifier: ObvDiscussionIdentifier

        
        let globalCornerRadius: CGFloat = 20.0
        
        
        private var delegate: SharedStateDelegate?
        
        
        func setDelegate(to newDelegate: SharedStateDelegate) {
            self.delegate = newDelegate
        }
        
        /// Allows to disable many parts of the compose view interface.
        @Published private(set) var isCurrentlySendingMessage = false
        
        
        private func setIsCurrentlySendingMessage(_ newValue: Bool) {
            self.isCurrentlySendingMessage = newValue
            self.textFieldSharedState.isPreventingEdition = self.isPreventingEdition
        }
        
        
        /// Allows the discussion view controller to disable the composition interface when it is loading something (e.g., while performing a drag and drop of a new attachment).
        @Published private(set) var isDiscussionViewPreventingEdition = false
        
        /// For now, this is only used when the user types a memoji in the text editor: in that case, we strip the memoji from the `AttributedString` and add its image as an attachment.
        /// During the process, `isLocallyAddingAttachment` is set to true.
        @Published private var isLocallyAddingAttachment = false
        
        /// This is used to disable various parts of the compose view.
        ///
        /// We do not disable all the views at once as disabling the TextEditor dismisses the keyboard and shows it a few milliseconds later,
        /// causing a bad user experience.
        var isPreventingEdition: Bool { isCurrentlySendingMessage || isDiscussionViewPreventingEdition || isLocallyAddingAttachment }
        
        
        func setIsDiscussionViewPreventingEdition(_ isLoading: Bool) {
            guard self.isDiscussionViewPreventingEdition != isLoading else { return }
            withAnimation {
                self.isDiscussionViewPreventingEdition = isLoading
                self.textFieldSharedState.isPreventingEdition = self.isPreventingEdition
            }
        }
        
        
        @Published var showNoRecordPermissionAlert: Bool = false
        
        
        @Published private(set) var hasReplyViewDisplayedAbove = false
        
        
        func setHasReplyViewDisplayedAbove(to newValue: Bool) {
            guard self.hasReplyViewDisplayedAbove != newValue else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                self.hasReplyViewDisplayedAbove = newValue
            }
        }
                  
        
        private let containerURLforTempFiles: URL
        
        
        enum AudioRecorderState {
            case notRecording
            case longPressing
            case isRecording
            case recorded
        }
        
        
        @Published private(set) var recordingState: AudioRecorderState = .notRecording
        
        
        func setAudioRecorderState(to newValue: AudioRecorderState) {
            guard self.recordingState != newValue else { return }
            self.recordingState = newValue
        }

        
        private let dateFormatter: DateFormatter = {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd HH-mm-ss"
            return df
        }()
        
        
        @Published private(set) var mentionViewSharedState: ComposeMentionsView.SharedState
        private(set) var textFieldSharedState: ComposeTextField.SharedState
        
        
        /// Allows to transfer the user decision about suggested mentions back to the view allowing to input text.
        private var continuationForMentions: CheckedContinuation<ComposeTextField.SharedState.UserDecisionOnNewMentionString, Never>?
                
        
        @Published private(set) var isTextEditorEmpty = true
                
        
        fileprivate func onTextChangeInTextEditor(_ newText: AttributedString?) {
            // Saves the current version of the body to database
            Task {
                do {
                    try await delegate?.composeViewHasChangedTextAndMentions(discussionIdentifier: discussionIdentifier, attributedText: newText ?? AttributedString())
                } catch {
                    assertionFailure()
                }
            }
            // Avoid publishing changes from within view updates
            Task { @MainActor in
                self.isTextEditorEmpty = (newText == nil)
            }
        }
        
        
        /// Set once at initialization, we expect the `ComposeView` to subscribe to a stream using the `ComposeViewParametersDataSource`
        /// and to update this value as required.
        @Published private(set) var parameters: ComposeViewParameters

        
        func onNewComposeViewParameters(_ newParameters: ComposeViewParameters) {
            self.parameters = newParameters
            self.textFieldSharedState.onNewSendMessageShortcutType(newParameters.sendMessageShortcutType)
        }
        
        
        /// Pastes provided text into the editor (e.g., the URL string after adding its preview as an attachment).
        ///
        /// This is used, e.g., when the user pastes an URL using the paste button of the compose view. In that case, the compose
        /// view requests to add attachments to the draft. An URL preview is added as an attachment, and the URL (as a String) is reported back
        /// here, so as to paste it in the `TextEditor`.
        func pasteTextIntoTextEditor(_ textToPaste: AttributedString) {
            self.textFieldSharedState.pasteTextIntoTextEditor(textToPaste)
        }
        
        
        private var draftHasAttachments: Bool = false
        
        /// This is called by the compose view. The `draftHasAttachments` is only used when the user requests the sending of the draft, to ensure there is something to send.
        func setDraftHasAttachments(to newValue: Bool) {
            guard self.draftHasAttachments != newValue else { return }
            self.draftHasAttachments = newValue
        }

        
        @available(iOS 18.0, *)
        fileprivate func userTypedAdaptiveImageGlyphAttributeInTextEditor(_ glyph: AttributedString.AdaptiveImageGlyph) {
            isLocallyAddingAttachment = true
            Task {
                defer { isLocallyAddingAttachment = false }
                if AttributedString.AdaptiveImageGlyph.contentType == .heic {
                    guard let pngData: Data = convertHEICToPNG(heicData: glyph.imageContent) else { assertionFailure(); return }
                    let itemProvider = NSItemProvider(item: pngData as NSData, typeIdentifier: UTType.png.identifier)
                    try await delegate?.userWantsToAddAttachmentsToDraft(discussionIdentifier: discussionIdentifier, itemProviders: [itemProvider])
                } else {
                    let itemProvider = NSItemProvider(item: glyph.imageContent as NSData, typeIdentifier: AttributedString.AdaptiveImageGlyph.contentType.identifier)
                    try await delegate?.userWantsToAddAttachmentsToDraft(discussionIdentifier: discussionIdentifier, itemProviders: [itemProvider])
                }
            }
        }
        
        
        fileprivate func userTypedStickerInTextEditor(_ stickerImage: UIImage) {
            isLocallyAddingAttachment = true
            Task {
                defer { isLocallyAddingAttachment = false }
                guard let pngData = stickerImage.pngData() else { assertionFailure(); return }
                let itemProvider = NSItemProvider(item: pngData as NSData, typeIdentifier: UTType.png.identifier)
                try await delegate?.userWantsToAddAttachmentsToDraft(discussionIdentifier: discussionIdentifier, itemProviders: [itemProvider])
            }
        }
        
        
        /// Called when the user pastes content into the text editor via UITextPasteDelegate
        /// This method receives the NSItemProvider directly and adds it as an attachment
        fileprivate func userPastedItemProvider(_ itemProvider: NSItemProvider) {
            isLocallyAddingAttachment = true
            Task {
                defer { isLocallyAddingAttachment = false }
                try await delegate?.userWantsToAddAttachmentsToDraft(discussionIdentifier: discussionIdentifier, itemProviders: [itemProvider])
            }
        }
        
    }
    
}


extension ComposeView.SharedState {

    /// This method is called when the user presses the up/down arrows while mention suggestions are shown. It allows to navigate through them.
    func suggestNextMentionIfAppropriate() -> KeyboardResult {
        self.mentionViewSharedState.suggestNextMentionIfAppropriate()
    }
    
    /// This method is called when the user presses the up/down arrows while mention suggestions are shown. It allows to navigate through them.
    func suggestPreviousMentionIfAppropriate() -> KeyboardResult {
        self.mentionViewSharedState.suggestPreviousMentionIfAppropriate()
    }
    
    func acceptCurrentlySelectedMentionIfAppropriate() -> KeyboardResult {
        self.mentionViewSharedState.acceptCurrentlySelectedMentionIfAppropriate()
    }
    
}


// MARK: - Errors

extension ComposeView.SharedState {
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}

// MARK: - Sending a draft

extension ComposeView.SharedState {
    
    enum SendRequest {
        case specificAttributedText(attributedText: AttributedString)
        case currentDraft
        case audioMessage
    }
    
    func userWantsToSendDraft(request: SendRequest) throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        Task {
            // We set isLocallyPreventingEdition from within the task to avoid publishing changes from within view updates
            self.setIsCurrentlySendingMessage(true)
            defer { self.setIsCurrentlySendingMessage(false) }
            do {
                switch request {
                case .audioMessage:
                    self.clearInput()
                    try await delegate.userWantsToSendDraft(discussionIdentifier: discussionIdentifier, attributedText: "")
                case .specificAttributedText(let attributedText):
                    self.clearInput()
                    try await delegate.userWantsToSendDraft(discussionIdentifier: discussionIdentifier, attributedText: attributedText)
                case .currentDraft:
                    let attributedText = self.computeAttributedStringFromCurrentTextInTextEditor() ?? AttributedString()
                    guard !attributedText.characters.isEmpty || draftHasAttachments else { assertionFailure(); return }
                    self.clearInput()
                    try await delegate.userWantsToSendDraft(discussionIdentifier: discussionIdentifier, attributedText: attributedText)
                }
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }

    
    /// Called by the compose view when the user requests the sending of the current draft (e.g., by tapping the "send" button).
    private func computeAttributedStringFromCurrentTextInTextEditor() -> AttributedString? {
        return self.textFieldSharedState.computeAttributedStringFromCurrentTextInTextEditor()
    }

    private func clearInput() {
        self.recordingState = .notRecording
        self.textFieldSharedState.clearInput()
        self.mentionViewSharedState.clearInput()
    }

}


extension ComposeView.SharedState: @MainActor ObvAudioRecorderDelegate {
    
    public func recordingHasFailed() {
        self.recordingState = .notRecording
    }
    
    
    func startRecording() {
        let containerURLforTempFiles = self.containerURLforTempFiles
        ObvAudioRecorder.shared.delegate = self
        
        guard let fileExtention = UTType.m4a.preferredFilenameExtension else { assertionFailure(); return }
        let name = "Recording @ \(self.dateFormatter.string(from: Date()))"
        let tempFileName = [name, fileExtention].joined(separator: ".")
        let url = containerURLforTempFiles.appendingPathComponent(tempFileName)
        
        let settings: [String: Int] = [
            AVFormatIDKey as String: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey as String: 44_100,
            AVEncoderBitRateKey as String: 48_000,
            AVNumberOfChannelsKey as String: 1,
            AVEncoderAudioQualityKey as String: Int(AVAudioQuality.high.rawValue)
        ]

        print("[debug] start recording at \(url)")
        ObvAudioRecorder.shared.startRecording(url: url, settings: settings) { result in
            switch result {
            case .success:
                Self.logger.info("🎤 Start Recording")
                return
            case .failure(let error):
                switch error {
                case .recordingInProgress:
                    assertionFailure()
                    self.recordingState = .notRecording
                case .noRecordPermission:()
                    self.showNoRecordPermissionAlert = true
                    self.recordingState = .notRecording
                case .audioSessionError(let error):
                    Self.logger.fault("🎤 Failed to record: audio session error \(error.localizedDescription, privacy: .public)")
                    assertionFailure()
                    self.recordingState = .notRecording
                case .audioRecorderError(let error):
                    Self.logger.fault("🎤 Failed to record: audio recorder error \(error.localizedDescription, privacy: .public)")
                    assertionFailure()
                    self.recordingState = .notRecording
                }
                return
            }
        }
    }
    
    func stopRecording() -> URL? {
        guard ObvAudioRecorder.shared.isRecording else { return nil }
        
        
        let url: URL
        do {
            url = try ObvAudioRecorder.shared.stopRecording()
            
            return url
        } catch {
            Self.logger.fault("🎤 Failed to record: \(error.localizedDescription, privacy: .public)")
            
            ObvAudioRecorder.shared.cancelRecording()
            recordingState = .notRecording
            return nil
        }
        
    }
}

// MARK: - Handling the communication between the text field and the mentions view

extension ComposeView.SharedState {
    
    fileprivate func userTypedMentionStringInTextEditor(_ newMentionString: String?) async -> ComposeTextField.SharedState.UserDecisionOnNewMentionString {
        return await withCheckedContinuation { (continuation: CheckedContinuation<ComposeTextField.SharedState.UserDecisionOnNewMentionString, Never>) in
            continuationForMentions?.resume(returning: .doNothing)
            continuationForMentions = continuation
            self.mentionViewSharedState.setCurrentMentionString(newMentionString)
        }
    }

    /// Called when the user selects a mention in the mentions view
    fileprivate func onMentionSelectedByUser(_ mention: ComposeMentionSuggestionModel) {
        guard let continuationForMentions else { assertionFailure(); return }
        continuationForMentions.resume(returning: .insertMention(mention))
        self.continuationForMentions = nil
    }
    
}


extension ComposeTextField {
    
    @MainActor
    final class SharedState: ObservableObject {
        
        fileprivate weak var globalSharedState: ComposeView.SharedState?
        
        let discussionIdentifier: ObvDiscussionIdentifier
        private var initialBody: AttributedString? // Value of the body when entering the discussion
        @Published fileprivate(set) var isPreventingEdition: Bool = false
        
        /// Observe changes to the global autocorrection setting
        @Published var autocorrection: ObvTextAutocorrectionType = ObvMessengerSettings.Discussions.autocorrectionType
        
        /// Allows to observe changes made to settings
        private var cancellables = Set<AnyCancellable>()
        
        init(discussionIdentifier: ObvDiscussionIdentifier,
             initialBody: AttributedString?,
             initialSendMessageShortcutType: ComposeViewParameters.SendMessageShortcutType) {
            self.discussionIdentifier = discussionIdentifier
            self.initialBody = initialBody
            self.sendMessageShortcutType = initialSendMessageShortcutType
            
            // Observe changes to the global autocorrection setting
            ObvMessengerSettingsObservableObject.shared.$autocorrectionType
                .receive(on: DispatchQueue.main)
                .sink { [weak self] newValue in
                    self?.autocorrection = newValue
                }
                .store(in: &cancellables)
        }

        private var currentTextInTextEditor: StringOrAttributedString? = nil
        private var currentMentionsInTextEditor = [Range<String.Index> : (mentionedCryptoId: ObvCryptoId, title: String)]() // Only used when the TextEditor does not support AttributedString (like on iOS 18)
        fileprivate(set) var sendMessageShortcutType: ComposeViewParameters.SendMessageShortcutType
        
        fileprivate func onNewSendMessageShortcutType(_ newSendMessageShortcutType: ComposeViewParameters.SendMessageShortcutType) {
            guard self.sendMessageShortcutType != newSendMessageShortcutType else { return }
            self.sendMessageShortcutType = newSendMessageShortcutType
        }
        
        enum UserDecisionOnNewMentionString {
            case doNothing
            case insertMention(ComposeMentionSuggestionModel)
        }
        
        /// Called by the text editor whenever it detects that the user input a new mention string (like "@alice") to look for.
        func userTypedMentionStringInTextEditor(_ newMentionString: String?) async -> UserDecisionOnNewMentionString {
            guard let globalSharedState else { assertionFailure(); return .doNothing }
            return await globalSharedState.userTypedMentionStringInTextEditor(newMentionString)
        }

        
        @available(iOS 18.0, *)
        func userTypedAdaptiveImageGlyphAttributeInTextEditor(_ glyph: AttributedString.AdaptiveImageGlyph) {
            globalSharedState?.userTypedAdaptiveImageGlyphAttributeInTextEditor(glyph)
        }
        
        func userTypedStickerInTextEditor(_ stickerImage: UIImage) {
            globalSharedState?.userTypedStickerInTextEditor(stickerImage)
        }
        
        /// Called when the user pastes content into the text editor
        func userPastedItemProvider(_ itemProvider: NSItemProvider) {
            globalSharedState?.userPastedItemProvider(itemProvider)
        }
        
        func onTextChangeInTextEditor(_ newText: StringOrAttributedString) {
            
            // Store the current text in the text editor
            
            switch newText {
            case .string(let string):
                if let trimmed = string.trimmingWhitespacesAndNewlines().mapToNilIfZeroLength() {
                    self.currentTextInTextEditor = .string(trimmed)
                } else {
                    self.currentTextInTextEditor = nil
                }
            case .attributedString(let attributedString):
                let trimmed = attributedString.trimmingWhitespacesAndNewlines()
                if !trimmed.characters.isEmpty {
                    self.currentTextInTextEditor = .attributedString(trimmed)
                } else {
                    self.currentTextInTextEditor = nil
                }
            }
            
            // If the text in the text editor is nil, there cannot be any mention in it
            
            if self.currentTextInTextEditor == nil {
                currentMentionsInTextEditor.removeAll()
            }
            
            // Allow other parts of the ComposeView to react to the change
            
            guard let globalSharedState else { assertionFailure(); return }
            
            globalSharedState.onTextChangeInTextEditor(self.computeAttributedStringFromCurrentTextInTextEditor())
            
        }
     
        
        func onNewInsertedMentionInTheTextEditor(mentionRangeInCurrentText: Range<String.Index>, mention: (mentionedCryptoId: ObvCryptoId, title: String)) {
            // When a new mention is inserted in the TextEditor, we remove any previous overlapping mention
            self.currentMentionsInTextEditor =  self.currentMentionsInTextEditor.filter { range, _ in !range.overlaps(mentionRangeInCurrentText) }
            self.currentMentionsInTextEditor[mentionRangeInCurrentText] = mention
        }
        
        
        fileprivate func clearInput() {
            self.currentTextInTextEditor = nil
            self.currentMentionsInTextEditor.removeAll()
            guard let continuationOnClearInput else { assertionFailure(); return }
            continuationOnClearInput.yield()
        }
        
        private var continuationOnClearInput: AsyncStream<Void>.Continuation?
        
        func getAsyncStreamOfClearInputRequests() -> AsyncStream<Void> {
            return AsyncStream<Void> { (continuation: AsyncStream<Void>.Continuation) in
                continuationOnClearInput?.finish()
                continuationOnClearInput = continuation
            }
        }
        
        fileprivate func computeAttributedStringFromCurrentTextInTextEditor() -> AttributedString? {
            guard let currentTextInTextEditor else { return nil }
            switch currentTextInTextEditor {
            case .attributedString(let attributedString):
                return attributedString
            case .string(let string):
                var attributedText = AttributedString(string)
                for (rangeInString, mention) in currentMentionsInTextEditor {
                    guard let rangeInAttributedString = Range(rangeInString, in: attributedText) else { continue }
                    guard "@" + mention.title == String(attributedText[rangeInAttributedString].characters) else { continue }
                    attributedText[rangeInAttributedString].mention = .init(cryptoId: mention.mentionedCryptoId)
                }
                return attributedText
            }
        }
        
        /// Called when the user perfoms the appropriate "send" shortcut (either Enter or Cmd+Enter)
        func userWantsToSendDraft(currentTextInTextEditor: StringOrAttributedString) throws {
            guard let globalSharedState else { assertionFailure(); throw ObvError.globalSharedStateIsNil }
            self.onTextChangeInTextEditor(currentTextInTextEditor)
            try globalSharedState.userWantsToSendDraft(request: .currentDraft)
        }
        
        enum ObvError: Error {
            case globalSharedStateIsNil
        }
        
        /// Returns the initial value of the body so that it can be inserted in the TextEditor when it appears.
        /// Once called, this method returns nil on subsequent calls, ensuring the initial value is never set twice.
        func consumeInitialBody() -> AttributedString? {
            let valueToReturn = self.initialBody
            self.initialBody = nil
            return valueToReturn
        }
        
        @Published private(set) var attributedTextToPaste: AttributedString? = nil
        @Published private(set) var textToPaste: String? = nil
        
        /// Pastes provided text into the editor (e.g., the URL string after adding its preview as an attachment).
        ///
        /// This is used, e.g., when the user pastes an URL using the paste button of the compose view. In that case, the compose
        /// view requests to add attachments to the draft. An URL preview is added as an attachment, and the URL (as a String) is reported back
        /// here, so as to paste it in the `TextEditor`.
        fileprivate func pasteTextIntoTextEditor(_ newTextToPaste: AttributedString) {
            assert(attributedTextToPaste == nil)
            assert(textToPaste == nil)
            attributedTextToPaste = newTextToPaste
            textToPaste = String(newTextToPaste.characters[...])
        }
        
        func resetTextToPasteIntoTextEditor() {
            attributedTextToPaste = nil
            textToPaste = nil
        }
        
    }
    
}


// MARK: - Shared state for the ComposeMentionsView

extension ComposeMentionsView {
    
    @MainActor
    final class SharedState: ObservableObject {
        
        /// Expected to be set from the `ComposeMentionView`, while listening to the stream of its datasource.
        @Published private(set) var streamedModel: ComposeSuggestionsModel?
        @Published var currentStreamUUID: UUID?
        
        func setStreamedModel(to newStreamedModel: ComposeSuggestionsModel) {
            guard self.streamedModel != newStreamedModel else { return }
            if newStreamedModel.mentions.count > 0 {
                self.suggestionSelectedIndex = self.suggestionSelectedIndex % newStreamedModel.mentions.count
            } else {
                self.suggestionSelectedIndex = 0
            }
            self.streamedModel = newStreamedModel
        }
        
        @Published private(set) var suggestionSelectedIndex: Int = 0
        
        fileprivate weak var globalSharedState: ComposeView.SharedState?
        
        let discussionIdentifier: ObvDiscussionIdentifier
        
        init(discussionIdentifier: ObvDiscussionIdentifier) {
            self.discussionIdentifier = discussionIdentifier
        }
        
        @Published private(set) var currentMentionString: String?
        
        fileprivate func setCurrentMentionString(_ currentMentionString: String?) {
            self.currentMentionString = currentMentionString
        }
        
        func onMentionSelectedByUser(_ mention: ComposeMentionSuggestionModel) {
            globalSharedState?.onMentionSelectedByUser(mention)
        }
        
        fileprivate func suggestNextMentionIfAppropriate() -> KeyboardResult {
            guard let streamedModel else { assertionFailure(); return .ignored }
            guard streamedModel.mentions.count > 0 else { self.suggestionSelectedIndex = 0; return .ignored }
            // Avoid publishing changes from within view updates
            Task { self.suggestionSelectedIndex = (self.suggestionSelectedIndex + 1) % streamedModel.mentions.count }
            return .handled
        }
        
        fileprivate func suggestPreviousMentionIfAppropriate() -> KeyboardResult {
            guard let streamedModel else { assertionFailure(); return .ignored }
            guard streamedModel.mentions.count > 0 else { self.suggestionSelectedIndex = 0; return .ignored }
            // Avoid publishing changes from within view updates
            Task { self.suggestionSelectedIndex = (self.suggestionSelectedIndex - 1 + streamedModel.mentions.count) % streamedModel.mentions.count } // Note that adding streamedModel.mentions.count allows to have a positive value
            return .handled
        }
        
        fileprivate func acceptCurrentlySelectedMentionIfAppropriate() -> KeyboardResult {
            guard let streamedModel else { assertionFailure(); return .ignored }
            guard streamedModel.mentions.count > 0 else { self.suggestionSelectedIndex = 0; return .ignored }
            guard self.suggestionSelectedIndex >= 0 && self.suggestionSelectedIndex < streamedModel.mentions.count else { self.suggestionSelectedIndex = 0; return .ignored }
            let mention = streamedModel.mentions[self.suggestionSelectedIndex]
            self.onMentionSelectedByUser(mention)
            return .handled
        }
        
        fileprivate func clearInput() {
            self.suggestionSelectedIndex = 0
        }
        
    }
    
}


// MARK: - Private helpers

private func convertHEICToPNG(heicData: Data) -> Data? {
    
    guard let imageSource = CGImageSourceCreateWithData(heicData as CFData, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        return nil
    }
    
    let pngData = NSMutableData()
    guard let imageDestination = CGImageDestinationCreateWithData(
        pngData as CFMutableData,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        return nil
    }
    
    CGImageDestinationAddImage(imageDestination, cgImage, nil)
    
    guard CGImageDestinationFinalize(imageDestination) else {
        return nil
    }
    
    return pngData as Data
    
}
