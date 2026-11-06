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


/// Why a drain of the engine's inbox stopped. Always set, and never a synonym for *it worked*:
/// ``thereWasNothingLeftToDo`` is the only ending that means the inbox is clear.
///
/// A type of its own, in a file importing Foundation alone, rather than a case nested in ``ObvInboxDrainReport``
/// where it was written. The reason is testability and nothing else: the rule that reads it —
/// ``ObvInboxDrainWindowSchedule/earliestBeginDate(after:now:)`` — is the one piece of this feature that is pure
/// logic, and the app's unit tests compile only the files named in `sourcesUnderTest`, so anything it touches has to
/// be reachable without dragging in the app. ``ObvInboxDrainReport`` knows where reports are stored, which reaches
/// the app's constants and through them UIKit; this does not.
///
/// `ObvInboxDrainReport.StopReason` remains as a typealias, so every call site reads as it did.
enum ObvInboxDrainStopReason: String, Codable, Sendable {

    case thereWasNothingLeftToDo

    case theDeadlinePassed

    /// Somebody flipped the stop flag — in a background run, that is the expiration handler, meaning the system was
    /// about to take the window away.
    case weWereAskedToStop

    /// The listing has finished, work is still owed, and nothing has moved for half a minute.
    ///
    /// **This one means something is wrong**, and it is the only ending that does. Everything else has been ruled out
    /// by the time it is reached: nothing is still arriving, and a message needs decrypting, or the app has not taken
    /// one, or a releasable row has not been swept — each of which has something whose job it is to act. Either this
    /// app is wedged, or the server cannot be reached for the batch deletion. The end counts say which population was
    /// stuck, and that is the diagnosis.
    case nothingWasMovingAnyMore

    /// The listing could not reach the server for long enough. **Deliberately not folded into ``nothingWasMovingAnyMore``**:
    /// no network looks exactly like nothing to do, and the two want opposite answers. Nothing has been learnt about
    /// the inbox here, so the next window is wanted soon rather than in six hours, and the reader is owed a different
    /// sentence.
    ///
    /// An ordinary listing answers a failure by retrying for ever, without returning and without throwing, so this is
    /// known only from the engine's own timings, which it records for every attempt including the ones that never got
    /// as far as asking: see ``ObvEngine/howLongTheListingHasBeenUnableToReachTheServer(since:now:)`` and the rule
    /// that reads it in ``ObvInboxDrainRoundDecision``.
    ///
    /// **A listing that is merely slow is not this.** Only an attempt that could not be made at all counts; an answer of
    /// any kind, refusal included, is the server being reached.
    case theServerCouldNotBeReached

    case weRanOutOfMemoryHeadroom

    case theCountsCouldNotBeRead

    /// Nothing ran: a drain was already going, and two at once would both be listing and both be counting.
    ///
    /// This asks for another window shortly rather than at the ordinary interval. It is tempting to think that whoever we stood aside for will ask for
    /// the next window, but a run started from the settings never submits one, so standing aside settles nothing and leaves nobody scheduled.
    case anotherDrainWasAlreadyRunning

    /// Nothing ran: a delegate along the chain from the screen to the coordinator was nil.
    case theDrainCouldNotBeStarted

    /// Nothing ran: a background launch did not finish building both Core Data stacks and the engine within the
    /// budget, so the window was given up before the delegate existed.
    ///
    /// **Deliberately not folded into ``theDrainCouldNotBeStarted``**, which it otherwise resembles — neither ran, and
    /// neither knows anything about the inbox. What separates them is how long the fault lasts, and that is what the
    /// next window's timing turns on: a missing delegate is a fault in how the app is put together and will still be
    /// missing in a minute, where an app that was too busy to finish launching may well not be busy in a minute. So
    /// this one asks to come back soon and that one waits the ordinary interval.
    case theAppDidNotFinishInitializingInTime

}
