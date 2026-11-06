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
import UIKit
// For `OSSignposter`, which puts the entry on Instruments' Points of Interest track — see ``SingleDiscussionCellsListView/theEntryInInstruments``.
import OSLog


// Six probes lived here on 2026-08-24, one in each place that can move the transcript — five `scrollTo` callers in this file and the one
// `contentOffset =` in ``MovesTheMessagesWhenTheSpaceBelowThemChanges`` — because a frame log can say that the offset changed and never who
// changed it. They named the writer in a single run after an evening of reading had not, and they are in the history of Step 46k if that
// question is ever open again. Put all six back at once if so: the answer was which of them acted, which needs them all to speak.


/// The list of the cells of a discussion, which opens on its most recent message, as the legacy screen does.
///
/// **A `List`, and not a `ScrollView` containing a `LazyVStack`.** A lazy stack guesses the height of every cell it has never created, from the average of
/// the ones it has, so its total height is a guess — and when the screen opens, before anything near the end exists, that guess is wrong by however long
/// the discussion is. Anything positioning itself from the total then lands where there is nothing to see: a blank screen, worse the older the discussion.
/// `defaultScrollAnchor(.bottom)` and `scrollPosition(_:anchor:)` both failed this way.
///
/// A `List` estimates too, but the `UICollectionView` underneath **corrects itself**: when a real height differs from the estimate it redoes its layout and
/// adjusts the offset so that what is on screen stays on screen. With a `scrollTo` that asks for a *cell* rather than an offset, the position converges
/// instead of being decided once and left wrong.
///
/// **The price** is that `ForEach` builds every row, not only the visible ones, whenever ``cellIdentifiers`` changes — about 8µs per message, so a
/// millisecond for a few hundred and a tenth of a second for ten thousand, on every message sent or received. Only a shorter ``cellIdentifiers`` can make
/// that cheaper.
///
/// `id: \.self` is right here: a cell identifier *is* an identity, it does not depend on position or on anything that can change, and it is cheap to hash.
///
/// **Nothing moves this list except the reader's finger and the button back to the end.** Five rules once did, each correct about the case in front of it
/// and wrong about the next, and between them they wrote the offset for the same event more than once — which is why the fault was intermittent and reading
/// never settled it. All five were removed at Step 44a, at once, so that what the `List` does by default could be seen before anything was put back.
///
/// **iOS 18**, decided 2026-08-24: every iPhone that runs 17 runs 18, so supporting 17 buys no device and had already cost the composition bar's attachment
/// panel its animation.
@available(iOS 18.0, *)
struct SingleDiscussionCellsListView: View {

    let cellIdentifiers: [SingleDiscussionView.CellIdentifier]

    /// The list's sections — see `SingleDiscussionView.Model.theSections`.
    let theSections: [SingleDiscussionView.Model.TheSection]

    /// The model of the last cell, streamed alongside the identifiers — see `SingleDiscussionView.Model.lastCellModel`. Handed to that cell so that a message
    /// just sent or received shows its content at once instead of a redacted skeleton.
    let lastCellModel: SingleDiscussionCellView.Model?

    let initialCellModels: [SingleDiscussionView.CellIdentifier: SingleDiscussionCellView.Model]

    /// Whether opening the discussion waits for the transcript to be in place before uncovering it, and then sees its scroll through to the end.
    ///
    /// **A setting of the app's, on by default**, and the reasoning for it being one switch over two behaviours is with the setting itself, in
    /// `ObvMessengerSettings.Interface`. Read here rather than from the environment because the entry is the only thing that reads it, and read once as the screen
    /// is created, so a reader who changes it sees the difference on the next discussion they open.
    ///
    /// **Turning it off restores exactly what the entry did before 2026-08-26**: the cover is lifted the moment the scroll is *asked for* rather than when it has
    /// arrived, and the entry keeps whatever position that single ask reached. Both halves were faults — the reveal ran inside the entry's own layout and stuttered,
    /// and one entry in three was measured landing 526pt short of the end — and both are worth the seconds this costs only if real discussions say so, which is
    /// what the switch exists to find out.

    /// Which messages count as new since the reader entered or last replied — see `SingleDiscussionView.Model.NewMessages`.
    ///
    /// **Streamed, since Step 53**, where it used to be fixed for the life of the screen. That it is now followed does *not* mean the marker creeps down the
    /// discussion: it stays anchored above the first of these still present, and what changes underneath is which messages the set holds — one more when a message
    /// arrives, none at all once the reader replies.
    let newMessages: SingleDiscussionView.Model.NewMessages?

    /// What the discussion says about itself, above everything — see `SingleDiscussionView.InitialValues.sentenceSayingTheDiscussionIsEndToEndEncrypted`. Drawn as a
    /// fixed first row, outside the `ForEach`, which is what makes "before every message" true by construction rather than by ordering.
    let sentenceSayingTheDiscussionIsEndToEndEncrypted: String?

    let dataSource: any SingleDiscussionCellViewDataSource

    /// What the reader can ask of this screen, as opposed to what it can be told. So far only the downloading of an attachment.
    let actions: any SingleDiscussionCellViewActions

    /// Says what the reader is looking at: what is on screen now, and everything seen since the last time this was said.
    ///
    /// A closure rather than another actions protocol: the screen above already holds the one this belongs to, and what it needs from here is a fact — see
    /// `SingleDiscussionViewActions.messagesAreOnScreen(discussionIdentifier:onScreenNow:seenSinceTheLastReport:)`, where what is done with each is written down.
    let reportsWhatTheReaderIsLookingAt: (_ onScreenNow: Set<SingleDiscussionView.CellIdentifier>, _ seenSinceTheLastReport: Set<SingleDiscussionView.CellIdentifier>) -> Void

    /// Counted up by the screen each time a message that has just arrived has finished fading in — see `SingleDiscussionView.arrivalsThatHaveFinishedAppearing`.
    ///
    /// It is the *second half* of following an arrival. The decision is taken when ``cellIdentifiers`` changes and acted on here, so that the two movements
    /// happen in sequence — the message appears where it is, then the transcript scrolls to it — rather than as two animations of one event.
    let arrivalsThatHaveFinishedAppearing: Int

    /// Whatever the reader has dropped on the messages, on its way to the draft.
    ///
    /// A closure, for the same reason ``reportsWhatTheReaderIsLookingAt`` is one: the screen above holds the actions this belongs to, and what it needs from here is
    /// the item providers. See `SingleDiscussionViewActions.userDroppedItemsOnTheMessages(discussionIdentifier:itemProviders:)`.
    let itemsWereDroppedOnTheMessages: ([NSItemProvider]) -> Void

    /// The reader clicked on the messages, which on a Mac says they have finished typing. A closure for the same reason as the one above. See
    /// ``AClickOnTheMessagesTakesTheCaretAway``.
    let theReaderClickedOnTheMessages: () -> Void

    /// Which messages are ticked, written by the `List` itself.
    ///
    /// **A binding, because the two halves of this cannot live in one place.** A `List` writes its own selection, and the mode it belongs to is the screen's:
    /// the bar that counts the ticks is not in this list, and neither is the trash that acts on them.
    @Binding var selectedCellIdentifiers: Set<SingleDiscussionView.CellIdentifier>

    /// The message a ⇧-click extends *from* — Step 42e's second stage, and Catalyst's alone.
    ///
    /// A second binding rather than the whole of ``TheSelectionOfSeveralMessages``, so that what this list is handed stays the things it actually needs.
    @Binding var theAnchorOfTheSelection: SingleDiscussionView.CellIdentifier?

    /// What the last ⇧-click added, so that the next one can take it back, corrected on 2026-08-31. Catalyst's alone, like the anchor beside it.
    ///
    /// **A third binding, and it has to be one.** ``theReaderClicked(_:shiftWasHeld:over:)`` builds a fresh ``TheSelectionOfSeveralMessages`` from the bindings
    /// on every click and writes the changed parts back, so anything the type remembers between clicks must have a binding to be remembered *in*. A field added
    /// to the struct alone would be constructed, written and thrown away on the same line, and a range would go on only growing with nothing to show why.
    @Binding var whatTheLastExtensionAdded: Set<SingleDiscussionView.CellIdentifier>

    /// Whether the reader is choosing messages, which is what puts this list into edit mode.
    ///
    /// Handed down rather than read from the environment, though the cells read it there: this is the value that *drives* `editMode`, and a view that writes the
    /// environment for its children should not be reading the same key for itself.
    let theReaderIsChoosingMessages: Bool

    /// The rows of the list: the cells of the discussion, with the "new messages" marker inserted above the first message the reader had not seen.
    ///
    /// Derived here rather than handed over by the data source, which would then have to remember where the marker goes and re-insert it on every change of
    /// the discussion — the identifiers being rebuilt from scratch each time. This needs no such state: ``newMessages`` never changes, so the position is
    /// recomputed from the identifiers themselves.
    ///
    /// The marker is a row of its own, and not something drawn inside the row below it, so that the screen can *scroll to it* when the discussion opens.
    ///
    /// The position is searched for in ``cellIdentifiers`` rather than read from ``indexOfCellIdentifier``, which is state filled by an `onChange` and is
    /// therefore *not* available on the first evaluation of this body — the marker was then missing from the rows at the very moment the screen asked to scroll
    /// to it. The search costs a pass over the identifiers, and only for a discussion that has a marker at all.
    private func rowIdentifiers(with theMarker: TheMarker?) -> [SingleDiscussionView.CellIdentifier] {
        guard let theMarker else { return cellIdentifiers }
        var rowIdentifiers = cellIdentifiers
        rowIdentifiers.insert(.newMessagesMarker, at: theMarker.index)
        return rowIdentifiers
    }

    /// The rows of one section of the list.
    fileprivate struct TheRowsOfASection: Identifiable {
        let id: String
        let rows: [SingleDiscussionView.CellIdentifier]
    }

    /// The rows as displayed, cut into ``theSections``. The marker is not a cell, so it goes into the section of the message it sits above.
    ///
    /// A single section when the sections do not account for every cell, which is also what a model without sections gives.
    private func rowsOfEachSection(among theRowsAsDisplayed: [SingleDiscussionView.CellIdentifier], theMarker: TheMarker?) -> [TheRowsOfASection] {
        guard theSections.reduce(0, { $0 + $1.numberOfCells }) == cellIdentifiers.count, !theSections.isEmpty else {
            return [.init(id: "", rows: theRowsAsDisplayed)]
        }
        var theRowsOfEachSection = [TheRowsOfASection]()
        theRowsOfEachSection.reserveCapacity(theSections.count)
        // A section met twice would give two sections the same identity, which `ForEach` does not survive. It cannot happen, the sections of a discussion
        // following its order, but a suffix costs nothing.
        var timesEachSectionWasMet = [String: Int]()
        var firstCell = 0
        var firstRow = theRowsAsDisplayed.startIndex
        for theSection in theSections {
            let endOfTheCells = firstCell + theSection.numberOfCells
            let theMarkerIsInThisSection = theMarker.map({ (firstCell..<endOfTheCells).contains($0.index) }) ?? false
            let endOfTheRows = firstRow + theSection.numberOfCells + (theMarkerIsInThisSection ? 1 : 0)
            let timesMet = timesEachSectionWasMet[theSection.identifier, default: 0]
            timesEachSectionWasMet[theSection.identifier] = timesMet + 1
            theRowsOfEachSection.append(.init(id: timesMet == 0 ? theSection.identifier : "\(theSection.identifier)-\(timesMet)",
                                              rows: Array(theRowsAsDisplayed[firstRow..<endOfTheRows])))
            firstCell = endOfTheCells
            firstRow = endOfTheRows
        }
        // Whatever the sections did not account for goes into the last one rather than vanishing: the marker, were it ever below the last message.
        if firstRow < theRowsAsDisplayed.endIndex, let theLastSection = theRowsOfEachSection.popLast() {
            theRowsOfEachSection.append(.init(id: theLastSection.id, rows: theLastSection.rows + theRowsAsDisplayed[firstRow...]))
        }
        return theRowsOfEachSection
    }

    /// Where the marker goes and what it says.
    private struct TheMarker {

        /// Where in ``cellIdentifiers`` the marker is inserted: above the first message the reader had not seen that is *still in the discussion*.
        let index: Int

        /// How many new messages the marker announces.
        let numberOfNewMessages: Int

    }

    /// Where the marker goes and what it says, or nil when there is nothing to mark — including when every message it was marking has been deleted.
    ///
    /// **Both answers come out of one pass, because they are the same question asked twice.** The marker's position is the first of the new messages that is still
    /// listed, and its label counts how many of them still are — so a message deleted from anywhere in the block moves the marker down if it was the top one and
    /// leaves it alone otherwise, and takes one off the count either way. That is what the reader expects: *four new messages* becoming *three*, in place, rather
    /// than the marker disappearing because the one identifier it was pinned to has gone.
    ///
    /// **No more expensive than the `firstIndex(of:)` it replaces.** That searched for the first new message, which sits *near the end* of the discussion, so it
    /// already walked nearly the whole array; this walks it once and does a `Set` lookup per element instead of an equality test.
    ///
    /// Computed rather than kept in state filled by an `onChange`, for the reason given on ``indexOfCellIdentifier``: state written by an `onChange` does not
    /// exist on the first evaluation of the body, and this one has to — the marker must be among the rows at the very moment the screen asks to scroll to it.
    private var theMarker: TheMarker? {
        theMarker(among: cellIdentifiers)
    }


    /// The same question asked of a *given* list of identifiers, so that ``followsAMessageThatHasJustArrived(among:)`` can ask it of the identifiers it
    /// has just been handed rather than of the ones the body was last built from — Step 71's probe. The body's own answer is the property above.
    private func theMarker(among identifiers: [SingleDiscussionView.CellIdentifier]) -> TheMarker? {
        guard let newMessages else { return nil }
        var indexOfTheFirstOneStillThere: Int?
        var howManyAreStillThere = 0
        for (index, identifier) in identifiers.enumerated() where newMessages.theOnesThatCount.contains(identifier) {
            if indexOfTheFirstOneStillThere == nil { indexOfTheFirstOneStillThere = index }
            howManyAreStillThere += 1
        }
        guard let indexOfTheFirstOneStillThere else { return nil }
        return .init(index: indexOfTheFirstOneStillThere, numberOfNewMessages: howManyAreStillThere)
    }

    /// Where each cell identifier sits in ``cellIdentifiers``.
    ///
    /// Kept so that the range of rows to prefetch can be found in constant time. Rows appear many times a second while a finger is
    /// moving, and searching a discussion of thousands of messages for the index of each one is the kind of cost that only shows up
    /// on the oldest devices. This is rebuilt when the discussion itself changes, which happens far less often.
    @State private var indexOfCellIdentifier: [SingleDiscussionView.CellIdentifier: Int] = [:]

    /// Whether the list is moving because of the reader: under their finger, or still coasting after it.
    ///
    /// Nothing may be asked of the scroll view while this is true. Dragging the messages down to dismiss the keyboard makes the
    /// bottom inset shrink about thirty times while the keyboard follows the finger, and answering each of those looked like the
    /// messages being snapped to the end the moment the keyboard started to move. The finger is already moving the messages, so
    /// there is nothing to correct.
    ///
    /// `animating` is deliberately not one of these. That state is this screen's own scrolling, and the correction below has to be
    /// allowed to happen while a scroll of our own is still running.
    ///
    /// **Answered per frame since Step 46c**, by ``TheGeometryOfTheTranscriptReadPerFrame``, where it used to be a `@State` written by
    /// `onScrollPhaseChange` — the fifth and last of the iOS 18 APIs holding this screen.
    private var isUnderTheReadersFinger: Bool { theGeometry.isUnderTheReadersFinger }

    /// Which row a jump has just landed on, so that message can say *this one* — see ``TheMessageAJumpLandedOn``.
    @State private var theRowAJumpLandedOn: TheRowAJumpLandedOn = .none

    /// Whether the discussion has already been entered once, and must therefore not be entered again.
    ///
    /// **`onAppear` runs more than once, and the second time is not an entry.** Showing something full screen, such as the
    /// attachment viewer, takes the view underneath out of the hierarchy. Coming back from it runs `onDisappear` and then `onAppear`
    /// again. Asking for the end there sent the list back to the end of the discussion as soon as the reader closed a photograph they
    /// had opened halfway up, so they came back somewhere else entirely. The same happens with anything pushed on top. An `onAppear`
    /// must therefore be safe to run twice.
    ///
    /// Nothing has to be restored on the way back: the list keeps its offset, having only been detached. What is
    /// needed is to leave it alone.
    ///
    @State private var theDiscussionHasBeenEntered = false

