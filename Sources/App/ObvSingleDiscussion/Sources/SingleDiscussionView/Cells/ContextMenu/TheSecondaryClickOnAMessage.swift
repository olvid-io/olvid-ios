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
import SwiftUIIntrospect
import UIKit
import OSLog


/// A **secondary click** on a message opens what that message offers, on Mac Catalyst and nowhere else.
///
/// **Why it is needed.** The menu was already reachable on a Mac — 21b's press works with a pointer — but **click-and-hold is a touch idiom Mac readers do
/// not attempt**, and right-click, the one they do, was measured doing nothing at all. Legacy gets this free: it reaches its menu through
/// `UIContextMenuInteraction`, which answers a secondary click without being asked, and 21b replaced that interaction with a custom overlay. The platform
/// idiom went with it, and this puts it back. Step 48 rests on it too: once the menu is reachable the way the platform expects, the argument for a hover
/// control is about discoverability alone.
///
/// **The mechanism is a `UIContextMenuInteraction` used as a detector**, whose delegate reports into ``PressesOnMessages`` and answers `nil` — so UIKit
/// draws no menu of its own and 21b's overlay opens instead, from the same ``PressOnAMessage/heldLongEnough(_:showing:)`` a long press sends. There is no
/// second menu and no second path through the state machine: a secondary click is another way of **saying the same sentence**.
///
/// **It was first built as a `UITapGestureRecognizer` with `buttonMaskRequired = .secondary`, and that does not work here** — kept because the measurement
/// is worth more than the corrected code. On a Mac, with unconditional lines at the top of both methods, the recogniser was installed on every cell,
/// `isEnabled=true`, `mask=2`, and **never once called**. A secondary click on Catalyst is not delivered to a plain gesture recogniser: it goes to the
/// platform's context-menu machinery, which looks for one of these and drops the event when there is none. `buttonMaskRequired` is right on an iPad with a
/// mouse and wrong here. **Nothing but a probe separates those two cases** — a gesture that does nothing is equally explained by never being installed and
/// by never being offered the event.
///
/// **Catalyst-only is a correctness requirement, not the usual platform-scoping.** A `UIContextMenuInteraction` on a touch platform is triggered by a **long
/// press**, which is exactly how it stole the press from the SwiftUI gesture before Step 41 — the fault that left a finger unable to open the menu at all.
/// The `#if` is what keeps Step 41 intact. Measured on a Mac: with this installed, a click-and-hold still opens the menu and a press-and-move still carries
/// a message's files away, a press with a pointer being neither a secondary click nor, by itself, a drag.
struct TheSecondaryClickOnAMessage: ViewModifier {

    /// **Optional**, for the reason ``AMessageThatCanBeLifted`` gives: something drawn like a message but which is not one carries this modifier
    /// and is simply never clicked open.
    let cellIdentifier: SingleDiscussionView.CellIdentifier?

    /// What this message is, carried so that the overlay can draw a copy of it — exactly as the press carries it, and for the reason written on
    /// ``PressOnAMessage/heldLongEnough(_:showing:)``: the cache it could be read back from is allowed to answer nothing, and a *copy* must not
    /// be one update behind what the cell is drawing.
    let model: SingleDiscussionCellView.Model

    #if targetEnvironment(macCatalyst)

    /// How the screen is told that this message is to be lifted — the channel the press uses.
    @Environment(\.pressesOnMessages) private var pressesOnMessages

    /// Whether the reader is choosing messages, in which case this stands down.
    ///
    /// **It has to be told, like the drag interaction beside it and unlike everything in the content.** The screen silences a cell's gestures
    /// with one `allowsHitTesting` at the top of the content tree; this is not in the content, it is UIKit's and it is on the row's own cell, so
    /// that rule does not reach it. See ``TheAttachmentsOfAMessageDraggedOut``, which says the same of itself.
    @Environment(\.theReaderIsChoosingMessages) private var theReaderIsChoosingMessages

    /// An object rather than state: it is read from a UIKit callback, outside any SwiftUI update.
    @State private var theClick = WhatASecondaryClickAsksFor()

