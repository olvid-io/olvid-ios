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
import ObvSystemIcon


/// Displays a message sent by the owned identity.
///
/// The model is handed over by ``SingleDiscussionCellView``, which already streamed it: this view must not open a second stream for the same
/// message. When attachments, reactions and replies are implemented, they will be identified within the model and streamed by the views that
/// display them, each keyed by its own identifier.
public struct SentMessageCellView: View {

    public struct Model: Equatable, Sendable {

        /// What this message shows — its text and its attachments, or the one thing that takes their place. See ``MessageContent``.
        let content: MessageContent

        let statusIcon: StatusIcon
        let timestamp: Date

        /// The day this message opens, when it is the first of its day, and nil otherwise. See ``DateSeparatorView``.
        let dateSeparator: Date?

        /// Whether this message was forwarded from somewhere else rather than written here. See ``MessageForwardedBadgeView``.
        let isForwarded: Bool

        /// Whether this message says it was edited — already decided, the rule being neither this view's nor simply `isEdited`. See ``MessageEditedBadgeView``.
        let isShownAsEdited: Bool

        /// The message this one answers, and nil when it answers none. See ``MessageRepliedTo``.
        let repliedTo: MessageRepliedTo?

        /// That this message shows the reactions it has, and nil when it shows none. What those reactions *are* is not here — see ``ReactionsOfAMessage``.
        let reactions: ReactionsOfAMessage?


        /// What this message says about its own ephemerality — that it burns when read, and when it is destroyed. See
        /// ``TheEphemeralityOfAMessage`` and the countdown drawn from it, ``TheCountdownOfAnEphemeralMessage``.
        ///
        /// **Four facts rather than a decision**, deliberately: whether a countdown is shown at all depends on the time, so it is
        /// answered where it is asked afresh each second and not here.
        let ephemerality: TheEphemeralityOfAMessage

        public init(content: MessageContent, statusIcon: StatusIcon, timestamp: Date, dateSeparator: Date?, isForwarded: Bool, isShownAsEdited: Bool, repliedTo: MessageRepliedTo?, reactions: ReactionsOfAMessage?, ephemerality: TheEphemeralityOfAMessage) {
            self.content = content
            self.statusIcon = statusIcon
            self.timestamp = timestamp
            self.dateSeparator = dateSeparator
            self.isForwarded = isForwarded
            self.isShownAsEdited = isShownAsEdited
            self.repliedTo = repliedTo
            self.reactions = reactions
            self.ephemerality = ephemerality
        }

        /// The status indicator of a sent message.
        ///
        /// This module stays independent of the persistence layer, so the data source is the one resolving a persisted status into an icon. It must do
        /// so through the canonical mapping the app already owns, `PersistedMessageSent.MessageStatus.getSymbolIcon(messageHasMoreThanOneRecipient:)`,
        /// which is what the legacy screen uses. `none` reproduces the legacy special case: no indicator at all when the message has no recipient.
        public enum StatusIcon: Hashable, Sendable {
            case none
            case system(SystemIcon)
            case custom(CustomIcon)
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
        // Two stacks and not one, so that the air above the date is its own metric: the parts of a message are spaced by `gap`, and the date sits closer. See
        // ``MessageBubbleMetrics/gapAboveTheDateRow``.
        VStack(alignment: .trailing, spacing: MessageBubbleMetrics.gapAboveTheDateRow) {
            MessageItself(model: model, dataSource: dataSource, actions: actions, cellIdentifier: cellIdentifier, thePointerIsOverThisRow: thePointerIsOverThisRow)
                // What the context menu lifts: the message, and nothing the cell draws around it. See ``AMessageThatCanBeLifted``.
                .canBeLiftedOutOfTheDiscussion(cellIdentifier, showing: .sentMessage(model), hangingFrom: .trailing, dataSource: dataSource, actions: actions)
                // Every file of this message, dragged out at once. The interaction goes on the row's own cell rather than on this
                // view; see ``TheAttachmentsOfAMessageDraggedOut``, which says why, and why it is UIKit.
                .attachmentsCanBeDraggedOutOfTheDiscussion(model.content.everyFileAttached, cellIdentifier: cellIdentifier, dataSource: dataSource)
            theBottomOfTheCell
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        // **The row notices the pointer; the column places the button**, and the two are joined by the state below because this view contains both.
        // See ``TheRowThatNoticesThePointer`` for why the noticing cannot happen where the placing does.
        .modifier(TheRowThatNoticesThePointer(thePointerIsOverTheRow: $thePointerIsOverThisRow))
    }


