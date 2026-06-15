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


public struct ComposeViewDataSourceModel: Sendable, Equatable {
    
    let attributedText: AttributedString
    
    let discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier
    
    let emojiButtonSpecificToDiscussion: String?
    
    let contactOriginalNameIfOneToOne: String?
    
    let isDraftDeleted: Bool
    
    let contactIdentifier: ObvContactIdentifier?
    
    let isOneToOne: Bool
    
    let hasSomeExpiration: Bool
    
    let attachments: [ComposeAttachmentView.AttachmentIdentifier]
    
    let linkPreviewIdentifier: ComposeAttachmentView.AttachmentIdentifier?
    
    let audioAttachment: ComposeAttachmentView.AttachmentIdentifier?
    
    let replyTo: ObvAppTypes.ObvMessageAppIdentifier?
    
    /// Method to check if another view has to be displayed.
    public func hasInsertionToPerform(compareTo viewModel: ComposeViewDataSourceModel) -> Bool {
        if self.attachments.isEmpty && !viewModel.attachments.isEmpty {
            return true
        }
        
        if self.linkPreviewIdentifier == nil && viewModel.linkPreviewIdentifier != nil {
            return true
        }
        
        return false
    }
    
    public init(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier,
                isDraftDeleted: Bool,
                hasSomeExpiration: Bool,
                isOneToOne: Bool,
                attributedText: AttributedString = "",
                emojiButtonSpecificToDiscussion: String?,
                contactOriginalNameIfOneToOne: String?,
                contactIdentifier: ObvContactIdentifier?,
                attachments: [ComposeAttachmentView.AttachmentIdentifier],
                linkPreview: ComposeAttachmentView.AttachmentIdentifier?,
                audio: ComposeAttachmentView.AttachmentIdentifier?,
                replyTo: ObvAppTypes.ObvMessageAppIdentifier?) {
        self.discussionIdentifier = discussionIdentifier
        self.isDraftDeleted = isDraftDeleted
        self.isOneToOne = isOneToOne
        self.attributedText = attributedText
        self.emojiButtonSpecificToDiscussion = emojiButtonSpecificToDiscussion
        self.contactOriginalNameIfOneToOne = contactOriginalNameIfOneToOne
        self.contactIdentifier = contactIdentifier
        self.hasSomeExpiration = hasSomeExpiration
        self.attachments = attachments
        self.linkPreviewIdentifier = linkPreview
        self.audioAttachment = audio
        if let replyTo {
            if replyTo.discussionIdentifier == discussionIdentifier {
                self.replyTo = replyTo
            } else {
                assertionFailure("The replied-to message does not belong to the discussion corresponding to the discussionIdentifier, which is unexpected")
                self.replyTo = nil
            }
        } else {
            self.replyTo = nil
        }
    }
}

extension ComposeViewDataSourceModel {
    
    func isActionAvailable(for action: ComposeViewParameters.SortableAction) -> Bool {
        guard !isDraftDeleted else { return false }
        switch action {
        case .oneTimeEphemeralMessage,
                .shootPhotoOrMovie,
                .chooseImageFromLibrary,
                .choseFile:
            return true
        case .createPoll:
            return true
        case .shareLocation:
            return true
        case .scanDocument:
#if targetEnvironment(macCatalyst)
            return false
#else
            return true
#endif
        case .introduceThisContact:
            if isOneToOne {
                return contactIdentifier != nil
            } else {
                return false
            }
        case .pasteContent:
            return true
        }
    }
    
    func isActionAvailable(for action: ComposeViewParameters.UnsortableAction) -> Bool {
        guard !isDraftDeleted else { return false }
        switch action {
        case .composeMessageSettings:
            return true
        }
    }
    
    func actionTitle(for action: ComposeViewParameters.SortableAction) -> String {
        
        if case .introduceThisContact = action {
            if let contactName =  contactOriginalNameIfOneToOne {
                /// Override action.title to show the name of contact
                return String(localizedInThisBundle: "INTRODUCE_CONTACT_\(contactName)_TO")
                //return String.localizedStringWithFormat(NSLocalizedString("INTRODUCE_CONTACT_%@_TO", comment: ""), contactName)
            } else {
                return action.title
            }
        } else {
            return action.title
        }
        
    }
}

