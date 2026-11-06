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


/// What the reader may react with, and what they have already reacted with — everything the bar of favourite emojis needs
/// that is not already known.
///
/// **Asked at press time**, in the same breath as ``WhatAMessageOffers``, and for the same reason: the answer is needed to
/// draw something within the gesture that asked for it. Reading the favourites then rather than following them also makes
/// them always current, which matters — the reader can edit their favourites from the emoji picker while this screen is
/// up, and nothing here would otherwise hear about it.
///
/// **A value of its own rather than fields on `WhatAMessageOffers`.** The favourites are a property of the *reader* and
/// the reaction is a property of *this message*; putting either into something named "what a message offers" would make
/// it a bag the next reader has to open twice.
public struct TheEmojisOnOffer: Equatable, Sendable {

    /// The reader's favourites, in order, **already cut** to the number the bar shows — five, and eight under Catalyst.
    /// Cut on the app's side because the list and the rule for how much of it to show both live there.
    public let favourites: [String]

    /// What this reader has already put on this message, and nil when they have not.
    ///
    /// It is here because the toggle needs it: the model *replaces* rather than toggles —
    /// `setReactionFromOwnedIdentity(withEmoji:)` updates the existing reaction for a non-nil emoji and deletes only when
    /// passed nil — so removing a reaction by choosing it again is the caller's work, and a caller can only do it if it
    /// knows what the reader chose last time.
    ///
    /// **Not the same fact as `WhatAMessageOffers.Entry.react(alreadyReacted:)`**, which comes from
    /// `deleteOwnReactionActionCanBeMadeAvailable` and is what the legacy menu keys its "Add a reaction" against "Change
    /// my reaction" wording on. Deriving one from the other would change that wording as a side effect.
    public let theReadersOwn: String?

    /// The single emoji a **double tap** on a message received reacts with.
    ///
    /// **It was `theEmojiTheButtonSends` until Step 56**, and the rename is the change: the two gestures deliberately sent the same
    /// thing, on the reasoning that a double tap sending one emoji while the button beside the composition bar showed another would be
    /// incoherent. Step 56 decided they are *meant* to differ, so this is now a fact about the double tap alone and the button is not
    /// involved in it. The field had exactly one consumer, which is why the rename was cheap.
    ///
    /// Nil only when the app has nothing to offer, which should not happen: there is a per-discussion emoji, a global setting behind
    /// it, and a constant behind that.
    public let theEmojiADoubleTapSends: String?

    public init(favourites: [String], theReadersOwn: String?, theEmojiADoubleTapSends: String?) {
        self.favourites = favourites
        self.theReadersOwn = theReadersOwn
        self.theEmojiADoubleTapSends = theEmojiADoubleTapSends
    }

    /// Nothing to react with and nothing reacted — what a message the reader may not react to answers, and what a preview
    /// answers when it has no settings to read.
    public static let none = TheEmojisOnOffer(favourites: [], theReadersOwn: nil, theEmojiADoubleTapSends: nil)

}


extension WhatAMessageOffers {

    /// Whether this message may be reacted to at all, which is what decides whether the bar of favourite emojis is drawn.
    ///
    /// **The same answer the menu's own entry rests on**, so there is no second rule and no second question asked of the
    /// database: `ownedIdentityIsAllowedToSetReaction` decided it once, at press time. It falls out of this that a system
    /// message never shows a bar, never offering that entry.
    public var offersToReact: Bool {
        entries.contains { entry in
            if case .react = entry { return true } else { return false }
        }
    }

    /// Whether the body of this message may be rewritten, which is what a **double tap on a message the reader sent** asks.
    ///
    /// **The same answer the menu's entry rests on**, for the reason its neighbour above gives: `editBodyActionCanBeMadeAvailableForSentMessage`
    /// decided it once, at press time, and a second rule would be a second thing to keep in step. It is what makes the gesture *silent* on a
    /// sent message that cannot be edited — wiped, read once, a location still being shared, one sent from another device — which is the
    /// trade Step 56 took knowingly: one rule with no exceptions, at the cost of a reader being unable to predict the silence.
    public var offersToEdit: Bool {
        entries.contains { entry in
            if case .edit = entry { return true } else { return false }
        }
    }

    /// Whether this message may be replied to, which is what a **swipe** asks before it lets the message move.
    ///
    /// **The same answer the menu's entry rests on**, for the reason its two neighbours above give: `replyToActionCanBeMadeAvailable` decided it
    /// once, at press time, and a second rule would be a second thing to keep in step. So a message that offers no reply does not move at all under
    /// the finger, rather than moving and then doing nothing — the swipe and the menu cannot come to disagree about what a message allows.
    public var offersToReply: Bool {
        entries.contains { entry in
            if case .reply = entry { return true } else { return false }
        }
    }

}
