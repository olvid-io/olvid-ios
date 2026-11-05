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
import ObvSystemIcon


/// Everything the screen knows about the messages the reader is choosing, or is not.
///
/// **Deliberately shaped like ``TheSearchOfThisDiscussion``**, which is its sibling in every respect that matters: both are modes of this screen rather than things
/// presented over it, both are entered from the ellipsis, both take the composition bar's place, and neither may run while the other does. Held as one piece of
/// state, and `Equatable`, so that ticking a message is one change rather than two.
struct TheSelectionOfSeveralMessages: Equatable {

    /// Whether the reader is choosing messages at all. It is what swaps the composition bar for the bar below, and what will put the list into edit mode.
    var isRunning: Bool = false

    /// What has been ticked.
    ///
    /// **Empty until Step 42b**, which is what gives the list its selection: 42a builds the mode and the bar, and nothing can yet be chosen. It is here from the
    /// start all the same, so that the bar counts its real source rather than a literal zero it would have to be weaned off.
    var cellIdentifiers: Set<SingleDiscussionView.CellIdentifier> = []

    /// **The message a range extends *from*** — the last plain click, ticked or unticked — Step 42e's second stage.
    ///
    /// Held here rather than in the row that was clicked, for the reason the whole of this struct is here: a row is created and destroyed as the reader scrolls,
    /// and an anchor that lives on one cannot survive the message leaving the screen, which is exactly the case a range is for. **Catalyst is the only platform
    /// that *reads* it**, ⇧-click being the one gesture a touch platform has no way to make. The property itself is unconditional, and so is the one place that
    /// writes it outside Catalyst — ``startsFrom(_:)``, which a `Select` entry calls everywhere. **That is deliberate rather than sloppy**: a stored field a
    /// platform never reads costs it nothing, where a `#if` here would be a third platform branch in a step whose standing constraint is that there are exactly
    /// two. What must not leak to a touch platform is *work*, and none does — see ``keepsOnlyWhatIsStillThere(in:)``, where an anchor test written ahead of the
    /// early return was this step's own way of making a Mac feature cost an iPhone something, and was moved.
    var theAnchor: SingleDiscussionView.CellIdentifier?

    /// What the **last ⇧-click added**, so that the next one can take it back before extending afresh, corrected on 2026-08-31.
    ///
    /// Without it a range only ever grows. ``extends(to:over:whereARowMayBeTicked:)`` unions, and a union removes nothing, so a reader who clicked message 10,
    /// ⇧-clicked 50, realised they meant 20 and ⇧-clicked 20 still had all forty-one ticked — and the trash then offered *delete for everyone* on all of them.
    /// The note on ``theAnchor`` claimed that keeping the anchor *"is what makes a range adjustable"*: it is half of what does, and this is the other half.
    ///
    /// **What was *added*, and not the range itself.** A message inside the range that the reader had already ticked with a plain click is not this extension's
    /// to take away, so it is never recorded here and survives every re-extension. Subtracting the whole previous range would have been simpler and would have
    /// quietly untick messages nobody asked to lose.
    ///
    /// Emptied whenever the anchor moves — a plain click ends the range that was adjustable and begins a new one — and whenever the anchor's message goes.
    /// The invariant is that this is always a subset of ``cellIdentifiers``; ``keepsOnlyWhatIsStillThere(in:)`` maintains it.
    var whatTheLastExtensionAdded: Set<SingleDiscussionView.CellIdentifier> = []

    /// Nothing being chosen, which is how the screen starts and what cancelling returns it to.
    static let notSelecting = TheSelectionOfSeveralMessages()


    /// **The selection a `Select` entry starts**: that one message ticked, and a range extending from it.
    ///
    /// One mutation and not two, which is what this type is a single piece of state *for* — see the note on its shape. It also says the thing plainly: the
    /// message the reader started from is both what is chosen and where a range begins, and those are not two facts.
    mutating func startsFrom(_ cellIdentifier: SingleDiscussionView.CellIdentifier) {
        cellIdentifiers = [cellIdentifier]
        theAnchor = cellIdentifier
        whatTheLastExtensionAdded = []
    }

    /// How many messages are ticked, which is the whole of what the bar says.
    var count: Int {
        cellIdentifiers.count
    }

