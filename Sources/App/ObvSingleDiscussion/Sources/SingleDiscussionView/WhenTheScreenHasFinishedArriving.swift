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
// For `OSAllocatedUnfairLock`, which latches the one fact this carries.
import os


/// **How the screen learns that it has finished sliding into place.**
///
/// A push is the navigation controller's business and this screen is not one, so the hosting controller is told and says so here — the arrangement
/// ``WhatTheFindShortcutsAsk`` uses for ⌘F, and for the same reason: what the fact *means* is decided by the screen.
///
/// **What it is for.** The transcript is revealed once it has been sent where the discussion opens, which happens a fifth of a second in — well before the
/// push has finished. The navigation bar's background arrives at the end of that push, so a reveal made earlier shows the reader a clear bar that acquires a
/// background a moment later, for no reason they can see. Waiting for the arrival puts the change back inside the transition, where it belongs and where
/// nothing is yet being looked at.
///
/// **A latched fact and not a stream, which is the whole of the design.** The arrival may happen before anything asks about it — a discussion that opens
/// instantly, a push already over by the time the entry gets this far — and a channel that delivers only *events* would then wait for a second arrival that
/// never comes. The shape is a known one: anything one-shot behind a property is a bug waiting for the timing to change. So this answers *has it
/// arrived*, not *tell me when it does*, and a late asker gets the right answer.
///
/// **It never goes back to false.** Showing a photograph takes this screen out of the hierarchy and returning runs the controller's appearance again, but a
/// screen that has arrived once has arrived; and the entry that reads this runs once per discussion in any case.
public final class WhenTheScreenHasFinishedArriving: Sendable {

    private let itHasArrived = OSAllocatedUnfairLock<Bool>(initialState: false)

    public init() {}

    /// Whether the screen has finished sliding into place.
    var hasFinishedArriving: Bool {
        itHasArrived.withLock { $0 }
    }

    /// Said by the hosting controller once the navigation transition that brought this screen in has completed.
    public func theScreenHasFinishedArriving() {
        itHasArrived.withLock { $0 = true }
    }

}


extension EnvironmentValues {

    /// How the transcript asks whether the screen has finished arriving — see ``WhenTheScreenHasFinishedArriving``.
    var whenTheScreenHasFinishedArriving: WhenTheScreenHasFinishedArriving? {
        get { self[WhenTheScreenHasFinishedArrivingKey.self] }
        set { self[WhenTheScreenHasFinishedArrivingKey.self] = newValue }
    }

}


private struct WhenTheScreenHasFinishedArrivingKey: EnvironmentKey {
    static let defaultValue: WhenTheScreenHasFinishedArriving? = nil
}
