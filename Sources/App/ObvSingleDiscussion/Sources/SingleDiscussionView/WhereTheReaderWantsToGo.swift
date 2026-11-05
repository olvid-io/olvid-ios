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
// For `OSAllocatedUnfairLock`, which holds the channel's continuation.
import os


/// How something inside a cell asks the list to take the reader to another row.
///
/// It exists because the two ends are far apart and neither can reach the other: the `ScrollViewProxy` belongs to
/// ``SingleDiscussionCellsListView``, and what asks is a reply header several views down inside a cell. So this is the channel between them, and deliberately the
/// *only* one — moving between the results of a search, Step 23b, is the same question asked by somebody else, which is why nothing here is named after replies.
///
/// **A stream of rows rather than a callback.** Where the list must go is a fact, and the list reads it where it can act on it — inside its own `ScrollViewReader`,
/// in a `.task`, exactly as it reads everything else on this screen. A closure would have had to capture the proxy and outlive the closure it is valid in.
///
/// `Sendable` without an actor, the mutable continuation being held under a lock: a row may be asked for from anywhere.
/// Only the latest row asked for is kept — a reader who taps twice while the list is still moving means the second tap.
///
/// **A fresh stream per consumer**, for the reason ``PressesOnMessages`` gives at length: an `AsyncStream` may be iterated once, the list consumes this from a
/// `.task`, and SwiftUI cancels a `.task` when the view leaves the hierarchy — which opening an attachment does. Handing out the same stream twice meant the
/// second consumer got nothing at all, so after a reader came back from a photograph, a tap on a reply header or a step through the search results moved nothing.
///
/// **Public, and owned by whoever creates the screen.** Three things now ask: a reply header, the search bar, and the app itself, which is handed a message to show
/// when the reader opens a notification or picks a result out of the global search. That third one arrives **before the list is even on screen** — from the
/// controller's `init`, where the only consumer is a `.task` that has not run — and it is kept here until somebody listens.
///
/// **The buffer does not cover that, and reading as though it did cost a bug.** `.bufferingNewest(1)` buffers inside a stream that *exists*; before ``rowsToGoTo()``
/// is first called there is no continuation and a yield goes nowhere at all. What that looked like was a discussion opened from a notification, or from a result of
/// the global search, opening at its end rather than at the message — but only when the screen was not already in the navigation stack, which is why it survived so
/// long. So the newest row asked for while nobody is listening is held under the same lock as the continuation, and handed over the moment one registers.
///
/// **And *listening* means a consumer that is still reading, which a continuation cannot say by itself** — finding 16 of the 2026-08-30 review, fixed on
/// 2026-09-01. Cancelling the consuming task ends the iteration and leaves the continuation exactly as it was, so ``goTo(_:)`` took the *somebody is listening*
/// branch and yielded into a stream nobody would ever read again. That is the same drop as the one above, in the one circumstance the fix for it could not see, and
/// the cure is to make the two states indistinguishable: a terminated stream clears the continuation, whereupon a row is **kept** by the machinery that already
/// exists for a row asked for too early.
///
/// It is worth knowing how narrow the window is, so that nobody widens the claim. The one caller that can jump into a screen already on the navigation stack is
/// `ObvFlowController.userWantsToNavigateToDiscussion`, and it **awaits** `presentedViewController?.dismissAndAwaitCompletion` before it pops and asks — so a
/// photograph is dismissed, and its dismissal finished, before the jump. What is left is the gap between that dismissal completing and SwiftUI re-running the
/// list's `.task`: a frame, not a photograph. Small enough that no walk has ever seen it, and there is no reason for the next caller to inherit it.
public final class WhereTheReaderWantsToGo: Sendable {

    /// Whoever is listening, and whatever was asked for while nobody was.
    ///
    /// The three live under one lock because they are one decision: a row is either yielded now or kept for later, and nothing may land in between.
    private struct WhatIsWaiting {
        /// Whoever is listening now. Nil while nobody is — including once their stream has been cancelled, which is what ``theConsumerListening`` is for.
        var whoIsListening: AsyncStream<SingleDiscussionView.CellIdentifier>.Continuation?
        /// **Which consumer ``whoIsListening`` belongs to**, counted up on every registration.
        ///
        /// A stream announces its own termination, and the announcement has to be matched against the continuation that is current *now*: an
        /// `AsyncStream.Continuation` is not `Equatable`, so there is nothing else to compare. Without it, a consumer registering while the previous one was being
        /// torn down would have its brand-new continuation cleared by the old one's farewell.
        var theConsumerListening = 0
        /// The newest row asked for while nobody was listening, and nil once it has been handed over.
        var theRowAskedForBeforeAnybodyListened: SingleDiscussionView.CellIdentifier?
    }

