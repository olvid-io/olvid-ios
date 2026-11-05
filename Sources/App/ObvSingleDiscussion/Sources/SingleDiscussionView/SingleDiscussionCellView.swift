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
import ObvDesignSystem
import ObvTypes
import ObvPollFeature


// MARK: - SingleDiscussionCellView's data source

@MainActor
/// What a cell of this screen asks about what it shows.
///
/// `ObvAvatarViewDataSource` is among these because a cell draws people: the mark on a shared location is the sharer's avatar, and so is the sender's picture above
/// a message in a group discussion. It is a photo cache belonging to the app rather than to this screen, so an implementation is expected to forward to whichever
/// one the app already keeps, and not to build a second.
///
/// `ReactionsCountViewDataSource` is among them for a related reason: the reactions of a message reach a cell through the very stream the sheet that lists who
/// reacted already uses. See ``ReactionsOfAMessage``.
public protocol SingleDiscussionCellViewDataSource: Sendable, AttachmentProgressDataSource, AnimatedImageDataSource, AudioPlaybackDataSource, LinkPreviewDataSource, LocationDataSource, PollDataSource, ObvAvatarViewDataSource, ReactionsCountViewDataSource {

    func getAsyncStreamOfSingleDiscussionCellViewModel(cellIdentifier: SingleDiscussionView.CellIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<SingleDiscussionCellView.Model>)

    func finishAsyncStreamOfSingleDiscussionCellViewModel(cellIdentifier: SingleDiscussionView.CellIdentifier, streamUUID: UUID)

    /// The model of a cell if one is already known, so that a cell can be shown with its content instead of a skeleton while its own stream starts.
    ///
    /// Expected to be a lookup and nothing else — no fetch, no I/O — as it is called while building the body of the list. Returning nil is always safe: the
    /// cell then shows a skeleton until its stream produces a model, which is what happened for every cell before this existed.
    ///
    /// It exists because a cell that is released and re-created loses the model its stream had given it, and rows are released as the content moves — so a
    /// message a screen has already displayed would flash back to a skeleton for a few milliseconds. Notably that happened to the *previous* last message every
    /// time a new one arrived.
    func cachedModelOfSingleDiscussionCellView(cellIdentifier: SingleDiscussionView.CellIdentifier) -> SingleDiscussionCellView.Model?

    /// Asks for the models of the cells that are *about* to be displayed, so that
    /// ``cachedModelOfSingleDiscussionCellView(cellIdentifier:)`` can answer for them by the time they are created.
    ///
    /// A hint, and not a request: it returns immediately, it cannot fail, and nothing is promised about when — or whether — a given model becomes available. The
    /// caller reads the result, if any, through the synchronous lookup above.
    ///
    /// It exists because a cell that is created *without* a model sizes itself twice: it shows a skeleton of a fixed, one-line height, and becomes as tall as its
    /// message a few milliseconds later. On a list of cells whose height is not known in advance that second sizing moves everything around it, which is seen, on
    /// scrolling up through a discussion, as the content jumping. Verified by seeding every cell at entry instead: the jumps disappear entirely.
    ///
    /// Two things are expected of an implementation, and neither is expressible in the signature:
    ///
    /// - **It must not block the caller**, which calls this while the list is being scrolled, from the main actor. The work belongs on another thread.
    /// - **It must be cheap to call repeatedly with overlapping windows**, since it is driven by the scroll view reporting what it shows. Discarding the
    ///   identifiers whose models are already known is what makes that hold.
    ///
    /// The identifiers are given in the order they are displayed, so that an implementation may honour them in that order. The caller is expected to ask for
    /// rather more than what is strictly visible: a lazy container creates its cells slightly beyond the visible area, so a window that covers no more than what
    /// can be seen is already too late.
    func prefetchModelsOfSingleDiscussionCellViews(cellIdentifiers: [SingleDiscussionView.CellIdentifier])

    /// What this message offers when the reader presses it — the entries of its context menu.
    ///
    /// **Synchronous, and asked at press time rather than carried on the model.** Three of the rules behind the answer
    /// assert the main thread and want the *view* context, two of them simulating the operation on a child context; this
    /// screen builds its models on a background context. See ``WhatAMessageOffers``, which sets out what that would have
    /// cost. Synchronous because the answer is needed to draw a menu within the gesture that asked for it.
    ///
    /// Expected to be cheap enough for one call per press — it is not cheap enough for one call per message, which is
    /// the whole point.
    ///
    /// An empty answer means a message that offers nothing, and no menu is drawn at all.
    func whatTheMessageOffers(cellIdentifier: SingleDiscussionView.CellIdentifier) -> WhatAMessageOffers

    /// What the reader may react with, and what they have already put on this message — see ``TheEmojisOnOffer``.
    ///
    /// **Asked at press time, beside ``whatTheMessageOffers(cellIdentifier:)``**, and expected to be as cheap: a read of
    /// the reader's settings and one look at the message's own reactions. Never asked per message on screen.
    ///
    /// A separate method rather than more fields on `WhatAMessageOffers` because neither of the two things it carries is a
    /// property of the message alone.
    func whatTheReaderMayReactWith(cellIdentifier: SingleDiscussionView.CellIdentifier) -> TheEmojisOnOffer

