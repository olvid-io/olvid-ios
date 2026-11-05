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


/// Follows one attachment — its picture, where it stands, how far along its download is — and hands the picture to whatever draws it.
///
/// Everything an attachment has in common, whatever it is shown as, lives here: the stream that watches the join, the stream that follows the bytes, and the
/// control the reader taps to fetch the file. What is left to each presentation is only its shape — a square in a bubble, a grid tile, the thumbnail of a card,
/// the top of a PDF — which is exactly what differs between them.
///
/// Separated rather than parameterised because the shapes have nothing to do with one another and will only diverge further. An image will one day size itself to
/// its own ratio, from a value carried in the message's model; a card's thumbnail will always be a square as tall as the two labels beside it. One view told to
/// be both would have to ignore most of what it was given.
///
/// **The size asked for is not the size drawn.** This takes the size to *request*, in points, and says nothing about how big the result is shown. A card asks for
/// 100×100 and draws it at whatever its labels come to; an image asks for what it occupies. Keeping the two apart is also what keeps the cache small — a size no
/// other message shares is an entry no other message can use.
struct FollowedAttachment<Content: View>: View {

    let attachment: MessageAttachment

    /// The size the image is asked for, **in points**. Turned into pixels here, once, rather than at each call site.
    ///
    /// `.zero` asks for no image at all, which is what an audio attachment wants: it needs the phase and the progress, and has nothing to show a picture of. The
    /// data source declines a request of no size, so nothing is decoded and nothing is rendered.
    let sizeToRequest: CGSize

    /// The image if one had already been decoded at this size when this view was built, so that a picture the reader has already seen is there on the frame it
    /// appears on rather than a frame or two later. Looked up by the view that builds this one, never here, so that nothing is fetched from within a view's initializer.
    let initialImage: CGImage?

    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    /// Where the control sits. Centred on a picture, and at the leading edge of an audio player — where the legacy screen puts it, over the play button it stands
    /// in for.
    var controlAlignment: Alignment = .center

    /// Whether the reader is offered the control at all.
    ///
    /// False for a link preview, which is the one kind of attachment that is *always* fetched, whatever size the reader has set as their limit — so there is never
    /// anything to ask for, and the legacy screen offers nothing there either. It also stops the download being followed: the number would be shown by nothing.
    var showsTheStateControl: Bool = true

    /// Draws the attachment, given the best picture there is so far — nil while there is none — and where the attachment stands, nil until its stream has said.
    ///
    /// The phase is handed over because some presentations need more of the file than a picture, and must know when they can go and get it: an audio player has to
    /// measure the recording, and cannot do so until it is here. Without it, such a view has no way to learn that a download it was watching has finished.
    @ViewBuilder let content: (CGImage?, AttachmentState.Phase?) -> Content

    @Environment(\.displayScale) private var displayScale

    /// Whether this attachment belongs to a message the reader has yet to ask to see. See ``EnvironmentValues/attachmentsAreCoveredUntilRead``.
    @Environment(\.attachmentsAreCoveredUntilRead) private var isCovered

    /// Where the attachment stands, as its own stream reports it. Nil until it has said anything, which is why the control appears a beat after the picture it
    /// sits on rather than flickering onto one that is already there.
    @State private var state: AttachmentState?

    /// How far along the download is, from the stream that follows it, and nil whenever there is no download to follow.
    @State private var progress: AttachmentProgress?

    /// Set when the progress stream ends **of its own accord** rather than by this view being done with it.
    ///
    /// The engine closes every stream following an attachment the moment its download completes, before it announces that it has — so a stream ending is not by
    /// itself remarkable, and at the end of an ordinary download the phase becomes `available` a beat later and the control goes. It matters only when the phase
    /// stays one that has a transfer behind it, which happens when a downloaded file turns out not to hash as its sender said it would: the engine discards it
    /// and fetches it again, and this view is following nothing at all while it does.
    @State private var theProgressStreamEndedOnItsOwn = false

    /// Bumped to follow the progress again after the engine closed the stream and there is still a transfer to follow.
    ///
    /// Part of the identity of the task below so that a new stream is asked for exactly once per such occasion. Nought for the whole of an ordinary download.
    @State private var timesTheProgressWasFollowedAgain = 0

