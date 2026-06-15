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
        
        let composeView = ComposeView(sharedState: sharedState,
                                      dataSources: dataSources,
                                      actions: internalComposeViewActions)
        
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
    
    func userWantsToSendDraft(_ view: ComposeView, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, attributedText: AttributedString) async throws {
        try await delegate?.userWantsToSendDraft(view, discussionIdentifier: discussionIdentifier, attributedText: attributedText)
    }
    
    func composeViewHasChangedTextAndMentions(_ view: ComposeView, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, attributedText: AttributedString) async throws {
        try await delegate?.composeViewHasChangedTextAndMentions(view, discussionIdentifier: discussionIdentifier, attributedText: attributedText)
    }
    
    func actionTapped(_ view: ComposeView, for action: ComposeViewParameters.SortableAction, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, contactIdentifier: ObvTypes.ObvContactIdentifier?) async throws {
        try await delegate?.actionTapped(view, for: action, discussionIdentifier: discussionIdentifier, contactIdentifier: contactIdentifier)
    }
    
    func actionTapped(_ view: ComposeView, for action: ComposeViewParameters.UnsortableAction, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) async throws {
        try await delegate?.actionTapped(view, for: action, discussionIdentifier: discussionIdentifier)
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
    
    func userWantsToDeleteDraftAttachment(_ view: ComposeAttachmentView, attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws {
        try await delegate?.userWantsToDeleteDraftAttachment(view, attachmentIdentifier: attachmentIdentifier)
    }
    
    func userWantsToDeleteDraftAttachment(_ view: ComposeView, attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws {
        try await delegate?.userWantsToDeleteDraftAttachment(view, attachmentIdentifier: attachmentIdentifier)
    }
    
    func userWantsToDeleteDraftAttachment(_ view: ComposeLinkPreviewView, attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws {
        try await delegate?.userWantsToDeleteDraftAttachment(view, attachmentIdentifier: attachmentIdentifier)
    }
    
    func userWantsToAddAttachmentsToDraft(_ view: ComposeView, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, itemProviders: [NSItemProvider]) async throws {
        try await delegate?.userWantsToAddAttachmentsToDraft(view, discussionIdentifier: discussionIdentifier, itemProviders: itemProviders)
    }
    
}
