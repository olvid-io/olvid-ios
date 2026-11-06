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


/// Everything the context menu adds to the discussion screen: the overlay that draws a lifted message, the two environment values the messages read, the task
/// that follows what the reader's finger is doing, and the three occasions on which the overlay has to be taken away.
///
/// **A modifier of its own rather than a dozen lines in the screen's body**, and not only for tidiness: inlined, it made that body large enough for the Swift type
/// checker to give up on the whole expression — which it reports as a failure of the *body*, naming none of the part that had grown.
///
/// **Applied after the composition bar has been inserted into the safe area**, so the backdrop covers the bar as well as the transcript. What it cannot cover is
/// the navigation bar, which is UIKit's own chrome above this view: the one thing the system's context menu gets for free and this does not.
struct TheContextMenuOfAMessageOnThisScreen: ViewModifier {

    /// The state machine, owned by the screen. A binding rather than a value because the screen writes it and this reads it, and both must see the same one.
    @Binding var contextMenu: TheContextMenuOfAMessage

    /// The one flag every visible movement hangs on. Read only: it is the screen that sets it, inside the single animation that the eye sees.
    let theMessageIsUp: Bool

    /// The rows of the discussion, watched for the one case that leaves the overlay with nowhere to put its message back: the message being deleted while it is up.
    let cellIdentifiers: [SingleDiscussionView.CellIdentifier]

    let pressesOnMessages: PressesOnMessages

    /// What a cell uses to ask to be taken elsewhere — **injected around the copy so that it is laid out in the same environment the rows are**, and for no
    /// other reason: the copy is not hit-testable, so nothing here is ever asked to go anywhere.
    ///
    /// The rows get this from `SingleDiscussionCellsListView`, around the `List`; the overlay is outside that, so until 2026-08-26 the copy was drawn without
    /// it. **It is not known to change any measurement**, and the honest history is worth more than a tidy claim: it was added while chasing a copy drawn 3.4%
    /// wider than its message, on the theory that `MessageRepliedToView` **branches on this value** — wrapping its header in a `Button` where there is somewhere
    /// to go, drawing it bare where there is not — and that a button's label is not proposed the same width. The real cause turned out to be
    /// ``MessageBodyView`` inheriting its font, and this was left in place on its own merits rather than on that theory's.
    ///
    /// Those merits are the reason to keep it: a copy laid out in a *different* environment from the original will drift wherever the two environments differ,
    /// and this screen was bitten by that class twice within one hour — the font, and this branch. Injecting what the rows get costs nothing and removes the
    /// family rather than one member of it.
    ///
    /// **A suspicion recorded rather than fixed**: a view's *size* should not depend on whether it has an action. While `MessageRepliedToView` decides its
    /// shape that way, two identical quotes may differ in width inside the transcript itself, depending on whether the message they quote still exists — which
    /// is unmeasured, and is not this step's to change.
    let whereTheReaderWantsToGo: WhereTheReaderWantsToGo

    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    /// What the messages of the discussion are told, computed by the screen rather than derived here — and that is Step 60's doing.
    ///
    /// **Two treatments can hide a message now**: this one, and the copy held beside the composition bar while the reader writes a reply. Only one modifier may
    /// publish the value they both speak through, or whichever is applied further out silently overrides the other — so the screen decides which of its two
    /// states is speaking and this carries the answer. It used to read `contextMenu.asTheMessagesSeeIt` here, which was right while there was one treatment.
    let theMessageBeingLifted: TheMessageBeingLifted

    let followsThePresses: () async -> Void

    /// **Carries the model as well as the identifier** — Step 60: choosing *Reply* takes the message down beside the composition bar, and the copy drawn there
    /// has to be drawn from something. This is the one place that still holds what the message was when it was lifted.
    let chose: (MessageAction, SingleDiscussionView.CellIdentifier, SingleDiscussionCellView.Model, TheCopyTheMenuHandsOver) -> Void
    let dismiss: () -> Void

    /// Takes the overlay away without animating anything, there being nothing left to animate to.
    let dismissAtOnce: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    func body(content: Content) -> some View {
        content
            // The anchors resolve in the space of the view this is attached to, which is why the `GeometryReader` and the anchors meet here and not in two places.
            .overlayPreferenceValue(WhereTheMessagesAre.self) { whereTheMessagesAre in
                GeometryReader { proxy in
                    // A `Group`, and not a container: with nothing lifted this must contribute no subview at all.
                    if let lifted = contextMenu.whatTheOverlayHasTaken, let anchor = whereTheMessagesAre[lifted.cellIdentifier] {
                        MessageContextMenuOverlay(
                            model: lifted.model,
                            offers: lifted.offers,
                            emojis: lifted.emojis,
                            whereTheMessageIs: proxy[anchor],
                            within: proxy.size,
                            appeared: theMessageIsUp,
                            dataSource: dataSource,
                            actions: actions,
                            chose: { action, theCopy in chose(action, lifted.cellIdentifier, lifted.model, theCopy) },
                            dismiss: dismiss)
                        // **The copy is laid out in the environment the rows are laid out in** — see ``whereTheReaderWantsToGo``, which says what it cost to
                        // be missing. On the overlay rather than on `content`, which already has it from the list.
                        .environment(\.whereTheReaderWantsToGo, whereTheReaderWantsToGo)
                    }
                }
            }
            // What the messages themselves need to know: which of them is under a finger, and which of them the overlay has taken. A value rather than an object
            // anything observes — see ``TheMessageBeingLifted``. The list reads the same value to know that it must hold still.
            .environment(\.theMessageBeingLifted, theMessageBeingLifted)
            .environment(\.pressesOnMessages, pressesOnMessages)
            .task { await followsThePresses() }
            // Whatever the overlay stands on, changing under it. See ``WhatTheOverlayStandsOn`` for the two things that can, and
            // ``dismissAtOnce`` for what is done about them.
            //
            // **`task(id:)` and not `onChange(of:)`**, which in the two-closure form that reports the old value is iOS 17 while this module is iOS 16. It fires
            // once on appearance as well, with nothing lifted, which the guard inside makes a no-op.
            .task(id: whatTheOverlayStandsOn) {
                guard contextMenu.isUp else { return }
                dismissAtOnce()
            }
    }


    /// What the overlay stands on, and what it therefore cannot survive a change of.
    ///
    /// **Not the rows themselves.** A message arriving changes the discussion and takes nothing away from the lifted one, so what is watched is whether the row
    /// being lifted is *still there* — which stays true through every arrival and turns false exactly once: when the message is deleted, by its sender, for
    /// everyone, while the reader is holding it.
    private var whatTheOverlayStandsOn: WhatTheOverlayStandsOn {
        .init(horizontalSizeClass: horizontalSizeClass,
              verticalSizeClass: verticalSizeClass,
              theLiftedMessageIsStillInTheDiscussion: contextMenu.whatTheOverlayHasTaken.map { cellIdentifiers.contains($0.cellIdentifier) } ?? true)
    }


    private struct WhatTheOverlayStandsOn: Equatable {
        /// The geometry: a rotation, or a window resized on iPad. The copy is placed against a frame that no longer means anything.
        let horizontalSizeClass: UserInterfaceSizeClass?
        let verticalSizeClass: UserInterfaceSizeClass?
        /// Whether there is still a row for the copy to travel back to.
        let theLiftedMessageIsStillInTheDiscussion: Bool
    }

}