    /// Everything a sent message draws, and nothing the cell draws around it — not its date, not its status, not its reactions.
    ///
    /// **A view of its own rather than a computed property of the cell, because it is drawn twice**: once in the transcript, and once more by
    /// ``MessageContextMenuOverlay`` as the copy that is lifted when the reader presses it. See ``ReceivedMessageCellView/MessageItself``, which says the same.
    struct MessageItself: View {

        let model: SentMessageCellView.Model
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
                TheCountdownOfAnEphemeralMessage(ephemerality: model.ephemerality)
                theColumn
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }


        private var theColumn: some View {
            VStack(alignment: .trailing, spacing: MessageBubbleMetrics.gap) {
                // Above the bubble, as in the legacy cell. Nothing precedes it here: only a message *received* can have messages missing before it.
                if model.isForwarded {
                    MessageForwardedBadgeView()
                }
                whatIsQuotedAndTheMessage
            }
            // Says *this one* when a reply, a search result, a notification or the gallery lands the reader here.
            //
            // **On the column and not on `MessageItself`**, which carries a greedy frame for the countdown beside it: applied there, the wash spanned the whole
            // width of the row and read as a highlighted row rather than a coloured bubble. Here it is the message's own width.
            .emphasisedWhenAJumpLandsOnIt(cellIdentifier, hangingFrom: .trailing)
            // The shortcut a pointer reveals. **Here and not on `MessageItself`**, for the reason the note above gives about the wash: this is the
            // message's own width, where that one is greedy, and a button aligned to a greedy frame sits at the far end of the cell.
            .modifier(TheShortcutThatAppearsOnHover(cellIdentifier: cellIdentifier, model: .sentMessage(model), side: .trailing, thePointerIsOverTheRow: thePointerIsOverThisRow))
            // **Pulled aside to reply to it**. Here for the same reason the two modifiers above are here: this is the message's own width, where
            // `MessageItself` is greedy, so a glyph revealed at the edge of a greedy frame would appear at the far end of the row rather than beside the bubble.
            .modifier(TheSwipeThatRepliesToAMessage(cellIdentifier: cellIdentifier, side: .trailing, dataSource: dataSource, actions: actions, model: .sentMessage(model)))
            // Nothing else in this view depends on the pointer, so the flag arrives as a plain value rather than through the environment.
        }


        /// The message this one answers, and the message itself over it.
        ///
        /// A stack of its own, and the **only** one on this screen with a negative spacing: the header is behind the message, which is what an overlap is for. The
        /// message comes second and is therefore drawn on top, and the two share the **trailing** edge, that being the edge a sent cell aligns to: the design draws
        /// the header the full width of the message, so the overlap is the whole of what says which of them is behind. See
        /// ``MessageRepliedToMetrics/overlapUnderTheBubble``.
        private var whatIsQuotedAndTheMessage: some View {
            VStack(alignment: .trailing, spacing: -MessageRepliedToMetrics.overlapUnderTheBubble) {
                if let repliedTo = model.repliedTo {
                    MessageRepliedToView(repliedTo: repliedTo, dataSource: dataSource, actions: actions)
                }
                theMessageItself
            }
        }


