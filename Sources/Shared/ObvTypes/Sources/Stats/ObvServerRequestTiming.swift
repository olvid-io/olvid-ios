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


/// How long one attempt at a server request took, and what came back.
///
/// Recorded so that a reader who says "it takes ten seconds before I see a message" can send us numbers instead of an impression. A duration on its own
/// would not be enough: an attempt that took ten seconds and came back `.invalidSession` is a different fault from one that took ten seconds and returned
/// eight hundred messages, and the two have different fixes. So the outcome and the number of messages are kept beside the durations, and the durations are
/// split by phase rather than summed — `durationOfTheRequest` is the network, `durationOfTheSaveAndProcess` is us, and only the second one is ours to make
/// faster.
///
/// `request` exists so that a second kind of request can be recorded in the same place later without a second mechanism. Only the listing is recorded today.
public struct ObvServerRequestTiming: Sendable, Equatable, Codable {

    /// The server request being timed. One case today, and the reason this is not simply implied.
    public enum ServerRequest: String, Sendable, Codable {
        case downloadMessagesAndListAttachments
    }

    /// What provoked the request.
    ///
    /// Worth keeping because "slow when the device is woken by a push" and "slow when the reader opens the app" are different complaints with different
    /// causes, and the reader cannot tell us which of the two they saw.
    public enum Trigger: String, Sendable, Codable {
        /// The app asked. Coming to the foreground, a pull to refresh and a silent push all arrive here as one thing: the engine is told to fetch and not
        /// why, so telling them apart needs the app to say which, and it does not yet.
        case theAppAskedForIt
        /// The background **processing** task that drains the inbox while the device is idle and on external power. Distinguished from `theAppAskedForIt`
        /// because these are the listings nobody is waiting for: a slow one costs a night rather than a reader's patience, and a run of them is what a device
        /// working off a large backlog overnight looks like.
        case theBackgroundProcessingTaskDrainingTheInbox
        case webSocketSaysAMessageIsAvailable
        /// The socket carried a whole message and it could not be saved, so a full listing was made instead. Rare, and worth seeing when it happens.
        case webSocketMessageCouldNotBeSaved
        case webSocketRegistrationSucceeded
        case pushNotificationRegistrationSucceeded
        /// Asked for again by the previous attempt, after an invalid session, an unregistered device or a general error. A run of these is itself an
        /// explanation for a long wait, which no single duration would show.
        case retryOfAPreviousAttempt
        /// The server had more to give than one listing could carry, so the previous attempt asked for the next page. Nothing has gone wrong here, and a
        /// long run of them is what a device working through a large backlog looks like.
        case continuationOfATruncatedListing
    }

    /// What the server answered, or that we never got as far as asking.
    public enum Outcome: String, Sendable, Codable {
        case ok
        case listingTruncated
        case invalidSession
        case deviceIsNotRegistered
        case generalError
        /// The request was not made at all — no session token, no device UID, or the call itself threw.
        case couldNotPerformTheRequest
        /// The server answered and we could not save what it gave us. Distinct from the above because the network was fine and we were not.
        case couldNotSaveWhatCameBack

        /// Whether we got as far as an answer from the server, whatever that answer was.
        ///
        /// **The question is about the network, not about success.** A refused session, an unregistered device and a general error are all the server
        /// speaking, and a caller asking *can this device reach Olvid at all* must count them as yes — only ``couldNotPerformTheRequest`` is a no.
        ///
        /// Exhaustive rather than defaulted, so that a new outcome has to be placed on one side or the other rather than silently joining the majority.
        public var theRequestReachedTheServer: Bool {
            switch self {
            case .ok, .listingTruncated, .invalidSession, .deviceIsNotRegistered, .generalError, .couldNotSaveWhatCameBack:
                return true
            case .couldNotPerformTheRequest:
                return false
            }
        }
    }

    public let date: Date
    public let request: ServerRequest
    public let trigger: Trigger
    public let outcome: Outcome

    /// Getting a valid session token, which is usually cached and free, and is a round trip of its own when the token was just invalidated.
    public let durationOfTheServerSessionTokenRequest: TimeInterval

    /// The request itself. This is the number the "ten seconds" complaint is usually assumed to be about.
    public let durationOfTheRequest: TimeInterval

    /// Saving the returned messages and asking for their decryption, slice by slice. Nil when there was nothing to save, which is every outcome but `.ok`
    /// and `.listingTruncated` — nil and zero mean different things here and are worth telling apart.
    public let durationOfTheSaveAndProcess: TimeInterval?

    /// Nil for the outcomes that returned no list at all, for the same reason.
    public let numberOfMessagesReturned: Int?

