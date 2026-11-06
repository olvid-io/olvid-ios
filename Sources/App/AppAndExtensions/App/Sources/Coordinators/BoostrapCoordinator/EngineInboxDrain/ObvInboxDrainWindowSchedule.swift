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
import OlvidUtils


/// When to ask for the next window of the background task that drains the engine's inbox.
///
/// **A type of its own because it is the only part of this feature a test can reach.** Everything else — the loop,
/// the handler, the expiration race, the screen — needs a device, a backlog, or both, and the two
/// cannot be had on one machine. This rule needs neither: it
/// is a function of what the last run left behind and of the clock, and getting it wrong is the difference between
/// one night's work and thirty hours of it. It lived in `BackgroundTasksManager`, which reaches half the app and
/// therefore cannot be compiled into the hostless unit-test target; this file imports Foundation and `OlvidUtils`
/// and is listed in `sourcesUnderTest` in `Sources/App/AppAndExtensions/Project.swift`.
///
/// The clock is a parameter for the same reason. A rule that reads `.now` inside itself can be run but not checked.
enum ObvInboxDrainWindowSchedule {

    /// The shortest interval before asking for another window, used whenever the last run was cut off with work still
    /// outstanding.
    ///
    /// Short on purpose. A window ends when the user picks the device up, and the right moment to carry on is
    /// whenever they put it down again — which may be minutes. The floor exists only so that a run ending instantly
    /// cannot spin, and it costs no battery to be woken: this task requires external power.
    static let shortestIntervalBeforeAskingForAnotherWindow = TimeInterval(minutes: 1)

    /// The ordinary cadence, for when the last run found nothing left to do. The same six hours the app's other
    /// processing tasks use.
    static let usualIntervalBetweenDrainWindows = TimeInterval(hours: 6)


    /// What the last run found out about the inbox. **Three answers rather than two**, because *there is nothing left* and *we never looked* are different
    /// facts and only one of them justifies standing down for six hours. Two ordinary runs never look: a window whose expiration handler fires before the
    /// baseline counts come back, and a run that stood aside because another was already going.
    enum WhatWasLearnedAboutTheInbox {
        /// Something is still owed: to be decrypted, to be stored by the app, or to be swept away.
        case thereIsWorkOutstanding
        /// Nothing a drain can move is left. Rows may well remain — a message on hold, one waiting for a contact, one whose attachment the reader has not
        /// asked for — and none of them is a drain's to move.
        case thereIsNothingOutstanding
        /// The counts were never read, so this run knows nothing either way. **Not the same as `thereIsNothingOutstanding` and must never be folded into
        /// it**: the whole point of the distinction is that the rule below treats *unknown* as a reason to come back rather than as a reason to stop.
        case theInboxWasNeverRead
    }


    /// The facts of a report that ``whatWasLearnedAboutTheInbox(from:)`` reads, and no more of the report than that. The report itself reaches half the
    /// app, and this is what lets the rule be compiled into the unit tests without it.
    struct WhatTheReportHolds {
        /// Whether the last page came back truncated. Nil when the listing was never started, which is every run that ended during the stale-settings pass.
        let theServerStillHadMoreAtTheEnd: Bool?
        /// Whether the stale-settings pass returned with rows still to examine. Nil in a report written by an older build.
        let theStaleSettingsPassStoppedEarly: Bool?
        /// Whether the pass counted anything to examine, which it does before touching a row.
        let theStaleSettingsPassHadSomethingToExamine: Bool
        /// Whether the pass has returned, whichever way. False in a report stored while it was still running, which is the report an expiration handler stores.
        let theStaleSettingsPassHasEnded: Bool
        let numberOfMessagesNotYetDecryptedAtEnd: Int?
        let numberOfMessagesAwaitingTheAppAtEnd: Int?
        let numberOfMessagesStillToBeRemovedAtEnd: Int?
    }


