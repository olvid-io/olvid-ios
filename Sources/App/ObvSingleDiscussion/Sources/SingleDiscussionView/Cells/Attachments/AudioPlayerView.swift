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


/// The first audio attachment of a message, shown much as the legacy screen shows it: a play button, the shape of the recording, the time, and the play rate.
///
/// **There is one player for the whole app**, so a recording is reached through an actions protocol and followed through a stream of its state — the same shape as
/// a download's progress. What that buys is the thing a single player makes necessary: a view showing a recording that is *not* the one playing has no other way to
/// learn that it has been displaced. See ``AudioPlaybackDataSource``.
///
/// Unlike every other kind of attachment, this one sits in a **message bubble** rather than in a grey card.
struct AudioPlayerView: View {

    let audio: MessageAttachment

    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    /// Which corners this player joins to another part of the same message — see ``TheColumnOfPartsOfAMessage``. Fully rounded unless the cell says otherwise.
    @Environment(\.cornersOfThisPartOfTheMessage) private var corners

    /// Whether this recording belongs to a message the reader has yet to ask to see. See ``EnvironmentValues/attachmentsAreCoveredUntilRead``.
    @Environment(\.attachmentsAreCoveredUntilRead) private var isCovered

    /// The recording itself — its shape and its length — or nothing while it is unknown: the file not being here, or not yet measured.
    @State private var recording: AudioRecording?

    /// Where the playing of this recording stands. At rest until its stream says otherwise, which is also what it returns to when another attachment takes the
    /// player — there being only one.
    @State private var playback: AudioPlaybackState = .atRest()

    /// Where the reader has dragged to, and it **outlives the drag**.
    ///
    /// This is where a scrubbed position lives, and it has to live here: the app keeps one position for the one recording the player holds, and knows nothing of where
    /// a reader dragged to on a recording that has never sounded. Clearing this when the finger lifted was what made the position snap back to the beginning.
    ///
    /// Given up as soon as the player itself starts reporting — from then on it is the player that knows where the recording has got to.
    @State private var fractionDraggedTo: Double?

    /// Whether the recording was playing when a finger landed on the waveform, so that it can be set going again when the finger comes off. Nil once that has been
    /// answered.
    ///
    /// **It no longer says whether a drag is in progress**, which is ``thereIsAFingerOnTheWaveform``'s job — see there for what asking one property both questions
    /// cost.
    @State private var wasPlayingWhenTheDragBegan: Bool?

    /// Whether a finger is on the waveform right now.
    ///
    /// **A `@GestureState` rather than a `@State`, and that is the whole of it**: SwiftUI puts a `@GestureState` back to its initial value when the gesture ends
    /// *or is cancelled*, and a cancelled gesture is not a rare case here — it is what happens every time a touch that landed on the waveform turns into a scroll of
    /// the transcript, which a `DragGesture(minimumDistance: 0)` inside a `List` invites by taking the touch down.
    ///
    /// `onEnded` is **not called** on a cancellation, so everything unwound there was left standing: the recording stayed paused, this recording's position stayed
    /// frozen wherever the finger had been for the rest of the screen's life, and the next drag did not pause because the flag saying a drag was already in progress
    /// had never been cleared. There is no `onCancelled` on a `DragGesture` to hang the unwind from — a `@GestureState`'s reset is the signal that exists, so the
    /// unwind is driven by watching this rather than by the gesture's own ending. See ``theScrubHasFinished()``.
    @GestureState private var thereIsAFingerOnTheWaveform = false

    /// The position to draw: where the reader put it, or where the player has got to.
    private var fractionShown: Double {
        fractionDraggedTo ?? playback.fractionPlayed
    }