    private let whatIsWaiting = OSAllocatedUnfairLock(initialState: WhatIsWaiting())

    public init() {}

    /// The rows asked for, in order. **One consumer at a time**, which is the list; asking again replaces the last.
    ///
    /// A row asked for before this was first called is delivered here, newest only — a reader who taps two notifications before the screen exists means the second.
    func rowsToGoTo() -> AsyncStream<SingleDiscussionView.CellIdentifier> {

        let (stream, continuation) = AsyncStream.makeStream(of: SingleDiscussionView.CellIdentifier.self,
                                                            bufferingPolicy: .bufferingNewest(1))

        let (thePreviousConsumer, thisConsumer, theRowThatWasWaiting) = whatIsWaiting.withLock { waiting in
            let previous = waiting.whoIsListening
            waiting.theConsumerListening += 1
            waiting.whoIsListening = continuation
            let waited = waiting.theRowAskedForBeforeAnybodyListened
            waiting.theRowAskedForBeforeAnybodyListened = nil
            return (previous, waiting.theConsumerListening, waited)
        }

        // **Outside the lock, and it has to be.** `finish()` calls that stream's own termination handler *synchronously*, on this thread — and the handler below
        // takes this very lock. Finishing the previous consumer where the previous version did, inside `withLock`, would deadlock on an `OSAllocatedUnfairLock`,
        // which is not recursive.
        thePreviousConsumer?.finish()

        // **Registered after the continuation is already the current one**, so the farewell of a stream that terminates in the meantime is matched against a
        // consumer number that has moved on and clears nothing. Setting this on a continuation that has *already* terminated calls the handler at once, which is
        // the same harmless case by the same guard.
        continuation.onTermination = { [weak self] _ in
            self?.thatConsumerHasStoppedListening(thisConsumer)
        }

        // Into the buffer of a stream that now exists, which is where `.bufferingNewest(1)` does work: the consumer reads it on its first turn.
        if let theRowThatWasWaiting {
            continuation.yield(theRowThatWasWaiting)
        }

        return stream
    }


    /// A consumer's stream has ended — finished by the next registration, or **cancelled**, which is what SwiftUI does to the list's `.task` when the view leaves
    /// the hierarchy.
    ///
    /// Only the consumer that is still current may clear anything: see ``WhatIsWaiting/theConsumerListening``. Nothing is remembered here beyond that — a row asked
    /// for after this point finds nobody listening and is kept by ``goTo(_:)``, which is the whole of the fix and is why it is three lines rather than a mechanism.
    private func thatConsumerHasStoppedListening(_ consumer: Int) {
        whatIsWaiting.withLock { waiting in
            guard waiting.theConsumerListening == consumer else { return }
            waiting.whoIsListening = nil
        }
    }

    /// Asks the list to take the reader to a row. Nothing happens if the list does not hold it — a message deleted, or one this screen does not show — which is what
    /// the legacy screen does too, its own jump resolving an index path and giving up when there is none.
    ///
    /// Kept rather than dropped when nobody is listening yet, which is the case the app itself is in when it opens a discussion on a message — and equally when
    /// whoever *was* listening has been cancelled, the two being indistinguishable here by design. See the note on the type.
    public func goTo(_ row: SingleDiscussionView.CellIdentifier) {
        whatIsWaiting.withLock { waiting in
            if let whoIsListening = waiting.whoIsListening {
                whoIsListening.yield(row)
            } else {
                waiting.theRowAskedForBeforeAnybodyListened = row
            }
        }
    }

}


extension EnvironmentValues {

    /// The channel a cell uses to ask the list to move — see ``WhereTheReaderWantsToGo``.
    ///
    /// **The environment rather than a parameter**, for the reason `TapToRead.attachmentsAreCoveredUntilRead` gives: this is an ambient property of the screen, and
    /// threading it through the initialisers of a cell, of the two kinds of cell, and of a reply header would put the list's business into the signature of
    /// everything drawn inside it. It holds an *instance* and never a closure, which is what keeps it out of the way of SwiftUI's diffing.
    ///
    /// Optional, with nothing as its default, so that a view drawn outside a list — every preview of a cell — asks nobody and does nothing, rather than asking a
    /// stand-in whose requests are silently dropped.
    var whereTheReaderWantsToGo: WhereTheReaderWantsToGo? {
        get { self[WhereTheReaderWantsToGoKey.self] }
        set { self[WhereTheReaderWantsToGoKey.self] = newValue }
    }

}


private struct WhereTheReaderWantsToGoKey: EnvironmentKey {
    static let defaultValue: WhereTheReaderWantsToGo? = nil
}
