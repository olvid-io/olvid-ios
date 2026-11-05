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
import OlvidUtils


/// Whether a drain of the engine's inbox should run another round, and if not, why not.
///
/// **A type of its own because, like ``ObvInboxDrainWindowSchedule``, it is a part of this feature a test can reach.** The loop around it needs an engine, a
/// server and a backlog; this needs a handful of numbers and a clock. The app's unit tests host no app — they compile only the files named in
/// `sourcesUnderTest` — so anything testable has to be reachable without dragging the app in. Hence Foundation, `ObvTypes` and `OlvidUtils`, and nothing else.
///
/// The clock and the memory reading are parameters for the same reason: a rule that reads `.now` from inside itself can be run but not checked.
enum ObvInboxDrainRoundDecision {

    /// Everything the rule is allowed to know. Deliberately a value: the loop reads these once, at a round boundary, and hands them over.
    struct WhatTheRunKnows {

        /// What the inbox held when this round asked, or nil if the reading failed.
        ///
        /// **Nil is *this one reading failed*, never *the inbox is empty*.** Every question below that needs the counts is skipped when there are none,
        /// which errs towards draining on rather than stopping early.
        ///
        /// Whether a failed reading is a reason to *stop* is ``howLongTheCountsHaveBeenUnreadable``'s to say, not this field's. The two are set together by
        /// the one caller that has them.
        let counts: ObvInboxCounts?

        /// How long the counts have been unreadable, or nil if this round read them.
        ///
        /// A bound rather than a bare failure: the count is taken over a store three extensions also write to, where one refusal is ordinary and the next
        /// reading a second later comes back. Ending the run on the first refusal cost a night, ``ObvInboxDrainWindowSchedule`` treating that ending as
        /// six hours' worth of unknown.
        ///
        /// A duration rather than a count of readings, for the reason ``howLongNothingHasMoved`` gives: a bound counted in polls changes meaning whenever
        /// the loop is re-timed.
        let howLongTheCountsHaveBeenUnreadable: TimeInterval?

        /// Whether no round has run yet. **One round always runs**, however empty the inbox looks, because an empty inbox says nothing about what the
        /// *server* still holds: a device that deleted its rows locally, or one restored from a backup, has a backlog waiting on the server and nothing
        /// local to hint at it. Listing is one request, so the cost of asking when there is nothing is a request; the cost of not asking is that this task
        /// can never help the case it was built for. It also makes the expiration path reachable on a device whose inbox is empty, where a run that stopped
        /// before its first round would end in milliseconds and leave nothing to expire.
        let isTheFirstRound: Bool

        /// Whether the last page that came back was truncated — the server's own statement that it still holds something for this device.
        let theServerHasMore: Bool

        /// How long the inbox counts have been completely unchanged, or nil while the listing is still fetching, since nothing can be concluded from
        /// stillness then.
        ///
        /// **A duration rather than a count of rounds.** A bound counted in rounds changes meaning whenever the loop is re-timed: two rounds of a listing
        /// plus a sweep are tens of seconds, two rounds of a half-second poll are one second, and one second of stillness is an ordinary pause between
        /// batches. Expressed in seconds, the bound cannot be broken that way.
        let howLongNothingHasMoved: TimeInterval?

        /// How long the listing has been failing to reach the server at all, or nil if it is reaching it, or if nothing is yet known.
        ///
        /// A duration rather than a count of rounds, for the same reason as the field above: the listing backs off over 5, 15, 30 and 60 seconds, which has
        /// no common unit with a poll. Answered by the engine, which records a timing for every listing including the ones that never got as far as
        /// asking, see ``ObvEngine/howLongTheListingHasBeenUnableToReachTheServer(since:now:)``.
        ///
        /// **A listing that is merely slow is not this.** Only an attempt that could not be made at all counts; an answer of any kind, refusal included, is
        /// the server being reached. Folding the two together told a device with a large backlog that the server could not be reached while it was.
        ///
        /// Nil is *nothing known*, never *all is well*: it is what a run gets before its listing has reported anything.
        let howLongTheListingHasBeenUnableToReachTheServer: TimeInterval?