    /// The time to show beside it, which follows the same rule.
    ///
    /// The length is taken from the *recording* rather than from the player, which knows only the one it is holding: a reader dragging along a recording that has
    /// never been played would otherwise be shown `00:00` throughout, the position moving under their finger while the time stood still.
    private var timeShown: TimeInterval {
        if let fractionDraggedTo, let duration = durationShown {
            return fractionDraggedTo * duration
        }
        // **A recording standing at its beginning shows how long it is**, rather than a position of nought — which is what the legacy screen shows there, and a
        // deliberate departure from it: `00:00` beside a full waveform says nothing at all, where the length is the one thing a reader wants before deciding to
        // listen. It is a *position* from the moment there is one, and the length again when the recording has been heard out and put back to its beginning.
        if !playback.isPlaying, playback.currentTime == 0, let duration = durationShown {
            return duration
        }
        return playback.currentTime
    }


    /// How long the recording lasts, and nil while that is unknown — the file not being here, or not yet measured.
    ///
    /// Asked of the *recording* first: the player knows the length of the one it is holding and of no other, so a recording that has never sounded has nobody else
    /// to ask.
    private var durationShown: TimeInterval? {
        recording?.duration ?? playback.duration
    }

    /// `WaveFormView.totalNumberOfSamples`.
    static let numberOfBars = 35

    var body: some View {
        // No image is asked for — there is nothing to show a picture of — so this is here for the phase and the progress alone, and for the control they drive.
        // At the leading edge, where the legacy screen puts it: over the play button, whose place it takes while the recording is not here.
        FollowedAttachment(attachment: audio,
                           sizeToRequest: .zero,
                           initialImage: nil,
                           dataSource: dataSource,
                           actions: actions,
                           controlAlignment: .leading) { _, phase in
            HStack(alignment: .center, spacing: 4) {
                playButton(isPlayable: phase == .available && !isCovered)
                WaveformView(samples: recording?.samples, fractionPlayed: fractionShown)
                    .gesture(scrub)
                    // **A scrub is over when the finger comes off, however it comes off** — including when the transcript takes the touch away, which `onEnded`
                    // never reports. See ``thereIsAFingerOnTheWaveform``.
                    .onChange(of: thereIsAFingerOnTheWaveform) { thereIsAFinger in
                        guard !thereIsAFinger else { return }
                        theScrubHasFinished()
                    }
                    // **A scrub is not a press on the message** — finding 18. The shrink means *hold and this will lift*, and on the waveform it cannot: the scrub
                    // wins the touch outright, so a hold here shrank the message for the whole of a scrub and promised something that never came. The same
                    // `@GestureState` that finding 9 added for the cancellation does this for nothing.
                    .aFingerHereIsNotAPressOnTheMessage(thereIsAFingerOnTheWaveform)
                timeAndRate
            }
            // Keyed on the phase, and that is what makes a recording measure itself the moment its download ends. Keyed on the attachment instead — which it was —
            // the measurement was attempted once, while the file was still absent, and never again: the waveform stayed flat until the row was destroyed and built
            // afresh by a scroll.
            .task(id: phase) {
                // A covered recording is not measured either: its shape is as much of a message as its words are, and reading a file to draw it is exactly what a
                // message the reader has not asked to see must not cause.
                guard phase == .available, !isCovered else { recording = nil; return }
                recording = await dataSource.recordingForAudioAttachment(audio, numberOfSamples: Self.numberOfBars)
            }
            // Followed only while there is a recording to play. There is one player for the whole app, so this says as much about losing it to another attachment as
            // about having it — see ``AudioPlaybackDataSource``.
            .task(id: phase) {
                guard phase == .available else { return }
                await followsThePlaying()
            }
        }
        .foregroundStyle(Color(UIColor.label))
        .padding(.horizontal, MessageBubbleMetrics.horizontalInset)
        .padding(.vertical, MessageBubbleMetrics.verticalInset)
        // `newReceivedCellBackground` whether the message was sent or received, as on the legacy screen — where it is hardcoded, and looks like an oversight
        // rather than a decision. Reproduced all the same: it is what a reader sees today.
        .background(MessageBubbleStyle.received.backgroundColor,
                    in: MessageBubbleMetrics.shape(corners))
    }