    /// Whether anything at all has been chosen — what greys out everything the bar offers.
    var isEmpty: Bool {
        cellIdentifiers.isEmpty
    }

    /// Forgets whatever has been ticked and is no longer in the discussion.
    ///
    /// **A selection is a set of identifiers, and identifiers go away.** A message deleted from another device, or one wiped as it expires, leaves a tick behind
    /// that nothing can draw and that a deletion would then be asked to act on. Intersecting with the rows there actually are is the whole of the answer, and it
    /// costs a pass over the selection rather than over the discussion.
    mutating func keepsOnlyWhatIsStillThere(in rows: [SingleDiscussionView.CellIdentifier]) {
        // **Nothing chosen and nowhere to extend from costs nothing at all**, which is the overwhelmingly common case — a screen not in the mode — and it is
        // why this guard comes first and is widened rather than a second pass being added beside the old one.
        guard theAnchor != nil || !cellIdentifiers.isEmpty else { return }
        // Built once and asked twice. **Not `rows.contains(_:)`**: that is a linear scan of every row in the discussion, and putting one ahead of the guard
        // above was this step's own way of making a Mac feature cost a touch platform something.
        let rowsThatExist = Set(rows)
        // **The anchor is dropped with its message**, or a ⇧-click extends from nowhere. Asked before the ticks are, the returns below being about them.
        if let theAnchor, !rowsThatExist.contains(theAnchor) {
            self.theAnchor = nil
            // What the last extension added extended *from* that anchor, and there is now nothing to re-extend: a ⇧-click with no anchor is a plain click.
            whatTheLastExtensionAdded = []
        }
        guard !cellIdentifiers.isEmpty, !cellIdentifiers.isSubset(of: rowsThatExist) else { return }
        cellIdentifiers.formIntersection(rowsThatExist)
        // Keeps ``whatTheLastExtensionAdded`` a subset of what is ticked, which is what lets the guard above return early: while the ticks are all still there,
        // so is everything the last extension put among them.
        whatTheLastExtensionAdded.formIntersection(rowsThatExist)
    }


    /// **A plain click toggles**, and becomes the anchor whatever it did.
    ///
    /// The anchor is set on a click that *un*ticks as well as one that ticks: what it records is where the reader last was, not what they last chose, and a
    /// range extended from a message the reader has just unticked is a perfectly ordinary thing to want.
    mutating func ticksOrUnticks(_ cellIdentifier: SingleDiscussionView.CellIdentifier) {
        if cellIdentifiers.contains(cellIdentifier) {
            cellIdentifiers.remove(cellIdentifier)
        } else {
            cellIdentifiers.insert(cellIdentifier)
        }
        theAnchor = cellIdentifier
        // The range that was adjustable ends here: the next ⇧-click extends from *this* message, so there is nothing left to take back.
        whatTheLastExtensionAdded = []
    }


