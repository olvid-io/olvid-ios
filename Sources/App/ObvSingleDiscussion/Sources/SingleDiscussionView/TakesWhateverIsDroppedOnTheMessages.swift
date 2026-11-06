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


/// The messages take whatever is dropped on them, and put it in the draft — the half of Step 26a that was given up on, taken again.
///
/// **Why this is UIKit.** Two days were spent asking SwiftUI for it: `onDrop` around the list, on the list, on each row; `onInsert` and `dropDestination`
/// on the `ForEach`; a hit-testable view laid in front of it — **not one is ever offered the drag**, while the same modifier over the composition bar takes
/// it from the first frame. With the `List` replaced by a plain `Color`, the drop lands.
///
/// **What that measured and what it was read as are not the same thing.** Every position in that table is a *SwiftUI* drop API, so what was proven is that
/// no SwiftUI drop target works where a `List` is — not that the region refuses drops. The row nobody ran is this one: legacy's transcript takes drops
/// through **`UICollectionViewDropDelegate`**, set on its own collection view, and that was seen working on Catalyst. From iOS 16 a `List` *is* a
/// `UICollectionView`, and `swiftui-introspect` hands it over. Same class, same delegate, same platform. The session does reach the collection view; what
/// was missing was something to answer for it.
///
/// **What it does** is exactly what the legacy delegate does: accept anything, propose `.copy`, hand the item providers on. Where they *go* is not decided
/// here, and not decided differently from the bar — both end in the one operation that turns a dropped thing into an attachment, into text, or into both.
/// See ``TakesWhateverIsDroppedOnTheBar``, which says why that route is `[NSItemProvider]` and not `Transferable`.
///
/// It proposes **no insertion**, which keeps the list from opening a gap under the reader's finger for a row that will never be inserted; a discussion is
/// not a reorderable list, and legacy makes the same choice by omission. The one thing it refuses is a drag that came **out of this very discussion**,
/// which is ``TheDragOutOfTheDiscussion``.
///
/// **The availability annotation is inherited from the list and is not required here** — `UICollectionViewDropDelegate` is far older. It is kept in step
/// with ``SingleDiscussionCellsListView`` so that the platform list of the introspection below cannot drift from the versions the screen runs on. That
/// drift is not hypothetical: it was left at `.iOS(.v18, .v26)` when the screen briefly went to 17, which would have installed no delegate at all on 17 —
/// silently, a platform list being a value rather than availability. **Move both together, or not at all.**
@available(iOS 18.0, *)
struct TakesWhateverIsDroppedOnTheMessages: ViewModifier {

    /// Where a drop goes: out through the screen, to the app, and into the draft.
    let itemsWereDropped: ([NSItemProvider]) -> Void

    /// Whether a drag is presently carrying files *out* of this discussion, in which case nothing may be dropped back into it.
    let theDragOutOfTheDiscussion: TheDragOutOfTheDiscussion

    /// An object rather than state: it is read from UIKit callbacks, outside any SwiftUI update.
    @State private var whatTheMessagesTake = WhatTheMessagesTake()

    func body(content: Content) -> some View {
        content
            .introspect(.list, on: .iOS(.v18, .v26, .v27)) { collectionView in
                whatTheMessagesTake.hands(to: itemsWereDropped, refusingWhile: theDragOutOfTheDiscussion)
                whatTheMessagesTake.installsItself(on: collectionView)
            }
            .onDisappear {
                whatTheMessagesTake.saysTheScreenIsGoing()
            }
    }

}


extension View {

    /// Lets whatever is dropped on the messages reach the draft — see ``TakesWhateverIsDroppedOnTheMessages``.
    @available(iOS 18.0, *)
    func messagesTakeWhateverIsDroppedOnThem(itemsWereDropped: @escaping ([NSItemProvider]) -> Void, theDragOutOfTheDiscussion: TheDragOutOfTheDiscussion) -> some View {
        modifier(TakesWhateverIsDroppedOnTheMessages(itemsWereDropped: itemsWereDropped, theDragOutOfTheDiscussion: theDragOutOfTheDiscussion))
    }

}


/// What answers for a drop over the messages — see ``TakesWhateverIsDroppedOnTheMessages``, where all of this is explained.
@MainActor
final class WhatTheMessagesTake: NSObject {

    private var itemsWereDropped: (([NSItemProvider]) -> Void)?
    private var theDragOutOfTheDiscussion: TheDragOutOfTheDiscussion?