    /// Hidden by opacity rather than removed, as on the legacy screen, so that the space it takes is the same whether or not the recording can be played.
    private func playButton(isPlayable: Bool) -> some View {
        Button {
            let action: AudioAction = playback.isPlaying ? .pause : .play(fromFraction: fractionShown)
            Task { await actions.userWantsToActOnAudioAttachment(audio, action: action) }
        } label: {
            // Both glyphs are laid out, one of them hidden, so that the button is as wide as the wider of the two whichever is showing. A triangle and a pair of bars
            // are not the same width, and swapping one for the other shifted the waveform beside it by a point or two on every tap.
            //
            // Reserved this way rather than with a width of its own: the glyphs grow with the reader's text size, and a number chosen here would not.
            ZStack {
                Image(systemIcon: .playFill).hidden()
                Image(systemIcon: .pauseFill).hidden()
                Image(systemIcon: playback.isPlaying ? .pauseFill : .playFill)
            }
        }
        .buttonStyle(.plain)
        // **A hold here is not the start of a long press** — finding 18. Measured on an iPhone 13: a two-second hold shrank the message, played the recording on
        // release, and opened no menu at all. See ``AFingerOnThisIsNotAPressOnTheMessageEither``, which is why this is a gesture rather than a `ButtonStyle`.
        .aFingerHereIsNotAPressOnTheMessage()
        .padding(20)
        .opacity(isPlayable ? 1 : 0)
        .disabled(!isPlayable)
    }


    /// How far into the recording the player has got — or, for one standing at its beginning, how long it lasts. See ``timeShown``.
    ///
    /// It follows the **finger** while one is on the waveform, rather than the player: a reader dragging to a place in the recording is asking where that place is,
    /// and the answer is of no use arriving after they let go.
    private var timeAndRate: some View {
        VStack(alignment: .center, spacing: 14) {
            Text(verbatim: Self.formatted(timeShown))
                .font(.caption)
                // Fixed width, so the bars beside it do not shift as the seconds tick over from one digit to two.
                .monospacedDigit()
            rateButton
        }
        .frame(minWidth: 60)
    }


    /// Cycles through the speeds, as on the legacy screen. The rate belongs to the player rather than to a recording, so every audio player on the screen shows the
    /// same one and any of them can change it.
    private var rateButton: some View {
        Button {
            Task { await actions.userWantsToActOnAudioAttachment(audio, action: .setRate(playback.rate.next)) }
        } label: {
            Text(verbatim: playback.rate.title)
                .font(.subheadline)
                .monospacedDigit()
        }
        .buttonStyle(.plain)
        // See the play button above: a hold here changed the speed on release, shrank the message throughout, and lifted nothing.
        .aFingerHereIsNotAPressOnTheMessage()
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(.quaternary.opacity(0.5))
        .clipShape(Capsule())
    }


    /// Dragging along the waveform moves the position within the recording, as on the legacy screen — where a tap counts too, `minimumDistance` being zero.
    ///
    /// A recording that is playing is **paused** for the duration of the drag and set going again at the new position when it ends, so the sound does not stutter
    /// under the finger. One that is already paused stays paused, and simply keeps the position it was left at.
    /// A cancellation is treated exactly as an ending, which is right rather than merely convenient: a tap is a drag of no distance here, `minimumDistance` being
    /// zero, so seeking to where the finger landed is already what the lightest touch on the waveform does.
    private var scrub: some Gesture {
        DragGesture(minimumDistance: 0)
            // Nothing but the flag: the side effects stay in `onChanged`, an `updating` closure being called as part of delivering the gesture and no place for
            // them. What this buys is the *reset*, which is the one thing a cancelled gesture still does.
            .updating($thereIsAFingerOnTheWaveform) { _, thereIsAFinger, _ in
                thereIsAFinger = true
            }
            .onChanged { value in
                if wasPlayingWhenTheDragBegan == nil {
                    wasPlayingWhenTheDragBegan = playback.isPlaying
                    if playback.isPlaying {
                        Task { await actions.userWantsToActOnAudioAttachment(audio, action: .pause) }
                    }
                }
                fractionDraggedTo = min(1, max(0, value.location.x / WaveformView.width))
            }
    }


