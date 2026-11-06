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
import OlvidUtils


/// What a message says about its own ephemerality: that it burns when read, and when it is destroyed.
///
/// **Five facts and no decision.** Whether anything is *shown* depends on the time — a destruction date in the past
/// shows nothing — so that question belongs where it is asked afresh each second, in
/// ``TheCountdownOfAnEphemeralMessage``, and not in a model resolved once.
///
/// The names are the legacy screen's, from `ExpirationIndicatorView.configure(readingRequiresUserAction:readOnce:scheduledVisibilityDestructionDate:scheduledExistenceDestructionDate:)`
/// and `EphemeralityInformationsView.configure(readOnce:visibilityDuration:)`, the two views this model serves.
public struct TheEphemeralityOfAMessage: Equatable, Sendable {

    /// That the message is destroyed as soon as it has been read.
    public let readOnce: Bool

    /// That the reader has still to tap the message before its body may be shown. **Always false for a message sent**:
    /// a sender is never asked to tap their own message, and the legacy cell passes `false` there literally.
    public let readingRequiresUserAction: Bool

    /// How long the message stays visible **once it has been read** — what the sender granted, and nil when they granted no limit.
    ///
    /// Not the same fact as ``scheduledVisibilityDestructionDate``, and neither can be derived from the other: this one is a
    /// promise about a clock that has **not started**, and it is all there is to say about a message still to be tapped;
    /// that one is the moment the clock it started will run out. They are drawn by different views for that reason — this by
    /// ``WhatWillHappenWhenThisMessageIsRead``, before the reader commits, and the date by
    /// ``TheCountdownOfAnEphemeralMessage``, after.
    public let visibilityDuration: TimeInterval?

    /// When the message stops being *visible*, its body going with it. The sender set a duration; this is the moment it ends.
    public let scheduledVisibilityDestructionDate: Date?

    /// When the message stops *existing* at all, whether or not it was ever read.
    public let scheduledExistenceDestructionDate: Date?

    public init(readOnce: Bool, readingRequiresUserAction: Bool, visibilityDuration: TimeInterval?, scheduledVisibilityDestructionDate: Date?, scheduledExistenceDestructionDate: Date?) {
        self.readOnce = readOnce
        self.readingRequiresUserAction = readingRequiresUserAction
        self.visibilityDuration = visibilityDuration
        self.scheduledVisibilityDestructionDate = scheduledVisibilityDestructionDate
        self.scheduledExistenceDestructionDate = scheduledExistenceDestructionDate
    }

    /// Nothing ephemeral about this message, which is what most messages carry.
    public static let none = TheEphemeralityOfAMessage(readOnce: false, readingRequiresUserAction: false, visibilityDuration: nil, scheduledVisibilityDestructionDate: nil, scheduledExistenceDestructionDate: nil)

}


/// The countdown beside an ephemeral message: an icon, and the time it has left, in a colour that says how little that is.
///
/// `ExpirationIndicatorView` on the legacy screen, which draws it **beside the bubble** — leading for a message sent, trailing for one received, so it always
/// sits towards the middle of the screen. Not to be confused with ``WhatWillHappenWhenThisMessageIsRead``, the chip *in the date row* that says what the
/// sender chose: that counts nothing down, and appears in the one case this view stays quiet about.
///
/// **What decides that it appears**, transcribed from `shouldShow`, and it is not "the message is ephemeral":
///
/// - a message whose body still has to be **tapped** shows a countdown for its *existence* only. Its visibility has not begun, so counting it down would be
///   counting something that is not running, and its read-once flame would say what the unopened bubble already says;
/// - otherwise: read-once, or a visibility date, or an existence date.
///
/// A date already **passed** counts for nothing — the message is on its way out, and until it goes it shows no countdown. That is why the rule is applied per
/// tick rather than resolved into the model.
///
/// **`TimelineView(.periodic(from:by:))`, once a second, and only around this view.** That is the whole of why a countdown is affordable here: what
/// re-renders each second is an icon and five characters, not a cell. Driving it from the model would rebuild a message every second and cost a `ForEach`
/// pass over the discussion with it. (Legacy refreshes every visible cell from a timer, which it can afford because a `UICollectionViewCell` is reconfigured
/// rather than rebuilt.)
///
/// **It ticks only when there is something to count.** A read-once message with no dates shows a flame and no number, so it is drawn once and left alone.
struct TheCountdownOfAnEphemeralMessage: View {

    let ephemerality: TheEphemeralityOfAMessage

