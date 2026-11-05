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
// For `OSAllocatedUnfairLock`, which holds the channel's continuation — see ``PressesOnMessages``.
import os


// MARK: - Where the messages are

/// The bounds of every message drawn in the discussion, keyed by its row, in whichever space the reader of this preference resolves them in.
///
/// **An `Anchor<CGRect>` and not a `CGRect`.** The overlay draws a copy of a message on top of the transcript, exactly where the real one is; the message is deep
/// inside a `List` row while the overlay is a sibling of the `List`, and SwiftUI offers no way to ask where a descendant is — geometry is knowable only from
/// *inside* a view, through a `GeometryReader`, and what it reads is in that view's space and not the asker's. An anchor is the opaque value made for this: the
/// message captures its own bounds, a preference carries it up the tree, and any ancestor holding a `GeometryProxy` resolves it into its own terms with
/// `proxy[anchor]`. Publishing a plain rect instead would mean converting between coordinate spaces by hand — and carrying a value up the tree in SwiftUI *is* a
/// preference either way, so the choice was never "anchors or no preferences".
///
/// **What this costs while scrolling was measured before it was written**: no extra row body evaluations at all, and a frame profile indistinguishable from the
/// floor, at some eleven preference reductions per frame. The
/// thing that is *not* free is feeding this into `@State` once per frame, which nothing here does.
struct WhereTheMessagesAre: PreferenceKey {

    static var defaultValue: [SingleDiscussionView.CellIdentifier: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [SingleDiscussionView.CellIdentifier: Anchor<CGRect>], nextValue: () -> [SingleDiscussionView.CellIdentifier: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }

}


// MARK: - Which side a message hangs from

/// The edge of the discussion a message is aligned to, which decides three things about the lift: the point the copy scales from, the edge the menu lines up with,
/// and the side a reaction bar will bloom from when Step 22a draws one.
enum TheSideAMessageHangsFrom: Equatable, Sendable {

    /// A message received.
    case leading
    /// A message the reader sent.
    case trailing
    /// Something the discussion says about itself, which hangs from neither side.
    case centre

    /// Where the lift scales from: the near edge, so that a bubble grows away from the side it is attached to rather than drifting across the screen.
    var nearEdge: UnitPoint {
        switch self {
        case .leading: return .leading
        case .trailing: return .trailing
        case .centre: return .center
        }
    }

    /// How the menu — and, later, the reaction bar — line up within the width the message occupies.
    var alignment: Alignment {
        switch self {
        case .leading: return .topLeading
        case .trailing: return .topTrailing
        case .centre: return .top
        }
    }

    /// The corner the bar of favourite emojis blooms out of: the bottom of the near edge, the bar sitting above the message
    /// and growing away from it. See ``TheFavouriteEmojisBar``.
    var bottomOfTheNearEdge: UnitPoint {
        switch self {
        case .leading: return .bottomLeading
        case .trailing: return .bottomTrailing
        case .centre: return .bottom
        }
    }

    /// Where the bar sits within the space kept for it above the message — the same corner, as an `Alignment` for a frame.
    var whereTheBarSits: Alignment {
        switch self {
        case .leading: return .bottomLeading
        case .trailing: return .bottomTrailing
        case .centre: return .bottom
        }
    }

    /// The top of the near edge, which two things are scaled about: the lifted copy and the card that grows out of it.
    ///
    /// **The top matters as much as the side.** The copy is scaled — up a little as it rises, and *down* when the message is taller than the screen leaves room
    /// for — and it is placed by its top-left corner. Scaling about anything but the top would move that corner, and the arithmetic that decides where the message
    /// goes and where the card goes under it would be wrong by whatever the scale changed.
    var topOfTheNearEdge: UnitPoint {
        switch self {
        case .leading: return .topLeading
        case .trailing: return .topTrailing
        case .centre: return .top
        }
    }

}


// MARK: - What the context menu has its hands on

/// Which message the context menu is touching, as the views that draw the messages need to know it.
///
/// **A value in the environment rather than an object anything observes.** Two facts, both of which change a handful of times per gesture — never per frame — and
/// each of which only a message's own view needs, to answer *is this one me?*. An environment value propagates without anybody subscribing to anything, and works
/// on every version of iOS this module supports, which an `@Observable` would not.
struct TheMessageBeingLifted: Equatable {

