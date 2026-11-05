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
// For `OSAllocatedUnfairLock`, which holds the channel's continuation.
import os


/// How the keyboard's own find shortcuts reach this screen: ⌘F to search, ⌘G for the next match, ⇧⌘G for the previous one.
///
/// **Why anything is needed.** Those three are not delivered to whatever is on screen. The system calls `find(_:)`, `findNext(_:)` and `findPrevious(_:)` up
/// the **responder chain**, and the app answers them far above this screen, in `MainFlowViewController`, which hands them down to whichever discussion is
/// showing. That is a UIKit arrangement with no SwiftUI equivalent, so a SwiftUI screen needs a way in.
///
/// This is that way in, and it is the *only* thing the hosting controller does with them: it receives the responder call, because UIKit requires a
/// `UIResponder`, and says so here. What a shortcut *means* is decided by the screen, in the same place the search bar's own asks are answered, a
/// `UIHostingController` staying as thin as UIKit allows.
///
/// **A stream rather than an `ObservableObject`**, for the same reason as ``WhereTheReaderWantsToGo``: a command is a thing that happened, not a state to be
/// held, and a publisher would have to invent a value to change. Only the latest is kept — holding ⌘G down means *keep going*, and a queue of a hundred
/// steps drained after the fact would be nonsense.
///
/// **A fresh stream is handed out per consumer, and this is not optional.** An `AsyncStream` may be iterated once; when the `.task` consuming it is cancelled
/// the iteration ends and every later `for await` on that same stream returns immediately, for ever. SwiftUI cancels a `.task` when its view leaves the
/// hierarchy, and **showing anything full screen takes the view under it out of the hierarchy** — so with a single shared stream these three shortcuts
/// would stop working the first time a reader opened a photograph and came back. Never seen in a walk, reaching it needing a hardware keyboard *and* a
/// photograph first. The continuation is therefore mutable and held under an `OSAllocatedUnfairLock` rather than behind an actor: this is said from a
/// `UIResponder` on the main actor and must not await anything.
public final class WhatTheFindShortcutsAsk: Sendable {

    public enum Shortcut: Sendable {

        /// ⌘F. Starts a search, or leaves one already running alone.
        case find

        /// ⌘G. The next match, which is the one **further back** in the discussion — the same direction as the up chevron. Legacy's `findNext(_:)`.
        case findNext

        /// ⇧⌘G. The previous match, further forward in the discussion. Legacy's `findPrevious(_:)`.
        case findPrevious

    }

    /// Whoever is listening now. Nil while nobody is.
    private let whoIsListening = OSAllocatedUnfairLock<AsyncStream<Shortcut>.Continuation?>(initialState: nil)

    public init() {}

    /// Everything that has been asked, in order. **One consumer at a time**, which is the screen.
    func shortcutsAskedFor() -> AsyncStream<Shortcut> {
        let (stream, continuation) = AsyncStream.makeStream(of: Shortcut.self,
                                                            bufferingPolicy: .bufferingNewest(1))
        whoIsListening.withLock { previous in
            previous?.finish()
            previous = continuation
        }
        return stream
    }

    /// Said by whatever answered the responder chain. Nothing happens if the screen has gone, or if it is not listening yet.
    public func says(_ shortcut: Shortcut) {
        // `_ =` because a single-expression closure returns whatever it evaluates to, and nothing here reads `yield`'s answer — see ``PressesOnMessages``.
        whoIsListening.withLock { _ = $0?.yield(shortcut) }
    }

}
