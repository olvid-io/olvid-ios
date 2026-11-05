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


/// What a message offers when the reader presses it — the entries of its context menu, already decided and already in
/// the order the legacy screen shows them.
///
/// **Entries, and not a bag of booleans.** The order is the legacy one and belongs in a single place; a menu that
/// renders a list cannot get it wrong, where a menu assembling itself from a dozen flags can.
///
/// **This is asked at press time, and is deliberately not part of a cell model.** Three of the rules behind it —
/// `deletionTypesThatCanBeMadeAvailableForThisMessage`, `editBodyActionCanBeMadeAvailableForSentMessage` and
/// `replyToActionCanBeMadeAvailable` — assert the main thread and work on the *view* context, two of them by simulating
/// the operation on a child context. This screen builds its cell models on a background context, for every message it
/// prefetches: putting this there would have tripped an assertion in debug and, in release, silently returned **no
/// deletion types at all**, disabling Delete on every message. It would also have run child-context simulations for
/// messages nobody ever presses. The legacy screen asks the same question at the same moment — `createMenu(for:)` runs
/// when the press is recognised.
public struct WhatAMessageOffers: Equatable, Sendable {

    /// In the order they are shown. Empty for a message that offers nothing, which draws no menu at all — as the legacy
    /// screen builds no button when its menu elements are empty.
    public let entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    public var isEmpty: Bool { entries.isEmpty }


    /// One entry of the menu. The counts are carried because they are in the wording — "Share 3 photos" — and because
    /// they are what decides whether the entry appears at all.
    ///
    /// **Counts, and never the things counted.** Building an item provider per attachment, or asking
    /// `HardLinksToFylesManager` for a URL per file, is work; it is done when an entry is *chosen*, in the action, not
    /// when the menu is drawn. A menu only needs to know how many there are.
    public enum Entry: Equatable, Sendable {

        /// What is known about this message and its delivery. Reachable on a system message too.
        case showInfo

        /// The emoji picker. `alreadyReacted` chooses between "Add a reaction" and "Change my reaction", and the icon
        /// with it, exactly as the legacy menu does.
        case react(alreadyReacted: Bool)

        case deleteOwnReaction

        case copyText

        case sharePhotos(count: Int)

        /// Everything attached, when that is a different set from the photos alone — the legacy menu omits this entry
        /// when the two sets are the same size.
        case shareAttachments(count: Int)

        case saveAttachments(count: Int)

        case reply

        case edit

        case forward

        /// Calling back from a call log. Only ever offered on a system message.
        case call

        /// Chooses several messages, starting with this one.
        ///
        /// **The second way into the mode**, the first being the ellipsis of the navigation bar. It is here because this is where the hand reaches: a reader who
        /// wants to delete several messages is already pressing one of them, and every other messenger offers it from exactly this menu.
        ///
        /// **It is not a thing done *to* the message**, which makes it the odd entry of this list: everything else acts on the message pressed, and this changes
        /// what the whole screen is doing. That is also why the screen answers it rather than the app — see `SingleDiscussionView.choose(_:on:)`.
        ///
        /// Offered wherever a message can be ticked at all, which includes a system message: those may be chosen and deleted like any other.
        case select

        /// Destructive, and the only entry drawn as such.
        case delete

    }

}


/// What the reader asked of a message, as one value.
///
/// One case per entry rather than one method each, for the reason ``AttachmentAction`` gives: a case names what it does
/// as well as a method name would while being something that can be logged and passed on, and the compiler names every
/// place that must answer when a case is added.
public enum MessageAction: Equatable, Sendable {
    case showInfo

    /// The full emoji picker, from the menu's entry or from the `+` at the end of the bar of favourites.
    case react

    /// One emoji, chosen straight from the bar of favourites — and **nil to take the reader's reaction away**, which is
    /// what choosing the one already chosen means. See ``TheEmojisOnOffer/theReadersOwn`` for why the removal cannot be
    /// left to the model: it replaces rather than toggles.
    case reactWith(emoji: String?)

    case deleteOwnReaction
    case copyText
    case sharePhotos
    case shareAttachments
    case saveAttachments
    case reply
    case edit
    case forward
    case call

    /// Chooses several messages, starting with this one.
    ///
    /// **The one action of this list the app never sees.** `SingleDiscussionView.choose(_:on:)` answers it and does not
    /// pass it on, for the reason the ellipsis's own entry is a closure rather than a `DiscussionBarAction`: nothing is
    /// presented, the screen simply changes what it is doing. An implementation of the actions protocol that receives
    /// this has been reached by a route nobody intended.
    case select

    case delete
}


extension MessageAction {

    /// Whether carrying this out puts something **on top of the screen** — a sheet, a picker, an alert, a share sheet.
    ///
    /// **It decides whether the app is asked before or after the message has flown home.** Those two used to happen at once: `SingleDiscussionView.choose(_:…)`
    /// started the return spring and fired the action in the same turn, so a sheet rose while the copy of the message was still travelling under it, and the
    /// flight was what looked wrong. The two are now serialised for these cases — which is what that function's own documentation always claimed, and what
    /// `Reply` already did.
    ///
    /// **A property on the action rather than a list at the call site, and that is the point**: the compiler makes anybody adding an entry answer this, where a
    /// list somewhere else would go quietly out of date. It is the shape ``WhatAMessageOffers/Entry/isDestructive`` already has.
    ///
    /// The ones that answer `false` are not delayed, and deliberately: they change the message rather than covering it, so their result is best written while it
    /// is on its way back rather than a third of a second after it lands — the bar of favourites being the quickest thing in this menu.
    var putsSomethingOverTheScreen: Bool {
        switch self {
        case .showInfo, .react, .sharePhotos, .shareAttachments, .saveAttachments, .edit, .forward, .call, .delete:
            return true
        case .reactWith, .deleteOwnReaction, .copyText:
            return false
        case .reply, .select:
            // Neither reaches the branch that consults this: `Reply` hands the copy over to the composition bar and waits on that, and `Select` is answered by
            // the screen and never passed on at all.
            return false
        }
    }

}


extension WhatAMessageOffers.Entry {

    /// What choosing this entry asks for. The entry carries what the *menu* needs to draw itself; the action carries
    /// only what it is.
    public var action: MessageAction {
        switch self {
        case .showInfo: return .showInfo
        case .react: return .react
        case .deleteOwnReaction: return .deleteOwnReaction
        case .copyText: return .copyText
        case .sharePhotos: return .sharePhotos
        case .shareAttachments: return .shareAttachments
        case .saveAttachments: return .saveAttachments
        case .reply: return .reply
        case .edit: return .edit
        case .forward: return .forward
        case .call: return .call
        case .select: return .select
        case .delete: return .delete
        }
    }

}
