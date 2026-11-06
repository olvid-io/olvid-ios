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
import UniformTypeIdentifiers
import OSLog


/// The composition bar takes whatever is dropped on it, and puts it in the draft.
///
/// **In this module, so that both discussion screens have it.** The bar is shared: the legacy screen hosts the same `ComposeView` as the
/// SwiftUI one, and both already implement `ComposeViewActions.userWantsToAddAttachmentsToDraft(_:discussionIdentifier:itemProviders:)`,
/// which is where this ends. So the feature costs neither screen a line, and the legacy screen *gains* something it never had: its own drop
/// is on its collection view, and a file let go over its bar is refused today.
///
/// ## The bar, and — separately — the messages
///
/// No SwiftUI drop target works where a `List` is. Measured on Mac Catalyst over two days, in the SwiftUI screen: five drop APIs at seven
/// positions in and around the transcript's `List` — around it, on it, on each row, `onInsert`, `dropDestination`, and a hit-testable view
/// laid in front of it — and **not one of them is ever offered the drag**, while the same modifier over the bar takes it from the first
/// frame. With the `List` replaced by a plain view of the same size, in the same screen, the drop works; and switching off all eight layers
/// that screen puts over its list changes nothing. So it is `List` itself, and it is not Olvid's doing.
///
/// That is a fact about SwiftUI's drop APIs, and it was taken for a while as a fact about the region. The messages of the SwiftUI screen
/// **do** take a drop — through the `List`'s own `UICollectionView` and a `UICollectionViewDropDelegate`, which is how the legacy screen has
/// always done it. It is answered over there rather than here because only that screen can reach that collection view; both routes end in the
/// same ``ComposeView/SharedState/itemsWereDropped(_:)``, which is what keeps them from meaning two different things. See
/// `TakesWhateverIsDroppedOnTheMessages`.
///
/// A reader aiming at a discussion aims at where they type, so this half was always most of the value — and it is where the legacy screen is
/// *weakest*, its bar being the one place a drop is refused there.
///
/// ## `onDrop` and not `dropDestination`, deliberately
///
/// `dropDestination(for:)` is the newer API and the `Transferable` one, and it cannot express this. A `Transferable` is a **type**: to accept
/// what this bar must accept — any file out of Finder, a photograph, a screenshot, a link with its preview metadata, a snippet of text — one
/// would have to enumerate those types in advance and re-implement the receiving of each. That receiving already exists, is shared with
/// paste, the share extension, the photo picker and AirDrop, and knows things a hand-rolled conformance would not: how a link arrives with
/// `UTType.appleLinkpresentationMetadata` and yields both an attachment and a line of text, for one.
///
/// `onDrop(of:isTargeted:perform:)` hands over `[NSItemProvider]`, which is exactly what that operation takes, and `UTType.item` is *any*
/// item — the same unconditional acceptance the legacy screen's `canHandle(session:)` gives. It is not deprecated, and it exists on macOS as
/// well as on iOS, so it survives the AppKit port. Newer is not the same as later.
///
/// ## What it does not decide
///
/// Nothing about what a dropped thing *becomes*. Attachment, text, or both, is answered by the operation behind
/// ``ComposeView/SharedState/itemsWereDropped(_:)`` — the same one the other three ways into this bar use. The bar closes itself to
/// editing while the copy is made, and opens again however it ends.
///
/// **A text field keeps its own drops.** A `TextEditor` accepts text natively, and an inner view that accepts a drop is offered it before an
/// outer one, so a sentence dropped straight onto the field is *typed* into the draft while the same sentence dropped elsewhere on the bar
/// arrives here and is written into the draft's text. Two routes, one outcome.
struct TakesWhateverIsDroppedOnTheBar: ViewModifier {

    /// Where a drop goes. The bar's own state, which holds the draft's identity and the flag that closes it to editing.
    let sharedState: ComposeView.SharedState

    func body(content: Content) -> some View {
        content
            // **`nil`, and the question that made that look doubtful is answered.** This bar once refused every drop on a Mac, showing no `+`
            // cursor at all, and a non-nil `isTargeted` binding was in the build that then took them — five for five. But those two runs were
            // also a fresh process against one that had been up for fifty minutes and crashed once, so which change mattered was not knowable
            // from them. Asked again on 2026-08-29 with one variable moving: fresh process, `nil`, a Mac — the `+` appeared over the bar and the
            // drop landed in the draft, five times. **The binding is innocent**; the refusal belongs to a state a worn process falls into, which
            // is unexplained and is tracked in `drag-and-drop.md` rather than here.
            .onDrop(of: [.item], isTargeted: nil) { itemProviders in
                theProbe.info("the bar was HANDED \(itemProviders.count, privacy: .public) item(s)")
                // An empty drop is not a drop. Answering `false` leaves the system to fly the item back where it came from, which is the
                // truthful animation: nothing was taken.
                guard !itemProviders.isEmpty else { return false }
                sharedState.itemsWereDropped(itemProviders)
                return true
            }
    }


    // MARK: - Kept for the drop crash, and no longer for the question it was written for

    /// **TEMPORARY until the drop crash of 2026-08-25 is understood or written off.** Written on 2026-08-25, when a file dragged over this bar showed **no `+` cursor at all** and flew back — on the SwiftUI
    /// screen *and* on the legacy one, which share this modifier — to ask the question that actually mattered: is this drop target ever
    /// **offered** the session? *No cursor* is evidence about the **cursor**, and only the callback can say whether anything was handed over.
    ///
    /// **That question is closed** — 2026-08-29, fresh process, `nil`, a Mac: offered, and handled, five times. It stays for a *different*
    /// reason, and the reason is worth stating so nobody removes it as spent. The refusal and the crash on leaving a discussion are plausibly
    /// one fault, and the fingerprint of the state they share is this category saying *the messages are answering a session* while the bar is
    /// handed nothing. That is the cheapest thing anybody has that would catch the state **before** the crash does, and the crash is parked
    /// rather than fixed.
    ///
    /// Such an answer has to be measured rather than reasoned about — a silent probe is not an answer until you
    /// have proved it runs, and two rounds were lost on this screen to reading an absence of log lines as a guard refusing when the callback
    /// was never called.
    ///
    /// A file-scope `let` rather than a static on the `ViewModifier`: a `Logger` is `Sendable`, where a main-actor-isolated static referenced
    /// from `onDrop`'s `Sendable` closure is a warning that says nothing useful.
    ///
    /// The companion probe on `isTargeted` was taken out with the binding it needed — see the note at the `onDrop` above.

}


/// **TEMPORARY until the drop crash of 2026-08-25 is understood or written off.** See the note inside ``TakesWhateverIsDroppedOnTheBar``.
private let theProbe = Logger(subsystem: "io.olvid.messenger", category: "TranscriptDrop")