        /// Somebody — the reader leaving the screen, or the expiration handler of a background window — has asked the run to stop.
        let isStopRequested: Bool

        let deadline: Date

        let now: Date

        let headroom: ObvProcessMemory.Allowance

        /// Whether this process has ever been seen to have a memory limit at all. Read the note on ``weAreOutOfMemoryHeadroom(given:knownToBeMemoryLimited:)``
        /// before changing anything that feeds it.
        let weKnowThisProcessIsMemoryLimited: Bool

    }


    /// Why the drain should not run another round, or nil if it should.
    ///
    /// Asked once before the first round and once after each of them, with the counts that round produced — so a drain that starts with nothing to do never
    /// runs a round at all, and the endings are a list one can read rather than a scattering of `break`s.
    static func reasonToStopBeforeAnotherRound(_ known: WhatTheRunKnows) -> ObvInboxDrainStopReason? {

        if known.isStopRequested { return .weWereAskedToStop }

        if known.now >= known.deadline { return .theDeadlinePassed }

        // A bound rather than a `guard let`: a store shared with three extensions can refuse one count and answer the next. Only a store that has gone on
        // refusing for long enough to be broken ends anything here, which is what the schedule assumes of this ending.
        //
        // Asked here rather than inside a branch that has the counts: every test below is skipped when the reading is missing, so a run whose readings
        // stop coming back would otherwise have no ending short of its deadline.
        if let howLongTheCountsHaveBeenUnreadable = known.howLongTheCountsHaveBeenUnreadable,
           howLongTheCountsHaveBeenUnreadable >= howLongTheCountsMayBeUnreadableBeforeGivingUp {
            return .theCountsCouldNotBeRead
        }

        if !known.isTheFirstRound {

            // Asked before the questions about the inbox: a device that could not reach the server does not know what the server holds, so *there was
            // nothing left to do* on the strength of a local count would be a confident ending drawn from a question nobody managed to ask.
            //
            // Only attempts that could not be made count here. A slow page is a fact about this device, not about the network.
            if let howLongUnableToReachTheServer = known.howLongTheListingHasBeenUnableToReachTheServer,
               howLongUnableToReachTheServer >= howLongTheServerMayBeUnreachableBeforeGivingUp {
                return .theServerCouldNotBeReached
            }

            // The tests below read a *local* count, and a local count cannot answer *is there more to come*. Only a truncated page answers that, so a
            // round that has just been told there is another page must run it whatever the inbox looks like. The inbox looks empty at exactly the wrong
            // moment: right after a page has been listed, stored and swept, and right before the next one is asked for.
            //
            // Skipped, not returned from: an early `return nil` would skip the memory floor below, and a server that still has pages is exactly when the
            // footprint climbs. A reading that failed is not a count either, so the tests are skipped rather than guessed at; the unreadable reading is
            // answered above, by how long it has gone on.
            if let counts = known.counts, !known.theServerHasMore {

                // Nothing anybody owes: nothing to decrypt, nothing for the app to store, nothing for the sweep to take. Rows may well be left, a message on
                // hold or one whose attachment nobody has tapped, but no amount of draining moves those.
                //
                // `numberOfMessagesStillOwed` leaves out the rows waiting for a manual download, since a device holding one unopened photograph would
                // otherwise never reach nought here, and counts the undecrypted, since a round that has just listed a hundred thousand messages has
                // `awaitingTheApp == 0 && markedForDeletion == 0` before anything has been decrypted.
                if counts.numberOfMessages == 0 { return .thereWasNothingLeftToDo }
                if counts.numberOfMessagesStillOwed == 0 { return .thereWasNothingLeftToDo }

                // Reaching this is a fault, and the sentence the reader is shown says so: the listing has finished, work is owed, and nothing has moved for
                // half a minute. Either the app or the engine is wedged, or the server cannot be reached for the batch deletion, which backs off without
                // a cap exactly as the listing does. The end counts say which population was stuck.
                if let howLongNothingHasMoved = known.howLongNothingHasMoved, howLongNothingHasMoved >= stillnessThatMeansSomethingIsWrong {
                    return .nothingWasMovingAnyMore
                }

            }

        }

        if weAreOutOfMemoryHeadroom(given: known.headroom, knownToBeMemoryLimited: known.weKnowThisProcessIsMemoryLimited) { return .weRanOutOfMemoryHeadroom }

        return nil

    }


