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
    func userWantsToSendDraft(_ view: ComposeView, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, attributedText: AttributedString) async throws
    
    /// Method called when the compose view needs to save the draft body automatically
    func composeViewHasChangedTextAndMentions(_ view: ComposeView, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, attributedText: AttributedString) async throws
    
    func actionTapped(_ view: ComposeView, for action: ComposeViewParameters.SortableAction, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, contactIdentifier: ObvTypes.ObvContactIdentifier?) async throws
    
    func actionTapped(_ view: ComposeView, for action: ComposeViewParameters.UnsortableAction, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) async throws
    
    //func userWantsToDeleteDraftFyleJoin(attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async
    
    func userDidTapOnDraftFyleJoinWithHardLink(_ view: ComposeAttachmentsView, at index: Int) throws
    
    func userDidRecordAudio(at url: URL, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) async throws
    
    func userWantstoRemoveReplyToMessage(_ view: ComposeReplyToView, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) async throws
    
    func userWantsToOpenEmojiPicker()
    
    func userWantsToDeleteDraftAttachment(_ view: ComposeAttachmentView, attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws
    func userWantsToDeleteDraftAttachment(_ view: ComposeView, attachmentIdentifier: ComposeAttachmentView.AttachmentIdentifier) async throws

    func userWantsToAddAttachmentsToDraft(_ view: ComposeView, discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, itemProviders: [NSItemProvider]) async throws

}