    /// The image of an attachment, decoded at the size it is to be drawn at.
    ///
    /// Asked for by the sha256 of the **file** rather than by the attachment showing it, so that the same picture attached to two messages is decoded once.
    /// The size is part of the request rather than something the caller shrinks afterwards: a full photograph decoded for a 200pt bubble wastes tens of
    /// megabytes per message.
    ///
    /// `pixelSize`, not points — the caller multiplies by its own `displayScale`. A `CGImage`, not a `UIImage`: it is already decoded, so nothing lazy can happen on the main thread
    /// while the list scrolls; it is `Sendable`; and it is the same type on every Apple platform. Orientation is not lost — the image is *rendered* upright
    /// at decode time.
    ///
    /// **A stream, not a single answer**, because one attachment legitimately produces more than one image: a file still on its way may have a small blurred
    /// blob worth showing until the file itself replaces it. An implementation may yield nothing at all — an attachment nobody has asked for yet is the
    /// ordinary case — and the view then keeps a placeholder already the size the image will have.
    ///
    /// **It stays open**, an attachment still being fetched having nothing at first, something blurred once its thumbnail lands, and its picture when that
    /// arrives — none of which reaches the message's model. Unlike the streams of models above it takes no `streamUUID` and has nothing to finish it: a
    /// caller that loses interest cancels the task it is iterating in, and the implementation tears down whatever it was watching.
    ///
    /// The whole attachment is passed rather than its hash alone, because the two identify different things: the **join** is what has to be watched, and the
    /// **file** is what the answer is cached under. It yields an ``AttachmentState`` rather than an image because an attachment is not merely present or
    /// absent: it may be waiting for the reader to ask for it, asked for and unanswered, or on its way. The image is one of those states.
    func getAsyncStreamOfStateForAttachment(_ attachment: MessageAttachment, pixelSize: CGSize) -> AsyncStream<AttachmentState>

    /// The image of an attachment if one has already been decoded at that size, so that it can be shown on the frame the view appears on.
    ///
    /// Expected to be a lookup and nothing else — no fetch, no decode, no I/O — as it is called while building a body. Returning nil is always safe: the view
    /// then shows its placeholder until the stream above produces something, which is what happened before this existed.
    ///
    /// It exists because a row scrolled out of the list and back is created afresh, with no image, and would show a grey square for a frame or two before its
    /// stream answered — on a photograph that had already been decoded. The same reason ``cachedModelOfSingleDiscussionCellView(cellIdentifier:)`` exists.
    ///
    /// Takes the attachment and not merely its file, because it must answer for *this* attachment: an image kept from an earlier message must not be handed
    /// back for one whose file has still to be downloaded, which would show the reader a photograph that is not there.
    func cachedImageForAttachment(_ attachment: MessageAttachment, pixelSize: CGSize) -> CGImage?

    /// What a recording *is*: its shape, and how long it lasts.
    ///
    /// **A single answer, and not a stream.** Unlike an image, a waveform has no cruder version worth showing while the good one is prepared; unlike a download's
    /// progress, neither of these changes once known. So there is nothing for a stream to carry after the first value.
    ///
    /// The two arrive together because they come from one reading of one file, and because a view needs both before anything is played: the shape to draw, and the
    /// length to turn a position the reader drags to into a time to show them.
    ///
    /// Nil while there is nothing to answer with — the file not being here yet, or the recording being unreadable. The view reserves its space either way, so
    /// nothing moves when the answer arrives.
    ///
    /// Reading a recording to measure it is real work, proportional to its length, and belongs off the main actor with the result remembered: what reaches the
    /// view is ready to draw, exactly as an image is.
    func recordingForAudioAttachment(_ attachment: MessageAttachment, numberOfSamples: Int) async -> AudioRecording?

    /// The file this attachment **is**, on disk, for handing to another application, dragging an attachment out of the discussion.
    ///
    /// A *hardlink*, which is what the app makes of a stored file so that it can be given away without being copied and without exposing where
    /// it really lives. The legacy screen holds them on its cell already; this one asks, which is why this is `async` — and why a drag resolves
    /// it **lazily**, when something accepts the drop rather than when the gesture begins. See ``getTheFileOfAnAttachment(_:)``.
    ///
    /// Throws when there is no file to give: an attachment still downloading, or one whose message has been wiped since. A drag of nothing is
    /// better refused than answered with an empty file.
    func getTheFileOfAnAttachment(_ attachment: MessageAttachment) async throws -> URL

    /// A picture of this attachment at **whatever size one has already been decoded at**, or nil if none has — and never a decode.
    ///
    /// The one caller cannot name a size: a drag out of the discussion has to show what it is carrying in the instant the drag begins, at 50 by
    /// 50, which is a size nothing here displays — so `cachedImageForAttachment(_:pixelSize:)`, keyed on the exact size, can only miss. An
    /// attachment nobody has looked at yet is carried as an icon instead. See ``TheAttachmentsOfAMessageDraggedOut``.
    func cachedImageOfAnySizeForAttachment(_ attachment: MessageAttachment) -> CGImage?

}


public extension SingleDiscussionCellViewDataSource {

    /// Ignoring the hint is a valid implementation, which is why there is a default one: the cells then show skeletons until their own streams produce their
    /// models, exactly as they did before any of this existed. Previews rely on this.
    func prefetchModelsOfSingleDiscussionCellViews(cellIdentifiers: [SingleDiscussionView.CellIdentifier]) {}

}


// MARK: - SingleDiscussionCellView's actions

/// What can be asked of a file, and answered without showing anything: a download resumed, a recording played.
///
/// Its own protocol because it is the part a **data source** can implement — everything here ends at the engine or at the audio player, and needs no view controller.
/// The rest of ``SingleDiscussionCellViewActions`` does: see there.
@MainActor
public protocol SingleDiscussionAttachmentActions: AnyObject {