    /// When a session was last answered, so that the teardown below can say whether one was in flight as the screen went.
    ///
    /// **The one thing the crash's log would otherwise not carry.** The two probes above establish *that* a session was claimed by the messages;
    /// this establishes *how close to the departure* — which is the difference between the drop having caused the teardown fault and merely having
    /// happened earlier in the same discussion. A `Date` rather than a flag, because a flag would need clearing on every way a session can end and
    /// a missed one would read as a session permanently in flight.
    private var whenASessionWasLastAnswered: Date?


    /// Says the screen is going, and how long ago a drop session was last answered — **kept until the drop crash of 2026-08-25 is understood or
    /// written off**, which is a condition and not a date, the crash having no reproduction to put one against.
    ///
    /// The crash of 2026-08-25 has a stack and no reproduction: `sessionDidEnter` and `sessionDidUpdate` delivered into SwiftUI's own
    /// `DragAndDropBridge` during a cancel, in a process that had *also* stopped offering the composition bar any session at all. The standing
    /// hypothesis is a session still in flight when the discussion is left. Nothing in this category said when that was, so a tester's log could
    /// show the session and the crash and not the order of them.
    ///
    /// **`onDisappear` is the right hook here and is wrong for most things**, which is worth saying at the call site: it
    /// does not fire on backgrounding, and it was measured on this screen not firing behind a full-screen presentation either. Both are correct for
    /// this line — neither is the discussion being *left*, which is the only case the crash is about.
    func saysTheScreenIsGoing() {
        guard let whenASessionWasLastAnswered else {
            theProbe.info("the messages are going, having answered no session at all")
            return
        }
        let howLongAgo = Date.now.timeIntervalSince(whenASessionWasLastAnswered)
        theProbe.info("the messages are going \(String(format: "%.1f", howLongAgo), privacy: .public)s after last answering a session")
    }


    /// Points this object at where a drop goes, and at what says a drag is presently leaving this discussion.
    func hands(to itemsWereDropped: @escaping ([NSItemProvider]) -> Void, refusingWhile theDragOutOfTheDiscussion: TheDragOutOfTheDiscussion) {
        self.itemsWereDropped = itemsWereDropped
        self.theDragOutOfTheDiscussion = theDragOutOfTheDiscussion
    }


    /// Takes the collection view's `dropDelegate`, which is the whole of the trick.
    ///
    /// **The property is not free when we arrive.** A `List` installs `CollectionViewListDragAndDropController` there — measured on Catalyst,
    /// 2026-08-15, by printing what held it — which is what serves `onMove`, `onInsert`, `dropDestination` and `draggable` on rows. This screen
    /// asks for none of those, so replacing it takes nothing away; a row that later wants one of them will have to be given it here rather than
    /// in SwiftUI, and it would fail *silently*, which is the trap worth knowing about.
    ///
    /// That controller is also the answer to why no SwiftUI drop target on this screen was ever offered a drag: it claims the session and then
    /// proposes nothing, and a `UIDropInteraction` that answers "mine" consumes it — so nothing above it, below it, or beside it is asked.
    ///
    /// **Re-asserted rather than installed once**, the property being one SwiftUI has written to at least once. It has never been seen taken
    /// back — the same measurement counted the installations per screen and the answer was always exactly one — so this is a guard rather than
    /// a mechanism, and it costs a pointer comparison per update of the list. `dropDelegate` is `weak`, which is why this object is held as
    /// state by the modifier.
    func installsItself(on collectionView: UICollectionView) {
        guard collectionView.dropDelegate !== self else { return }
        collectionView.dropDelegate = self
        // **TEMPORARY until the drop crash of 2026-08-25 is understood or written off** — written for Step 50's Catalyst walk, which is long finished.
        // Says who held the property before we took it, and that we took it — so that a silence from
        // the two delegate probes can be told apart from this never having been installed at all.
        theProbe.info("the messages took the collection view's dropDelegate")
    }


}


// MARK: - UICollectionViewDropDelegate

@MainActor
extension WhatTheMessagesTake: UICollectionViewDropDelegate {

    /// Anything at all, as `NewSingleDiscussionViewController.collectionView(_:canHandle:)` answers — except what is on its way out of this
    /// discussion.
    func collectionView(_ collectionView: UICollectionView, canHandle session: any UIDropSession) -> Bool {
        let answer = theDragOutOfTheDiscussion?.isInProgress != true
        // **TEMPORARY until the drop crash of 2026-08-25 is understood or written off.** The composition bar's own drop target is never offered a session, on both discussion
        // screens — and a `UIDropInteraction` that answers *mine* **consumes** the session, which is this document's own explanation for why
        // no SwiftUI drop target near the `List` was ever offered one. So the question is whether this delegate is claiming a session whose
        // pointer is over the bar rather than over the messages. Reported unconditionally, at the top, in both directions.
        theProbe.info("the messages were asked whether they CAN HANDLE a session → \(answer ? "YES" : "no", privacy: .public)")
        return answer
    }