    /// What a run found out about the inbox, from what its report holds.
    ///
    /// **A run cut off with work outstanding is the normal case**: a background processing task runs only while the device is idle and ends the moment the
    /// user picks it up, so a large backlog is meant to be crossed in many short passes. Answering *no* when the answer is *yes* postpones the next pass by
    /// hours and turns one night's work into several.
    ///
    /// **Counts that were never read answer ``WhatWasLearnedAboutTheInbox/theInboxWasNeverRead``**, not *no work*. The figures are missing when the store
    /// cannot be read, and also when a window expires before the baseline counts come back, which is an ordinary ending. Saying *unknown* lets
    /// ``earliestBeginDate(after:now:)`` decide per ending which kind of unknown it is.
    ///
    /// **The undecrypted count is work**, for the same reason it counts in `ObvInboxCounts.numberOfMessagesStillOwed`: a window cut off just after a
    /// listing has everything still to do. An older report has it nil, which reads as nought, the safe direction.
    ///
    /// **A row waiting for a manual download is not work.** A device holding one unopened photograph keeps a message marked for deletion for as long as it
    /// holds it, so the raw marked count would say *work outstanding* for ever on an ordinary device; the caller subtracts it before handing the count over.
    static func whatWasLearnedAboutTheInbox(from report: WhatTheReportHolds) -> WhatWasLearnedAboutTheInbox {
        // Asked first, and it outranks every local count: a run cut off with the server still holding pages has work outstanding however empty the inbox
        // is, and the inbox is emptiest right after a page has been listed, stored and swept. Nil, the listing never started, falls through to the counts.
        if report.theServerStillHadMoreAtTheEnd == true { return .thereIsWorkOutstanding }
        // The stale-settings pass, asked second, outranks the counts for the same reason: a held message is in none of the three counts below. A cut-off
        // pass either returned early and said so, or was still running when this report was written, which is the report the expiration handler stores.
        if report.theStaleSettingsPassStoppedEarly == true { return .thereIsWorkOutstanding }
        if report.theStaleSettingsPassHadSomethingToExamine, !report.theStaleSettingsPassHasEnded { return .thereIsWorkOutstanding }
        guard let awaitingTheApp = report.numberOfMessagesAwaitingTheAppAtEnd, let stillToBeRemoved = report.numberOfMessagesStillToBeRemovedAtEnd else { return .theInboxWasNeverRead }
        let somethingIsOwed = (report.numberOfMessagesNotYetDecryptedAtEnd ?? 0) > 0 || awaitingTheApp > 0 || stillToBeRemoved > 0
        return somethingIsOwed ? .thereIsWorkOutstanding : .thereIsNothingOutstanding
    }


    /// The four facts about the last run that the rule reads, and no more of the report than that.
    struct WhatTheLastRunLeft {

        let stopReason: ObvInboxDrainStopReason
        let whatWasLearnedAboutTheInbox: WhatWasLearnedAboutTheInbox
        /// Whether the stale-settings pass returned with rows still held. Kept apart from ``whatWasLearnedAboutTheInbox``, which it also feeds,
        /// because the rule must see it past the stop reason: the pass runs before the listing, so a run whose pass gave up on a profile goes on to
        /// list, and ends on the listing's own reason, which is usually that there was nothing left to do.
        let theStaleSettingsPassLeftRowsHeld: Bool
        let startedAt: Date

        init(stopReason: ObvInboxDrainStopReason, whatWasLearnedAboutTheInbox: WhatWasLearnedAboutTheInbox, theStaleSettingsPassLeftRowsHeld: Bool = false, startedAt: Date) {
            self.stopReason = stopReason
            self.whatWasLearnedAboutTheInbox = whatWasLearnedAboutTheInbox
            self.theStaleSettingsPassLeftRowsHeld = theStaleSettingsPassLeftRowsHeld
            self.startedAt = startedAt
        }

    }