    /// Carries out what the reader asked of an attachment.
    ///
    /// One method with the action as a value, rather than one method per action: a case names what it does exactly as a method name would, while making it
    /// something that can be logged, tested and passed on — and an implementation is told by the compiler when a case is added.
    func userWantsToActOnAttachment(_ attachment: MessageAttachment, action: AttachmentAction) async

    /// Carries out what the reader asked of a recording. Its own method and its own enum, for the reason ``AudioAction`` gives.
    func userWantsToActOnAudioAttachment(_ attachment: MessageAttachment, action: AudioAction) async

}


/// Everything the cells of this screen ask of their owner.
///
/// It is split in two on purpose. What a file needs done ends at the engine, so a data source can answer it — hence
/// ``SingleDiscussionAttachmentActions``. What a **place** needs done has to be *presented*: a map inside the app, a maps application, or the alert that
/// chooses between several of them. That is not something a data source can do, and it is why an implementation of this protocol is expected to be, or to be held
/// by, something that has a view controller.
@MainActor
public protocol SingleDiscussionCellViewActions: SingleDiscussionAttachmentActions {

    /// Carries out what the reader asked of a place.
    ///
    /// The whole ``LocationInMessage`` is handed over, and not merely the coordinate, because an implementation has to choose *how* to honour the request: which map
    /// can be opened depends on whether the place is being shared and on what this version of iOS can do, and neither is a question a view should answer.
    ///
    /// The coordinate and the address come **beside** it rather than from it, because they are not the message's to give: they are what the place's own stream last
    /// said, which is where a sender's movement arrives. Passing them as non-optional is also what makes "open a map at nowhere" unrepresentable — a caller with no
    /// place to show has nothing to ask for.
    func userWantsToActOnLocation(_ location: LocationInMessage, at coordinate: LocationCoordinate, address: String?, action: LocationAction) async

    /// Reveals a message the reader had to ask to see.
    ///
    /// The one action of this screen that belongs to a *message* rather than to something in it, which is why it is a method of its own and carries no enum: there is
    /// one thing to ask, and asking it is what marks the message read, sends the read receipt, and starts whatever expiration its sender set.
    func userWantsToRevealMessage(_ message: TapToRead) async

    /// Carries out what the reader asked of a poll — casting a vote, or asking to see the whole of it.
    ///
    /// A refused vote arrives here too, carrying its reason: the view can tell that a poll has finished or that "None" is chosen, so it refuses without a round trip,
    /// and an implementation is expected to say so to the reader. Which needs a toast, and therefore a view controller.
    func userWantsToActOnPoll(_ poll: PollInMessage, action: PollAction) async

    /// Opens an attachment: the picture tapped, and every other attachment of the same message beside it, as the legacy screen opens them.
    ///
    /// Here rather than on ``SingleDiscussionAttachmentActions`` because opening is a **presentation** — QuickLook is a view controller, and a data source has none.
    /// It is asked only of an attachment whose file is here and whose message the reader has already asked to see; both are decided where the gesture is, which is
    /// the one place that knows the phase.
    ///
    /// The attachment names *which* one was tapped, and nothing more: which others are shown beside it, and in what order, is read from the message by whoever
    /// presents them.
    func userWantsToOpenAttachment(_ attachment: MessageAttachment) async

    /// The reader tapped something the discussion said about itself, and it is one of the few that lead somewhere.
    ///
    /// Every one of them ends outside this screen — a settings screen, a permission the system grants, the page of a group — which is why a view can only ask. See
    /// ``TappableSystemMessage``.
    func userWantsToActOnSystemMessage(_ systemMessage: TappableSystemMessage) async

    /// Carries out what the reader chose from a message's context menu. See ``MessageAction``.
    ///
    /// **Nine of the twelve present something** — an activity sheet, a document picker, the message's info, the emoji
    /// picker, an edit sheet, a chooser of discussions to forward to, a confirmation before deleting — so this belongs
    /// on the actions and not on the data source, whatever the two that are pure database could have managed alone.
    ///
    /// Takes the cell's identifier rather than a message value: the answer to ``whatTheMessageOffers(cellIdentifier:)``
    /// was keyed by it, and everything an action needs is read from the message it names.
    func userWantsToActOnMessage(cellIdentifier: SingleDiscussionView.CellIdentifier, action: MessageAction) async

    /// The reader wants to see whoever sent a message — they tapped that sender's name or picture in a group discussion.
    ///
    /// **A presentation, and the app's alone.** What opens is the contact's own screen, which decides for itself what to
    /// offer: *Invite* for somebody the reader has no one-to-one discussion with, *Discuss* and *Call* for somebody they
    /// do — and *Discuss* then takes the whole navigation to that discussion. None of that is this screen's business, and
    /// nothing about it is a question a view can answer.
    ///
    /// Asked with an ``ObvContactIdentifier``, which is what the screen it opens is keyed by. Never asked for a contact
    /// since deleted: such a sender is still named but has no identifier — see ``MessageSender/contactIdentifier``.
    func userWantsToSeeAContact(contactIdentifier: ObvContactIdentifier) async

    /// The reader wants to know who reacted to a message — they tapped its chip of reactions.
    ///
    /// **A presentation, and the app's alone**, like ``userWantsToSeeAContact(contactIdentifier:)``: what opens is a sheet
    /// naming each person and what they reacted with, from which a reaction of the reader's own can be removed and any
    /// emoji added to or taken out of their favourites. A view can show none of that and a data source cannot present.
    ///
    /// Asked with the identifier the chip already carries — an ``ObvMessageReactionsViewModel/MessageIdentifier``, which is
    /// what that sheet is keyed by, so nothing is converted on the way. Never asked of a message with no reactions: an
    /// empty chip draws nothing and has no area to tap.
    func userWantsToSeeWhoReactedToAMessage(messageIdentifier: ObvMessageReactionsViewModel.MessageIdentifier) async

