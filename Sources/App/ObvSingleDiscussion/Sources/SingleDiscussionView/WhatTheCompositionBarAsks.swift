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


/// How the composition bar reaches this screen.
///
/// **Why anything is needed.** This screen sees the composition bar as an **opaque view** it puts in its safe area. Everything the bar offers is wired to the
/// app: the quote comes from the draft, and its close button reports through `ComposeViewActions.userWantstoRemoveReplyToMessage`, a protocol in a module
/// shared with the legacy screen. So when the reader drops a reply from the bar, the screen is the last to know — and since Step 60 the screen is holding
/// something that must go with it. It is the mirror of ``WhatTheFindShortcutsAsk``: that carries keys the screen cannot receive, this a button it cannot see.
///
/// **It carries nothing about what the screen should do.** The bar says only *the reply that was being answered has gone, and why*; what follows is decided
/// where a tap on the blur and Esc are answered. A channel carrying `putTheMessageBack` would be the app deciding, one view removed.
///
/// **The *why* is not a loophole in that rule, and it was nearly written as one.** A send wants no journey home where the reader cancelling does, and the
/// obvious channel is an `animated` flag — legacy's own shape, `hideReplyViewIfNeeded(animated:)`. But *animated* is a decision about what the screen does,
/// and the caller here is the app. ``WhatBecameOfTheReply`` is a fact about the draft instead — the reader took it away, or a message was sent carrying it —
/// and the screen draws its own conclusion. The distinction costs nothing and keeps the next such difference from arriving as a second flag.
///
/// **A fresh stream per consumer**, ``WhatTheFindShortcutsAsk``'s shape: an `AsyncStream` may be iterated **once**, so a shared one dies the first time the
/// consuming `.task` is cancelled — which here is every time the reader opens a photograph — and every later `for await` returns immediately, for ever.
///
/// Only the latest is kept. Dropping a reply twice in a frame is dropping it once.
public final class WhatTheCompositionBarAsks: Sendable {

    /// Whoever is listening now. Nil while nobody is.
    private let whoIsListening = OSAllocatedUnfairLock<AsyncStream<WhatBecameOfTheReply>.Continuation?>(initialState: nil)

    public init() {}

    /// Every time the reply being answered goes away, and what became of it. **One consumer at a time**, which is the screen.
    func timesTheReplyWentAway() -> AsyncStream<WhatBecameOfTheReply> {
        let (stream, continuation) = AsyncStream.makeStream(of: WhatBecameOfTheReply.self,
                                                            bufferingPolicy: .bufferingNewest(1))
        whoIsListening.withLock { previous in
            previous?.finish()
            previous = continuation
        }
        return stream
    }

    /// Said by whatever took the reply quote off the draft — the panel's own close button, or Esc reaching past everything the screen had to dismiss.
    ///
    /// **Said whether or not a message is beside the bar**, the invariant being *no quote, no message beside the bar*: whether one is down is a fact of the screen
    /// rather than of the caller, and the screen makes this a no-op when nothing is. Asking the caller to know would put the invariant in two places and break it
    /// the next time Esc's priorities change.
    public func theReplyBeingAnsweredWasDropped() {
        saysWhatBecameOfIt(.theReaderDroppedIt)
    }


    /// Said when a message was sent carrying the reply, which consumes the whole draft and the quote with it — added 2026-08-28.
    ///
    /// **The third place the quote is dropped, and it was missing entirely.** The bar stops showing the quotation on its own, so the fault was invisible until
    /// Step 60 gave the screen a message of its own to put away: the copy stayed hanging over a discussion that stayed blurred, and further messages answered
    /// nothing. Legacy hides its reply view here too — `NewSingleDiscussionViewController.userWantsToSendDraft(_:discussionIdentifier:attributedText:)`.
    public func theReplyBeingAnsweredWasSent() {
        saysWhatBecameOfIt(.aMessageWasSentWithIt)
    }


    private func saysWhatBecameOfIt(_ whatBecameOfIt: WhatBecameOfTheReply) {
        // `_ =` because a single-expression closure returns whatever it evaluates to, and nothing here reads `yield`'s answer — see ``PressesOnMessages``.
        whoIsListening.withLock { _ = $0?.yield(whatBecameOfIt) }
    }

}


/// What became of the reply that was being answered — **a fact about the world, and never an instruction to the screen**. See ``WhatTheCompositionBarAsks``.
public enum WhatBecameOfTheReply: Sendable {

    /// The reader took it away: the quote panel's own close button, or Esc.
    case theReaderDroppedIt

    /// A message was sent carrying it. The reply has become a message, so there is nothing left to give back.
    case aMessageWasSentWithIt

}