    /// **⇧-click extends the selection to the message clicked** — Step 42e's second stage, and the one modifier this screen keeps.
    ///
    /// ⌘ means *toggle*, which a plain click now does, so it has nothing left to say and is treated as one. ⇧ means *extend*, which nothing else here offers,
    /// and a reader who wants forty messages should not click forty times.
    ///
    /// Four corners, all of them the plan's and each one a thing that would otherwise be found by a reader:
    ///
    /// - **It adds rather than replaces.** A plain click toggles rather than replaces, so extending must not throw away what is already ticked.
    /// - **The anchor is left where it was**, so a second ⇧-click re-extends from the same place rather than from the last one. That is *half* of what makes a
    ///   range adjustable, and it is why this does not simply call ``ticksOrUnticks(_:)`` at the end. The other half is
    ///   ``whatTheLastExtensionAdded``, without which the union below could only ever grow the range — see there for what that cost.
    /// - **Over the rows as displayed**, which is what `rows` is, and not the model's own order. The marker sits among them and the two are not the same list.
    /// - **With no anchor it behaves as a plain click**, and becomes one — which is also what happens when the anchor's message has gone, that having been
    ///   dropped by ``keepsOnlyWhatIsStillThere(in:)``.
    ///
    /// What may be ticked is asked of the caller rather than decided here: the marker saying how many messages arrived is a row and not a message, and this
    /// type has no way to know that.
    mutating func extends(to cellIdentifier: SingleDiscussionView.CellIdentifier,
                          over rows: [SingleDiscussionView.CellIdentifier],
                          whereARowMayBeTicked mayBeTicked: (SingleDiscussionView.CellIdentifier) -> Bool) {
        guard let theAnchor,
              let fromTheAnchor = rows.firstIndex(of: theAnchor),
              let toTheClick = rows.firstIndex(of: cellIdentifier) else {
            ticksOrUnticks(cellIdentifier)
            return
        }
        // **Taken back before the new range is laid down**, which is the whole of what makes a range adjustable rather than merely re-extendable. Only what the
        // last extension itself added: anything the reader ticked by hand stays ticked, wherever it happens to lie. See ``whatTheLastExtensionAdded``.
        cellIdentifiers.subtract(whatTheLastExtensionAdded)
        let theRange = fromTheAnchor <= toTheClick ? fromTheAnchor...toTheClick : toTheClick...fromTheAnchor
        let theTicksThisRangeAsksFor = Set(rows[theRange].filter(mayBeTicked))
        // Recorded *before* the union, so that it is what this extension is adding rather than everything the range covers.
        whatTheLastExtensionAdded = theTicksThisRangeAsksFor.subtracting(cellIdentifiers)
        cellIdentifiers.formUnion(theTicksThisRangeAsksFor)
    }

}


// MARK: - What the cells read

extension EnvironmentValues {

    /// Whether the reader is choosing messages, which is what every gesture inside a cell has to stand down for.
    ///
    /// **One value read once, at the top of the cell tree, rather than at each gesture.** The plan for this step said each gesture site would decline for itself;
    /// reading it once and taking the whole message's content out of hit testing is better, and the reason is that the list of gestures is not knowable. A cell
    /// carries a long press, a double tap, taps on a photograph, on a poll's answers, on a recording's controls, on an itinerary, on a sender's name, on a
    /// reactions chip — and Step 40 will add a swipe. A rule applied per gesture is a rule that is true on the day it is written; a rule applied to the content is
    /// true for whatever is added to it later.
    ///
    /// **It does not silence the `UIDragInteraction`**, which is UIKit's and sits on the row's cell rather than inside the content — see
    /// ``TheAttachmentsOfAMessageDraggedOut``, which reads this value for itself and switches the interaction off. That is the one exception, and it is the
    /// exception the plan predicted.
    var theReaderIsChoosingMessages: Bool {
        get { self[TheReaderIsChoosingMessagesKey.self] }
        set { self[TheReaderIsChoosingMessagesKey.self] = newValue }
    }

}


private struct TheReaderIsChoosingMessagesKey: EnvironmentKey {
    /// **False where nothing says otherwise**, which is every preview and the cell drawn by the context menu's overlay: neither is in a discussion that can be
    /// choosing anything, and both must keep their gestures.
    static let defaultValue: Bool = false
}


/// The bar the reader chooses messages from, which takes the composition bar's place for as long as the choosing lasts.
///
/// **Where it is was already solved.** The composition bar is not laid out beside the transcript: it is inserted into `SingleDiscussionView`'s bottom safe
/// area, and the search bar already branches there. So this is a third branch of one `Group`, and the inset, the keyboard following it, and the measuring of
/// whichever bar is at the bottom all come free. That matters more than it sounds — the space below this list is the one quantity SwiftUI and UIKit both
/// feel entitled to adjust, and four rules on this screen were written for changes to it.
///
/// **It draws the count, and nothing that acts.** The trash was here until 2026-08-17 and is now in the navigation bar beside the way out, which is where the
/// **discussions list** puts the actions of its own select mode. Two screens of one app offering multiple selection should put their controls in the same
/// place, and the one that already shipped decides which place that is.
///
/// **So why is there still a bar?** Because the count is worth saying and there is nowhere else to say it; because something has to stand where the
/// composition bar stands, and falling back to it would offer a reader a field to type in while they choose what to delete; and because removing the bar
/// altogether would change the bottom inset by its whole height, which on this screen is never a small thing to do.
///
/// The leading side is **deliberately empty**, and this used to say that share and forward would go there when they came. Forward came, and went
/// into the navigation bar instead — beside Delete, in the menu that the trash turned into, because that is where the **discussions list** keeps the actions of
/// its own select mode and two screens of one app should not disagree about it. So the sentence is corrected rather than deleted: nothing is planned for this
/// side now, and a future share or save belongs in that menu with the others rather than here. The count sits where the trash left it.
///
/// It otherwise follows the **gallery's** bar — `DiscussionGalleryViewController.refreshToolbar()` — for two decisions worth naming as borrowed rather than
/// invented: a count that is **plural-aware**, and a zero case that says *what to do* instead of *nothing is chosen*.
///
/// A line beside the count once read *⌘-click to choose several*, true while a `List`'s selection brought Catalyst's own behaviour, where a click
/// **replaces** what is chosen. Step 42e built a selection whose every click toggles, and the sentence was removed with its string. **The shape is worth
/// keeping**: a sentence explaining a behaviour is what you write when you cannot change the behaviour, so it is also the thing to go looking for once you
/// have — and nothing will remind you.
struct TheBarForSelectingSeveralMessages: View {