    /// The reader tapped the bubble saying that messages are missing.
    ///
    /// It is a question rather than a request — "why is something missing?" — and the answer is an explanation: a message whose sending was cancelled, or a large one
    /// still being uploaded. Which is an alert, and therefore not something a view or a data source can show.
    func userWantsToKnowWhyMessagesAreMissing() async

    /// The reader tapped a link in the body of a message.
    ///
    /// **Not something a view opens itself.** The app decides what a URL means — an Olvid invitation is opened *by* the app, and only what is left goes to a
    /// browser — which is why the legacy screen routes every tapped link through `UIApplication.userSelectedURL(_:within:)` rather than through the system.
    func userWantsToOpenURLFromAMessage(_ url: URL) async

    /// Where the attachments of this screen are drawn, and which of them is on its way to or from the viewer.
    ///
    /// **A property of the actions rather than something threaded through the views**, and the reason is the same one that puts opening here: what reads it is
    /// whoever presents the viewer, and every view that draws an attachment already holds these actions. See ``AttachmentFrames``.
    var attachmentFrames: AttachmentFrames { get }

}


// MARK: - SingleDiscussionCellView

/// Displays one cell of the single discussion screen.
///
/// The cell receives only the identifier of the item it displays, and resolves its own model as a live stream. This keeps the memory footprint of a
/// discussion bounded by the number of visible cells, whatever the number of messages it contains.
///
/// Once the model is known, this view only dispatches to the view dedicated to the kind of cell to show, handing it the associated data. It
/// deliberately opens **one** stream per cell: the view dedicated to a kind of message must not open a second stream for the same message.
/// Sub-parts that have their own identity *and* their own update cadence (attachments, reactions) are expected to be identified within the model,
/// and to be streamed by the view that displays them, one level down.
public struct SingleDiscussionCellView: View {

    /// What this cell shows, and the data it needs to show it.
    public enum Model: Equatable, Sendable {

        case sentMessage(SentMessageCellView.Model)
        case receivedMessage(ReceivedMessageCellView.Model)

        /// Something the discussion says about itself — see ``SystemMessageCellView``. A third kind rather than a special case of a message, since everything a
        /// message has it lacks: a sender, a body of its own writing, attachments, a status.
        case systemMessage(SystemMessageCellView.Model)


        /// The day this cell opens, when its message is the first of its day, and nil otherwise.
        ///
        /// Read here rather than in each of the two cells because a separator is drawn the same way whichever kind of message follows it, and because it spans the
        /// whole width where a message is on one side or the other.
        var dateSeparator: Date? {
            switch self {
            case .sentMessage(let model): return model.dateSeparator
            case .receivedMessage(let model): return model.dateSeparator
            case .systemMessage(let model): return model.dateSeparator
            }
        }

    }

    private let cellIdentifier: SingleDiscussionView.CellIdentifier
    private let dataSource: any SingleDiscussionCellViewDataSource
    private let actions: any SingleDiscussionCellViewActions

    /// Seed known before this cell is ever rendered, so that it shows its content on the very first frame instead of a skeleton. Nil for a cell whose
    /// model was not prefetched, typically one scrolled into view long after the discussion was opened.
    private let initialModel: Model?

    @State private var streamedModel: Model?

    private var model: Model? { streamedModel ?? initialModel }

    public init(cellIdentifier: SingleDiscussionView.CellIdentifier, dataSource: any SingleDiscussionCellViewDataSource, actions: any SingleDiscussionCellViewActions, initialModel: Model?) {
        self.cellIdentifier = cellIdentifier
        self.dataSource = dataSource
        self.actions = actions
        self.initialModel = initialModel
    }

    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfSingleDiscussionCellViewModel(cellIdentifier: cellIdentifier)
            defer { dataSource.finishAsyncStreamOfSingleDiscussionCellViewModel(cellIdentifier: cellIdentifier, streamUUID: streamUUID) }
            for await receivedModel in stream {
                // Nothing to do when the stream merely confirms what the cell is already showing, which is the common case for a prefetched cell.
                //
                // **Compared with what has been *streamed*, and not with what is being *shown*.** That difference is the whole of a bug: a message that
                // arrives is seeded from `lastCellModel`, its stream's first value equals that seed, and comparing against ``model`` therefore skipped the
                // assignment — so ``streamedModel`` stayed nil and the cell went on living off a seed it did not own. `initialModel(for:)` gives the last row
                // `lastCellModel`, and **only while it is the last row**: the next arrival takes it away, the cache holds the cell up a while longer, and
                // when that lapses the model is nil, a skeleton is drawn, and nothing re-runs this task because the row's identity never changed. A message
                // permanently blank whose content had already been delivered. Comparing against ``streamedModel`` keeps what the guard was for — no redundant
                // write, no needless rebuild — and makes the cell own what it shows.
                //
                // **No animation, deliberately.** A cell changing height inside an animated transaction moves everything below it, and a screenful of that on
                // entering a discussion is seen as the list scrolling. Animating the changes that deserve it — a status, an edit, a reaction — belongs to the
                // view that draws them, where it can be scoped to the part that actually changes.
                guard receivedModel != streamedModel else { continue }
                // **Against what was *streamed*, and never against what is *shown***, which is the rule two lines above and was broken here once and paid for
                // within the hour: `model` is `streamed ?? seed`, so a guard written against it skips the assignment whenever the stream merely *confirms* the
                // seed — the common case — and the cell then shows the right thing while owning nothing. It goes blank for good when the seed expires.
                streamedModel = receivedModel
            }
        } catch {
            assertionFailure()
        }
    }

    public var body: some View {
        // The switch is wrapped in a single-root container so that this cell stays *unary*, i.e. produces exactly one top-level view whichever branch
        // is taken. This is what allows the enclosing lazy container to derive the identity of its cells from the identifiers alone. Were the cell to
        // branch between several top-level shapes, SwiftUI would have to evaluate the body of *every* cell just to compute its identity, at a cost
        // growing with the number of messages in the discussion. A `Group` would **not** do: it is a passthrough, not a container.
        VStack(spacing: 0) {
            // Above the message, and inside its cell: the day it opens, when it opens one. See ``DateSeparatorView``.
            if let dateSeparator = model?.dateSeparator {
                DateSeparatorView(day: dateSeparator)
            }
            switch model {
            case .sentMessage(let model):
                SentMessageCellView(model: model, cellIdentifier: cellIdentifier, dataSource: dataSource, actions: actions)
            case .receivedMessage(let model):
                ReceivedMessageCellView(model: model, cellIdentifier: cellIdentifier, dataSource: dataSource, actions: actions)
            case .systemMessage(let model):
                SystemMessageCellView(model: model, cellIdentifier: cellIdentifier, actions: actions)
            case nil:
                // Until the model is known, the kind of the cell is unknown too, so the skeleton cannot mirror the layout it is replaced with. It is
                // deliberately neutral.
                SingleDiscussionCellSkeletonView()
            }
        }
        .task(onTask)
    }

}


