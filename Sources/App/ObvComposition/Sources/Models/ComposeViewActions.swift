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
import ObvTypes
import ObvAppTypes

@MainActor
public protocol ComposeViewActions: AnyObject, ComposeLinkPreviewViewActions {
    
    /// method calls when user try to send current draft
    ///
    /// Asked by the shared state rather than by a view, and so it is the state that identifies itself. Every method here names what is asking; this one
    /// cannot name a `ComposeView`, because the state would then have to keep one in order to pass it — and a `ComposeView` holds the state back through
    /// its `@ObservedObject`. The two retained each other, and no shared state was ever deallocated on either discussion screen.
    func userWantsToSendDraft(_ sharedState: ComposeView.SharedState, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, attributedText: AttributedString) async throws

    /// Method called when the compose view needs to save the draft body automatically
    ///
    /// Identified by the shared state, for the reason given on `userWantsToSendDraft(_:discussionIdentifier:attributedText:)`.
    func composeViewHasChangedTextAndMentions(_ sharedState: ComposeView.SharedState, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, attributedText: AttributedString) async throws
    
    func actionTapped(_ view: ComposeView, for action: ComposeViewParameters.Action, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, contactIdentifier: ObvTypes.ObvContactIdentifier?) async throws
    
    //func userWantsToDeleteDraftFyleJoin(attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async
    
    func userDidTapOnDraftFyleJoinWithHardLink(_ view: ComposeAttachmentsView, at index: Int) throws
    
    func userDidRecordAudio(at url: URL, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) async throws
    
    func userWantstoRemoveReplyToMessage(_ view: ComposeReplyToView, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) async throws
    
    func userWantsToOpenEmojiPicker()

    /// Called when the reader picks, in the composition bar, the size this draft's photographs and videos are to be sent at.
    ///
    /// One choice for the whole draft, applying to attachments added after it as well as before. It is recorded whether or not the
    /// file for that size has been written yet — the menu never makes the reader wait — so the answer to this may be *yes, and it will
    /// take effect shortly*.
    func userWantsToChangeTheMediaFormatOfTheDraft(_ view: ComposeView, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, format: ObvMediaFormat) async throws
    
    func userWantsToDeleteDraftAttachment(_ view: ComposeAttachmentView, attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws
    func userWantsToDeleteDraftAttachment(_ view: ComposeView, attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws

    /// Identified by the shared state, for the reason given on `userWantsToSendDraft(_:discussionIdentifier:attributedText:)`.
    ///
    /// **What it returns is half of its job**, and the name says only the other half. What is handed over goes to one
    /// operation which decides, item by item, what becomes an attachment and what belongs in the text — and one item can be
    /// both: a pasted link is attached as a preview *and* leaves its URL in the text. What comes back is that second half,
    /// which the shared state inserts into the editor itself. See ``TextToPasteIntoTheDraft``.
    ///
    /// An empty array is the ordinary answer: most of what is pasted or dropped is attached and nothing is written.
    func userWantsToAddAttachmentsToDraft(_ sharedState: ComposeView.SharedState, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, itemProviders: [NSItemProvider]) async throws -> [TextToPasteIntoTheDraft]

}