    /// Why a run ended before it could take the baseline counts that every figure in its report is a difference against.
    ///
    /// Three answers, worth six hours apart. The baseline is retried against ``howLongTheCountsMayBeUnreadableBeforeGivingUp``, and the retry can be left
    /// because the reader picked the device up or the window ran out of time. Only a store that went on refusing for the whole bound is
    /// `theCountsCouldNotBeRead`, the ending ``ObvInboxDrainWindowSchedule`` stands the device down six hours for.
    ///
    /// The stop flag outranks the deadline, as in ``reasonToStopBeforeAnotherRound(_:)``: *the system took the window* is a truer account than *time ran
    /// out*.
    static func reasonTheBaselineCouldNotBeTaken(isStopRequested: Bool, now: Date, deadline: Date) -> ObvInboxDrainStopReason {
        if isStopRequested { return .weWereAskedToStop }
        if now >= deadline { return .theDeadlinePassed }
        return .theCountsCouldNotBeRead
    }


    /// Whether there is too little room left to start another round.
    ///
    /// **A nought is only believed once something positive has been seen.** `os_proc_available_memory()` answers nought both for a process with no memory
    /// limit and for one that has already exceeded its limit, and the first of those is every simulator — where this loop is tested. Treating an unqualified
    /// nought as *out of room* would stand the drain down on its first round there, and would look exactly like the loop being broken.
    static func weAreOutOfMemoryHeadroom(given headroom: ObvProcessMemory.Allowance, knownToBeMemoryLimited: Bool) -> Bool {
        switch headroom {
        case .bytesRemaining(let bytes):
            return bytes < minimumBytesOfMemoryHeadroom
        case .zeroWhichIsAmbiguous:
            return knownToBeMemoryLimited
        }
    }


    // MARK: Constants

    /// How long the counts may stand completely still, with work owed and the listing finished, before the drain concludes that something is wrong.
    ///
    /// Generous on purpose, because the two ways of being wrong are not comparable. Too short, and an ordinary pause between batches is reported as a
    /// fault, which in a night-time window costs six hours before the device tries again. Too long, and a genuinely stuck device keeps the screen lit a
    /// few extra seconds. Thirty seconds still catches the stall this exists for, measured as nought rows removed in a hundred idle seconds.
    static let stillnessThatMeansSomethingIsWrong = TimeInterval(seconds: 30)

    /// How long the listing may go on failing to reach the server before the drain says so and stops.
    ///
    /// Two minutes, chosen against the listing's own back-off: it retries after 5, 5, 15, 30 and 60 seconds, so two minutes is six attempts in a row that
    /// could not be made, and by then the next attempt is five minutes away. Anything shorter would stop on an episode a working network recovers from.
    static let howLongTheServerMayBeUnreachableBeforeGivingUp = TimeInterval(minutes: 2)

    /// How long the inbox counts may go on being unreadable before the drain says so and stops.
    ///
    /// Thirty seconds, which at a poll a second is thirty consecutive refusals. A count that fails to cross-process contention is answered by the next
    /// one, so a store that survives half a minute of retrying is genuinely not readable, which is the claim ``ObvInboxDrainWindowSchedule`` makes when
    /// it stands the device down for six hours. Below the bound the run carries on blind: the listing, the app and the sweep need no help from the
    /// counts, so a failed reading costs the observation and not the work.
    static let howLongTheCountsMayBeUnreadableBeforeGivingUp = TimeInterval(seconds: 30)

    /// How much room must be left before the run carries on.
    ///
    /// A floor under the process, not a forecast of the next round: a round is a poll and holds five counts, and what allocates throughout is the listing
    /// and the app. What the drain can do is stop asking the device to stay awake for work it is about to be killed for.
    static let minimumBytesOfMemoryHeadroom = 50 * 1024 * 1024

}
