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

    /// The size this draft's photographs and videos will be sent at, and what each size weighs — or nil when the draft holds neither,
    /// which is what the composition bar reads as "do not offer a size to choose".
    let mediaFormatSelection: MediaFormatSelection?

    /// What the size menu draws.
    ///
    /// **Media and not photographs** — see ``ComposeMediaFormatButton``, which this is the model for, and which carries the note about
    /// why the name was changed.
    public struct MediaFormatSelection: Sendable, Equatable {

        /// The size currently chosen. Always one of the four, a draft that has never been asked answering with the app-wide default.
        public let selected: ObvMediaFormat

        /// What the whole draft weighs at each size, for the sizes at which every attachment has a weight.
        ///
        /// A size is **absent** while any of the draft's attachments has no weight at it — a partial total would be a number that means
        /// nothing and that shrinks as the rest arrive. The menu draws the absent ones as being prepared, and picking one is allowed
        /// anyway: the choice is recorded and takes effect when the files land.
        public let totalByteCountForFormat: [ObvMediaFormat: Int64]

        /// The sizes whose total includes an estimate.
        ///
        /// A video is exported only at the size chosen, an export costing tens of seconds, so its other sizes are estimated from the
        /// clip's duration. The menu marks those totals as approximate.
        public let formatsWhoseWeightIsAnEstimate: Set<ObvMediaFormat>

        public init(selected: ObvMediaFormat, totalByteCountForFormat: [ObvMediaFormat: Int64], formatsWhoseWeightIsAnEstimate: Set<ObvMediaFormat>) {
            self.selected = selected
            self.totalByteCountForFormat = totalByteCountForFormat
            self.formatsWhoseWeightIsAnEstimate = formatsWhoseWeightIsAnEstimate
        }

    }


    /// Whether going from this model to that one **may** make the bar a different height, in either direction.
    ///
    /// The sibling of ``hasInsertionToPerform(compareTo:)``, which asks a one-directional question about insertion only. A host that cannot afford an
    /// *animated* change of the bar's height needs the symmetric answer — see `ComposeView.theBarsHeightMayBeAnimated`.
    ///
    /// ## Answered by exclusion, and the name says *may* for that reason
    ///
    /// **The first version of this named the fields that do change the height, and shipped without two of them.** It tested ``attachments`` and
    /// ``linkPreviewIdentifier``; ``replyTo`` and ``audioAttachment`` change the bar's height just as surely, were not tested, and so were answered
    /// *no height change* — whereupon the update went inside `withAnimation`, and a `safeAreaInset` answers an animated height change by
    /// reparameterising the scroll view it sits under.
    ///
    /// What that cost, measured on 2026-08-24: tapping Reply and sending from the middle of a discussion ran a **10,086pt** scroll inside a viewport
    /// of 403pt, and left the sent message 401pt below the bottom of the screen for fifteen seconds; cancelling a reply at the end of a discussion
    /// left the last message behind the composition bar and kept it there. Both were fixed by what follows.
    ///
    /// **So the list is inverted.** What is enumerated below is what *cannot* move the bar, and everything else — including any property added to this
    /// struct after this was written — is assumed to. A new field is then safe by default rather than dangerous by default, which is the whole of the
    /// change: the failure mode of the old shape was silent, and the failure mode of this one is a lost animation.
    ///
    /// The same mistake was made three times about the *inset*: **a list of parts cannot be known to be complete**. This
    /// predicate was written to fix that class of bug and reproduced it, which is the reason for stating the rule here as well.
    ///
    /// **``attributedText`` is deliberately *not* excluded.** A draft growing a line makes the bar taller, so a change of the text may change the
    /// height and is treated as though it does. On a host that permits animated height changes nothing here applies at all; on the one that does not,
    /// the bar takes a draft's new line as a step rather than as an animation, which is what that host asked for.
    ///
    /// ## Built through the initialiser, so that a new field cannot be forgotten
    ///
    /// The comparison could copy the harmless fields onto a `var` copy of `self`, and a property added later would then simply not be copied and
    /// would count as possibly-height-changing — safe, but silently so. Going through ``init(discussionIdentifier:isDraftDeleted:hasSomeExpiration:isOneToOne:attributedText:emojiButtonSpecificToDiscussion:contactOriginalNameIfOneToOne:contactIdentifier:attachments:linkPreview:audio:replyTo:)``
    /// instead means a new stored property **stops this file compiling** until somebody says which side of the question it falls on. A loud failure
    /// beats a safe-but-silent one when the thing being guarded against is precisely a field nobody remembered.
    public func mayChangeTheHeightOfTheBar(comparedTo viewModel: ComposeViewDataSourceModel) -> Bool {

        // The fields that provably cannot alter the bar's height are taken from `viewModel`; everything else is kept from `self`. If what comes out
        // still differs from `viewModel`, something that might have altered the height has changed.
        //
        // `discussionIdentifier` and `isDraftDeleted` are **not** among the harmless: a different discussion is a different bar, and a deleted draft
        // empties one. `replyTo` is validated against the discussion inside the initialiser, which is the other reason to leave the identifier alone.
        let asIfOnlyTheHarmlessFieldsDiffered = ComposeViewDataSourceModel(
            discussionIdentifier: self.discussionIdentifier,
            isDraftDeleted: self.isDraftDeleted,
            hasSomeExpiration: viewModel.hasSomeExpiration,
            isOneToOne: viewModel.isOneToOne,
            attributedText: self.attributedText,
            emojiButtonSpecificToDiscussion: viewModel.emojiButtonSpecificToDiscussion,
            contactOriginalNameIfOneToOne: viewModel.contactOriginalNameIfOneToOne,
            contactIdentifier: viewModel.contactIdentifier,
            attachments: self.attachments,
            linkPreview: self.linkPreviewIdentifier,
            audio: self.audioAttachment,
            replyTo: self.replyTo,
            // Harmless: the size menu's button lives **inside** the attachments row, whose height `ComposeView` already pins at 125pt,
            // so neither changing the size nor a weight arriving can alter what the bar reports. Classing it the other way would
            // suppress the attachment panel's animation every time a photograph finished being written, for nothing.
            mediaFormatSelection: viewModel.mediaFormatSelection)

        return asIfOnlyTheHarmlessFieldsDiffered != viewModel
    }

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
                replyTo: ObvAppTypes.ObvMessageAppIdentifier?,
                mediaFormatSelection: MediaFormatSelection?) {
        self.mediaFormatSelection = mediaFormatSelection
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
    
    func isActionAvailable(for action: ComposeViewParameters.Action) -> Bool {
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
        case .pasteContent,
                .composeMessageSettings:
            return true
        }
    }
    
    /// The title the card shows for an action.
    ///
    /// Only ``ComposeViewParameters/Action/introduceThisContact`` differs from the action's own title, and it
    /// differs for a measured reason: given the bare word *Introduce*, translators read it **reflexively** — seven of the
    /// thirteen locales had rendered it as "introduce yourself" before this was noticed. Naming the person removes the
    /// ambiguity in every language at once. The row is the least used one on the card and its label wraps rather than
    /// truncates, so a long name costs a second line there and nothing else.
    func actionTitle(for action: ComposeViewParameters.Action) -> String {
        switch action {
        case .introduceThisContact:
            guard let contactOriginalNameIfOneToOne else { return action.title }
            return String(localizedInThisBundle: "INTRODUCE_CONTACT_\(contactOriginalNameIfOneToOne)")
        default:
            return action.title
        }
    }
}

