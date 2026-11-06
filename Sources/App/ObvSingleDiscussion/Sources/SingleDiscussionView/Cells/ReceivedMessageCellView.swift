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


/// Displays a message received from a contact.
///
/// The model is handed over by ``SingleDiscussionCellView``, which already streamed it: this view must not open a second stream for the same
/// message. When reactions and replies are implemented, they will be identified within the model and streamed by the views that
/// display them, each keyed by its own identifier.
public struct ReceivedMessageCellView: View {

    public struct Model: Equatable, Sendable {

        /// What this message shows — its text and its attachments, or the one thing that takes their place. See ``MessageContent``.
        let content: MessageContent

        let timestamp: Date

        /// The day this message opens, when it is the first of its day, and nil otherwise. See ``DateSeparatorView``.
        let dateSeparator: Date?

        /// Whoever sent this message, and whether they are to be named above it at all. See ``SenderOfAMessage``.
        let sender: SenderOfAMessage

        /// Whether this message reached the reader from somewhere else. See ``MessageForwardedBadgeView``.
        let isForwarded: Bool

        /// Whether this message says it was edited — already decided, the rule being neither this view's nor simply `isEdited`. See ``MessageEditedBadgeView``.
        let isShownAsEdited: Bool

        /// How many messages are missing above this one, and zero when none are. See ``MissedMessagesBubbleView``.
        let missedMessageCount: Int

        /// The message this one answers, and nil when it answers none. See ``MessageRepliedTo``.
        let repliedTo: MessageRepliedTo?

        /// That this message shows the reactions it has, and nil when it shows none — which is what the legacy cell says of a message the reader has still to ask to
        /// see. What those reactions *are* is not here; see ``ReactionsOfAMessage``.
        let reactions: ReactionsOfAMessage?


        /// What this message says about its own ephemerality — that it burns when read, how long it lasts once read, and when it is
        /// destroyed. See ``TheEphemeralityOfAMessage`` and the two views drawn from it: the countdown beside the bubble,
        /// ``TheCountdownOfAnEphemeralMessage``, and the terms in the date row of a message still to be tapped,
        /// ``WhatWillHappenWhenThisMessageIsRead``.
        ///
        /// **Five facts rather than a decision**, deliberately: whether a countdown is shown at all depends on the time, so it is
        /// answered where it is asked afresh each second and not here.
        let ephemerality: TheEphemeralityOfAMessage

        public init(content: MessageContent, timestamp: Date, dateSeparator: Date?, sender: SenderOfAMessage, isForwarded: Bool, isShownAsEdited: Bool, missedMessageCount: Int, repliedTo: MessageRepliedTo?, reactions: ReactionsOfAMessage?, ephemerality: TheEphemeralityOfAMessage) {
            self.content = content
            self.timestamp = timestamp
            self.dateSeparator = dateSeparator
            self.sender = sender
            self.isForwarded = isForwarded
            self.isShownAsEdited = isShownAsEdited
            self.missedMessageCount = missedMessageCount
            self.repliedTo = repliedTo
            self.reactions = reactions
            self.ephemerality = ephemerality
        }

    }

    private let model: Model

    /// Which row this is, which the message needs for one thing only: to say that it is the one being pressed, and to be recognised by the overlay that lifts it.
    /// See ``AMessageThatCanBeLifted``.
    private let cellIdentifier: SingleDiscussionView.CellIdentifier

    /// Handed down so that the images of this message can ask for themselves, one by one and at their own pace. Their pictures are deliberately not part of
    /// ``Model``: a picture arriving must update one image and not the message, whose every change costs a pass over the whole discussion.
    private let dataSource: any SingleDiscussionCellViewDataSource

    /// Handed down for the same reason as the data source: an attachment of this message may be one the reader has to ask for, and asking is not something a
    /// data source does.
    private let actions: any SingleDiscussionCellViewActions

    /// Whether the pointer is anywhere on this row, and it lives here because this view holds both the row and the column: the row notices, the
    /// column places the button. Always false where there is no pointer, nothing writing it off Catalyst.
    @State private var thePointerIsOverThisRow = false