    /// How many messages are ticked. Everything this bar shows is derived from it.
    let numberOfSelectedMessages: Int

    var body: some View {
        HStack(spacing: 8) {
            theCount
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .modifier(OnAPieceOfGlass())
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        // **A margin of its own on a Mac**, where nothing else provides one: an iPhone has the home indicator and a Mac has nothing, so a bar flush with the
        // bottom of the window looks wrong. Kept *inside* this view rather than by the screen, which is what the composition bar does on that platform —
        // `ComposeView.spaceKeptBelowTheBarOnThisPlatform`, whose 20pt this is. **Copied and not shared**: this module does not depend on `ObvComposition`, and
        // could not ask it in any case, the bar arriving as a view the app has already built. `TheButtonBackToTheEnd` copies two numbers from it for the same
        // reason.
        //
        // Inside the bar matters for more than tidiness, and the reason is worth keeping even though nothing depends on it today: a rule that measures whichever
        // bar is at the bottom expects the margin a Mac needs to be **part of that height** rather than added after it, or it learns a different answer for each
        // of the two bars. Such a rule existed until Step 44a and was measured being wrong in exactly that way; the height it read left the module with the probes,
        // and nothing measures the bar now.
        .padding(.bottom, Self.spaceKeptBelowTheBarOnThisPlatform)
    }


    /// What is kept below this bar, which is nothing but a Mac's 20pt. See where it is applied.
    private static var spaceKeptBelowTheBarOnThisPlatform: CGFloat {
        #if targetEnvironment(macCatalyst)
        return 20
        #else
        return 0
        #endif
    }


    /// How many messages are chosen — or, when none are, what to do about it.
    ///
    /// **The zero case is an instruction and not a count**, which is the gallery's own trick: *Select messages* rather than *0 messages selected*. A bar that
    /// announces nothing is chosen the moment it appears reads as a failure; a bar that says what to do reads as an invitation. The plural is the string
    /// catalogue's, so every language decides for itself where its own boundaries are.
    ///
    /// **Monospaced digits**, so the bar does not twitch as the count runs through the widths of the figures. `RESULT_NUMBER_%lld_OF_%lld` in the search bar is
    /// monospaced for the same reason.
    private var theCount: some View {
        Text("COUNT_MESSAGES_SELECTED_\(numberOfSelectedMessages)")
            .monospacedDigit()
            .lineLimit(1)
            // A count is the one thing in this bar that must never be squeezed to nothing; it is also the only flexible thing here, which is exactly what an
            // `HStack` takes its space from, and a `Text` that must keep its lines needs telling so.
            .fixedSize(horizontal: true, vertical: false)
    }

}


#if DEBUG

#Preview("Nothing chosen") {
    TheBarForSelectingSeveralMessages(numberOfSelectedMessages: 0)
}

#Preview("One chosen") {
    TheBarForSelectingSeveralMessages(numberOfSelectedMessages: 1)
}

#Preview("Several chosen") {
    TheBarForSelectingSeveralMessages(numberOfSelectedMessages: 12)
}

#endif