    /// The finger has come off the waveform — by being lifted, or by the transcript taking the touch for a scroll. Driven by ``thereIsAFingerOnTheWaveform`` rather
    /// than by the gesture's `onEnded`, which the second of those never reaches.
    private func theScrubHasFinished() {
        let wasPlaying = wasPlayingWhenTheDragBegan ?? false
        wasPlayingWhenTheDragBegan = nil
        guard let fractionDraggedTo else { return }
        // One that was playing is set going again where the finger left it; one that was not says where it now stands, this view being destroyed by the scroll a
        // touch on the waveform so often turns into. The length goes with the second, the app having nobody to ask for a recording the player is not holding —
        // and nothing is said at all while it is unknown, there being no position to describe without it.
        let action: AudioAction?
        if wasPlaying {
            action = .play(fromFraction: fractionDraggedTo)
        } else if let durationShown {
            action = .standsAt(fraction: fractionDraggedTo, ofRecordingLasting: durationShown)
        } else {
            action = nil
        }
        guard let action else { return }
        Task { await actions.userWantsToActOnAudioAttachment(audio, action: action) }
    }


    /// Follows the playing of this recording for as long as this view is on screen.
    ///
    /// Finished from a task of its own, as the progress stream is: this one ends by being *cancelled*, and a cancelled task cannot await anything.
    private func followsThePlaying() async {
        guard let (streamUUID, stream) = try? await dataSource.getAsyncStreamOfAudioPlaybackState(forAttachment: audio) else { return }
        defer {
            Task { await dataSource.finishAsyncStreamOfAudioPlaybackState(streamUUID: streamUUID) }
        }
        for await reported in stream {
            playback = reported
            // Once the recording is sounding, the player is the one that knows where it has got to, and a position the reader dragged to would freeze the display.
            // Dropped only then: a recording that is paused or has never played keeps whatever the reader chose.
            //
            // **Asked of the finger and not of ``wasPlayingWhenTheDragBegan``**, which used to answer this and could not be trusted to: a cancelled gesture left it
            // set for ever, so this test never passed again and the display stayed frozen at the position of a drag the reader had abandoned.
            if reported.isPlaying, !thereIsAFingerOnTheWaveform {
                fractionDraggedTo = nil
            }
        }
    }


    /// `mm:ss`, as `AudioDurationFormatter` produces on the legacy screen.
    private static func formatted(_ time: TimeInterval) -> String {
        Duration.seconds(max(0, time)).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2)))
    }

}


/// The shape of a recording, as 35 bars.
///
/// **The same height whether it has samples or not**: 48pt, with a flat line of 3pt stubs standing in for a recording that has not been measured — which is how the
/// legacy screen reserves the space, and what keeps a row from changing height when the measurement arrives. A row that changes height moves everything below it
/// and cannot be animated.
private struct WaveformView: View {

    let samples: [Float]?

    /// How much of the recording has been played, between 0 and 1. What has been is drawn solid, what has not is faint, and the bar the player is crossing is
    /// somewhere between — as on the legacy screen, where the same arithmetic gives each bar its opacity.
    let fractionPlayed: Double

    /// `WaveFormView`'s own numbers: a 3pt bar with a point of air either side, so 5pt apiece.
    private static let barWidth = CGFloat(3)
    private static let gapBesideABar = CGFloat(1)

    /// The tallest a bar is drawn, and the shortest — a bar of nothing is still a dot.
    private static let heightOfTheTallestBar = CGFloat(40)
    private static let heightOfTheShortestBar = CGFloat(3)