    /// Whether the list has been sent where the discussion opens, and may therefore be looked at.
    ///
    /// **The transcript is invisible until this is true**, because until then it is showing the *top* of the discussion. A `List` opens at the top and stays
    /// there — measured, `offset=-116.0` unchanged across hundreds of frames — and the push transition is long enough for that to be seen: it was, in a
    /// screenshot taken on the way in, as a screenful of grey rounded squares, those top messages being images whose pixels had not been decoded.
    ///
    /// **Much smaller than the reveal Step 44a deleted, and the difference is instructive.** That one needed two rules — one recognising arrival from the
    /// scroll geometry, one giving up and waiting for the geometry to be still — on the belief that a scroll aimed at estimated row heights lands over several
    /// corrections and can never be said to have arrived. Measured, it lands in one: an anchor of `.bottom` on the last row resolves to the end whatever the
    /// heights above it are. So there is nothing to recognise, and the reveal is the next line after the scroll.
    ///
    /// No delay before the fade either, where the old one held blank for 100ms to hide the content settling afterwards. Nothing settles: across eight entries,
    /// from 200pt of content to 37,000pt, the first frame the display link ever saw was already exactly at the end and no second frame followed.
    ///
    /// It survives the screen leaving the hierarchy, being `@State` on a view whose identity does not change — so returning from a photograph does not blank
    /// the transcript, as it must not.
    @State private var theListHasBeenPutWhereTheDiscussionOpens = false

    /// What hides the transcript until it has been sent where the discussion opens: an opaque `systemBackground` over the list, faded away once it is there.
    ///
    /// **A cover, rather than fading the list in**, which is what legacy has always done. The earlier version read `opacity(flag ? 1 : 0)` with an
    /// `animation(_:value:)`, and the fault was the animation's **scope**: it attaches to the view *and its whole subtree*, so the 0.15s ease applied to
    /// every animatable change the `List` made in the same update — which is the entry's first real layout. It was reported as *"the appear animation feels
    /// strange, like it was interrupted mid-flight then continued"*. With a cover, nothing inside the `List` is ever in an animated transaction, and what is
    /// animated is one opacity, which costs nothing to present however busy the main thread is.
    ///
    /// **An `overlay` rather than a `ZStack`**, because a `Shape` in a `ZStack` is infinitely flexible and sizes the stack around it. An
    /// overlay is laid out in its parent's frame and takes no part in its sizing.
    ///
    /// **`allowsHitTesting` is explicit rather than relied upon.** A UIKit view at `alpha = 0` stops receiving touches, which is why legacy needs no
    /// equivalent; a SwiftUI view at `opacity(0)` is still hit-testable, and without this the cover would swallow every tap on the transcript for ever.
    ///
    /// **`ignoresSafeArea` is what makes it a cover rather than nearly one**, and the first version lacked it. An overlay respects the safe area, the list's
    /// is inset at both ends — 95pt at the top, the composition bar's ~70 at the bottom — and the transcript *scrolls under* both, so the cover stopped short
    /// of each edge and left a strip of live content showing. Extended at **every** edge rather than the bottom one that was seen, the top having the
    /// identical hole for the identical reason. It cannot hide the bars: the composition bar is a `safeAreaInset` applied *around* this view and the
    /// navigation bar is UIKit's, so both draw above whatever this puts down.
    ///
    /// **The curve and the duration are unchanged**, so this is a fix to *what* is animated, not to how it looks. No spinner, unlike legacy's: this is on
    /// screen for a fraction of a second, and something that appears and vanishes inside 150ms is noise rather than reassurance.
    @ViewBuilder
    private var theCoverUntilTheTranscriptIsInPlace: some View {
        Color(UIColor.systemBackground)
            .ignoresSafeArea()
            .opacity(theListHasBeenPutWhereTheDiscussionOpens ? 0 : 1)
            .animation(.easeIn(duration: Self.timeTheCoverTakesToFade), value: theListHasBeenPutWhereTheDiscussionOpens)
            .allowsHitTesting(!theListHasBeenPutWhereTheDiscussionOpens)
    }

    /// Whether the reader is close enough to the end that a message they *receive* should bring the end back — Step 44b's gate.
    ///
    /// **The same question `TheButtonBackToTheEnd` asks, at a far smaller tolerance**: both read ``ScrollGeometry/pointsBelowTheVisibleArea``, that one at half a
    /// screen because a button blinking in and out on a flick would be worse than one offered slightly too eagerly, this one at
    /// ``closeEnoughToTheEndToBeFollowed``.
    ///
    /// **Read before the message lands, which happens by construction rather than by care.** A message arriving is an *insertion*, and an insertion only ever
    /// makes `pointsBelowTheVisibleArea` bigger — by the height of the row that just appeared. Asked afterwards, the answer would be *no* by roughly the height
    /// of whatever arrived, which is the shape of fault that killed `MovesTheMessagesWhenTheSpaceBelowThemChanges`: its tolerance was 126.3pt and the change it
    /// had to survive was 125pt. It is read in `onChange(of: cellIdentifiers)`, which SwiftUI runs before the collection view has re-laid out, so this still
    /// holds the reading from before the arrival. And the failure mode of being wrong about that ordering is the safe one — a post-insertion reading is only
    /// ever *more* conservative, so it would decline to follow, never drag a reader out of last month.
    ///
    /// **Starts `true`**, which the deleted `isShowingTheEndOfTheDiscussion` deliberately did not: that one had to survive a discussion opening on its unread
    /// marker, far from the end, where a wrong assumption would never be corrected. This one opens at the end always, so `true` is not an assumption.
    /// **Answered per frame since Step 46b**, by ``TheGeometryOfTheTranscriptReadPerFrame``, where it used to be a `@State` written by an `onScrollGeometryChange`.
    /// Nothing about what it means changed.
    private var theReaderIsAtTheEndOfTheDiscussion: Bool { theGeometry.theReaderIsAtTheEndOfTheDiscussion }

    /// Where the transcript is, read every frame off the scroll view rather than reported by SwiftUI. It answers three questions and moves nothing.
    ///
    /// **Held, not observed.** What it publishes changes on every frame of a keyboard's animation. If this view observed it, each change would re-evaluate the
    /// `ForEach` over every row of the discussion, which SwiftUI then compares row by row: about 133 ms on an iPhone Xs for 4,760 messages, seven to eleven
    /// times per keyboard, with the composition bar unable to move meanwhile. Only three small views observe it: the button back to the end, the report made
    /// when the reader lets go, and each row's test of whether it can be read. A change then re-evaluates a few dozen views rather than the whole list.
    @StateObject private var theHolderOfTheGeometry = TheGeometryHeldWithoutBeingObserved()

    private var theGeometry: TheGeometryOfTheTranscriptReadPerFrame { theHolderOfTheGeometry.theGeometry }

    /// The message to scroll to once it has finished appearing, decided when it arrived and acted on when the screen says the fade is over.
    ///
    /// Held rather than acted on at once, because the reader is meant to see the arrival happen where it is and *then* be taken to it — see
    /// ``arrivalsThatHaveFinishedAppearing``.
    @State private var theMessageToScrollToOnceItHasAppeared: SingleDiscussionView.CellIdentifier?

    /// Whether the messages lag behind the scroll — see ``TheSpringEachMessageHangsFrom``.
    @Environment(\.elasticScrolling) private var elasticScrolling

    /// Whether the screen has finished sliding into place — see ``WhenTheScreenHasFinishedArriving``, and ``theScreenHasFinishedArriving()``, which is what the
    /// entry waits on.
    @Environment(\.whenTheScreenHasFinishedArriving) private var whenTheScreenHasFinishedArriving

    /// Whether files are on their way *out* of this discussion, which is what makes it refuse a drop until they have landed somewhere.
    ///
    /// **Owned here because both ends of it are below this view**: the cells' drag interactions set it, and the transcript's drop delegate reads it. Held as state so
    /// that it is one object for the life of the screen — an object made afresh in a body would be written into the environment on every evaluation and rebuild every
    /// cell. See ``TheDragOutOfTheDiscussion``.
    @State private var theDragOutOfTheDiscussion = TheDragOutOfTheDiscussion()

    /// How anything on this screen asks to be taken elsewhere — the message a reply answers, and the result of a search. Handed to the cells through the environment,
    /// and read here, where the `ScrollViewProxy` is. See ``WhereTheReaderWantsToGo``.
    ///
    /// **Owned by the screen rather than made here**, since Step 23b: the search bar asks the same thing from *outside* this list, where an environment value injected
    /// by the list cannot be seen. Nothing about how a request is answered changed with it.
    let whereTheReaderWantsToGo: WhereTheReaderWantsToGo

    /// What the rows have said about being seen, and what was last handed over — see ``WhatTheReaderIsLookingAt``.
    ///
    /// **An object rather than `@State`**, because nothing draws any of it. As `@State`, a row crossing the edge of what can be read wrote up to four values. Each
    /// write was a transaction that SwiftUI propagated through its graph, and transactions took a fifth of the main thread during a scroll on an iPhone Xs.
    @State private var whatTheReaderIsLookingAt = WhatTheReaderIsLookingAt()

    /// The rows the `List` was last given, for a scroll to find its row among — see ``TheRowsTheListWasLastGiven``.
    @State private var theRowsTheListWasLastGiven = TheRowsTheListWasLastGiven()

    /// Somewhere this list can be sent, held as an *intention* and not as a row.
    ///
    /// **Step 44a: only the button back to the end still names one.** This described where a discussion *opens*, and the entry that read it is gone; it is kept
    /// whole, marker case included, because 44b puts the entry back and this is the part of it that was never wrong.
    ///
    /// The difference matters. "The end" means whatever the last message happens to be at the moment the question is asked, and the
    /// last message can change while the discussion is still opening. This was seen with a message whose sender deleted it for
    /// everyone while the reader was still in the list of discussions. The identifiers this screen is created with are read before
    /// that deletion reaches the view context, so the row it had been told to open on no longer existed by the time it asked for it.
    /// `scrollTo` with an identifier the list does not contain moves nothing and says nothing, both when the screen opens and on
    /// every correction after that, so the discussion opened wherever it happened to be.
    ///
    /// Only the unread marker is a genuinely fixed row, and even that one can disappear, because the message it sits above can also
    /// be deleted.
    private enum EntryTarget {
        case theNewMessagesMarker
        case theEndOfTheDiscussion
    }

    /// The row an intention names *now*, and where in the viewport to put it. Nil for a discussion with nothing in it.
    private func rowAndAnchor(toOpenOn target: EntryTarget) -> (identifier: SingleDiscussionView.CellIdentifier, anchor: UnitPoint)? {
        switch target {
        case .theNewMessagesMarker where theMarker != nil:
            // Centred rather than put at the top, so that what came before it is visible too: a reader wants to see what they are coming back to, not only what
            // is new. A marker near the end simply lands wherever the end allows, a scroll view being unable to go past its own maximum.
            return (.newMessagesMarker, .center)
        case .theNewMessagesMarker, .theEndOfTheDiscussion:
            // Including the marker that has ceased to exist, its message having been deleted: the end is then where the discussion would have opened had there
            // been nothing new, which is the only sensible place left.
            guard let lastCellIdentifier = cellIdentifiers.last else { return nil }
            return (lastCellIdentifier, .bottom)
        }
    }