        private var theMessageItself: some View {
            VStack(alignment: .trailing, spacing: MessageBubbleMetrics.gap) {
                switch model.content {
                case .ordinary(let ordinary):
                    // The parts of one message are drawn as one block: where two of them meet, the corners take the small radius, so the column reads as a single
                    // thing with a spine on the trailing edge. Which part is first and which is last is answered from the model — see ``TheColumnOfPartsOfAMessage``.
                    let column = TheColumnOfPartsOfAMessage(ordinary, style: .sent)
                    MessageBodyView(textBody: ordinary.textBody, style: .sent, actions: actions)
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
                    MessageLocationView(location: location, style: .sent, dataSource: dataSource, actions: actions)
                case .poll(let poll):
                    MessagePollBubbleView(poll: poll, style: .sent, dataSource: dataSource, actions: actions)
                case .tapToRead(let message):
                    // Unreachable: only a *received* message can require the tap. Drawn rather than asserted, so that a sent cell would degrade to a covered
                    // message rather than to nothing at all.
                    MessageTapToReadView(message: message, style: .sent, dataSource: dataSource, actions: actions)
                case .wiped(let wiped):
                    MessageWipedView(wiped: wiped, style: .sent)
                }
            }
        }

    }


    /// The date row, and the reactions of this message to the **leading** side of it — the side away from the edge a sent cell aligns to, as in the legacy cell.
    ///
    /// A layout of its own rather than a stack, because the chip is taller than the row and rises into the bubble instead of pushing the date away from it. See
    /// ``TheDateRowAndItsReactions``, which is where that rule is written down.
    private var theBottomOfTheCell: some View {
        TheDateRowAndItsReactions(side: .sent) {
            dateAndStatus
            MessageReactionsChipView(reactions: model.reactions, dataSource: dataSource, actions: actions)
                // The chip overlaps the bubble, so it has to go with it — see ``HiddenWhileTheOverlayHasThisMessage``.
                .hiddenWhileTheOverlayHasThisMessage(cellIdentifier)
        }
    }


    /// The date, then the edited mark, then the status — the order of the legacy stack, and its 6pt gap.
    ///
    /// Aligned on the date's **baseline**, so that an icon taller than a line of `.caption` hangs below it rather than pushing the date down and taking the air above
    /// it with it. That was the other half of the space that read as too much under a bubble, and it grew with every icon the row gained.

    private var dateAndStatus: some View {
        HStack(alignment: .firstTextBaseline, spacing: MessageBubbleMetrics.gapWithinTheDateRow) {
            MessageTimestampView(timestamp: model.timestamp)
            if model.isShownAsEdited {
                MessageEditedBadgeView()
            }
            SentMessageStatusIconView(statusIcon: model.statusIcon)
        }
    }

}


/// The status indicator shown next to the date, under the bubble of a sent message.
///
/// As in the legacy screen, the indicator is **never** tinted by what it says: the icon itself, and not a colour, is what conveys a failure. It takes the colour of
/// the date it sits beside — see ``MessageTimestampView/foregroundColor``. The "edited" pencil that may precede it is ``MessageEditedBadgeView``.
private struct SentMessageStatusIconView: View {

    let statusIcon: SentMessageCellView.Model.StatusIcon

    private var image: Image? {
        switch statusIcon {
        case .none: return nil
        case .system(let systemIcon): return Image(systemIcon: systemIcon)
        case .custom(let customIcon): return Image(customIcon: customIcon)
        }
    }

    /// The indicator as a piece of *text* rather than as an image, for the reason ``MessageEditedBadgeView`` gives: an image is taller than the line it sits on, and
    /// what it adds is added above the baseline — which is seen as air between the bubble and the date.
    private var text: Text? {
        image.map(Text.init(_:))
    }

    /// The height this indicator takes, **whatever it happens to be showing**, so that a message changing status cannot change the height of its row.
    ///
    /// **Half a point, measured, and it is enough to make a discussion jump.** A sent message passes through several statuses in the second after it is sent, and each
    /// one is a different glyph with its own metrics — `checkmark`, then a circled one, then a double. As a `Text` the row is one line box tall, and that line box
    /// follows the glyph:
    ///
    /// ```
    /// 58.681  the last row is now 66.0pt tall
    /// 59.467  the last row is now 65.5pt tall     ← a status arrived
    /// 59.760  the last row is now 66.0pt tall     ← and another
    /// ```
    ///
    /// A row changing height makes the `List` re-measure, and doing that *while a message is settling* was seen to throw the whole layout away — the content
    /// collapsing from 2579pt to 1201, the offset clamped against it, and one frame of the top of the discussion shown for 65ms before it climbed back. Intermittent,
    /// because a re-measure does not always cost that. Measured on Mac Catalyst on 2026-08-15.
    ///
    /// So the indicator is given a height and stops having an opinion. It is **not** clipped to it — a frame does not clip — so nothing can be cut off; what the
    /// frame decides is only what the row is told. Scaled with the reader's text size, since the date beside it is.
    @ScaledMetric(relativeTo: .caption) private var heightItAlwaysTakes: CGFloat = 14