    /// The best picture there is: what the stream last offered, or, until it has offered anything, the one this view was built with.
    ///
    /// The seed is *dropped* the moment a state arrives, rather than kept as a fallback. What the stream says is the truth about this attachment, including when
    /// it says there is no picture to show — an attachment waiting to be downloaded must show its control on a blurred stand-in or on nothing, never on a
    /// picture left over from somewhere else.
    private var image: CGImage? {
        // A message the reader has not asked to see shows none of its pictures — not the file's, and not the blurred stand-in a message carries either, which would
        // say what a photograph is before the reader had asked.
        guard !isCovered else { return nil }
        guard let state else { return initialImage }
        return state.image
    }

    var body: some View {
        content(image, state?.phase)
            .overlay(alignment: controlAlignment) {
                // A covered attachment offers nothing to ask for: the message is what is asked for, and its own bubble does that. The legacy screen likewise leaves
                // its control out and puts the hand-tap glyph in its place.
                if isCovered {
                    // `.label`, as every legacy view that draws this glyph sets it — `SingleImageView`, `MultipleImagesView`, `SinglePDFView`, `AttachmentsView` and
                    // `AudioWaveFormView` all override `TapToReadView`'s own white default, which no caller keeps. White on the `systemFill` square a covered
                    // attachment shows is barely visible, which is how the slip was found.
                    Image(systemIcon: .handTap)
                        .font(.body)
                        .foregroundStyle(Color(UIColor.label))
                } else if showsTheStateControl, let phase = state?.phase {
                    AttachmentStateControl(phase: phase, fractionCompleted: progress?.fractionCompleted) { action in
                        Task { await actions.userWantsToActOnAttachment(attachment, action: action) }
                    }
                }
            }
            // Keyed on what makes the answer a different one. Not on the status: the stream watches the attachment itself and says so when its file arrives,
            // which the message's model never learns — it is fetched from the message, and a message is not told that one of its attachments changed.
            .task(id: TaskIdentity(attachment: attachment.id, sizeToRequest: sizeToRequest, displayScale: displayScale, isCovered: isCovered)) {
                await asksForTheState()
            }
            // Keyed on whether there is a download to follow, which starts and stops the following without a line of cancellation logic: the file arriving makes
            // this false, which cancels the task, which ends the stream, which tells the engine to stop reporting.
            .task(id: ProgressTaskIdentity(followsTheProgress: followsTheProgress, timesFollowedAgain: timesTheProgressWasFollowedAgain)) {
                await asksForTheProgress()
            }
    }


    /// Follows the stream for as long as this view is on screen rather than taking its first answer: an attachment may be waiting to be asked for, then asked
    /// for, then arriving as a blurred stand-in, then as its picture.
    private func asksForTheState() async {
        // In pixels, as the image strategy requires: the data source decodes to exactly what was asked for, and never to "full resolution to be safe".
        //
        // **A covered attachment asks for no size**, which the data source answers with the phase and no picture — the same free path an audio player and a link
        // preview take. Nothing of a message the reader has not asked to see is decoded, rasterised or cached.
        let pixelSize = isCovered ? .zero : CGSize(width: sizeToRequest.width * displayScale, height: sizeToRequest.height * displayScale)
        for await state in dataSource.getAsyncStreamOfStateForAttachment(attachment, pixelSize: pixelSize) {
            self.state = state
            followTheProgressAgainIfTheStreamEndedAndThereIsStillATransfer()
        }
    }


    /// Asks for a new progress stream when the engine closed the last one and this attachment is still transferring.
    ///
    /// Driven from a change of *state* rather than from the stream ending, and that is the point: at the end of an ordinary download the stream ends and the
    /// next state is `available`, so this declines and no stream is opened for nothing. It is only when a transfer is somehow still in front of us that it acts
    /// — which today means one thing, a file that arrived and did not hash as its sender said it would, whereupon the app has the engine discard it and put the
    /// join back to `downloadable`. That change of status is what reaches this.
    ///
    /// The fraction is dropped here rather than when the stream ended, so that the last frames of an ordinary download are not drawn with an empty arc: below
    /// `theEngineHasNotAnsweredYet`, nought and *unknown* are the same thing and both start the spinner.
    private func followTheProgressAgainIfTheStreamEndedAndThereIsStillATransfer() {
        guard theProgressStreamEndedOnItsOwn, followsTheProgress else { return }
        theProgressStreamEndedOnItsOwn = false
        progress = nil
        timesTheProgressWasFollowedAgain += 1
    }


