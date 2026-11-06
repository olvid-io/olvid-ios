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
import SwiftUI
import ObvDesignSystem
import ObvAppTypes
import ObvTypes


@MainActor
public final class ComposeViewHostingController: UIHostingController<ComposeView> {
    
    /// Publishes the latest frame of the main content view. This is used by the new single discussion view controller to adapt the insets of the collection view of messages.
    @Published public var composeViewFrame: CGRect = .zero
    
    private let sharedState: ComposeView.SharedState
    private let internalComposeViewActions = InternalComposeViewActions()
    
    // ************************
    // MARK: - Life Cycle
    // ************************
    
    public init(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier,
                initialBody: AttributedString?,
                dataSources: ComposeView.DataSources,
                actions: any ComposeViewActions,
                sendMessageShortcutType: ComposeViewParameters.SendMessageShortcutType,
                containerURLforTempFiles: URL,
                initialParameters: ComposeViewParameters) {
        
        self.sharedState = ComposeView.SharedState(discussionIdentifier: discussionIdentifier,
                                                   initialBody: initialBody,
                                                   containerURLforTempFiles: containerURLforTempFiles,
                                                   initialParameters: initialParameters)
        
        // This controller creates the view once, so fetching the seed of its first frame here is appropriate.
        let initialDataSourceViewModel = dataSources.dataSource.getInitialComposeViewDataSourceModel(discussionIdentifier: discussionIdentifier)

        let composeView = ComposeView(sharedState: sharedState,
                                      dataSources: dataSources,
                                      actions: internalComposeViewActions,
                                      initialDataSourceViewModel: initialDataSourceViewModel)
        
        super.init(rootView: composeView)
        
        internalComposeViewActions.delegate = actions

    }
    
    deinit {
        debugPrint("Deinit")
    }

    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.invalidateIntrinsicContentSize()
        updateComposeViewFramePublisher()
    }
    
    
    @MainActor required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }
    

    /// Called from ``viewDidLayoutSubviews()``
    private func updateComposeViewFramePublisher() {
        guard let superview = self.view.superview else { return }
        let composeViewViewBounds = self.view.bounds
        let newComposeViewFrame = superview.convert(composeViewViewBounds, from: self.view)
        if self.composeViewFrame != newComposeViewFrame {
            self.composeViewFrame = newComposeViewFrame
        }
    }
        
    // MARK: - The Return keys of the composition bar

    /// ↩, ⇧↩ and ⌘↩ while the caret is in the bar, each a `UIKeyCommand` with `wantsPriorityOverSystemBehavior`: a key that produces a character is
    /// claimed by text input, so a command without the flag is never offered Return, and SwiftUI's own handlers never see it at all. With it, the command
    /// fires and the text is left untouched, and the bar decides what the key means in one place, ``ComposeView/SharedState/returnWasPressed(with:)``.
    ///
    /// **No predicate here**, where the SwiftUI discussion needs one: this controller is in the responder chain only while the first responder is inside
    /// the bar, the legacy screen's search field living in the navigation bar, so a Return pressed anywhere else never reaches these. The selectors are
    /// named after this class, UIKit sending a command's action to the first responder in the chain that implements it.
    /// Built once: UIKit reads `keyCommands` about eighteen times per press, and the three commands never change.
    private let returnKeys: [UIKeyCommand] = {
        let returnKeys = [
            UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(ComposeViewHostingController.composeViewHostingControllerAnswersTheReturnKey)),
            UIKeyCommand(input: "\r", modifierFlags: .shift, action: #selector(ComposeViewHostingController.composeViewHostingControllerAnswersTheShiftReturnKey)),
            UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(ComposeViewHostingController.composeViewHostingControllerAnswersTheCommandReturnKey)),
        ]
        for command in returnKeys {
            command.wantsPriorityOverSystemBehavior = true
        }
        return returnKeys
    }()

    public override var keyCommands: [UIKeyCommand]? {
        (super.keyCommands ?? []) + returnKeys
    }

    @objc private func composeViewHostingControllerAnswersTheReturnKey() {
        sharedState.returnWasPressed(with: .none)
    }

    @objc private func composeViewHostingControllerAnswersTheShiftReturnKey() {
        sharedState.returnWasPressed(with: .shift)
    }

    @objc private func composeViewHostingControllerAnswersTheCommandReturnKey() {
        sharedState.returnWasPressed(with: .command)
    }

}