    var body: some View {
        // A `Group` and not a container: a message with nothing to say about its ephemerality must take no space at all,
        // and an empty container would still be given the stack's spacing. See `MessageBodyView`.
        Group {
            if ephemerality.hasADateToCountDown {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    theIndicator(asOf: context.date)
                }
            } else {
                // Nothing changes with time here — a flame, or nothing — so it is drawn once rather than every second.
                theIndicator(asOf: .now)
            }
        }
    }


    @ViewBuilder
    private func theIndicator(asOf now: Date) -> some View {
        let state = ephemerality.asOf(now)
        if let state {
            VStack(spacing: 0) {
                if let icon = state.icon {
                    Image(systemIcon: icon)
                        .font(.system(size: Self.fontSize))
                }
                if let remaining = state.remaining {
                    Text(verbatim: Self.durationFormatter.string(from: remaining) ?? "")
                        .font(.system(size: Self.fontSize))
                        // A countdown changes width as it counts, and a number that shifts its neighbours every second reads
                        // as a fault. Legacy pins a minimum width for exactly this reason, calling it a heuristic.
                        .frame(minWidth: Self.fontSize * 2.5)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(state.colour)
            .frame(height: Self.height, alignment: .top)
        }
    }


    /// `MessageCellConstants.expirationIndicatorViewHeight`, so the indicator reserves the same height whatever it is showing
    /// and a message does not change height when its countdown gains or loses a line.
    private static let height: CGFloat = 30

    /// The 12pt of `ExpirationIndicatorView`, for both the icon and the number.
    private static let fontSize: CGFloat = 12

    /// Made once. A `DateComponentsFormatter` is expensive to build and this is asked once a second per visible ephemeral message.
    private static let durationFormatter = DurationFormatter()

}


extension TheEphemeralityOfAMessage {

    /// Whether there is a date worth counting down to at all, which is what decides whether this ticks.
    fileprivate var hasADateToCountDown: Bool {
        scheduledVisibilityDestructionDate != nil || scheduledExistenceDestructionDate != nil
    }

    /// What the countdown shows at this moment, or nil when it shows nothing.
    ///
    /// The whole of the legacy rule, in one place: which dates still count, whether anything is shown, which icon, which
    /// colour, and how long is left.
    fileprivate func asOf(_ now: Date) -> (icon: SystemIcon?, remaining: TimeInterval?, colour: Color)? {

        // A date in the past is not a countdown. Legacy drops both the same way, in `configure`.
        let visibility = scheduledVisibilityDestructionDate.flatMap { $0 > now ? $0 : nil }
        let existence = scheduledExistenceDestructionDate.flatMap { $0 > now ? $0 : nil }

        let shouldShow: Bool = if readingRequiresUserAction {
            existence != nil
        } else {
            readOnce || visibility != nil || existence != nil
        }
        guard shouldShow else { return nil }

        // The icon. A flame means *this burns when you read it*, and it wins — but not before it has been read, where the
        // bubble asking to be tapped says as much already. Otherwise: an eye if visibility runs out first, a timer if
        // existence does.
        let icon: SystemIcon? = if readOnce && !readingRequiresUserAction {
            .flameFill
        } else {
            switch (visibility, existence) {
            case (nil, nil): nil
            case (nil, .some): .timer
            case (.some, nil): .eyes
            case (.some(let v), .some(let e)): v < e ? .eyes : .timer
            }
        }

        // How long is left: the sooner of the two, and never negative.
        let soonest: Date? = switch (visibility, existence) {
        case (nil, nil): nil
        case (nil, .some(let d)), (.some(let d), nil): d
        case (.some(let v), .some(let e)): min(v, e)
        }
        let remaining = soonest.map { max(0, $0.timeIntervalSince(now)) }

        // The colour says how little time is left, and read-once is red whatever the clock says: it goes on the reader's
        // next look, which no countdown can predict.
        let colour: Color = if readOnce {
            .red
        } else if let remaining {
            switch remaining {
            case ..<Self.limitForRed: .red
            case ..<Self.limitForOrange: .orange
            case ..<Self.limitForTheLabelColour: Color(UIColor.label)
            default: Color(UIColor.secondaryLabel)
            }
        } else {
            Color(UIColor.secondaryLabel)
        }

        return (icon, remaining, colour)

    }

    /// `MessageCellConstants.TimeIntervalForMessageDestruction`, unchanged: a minute, an hour, a day.
    fileprivate static let limitForRed: TimeInterval = 60
    fileprivate static let limitForOrange: TimeInterval = 60 * 60
    fileprivate static let limitForTheLabelColour: TimeInterval = 60 * 60 * 24

}