    func body(content: Content) -> some View {
        content
            // The same attachment point as the drag out of the discussion, and the same note applies to the version list: it follows the
            // versions the **screen** runs on rather than the ones this needs, it is a value rather than availability, so a version missing
            // from it costs no error and simply never attaches the interaction. See ``TheAttachmentsOfAMessageDraggedOut``.
            .introspect(.listCell, on: .iOS(.v18, .v26, .v27)) { cell in
                theClick.nowShowing(cellIdentifier: cellIdentifier, model: model, telling: pressesOnMessages)
                theClick.installsItself(on: cell)
            }
            // **A `task(id:)` rather than the introspection above**, for the reason ``TheAttachmentsOfAMessageDraggedOut`` gives: that closure
            // runs when SwiftUI updates the representable, and whether an environment change alone brings it round again is not something to
            // find out from a bug report.
            .task(id: theReaderIsChoosingMessages) {
                theClick.mayOpenTheMenu(!theReaderIsChoosingMessages)
            }
    }

    #else

    func body(content: Content) -> some View {
        content
    }

    #endif

}


#if targetEnvironment(macCatalyst)

/// **The interaction this feature installs, as a type of its own** — so that one can be told from any other on a cell and taken off.
///
/// It exists for the fault Step 40 measured on 2026-08-26 and this file has in the same shape. ``WhatASecondaryClickAsksFor`` is held as SwiftUI state, so it
/// belongs to the **row** rather than to the cell; when a cell is recycled by another row it is handed a *fresh* object, which removes its own previous
/// interaction — of which it has none — and adds a second beside the one already there. Step 40's own recogniser was measured accumulating to **four** on one
/// Mac cell, and on an iPhone **191 installs in 224** found an orphan waiting.
///
/// **Here the harm is the worse of the two.** A `UIContextMenuInteraction` holds its delegate weakly, so an orphan whose owner has gone is inert; but one
/// whose owner SwiftUI is still holding has a **live delegate pointing at the message that cell used to show**, and a secondary click on it opens the menu for
/// the **wrong message**. That is exactly the defect Step 55 wrote up and believed it had fixed — and the fix it wrote covers only the one case that is never
/// at fault, this object's own previous interaction. It has not been seen misbehaving on a Mac, which is also the platform where accumulation is *rare*: 1
/// install in 31 there against 85% on a phone. An iPad with a pointer is where it would bite.
final class AContextMenuThatDetectsASecondaryClick: UIContextMenuInteraction {}


/// What a secondary click on one message asks for — see ``TheSecondaryClickOnAMessage``.
///
/// The shape of ``WhatThisMessageHandsOver`` beside it, and for the same reasons: a cell is reused, so what it shows now is pointed at rather
/// than captured, and the interaction is installed once per cell rather than once per update.
@MainActor
final class WhatASecondaryClickAsksFor: NSObject {

    private var cellIdentifier: SingleDiscussionView.CellIdentifier?
    private var model: SingleDiscussionCellView.Model?

    /// How the screen is told that this message is to be lifted.
    private weak var pressesOnMessages: PressesOnMessages?

    /// Kept so that a reused cell is not given a second interaction, which would report the same click twice — and so that the one this object put
    /// on a cell can be taken off again when the cell moves on.
    private weak var interaction: AContextMenuThatDetectsASecondaryClick?

    /// Whether a click here may open a menu at all — false while the reader is choosing messages, Step 42b.
    ///
    /// Remembered as well as applied, because a cell is reused: the next cell has to be told the same thing, and the only place that knows it at
    /// that moment is here.
    private var mayOpen = true


    /// Points this object at the message the cell shows *now*, cells being reused as the reader scrolls.
    func nowShowing(cellIdentifier: SingleDiscussionView.CellIdentifier?,
                    model: SingleDiscussionCellView.Model,
                    telling pressesOnMessages: PressesOnMessages?) {
        self.cellIdentifier = cellIdentifier
        self.model = model
        self.pressesOnMessages = pressesOnMessages
    }