    var body: some View {
        ScrollViewReader { scrollViewProxy in
            listOfCells
                // **Opens the discussion at its last message, and this is the whole of it.** A `List` silently ignores `defaultScrollAnchor`, so the
                // position is asked for through the proxy.
                //
                // **One ask, not animated, and no correction after it.** Step 44a deleted five rules that wrote this offset, and the lesson of that was that a
                // second writer is what makes a fault intermittent — so this is deliberately the least that could work, and what it does *not* do is as much
                // the point as what it does.
                //
                // **Estimated row heights do not matter here, which took three experiments to establish.** The old entry asked repeatedly because it was
                // believed to be aiming at estimates — a discussion of 37,000pt of which only the first screenful has ever been laid out. It is not: an anchor
                // of `.bottom` on the last row resolves to *the end*, and the end is the end however wrong every height above it is. Measured across eight
                // entries, from 200pt of content to 37,000pt: the first frame the display link ever sees is already exact, and no second frame follows.
                //
                // What estimates really cost was paid elsewhere and is worth not re-learning. Handing the screen only its most recent messages, and letting the
                // rest arrive afterwards, *prepends* several hundred rows above the reader — and a `List` does not survive that: content grew 4,070 → 37,814
                // while the offset went **down**, 3,280 → 1,092, leaving the reader 35,932pt from the end. `UICollectionView` compensates for a height
                // *correction* above the viewport (content +172.6 and offset +168.4 in one frame, measured while scrolling) and not at all for an *insertion*.
                // So the whole discussion is given to the screen at once, and there is nothing to prepend.
                //
                // **A turn later, because the first layout pass has not happened yet.** `onAppear` runs before the `List` has laid out anything, and a `scrollTo`
                // asked for then has no rows to find.
                //
                // Not animated: this is where the discussion *opens*, not a movement the reader should see. Animating it would show them a fast scroll down
                // through messages they did not ask to look at.
                .onAppear {
                    // The guard against a second entry: coming back from something shown over this screen — a photograph, anything pushed on top — runs
                    // `onAppear` again, and re-opening the discussion then would take the reader away from where they left it. See ``theDiscussionHasBeenEntered``.
                    guard !theDiscussionHasBeenEntered else { return }
                    theDiscussionHasBeenEntered = true
                    Task { @MainActor in
                        let theEntryBegan = CFAbsoluteTimeGetCurrent()
                        let theEntryInInstruments = Self.theEntryInInstruments.beginInterval("entering the discussion")
                        Self.saysHowFarIntoTheEntryThisIs("the entry begins", theEntryBegan)
                        // **Once the collection view has arrived**, so that the scroll goes by index path rather than searching every row from the first — see
                        // ``scrolls(to:anchor:animated:using:)``. The introspection hands it over after `onAppear`.
                        let theCollectionViewArrived = await theCollectionViewHasArrived()
                        let whereTheEntryWent = opensTheDiscussion(using: scrollViewProxy)
                        // **Taken here and threaded through both corrections below, rather than let each take its own.** Everything between this line and them is
                        // spent *waiting*, and a jump asked for in that gap — the app opening the discussion on a message — is a scroll of our own like any other.
                        // A count taken at the correction would already include it and the stand-down would be blind to the one thing it exists to see.
                        var theScrollsTheEntryKnowsAbout = theGeometry.scrollsOfOurOwnAskedFor
                        Self.saysHowFarIntoTheEntryThisIs("the scroll has been asked for, opensOnTheEnd=\(whereTheEntryWent?.theLastRow == nil ? "no" : "yes"), scrolls=\(theScrollsTheEntryKnowsAbout)", theEntryBegan)
                        // **This bounds the cover and nothing else** — see ``theTranscriptIsBeingWatched()``. Everything below runs exactly as it did
                        // whatever this answers; all it can do is uncover early. Not asked when the collection view never came: it is the scroll view the clock
                        // reads, so the clock cannot be running, and waiting again would hold the cover for a second bound.
                        let theTranscriptIsWatched = theCollectionViewArrived ? await theTranscriptIsBeingWatched() : false
                        if !theTranscriptIsWatched {
                            theListHasBeenPutWhereTheDiscussionOpens = true
                            Self.saysHowFarIntoTheEntryThisIs("THE COVER IS LIFTED WITH NOTHING WATCHING THE TRANSCRIPT: no scroll view arrived, so nothing can say when the entry has landed and the discussion is shown as it stands", theEntryBegan)
                        }
                        // **Unconditional since 2026-08-29, the switch that used to guard this having been retired.** It existed to find out whether the
                        // wait was worth its cost on real discussions — the cost being that entering a long one takes noticeably longer — and that
                        // question is answered: the entry went from 601ms to 204ms warm on 2026-08-28, and the half before `onAppear` was then measured
                        // and found to happen entirely inside a push transition that runs ~600ms. The reader waits for the navigation, not for this. A
                        // switch whose question has been answered is a liability rather than an escape hatch.
                        do {
                            await theTranscriptSettlesBeforeItIsUncovered()
                            Self.saysHowFarIntoTheEntryThisIs("that scroll has stopped moving", theEntryBegan)
                            // **And the correction happens under the cover too** — 2026-08-28, and it is the second half of the same mistake the wait above was
                            // written for. That one waits on ``TheGeometryOfTheTranscriptReadPerFrame/aScrollOfOurOwnIsStillMoving``, which answers for the
                            // *offset* and says nothing about the row heights: the entry lands on estimates, the estimates are corrected a moment later, and the
                            // ask below puts the end right. Uncovering between the two showed the reader that correction. Measured on an iPhone 13, the cover
                            // came off at `08.738` and the offset snapped **40.7pt in a single frame at `09.088`** — 350ms after the entry and 230ms after the
                            // reveal, which is what they reported as a jump on entering.
                            //
                            // **A short prefix, and it stops the moment there is nothing to correct** — the whole window is a second and a half, which is a
                            // reasonable time to keep asking and an unreasonable time to hold a cover over a discussion. On the common path, where the entry
                            // landed exactly, this costs one sample. The window then runs in full below, so nothing this prefix declines to wait for is lost.
                            if let whereTheEntryWent {
                                switch whereTheEntryWent {
                                case .theEnd(let theEndItOpenedOn):
                                    theScrollsTheEntryKnowsAbout = await asksAgainWhileTheEndIsStillMoving(
                                        towards: theEndItOpenedOn,
                                        anchoredTo: .bottom,
                                        using: scrollViewProxy,
                                        knowingAbout: theScrollsTheEntryKnowsAbout,
                                        overAtMost: Self.timesTheEntryPutsTheEndRightBeforeUncovering,
                                        pausingBetweenTheLaterSamples: Self.timeBetweenTheEntrysLaterSamples,
                                        stoppingAtTheFirstCleanSample: true,
                                        takingItsFirstSampleAtOnce: true)
                                    Self.saysHowFarIntoTheEntryThisIs("the correction under the cover is done", theEntryBegan)
                                case .theMarker:
                                    // The marker entry gets the same check, with its own test of *in place*. Under the cover only: see the method.
                                    theScrollsTheEntryKnowsAbout = await asksAgainUntilTheMarkerHoldsStill(using: scrollViewProxy,
                                                                                                           knowingAbout: theScrollsTheEntryKnowsAbout)
                                    Self.saysHowFarIntoTheEntryThisIs("the marker's correction under the cover is done", theEntryBegan)
                                }
                                // The correction it may have just asked for is a scroll like any other, so the same wait again: uncovering while it runs would
                                // show the reader the very movement this exists to hide.
                                await theTranscriptSettlesBeforeItIsUncovered()
                                Self.saysHowFarIntoTheEntryThisIs("and its own scroll has stopped too", theEntryBegan)
                            }
                        }
                        // **The last thing waited for, and the only one that is not about the transcript.** The navigation bar takes its background at the end of the
                        // push, so uncovering before then shows a clear bar acquiring one a moment later. See ``theScreenHasFinishedArriving()``.
                        await theScreenHasFinishedArriving()
                        Self.saysHowFarIntoTheEntryThisIs("the screen has finished arriving", theEntryBegan)
                        // **And nothing is waited out here.** A fixed 100ms stood between the last of those waits and this line for one day — the fade broke
                        // without it — and it went the moment the reveal moved: see the note at ``theCoverUntilTheTranscriptIsInPlace`` for what the fade was
                        // really competing with, which was never the reveal itself.
                        theListHasBeenPutWhereTheDiscussionOpens = true
                        Self.saysHowFarIntoTheEntryThisIs("THE COVER IS LIFTED", theEntryBegan)
                        Self.theEntryInInstruments.endInterval("entering the discussion", theEntryInInstruments)
                        // **The fade's own bar, and it is the one to look inside.** A task of its own so that nothing here waits on it: what it marks is the
                        // nominal 0.15s of ``theCoverUntilTheTranscriptIsInPlace``, three frames of which are being lost to something this cannot name.
                        Task { @MainActor in
                            let theFadeInInstruments = Self.theEntryInInstruments.beginInterval("the cover fades")
                            try? await Task.sleep(seconds: Self.timeTheCoverTakesToFade)
                            Self.theEntryInInstruments.endInterval("the cover fades", theFadeInInstruments)
                        }
                        // **The entry has the same exposure as the follow, and it was measured having it** — walked on a Mac 2026-08-26, one entry in three landing
                        // `fromTheEnd=526.1` because the entry's ask reached 4094.5 and the content then re-estimated to a maximum offset of 4002.6, dragging the
                        // offset down 618pt with nothing to put it back. That falsifies what 44b concluded from fourteen entries — *the end is the end however
                        // wrong every estimated height above it is, so one ask lands exactly* — which was true fourteen times because the deflate is intermittent,
                        // not because the end is immune. Only where it opened **on the end**: on the marker, the gate answers nothing.
                        if let theEndItOpenedOn = whereTheEntryWent?.theLastRow {
                            await asksAgainWhileTheEndIsStillMoving(towards: theEndItOpenedOn,
                                                                    anchoredTo: .bottom,
                                                                    using: scrollViewProxy,
                                                                    knowingAbout: theScrollsTheEntryKnowsAbout)
                        }
                    }
                }
                // Keeps ``indexOfCellIdentifier`` in step with the discussion.
                // **Two things, in this order, and the order is the whole of why they share one handler**. Whether a message has arrived is decided
                // against the *previous* ``indexOfCellIdentifier``, so the answer must be taken before the dictionary is rebuilt. Two `onChange` modifiers on
                // the same value would work today and depend on the order SwiftUI happens to run them in, which is not a thing this screen relies on any more.
                .onChange(of: cellIdentifiers, initial: true) { _, newCellIdentifiers in
                    followsAMessageThatHasJustArrived(among: newCellIdentifiers)
                    indexOfCellIdentifier = Dictionary(
                        newCellIdentifiers.enumerated().map({ ($0.element, $0.offset) }),
                        uniquingKeysWith: { _, lastIndex in lastIndex })
                }
                // The second half of an arrival: the message has finished appearing, so now the transcript goes to it — see
                // ``theMessageToScrollToOnceItHasAppeared``.
                .onChange(of: arrivalsThatHaveFinishedAppearing) { _, _ in
                    Task { @MainActor in await goesToTheMessageThatHasJustAppeared(using: scrollViewProxy) }
                }
                // Takes the reader where something inside a cell asked to be taken — the message a reply answers, so far. See ``WhereTheReaderWantsToGo``.
                .task {
                    for await row in whereTheReaderWantsToGo.rowsToGoTo() {
                        await goTo(row, using: scrollViewProxy)
                    }
                }
                // **The geometry, read every frame rather than reported**, and it answers the three questions that used to be three
                // `onScrollGeometryChange` here: whether the reader is at the end, whether the way back is worth offering, and which band of
                // the list a row has to be in to have been seen. See ``TheGeometryOfTheTranscriptReadPerFrame``.
                .modifier(ReadsTheGeometryOfTheTranscriptPerFrame(theGeometry: theGeometry))
                .modifier(TheSpaceBelowTheMessagesWatchedBySwiftUI(theGeometry: theGeometry))
                // The way back, over the messages and above whichever bar is at the bottom. See ``TheButtonBackToTheEnd``.
                //
                // **Step 44a: no longer withheld until the discussion has finished opening**, there being no such moment any more — nothing puts this list
                // **Not offered until the discussion has finished opening**, which is legacy's `isTrackingEnabled`. It matters again now that a discussion can
                // open on its unread marker: the reader is then *already* far from the end, so this would be true from the first frame — and the fade that
                // hides the transcript does not cover it, `.opacity` being applied inside `listOfCells` while this overlay wraps it. The button would be the
                // one thing visible over a blank screen.
                //
                // An `.overlay` and not a sibling in a stack: everything this screen has learnt about the space under a scroll view says that a view laid out
                // beside the list can change what the list is offered — see `compose-view-integration.md`. An overlay takes no part in sizing, so the transcript
                // cannot feel it.
                .overlay(alignment: .bottomTrailing) {
                    TheButtonBackToTheEndOfferedByTheGeometry(theGeometry: theGeometry, theDiscussionHasOpened: theListHasBeenPutWhereTheDiscussionOpens) {
                        Task { await goesBackToTheEndOfTheDiscussion(using: scrollViewProxy) }
                    }
                }
                // **The scene going away, which nothing here answered.** What has been seen is handed over while the app end will still take it. Legacy
                // flushes at `didEnterBackground` and this cannot: its flush states *"no need to check whether the window is foreground active"*, those messages
                // having been vetted when they were **displayed**, where ours are vetted at the **report** — so a report made after the scene has deactivated is
                // refused, and `saysWhatTheReaderIsLookingAt()` clears what it reports. `willDeactivate` is the last moment the scene is still `foregroundActive`.
                // If that turns out not to hold, this degrades to exactly the old behaviour rather than breaking: the flush is refused, as it is today.
                //
                // **Only this half is here.** Coming *back* is answered by the app, which is the party that refused and the only one that can see a Mac window come
                // forward — see `SwiftUISingleDiscussionActions.saysAgainWhatTheReaderIsLookingAt()`. What this half exists for is the one thing the app cannot
                // know: rows that went by while the list was still moving, are no longer on screen, and are therefore in no report it has kept.
                //
                // Not filtered to this screen's own scene, and it does not need to be: another scene deactivating merely makes this say what it has a little sooner,
                // and whether that counts is the app's question — `theReaderIsReallyLooking()` asks it of *this* screen's window.
                .onReceive(NotificationCenter.default.publisher(for: UIScene.willDeactivateNotification)) { _ in
                    saysWhatTheReaderIsLookingAt()
                }
                // **The list has come to rest, so whatever went by while it was moving is said now** — the counterpart of the legacy screen's
                // `processReceivedMessagesThatBecameNotNewDuringScrolling`, and Step 46c.
                //
                // This fires on **both** edges where `onScrollPhaseChange` fired on every phase change, and the difference costs nothing: the
                // rising edge finds ``saysWhatTheReaderIsLookingAt()`` reporting nothing as seen, since it hands over `[]` while the finger is
                // down. The falling edge is the one that matters, and it is the one that clears the badge after a fling.
                .modifier(SaysWhatWasSeenWhenTheReadersHandMoves(theGeometry: theGeometry) {
                    saysWhatTheReaderIsLookingAt()
                })
        }
    }

    /// Takes the reader to a row, centred, as the legacy screen takes them to the message a reply answers.
    ///
    /// **Asked for twice**, which is copied from the legacy screen rather than added out of caution. A collection view whose cells
    /// size themselves approaches a position over several steps instead of landing on it in one, which is the same reason the
    /// opening scroll asks repeatedly. The second request is not animated, because it corrects a movement the reader has already
    /// seen.
    ///
    /// A row the list does not hold moves nothing, silently, which is what legacy does when it can find no index path for the message.
    ///
    /// **This one keeps its fixed wait, and that is a decision rather than an oversight.** Step 44b's second ask replaced the same pattern in the follow and in the
    /// way back, because both aim at *the end* and can therefore be told whether they arrived — `theReaderIsAtTheEndOfTheDiscussion` answers it per frame. A jump
    /// centres a row in the middle, where there is no such question: nothing on this screen knows how far a given row is from the centre of the viewport, so there
    /// is no condition to sample and a clock is all there is. If a jump is ever measured landing short the same way, what it needs first is that question.
    ///
    /// **Step 44a said nothing had to be stood down first, and added that whatever 44b put back would have to be. 44b put it back and it was not** — until
    /// 2026-08-30. The entry's ``asksAgainWhileTheEndIsStillMoving`` aims at the end and already had the guard for it, `scrolls != theScrollsWeKnowAbout`; what
    /// it did not have was a baseline old enough to see a jump, taking its own at a moment by which the jump had already gone through here. So the count is now
    /// the entry's, taken when the entry asked, and the stand-down works by counting rather than by a flag anybody has to remember to set — which is worth having
    /// in that form for the reason the next paragraph gives: a correction comparing counts is stood down by any future scroll nobody has thought of yet, where a
    /// flag would have to be taught about each one.
    ///
    /// **Every programmatic scroll on this screen goes through here.** One name to grep for, and one place that tells
    /// ``TheGeometryOfTheTranscriptReadPerFrame`` that the transcript is about to be moved by us.
    ///
    /// Why it must be told: `onScrollGeometryChange` does not observe a `ScrollViewProxy.scrollTo`, so the rule that positions the transcript is
    /// handed an `asItWas` from before the scroll and faithfully undoes it. 46k bounded that by magnitude, which catches a 7,900pt jump and misses a
    /// 96pt one — measured leaving the reader 166pt off the end after sending a reply. Knowing *that* a scroll happened needs no magnitude at all.
    ///
    /// **This is a convention, not a guarantee.** Nothing stops a new `scrollTo` being written that does not come through here; what there is instead
    /// is one place to look and one word to search for. The scroll itself goes through ``scrolls(to:anchor:animated:using:)``, the only caller of the proxy.
    /// - Parameter whereItIsHeaded: what this scroll is *for*. **Not defaulted, on purpose**: the note above admits this funnel is a convention rather than a
    ///   guarantee, so the least it can do is make every caller — including the next one to be written — answer the question that decides whether Step 57 goes
    ///   on believing the reader is at the end. A jump that took a reader 18,084pt up the discussion and was dragged straight back is what it cost to find out
    ///   that *a scroll happened* is not the useful fact. See ``TheGeometryOfTheTranscriptReadPerFrame/WhereAScrollOfOurOwnIsHeaded``.
    private func asksForAScrollOfOurOwn(headingFor whereItIsHeaded: TheGeometryOfTheTranscriptReadPerFrame.WhereAScrollOfOurOwnIsHeaded,
                                        _ theScroll: () -> Void) {
        theGeometry.aScrollOfOurOwnWasAskedFor(headingFor: whereItIsHeaded)
        theScroll()
    }


    /// Scrolls to a row: through the collection view, by its index path, when the collection view holds the rows the `List` was last given; through the proxy
    /// otherwise. Always called inside ``asksForAScrollOfOurOwn(headingFor:_:)``.
    ///
    /// **Not `ScrollViewProxy.scrollTo` first, because it searches.** To find a row by its identifier, SwiftUI walks the rows from the first and builds each
    /// one's view on the way (`ForEachState.firstOffset(forID:)`). A scroll to the end of a discussion of 4,760 messages cost about 950 ms on an iPhone Xs, on
    /// every opening at the end, every arrival followed and every return to the end.
    private func scrolls(to row: SingleDiscussionView.CellIdentifier, anchor: UnitPoint, animated: Bool = false, using scrollViewProxy: ScrollViewProxy) {
        let whyItSearches: String
        if let collectionView = theGeometry.theCollectionView {
            if let position = Self.scrollPosition(for: anchor) {
                switch whereTheRowIs(row, in: collectionView) {
                case .at(let indexPath):
                    collectionView.scrollToItem(at: indexPath, at: position, animated: animated)
                    Self.theScrollsLog.info("A scroll of our own went to \(indexPath.section, privacy: .public):\(indexPath.item, privacy: .public) by index path")
                    return
                case .unknown(let why):
                    whyItSearches = why
                }
            } else {
                whyItSearches = "the anchor has no scroll position"
            }
        } else {
            whyItSearches = "the collection view has not arrived"
        }
        // Said in every build: a scroll that searches works, and costs a second on a long discussion and an old phone, so it cannot be told from one that went
        // by index path except by this line.
        Self.theScrollsLog.notice("A scroll of our own searched for its row: \(whyItSearches, privacy: .public)")
        if animated {
            withAnimation { scrollViewProxy.scrollTo(row, anchor: anchor) }
        } else {
            scrollViewProxy.scrollTo(row, anchor: anchor)
        }
    }

    private static let theScrollsLog = Logger(subsystem: "io.olvid.messenger", category: "TranscriptScroll")


    private enum WhereTheRowIs {
        case at(IndexPath)
        case unknown(because: String)
    }


    /// Where a row is in the collection view, among the rows the `List` was last given — see ``TheRowsTheListWasLastGiven``. Unknown when the collection view
    /// does not hold the same sections, for instance while an update is not yet applied. The proxy is then asked instead.
    ///
    /// **Checked by counting only.** If a message is deleted and another added in the same section between the last body and the scroll, the check passes and
    /// the scroll lands one row away.
    private func whereTheRowIs(_ row: SingleDiscussionView.CellIdentifier, in collectionView: UICollectionView) -> WhereTheRowIs {
        let theRowsOfEachSection = theRowsTheListWasLastGiven.sections
        let sectionsBeforeTheRows = theRowsTheListWasLastGiven.sectionsBeforeThem
        guard !theRowsOfEachSection.isEmpty else {
            return .unknown(because: "the list has not been given its rows yet")
        }
        let numberOfSections = collectionView.numberOfSections
        guard numberOfSections == sectionsBeforeTheRows + theRowsOfEachSection.count else {
            return .unknown(because: "the collection view has \(numberOfSections) sections, the rows \(theRowsOfEachSection.count) after \(sectionsBeforeTheRows)")
        }
        // From the end, where nearly every scroll of this screen goes.
        for sectionIndex in theRowsOfEachSection.indices.reversed() {
            let rows = theRowsOfEachSection[sectionIndex].rows
            guard let item = rows.lastIndex(of: row) else { continue }
            let section = sectionsBeforeTheRows + sectionIndex
            let numberOfItems = collectionView.numberOfItems(inSection: section)
            guard numberOfItems == rows.count else {
                return .unknown(because: "section \(section) has \(numberOfItems) items in the collection view and \(rows.count) rows here")
            }
            return .at(IndexPath(item: item, section: section))
        }
        return .unknown(because: "the row is not among the rows")
    }