    /// The message under a finger that has not yet been held long enough. It shrinks a little, to say the press has been noticed.
    var beingPressed: SingleDiscussionView.CellIdentifier?

    /// The message whose copy the overlay is drawing, and which is therefore drawn nowhere in the list — hidden with `.opacity(0)`, so that the row keeps exactly
    /// the height it had and nothing around it moves.
    var takenByTheOverlay: SingleDiscussionView.CellIdentifier?

    /// Nothing pressed and nothing lifted, which is what the discussion looks like almost all of the time.
    static let none = TheMessageBeingLifted()

}


// MARK: - What a message reports about being pressed

/// One thing that happened to a message under a finger.
enum PressOnAMessage: Sendable {

    /// A finger went down on it.
    case began(SingleDiscussionView.CellIdentifier)

    /// The finger left, or the press was cancelled. Also said **after** a press that was held long enough, when the finger finally lifts, which is why whoever
    /// answers these has to know what state it is in rather than trusting the order.
    case ended(SingleDiscussionView.CellIdentifier)

    /// Held long enough to mean it: the message is to be lifted.
    ///
    /// **It carries what the message is**, because the copy the overlay draws has to be drawn from something and the cell is what holds it. Reading it back from
    /// `cachedModelOfSingleDiscussionCellView(cellIdentifier:)` instead was the first arrangement and it was worse in two ways: that cache is documented as
    /// allowed to answer nothing, so a press could silently do nothing at all — the least forgivable thing a gesture can do — and what it holds may be one update
    /// behind what the cell is drawing, which is exactly the drift a *copy* must not have.
    case heldLongEnough(SingleDiscussionView.CellIdentifier, showing: SingleDiscussionCellView.Model)

    /// The reader has asked to reply to this message by **swiping** it, and the swipe's half of it.
    ///
    /// **The gesture still asks for the reply itself**, through the same `userWantsToActOnMessage(cellIdentifier:action:)` the menu's entry uses, so there is one
    /// reply path and not two. What this adds is the *other* thing a reply does on this screen: the message comes down beside the composition bar. The swipe
    /// cannot do that itself — what draws the copy is the screen, which owns the overlay, where the swipe is a recogniser several levels down inside a cell —
    /// which is the same distance this channel exists to cross for a press.
    ///
    /// **It carries what the message is**, for the two reasons ``heldLongEnough(_:showing:)`` gives: the cache is documented as allowed to answer nothing, and
    /// what it holds may be one update behind what the cell is drawing.
    ///
    /// **And how far across the pull had carried it**, so that the copy can be placed over the message rather than over the row the message is about to spring
    /// back to. The two are the same place for every other way in and are eighty points apart at the end of a swipe.
    case askedToReplyTo(SingleDiscussionView.CellIdentifier, showing: SingleDiscussionCellView.Model, pulledAcrossBy: CGFloat)

