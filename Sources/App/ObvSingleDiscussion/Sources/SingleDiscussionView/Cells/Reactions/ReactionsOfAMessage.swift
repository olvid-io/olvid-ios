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


/// That a message shows the reactions it has, and how to follow them.
///
/// **What those reactions *are* is deliberately not here.** Reacting inserts a `PersistedMessageReaction` and touches neither the message nor anything else the
/// cell's own stream watches, exactly as casting a vote does — so the emojis and their counts reach the chip through a stream of their own, and one arriving costs a
/// redraw of a chip rather than a pass over the whole discussion. The argument is written out in ``PollInMessage`` and applies here unchanged; the difference is
/// that this stream was already written, for the sheet that lists who reacted.
///
/// It also carries **nothing that decides a height**, where a poll's shape had to. The chip is drawn beside the date row and tucked into the bottom of the bubble,
/// and at the reader's ordinary text size it adds no height to a cell at all — so there is nothing for the model to reserve. See ``TheDateRowAndItsReactions``,
/// which is where that is arranged.
///
/// A value of this type on a cell model means *this message shows the reactions it has*; nil means it shows none, which the legacy screen says of exactly one kind
/// of message — one the reader has still to ask to see. See `SingleDiscussionViewAppDataSource.reactions(of:)`.
public struct ReactionsOfAMessage: Equatable, Sendable {

    /// Identifies the **message**, which is what the stream of reactions follows — a reaction has an identifier of its own, and it is the sheet listing them that
    /// needs those.
    ///
    /// The type is the one that stream is already keyed by rather than one of this file's own: `ObvMessageReactionsViewDataSource` and its app-side implementation
    /// were written for the reactions sheet, and a second identifier would mean a second stream manager saying the same thing.
    public let identifier: ObvMessageReactionsViewModel.MessageIdentifier

    /// The reactions this message already had when the model was built, so that a chip can be drawn on the cell's **first frame** rather than a moment later.
    ///
    /// **A seed and nothing more.** What the chip shows after that is its own stream's, which is the only thing that can report a reaction arriving: a reaction is
    /// written by inserting a `PersistedMessageReaction` and touches neither the message nor the discussion, so a cell's own model would never hear of one. This
    /// exists solely because *nothing* seeded the chip, and the cost of that was measured: every chip on the first
    /// screen arrived after the first layout, growing the content and leaving the entry short of its end, which the cover then had to wait out.
    ///
    /// **It is not what makes a reaction appear**, and a reaction landing while the reader watches still arrives through the stream and still appears — which is
    /// right, that being a thing that has just happened. What goes is a chip that was always there appearing a beat after the discussion opens.
    public let theOnesItAlreadyHad: [ObvReactionsCountViewModel.ReactionAndCount]

    public init(identifier: ObvMessageReactionsViewModel.MessageIdentifier, theOnesItAlreadyHad: [ObvReactionsCountViewModel.ReactionAndCount] = []) {
        self.identifier = identifier
        self.theOnesItAlreadyHad = theOnesItAlreadyHad
    }

}