    /// The anchors this list scrolls with, as a collection view says them.
    private static func scrollPosition(for anchor: UnitPoint) -> UICollectionView.ScrollPosition? {
        switch anchor {
        case .top: return .top
        case .center: return .centeredVertically
        case .bottom: return .bottom
        default: return nil
        }
    }


    private func goTo(_ row: SingleDiscussionView.CellIdentifier, using scrollViewProxy: ScrollViewProxy) async {
        // **A jump that comes with the screen waits for the collection view, as the entry does**, or its first ask searches every row: opening on a message,
        // from a notification for instance. Only while the cover is up, so that if the collection view never comes, later jumps do not wait for it each time.
        if !theListHasBeenPutWhereTheDiscussionOpens {
            _ = await theCollectionViewHasArrived()
        }
        // **`aRowTheReaderAskedFor`, and this is the whole of Step 68.** A jump is a decision — the reader tapped a quote, stepped through a search, or opened
        // a notification — and until 2026-09-02 only a *finger* could overturn Step 57's belief that they were at the end. So a reply sent from the end, whose
        // quote was then tapped, jumped correctly and was put straight back: `live=1466.5 → 19550.7`, 498ms after the jump landed.
        asksForAScrollOfOurOwn(headingFor: .aRowTheReaderAskedFor) {
            scrolls(to: row, anchor: .center, animated: true, using: scrollViewProxy)
        }
        try? await Task.sleep(seconds: Self.timeToLetTheJumpLand)
        asksForAScrollOfOurOwn(headingFor: .aRowTheReaderAskedFor) { scrolls(to: row, anchor: .center, using: scrollViewProxy) }
        // **And then say which message it was**. After the correction, as the legacy screen does, and whether or not anything moved: a jump to a message
        // already on screen scrolls nothing at all, which is exactly when a reader most needs telling. See ``TheMessageAJumpLandedOn``.
        //
        // **After a pause, which is not decoration.** Said the instant the scroll ends, the whole effect plays while the reader's eye is still travelling with the
        // movement, and it is over before they are looking at the message. Legacy waits a tenth of a second; a longer wait was measured to read better here.
        try? await Task.sleep(seconds: Self.timeBeforeSayingWhichMessageItWas)
        theRowAJumpLandedOn = theRowAJumpLandedOn.landedOn(row)
    }


    /// Opens the discussion where the reader left off: on the marker when they missed something, and on the most recent message otherwise.
    ///
    /// **The marker is a row in the *middle*, and that is harder to reach than the end.** An ask for the end lands exactly, however wrong the estimated heights
    /// above it are. Centring a row needs the height of every row above it, which is estimated, so the ask made here can miss by hundreds of points. The entry
    /// corrects it under the cover, with ``asksAgainUntilTheMarkerHoldsStill(using:knowingAbout:)``.
    ///
    /// A discussion whose marked message has since been deleted falls back to the end — see ``rowAndAnchor(toOpenOn:)``, which is where that is decided.
    ///
    /// - Returns: where it sent the transcript, so the caller can check it got there. Nil for a discussion with nothing in it.
    @discardableResult
    private func opensTheDiscussion(using scrollViewProxy: ScrollViewProxy) -> WhereTheEntryWent? {
        let whereItOpens: EntryTarget = newMessages == nil ? .theEndOfTheDiscussion : .theNewMessagesMarker
        guard let (identifier, anchor) = rowAndAnchor(toOpenOn: whereItOpens) else { return nil }
        let itOpensOnTheEnd = identifier == cellIdentifiers.last
        // **And the reader is then not at the end**, which nothing else would say for a while. The gate is written by the scroll geometry, whose first report
        // comes a moment after this, and until it does a message arriving would be followed to the end — taking the reader away from the very messages they
        // opened the discussion to read. The deleted `isShowingTheEndOfTheDiscussion` recorded this exact trap; it is cheaper to answer it here, where where the
        // list is being sent is known for certain, than to reason about which report arrives first.
        // Both writes are named, on the object that holds the values.
        if itOpensOnTheEnd {
            theGeometry.theDiscussionHasOpenedOnItsEnd()
        } else {
            theGeometry.theDiscussionHasOpenedAboveItsEnd()
        }
        // **And the way back to the end is not worth offering either**, for the same reason and with the same timing. The list's *first* layout is at the top of
        // the discussion, which is where the end genuinely is far below, so the way back reads `true` before this scroll happens — and it stays true until the
        // geometry is next read. What the reader sees in that interval is the way-back button, alone on a screen the transcript has not been revealed on yet,
        // then vanishing: *"when entering the long discussion, we briefly see the button"*, walked on a Mac on 2026-08-21.
        //
        // **Only where the discussion opens on its end**, and the asymmetry is deliberate — which is why the two cases above are two named methods rather than one
        // with a flag. There, the answer is known for certain and needs no geometry: the end is exactly what the list was just sent to. Where it opens on the
        // **marker** the reader really is somewhere above the end and the button may well be worth offering, but *how far* above is a number only the geometry has,
        // so that case is left alone and corrected on the next frame like any other.
        // **The marker is a destination like any other the reader asked for**, and it must not be dragged to the end afterwards: a discussion opened on unread
        // messages is opened *there* on purpose. The end case is the one Step 57 is the net for, so it says so.
        asksForAScrollOfOurOwn(headingFor: itOpensOnTheEnd ? .theEndOfTheDiscussion : .aRowTheReaderAskedFor) {
            scrolls(to: identifier, anchor: anchor, using: scrollViewProxy)
        }
        return itOpensOnTheEnd ? .theEnd(identifier) : .theMarker
    }


    /// Where the entry sent the transcript, which decides how it is checked before the cover is lifted.
    private enum WhereTheEntryWent {

        /// The last row, anchored at the bottom.
        case theEnd(SingleDiscussionView.CellIdentifier)

        /// The unread marker, centred.
        case theMarker

        /// The last row, when that is where the entry went.
        var theLastRow: SingleDiscussionView.CellIdentifier? {
            guard case .theEnd(let theLastRow) = self else { return nil }
            return theLastRow
        }

    }


    /// Decides whether the message that has just arrived is one to follow, and remembers it, first half.
    ///
    /// **Called before ``indexOfCellIdentifier`` is rebuilt**, which is what lets *arrived* be answered exactly: the last row is an arrival when it is one the
    /// list did not previously hold. That distinguishes it from the two other things which change the identifiers and must move nothing — the last message
    /// being deleted, where the new last row is one the list has had all along, and a message elsewhere in the discussion disappearing.
    ///
    /// **A message the reader sent is followed wherever they are**, so that they see it leave; one they received only at the end. No identifier can tell the two
    /// apart, which is what `SingleDiscussionView.Model.lastCellModel` exists for.
    ///
    /// **Never under a finger.** The legacy screen has the same rule — `lastScrollWasManual`, cleared only when the reader comes to rest within 60pt of the
    /// bottom — and it is right: a reader moving the list is deciding where it sits, and taking it from them mid-drag is the rudest thing this screen could do.
    private func followsAMessageThatHasJustArrived(among newCellIdentifiers: [SingleDiscussionView.CellIdentifier]) {

        // **DEBUG INSTRUMENT, and it reports the *precondition* beside the decision**, which is the whole of why it exists. The excursion of 2026-09-09 — the content
        // re-estimating by 1,386pt mid-follow and the transcript showing one blank frame and one 1,222pt above the end — was captured twice with every guard
        // below refusing in silence, so nothing in the log could say whether the marker was there, whether its count had just changed, or which of the five
        // guards had answered. Twice over: a guard that refuses in silence cannot be told apart from a case that never arose, and for any test of a
        // guard, report the decision and check that the circumstance it needs actually arose.
        //
        // **The marker is asked of `newCellIdentifiers`**, not of ``theMarker``, so that it describes the rows this call is deciding about rather than the ones
        // the body was last built from. Two consecutive lines then give the count before and after with no state kept for it — which is deliberate, the reason
        // ``theMarker`` is computed rather than stored applying to anything that shadows it.
        var whatItDecided = "declined, the discussion has not opened yet"
        defer {
            // **``theMarker(among:)`` is asked inside the deferred argument, not before the call.** It walks every identifier with a set lookup apiece,
            // and nothing but this line wants it — in a local it would run on every arrival in a release build, where the report compiles to nothing.
            MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid(
                "an arrival: \(whatItDecided)",
                String(format: "rows=%d→%d marker=%@ lastCell=%@ fromTheEnd=%.1f atTheEnd=%@ finger=%@",
                       indexOfCellIdentifier.count, newCellIdentifiers.count,
                       theMarker(among: newCellIdentifiers).map({ "at \($0.index) saying \($0.numberOfNewMessages)" }) ?? "none",
                       Self.named(lastCellModel),
                       theGeometry.howFarTheEndIsBelowWhatTheReaderCanSee,
                       theReaderIsAtTheEndOfTheDiscussion ? "yes" : "NO",
                       isUnderTheReadersFinger ? "yes" : "no"))
        }

        // Nothing arrives before the discussion has opened. The first pass of this `onChange` is the discussion appearing, where every identifier is one the
        // list "did not previously hold" and the whole transcript would read as an arrival.
        guard theListHasBeenPutWhereTheDiscussionOpens else { return }
        whatItDecided = "declined, the discussion is empty"
        guard let theLastRow = newCellIdentifiers.last else { return }
        whatItDecided = "declined, the last row is not new"
        guard indexOfCellIdentifier[theLastRow] == nil else { return }
        whatItDecided = "declined, the reader has hold"
        guard !isUnderTheReadersFinger else { return }
        switch lastCellModel {
        case .sentMessage:
            whatItDecided = "FOLLOWS a message the reader sent"
            arrangesToFollow(theLastRow)
        case .receivedMessage, .systemMessage, nil:
            whatItDecided = "declined, it was received and the reader is not at the end"
            guard theReaderIsAtTheEndOfTheDiscussion else { return }
            whatItDecided = "FOLLOWS a message that arrived"
            arrangesToFollow(theLastRow)
        }
    }


    /// **Feeds a debug instrument only**, with the probe above. What kind of thing the last cell is, which is what decides how insistently an arrival is followed.
    private static func named(_ model: SingleDiscussionCellView.Model?) -> String {
        switch model {
        case .sentMessage: return "sent"
        case .receivedMessage: return "received"
        case .systemMessage: return "system"
        case nil: return "none"
        }
    }


    /// Arranges to follow an arrival, and **says so**, so that Step 57's branch stands aside while this scroll is owed — see
    /// ``TheGeometryOfTheTranscriptReadPerFrame/anArrivalIsWaitingToBeFollowed``. Both writes in one place, so the fact and the intention cannot
    /// drift apart.
    private func arrangesToFollow(_ theLastRow: SingleDiscussionView.CellIdentifier) {
        theMessageToScrollToOnceItHasAppeared = theLastRow
        theGeometry.saysWhetherAnArrivalIsWaitingToBeFollowed(true)
    }


    /// Takes the reader to the message that has just finished appearing, second half.
    ///
    /// Animated, where the entry is deliberately not: the entry is where the discussion *opens*, and there is no before for the reader to have seen, whereas an
    /// arrival is a movement of about one message that they should watch happen. The legacy screen animates it too, over 0.2s — `simpleScrollToBottom()`, which
    /// runs a `UIViewPropertyAnimator` of that duration around an unanimated `scrollToItem`. **That it is `withAnimation` which makes it animated at all was an
    /// open question until 2026-09-09 and is now measured** — see the call site below, where taking the wrapper off and putting it back is written up.
    ///
    /// **Guarded on the finger again, not only in the decision.** This runs when an animation completes, a few hundred milliseconds after the decision was
    /// taken, and the reader may have grabbed the transcript in between. A completion that fires late must be guarded on the state it belongs to.
    ///
    /// **Nothing is waited for here, and that took finding out.** This scroll used to jump the transcript by about a thousand points, and the cause was not the
    /// animation: a sent message's status indicator changed the last row's height by a sixth of a point, the collection view answered by discarding its layout
    /// and re-estimating the whole discussion — 352pt — and that landed roughly half a second after the message appeared, which is exactly when this runs. Two
    /// writers of the offset for one event. It is fixed where it was caused, in `SentMessageStatusIconView.howFarTheBaselineSitsAboveTheBottom`, so the row's
    /// height no longer moves and there is nothing left to collide with. Proven by a status arriving *during* this scroll and costing nothing.
    private func goesToTheMessageThatHasJustAppeared(using scrollViewProxy: ScrollViewProxy) async {
        guard let theMessage = theMessageToScrollToOnceItHasAppeared else { return }
        theMessageToScrollToOnceItHasAppeared = nil
        theGeometry.saysWhetherAnArrivalIsWaitingToBeFollowed(false)
        guard !isUnderTheReadersFinger else { return }
        // **A bare `withAnimation`, because an animation given here is not read** — measured 2026-08-27, Step 59. This asked for `.linear(duration: 0.2)` for
        // months; setting that duration to **1.5s changed nothing whatever**, and Step 50's iPhone 13 walk had already measured the follow at **~300ms** and
        // described it as an *ease-in-out*. `ScrollViewProxy.scrollTo` bottoms out in `UICollectionView.scrollToItem(at:animated:)`, which uses UIKit's own
        // animation and ignores the SwiftUI transaction: neither the curve nor the duration was ever ours. So the parameters are gone rather than left there
        // looking like decisions, and what remains is ~300ms of UIKit's ease.
        //
        // **The wrapper was taken off on 2026-09-09 and put straight back, and both halves of that are findings.** The question the paragraph above left
        // open — whether `withAnimation` is what makes this animated at all — is now answered: **it is.** Without it the follow lands in a single geometry
        // report, `offset 2785.0→2852.0`, where with it the same 67pt arrives as +5, +10.5, +6.5 across separate presented frames.
        //
        // **And that traverse is the window the excursion falls into.** Captured twice with the wrapper on: an arrival at the exact end grows the content by
        // the height of its own row — `content 4333.4→4452.4`, against a 60pt gate — so `fromTheEnd` goes to **118.9** and the arrival has to be *travelled
        // to*. Somewhere inside the traverse the `List` re-estimates, `content 4437.9→3051.6`, **−1,386pt**, with the offset untouched, and the reader is
        // shown one blank frame and one **1,222pt above the end**. `canSee` is 1762.0 on every geometry report of those episodes, so
        // ``MovesTheMessagesWhenTheSpaceBelowThemChanges`` is out of scope by its own guard and Step 57 stands down truthfully on stillness: **no rule caused
        // it and no rule could have repaired it.** With the wrapper off, eleven arrivals gave none — and re-estimates of **−795.3**, −94.0, −86.3 and −73.4
        // still happened, each with the offset moving by the *same* amount in the *same* report, so the end never left the screen. That is the whole
        // distinction: a re-estimate the clamp absorbs, against one caught mid-traverse with the offset committed where the new content cannot reach.
        //
        // **It goes back because the cut is not good enough**, judged on the screen, which is the only place it could be judged — an arrival is a movement of
        // about one message that the reader is meant to watch happen, and the legacy screen glides it over 0.2s. So the window stays, and what went instead is
        // what landed *in* it: the date line collapsing on the message above, which was the one change on this screen that altered a row's height and animated
        // itself while doing it. **That feature was deleted on 2026-09-09** and the fourth run of the walk is what settled it — the wrapper on, the collapse
        // gone, thirteen arrivals, no excursion, and `content` constant **to the decimal** through every single traverse (`5894.5` on all seventeen frames of
        // the first, `6095.5`, `6318.5`, `6742.5`). With the collapse on, the content moved during *every* follow. So it was not one occupant of the window
        // among several: it was the only one.
        asksForAScrollOfOurOwn(headingFor: .theEndOfTheDiscussion) {
            scrolls(to: theMessage, anchor: .bottom, animated: true, using: scrollViewProxy)
        }
        await asksAgainWhileTheEndIsStillMoving(towards: theMessage, anchoredTo: .bottom, using: scrollViewProxy)
    }


    /// Waits until the push that brought this screen in has finished, so the cover is lifted onto a screen that has stopped arriving.
    ///
    /// **What this is for is the navigation bar and not the transcript.** Everything else the entry waits for is about where the messages are; this one is about
    /// the bar above them, which takes its background at the end of the transition. The transcript is in place a fifth of a second in, the push runs for about
    /// three times that, and uncovering in between shows the reader a clear bar that acquires a background for no reason they can see. Measured on iOS 27: the
    /// background arrived **233ms** after the cover lifted, in a single frame, with the transcript stationary — and under Slow Animations that same gap became
    /// **3.9 seconds**, which is what says it rides the animation clock rather than any wall clock of ours. The log says the rest: across the whole window the
    /// entry asked for no scroll and every sample of the correction declined, so nothing here caused it and nothing here can hurry it.
    ///
    /// **Costing nothing that the reader was not already waiting for.** The push runs for about 600ms whatever this screen does, and the reader is watching it
    /// the whole time. Uncovering at 210ms buys them a transcript underneath a transition that has not finished.
    ///
    /// **A condition with a backstop, as its neighbours are.** It returns the instant the screen has arrived, so nothing is waited out on the ordinary path; the
    /// bound is there because a screen that is never told it has arrived must still show its discussion. A preview is exactly that case.
    private func theScreenHasFinishedArriving() async {
        guard let whenTheScreenHasFinishedArriving else { return }
        for _ in 0..<Self.timesTheEntryAsksWhetherTheScreenHasArrived {
            if whenTheScreenHasFinishedArriving.hasFinishedArriving { return }
            try? await Task.sleep(seconds: Self.timeBetweenAskingWhetherTheEntryHasSettled)
        }
    }