// MARK: - Skeleton shown while the model of the cell is unknown

private struct SingleDiscussionCellSkeletonView: View {

    var body: some View {
        // Mirrors the layout of a received message: a bubble, and the date under it.
        VStack(alignment: .leading, spacing: MessageBubbleMetrics.gap) {
            MessageBubbleView(style: .received) {
                Text(verbatim: "Placeholder message body")
            }
            MessageTimestampView(timestamp: .now)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: .placeholder)
    }

}


#if DEBUG

// MARK: - Previews

@MainActor
final class SingleDiscussionCellViewDataSourceForPreviews: SingleDiscussionCellViewDataSource, SingleDiscussionCellViewActions {

    func getAsyncStreamOfSingleDiscussionCellViewModel(cellIdentifier: SingleDiscussionView.CellIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleDiscussionCellView.Model>) {
        let stream = AsyncStream<SingleDiscussionCellView.Model> { (continuation: AsyncStream<SingleDiscussionCellView.Model>.Continuation) in
            Task {
                // Sleeping allows to see the redacted skeleton in previews
                try? await Task.sleep(seconds: 1)
                guard let model = SingleDiscussionCellView.Model.sampleDataForCellIdentifier[cellIdentifier] else { return }
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }

    func finishAsyncStreamOfSingleDiscussionCellViewModel(cellIdentifier: SingleDiscussionView.CellIdentifier, streamUUID: UUID) {
        // Nothing to finish in previews
    }

    /// Nothing cached, on purpose: this preview exists to show the redacted skeletons and their replacement by the streamed models.
    func cachedModelOfSingleDiscussionCellView(cellIdentifier: SingleDiscussionView.CellIdentifier) -> SingleDiscussionCellView.Model? {
        return nil
    }

    /// Every attachment starts out waiting to be asked for, so that previews show the control, and show it giving way to a picture once tapped.
    ///
    /// Except one: the file of ``MessageAttachment/sampleFileAlreadyHere`` is answered at once, for a presentation that offers no control and could therefore never ask
    /// — the picture of a reply header.
    func getAsyncStreamOfStateForAttachment(_ attachment: MessageAttachment, pixelSize: CGSize) -> AsyncStream<AttachmentState> {
        guard attachment.sha256 != MessageAttachment.sha256OfTheSampleFileAlreadyHere else {
            return AsyncStream { continuation in
                continuation.yield(.init(phase: .available, image: CGImage.sampleImage(pixelSize: pixelSize)))
                continuation.finish()
            }
        }
        return AsyncStream { continuation in
            stateContinuations[attachment.id] = continuation
            pixelSizes[attachment.id] = pixelSize
            continuation.yield(.init(phase: .downloadable, image: nil))
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.stateContinuations.removeValue(forKey: attachment.id) }
            }
        }
    }

    /// Nothing cached, on purpose: previews exist to show the placeholder giving way to an image.
    func cachedImageForAttachment(_ attachment: MessageAttachment, pixelSize: CGSize) -> CGImage? {
        return nil
    }

    /// A shape that looks like speech — loud where a word is, quiet between them — so that a preview shows a waveform rather than a straight line.
    func recordingForAudioAttachment(_ attachment: MessageAttachment, numberOfSamples: Int) async -> AudioRecording? {
        try? await Task.sleep(seconds: 1) // Long enough to see the flat line the space is reserved with
        let samples = (0..<numberOfSamples).map { index in
            let syllable = abs(sin(Double(index) * 0.7))
            let breath = 0.35 + 0.65 * abs(sin(Double(index) * 0.13))
            return Float(syllable * breath)
        }
        return .init(samples: samples, duration: Self.durationInPreviews)
    }

    /// Nothing to give: a preview has no hardlink, and no file behind an attachment that is drawn from sample data. Dragging one out of a preview therefore
    /// refuses, which is the truthful answer rather than an empty file.
    func getTheFileOfAnAttachment(_ attachment: MessageAttachment) async throws -> URL {
        throw ObvErrorForPreviews.thereIsNoFileBehindASampleAttachment
    }