    public init(model: Model, cellIdentifier: SingleDiscussionView.CellIdentifier, dataSource: any SingleDiscussionCellViewDataSource, actions: any SingleDiscussionCellViewActions) {
        self.model = model
        self.cellIdentifier = cellIdentifier
        self.dataSource = dataSource
        self.actions = actions
    }

    public var body: some View {
        // The sender above, and the message inset by the column their picture is in — as in the legacy cell, where that inset is applied to every received cell of
        // a group discussion and not only to the ones that show a name, so that the bubbles of a run line up under the name heading it.
        //
        // What the inset costs, and it is the one measured departure of this step: a bubble is capped at 80% of the width *offered to it*, so a received bubble in a
        // group is at most 80% of what is left of the row rather than 80% of the row, which is some 27pt narrower than the legacy screen allows. Only the longest
        // bubbles reach it.
        VStack(alignment: .leading, spacing: 0) {
            if case .shown(let sender) = model.sender {
                MessageSenderView(sender: sender, dataSource: dataSource, actions: actions)
            }
            messageAndItsDate
                .padding(.leading, model.sender.widthOfTheColumnOfThePicture)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // **The row notices the pointer; the column places the button**. See ``TheRowThatNoticesThePointer`` for why the noticing cannot happen
        // where the placing does.
        .modifier(TheRowThatNoticesThePointer(thePointerIsOverTheRow: $thePointerIsOverThisRow))
    }


    /// Everything but the sender: the message, and the date under it — the two spaced by ``MessageBubbleMetrics/gapAboveTheDateRow`` rather than by the gap that
    /// separates the parts of the message itself.
    private var messageAndItsDate: some View {
        VStack(alignment: .leading, spacing: MessageBubbleMetrics.gapAboveTheDateRow) {
            MessageItself(model: model, dataSource: dataSource, actions: actions, cellIdentifier: cellIdentifier, thePointerIsOverThisRow: thePointerIsOverThisRow)
                // What the context menu lifts: the message, and nothing the cell draws around it. See ``AMessageThatCanBeLifted``.
                .canBeLiftedOutOfTheDiscussion(cellIdentifier, showing: .receivedMessage(model), hangingFrom: .leading, dataSource: dataSource, actions: actions)
                // Every file of this message, dragged out at once. The interaction goes on the row's own cell rather than on this
                // view; see ``TheAttachmentsOfAMessageDraggedOut``, which says why, and why it is UIKit.
                .attachmentsCanBeDraggedOutOfTheDiscussion(model.content.everyFileAttached, cellIdentifier: cellIdentifier, dataSource: dataSource)
            theBottomOfTheCell
        }
    }


    /// The date row, and the reactions of this message to the **trailing** side of it — the side away from the edge a received cell aligns to, as in the legacy cell.
    ///
    /// A layout of its own rather than a stack, because the chip is taller than the row and rises into the bubble instead of pushing the date away from it. See
    /// ``TheDateRowAndItsReactions``, which is where that rule is written down.
    private var theBottomOfTheCell: some View {
        TheDateRowAndItsReactions(side: .received) {
            dateAndEditedMark
            MessageReactionsChipView(reactions: model.reactions, dataSource: dataSource, actions: actions)
                // The chip overlaps the bubble, so it has to go with it — see ``HiddenWhileTheOverlayHasThisMessage``.
                .hiddenWhileTheOverlayHasThisMessage(cellIdentifier)
        }
    }


    /// Everything a received message draws, and nothing the cell draws around it — not its sender, not its date, not its reactions.
    ///
    /// **A view of its own rather than a computed property of the cell, because it is drawn twice**: once in the transcript, and once more by
    /// ``MessageContextMenuOverlay`` as the copy that is lifted when the reader presses it. Two renderings of one definition cannot drift apart, where a copy
    /// written in the overlay would drift the first time a bubble changed.
    struct MessageItself: View {

        let model: ReceivedMessageCellView.Model
        let dataSource: any SingleDiscussionCellViewDataSource
        let actions: any SingleDiscussionCellViewActions

        /// Which row this is, so that a jump landing here can say so — see ``TheMessageAJumpLandedOn``. **Nothing by default**, which is what the copy the context
        /// menu lifts passes: that copy is not a row, and a jump has nothing to say about it.
        var cellIdentifier: SingleDiscussionView.CellIdentifier? = nil

        /// Whether the pointer is on the row this message is in. **False by default**, which is what the copy the context menu lifts passes: it is
        /// not a row, and nothing hovers it.
        var thePointerIsOverThisRow: Bool = false

        /// The message's own column, and the countdown of its ephemerality beside it.
        ///
        /// **The countdown sits towards the middle of the screen** — on the leading side of a message sent, the trailing side of one
        /// received — which is where the legacy screen puts it, and it is inside `MessageItself` rather than beside it so that it
        /// travels with the message when the context menu lifts it, as legacy's does.
        ///
        /// A message with nothing ephemeral about it is **unaffected**: the countdown returns a `Group` with nothing in it, which
        /// contributes neither a subview nor the stack's spacing. See ``MessageBodyView``, where that distinction cost 12pt once.
        ///
        /// The greedy frame moved out here from the column, where it would have pushed the countdown to the far edge of the screen
        /// instead of keeping it beside the bubble.
        var body: some View {
            HStack(alignment: .top, spacing: MessageBubbleMetrics.gapWithinTheDateRow) {
                theColumn
                TheCountdownOfAnEphemeralMessage(ephemerality: model.ephemerality)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }


        private var theColumn: some View {
            VStack(alignment: .leading, spacing: MessageBubbleMetrics.gap) {
                // At the very top of the cell, in the legacy order: what is missing before this message, then where it came from.
                if model.missedMessageCount > 0 {
                    MissedMessagesBubbleView(count: model.missedMessageCount, actions: actions)
                }
                if model.isForwarded {
                    MessageForwardedBadgeView()
                }
                whatIsQuotedAndTheMessage
            }
            // Says *this one* when a reply, a search result, a notification or the gallery lands the reader here.
            //
            // **On the column and not on `MessageItself`**, which carries a greedy frame for the countdown beside it: applied there, the wash spanned the whole
            // width of the row and read as a highlighted row rather than a coloured bubble. Here it is the message's own width.
            .emphasisedWhenAJumpLandsOnIt(cellIdentifier, hangingFrom: .leading)
            // The shortcut a pointer reveals. On the column and not on `MessageItself`, which is greedy: see `SentMessageCellView`.
            .modifier(TheShortcutThatAppearsOnHover(cellIdentifier: cellIdentifier, model: .receivedMessage(model), side: .leading, thePointerIsOverTheRow: thePointerIsOverThisRow))
            // **Pulled aside to reply to it**. Here for the same reason the two modifiers above are here: this is the message's own width, where
            // `MessageItself` is greedy, so a glyph revealed at the edge of a greedy frame would appear at the far end of the row rather than beside the bubble.
            .modifier(TheSwipeThatRepliesToAMessage(cellIdentifier: cellIdentifier, side: .leading, dataSource: dataSource, actions: actions, model: .receivedMessage(model)))
        }


        /// The message this one answers, and the message itself over it.
        ///
        /// A stack of its own, and the **only** one on this screen with a negative spacing: the header is behind the message, which is what an overlap is for. The
        /// message comes second and is therefore drawn on top, and the two share the leading edge, that being the edge a received cell aligns to: the design draws
        /// the header the full width of the message, so the overlap is the whole of what says which of them is behind. See
        /// ``MessageRepliedToMetrics/overlapUnderTheBubble``.
        private var whatIsQuotedAndTheMessage: some View {
            VStack(alignment: .leading, spacing: -MessageRepliedToMetrics.overlapUnderTheBubble) {
                if let repliedTo = model.repliedTo {
                    MessageRepliedToView(repliedTo: repliedTo, dataSource: dataSource, actions: actions)
                }
                theMessageItself
            }
        }


        private var theMessageItself: some View {
            VStack(alignment: .leading, spacing: MessageBubbleMetrics.gap) {
                switch model.content {
                case .ordinary(let ordinary):
                    // As in the sent cell, and mirrored: the spine of a received message is on its **leading** edge. See ``TheColumnOfPartsOfAMessage``.
                    let column = TheColumnOfPartsOfAMessage(ordinary, style: .received)
                    MessageBodyView(textBody: ordinary.textBody, style: .received, actions: actions)
                        .drawnAsPartOfTheMessage(column.corners(of: .body))
                    MessageLinkPreviewView(linkPreview: ordinary.linkPreview, dataSource: dataSource, actions: actions)
                        .drawnAsPartOfTheMessage(column.corners(of: .linkPreview))
                    MessageGifView(gif: ordinary.gif, dataSource: dataSource, actions: actions)
                        .drawnAsPartOfTheMessage(column.corners(of: .gif))
                    MessageImagesView(images: ordinary.images, dataSource: dataSource, actions: actions)
                        .drawnAsPartOfTheMessage(column.corners(of: .images))
                    MessageVideoView(video: ordinary.video, dataSource: dataSource, actions: actions)
                        .drawnAsPartOfTheMessage(column.corners(of: .video))
                    MessageDocumentPreviewView(document: ordinary.document, dataSource: dataSource, actions: actions)
                        .drawnAsPartOfTheMessage(column.corners(of: .document))
                    MessageAttachmentCardsView(cards: ordinary.cards, dataSource: dataSource, actions: actions)
                        .drawnAsPartOfTheMessage(column.corners(of: .cards))
                    MessageAudioPlayerView(audio: ordinary.audio, dataSource: dataSource, actions: actions)
                        .drawnAsPartOfTheMessage(column.corners(of: .audio))
                case .location(let location):
                    MessageLocationView(location: location, style: .received, dataSource: dataSource, actions: actions)
                case .poll(let poll):
                    MessagePollBubbleView(poll: poll, style: .received, dataSource: dataSource, actions: actions)
                case .tapToRead(let message):
                    MessageTapToReadView(message: message, style: .received, dataSource: dataSource, actions: actions)
                case .wiped(let wiped):
                    MessageWipedView(wiped: wiped, style: .received)
                }
            }
        }

    }


    /// The date, the edited mark beside it, and — on a message the reader has still to tap — what tapping it will cost them. All three aligned on the date's
    /// **baseline**, so that an icon taller than a line of `.caption` hangs below it rather than pushing the date away from the bubble.
    ///
    /// The order is the legacy cell's, which adds its `ephemeralityInformationsView` to `bottomHorizontalStack` after the date. It goes **inside** this row rather
    /// than beside it in ``TheDateRowAndItsReactions``, whose contract is two subviews — and legacy agrees, pinning its reactions chip to the whole of the row this
    /// chip is part of, so a message that is both waiting to be tapped and reacted to keeps the two apart.
    private var dateAndEditedMark: some View {
        HStack(alignment: .firstTextBaseline, spacing: MessageBubbleMetrics.gapWithinTheDateRow) {
            MessageTimestampView(timestamp: model.timestamp)
            if model.isShownAsEdited {
                MessageEditedBadgeView()
            }
            WhatWillHappenWhenThisMessageIsRead(ephemerality: model.ephemerality)
        }
    }

}


#if DEBUG

/// In a group discussion, where a run of messages from one person is named once and the rest of it keeps the column of their picture empty.
#Preview {
    ReceivedMessageCellsForPreviews(models: ReceivedMessageCellView.Model.sampleData)
}


/// In a one-to-one discussion, where the sender is never in doubt and nothing is kept aside for a picture.
#Preview {
    ReceivedMessageCellsForPreviews(models: ReceivedMessageCellView.Model.sampleDataInAOneToOneDiscussion)
}


private struct ReceivedMessageCellsForPreviews: View {

    let models: [ReceivedMessageCellView.Model]

    var body: some View {
        // Same container and metrics as SingleDiscussionCellsListView, so a preview shows the real layout.
        ScrollView {
            LazyVStack(spacing: 8) {
                // The offset is a stable identity here only because this sample data is a constant that never reorders. Do not identify real data by its
                // position.
                ForEach(Array(models.enumerated()), id: \.offset) { _, model in
                    ReceivedMessageCellView(model: model,
                                            cellIdentifier: .newMessagesMarker,
                                            dataSource: singleDiscussionCellViewDataSourceForPreviews,
                                            actions: singleDiscussionCellViewDataSourceForPreviews)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

}

#endif