    /// Waits for the introspection to hand over the `List`'s collection view, and says whether it came. If it does not, the entry's scroll searches for its row
    /// instead (see ``scrolls(to:anchor:animated:using:)``), and the entry does not wait for the clock, which reads that same scroll view. A jump that comes
    /// with the screen waits here too.
    private func theCollectionViewHasArrived() async -> Bool {
        for _ in 0..<Self.timesTheEntryWaitsForTheClockToStart {
            if theGeometry.theCollectionView != nil { return true }
            try? await Task.sleep(seconds: Self.timeBetweenAskingWhetherTheEntryHasSettled)
        }
        return theGeometry.theCollectionView != nil
    }


    /// Waits for the clock that answers every question the entry asks, and says whether it ever started.
    ///
    /// **A condition with a backstop, not a delay.** It returns the instant the clock is running, so an ordinary entry pays a sample or two for it and
    /// nothing else. The bound governs only the case where the clock never starts, and there it is what the reader waits before being shown a discussion
    /// this screen cannot see. Every wait the entry makes after this — for the scroll to settle, for its correction to settle — is a question only
    /// ``TheGeometryOfTheTranscriptReadPerFrame`` can answer, and each is separately bounded, so with nothing watching the reader was held behind the
    /// cover for the sum of all three and told nothing. That is what an introspection whose platform list did not name the running system cost: the same
    /// wait on every discussion, two messages or thirty thousand, ending on a timeout rather than on the transcript having arrived.
    ///
    /// **It decides when the cover comes off and nothing else, which is the whole of why it is safe to be wrong.** The first version made it a `guard`
    /// that returned, and that was a regression waiting for a slow launch: the bound is **not** an upper limit on anything measured — the display link's
    /// first frame was seen at 386–787ms on a Mac and 130–150ms on an iPhone 13, and nothing says what a cold start on a tired device does — so a healthy
    /// entry can overrun it. Returning there would have skipped ``asksAgainWhileTheEndIsStillMoving``, which is what puts the end right when the entry
    /// lands on estimated heights and has been measured recovering 85.5, 149.6 and 526.1 points. A reader left short of the end with the gate shut is a
    /// worse fault than the one this exists to fix, and it would have been intermittent.
    ///
    /// So being wrong costs an early reveal and nothing more: the corrections still run, and a cover lifted a little early shows the settling it exists
    /// to hide. That is the cheap error, and the cover's own design already argues for it against the expensive one, which is a blank screen.
    private func theTranscriptIsBeingWatched() async -> Bool {
        for _ in 0..<Self.timesTheEntryWaitsForTheClockToStart {
            if theGeometry.theTranscriptIsBeingRead { return true }
            try? await Task.sleep(seconds: Self.timeBetweenAskingWhetherTheEntryHasSettled)
        }
        return false
    }


    /// Waits until the entry's scroll has stopped moving the transcript, so the cover is lifted off a list that has finished arranging itself.
    ///
    /// **The cover was being lifted far too early, and that was the whole of the reveal's stutter.** `opensTheDiscussion` *asks* for the scroll; it does not wait
    /// for it. The flag was set the instant it returned, so the 0.15s fade ran while the list was still laying out rows it had never measured — measured on a Mac
    /// 2026-08-26, the display link's first geometry frame lands **386–787ms** after the entry, so the cover was gone two to five times over before the transcript
    /// had settled. What the reader then saw was the transcript *arriving* in the open, which reads as an animation interrupted and resumed; and the fade itself
    /// was competing for frames with that same layout, B5 having recorded ticks ~92ms apart during one such storm, which would present 150ms in two frames. Both
    /// causes are the same mistake, and this is the fix for both: reveal when the transcript is in place rather than when it was asked to be.
    ///
    /// **Which is what legacy does, and the part of its strategy that had not been copied.** `NewSingleDiscussionViewController` fades its `hidingView` out inside
    /// the *completion* of the initial scroll, gated on a snapshot having been applied — not where the scroll is requested. Taking the cover and leaving the timing
    /// behind got a smooth-looking reveal only for as long as the cover was also failing to cover the edges.
    ///
    /// **It waits on the geometry, not on a duration.** ``TheGeometryOfTheTranscriptReadPerFrame/aScrollOfOurOwnIsStillMoving`` is followed frame by frame and
    /// already distinguishes *has not begun* from *has finished* — which no test of stillness alone can. A duration here would be the same
    /// race the second ask was written to avoid, and the spread of the measurements above, 386 to 787ms, is exactly how wide it would have to be guessed.
    ///
    /// **Bounded, and it reveals anyway when the bound is reached.** Whatever goes wrong — no scroll view, a discussion with one message where the ask moves
    /// nothing — the reader must not be left looking at a blank screen: the cost of revealing early is the stutter this removes, and the cost of never revealing is
    /// the screen. So the bound is generous against the worst measurement and short enough to be survivable if it is ever hit.
    private func theTranscriptSettlesBeforeItIsUncovered() async {
        for _ in 0..<Self.timesTheEntryIsAskedWhetherItHasSettled {
            if !theGeometry.aScrollOfOurOwnIsStillMoving { return }
            try? await Task.sleep(seconds: Self.timeBetweenAskingWhetherTheEntryHasSettled)
        }
    }


    /// Keeps asking, while the end of the discussion is still moving, until the reader is actually at it — **Step 44b's second ask**.
    ///
    /// **A long follow lands on estimated row heights, and the estimate is corrected after it lands.** Measured on a Mac: a message sent from ~6,000pt and
    /// ~7,000pt above the end was followed, reported `fromTheEnd=0.0`, and was then left **85.5pt** and **149.6pt** short — permanently, with the gate
    /// shut, until the reader finished the scroll by hand. A **short** follow never has this: 119pt of travel landed at 0.0 and 1,040pt at −0.1. The
    /// variable is how many unmeasured rows the scroll crosses, and `scrollTo` targets a **row**, so asking again once the heights are real lands on it.
    ///
    /// **No single wait can be right here.** The two deficits appeared at 127ms and 462ms, so the neighbouring scrolls' fixed wait would have caught one
    /// and missed the other: a fixed wait is a race. What must be long enough is the **window**, inside which the question is asked
    /// repeatedly and answered by the geometry rather than by the clock.
    ///
    /// **The condition is the gate the screen already computes**, ``TheGeometryOfTheTranscriptReadPerFrame/theReaderIsAtTheEndOfTheDiscussion``. Reusing it
    /// rather than inventing a tolerance means this cannot disagree with the rule that decides whether the *next* arrival is followed, which is the harm the
    /// deficit actually did.
    ///
    /// **The healthy case does nothing at all**: an arrival followed from within a screen of the end is at the end on the first check, so nothing is written
    /// and nothing suppressed. On the common path this costs a few sleeps in a task that is already detached.
    ///
    /// Three ways out: **the reader takes hold** (it stops being ours to move); **somebody else scrolled** — a reply header or the way back, tapped inside
    /// the window, is a scroll this must not undo, so the count of our own scrolls is taken before the wait and compared after; and **it is settled**.
    ///
    /// - Parameters:
    ///   - overAtMost: how many samples the window is given. The whole of it for a follow; a short prefix for the entry, which cannot keep the reader behind
    ///     a cover for a second and a half.
    ///   - pausingBetweenTheLaterSamples: how long to wait between samples *after* the first. The first always waits ``timeTheEndIsGivenToStopMoving``,
    ///     which is measured: the deficit an entry lands with does not exist when the scroll stops, and appeared 91–117ms later on an iPhone 13. Sampling
    ///     sooner finds `fromTheEnd=0.0` and answers before the movement has begun.
    ///   - takingItsFirstSampleAtOnce: whether to look before the first pause. On ten entries the deficit was already visible **64–93ms before**
    ///     ``theTranscriptSettlesBeforeItIsUncovered`` returned, never after, so for the entry that pause waited for something already true. A follow keeps
    ///     its pause, having no settle-wait in front of it.
    ///   - stoppingAtTheFirstCleanSample: whether a clean sample **ends** the window. False for a follow — a deficit was seen appearing 462ms after
    ///     landing, so stopping at the first healthy answer would declare success and leave the fault. True for the entry, where the whole window runs
    ///     afterwards anyway.
    /// - Parameter theScrollsAlreadyKnownAbout: the count of our own scrolls as of the ask this is correcting, or nil to take it now.
    ///
    ///   **It must be the caller's, not this function's, wherever the two can differ** — and for the entry they differ by everything that matters. The entry asks
    ///   for its scroll, then *waits* for the transcript to settle before calling this; a jump arriving in that gap goes through
    ///   ``asksForAScrollOfOurOwn`` and is therefore already inside a count taken here, so the guard below sees `scrolls=3(was 3)` and stands down for nobody.
    ///   Measured on 2026-08-30, opening a discussion on a message from the storage manager: the jump landed, and 619ms later this asked again towards the end
    ///   with `fromTheEnd=2677.0` — reading the reader's requested position as a deficit to be corrected — and took them back. That is the case the note at
    ///   ``asksForAScrollOfOurOwn`` predicted when Step 44a dropped the old stand-down: *whatever 44b puts back will have to be stood down here again*.
    @discardableResult
    private func asksAgainWhileTheEndIsStillMoving(towards theMessage: SingleDiscussionView.CellIdentifier,
                                                   anchoredTo anchor: UnitPoint,
                                                   using scrollViewProxy: ScrollViewProxy,
                                                   knowingAbout theScrollsAlreadyKnownAbout: Int? = nil,
                                                   overAtMost theSamplesAllowed: Int = Self.timesTheFollowMayAskAgain,
                                                   pausingBetweenTheLaterSamples theLaterPause: TimeInterval = Self.timeTheEndIsGivenToStopMoving,
                                                   stoppingAtTheFirstCleanSample: Bool = false,
                                                   takingItsFirstSampleAtOnce: Bool = false) async -> Int {

        var theScrollsWeKnowAbout = theScrollsAlreadyKnownAbout ?? theGeometry.scrollsOfOurOwnAskedFor

        for sample in 1...max(1, theSamplesAllowed) {

            if sample > 1 || !takingItsFirstSampleAtOnce {
                try? await Task.sleep(seconds: sample == 1 ? Self.timeTheEndIsGivenToStopMoving : theLaterPause)
            }

            // **DEBUG INSTRUMENT, and it is the whole instrument this is judged by.** Every sample says what it saw and what it decided, before any
            // guard — because the first verification of this rule passed without testing it: four sends landed correctly and not one caused the content
            // re-estimate that is the fault, so *nothing happened* and *the cure worked* were indistinguishable. Twice over: a guard that refuses in
            // silence cannot be told apart from a case that never arose, and for any test of a guard, report the decision and check the circumstance arose.
            // **Read once, reported and decided on.** The count below is written by a display link, so asking for it twice in one sample can give two
            // answers a frame apart — and a line saying one thing while the guard did another is worse than no line at all.
            let framesTheEndHasBeenStillFor = theGeometry.framesSinceTheEndOfTheDiscussionLastMoved

            // **A function rather than a value, so the formatting happens only where the report does** — every caller below hands it to an
            // `@autoclosure`, which evaluates nothing in a release build. The count above stays a local and is captured, so the line and the guard
            // still answer from one reading of it.
            func said() -> String {
                String(format: "sample %d/%d | fromTheEnd=%.1f atTheEnd=%@ ourScrollMoving=%@ finger=%@ scrolls=%d(was %d) endStillFor=%d frames",
                              sample, max(1, theSamplesAllowed),
                              theGeometry.howFarTheEndIsBelowWhatTheReaderCanSee,
                              theGeometry.theReaderIsAtTheEndOfTheDiscussion ? "yes" : "NO",
                              theGeometry.aScrollOfOurOwnIsStillMoving ? "yes" : "no",
                              isUnderTheReadersFinger ? "yes" : "no",
                              theGeometry.scrollsOfOurOwnAskedFor, theScrollsWeKnowAbout,
                              framesTheEndHasBeenStillFor)
            }

            guard !isUnderTheReadersFinger else {
                MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid("the follow's second ask STOOD DOWN, the reader has hold", said())
                return theScrollsWeKnowAbout
            }
            guard theGeometry.scrollsOfOurOwnAskedFor == theScrollsWeKnowAbout else {
                MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid("the follow's second ask STOOD DOWN, something else scrolled", said())
                return theScrollsWeKnowAbout
            }

            // **Nothing may be asked while our own scroll is still running**, the reader being mid-flight and the gate legitimately shut — a sample taken here
            // would read as a failure and truncate the arrival's animation. This is the first third of the window, roughly, and it is spent deliberately.
            guard !theGeometry.aScrollOfOurOwnIsStillMoving else {
                MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid("the follow's second ask waits, our own scroll is still moving", said())
                continue
            }

            // Not an error and not the end of the window: the correction may not be needed *yet*. The second of the two measured runs had no deficit at all until
            // 462ms after landing, so a version of this that stopped at the first healthy answer would have declared success and left the fault in place.
            //
            // **Asked as *is the end reached*, and not as *is the reader near enough to the end to be followed*** — Step 59's walk, 2026-08-27. Those are two
            // questions and they were sharing one constant: `theReaderIsAtTheEndOfTheDiscussion` is true within **60pt**, which is a gate about whether an arrival
            // is worth following at all, and it made this blind to any deficit smaller than itself. Measured: a follow landed **27pt** short — the sent message's
            // real height arriving in the very frame the scroll ended, `content` 3889.5 → 3916.5 — and this said *finds the reader at the end, nothing to correct*,
            // ten times in a row. A correction that cannot see a deficit smaller than its own tolerance has a floor, and the floor was visible.
            guard theGeometry.howFarTheEndIsBelowWhatTheReaderCanSee > Self.asCloseToTheEndAsThisNeedsToGet else {
                // **Quick to act on a deficit, slow to believe there is none** — and the asymmetry is the whole of what makes looking at once safe. A deficit
                // seen is a fact; *no deficit seen* may only mean it has not appeared yet, which is the stillness trap and the fault this prefix was
                // written for. So a clean answer is refused until the end has been **seen** not to move, for
                // ``framesOfStillnessThatMakeACleanSampleBelievable`` presented frames — evidence read off the transcript rather than a duration waited out,
                // and the display link is asked because it is the only thing that sees every frame of a growth nobody announces.
                //
                // **Asked only from here, and only after the settle-wait**, which is what keeps this out of the stillness trap: by the time this runs a scroll
                // has been asked for, seen to move, and been still for three frames, so the movement has begun long before its absence is believed.
                let theEndHasStoppedMoving = framesTheEndHasBeenStillFor >= Self.framesOfStillnessThatMakeACleanSampleBelievable
                MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid(stoppingAtTheFirstCleanSample ? (theEndHasStoppedMoving ? "the entry's correction finds the end reached and still, the cover may go" : "the entry's correction finds the end reached, but it has not been still long enough to believe it") : "the follow's second ask finds the end reached, nothing to correct", said())
                if stoppingAtTheFirstCleanSample, theEndHasStoppedMoving { return theScrollsWeKnowAbout }
                continue
            }

            MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid("the follow ASKS AGAIN, the end moved after it landed", said())
            // **`theEndOfTheDiscussion` by this method's own definition**, not by an assumption about its callers: reaching the end is what it is named for and
            // all three of them guard on having opened on, or arrived at, the end. A caller that ever aims this elsewhere must give it a heading of its own.
            asksForAScrollOfOurOwn(headingFor: .theEndOfTheDiscussion) { scrolls(to: theMessage, anchor: anchor, using: scrollViewProxy) }
            theScrollsWeKnowAbout = theGeometry.scrollsOfOurOwnAskedFor

        }

        return theScrollsWeKnowAbout

    }


