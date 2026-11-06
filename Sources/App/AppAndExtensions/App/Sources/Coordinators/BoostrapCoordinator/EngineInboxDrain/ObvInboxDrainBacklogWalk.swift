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


/// How far through a backlog's timeline a drain has walked, as a fraction that only ever rises.
///
/// A type of its own, like ``ObvInboxDrainWindowSchedule`` and ``ObvInboxDrainRoundDecision``, so a test can reach it: the fraction has had two defects
/// that only a device showed.
///
/// The server will not say how many messages are waiting, only whether the page it sent was the last, so there is no denominator and every count-based
/// estimate invents one. What is knowable is when the backlog got to: a listing walks forward through the messages' upload timestamps, and both ends of
/// that walk are known, where it started and the moment the run began. The fraction is where between those the walk has reached, whatever the size of
/// the backlog.
///
/// The positions come from the messages the app has stored, so this keeps moving whether the drain is doing the listing or the app is, and through the
/// wait for the app to catch up, which is most of a run.
struct ObvInboxDrainBacklogWalk {

    /// The most the walk will ever claim on its own. The last of it belongs to the server saying it has nothing left, which is the only statement that means
    /// the run is over; a bar that reaches the end while work continues is worse than one that stops short of it.
    static let asFarAsTheWalkCanClaim = 0.99

    /// The moment the run began, in the server's own milliseconds. Everything in the backlog was uploaded before this, so it is the far end of the walk, and
    /// it is fixed — which is what stops the denominator shifting under the fraction the way a count-based estimate does.
    ///
    /// Taken from this device's clock against the server's timestamps, so it carries whatever skew there is between them. Seconds, in practice, against a
    /// backlog that spans minutes at least; and a device clock behind the server's only makes the fraction reach the end early, where it is clamped.
    private let millisecondsAtTheStartOfTheRun: Int

    /// Where the backlog begins: the smallest timestamp anything has ever reported.
    ///
    /// **The smallest ever seen rather than the first**, because messages are not guaranteed to arrive in timestamp order. A position earlier than one before
    /// it widens the span being measured, which is the safe direction — the alternative is a fraction above 1 that has to be clipped, and a bar that sits at
    /// the end while the run carries on.
    private var earliestPositionSeen: Int?

    /// The highest fraction reported so far, which is what makes the bar monotonic.
    private var highestFractionSoFar: Double = 0

    /// Whether anything has ever established a position. **Nil is not nought**, and this is what tells the two apart: a run whose first message has not yet
    /// been stored has no position, and a bar at nought there says nothing is happening while the count beside it climbs.
    private(set) var aPositionHasBeenEstablished = false

    init(millisecondsAtTheStartOfTheRun: Int) {
        self.millisecondsAtTheStartOfTheRun = millisecondsAtTheStartOfTheRun
    }


    /// How far the walk has reached, or nil when that question has no answer.
    ///
    /// Every position known at this moment is passed in together, the oldest and newest messages the app has stored since the run began. The smallest
    /// widens the span, the largest is how far we have got. Raises ``highestFractionSoFar`` rather than answering freely, so that a position out of order
    /// cannot pull the bar back.
    mutating func fractionWalked(positionsInMilliseconds: [Int]) -> Double? {

        guard let furthestReached = positionsInMilliseconds.max(), let earliestOfThese = positionsInMilliseconds.min() else { return nil }

        let earliest = min(earliestPositionSeen ?? earliestOfThese, earliestOfThese)
        earliestPositionSeen = earliest

        // A backlog whose whole span is shorter than a millisecond, or a device clock far enough behind the server's to put the start of the run before the
        // messages it is fetching. Nothing to divide by; say nothing rather than assert a number.
        let span = millisecondsAtTheStartOfTheRun - earliest
        guard span > 0 else { return nil }

        aPositionHasBeenEstablished = true

        // Past the frontier, this measure is spent, and clipping it to 1 would be a bug: messages keep arriving while a drain runs, so the walk passes the
        // far end it was measured against, and pinned to 1 the bar would read as *finished* for however long the run really has left. What is left
        // arrived after the run began, which the time measure cannot speak to, so the bar holds just short of the end until the exact count takes over.
        guard furthestReached < millisecondsAtTheStartOfTheRun else {
            highestFractionSoFar = max(highestFractionSoFar, Self.asFarAsTheWalkCanClaim)
            return highestFractionSoFar
        }

        highestFractionSoFar = max(highestFractionSoFar, min(Self.asFarAsTheWalkCanClaim, Double(furthestReached - earliest) / Double(span)))
        return highestFractionSoFar

    }


    /// Raises the mark from an exact count, which is what takes over once the server says it has nothing more.
    ///
    /// The time walk is an estimate and this is not, so this one may reach 1: what remains at that point is local work — decrypting, storing, sweeping — and
    /// a count of it is better than any estimate of it.
    mutating func fractionFromTheExactCount(done: Int, outstanding: Int) -> Double {
        let total = max(1, done + outstanding)
        aPositionHasBeenEstablished = true
        highestFractionSoFar = max(highestFractionSoFar, min(1, Double(done) / Double(total)))
        return highestFractionSoFar
    }



}