    public init(date: Date, request: ServerRequest, trigger: Trigger, outcome: Outcome, durationOfTheServerSessionTokenRequest: TimeInterval, durationOfTheRequest: TimeInterval, durationOfTheSaveAndProcess: TimeInterval?, numberOfMessagesReturned: Int?) {
        self.date = date
        self.request = request
        self.trigger = trigger
        self.outcome = outcome
        self.durationOfTheServerSessionTokenRequest = durationOfTheServerSessionTokenRequest
        self.durationOfTheRequest = durationOfTheRequest
        self.durationOfTheSaveAndProcess = durationOfTheSaveAndProcess
        self.numberOfMessagesReturned = numberOfMessagesReturned
    }

    /// How long the requests described by `timings` have been failing to reach the server, counting only what happened since `since`, or nil if the most
    /// recent of them reached it.
    ///
    /// **A duration rather than a count, and that is the point of it.** A caller polling twice a second and a request backing off over 5, 15, 30 and 60
    /// seconds have no common unit, so a count of *rounds* means whatever the poll interval happens to be that month. The drain's rule learnt this once
    /// already, when `numberOfBarrenRounds` became `howLongNothingHasMoved` after a loop re-timing quietly turned *two rounds* into *one second*.
    ///
    /// **Bounded by `since`, because a stale failure is not a current one.** A device that was offline yesterday still holds those timings, and answering
    /// from them would condemn a request that has not yet had its first attempt come back.
    ///
    /// The duration is measured from the **first** failure of the unbroken run of them that reaches the present, so it says how long the trouble has lasted
    /// rather than how old the last attempt is — by then the two differ by a whole back-off, which is minutes.
    ///
    /// - Returns: nil when the most recent timing reached the server, and nil when there are no timings at all since `since`. **Nil is *nothing known*,
    /// never *all is well***: a caller must read it as leave to carry on rather than as evidence.
    public static func howLongTheRequestsHaveBeenUnableToReachTheServer(in timings: [ObvServerRequestTiming], since: Date, now: Date) -> TimeInterval? {

        // Sorted here rather than assumed: these are recorded without waiting for them to land, so two made close together can be stored the other way
        // round, and every question below is about order.
        let timings = timings
            .filter { $0.date >= since }
            .sorted { $0.date < $1.date }

        // The start of the unbroken run of failures ending at the present. Oldest first, so this walks back from the end. The run is empty both when
        // there are no timings and when the most recent reached the server, so one test covers both.
        guard let startOfTheTrouble = timings.reversed().prefix(while: { !$0.outcome.theRequestReachedTheServer }).last?.date else { return nil }

        // Clamped because `now` is the caller's and a timing's date is the recorder's, and nothing makes the two monotonic with respect to one another.
        return max(0, now.timeIntervalSince(startOfTheTrouble))

    }


    /// Everything the attempt took, as far as we measured it. The three phases will not always add up to the wall clock — anything between them is not
    /// timed — and a gap between this and the phases is itself worth noticing, since that gap is somewhere the seconds could be hiding.
    public var totalMeasuredDuration: TimeInterval {
        durationOfTheServerSessionTokenRequest + durationOfTheRequest + (durationOfTheSaveAndProcess ?? 0)
    }

    /// Short keys because a hundred of these are kept and the property names would otherwise be most of the bytes. They are never displayed, so nothing is
    /// lost by shortening them — unlike the enums' raw values, which the report prints and which stay readable.
    enum CodingKeys: String, CodingKey {
        case date = "d"
        case request = "rq"
        case trigger = "tg"
        case outcome = "o"
        case durationOfTheServerSessionTokenRequest = "st"
        case durationOfTheRequest = "rd"
        case durationOfTheSaveAndProcess = "sp"
        case numberOfMessagesReturned = "n"
    }

}


// MARK: - Summarising a set of timings

extension Array where Element == ObvServerRequestTiming {

    /// The requested percentile of the given duration, over the timings that have one. Nil for an empty set, which the caller must be able to say out loud:
    /// "no value" and "zero seconds" are answers to different questions.
    public func percentile(_ percentile: Double, of duration: (ObvServerRequestTiming) -> TimeInterval?) -> TimeInterval? {
        let values = self.compactMap(duration).sorted()
        guard !values.isEmpty else { return nil }
        let rank = Swift.max(0, Swift.min(values.count - 1, Int((percentile * Double(values.count - 1)).rounded())))
        return values[rank]
    }

    public func countPerOutcome() -> [ObvServerRequestTiming.Outcome: Int] {
        self.reduce(into: [:]) { counts, timing in counts[timing.outcome, default: 0] += 1 }
    }

}