    /// Puts the unread marker where the entry asked for it, before the cover is lifted. The marker's counterpart of
    /// ``asksAgainWhileTheEndIsStillMoving(towards:anchoredTo:using:knowingAbout:overAtMost:pausingBetweenTheLaterSamples:stoppingAtTheFirstCleanSample:takingItsFirstSampleAtOnce:)``,
    /// with the same guards, the same bound and the same constants.
    ///
    /// Centring the marker needs the height of every row above it, and those are estimates until the rows are laid out. When the real heights arrive, they
    /// can push the marker far from where it was put, even off the screen. So this reads where the marker is, and asks for it again until it holds still.
    ///
    /// A sample is accepted in four cases:
    /// - The marker is in the middle of what can be seen.
    /// - The reader is at the very end, and the marker is at or below the middle. The marker is too near the end to be centred.
    /// - The reader is at the very top, and the marker is at or above the middle. The marker is too near the top to be centred, or the discussion fits on the
    ///   screen.
    /// - Asking again left the marker exactly where it was. The list has then shown where it puts a centred marker, so a wrong idea of *the middle* costs one
    ///   ask rather than the whole bound.
    ///
    /// It waits for the marker to hold still, not for the end: rows growing above the screen move the end but not the marker. Nothing corrects a marker
    /// entry once the cover is lifted, because moving the transcript under somebody reading is worse than a small error.
    private func asksAgainUntilTheMarkerHoldsStill(using scrollViewProxy: ScrollViewProxy, knowingAbout theScrollsAlreadyKnownAbout: Int) async -> Int {

        var theScrollsWeKnowAbout = theScrollsAlreadyKnownAbout
        var hasAskedAgain = false
        // Where the marker was when it was last asked for again, nil if it was not laid out then.
        var whereTheMarkerWasWhenAskedAgain: CGFloat?
        let theSamplesAllowed = Self.timesTheEntryPutsTheEndRightBeforeUncovering

        for sample in 1...theSamplesAllowed {

            if sample > 1 {
                try? await Task.sleep(seconds: Self.timeBetweenTheEntrysLaterSamples)
            }

            // Read once, so that the reported line and the decision use the same values.
            let whereTheMarkerIs = theGeometry.whereTheMarkerIs
            let framesTheMarkerHasBeenStillFor = theGeometry.framesSinceTheMarkerLastMoved
            let theMiddle = theGeometry.theMiddleOfWhatCanBeSeen
            let theReaderIsAtTheVeryEnd = theGeometry.theReaderIsAtTheVeryEnd
            let theReaderIsAtTheVeryTop = theGeometry.theReaderIsAtTheVeryTop

            // DEBUG INSTRUMENT. A function rather than a value, so that nothing is formatted in a release build.
            func said() -> String {
                String(format: "sample %d/%d | marker=%@ middle=%@ markerStillFor=%d frames atTheVeryEnd=%@ atTheVeryTop=%@ askedAgain=%@ ourScrollMoving=%@ finger=%@ scrolls=%d(was %d)",
                       sample, theSamplesAllowed,
                       whereTheMarkerIs.map { String(format: "%.1f", $0) } ?? "not laid out",
                       theMiddle.map { String(format: "%.1f", $0) } ?? "unknown",
                       framesTheMarkerHasBeenStillFor,
                       theReaderIsAtTheVeryEnd ? "yes" : "no",
                       theReaderIsAtTheVeryTop ? "yes" : "no",
                       hasAskedAgain ? (whereTheMarkerWasWhenAskedAgain.map { String(format: "with the marker at %.1f", $0) } ?? "with the marker not laid out") : "no",
                       theGeometry.aScrollOfOurOwnIsStillMoving ? "yes" : "no",
                       isUnderTheReadersFinger ? "yes" : "no",
                       theGeometry.scrollsOfOurOwnAskedFor, theScrollsWeKnowAbout)
            }

            guard !isUnderTheReadersFinger else {
                MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid("the marker's correction STOOD DOWN, the reader has hold", said())
                return theScrollsWeKnowAbout
            }
            // A jump asked for during the entry, such as the app opening the discussion on a message, is not ours to undo.
            guard theGeometry.scrollsOfOurOwnAskedFor == theScrollsWeKnowAbout else {
                MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid("the marker's correction STOOD DOWN, something else scrolled", said())
                return theScrollsWeKnowAbout
            }
            guard !theGeometry.aScrollOfOurOwnIsStillMoving else {
                MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid("the marker's correction waits, our own scroll is still moving", said())
                continue
            }

            // A marker that is not laid out is far from where it was asked to be, so it is asked for again at once.
            if let whereTheMarkerIs {
                guard framesTheMarkerHasBeenStillFor >= Self.framesOfStillnessThatMakeACleanSampleBelievable else {
                    MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid("the marker's correction waits, the marker is still moving", said())
                    continue
                }
                let isAsNearTheMiddleAsTheListAllows = theMiddle.map { theMiddle in
                    let tolerance = Self.howNearTheMiddleCountsAsCentred
                    return abs(whereTheMarkerIs - theMiddle) <= tolerance
                        || (theReaderIsAtTheVeryEnd && whereTheMarkerIs >= theMiddle - tolerance)
                        || (theReaderIsAtTheVeryTop && whereTheMarkerIs <= theMiddle + tolerance)
                } ?? false
                let askingAgainMovedNothing = whereTheMarkerWasWhenAskedAgain.map { abs(whereTheMarkerIs - $0) <= Self.howFarAnAskMustMoveTheMarkerToCount } ?? false
                if isAsNearTheMiddleAsTheListAllows || askingAgainMovedNothing {
                    MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid("the marker's correction finds the marker in place, the cover may go", said())
                    return theScrollsWeKnowAbout
                }
            } else if hasAskedAgain, whereTheMarkerWasWhenAskedAgain == nil, theGeometry.theLastScrollOfOurOwnMovedNothing {
                // The marker was asked for while it was not laid out, it is still not laid out, and the ask moved nothing. A list moves to show a row it has, so
                // the marker has left the list, its messages having been deleted, and asking again would only use up the bound. A marker that is only hard to
                // reach, past rows whose heights were estimates, moves the list and is asked for again. This is decided from the geometry because ``theMarker``
                // cannot answer here: this task holds a copy of the view taken when the entry began.
                MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid("the marker's correction STOOD DOWN, asking again for a marker that is not laid out moved nothing", said())
                return theScrollsWeKnowAbout
            }

            MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid(
                whereTheMarkerIs == nil ? "the marker's correction ASKS AGAIN, the marker is not laid out" : "the marker's correction ASKS AGAIN, the marker is not where it was asked to be",
                said())
            hasAskedAgain = true
            whereTheMarkerWasWhenAskedAgain = whereTheMarkerIs
            // A row the reader asked for, not the end: the rule that puts the reader back at the end must not pull them away from the marker afterwards.
            asksForAScrollOfOurOwn(headingFor: .aRowTheReaderAskedFor) {
                scrolls(to: .newMessagesMarker, anchor: .center, using: scrollViewProxy)
            }
            theScrollsWeKnowAbout = theGeometry.scrollsOfOurOwnAskedFor

        }

        MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid("the marker's correction GIVES UP, its bound is reached", "the cover goes regardless")
        return theScrollsWeKnowAbout

    }


    /// How near the middle of what can be seen counts as centred. UIKit places a centred row on a pixel, so a point allows for the rounding.
    private static let howNearTheMiddleCountsAsCentred: CGFloat = 1

    /// How far an ask must move the marker to count as having moved it: the half point the geometry calls real rather than rounding.
    private static let howFarAnAskMustMoveTheMarkerToCount: CGFloat = 0.5


    // The two thresholds this screen used to keep — how close to the end counts as *at the end*, and how far below it the way back is worth
    // offering — moved to ``TheGeometryOfTheTranscriptReadPerFrame`` at Step 46b, along with the questions they answer and the provenance of
    // both numbers.




    /// How long the first pass of a jump is given before it is corrected. Long enough for the animated scroll to have finished, short enough that the correction is
    /// part of the same movement to the eye.
    private static let timeToLetTheJumpLand: TimeInterval = 0.35

    /// How long the end is given to stop moving between two of the follow's asks — see ``asksAgainWhileTheEndIsStillMoving(towards:using:)``.
    ///
    /// **This is a sampling interval, not a wait for an event**, which is the distinction that matters: no single one of these has to land on the moment the row
    /// heights become real, only the product of the two constants has to outlast it. Short enough that a correction reads as part of the same movement, and long
    /// enough that a saturated main thread — ~92ms a frame across the landing that was measured — presents something new between two of them.
    private static let timeTheEndIsGivenToStopMoving: TimeInterval = 0.15

    /// How many presented frames the end must have been still for before a **clean** sample may be believed — see
    /// ``TheGeometryOfTheTranscriptReadPerFrame/framesSinceTheEndOfTheDiscussionLastMoved``.
    ///
    /// **This replaced a 150ms floor, 2026-08-28, and the floor was insuring against something already over.** The asymmetry it exists for is
    /// unchanged and is the whole of why the entry may look at once: a deficit *seen* is a fact, where *no deficit seen* may only mean it has not
    /// appeared yet. What changed is what answers the second half. A clock cannot tell those apart and so waits out its worst case on every entry;
    /// the display link can, because a transcript that is going to grow moves the end and this count goes back to nought.
    ///
    /// **Measured, ten entries over two discussions on an iPhone 13.** The entry's growth is real — +148.3pt in one discussion, +703.6 and +1703.3 in
    /// a heavier one, identical to the decimal between entries — and every point of it lands *before* the display link's first frame at 130–150ms.
    /// After that frame the transcript never moved again in any of the ten: one frame-report line each, `fromTheEnd=0.0`, and all 84 samples clean
    /// with not one correction asked for. The floor then held the cover for a further 160ms of nothing.
    ///
    /// **Three frames, and it is ``TheGeometryOfTheTranscriptReadPerFrame``'s own number for the same question** — what ends a scroll of our own is
    /// three frames of stillness. Sharing it is deliberate: both are *has this stopped moving*, asked of the same clock, and two different answers to
    /// that would be two rules that can disagree. On this 60Hz device it is 50ms of evidence against 150ms of tolerance; on a 120Hz screen it is 25ms
    /// of the same evidence, which is the property a clock does not have — what is being counted is frames in which the end could have moved and did
    /// not, and a faster screen supplies them sooner.
    private static let framesOfStillnessThatMakeACleanSampleBelievable = 3

    /// How long the cover takes to fade away once the transcript is in place — see ``theCoverUntilTheTranscriptIsInPlace``.
    ///
    /// **Shorter than it was, and it can afford to be now.** It was 0.15s while the fade ran *inside* the entry's layout, where it was competing for frames and
    /// being presented in two or three of them; since the cover is lifted only once the scroll has settled, the main thread is free and every frame of this is
    /// drawn. A fade that is given all its frames reads as longer than one that is not, so the same number felt slower in the good version than in the bad one.
    /// Legacy's is 0.3s, which is where ours came from; there is no measurement behind either, and the reader asked for less.
    private static let timeTheCoverTakesToFade: TimeInterval = 0.1

    /// How often the entry is asked whether its scroll has settled, before the cover is lifted — see ``theTranscriptSettlesBeforeItIsUncovered()``.
    ///
    /// Finer than the second ask's interval, and for the opposite reason: that one is waiting for something that takes hundreds of milliseconds and costs nothing
    /// to be late about, where every millisecond of this one is a millisecond of cover the reader is looking at.
    private static let timeBetweenAskingWhetherTheEntryHasSettled: TimeInterval = 0.02

    /// How long the entry may be waited for, at the interval above — **1.2s**, against a worst measurement of 787ms.
    ///
    /// It is a backstop and not a budget: reaching it means the geometry never said the scroll had settled, and the answer then is to show the reader their
    /// discussion regardless rather than to keep a cover over it.
    private static let timesTheEntryIsAskedWhetherItHasSettled = 60

    /// How long the entry waits for the clock to start before concluding that nothing is watching — see ``theTranscriptIsBeingWatched()``.
    ///
    /// **Generous, and it costs nothing to be.** This is a condition rather than a delay, so an entry whose clock starts promptly leaves on its first
    /// or second sample whatever this says; the number only bounds the case where it never starts. **It is not measured** — how late the introspection
    /// may hand over a scroll view on a slow device has never been established, and a bound shorter than that would uncover a healthy entry early. That
    /// measurement is what would let this shrink.
    ///
    /// A constant of its own, though it is presently the same length as the settle-wait above: two questions sharing one number are two rules that
    /// cannot be tuned apart.
    private static let timesTheEntryWaitsForTheClockToStart = 60

    /// How long the entry waits for the push to finish before uncovering anyway — see ``theScreenHasFinishedArriving()``.
    ///
    /// **Generous because it is a condition rather than a delay**: an entry whose screen arrives on time leaves the moment it does, whatever this says. What the
    /// number bounds is a screen that is never told it has arrived — a preview, or anything presented in a way the hosting controller does not report — where the
    /// reader must be shown their discussion regardless. Against a push measured at about 600ms, this is comfortably clear of it.
    private static let timesTheEntryAsksWhetherTheScreenHasArrived = 60


    /// How near the end counts as *arrived*, for the correction above and for nothing else.
    ///
    /// Half a point, which is to say **exactly**: this is the tolerance of a rule whose whole purpose is that `pointsBelowTheVisibleArea` should be nought, so
    /// anything it can measure it should fix. Deliberately **not** ``closeEnoughToTheEndToBeFollowed`` — see the note at the guard, where sharing that 60pt gave
    /// this a floor it could not see under.
    private static let asCloseToTheEndAsThisNeedsToGet: CGFloat = 0.5


    /// How many samples the follow may take while the end is still moving, which with the interval above gives it a window of **1.5s**.
    ///
    /// The two measured deficits appeared 127ms and 462ms after the follow landed, and the second arrived with a re-estimate that moved the content by 3,611pt — so
    /// the window is set at several times the worse of the two rather than at its size, the first part of it being spent waiting for the follow's own animation to
    /// settle. Making it generous costs nothing: every sample that finds the reader at the end, or the transcript still moving, is two property reads. What the
    /// constant buys is the bound — nothing here can run on indefinitely after the arrival that started it, whatever the list decides to re-estimate.
    private static let timesTheFollowMayAskAgain = 10

    /// How many of those samples the **entry** takes before uncovering — see the call in `onAppear`.
    ///
    /// Twenty, which with ``timeBetweenTheEntrysLaterSamples`` is ≈ 600ms of cover in the worst case, and rather less than that on any real path — what ends it
    /// is the geometry, and the count is only there so that nothing can leave the reader behind a cover for ever. It is generous because the first sample is now
    /// taken at once and a clean answer is refused until the end has been still for ``framesOfStillnessThatMakeACleanSampleBelievable`` frames, so the early
    /// samples are cheap and there are more of them,
    /// the prefix stopping at the first sample that finds nothing to correct. It is a bound rather than a duration to wait out: what decides is the geometry, and
    /// this only says how long the reader may be kept looking at a cover before being shown a transcript that may still move. Step 50 measured an entry's first
    /// settled frame at 386–787ms, so a cover that lasts into that range is not out of proportion with what the screen is actually doing.
    private static let timesTheEntryPutsTheEndRightBeforeUncovering = 20

    /// How long the entry waits between samples **after the first**, the first keeping ``timeTheEndIsGivenToStopMoving`` for the reason given at
    /// ``asksAgainWhileTheEndIsStillMoving(towards:anchoredTo:using:overAtMost:pausingBetweenTheLaterSamples:stoppingAtTheFirstCleanSample:)``.
    ///
    /// **Thirty milliseconds, and the reason for shortening it is measured.** Ten entries on an iPhone 13, 2026-08-28: the cover lifted at a median of **601ms**
    /// warm — 18ms to ask for the scroll, ~240ms for it to stop, and then **~345ms of sampling**, more than half the wait and almost all of it asleep. Every one
    /// of the ten found the same `fromTheEnd=27.3` on the first sample and corrected it, so the second sample is not an unlucky case but the ordinary one, and it
    /// cost 183ms to notice something that had already happened. The same value as
    /// ``timeBetweenAskingWhetherTheEntryHasSettled``'s neighbourhood, and for the same reason: a question answered by the geometry costs nothing to ask again.
    private static let timeBetweenTheEntrysLaterSamples: TimeInterval = 0.03


    /// **TEMPORARY until the entry stops being tuned**, and it exists to make a before and an after comparable.
    ///
    /// The entry was reported as slow after the cover was made to wait for the correction, and the only figure anybody had for how long it lasts was one read off
    /// the geometry frames by hand: **nothing reports the reveal itself**. So this says, unconditionally, how far into the entry each milestone falls, in
    /// milliseconds from the moment `onAppear` starts working. `THE COVER IS LIFTED` is the number that matters; the ones before it say where the time went, and
    /// the gaps between them are what any change here has to be judged on.
    ///
    /// It goes out once the entry has been tuned and the numbers are written down. Through
    /// ``MovesTheMessagesWhenTheSpaceBelowThemChanges/saysWhatItDid(_:_:)`` rather than a `Logger` of its own, so it lands in the category the frame rigs already
    /// filter on and needs no second thing to keep in step.
    private static func saysHowFarIntoTheEntryThisIs(_ milestone: String, _ theEntryBegan: CFAbsoluteTime) {
        let millisecondsIn = (CFAbsoluteTimeGetCurrent() - theEntryBegan) * 1000
        MovesTheMessagesWhenTheSpaceBelowThemChanges.saysWhatItDid("the entry", String(format: "at=%5.0fms  ", millisecondsIn) + milestone)
        theEntryInInstruments.emitEvent("a milestone of the entry", "\(milestone, privacy: .public)")
    }


