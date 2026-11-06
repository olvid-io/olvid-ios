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


/// Where the playing of one recording stands.
///
/// A protocol of its own, for the reason ``AttachmentProgressDataSource`` is one: what it carries changes some thirty times a second, belongs to a single view, and
/// must never travel through a message's model — a model change costs a pass over every row of the discussion.
@MainActor
public protocol AudioPlaybackDataSource: AnyObject {

    /// Follows the playing of one recording until the caller finishes with it.
    ///
    /// **There is one player for the whole app**, so this stream says as much about what is *not* happening as about what is: an attachment that had the player and
    /// has lost it to another is told so, by a state that is no longer playing. A view that only heard about its own playing would go on showing a pause button for
    /// a recording that had fallen silent.
    ///
    /// Finished explicitly rather than by cancelling the task that reads it, as the progress streams are, and for the same reason: what feeds it is a single
    /// delegate slot on an object outside this module, which cannot see that a view has gone away.
    ///
    /// Worth asking for only once the recording is here; an implementation may answer nothing for an attachment that is not.
    func getAsyncStreamOfAudioPlaybackState(forAttachment attachment: MessageAttachment) async throws -> (streamUUID: UUID, stream: AsyncStream<AudioPlaybackState>)

    /// Ends a stream obtained above. Must be called, or whatever is feeding it goes on doing so.
    func finishAsyncStreamOfAudioPlaybackState(streamUUID: UUID) async

}


/// What a recording is, as opposed to what is being done with it: measured once, from the file, and true for as long as the file exists.
public struct AudioRecording: Sendable, Equatable {

    /// One value per bar, each between 0 and 1, in the order they are drawn.
    public let samples: [Float]

    /// How long the recording lasts, in seconds.
    ///
    /// Here rather than only in ``AudioPlaybackState`` because a reader may drag along a recording that has never been played, and the time to show them is a fraction
    /// of its length — which the player cannot tell us about a recording it has never held.
    public let duration: TimeInterval

    public init(samples: [Float], duration: TimeInterval) {
        self.samples = samples
        self.duration = duration
    }

}


/// How far through a recording the player has got, and whether it is moving.
public struct AudioPlaybackState: Sendable, Equatable {

    /// False for a recording that is paused, that has finished, and for one whose player has been taken by another attachment.
    public let isPlaying: Bool

    /// Where the player stands, in seconds. Zero for a recording that has not been played.
    public let currentTime: TimeInterval

    /// The recording's length, which is only known once it has been handed to the player. Nil before that.
    public let duration: TimeInterval?

    /// How fast recordings are played, which is a setting of the player and therefore the same for every recording on the screen — including those standing still.
    public let rate: AudioPlaybackRate

    public init(isPlaying: Bool, currentTime: TimeInterval, duration: TimeInterval?, rate: AudioPlaybackRate) {
        self.isPlaying = isPlaying
        self.currentTime = currentTime
        self.duration = duration
        self.rate = rate
    }

    /// Between 0 and 1, and zero for a recording of unknown length rather than a division by zero.
    public var fractionPlayed: Double {
        guard let duration, duration > 0 else { return 0 }
        return min(1, max(0, currentTime / duration))
    }

    /// What a recording that is not being played looks like — the rate excepted, which belongs to the player and is the same everywhere.
    public static func atRest(rate: AudioPlaybackRate = .ordinary) -> AudioPlaybackState {
        .init(isPlaying: false, currentTime: 0, duration: nil, rate: rate)
    }

}