    /// The press became a **drag**: the reader held this message and then moved, and its files are now travelling.
    ///
    /// **The menu stands aside when that happens**, which is what UIKit's own pair does — one press, and the movement decides whether it meant a menu or a drag.
    /// Said from `TheAttachmentsOfAMessageDraggedOut`, which is where a drag session announces itself.
    case draggedAway(SingleDiscussionView.CellIdentifier)

}


/// How a message tells the screen that it is being pressed.
///
/// The same shape, and for the same reason, as ``WhereTheReaderWantsToGo``: the two ends are far apart and neither can reach the other — what decides to lift a
/// message is the screen, which owns the overlay, and what feels the finger is a view several levels down inside a cell. So this is the channel between them.
///
///
/// **A fresh stream for each consumer, and that is a bug fix rather than a small extra.** This used to hand out one stream, made once and iterated once — and an
/// `AsyncStream` may be iterated **once**: when the task consuming it is cancelled the iteration ends, and a second `for await` on the same stream returns
/// immediately, for ever.
///
/// The screen consumes this from a `.task`, and SwiftUI cancels a `.task` when its view leaves the hierarchy — **which is exactly what opening an attachment
/// does**, the viewer being shown full screen over it. So after a reader tapped a photograph and came back, every press was reported into a stream nobody was
/// reading, and a long press did nothing at all until they left the discussion and returned. Found on an iPhone, 2026-08-16.
///
/// Vending a new stream per consumer makes the channel survive that, and finishing the previous one keeps the "one consumer" rule true.
///
/// `Sendable` without an actor, the mutable continuation being held under a lock: a press is reported from wherever a finger is felt.
final class PressesOnMessages: Sendable {

    /// Whoever is listening now. Nil while nobody is — presses made then are dropped, which is right: the screen is not on the reader's screen.
    private let whoIsListening = OSAllocatedUnfairLock<AsyncStream<PressOnAMessage>.Continuation?>(initialState: nil)

    /// What has happened to the messages under the reader's finger, in order. **One consumer at a time**, which is the screen; asking again replaces the last.
    ///
    /// **Buffered without limit, and that is not incidental.** A press produces `began` and then, three tenths of a second later, `heldLongEnough`; keeping only
    /// the newest would let the first be dropped when the two arrive close together, and the state machine at the other end would then see a message held that it
    /// never saw pressed.
    func pressesToFollow() -> AsyncStream<PressOnAMessage> {
        let (stream, continuation) = AsyncStream.makeStream(of: PressOnAMessage.self, bufferingPolicy: .unbounded)
        whoIsListening.withLock { previous in
            previous?.finish()
            previous = continuation
        }
        return stream
    }

    func report(_ press: PressOnAMessage) {
        // **The `_ =` is what stops this returning something.** `yield` answers whether the value was buffered, a single-expression closure returns whatever
        // its expression evaluates to, and `withLock` hands that answer back — so without this the lock returns a `YieldResult?` nobody reads. There is
        // nothing here that could act on it: a press reported after the stream has finished is one nobody is listening for, which is the case this whole
        // type is written to drop.
        whoIsListening.withLock { _ = $0?.yield(press) }
    }

}


// MARK: - The environment

extension EnvironmentValues {

    /// Which message the context menu is touching — see ``TheMessageBeingLifted``.
    ///
    /// The environment rather than a parameter, for the reason ``WhereTheReaderWantsToGo`` gives: this is an ambient property of the screen, and threading it
    /// through the initialisers of a cell, of the three kinds of cell and of everything drawn inside them would put the overlay's business into the signature of
    /// the whole discussion.
    var theMessageBeingLifted: TheMessageBeingLifted {
        get { self[TheMessageBeingLiftedKey.self] }
        set { self[TheMessageBeingLiftedKey.self] = newValue }
    }

    /// How a message says it is being pressed — see ``PressesOnMessages``.
    ///
    /// Optional, with nothing as its default, so that a message drawn outside this screen — every preview of a cell — reports to nobody rather than to a stand-in
    /// whose reports are silently dropped. A press then does nothing at all, which is the honest behaviour for a cell with no screen around it.
    var pressesOnMessages: PressesOnMessages? {
        get { self[PressesOnMessagesKey.self] }
        set { self[PressesOnMessagesKey.self] = newValue }
    }

}


private struct TheMessageBeingLiftedKey: EnvironmentKey {
    static let defaultValue: TheMessageBeingLifted = .none
}


private struct PressesOnMessagesKey: EnvironmentKey {
    static let defaultValue: PressesOnMessages? = nil
}