    /// **TEMPORARY until the entry stops being tuned**, with ``saysHowFarIntoTheEntryThisIs(_:_:)``, and it exists so that a profiler trace can be read.
    ///
    /// The entry's cost is now known to the millisecond from the log, and what is *not* known is what the main thread spends ~50ms doing while the cover fades. A
    /// log cannot answer that and a Time Profiler can, but only if the fifty milliseconds can be found in a trace of a whole session. So the entry marks itself.
    ///
    /// **The `pointsOfInterest` category, deliberately**: signposts logged there appear on Instruments' *Points of Interest* track, which is in the standard
    /// profiling template already, so a trace needs no instrument added to it and no configuration to get wrong.
    ///
    /// Two intervals rather than one, because the interesting window is the *second*. `entering the discussion` runs from the moment `onAppear` starts working to
    /// the instant the cover is lifted, with a point event at each milestone along it; `the cover fades` covers the 0.15s after that, which is where the three
    /// missing frames are. Whatever occupies the main thread there will be inside the second bar.
    private static let theEntryInInstruments = OSSignposter(logHandle: OSLog(subsystem: "io.olvid.messenger", category: .pointsOfInterest))

    /// How long the list is left still before the message that was jumped to says *this one* — see ``TheMessageAJumpLandedOn``. Long enough for the reader's eye to
    /// have stopped travelling with the scroll, which is what makes the effect visible at all.
    private static let timeBeforeSayingWhichMessageItWas: TimeInterval = 0.4


    /// Takes the reader back to the end of the discussion, the way the button that asks for it means it.
    ///
    /// **The row is resolved when the press happens**, through the same `rowAndAnchor(toOpenOn:)` the entry uses: "the end" is whatever the last message is at
    /// that moment, which is not what it was when the button appeared — a message may have arrived, or the last one been deleted for everyone.
    ///
    /// Asked for more than once, because a list of self-sizing rows approaches a position over several steps: the first request lands near the end and a later one
    /// lands on it. The correction is not animated, the reader having already seen the movement.
    ///
    /// **It waits on the geometry rather than on a clock, which it did not until Step 44b's second ask was written.** This used to re-ask exactly once, after
    /// ``timeToLetTheJumpLand``, and that is the same race the follow was measured losing: the content re-estimate that leaves a long scroll short of the end
    /// arrived 127ms after one landing and **462ms** after another, so a single wait of 0.35s catches the first and misses the second. The button reaches the end
    /// from wherever the reader happens to be, which is exactly the long scroll across unmeasured rows that provokes it, so it has the same exposure — the fault
    /// was found on the *send* only because that is what Group B happened to walk. See ``asksAgainWhileTheEndIsStillMoving(towards:anchoredTo:using:)``.
    private func goesBackToTheEndOfTheDiscussion(using scrollViewProxy: ScrollViewProxy) async {
        guard let (identifier, anchor) = rowAndAnchor(toOpenOn: .theEndOfTheDiscussion) else { return }
        asksForAScrollOfOurOwn(headingFor: .theEndOfTheDiscussion) {
            scrolls(to: identifier, anchor: anchor, animated: true, using: scrollViewProxy)
        }
        await asksAgainWhileTheEndIsStillMoving(towards: identifier, anchoredTo: anchor, using: scrollViewProxy)
    }


    private static let horizontalPadding: CGFloat = 16


    /// The selection the `List` manages — **and nil on a Mac, which is the whole of Step 42e**.
    ///
    /// A `List` given a selection on Catalyst brings the platform's own rules with it: a click **replaces** what is chosen and ⌘-click adds to it. Two attempts to
    /// change that from outside failed, and both failed the same way — they took the click while UIKit's selection was still running. Handing it **no** selection
    /// leaves nothing to fight: no ⌘ semantics, no active-against-inactive tinting, and no part of the row belonging to somebody else. What a row then draws and
    /// what answers a click on it is ``AMessageTickedOnAMac``.
    ///
    /// **An optional binding rather than two `List`s.** This was the question that decided whether 42e was worth writing at all: a platform branch around the
    /// `List` itself would have duplicated every row in this file. The initialiser taking `Binding<Set<SelectionValue>>?` is what makes the branch one line.
    ///
    /// Nothing changes on a touch platform, which is the standing constraint on selecting several messages.
    private var theSelectionTheListManages: Binding<Set<SingleDiscussionView.CellIdentifier>>? {
        #if targetEnvironment(macCatalyst)
        return nil
        #else
        return $selectedCellIdentifiers
        #endif
    }


    /// Whether the `List` is editing, which on a touch platform is what draws its circles and insets its rows.
    ///
    /// **Never on a Mac**, where the selection is not the list's: edit mode without a selection would inset every row to make room for a circle that is never
    /// drawn. The room a Mac makes is ``AMessageTickedOnAMac``'s, and it makes it for a tick that exists.
    private var theEditModeTheListIsIn: EditMode {
        #if targetEnvironment(macCatalyst)
        return .inactive
        #else
        return theReaderIsChoosingMessages ? .active : .inactive
        #endif
    }


    /// What a click on a message means while the reader is choosing, Catalyst only, everywhere else being the `List`'s own business.
    ///
    /// **Assembled here and not in the row**, because only this view knows the rows in the order they are drawn. It reads and writes the selection through the
    /// two bindings rather than owning either: a `List` writes its own selection on a touch platform and this screen owns the mode, and 42e's constraint is that
    /// nothing below this line differs between the platforms.
    ///
    /// **What may be ticked is decided here too.** The marker saying how many messages arrived is a row and not a message — it sits inside the `ForEach` so the
    /// screen can scroll to it — and the sentence about encryption is outside the `ForEach` and never had a tick. A range must step over the first and cannot
    /// reach the second.
    private func theReaderClicked(_ cellIdentifier: SingleDiscussionView.CellIdentifier,
                                  shiftWasHeld: Bool,
                                  over theRowsAsDisplayed: [SingleDiscussionView.CellIdentifier]) {
        var theSelection = TheSelectionOfSeveralMessages(isRunning: true,
                                                         cellIdentifiers: selectedCellIdentifiers,
                                                         theAnchor: theAnchorOfTheSelection,
                                                         whatTheLastExtensionAdded: whatTheLastExtensionAdded)
        if shiftWasHeld {
            theSelection.extends(to: cellIdentifier, over: theRowsAsDisplayed) { $0 != .newMessagesMarker }
        } else {
            theSelection.ticksOrUnticks(cellIdentifier)
        }
        selectedCellIdentifiers = theSelection.cellIdentifiers
        theAnchorOfTheSelection = theSelection.theAnchor
        // Written back like the other two, and for the same reason: this object is rebuilt on the next click and remembers nothing of its own.
        whatTheLastExtensionAdded = theSelection.whatTheLastExtensionAdded
    }