    /// `.copy`, and no insertion: a discussion has no gap to open. The refusal while a drag is leaving is legacy's, and is
    /// ``TheDragOutOfTheDiscussion``.
    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: any UIDropSession, withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
        // **TEMPORARY until the drop crash of 2026-08-25 is understood or written off** — see the note in `canHandle` above. The location says whether the session being claimed here
        // is one whose pointer is over the messages or over the composition bar below them — but it arrives in the collection view's **content**
        // coordinates, so it must have the offset taken off it before it can be compared with a height. The first version of this line printed
        // `y=2510 of 721` and meant nothing.
        whenASessionWasLastAnswered = .now
        let whereThePointerIsOnScreen = session.location(in: collectionView).y - collectionView.contentOffset.y
        theProbe.info("the messages are answering a session \(String(format: "%.0f", whereThePointerIsOnScreen), privacy: .public)pt down a viewport of \(String(format: "%.0f", collectionView.bounds.height), privacy: .public), inset \(String(format: "%.0f", collectionView.adjustedContentInset.bottom), privacy: .public)")
        guard theDragOutOfTheDiscussion?.isInProgress != true else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        return UICollectionViewDropProposal(operation: .copy)
    }


    /// The drop itself. Nothing is inserted into the collection view — what was dropped belongs to the draft, not to the transcript — so the
    /// coordinator is read for its items and let go, exactly as the legacy screen reads it.
    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: any UICollectionViewDropCoordinator) {
        let itemProviders = coordinator.items.map(\.dragItem.itemProvider)
        guard !itemProviders.isEmpty else { return }
        itemsWereDropped?(itemProviders)
    }

}


// MARK: - The drag that is leaving

/// Whether files are presently being carried **out** of this discussion, which is what makes the transcript refuse a drop.
///
/// It is legacy's `isDragSessionInProgress`, and it exists to prevent one accident: a message's own attachments dragged out and let go again
/// over the discussion they came from, re-attaching to the draft what is already in the discussion. The legacy screen has both ends of it on
/// one controller; here they are a `UIDragInteraction` on each cell — ``TheAttachmentsOfAMessageDraggedOut`` — and a `dropDelegate` on the
/// list, so this object is the channel between them, in the shape ``PressesOnMessages`` and ``WhereTheReaderWantsToGo`` already use.
///
/// This was once skipped, for the reason that with
/// the drop on the *bar*, the accident it prevents needs a reader to carry a message's files deliberately down to the composition bar, and
/// wiring it would have meant a signal crossing two modules. Now that the transcript takes the drop, both ends are in this module and it costs
/// a boolean.
///
/// A class, and read from UIKit callbacks rather than from a body: nothing here is state a view draws from.
@MainActor
final class TheDragOutOfTheDiscussion {

    /// Set as a drag out of this discussion begins and ends — see ``TheAttachmentsOfAMessageDraggedOut``, which sets it.
    var isInProgress = false

}


// MARK: - The environment

extension EnvironmentValues {

    /// Whether something is being dragged out of this discussion — see ``TheDragOutOfTheDiscussion``.
    ///
    /// Optional, with nothing as its default, for the reason ``EnvironmentValues/pressesOnMessages`` gives: a cell drawn outside this screen —
    /// every preview of one — then reports to nobody rather than to a stand-in nobody reads. A drag from such a cell is still a drag; it is
    /// merely nobody's business that it is happening.
    var theDragOutOfTheDiscussion: TheDragOutOfTheDiscussion? {
        get { self[TheDragOutOfTheDiscussionKey.self] }
        set { self[TheDragOutOfTheDiscussionKey.self] = newValue }
    }

}


private struct TheDragOutOfTheDiscussionKey: EnvironmentKey {
    static let defaultValue: TheDragOutOfTheDiscussion? = nil
}


/// **TEMPORARY until the drop crash of 2026-08-25 is understood or written off** — the same category the composition bar's own drop probe uses, so that the two ends of one session are read in a single stream
/// and *which* target was offered it is a matter of reading the order. See ``TakesWhateverIsDroppedOnTheBar`` for the other end of it.
///
/// A file-scope `let` rather than a static on the `@MainActor` class, for the reason the sibling file gives: a `Logger` is `Sendable`, where a
/// main-actor-isolated static is a warning wherever it is read from anything that is not.
private let theProbe = Logger(subsystem: "io.olvid.messenger", category: "TranscriptDrop")