    /// The strip's own height, which never changes.
    private static let height = CGFloat(48)

    /// The strip's width, which is arithmetic rather than a measurement: 35 bars of 3pt with a point of air either side. Known in advance, so a drag along it needs no
    /// `GeometryReader` — the legacy screen keeps one only because its bar count is a variable.
    static var width: CGFloat {
        CGFloat(AudioPlayerView.numberOfBars) * (barWidth + 2 * gapBesideABar)
    }

    /// A bar the player has not reached is at this much; one it has passed is at 1. `0.3 + 0.7 × fill`, as on the legacy screen.
    private static let opacityAtRest = 0.3

    /// The bars spring up from the flat line rather than appearing at their heights, which is what the legacy screen does with
    /// `spring(response: 0.7, dampingFraction: 0.47, blendDuration: 0.25)` — a low damping, so they overshoot a little and settle.
    private static let riseOfTheBars = Animation.spring(response: 0.7, dampingFraction: 0.47, blendDuration: 0.25)

    /// How much longer each bar waits than the one before it, half a millisecond, as on the legacy screen.
    ///
    /// **The wait itself is cumulative, and so grows as the square of the index.** The legacy screen sleeps `0.5ms × i` *between* one bar and the next, inside a
    /// loop, so bar `i` begins after the sum of every sleep before it — half a millisecond times `i(i+1)/2`. Across 35 bars that is some **300ms**, not the 17ms a
    /// linear reading of the same constant gives, and it accelerates: the first bars rise almost together while the last ones lag further and further behind.
    ///
    /// That acceleration is very likely an accident of writing the delay inside the loop rather than from the start. It is also what looks right, so it is what is
    /// reproduced here — deliberately, and with the arithmetic spelled out, since a linear stagger of the same constant is indistinguishable from no stagger at all.
    private static let extraDelayPerBar = 0.0005

    private static func delayOfTheBar(at index: Int) -> Double {
        extraDelayPerBar * Double(index * (index + 1)) / 2
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(0..<AudioPlayerView.numberOfBars, id: \.self) { index in
                bar(at: index)
            }
        }
        .frame(height: Self.height)
    }

    private func bar(at index: Int) -> some View {
        Rectangle()
            .frame(width: Self.barWidth, height: heightOfTheBar(at: index))
            // Scoped to the height alone, and deliberately placed here rather than at the end of the chain. `animation(_:value:)` governs everything *below* it, so
            // with the opacity below it the bars stopped lighting up as the recording played: the only change it would honour was one of the samples.
            //
            // Declared per bar rather than driven by a loop that sleeps between them, which is how the legacy screen staggers it. The effect is the same and there is
            // no task to cancel, no intermediate state to hold, and nothing to go wrong if the samples change again.
            .animation(Self.riseOfTheBars.delay(Self.delayOfTheBar(at: index)), value: samples)
            .cornerRadius(Self.barWidth)
            .opacity(opacityOfTheBar(at: index))
            .padding(.horizontal, Self.gapBesideABar)
    }

    private func heightOfTheBar(at index: Int) -> CGFloat {
        guard let samples, index < samples.count else { return Self.heightOfTheShortestBar }
        return max(Self.heightOfTheShortestBar, Self.heightOfTheTallestBar * CGFloat(samples[index]))
    }

    /// `0.3 + 0.7 × fill`, where the fill of a bar is how much of *it* the player has crossed — so the bar being played is part-lit rather than switching from one
    /// state to the other, which is what makes the movement read as continuous across only 35 bars.
    private func opacityOfTheBar(at index: Int) -> Double {
        let fill = min(1, max(0, fractionPlayed * Double(AudioPlayerView.numberOfBars) - Double(index)))
        return Self.opacityAtRest + (1 - Self.opacityAtRest) * fill
    }

}