    private var listOfCells: some View {
        // Asked once and handed to both the rows and the marker's label: it walks the identifiers, and the two things it answers are wanted in the same breath.
        let theMarker = self.theMarker
        // **Asked once and closed over by every row**, which is the whole reason a click is *reported* rather than acted on where it happens: extending a range
        // needs the rows in the order they are drawn, and that is a list this long which no row should hold and which would be compared per row on every update
        // if one did. See ``AMessageTickedOnAMac``.
        let theRowsAsDisplayed = rowIdentifiers(with: theMarker)
        let theRowsOfEachSection = rowsOfEachSection(among: theRowsAsDisplayed, theMarker: theMarker)
        // Kept for the scrolls, which may run on an older copy of this view than the one being evaluated. See ``TheRowsTheListWasLastGiven``.
        theRowsTheListWasLastGiven.sections = theRowsOfEachSection
        theRowsTheListWasLastGiven.sectionsBeforeThem = sentenceSayingTheDiscussionIsEndToEndEncrypted == nil ? 0 : 1
        // **Built once and shared by every row, never inside the `ForEach`.** A closure written at the row would capture `self` *by value* — a copy of this
        // whole view struct — and the rows array with it, once per row per update, on **every** platform including the ones that never call it. A row's build
        // was measured at ~8µs, so what runs per row must be trivial. One allocation per body evaluation is the cost instead.
        let theReaderClickedARow: (SingleDiscussionView.CellIdentifier, Bool) -> Void = { theMessage, shiftWasHeld in
            theReaderClicked(theMessage, shiftWasHeld: shiftWasHeld, over: theRowsAsDisplayed)
        }
        // **The selection is the `List`'s own, which the comment at the head of this file said it could not be**. That comment expected multiple
        // selection to be built by hand, on the grounds that a `List`'s edit mode indents its rows and suppresses the interactions of their content. Both are
        // true, and both turn out to be what this feature *wants*: a tap on a message while choosing must mean *tick this one* and not *open this photograph*.
        // What is not free is the indent, which moves every bubble, and that is measured on a screen rather than argued about here.
        return List(selection: theSelectionTheListManages) {
            // Before the rows, and outside the `ForEach`: the discussion saying what it is. It has no identifier because nothing ever scrolls to it — it is where the
            // list starts.
            if let sentenceSayingTheDiscussionIsEndToEndEncrypted {
                SystemMessageCellView(model: .init(text: sentenceSayingTheDiscussionIsEndToEndEncrypted,
                                                   tint: .green,
                                                   timestamp: nil,
                                                   dateSeparator: nil),
                                      // No identifier: this is not a message, has no row of its own to be scrolled to, and offers no context menu.
                                      cellIdentifier: nil,
                                      actions: actions)
                    .padding(.horizontal, Self.horizontalPadding)
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            // In sections, so that the `List` walks a section's rows to find one rather than the whole discussion's — see
            // `SingleDiscussionView.Model.theSections`.
            ForEach(theRowsOfEachSection) { theSection in
                Section {
                    ForEach(theSection.rows, id: \.self) { cellIdentifier in
                        // The branch is wrapped in a single-root container so that a row stays *unary*, i.e. produces exactly one top-level view whichever way it goes.
                        // See `SingleDiscussionCellView` for what a row that does not costs.
                        VStack(spacing: 0) {
                            if case .newMessagesMarker = cellIdentifier {
                                NewMessagesMarkerView(numberOfNewMessages: theMarker?.numberOfNewMessages ?? 0)
                                    // Where the marker is, for the entry to check it is where it was asked to be. On this one row only, so it costs nothing per row.
                                    .onGeometryChange(for: CGFloat.self) { proxy in
                                        proxy.frame(in: .named(Self.coordinateSpaceOfTheList)).midY
                                    } action: { middle in
                                        theGeometry.theMarkerIsAt(middle)
                                    }
                                    .onDisappear {
                                        theGeometry.theMarkerIsAt(nil)
                                    }
                            } else {
                                SingleDiscussionCellView(
                                    cellIdentifier: cellIdentifier,
                                    dataSource: dataSource,
                                    actions: actions,
                                    initialModel: initialModel(for: cellIdentifier)
                                )
                            }
                        }
                        // **The elastic scroll — see ``TheSpringEachMessageHangsFrom``.** On the whole row, which is the point of it: a
                        // message is **rigid**, its bubble, its date line, its reactions and its attachments keeping every distance between them, and what
                        // springs is one message against the next. Applied to the bubble at first, which would have sprung a message against its own date.
                        //
                        // Well above the `listRow*` modifiers at the end of this chain, as anything that reads geometry must be: a `List`
                        // reads those off the row it is handed, and a modifier wrapping around them makes the separators come back.
                        .modifier(TheMessageHangsFromASpringIfAsked(asked: elasticScrolling, theSpeed: theGeometry.theSpeedOfThisTranscript))
                        // **While the reader is choosing, nothing in a row answers a touch but the row itself**. A cell carries a long press, a double tap, and
                        // taps on a photograph, a poll's answers, a recording's controls, an itinerary, a sender's name and a reactions chip; taking the content out of hit
                        // testing is one rule that covers all of them and whatever is added later, where deciding at each gesture is a rule that is only true on the day it
                        // is written. The touch then reaches the cell behind, which is what the `List` selects with.
                        //
                        // A `List`'s edit mode is said to suppress the interactions of a row's content by itself, in which case this is redundant rather than wrong. It is
                        // kept until a screen says which — the failure it guards against is a photograph opening when the reader meant to tick a message.
                        .allowsHitTesting(!theReaderIsChoosingMessages)
                        // **After the line above, and that is why it works.** On a Mac the tick, the room it takes and the click that makes it are all ours — the `List`
                        // is given no selection there at all. `allowsHitTesting(false)` applies to what it wraps, so the click this adds is still felt while everything
                        // the message draws is not. Nothing whatever on a touch platform, where the `List` does all three. See ``AMessageTickedOnAMac``.
                        .aMessageTickedOnAMac(cellIdentifier,
                                              theReaderIsChoosingMessages: theReaderIsChoosingMessages,
                                              selectedCellIdentifiers: $selectedCellIdentifiers,
                                              theReaderClicked: theReaderClickedARow)
                        .padding(.horizontal, Self.horizontalPadding)
                        // 4pt above and below each row, so 8pt between two of them.
                        .padding(.vertical, 4)
                        // Whether this row is where the reader can read it, which is **not** the same question as whether it exists — see
                        // ``WhatTheReaderIsLookingAt/onScreen``.
                        //
                        // A `Bool` and not a frame, deliberately: the closure is evaluated as the row lays out, which during a scroll is every frame, but the action runs
                        // only when the answer flips. So the cost of following this is a rect comparison per created row, and a write per row per *crossing*.
                        .modifier(TheRowSaysWhetherTheReaderCanSeeIt(theGeometry: theGeometry) { theReaderCanSeeThisRow in
                            if theReaderCanSeeThisRow {
                                whatTheReaderIsLookingAt.onScreen.insert(cellIdentifier)
                                // Remembered even when it goes by under a finger, which is the whole of ``WhatTheReaderIsLookingAt/seenSinceTheLastReport``.
                                whatTheReaderIsLookingAt.seenSinceTheLastReport.insert(cellIdentifier)
                            } else {
                                whatTheReaderIsLookingAt.onScreen.remove(cellIdentifier)
                            }
                            saysWhatTheReaderIsLookingAtOnceTheRowsHaveSaid()
                        })
                        // A row appearing is the signal that this part of the discussion is about to be needed — which *wants* to run ahead of what can be seen, and is
                        // therefore the one thing `onAppear` is still right for here.
                        .onAppear {
                            prefetchesTheModelsAround(cellIdentifier)
                        }
                        // A row destroyed cannot measure itself any more, so it is dropped from what is on screen here rather than left in the set for ever.
                        //
                        // **The last row does not say whether the end is on screen**: a `List` prepares a row well before it can be seen. That is measured
                        // from the geometry instead, with a tolerance.
                        .onDisappear {
                            whatTheReaderIsLookingAt.onScreen.remove(cellIdentifier)
                        }
                        // **The row modifiers come last, after everything else this row carries.** They are not ordinary modifiers: a `List` reads them off the row it is
                        // given, and a modifier wrapped *around* them can hide them — putting `onGeometryChange` after `listRowSeparator(.hidden)` brought every separator
                        // back. Whatever is added to a row later goes above this line.
                        //
                        // **`selectionDisabled` belongs to this group, which is why it is here and not up beside the tick.** The marker is not a message and may not be
                        // ticked; it is inside this `ForEach` — so that the screen can scroll to it — and therefore carries a selection tag like every other row unless it
                        // is told not to. It *was* told not to, immediately after `aMessageTickedOnAMac`, and the marker was selectable all the same: the `padding` and
                        // `onGeometryChange` below it wrapped the row and hid it, the same way they hid the separators. The sentence about encryption needs none of this:
                        // it is outside the `ForEach`, has no tag, and so was never selectable.
                        .selectionDisabled(cellIdentifier == .newMessagesMarker)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                // A section draws nothing of its own: each date is drawn by the first message of its day, as it was before there were sections.
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        // No room between two sections, which would otherwise move every message below a section's first one.
        .listSectionSpacing(0)
        // What turns the ticks on. **A constant binding on purpose**: the mode belongs to the screen above, which enters and leaves it from the
        // ellipsis and from Cancel, so there is nothing here for the system to write back. An `EditMode` the `List` could set itself would be a second place the
        // mode lives, and the bar counting the ticks would not know about it.
        .environment(\.editMode, .constant(theEditModeTheListIsIn))
        // Anchored to the list's **frame** and not to its content, which is what lets a row say where it is on screen: a row scrolled above reports a negative `maxY`,
        // one below reports a `minY` past the bottom. See ``WhatTheReaderIsLookingAt/onScreen``.
        .coordinateSpace(.named(Self.coordinateSpaceOfTheList))
        // What a cell uses to ask to be taken elsewhere. Injected here, around the rows, since it is the rows that ask.
        .environment(\.whereTheReaderWantsToGo, whereTheReaderWantsToGo)
        // Which row a jump landed on, so that message can say so — see ``TheMessageAJumpLandedOn``. Written only when a reader jumps, which is why the environment
        // is acceptable: every cell is rebuilt on it, and that cost is paid on an event rather than on the scrolling path.
        .environment(\.theRowAJumpLandedOn, theRowAJumpLandedOn)
        // What a cell says when it starts carrying its files out of the discussion, so that the drop below refuses them until they have landed. One object for the
        // life of the screen, so no cell is ever rebuilt on its account.
        .environment(\.theDragOutOfTheDiscussion, theDragOutOfTheDiscussion)
        // The messages take whatever is dropped on them, which needs the `List`'s own collection view — see ``TakesWhateverIsDroppedOnTheMessages``, where the two
        // days that concluded this was impossible are answered.
        .messagesTakeWhateverIsDroppedOnThem(itemsWereDropped: itemsWereDroppedOnTheMessages,
                                             theDragOutOfTheDiscussion: theDragOutOfTheDiscussion)
        // A tap on the status bar must not carry the reader to the oldest message, and it is what the legacy screen does that this one had stopped
        // doing. See ``TheDiscussionDoesNotJumpToItsOldestMessage``.
        .theDiscussionDoesNotJumpToItsOldestMessage()
        .theTranscriptDoesNotHoldTouchesBack()
        // On a Mac, a click on the messages takes the caret out of the composition bar. See ``AClickOnTheMessagesTakesTheCaretAway``.
        .aClickOnTheMessagesTakesTheCaretAway(theReaderClickedOnTheMessages)
        .theTranscriptFadesUnderTheNavigationBar()
        // Covered until it has been sent where the discussion opens, then uncovered — see ``theListHasBeenPutWhereTheDiscussionOpens``, which says what is on
        // screen in the meantime and why it must not be, and ``theCoverUntilTheTranscriptIsInPlace`` for why it is a cover rather than the list's own opacity.
        .overlay { theCoverUntilTheTranscriptIsInPlace }
        // **The space below the messages is no longer answered from here.** It was a modifier at this point through 44d and 44e, and is now called
        // by the object that reads the geometry every frame, which already holds the scroll view and already knows whether the reader has hold of it. One
        // object reads, one rule answers, and there is exactly one writer of `contentOffset` — the doctrine of Step 44, made structural. What that rule does
        // and what it deliberately does not are in ``MovesTheMessagesWhenTheSpaceBelowThemChanges``.
        // Dragging the messages down dismisses the keyboard, following the finger, as `keyboardDismissMode = .interactive` does on the legacy screen. Without
        // this, there is no way at all to dismiss it without leaving the discussion.
        .scrollDismissesKeyboard(.interactively)
        // Frozen while a message is up: the copy the overlay draws is placed at the frame the real message had when it was lifted, and a transcript that could be
        // scrolled underneath it would leave the copy pointing at nothing to come back to.
        .modifier(TheTranscriptHoldsStillWhileAMessageIsLifted())
    }

    /// The model a cell can be shown with straight away, in order of freshness.
    ///
    /// The streamed model of the last cell is the freshest thing available, and only exists for that one cell. The seeds computed when the screen was entered
    /// come next, being a batched fetch of a screenful. The cache of the data source comes last: it holds whatever has been built since, which is how a cell
    /// that was released and re-created — as the `List` does whenever a row leaves and comes back — is shown with its content rather than flashing back to a
    /// skeleton. Every one of the three may be nil, and a skeleton is then correct.
    ///
    /// This runs for *every* row each time ``cellIdentifiers`` changes, not only for the visible ones, so it has to stay what it is: three lookups and no work.
    private func initialModel(for cellIdentifier: SingleDiscussionView.CellIdentifier) -> SingleDiscussionCellView.Model? {
        if cellIdentifier == cellIdentifiers.last, let lastCellModel { return lastCellModel }
        if let seededAtEntry = initialCellModels[cellIdentifier] { return seededAtEntry }
        return dataSource.cachedModelOfSingleDiscussionCellView(cellIdentifier: cellIdentifier)
    }


    // MARK: Saying what is on screen


    /// The name of the coordinate space rows measure themselves in — the list's frame, which does not move as the content does.
    ///
    /// **`nonisolated` because the row's geometry transform is `@Sendable`** and reads it — see ``theReaderCanSee(_:within:)``. A `String` needs no actor to be
    /// read safely, so this costs nothing and says so.
    nonisolated private static let coordinateSpaceOfTheList = "TheListOfCellsOfTheDiscussion"


    /// Whether a row at this frame is where the reader can read it.
    ///
    /// **Any overlap counts.** A message taller than the screen would satisfy no stricter rule, and a reader who can see a line of it has seen it — which is the rule
    /// the legacy screen keeps too, for all that it asks the question later than it should.
    ///
    /// There is no band at all until the first scroll geometry arrives, so nothing is seen before the list has been laid out — which is right: a row cannot have been
    /// read before the screen it is on exists.
    ///
    /// **The band is handed in rather than read here**, which lets this be `nonisolated`. SwiftUI declares `onGeometryChange`'s transform `@Sendable`, so it
    /// may run off the main actor and may not read the band, which belongs to a `@MainActor` object. The caller reads the band while it evaluates its body, on
    /// the main actor, and the closure captures the value.
    ///
    /// So the band is the one from the last evaluation of the row's modifier, not the one at the instant the row is measured. In practice they are the same:
    /// the modifier observes the geometry, so the band cannot move without the modifier running again and rebuilding this closure.
    nonisolated private static func theReaderCanSee(_ frameOfTheRow: CGRect, within visibleAreaOfTheList: ClosedRange<CGFloat>?) -> Bool {
        guard let visibleAreaOfTheList else { return false }
        return frameOfTheRow.maxY > visibleAreaOfTheList.lowerBound && frameOfTheRow.minY < visibleAreaOfTheList.upperBound
    }


    /// Hands over what the reader is looking at — the two answers, which are not the same and are not said at the same moment.
    ///
    /// **What is on screen goes at once, scrolling or not.** It keeps the expiration of a sensitive message running while it is being looked at, and a message going
    /// by under a finger *is* being looked at; the legacy screen refreshes its visibility tracker from `willDisplay` with no regard for scrolling at all. Waiting
    /// would mean a message with a visibility duration outliving what its sender allowed.
    ///
    /// **What has been seen waits for the list to stop**, and is then handed over whole — everything that went by since the last time, not merely what remained on
    /// screen. That is what makes flinging through a discussion clear its badge, and it is what the legacy screen does by accumulating and flushing. Postponing it
    /// also spares the app a fetch per row while a finger is moving.
    ///
    /// Both are compared with what was last said, so that nothing is said twice.
    private func saysWhatTheReaderIsLookingAt() {

        whatTheReaderIsLookingAt.aReportIsOnItsWay = false

        let seen = isUnderTheReadersFinger ? [] : whatTheReaderIsLookingAt.seenSinceTheLastReport
        let whatIsOnScreenHasChanged = (whatTheReaderIsLookingAt.onScreen != whatTheReaderIsLookingAt.lastReportedAsOnScreen)

        guard whatIsOnScreenHasChanged || !seen.isEmpty else { return }

        whatTheReaderIsLookingAt.lastReportedAsOnScreen = whatTheReaderIsLookingAt.onScreen
        if !seen.isEmpty { whatTheReaderIsLookingAt.seenSinceTheLastReport = [] }

        reportsWhatTheReaderIsLookingAt(whatTheReaderIsLookingAt.onScreen, seen)

    }


    /// What a row crossing the fold asks for, once the other rows of the same layout pass have said whether they crossed it too. Several rows often cross in one
    /// pass. One report on the next turn of the main actor covers them all, at most a frame later, instead of one call to the app per row.
    private func saysWhatTheReaderIsLookingAtOnceTheRowsHaveSaid() {
        guard !whatTheReaderIsLookingAt.aReportIsOnItsWay else { return }
        whatTheReaderIsLookingAt.aReportIsOnItsWay = true
        Task { @MainActor in
            saysWhatTheReaderIsLookingAt()
        }
    }




    // MARK: Prefetching the models of the cells about to be displayed

    /// Asks the data source to have the models of the cells around the one that just appeared ready, so that each of them is *created* with its content.
    ///
    /// This is what stops the list from jumping as it is scrolled. A cell created without a model shows a skeleton of a fixed, one-line height and becomes as
    /// tall as its message a few milliseconds later; that second sizing moves everything around it.
    ///
    /// The window reaches well beyond the cell that appeared, in both directions, the point being to be ready *before* a cell is created rather than as it is.
    /// Rows appear one at a time, so a scroll produces a rapid series of heavily overlapping windows; the data source keeps only the identifiers whose models it
    /// does not already hold, which makes the repetition cheap.
    private func prefetchesTheModelsAround(_ cellIdentifier: SingleDiscussionView.CellIdentifier) {
        guard let index = indexOfCellIdentifier[cellIdentifier] else { return }
        let lowerBound = max(cellIdentifiers.startIndex, index - Self.numberOfCellsToPrefetchAroundOneAppearing)
        let upperBound = min(cellIdentifiers.endIndex, index + Self.numberOfCellsToPrefetchAroundOneAppearing + 1)
        dataSource.prefetchModelsOfSingleDiscussionCellViews(cellIdentifiers: Array(cellIdentifiers[lowerBound..<upperBound]))
    }

    /// How far beyond the cell that just appeared to prepare, in each direction.
    ///
    /// Two screenfuls of short messages, a screenful being fewer than twenty. Asking for less risks the prefetch trailing a fast scroll; asking for much more
    /// risks the models of the cells being displayed queueing behind those of cells that will never be seen, since the data source builds them on the one
    /// background queue this screen's streams also use — and the cache that holds them is bounded.
    private static let numberOfCellsToPrefetchAroundOneAppearing = 30

}


// MARK: - What observes the geometry, each on its own

@available(iOS 18.0, *)
extension SingleDiscussionCellsListView {

    /// Owns ``TheGeometryOfTheTranscriptReadPerFrame`` for the life of the list, as a `@StateObject` does, without the list observing it: this publishes
    /// nothing, so nothing the geometry publishes re-evaluates the list. Not a `@State`: its initial value would be built at every initialisation of the view,
    /// and building the geometry registers observers on the keyboard.
    @MainActor
    fileprivate final class TheGeometryHeldWithoutBeingObserved: ObservableObject {
        let theGeometry = TheGeometryOfTheTranscriptReadPerFrame()
    }


    /// The way back, offered when the end is far below what the reader can see and the discussion has finished opening. It observes the geometry so that the
    /// list does not have to — see ``theHolderOfTheGeometry``.
    fileprivate struct TheButtonBackToTheEndOfferedByTheGeometry: View {

        @ObservedObject var theGeometry: TheGeometryOfTheTranscriptReadPerFrame
        let theDiscussionHasOpened: Bool
        let goBack: () -> Void

        var body: some View {
            TheButtonBackToTheEnd(isShown: theGeometry.theEndIsFarBelowWhatTheReaderCanSee && theDiscussionHasOpened, goBack: goBack)
        }

    }


    /// Says what the reader has seen when they take hold of the transcript and when they let go of it, the second being what clears the badge after a fling. It
    /// observes the geometry so that the list does not have to — see ``theHolderOfTheGeometry``.
    fileprivate struct SaysWhatWasSeenWhenTheReadersHandMoves: ViewModifier {

        @ObservedObject var theGeometry: TheGeometryOfTheTranscriptReadPerFrame
        let action: () -> Void

        func body(content: Content) -> some View {
            content.onChange(of: theGeometry.isUnderTheReadersFinger) { _, _ in
                action()
            }
        }

    }


    /// What the rows have said about being seen, and what was last handed over to the app. Read and written on the main actor only, by the rows' actions and by
    /// ``SingleDiscussionCellsListView/saysWhatTheReaderIsLookingAt()``.
    @MainActor
    fileprivate final class WhatTheReaderIsLookingAt {

        /// The rows the reader can actually see, each row having measured itself.
        ///
        /// **Not `onAppear`.** That fires when a `List` *creates* a row, which it does well beyond the fold — so a message the reader has never seen would be
        /// marked read. The legacy screen's `willDisplay` is generous in the same way, but a `UICollectionView` prepares far less, so it never showed there. Each
        /// row therefore tests its own frame against the band the reader can read, and says so only when the answer changes — see
        /// ``TheRowSaysWhetherTheReaderCanSeeIt``.
        var onScreen = Set<SingleDiscussionView.CellIdentifier>()

        /// The last set handed over, so that nothing is said twice. The set changes on every row that appears; what is *reported* is only what differs.
        var lastReportedAsOnScreen = Set<SingleDiscussionView.CellIdentifier>()

        /// Every row the reader has seen since the last time this was said — including the ones that went by under a finger and are already gone again.
        ///
        /// **This is what makes flinging through a discussion mark it read**, which is how people clear a badge and what the legacy screen does by accumulating
        /// into `messagesToMarkAsNotNewWhenScrollingEnds`. Reporting only what is on screen when the list stops would leave the messages in between unread for
        /// ever: read one to ten, fling past eleven to nineteen, read twenty to thirty, and the discussion still claims nine unread — which a reader who has just
        /// read the *last* message cannot make sense of.
        ///
        /// Emptied each time it is handed over. It is not the same question as ``onScreen``, and that is the whole point of there being two.
        var seenSinceTheLastReport = Set<SingleDiscussionView.CellIdentifier>()

        /// Whether a report asked for by a row is already queued — see
        /// ``SingleDiscussionCellsListView/saysWhatTheReaderIsLookingAtOnceTheRowsHaveSaid()``.
        var aReportIsOnItsWay = false

    }


    /// The rows the `List` was last given, cut into its sections, which ``SingleDiscussionCellsListView/whereTheRowIs(_:in:)`` finds a row among. Written by
    /// every evaluation of the list's body.
    ///
    /// **Not cut again where a scroll needs them**, because a scroll may run on an old copy of the view. A jump is read by a `.task`, which keeps the copy of
    /// the view it started with, so rows cut from that copy are the rows of the screen as it appeared. A message deleted and another sent in the same month left
    /// the counts equal, and a jump then landed one row below its message.
    @MainActor
    fileprivate final class TheRowsTheListWasLastGiven {

        var sections = [TheRowsOfASection]()

        /// The sections the `List` puts before them: one for the sentence saying the discussion is end-to-end encrypted, a row outside the sections, when
        /// there is one.
        var sectionsBeforeThem = 0

    }


    /// Freezes the transcript while a message is lifted out of it — see ``TheMessageBeingLifted``. The screen owns the interaction and the overlay, and this reads
    /// the one fact the list needs of them from the environment, as the messages do.
    ///
    /// **Read here and not by the list.** Otherwise the list's body would run, and compare every row of the discussion, each time a message is lifted or put
    /// back.
    fileprivate struct TheTranscriptHoldsStillWhileAMessageIsLifted: ViewModifier {

        @Environment(\.theMessageBeingLifted) private var theMessageBeingLifted

        func body(content: Content) -> some View {
            content.scrollDisabled(theMessageBeingLifted.takenByTheOverlay != nil)
        }

    }


    /// Whether a row is where the reader can read it: inside the band from the list's top inset to its bottom one, in the list's own coordinate space. The content
    /// scrolls **behind** the composition bar, so a message under it is on screen and unreadable; taking the bottom inset off keeps it from counting as seen. There
    /// is no band until the first frame has been read, so no row is seen before the list has been laid out.
    ///
    /// The band moves with the keyboard and the composition bar, on every frame of their animations. Observed here, a move re-evaluates only the rows that
    /// exist. Observed by the list, it would re-evaluate every row of the discussion. See ``theHolderOfTheGeometry``.
    fileprivate struct TheRowSaysWhetherTheReaderCanSeeIt: ViewModifier {

        @ObservedObject var theGeometry: TheGeometryOfTheTranscriptReadPerFrame
        let action: (Bool) -> Void

        func body(content: Content) -> some View {
            content.onGeometryChange(for: Bool.self) { [visibleAreaOfTheList = theGeometry.visibleAreaOfTheList] proxy in
                SingleDiscussionCellsListView.theReaderCanSee(proxy.frame(in: .named(SingleDiscussionCellsListView.coordinateSpaceOfTheList)),
                                                              within: visibleAreaOfTheList)
            } action: { theReaderCanSeeThisRow in
                action(theReaderCanSeeThisRow)
            }
        }

    }

}