    /// When to ask for the next window, given what the last run achieved.
    ///
    /// **The two cases are not a refinement of each other, they are opposites.** A backlog is meant to be crossed in
    /// many short passes — Apple terminates a processing task the moment the user picks the device up — so a run that
    /// ended with messages still owed should be resumed as soon as the device is idle on power again. Asking for six
    /// hours there is what turns one night's work into several days of it: a window that clears 20'000 of 100'000 and
    /// then stands down for six hours needs thirty hours of charging to finish what a night could have done.
    ///
    /// A run that found nothing waits the ordinary interval instead, so an idle device is not woken over and over for
    /// nothing. A run that found *out* nothing is treated like one that found work, unless its ending says the
    /// not-finding-out will persist: `theCountsCouldNotBeRead` and `theDrainCouldNotBeStarted` will, where an app that
    /// merely ran out of time starting up will not. The ordinary interval is counted from when the run *started*,
    /// matching `appDatabaseSync` and `appInboxSyncMessageIdsKeptForLater`, and is never in the past.
    ///
    /// - Parameter lastRun: what the previous run left, or nil when there is no report to go on, which is the request
    /// submitted *before* the work and is also a minute.
    /// - Parameter now: the clock, passed in so the rule can be checked.
    static func earliestBeginDate(after lastRun: WhatTheLastRunLeft?, now: Date) -> Date {

        guard let lastRun else { return now.addingTimeInterval(shortestIntervalBeforeAskingForAnotherWindow) }

        // Asked before the stop reason, which it outranks. The stale-settings pass runs before the listing and gives a profile up when its held
        // rows cannot be counted, which at a cold background launch is the store being busy for a few seconds; the run then lists, finds nothing,
        // and ends on *there was nothing left to do*, whose case below assumes that asking again would give the same answer. It would not: the
        // rows are still held, and a store that was busy is not one that cannot be read.
        if lastRun.theStaleSettingsPassLeftRowsHeld { return now.addingTimeInterval(shortestIntervalBeforeAskingForAnotherWindow) }

        // Asked of *unknown* as well as of *outstanding*, which is the whole of what the third case buys: a run that never looked at the inbox has settled
        // nothing, so it is the stop reason alone that decides, exactly as it does for a run that saw work left.
        switch lastRun.whatWasLearnedAboutTheInbox {
        case .thereIsNothingOutstanding:
            break
        case .thereIsWorkOutstanding, .theInboxWasNeverRead:
            switch lastRun.stopReason {
            case .weWereAskedToStop, .theDeadlinePassed, .weRanOutOfMemoryHeadroom, .theServerCouldNotBeReached, .theAppDidNotFinishInitializingInTime:
                // Cut off with work outstanding, or cut off before it could find out. Nothing about the inbox has been settled, so come back for it. The
                // last two belong here because the fault is temporary: the network may well be back in a minute, and so may an app that was too busy to
                // finish launching. A window taken away before its baseline counts came back also lands here, its report having no figures.
                return now.addingTimeInterval(shortestIntervalBeforeAskingForAnotherWindow)
            case .anotherDrainWasAlreadyRunning:
                // Standing aside settles nothing either, and the run that *is* going may well be the one from the settings, which does not ask for a
                // window when it finishes. So this asks for one shortly.
                return now.addingTimeInterval(shortestIntervalBeforeAskingForAnotherWindow)
            case .thereWasNothingLeftToDo, .nothingWasMovingAnyMore:
                // Rows may remain, but asking again immediately would produce the same answer: either there is nothing a drain can move, or nothing moved
                // when it tried. Both want the ordinary interval.
                break
            case .theCountsCouldNotBeRead, .theDrainCouldNotBeStarted:
                // Deliberately the long interval: a store that cannot be counted will not become countable in a minute, and a missing delegate is a fault
                // in how the app is put together. The one place where *unknown* does not mean *come back soon*.
                break
            }
        }

        return max(now, lastRun.startedAt.addingTimeInterval(usualIntervalBetweenDrainWindows))

    }

}