    /// Whatever this preview's own cache has for the attachment, at the size it was drawn at — which is all a drag needs, and a preview has no drag anyway.
    func cachedImageOfAnySizeForAttachment(_ attachment: MessageAttachment) -> CGImage? {
        nil
    }

    enum ObvErrorForPreviews: Error {
        case thereIsNoFileBehindASampleAttachment
    }

    // AnimatedImageDataSource

    /// A square walking across the frame, so that a preview shows a GIF *animating* rather than a still — and shows it paced, the frames being asked for one at a
    /// time exactly as the app's own producer hands them over.
    func getAsyncStreamOfFramesForAnimatedImage(_ attachment: MessageAttachment, maxPixelSize: Int) -> AsyncStream<CGImage> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                var indexOfTheFrame = 0
                while !Task.isCancelled {
                    if let frame = CGImage.sampleAnimationFrame(pixelSize: .init(width: maxPixelSize, height: maxPixelSize),
                                                                indexOfTheFrame: indexOfTheFrame,
                                                                numberOfFrames: Self.numberOfFramesInPreviews) {
                        continuation.yield(frame)
                    }
                    try? await Task.sleep(seconds: 0.1)
                    indexOfTheFrame = (indexOfTheFrame + 1) % Self.numberOfFramesInPreviews
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static let numberOfFramesInPreviews = 12

    // LinkPreviewDataSource

    /// A preview of a page that does not exist, so that previews show every part of the card: a large picture, a description that has to clamp, a title and a domain.
    func linkPreviewMetadata(for source: LinkPreviewInMessage, maxPixelSize: Int) async -> LinkPreviewMetadata? {
        try? await Task.sleep(seconds: 1) // Long enough to see the spinner the space is reserved with
        let image: LinkPreviewImage = if let picture = CGImage.sampleImage(pixelSize: .init(width: maxPixelSize, height: maxPixelSize / 2)) {
            .large(picture, aspectRatio: 2)
        } else {
            .none
        }
        return .init(title: "A page with a rather long title, long enough to run onto a second line",
                     desc: "What the page says of itself, which is usually a sentence or two and sometimes, on the sites that are given the whole of this space, a good deal more than that.",
                     domain: "example.org",
                     url: URL(string: "https://example.org/a-page"),
                     image: image,
                     showsTheWholeDescription: false)
    }

    // PollDataSource

    /// A poll whose votes creep in, so that a preview shows the bars moving without a preview needing a database or a contact to vote.
    func getAsyncStreamOfPollState(forPollWith identifier: PollInMessage.Identifier) -> AsyncStream<MessagePollViewModel> {
        AsyncStream { continuation in
            let task = Task {
                var voters = 3
                while !Task.isCancelled {
                    continuation.yield(Self.pollInPreviews(voters: voters))
                    try await Task.sleep(seconds: 2)
                    voters += 1
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func pollInPreviews(voters: Int) -> MessagePollViewModel {
        let shares: [Double] = [55, 30, 15, 0]
        let answers = ["Monday, so that everyone has the weekend to prepare", "Tuesday", "Wednesday", "None of these"]
        let candidates = zip(answers, shares).enumerated().map { index, pair in
            MessagePollCandidateViewModel(uuid: UUID(uuidString: "0000000\(index)-0000-0000-0000-000000000000") ?? UUID(),
                                          text: pair.0,
                                          hasVoted: index == 1,
                                          totalPercent: pair.1)
        }
        return .init(question: "Which day suits you best?",
                     multipleChoice: false,
                     candidates: candidates,
                     expirationDate: Date.now.addingTimeInterval(3600 * 30),
                     totalNumberOfResponses: voters)
    }

    // SingleDiscussionCellViewActions, for a poll

    /// Nothing to do: a preview has no poll screen to open, and no toast to show a refusal with.
    func userWantsToActOnPoll(_ poll: PollInMessage, action: PollAction) async {}

    /// Nothing to do: revealing a message is a database operation, and a preview has no database.
    func userWantsToRevealMessage(_ message: TapToRead) async {}

    /// Nothing to do: a contact's screen is a presentation, and a preview has no controller to present from.
    func userWantsToSeeAContact(contactIdentifier: ObvContactIdentifier) async {}

    /// Nothing to do: the sheet of who reacted is a presentation, and a preview has no controller to present from.
    func userWantsToSeeWhoReactedToAMessage(messageIdentifier: ObvMessageReactionsViewModel.MessageIdentifier) async {}

    /// Nothing to do: nine of the twelve present something, and a preview has no controller to present from.
    func userWantsToActOnMessage(cellIdentifier: SingleDiscussionView.CellIdentifier, action: MessageAction) async {}

    /// A handful of favourites and one of them already chosen, so a preview shows the bar in both of its states.
    func whatTheReaderMayReactWith(cellIdentifier: SingleDiscussionView.CellIdentifier) -> TheEmojisOnOffer {
        .init(favourites: ["❤️", "👍", "👎", "😂", "‼️"], theReadersOwn: "👍", theEmojiADoubleTapSends: "❤️")
    }

    /// One of each kind of entry, so a preview shows a full menu: something to say about the message, a reaction to add
    /// and one to remove, text, two sets of attachments, and the four that act on the message itself.
    func whatTheMessageOffers(cellIdentifier: SingleDiscussionView.CellIdentifier) -> WhatAMessageOffers {
        .init(entries: [
            .showInfo,
            .react(alreadyReacted: true),
            .deleteOwnReaction,
            .copyText,
            .sharePhotos(count: 3),
            .shareAttachments(count: 5),
            .saveAttachments(count: 5),
            .reply,
            .edit,
            .forward,
            .delete,
        ])
    }

    /// Nothing to do: explaining a gap is an alert, which a preview has no controller to present. The tap is still worth having — it shows the bubble answering a
    /// finger at all rather than the row swallowing it.
    func userWantsToKnowWhyMessagesAreMissing() async {}

    /// Nothing to do: every one of these leads to a screen, a permission or a settings page, and a preview has none of them.
    func userWantsToActOnSystemMessage(_ systemMessage: TappableSystemMessage) async {}

    // ObvAvatarViewDataSource

    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 1)
        return UIImage.sampleImageForURL(photoURL)
    }

    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return UIImage.sampleImageForURL(photoURL)
    }

    // LocationDataSource

    /// A place that drifts, so that a preview shows a bubble following a sender rather than a still square — and shows that the picture already up is kept while the
    /// next is made, rather than the square blinking on every step.
    ///
    /// It moves by about ten metres a second, which at this zoom is some nine points: enough to see, and enough to be past the metre a request is quantised to.
    func getAsyncStreamOfLocationState(forLocationWith identifier: LocationInMessage.Identifier) -> AsyncStream<LocationState> {
        AsyncStream { continuation in
            let task = Task {
                var latitude = 48.8566
                while !Task.isCancelled {
                    continuation.yield(.init(coordinate: .init(latitude: latitude, longitude: 2.3522),
                                             address: "12 rue de la Paix, 75002 Paris, France",
                                             expiration: Date.now.addingTimeInterval(3600 + 1500)))
                    try await Task.sleep(seconds: 1)
                    latitude += 0.0001
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// A picture standing in for a map, so that previews show the square filled without a preview needing MapKit, a network or a coordinate that exists.
    ///
    /// Drawn **from the coordinate**, so that a place drifting pans the grid: a stand-in that ignored the place would make a bubble that follows a sender look exactly
    /// like one that does not.
    func mapSnapshot(centeredOn coordinate: LocationCoordinate, pointSize: CGSize, displayScale: CGFloat, appearance: MapAppearance) async -> CGImage? {
        try? await Task.sleep(seconds: 0.4) // Long enough to see the empty bubble the space is held with, short enough not to lag behind a place that moves
        return CGImage.sampleMapImage(pixelSize: .init(width: pointSize.width * displayScale, height: pointSize.height * displayScale),
                                      centeredOn: coordinate)
    }

    // AttachmentProgressDataSource

    /// Creeps from nought to one over a few seconds, so that a preview shows a moving arc.
    func getAsyncStreamOfProgressForAttachment(_ attachment: MessageAttachment) async throws -> (streamUUID: UUID, stream: AsyncStream<AttachmentProgress>) {
        let stream = AsyncStream(AttachmentProgress.self, bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                for step in 0...20 {
                    try await Task.sleep(seconds: 0.15)
                    continuation.yield(.init(fractionCompleted: Double(step) / 20))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (UUID(), stream)
    }

    func finishAsyncStreamOfProgressForAttachment(streamUUID: UUID) async {
        // Nothing to finish in previews: the stream above ends on its own and is cancelled with its task.
    }

    // AudioPlaybackDataSource

    /// Plays a preview's recording in the only sense a preview can: the time advances and the bars light up, from nothing, over ten seconds.
    func getAsyncStreamOfAudioPlaybackState(forAttachment attachment: MessageAttachment) async throws -> (streamUUID: UUID, stream: AsyncStream<AudioPlaybackState>) {
        let streamUUID = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: AudioPlaybackState.self, bufferingPolicy: .bufferingNewest(1))
        playbackContinuations[attachment.id] = continuation
        continuation.yield(.atRest(rate: rateInPreviews))
        return (streamUUID, stream)
    }

    func finishAsyncStreamOfAudioPlaybackState(streamUUID: UUID) async {
        // Nothing to finish in previews.
    }

    func userWantsToActOnAudioAttachment(_ attachment: MessageAttachment, action: AudioAction) async {
        guard let continuation = playbackContinuations[attachment.id] else { return }
        switch action {
        case .pause:
            playingInPreviews[attachment.id]?.cancel()
            continuation.yield(stateInPreviews(isPlaying: false, at: timePlayedInPreviews[attachment.id] ?? 0))
        case .standsAt(let fraction, _):
            let time = fraction * Self.durationInPreviews
            timePlayedInPreviews[attachment.id] = time
            continuation.yield(stateInPreviews(isPlaying: false, at: time))
        case .setRate(let rate):
            rateInPreviews = rate
            for continuation in playbackContinuations.values {
                continuation.yield(stateInPreviews(isPlaying: false, at: 0))
            }
        case .play(let fromFraction):
            playingInPreviews[attachment.id] = Task { [weak self] in
                var time = fromFraction * Self.durationInPreviews
                while time < Self.durationInPreviews {
                    continuation.yield(self?.stateInPreviews(isPlaying: true, at: time) ?? .atRest())
                    try await Task.sleep(seconds: 0.03)
                    time += 0.03
                    self?.timePlayedInPreviews[attachment.id] = time
                }
                self?.timePlayedInPreviews[attachment.id] = 0
                continuation.yield(self?.stateInPreviews(isPlaying: false, at: 0) ?? .atRest())
            }
        }
    }

    private func stateInPreviews(isPlaying: Bool, at time: TimeInterval) -> AudioPlaybackState {
        .init(isPlaying: isPlaying, currentTime: time, duration: Self.durationInPreviews, rate: rateInPreviews)
    }

    private var rateInPreviews: AudioPlaybackRate = .ordinary
    private static let durationInPreviews = TimeInterval(10)
    private var playbackContinuations = [MessageAttachment.ID: AsyncStream<AudioPlaybackState>.Continuation]()
    private var playingInPreviews = [MessageAttachment.ID: Task<Void, Error>]()
    private var timePlayedInPreviews = [MessageAttachment.ID: TimeInterval]()

    // ReactionsCountViewDataSource

    /// A different handful of reactions per message, so that a preview shows a chip with one emoji, a chip with several, an emoji whose count is one and therefore
    /// not written, and messages with no chip at all. Late, as a real stream is, so that the chip is seen arriving.
    func getAsyncStreamOfReactionsCountViewModel(messageIdentifier: ObvMessageReactionsViewModel.MessageIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<ObvReactionsCountViewModel>) {
        let numberOfReactions: Int
        switch messageIdentifier {
        case .forPreview(let uuid):
            // The first byte of the identifier, which is fixed for the lifetime of a sample message and differs from one to the next.
            numberOfReactions = Int(uuid.uuid.0) % 8
        case .objectID:
            numberOfReactions = 0
        }
        let stream = AsyncStream<ObvReactionsCountViewModel> { (continuation: AsyncStream<ObvReactionsCountViewModel>.Continuation) in
            Task {
                try? await Task.sleep(seconds: 1.5)
                continuation.yield(.init(reactionsAndCount: Array(ObvReactionsCountViewModel.ReactionAndCount.sampleData.prefix(numberOfReactions))))
            }
        }
        return (UUID(), stream)
    }

    func finishAsyncStreamOfReactionsCountViewModel(streamUUID: UUID) {
        // Nothing to finish in previews
    }

    // SingleDiscussionCellViewActions

    /// Nothing to do: a preview has no maps application to leave for, and no controller to present one from.
    func userWantsToActOnLocation(_ location: LocationInMessage, at coordinate: LocationCoordinate, address: String?, action: LocationAction) async {}

    /// Nothing to do: a preview has no app to hand a URL to.
    func userWantsToOpenURLFromAMessage(_ url: URL) async {}

    /// Nothing to do either: opening an attachment is QuickLook, which is a view controller a preview does not have. The tap is still worth having here — it is
    /// what shows that the gesture reaches the actions at all, rather than being swallowed by the control above it.
    func userWantsToOpenAttachment(_ attachment: MessageAttachment) async {}

    let attachmentFrames = AttachmentFrames()

    /// Walks the phases a download goes through, so that a preview shows the control acknowledging a tap, then turning, then giving way to the picture.
    func userWantsToActOnAttachment(_ attachment: MessageAttachment, action: AttachmentAction) async {
        guard let continuation = stateContinuations[attachment.id] else { return }
        switch action {
        case .pauseDownload:
            downloads[attachment.id]?.cancel()
            continuation.yield(.init(phase: .downloadable, image: nil))
        case .resumeDownload:
            continuation.yield(.init(phase: .askedToDownload, image: nil))
            downloads[attachment.id] = Task { [weak self] in
                try await Task.sleep(seconds: 1)
                continuation.yield(.init(phase: .downloading, image: nil))
                try await Task.sleep(seconds: 2)
                guard let pixelSize = self?.pixelSizes[attachment.id] else { return }
                continuation.yield(.init(phase: .available, image: CGImage.sampleImage(pixelSize: pixelSize)))
            }
        }
    }

    private var stateContinuations = [MessageAttachment.ID: AsyncStream<AttachmentState>.Continuation]()
    private var pixelSizes = [MessageAttachment.ID: CGSize]()
    private var downloads = [MessageAttachment.ID: Task<Void, Error>]()

}


/// Shared by the previews of the cells, which live in their own files and each need a data source to hand their images. Inside `#if DEBUG`, so it
/// ships nowhere.
let singleDiscussionCellViewDataSourceForPreviews = SingleDiscussionCellViewDataSourceForPreviews()


@available(iOS 18.0, *)
#Preview {
    // No seed at all here, so that this preview shows the redacted skeletons and their replacement by the streamed models.
    SingleDiscussionCellsListView(
        cellIdentifiers: SingleDiscussionView.CellIdentifier.sampleData,
        theSections: [],
        lastCellModel: nil,
        initialCellModels: [:],
        // As the setting is on by default, so a preview shows what a reader gets.
        newMessages: nil,
        sentenceSayingTheDiscussionIsEndToEndEncrypted: nil,
        dataSource: singleDiscussionCellViewDataSourceForPreviews,
        actions: singleDiscussionCellViewDataSourceForPreviews,
        reportsWhatTheReaderIsLookingAt: { _, _ in },
        // Nothing arrives in a preview, so nothing ever finishes appearing.
        arrivalsThatHaveFinishedAppearing: 0,
        // Taken and dropped: a preview has no draft to put anything in.
        itemsWereDroppedOnTheMessages: { _ in },
        // Nothing to leave: a preview's composition bar is a stand-in with no caret.
        theReaderClickedOnTheMessages: {},
        // Nothing ticked and nothing choosing: a preview has no bar to count a selection and no ellipsis to enter one from.
        selectedCellIdentifiers: .constant([]),
        // Nowhere for a range to extend from either, and so nothing a range could have added — see ``TheSelectionOfSeveralMessages/theAnchor``.
        theAnchorOfTheSelection: .constant(nil),
        whatTheLastExtensionAdded: .constant([]),
        theReaderIsChoosingMessages: false,
        // A channel of its own, asked by nobody: a preview has no search bar and no reply to jump to.
        whereTheReaderWantsToGo: WhereTheReaderWantsToGo())
}

#endif