    /// Where this indicator's baseline sits, measured up from the bottom of the box above — **and not from the glyph**, which is the whole point.
    ///
    /// ``heightItAlwaysTakes`` stops the indicator having an opinion about its *height*. It does not stop it having one about its **baseline**: a `Text` in
    /// a fixed frame still carries a text baseline, and where that falls inside the box depends on the glyph's ascent and descent. The date row is an
    /// `HStack(alignment: .firstTextBaseline)`, so the stack shifts the box to line the baselines up, and the row's height moves with it. Baseline
    /// alignment turns an opinion about the baseline back into an opinion about the height.
    ///
    /// Measured while sending one message:
    ///
    /// ```
    /// 06.890  status hourglass → hare
    /// 06.891                            row 84.3333 → 84.5000     ← one sixth of a point
    /// 07.188  content 36386.3 → 36034.3                           ← 352 points, 297ms later
    /// ```
    ///
    /// **One sixth of a point of row became 352 points of content**, the collection view discarding its layout and re-estimating the discussion. A message
    /// *received* changed the last row's height not at all and caused no re-estimate, which is what makes this the cause rather than a correlate: a
    /// received message has no status indicator. The re-estimate is harmless on its own — the content falls 352.0 and the offset 352.3 — but it lands half a
    /// second after the message appears, which is exactly when Step 44b wants to scroll to it. Two writers for one event, and the transcript was seen
    /// travelling a thousand points.
    ///
    /// So the baseline is resolved from the **box**. Every term is a constant, so the answer is the same for `hourglass`, `hare`, `checkmark` and the
    /// circled and doubled ones, and the row cannot change height whatever the status does next. Scaled with the reader's text size, as the height beside it
    /// is. Three points, which decides where the glyph sits against the date and was looked at on a screen rather than only measured.
    @ScaledMetric(relativeTo: .caption) private var howFarTheBaselineSitsAboveTheBottom: CGFloat = 3

    var body: some View {
        text?
            .font(.caption)
            // The date's own colour, so the row reads as one line: see ``MessageTimestampView/foregroundColor``.
            .foregroundStyle(MessageTimestampView.foregroundColor)
            .frame(height: heightItAlwaysTakes)
            // **After the frame, deliberately**: the dimensions this reads are then the frame's, which are fixed, rather than the glyph's, which are not. See
            // ``howFarTheBaselineSitsAboveTheBottom``.
            // **Captured rather than read inside**, because `alignmentGuide`'s closure is `@Sendable` and this is a `@ScaledMetric` on the view, which the main
            // actor owns. The value is taken here, where the body is evaluated and the actor is not in doubt; a metric that only moves with the Dynamic Type
            // setting cannot move without the body being evaluated again anyway.
            .alignmentGuide(.firstTextBaseline) { [howFarTheBaselineSitsAboveTheBottom] dimensions in
                dimensions[.bottom] - howFarTheBaselineSitsAboveTheBottom
            }
    }

}


#if DEBUG

#Preview {
    // Same container and metrics as SingleDiscussionCellsListView, so a preview shows the real layout.
    ScrollView {
        LazyVStack(spacing: 8) {
            // The offset is a stable identity here only because this sample data is a constant that never reorders. Do not identify real data by its
            // position.
            ForEach(Array(SentMessageCellView.Model.sampleData.enumerated()), id: \.offset) { _, model in
                SentMessageCellView(model: model,
                                    cellIdentifier: .newMessagesMarker,
                                    dataSource: singleDiscussionCellViewDataSourceForPreviews,
                                    actions: singleDiscussionCellViewDataSourceForPreviews)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

#endif