    /// Puts the interaction on the row's own cell, and re-points it as cells are reused.
    func installsItself(on view: UIView) {
        guard interaction?.view !== view else { return }
        // **Two removals, and they cover different cells.** This one follows *this object* to whatever cell it was on before, which the sweep below
        // cannot reach — that looking only at the cell being moved to. It is what Step 55 wrote, and on its own it is not enough: this object is
        // freshly made on every reuse, so it never has a previous interaction to remove and the line never fires.
        let itHadOneAlready = interaction != nil
        if let interaction { interaction.view?.removeInteraction(interaction) }
        // **And this one takes off every interaction this feature ever put on the cell being moved *to*.** See
        // ``AContextMenuThatDetectsASecondaryClick`` for the measurement, and note what it must not touch: a `UIContextMenuInteraction` UIKit or the
        // `List` put there itself, which is why identifying ours by type rather than by delegate is the whole point — an orphan whose owner has gone
        // has a **nil** delegate, so a delegate test fails in precisely the case it is needed for.
        let leftBehind = (view.interactions).compactMap { $0 as? AContextMenuThatDetectsASecondaryClick }
        leftBehind.forEach { view.removeInteraction($0) }
        let interaction = AContextMenuThatDetectsASecondaryClick(delegate: self)
        view.addInteraction(interaction)
        self.interaction = interaction
        // **DEBUG INSTRUMENT, with the swipe's own, and reporting into the same category on purpose**: the two are one defect measured in
        // two places, and reading them in one stream is what makes the comparison between them possible at all. `stillLive` is the term that decides how
        // bad it was here — a live delegate is the wrong-message menu, a nil one is merely an inert interaction nobody owns.
        //
        // **Behind `#if DEBUG` since 2026-08-31**, with the eight sites it belongs to in `TheSwipeThatRepliesToAMessage`: this shipped, and the two counts it
        // ends with each walk the cell's whole interaction list to build a line no release build can read.
        #if DEBUG
        Logger(subsystem: "io.olvid.messenger", category: "TranscriptSwipe")
            .info("secondary click installed | replacedItsOwn=\(itHadOneAlready, privacy: .public) sweptUpOrphans=\(leftBehind.count, privacy: .public) stillLive=\(leftBehind.count { $0.delegate != nil }, privacy: .public) oursOnThisCell=\(view.interactions.filter { $0 is AContextMenuThatDetectsASecondaryClick }.count, privacy: .public)")
        #endif
    }


    /// Says whether a click on this message may open its menu — false while the reader is choosing messages, Step 42b.
    ///
    /// A `UIContextMenuInteraction` has no `isEnabled`, so unlike the drag interaction beside it the refusal cannot be made here; it is made where
    /// the interaction asks, in the delegate method below.
    func mayOpenTheMenu(_ mayOpen: Bool) {
        self.mayOpen = mayOpen
    }


    /// Says what a press held long enough says — the one line of behaviour in this file.
    ///
    /// No state of its own and no guard on what the menu is currently doing. The state machine at the other end already answers that — a lift is
    /// accepted from `.idle` and from a press on this same message, and refused from anything else — and while the overlay is up its backdrop is
    /// what takes clicks, so this cell is not offered them.
    private func asksForWhatThisMessageOffers() {
        guard let cellIdentifier, let model else { return }
        pressesOnMessages?.report(.heldLongEnough(cellIdentifier, showing: model))
    }

}


// MARK: - UIContextMenuInteractionDelegate

extension WhatASecondaryClickAsksFor: UIContextMenuInteractionDelegate {

    /// **Answers `nil` always, and reports on the way past.** This interaction is here to be *told about a secondary click*, which on Mac Catalyst
    /// nothing else is; the menu it would ordinarily provide is one we do not want, 21b having replaced `UIContextMenuInteraction` with an overlay
    /// that draws the bubble, the reaction bar and the card together.
    ///
    /// **A side effect in a query, deliberately.** There is no *"the reader asked for a menu"* callback to answer instead — this method **is** the
    /// signal. Two things make it safe rather than merely convenient: the report is idempotent at the other end, the state machine refusing a lift
    /// unless it is idle or already pressing this same message; and answering `nil` means UIKit does nothing at all afterwards, so there is no
    /// second phase whose absence could matter.
    ///
    /// It also **refuses while the reader is choosing messages**, and this is where that refusal has to live, the interaction having no
    /// `isEnabled` to switch.
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard mayOpen else { return nil }
        asksForWhatThisMessageOffers()
        return nil
    }

}

#endif