extension ComposeViewHostingController {
  
    public var isDiscussionViewPreventingEdition: Bool {
        get { sharedState.isDiscussionViewPreventingEdition }
        set { sharedState.setIsDiscussionViewPreventingEdition(newValue) }
    }
    
    public var hasReplyViewDisplayedAbove: Bool {
        get { sharedState.hasReplyViewDisplayedAbove }
        set { sharedState.setHasReplyViewDisplayedAbove(to: newValue) }
    }
    
    public func pasteTextIntoTextEditor(_ textToPaste: AttributedString) {
        sharedState.pasteTextIntoTextEditor(textToPaste)
    }
    
}


// MARK - Implementing an internal class that conforms to ComposeViewActions


/// In practice, the `ComposeViewActions` are implemented by the discussion view. To prevenit a memory cycle, we create this internal class that acts as a proxy and allows to keep a weak reference to the discussion view controller.
@MainActor
fileprivate final class InternalComposeViewActions: ComposeViewActions {
    
    fileprivate weak var delegate: (any ComposeViewActions)?
    
    func userWantsToSendDraft(_ sharedState: ComposeView.SharedState, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, attributedText: AttributedString) async throws {
        try await delegate?.userWantsToSendDraft(sharedState, discussionIdentifier: discussionIdentifier, attributedText: attributedText)
    }

    func composeViewHasChangedTextAndMentions(_ sharedState: ComposeView.SharedState, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, attributedText: AttributedString) async throws {
        try await delegate?.composeViewHasChangedTextAndMentions(sharedState, discussionIdentifier: discussionIdentifier, attributedText: attributedText)
    }
    
    func actionTapped(_ view: ComposeView, for action: ComposeViewParameters.Action, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, contactIdentifier: ObvTypes.ObvContactIdentifier?) async throws {
        try await delegate?.actionTapped(view, for: action, discussionIdentifier: discussionIdentifier, contactIdentifier: contactIdentifier)
    }
    
    func userDidTapOnDraftFyleJoinWithHardLink(_ view: ComposeAttachmentsView, at index: Int) throws {
        try delegate?.userDidTapOnDraftFyleJoinWithHardLink(view, at: index)
    }
    
    func userDidRecordAudio(at url: URL, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) async throws {
        try await delegate?.userDidRecordAudio(at: url, discussionIdentifier: discussionIdentifier)
    }
    
    func userWantstoRemoveReplyToMessage(_ view: ComposeReplyToView, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) async throws {
        try await delegate?.userWantstoRemoveReplyToMessage(view, discussionIdentifier: discussionIdentifier)
    }
    
    func userWantsToOpenEmojiPicker() {
        delegate?.userWantsToOpenEmojiPicker()
    }

    func userWantsToChangeTheMediaFormatOfTheDraft(_ view: ComposeView, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, format: ObvMediaFormat) async throws {
        try await delegate?.userWantsToChangeTheMediaFormatOfTheDraft(view, discussionIdentifier: discussionIdentifier, format: format)
    }


    func userWantsToDeleteDraftAttachment(_ view: ComposeAttachmentView, attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws {
        try await delegate?.userWantsToDeleteDraftAttachment(view, attachmentIdentifier: attachmentIdentifier)
    }
    
    func userWantsToDeleteDraftAttachment(_ view: ComposeView, attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws {
        try await delegate?.userWantsToDeleteDraftAttachment(view, attachmentIdentifier: attachmentIdentifier)
    }
    
    func userWantsToDeleteDraftAttachment(_ view: ComposeLinkPreviewView, attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws {
        try await delegate?.userWantsToDeleteDraftAttachment(view, attachmentIdentifier: attachmentIdentifier)
    }
    
    func userWantsToAddAttachmentsToDraft(_ sharedState: ComposeView.SharedState, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, itemProviders: [NSItemProvider]) async throws -> [TextToPasteIntoTheDraft] {
        // No delegate means nobody to add anything to a draft, and therefore nothing that could have been text.
        try await delegate?.userWantsToAddAttachmentsToDraft(sharedState, discussionIdentifier: discussionIdentifier, itemProviders: itemProviders) ?? []
    }
    
}