    /// Whether there is a download to follow at all, rather than which phase it is in.
    ///
    /// The three phases that have a download behind them are treated as one, so that a download is followed by a *single* stream from the moment the file is
    /// found to be missing until it arrives. Keying on the phase itself tore the stream down and built it again — at the cost of a database operation each time
    /// — as it passed from `downloadable` to `askedToDownload` to `downloading`; measured, that doubled the number of subscriptions per download.
    ///
    /// `askedToDownload` is among them although it draws a spinner and ignores the fraction: following during it changes nothing on screen and saves the churn.
    /// Whether there is a transfer worth following, in **either** direction.
    ///
    /// Named for the download alone until Step 36, which is all it followed: an upload had no phase to follow. The name mattered more
    /// than it looks — a property called `followsTheProgress` is one nobody thinks to extend when the bytes start going the other way.
    private var followsTheProgress: Bool {
        // Nothing shows the number when there is no control, so nothing asks the engine for it — which covers a covered attachment too, its control being the glyph.
        guard showsTheStateControl, !isCovered else { return false }
        switch state?.phase {
        case .downloadable, .askedToDownload, .downloading: return true
        // An upload is followed for the same reason and by the same machinery, though what feeds it is not the engine but a transient
        // attribute on the join. See `SingleDiscussionViewAppDataSource.getAsyncStreamOfProgressForAttachment(_:)`.
        case .uploading: return true
        // Neither of the two Step 30 phases has a download behind it — one never will, the other not until the message arrives — so there is no number to ask the
        // engine for and no stream to open.
        case .available, .cancelledByServer, .leftBehindByAHistoryTransfer, .knownOnlyFromANotification, nil: return false
        }
    }


    /// Follows the download of this attachment, and only while there is one to follow.
    ///
    /// Nothing is asked for once the file is here: an attachment that has arrived has no progress, and the engine is told to stop reporting rather than left
    /// pushing a number at a view that would ignore it.
    ///
    /// Every value is taken as it comes. A 27MB attachment reports some three hundred times over its whole download, each costing a state change on this view
    /// and nothing above it — measured, the discussion's rows are not rebuilt once. What guards against a producer outrunning this is the stream's buffering
    /// policy, which keeps only the newest value.
    ///
    /// The stream is finished from a task of its own because this one ends by being *cancelled*, and a cancelled task cannot await anything — so the tidying up
    /// has to be handed to a task that was not.
    private func asksForTheProgress() async {
        guard followsTheProgress else { progress = nil; return }
        guard let (streamUUID, stream) = try? await dataSource.getAsyncStreamOfProgressForAttachment(attachment) else { return }
        defer {
            Task { await dataSource.finishAsyncStreamOfProgressForAttachment(streamUUID: streamUUID) }
        }
        for await reported in stream {
            progress = reported
        }
        // A cancelled task ends the same loop, and that is this view being done with the stream rather than the engine closing it. Only the latter is worth
        // remembering, and only it can leave a control drawing a number nothing will ever correct.
        guard !Task.isCancelled else { return }
        theProgressStreamEndedOnItsOwn = true
    }


    /// What makes the progress worth following again.
    private struct ProgressTaskIdentity: Hashable {
        let followsTheProgress: Bool
        let timesFollowedAgain: Int
    }


    /// What makes the request worth making again.
    private struct TaskIdentity: Hashable {
        let attachment: MessageAttachment.ID
        let sizeToRequest: CGSize
        let displayScale: CGFloat
        /// So that revealing a message asks again, this time for the picture: without it, the request made while the message was covered — for no size at all —
        /// would stand.
        let isCovered: Bool
    }

}
