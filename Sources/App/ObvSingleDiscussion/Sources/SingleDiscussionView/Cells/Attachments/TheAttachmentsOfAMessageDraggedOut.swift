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
import UniformTypeIdentifiers
import ObvSystemIcon


/// Every attachment of a message, dragged out of the discussion at once, as the legacy screen does it.
///
/// **UIKit, because SwiftUI cannot drag more than one thing.** `onDrag` returns a single `NSItemProvider` and `draggable(_:)` takes a single
/// value; several files need several `UIDragItem`s, which only a `UIDragInteraction` provides. This is the one file of the screen that must be
/// rewritten for AppKit; the drop beside it is pure SwiftUI.
///
/// **The interaction goes on the row's own cell**, which `swiftui-introspect` hands over. It has to be a view *containing* the message: an
/// overlay would take the taps that open an attachment, and a background would never be hit.
///
/// **One press, and the movement decides what it meant**. A touch drag and the context menu want the same press, and they share it:
/// `allowsSimultaneousRecognitionDuringLift`, without which this interaction is never even offered alongside the SwiftUI press that opens the menu. Hold still and
/// the menu opens; hold and move and the files come away, the menu standing aside because ``dragInteraction(_:sessionWillBegin:)`` says so. That is what UIKit's own
/// `UIContextMenuInteraction` does for itself, and what the legacy screen gets free.
///
/// **Where a finger drags, this draws no lift preview of its own** — see ``dragInteraction(_:previewForLifting:session:)``, which is the whole of what made the
/// shared press look wrong before.
struct TheAttachmentsOfAMessageDraggedOut: ViewModifier {

    /// What this message hands over. Empty for a message carrying no file, which then refuses the drag — as legacy does, its drag items coming
    /// from the attachments.
    let attachments: [MessageAttachment]

    let dataSource: any SingleDiscussionCellViewDataSource

    /// Which message this is, so that a drag beginning can tell the screen to put it back — see ``PressOnAMessage/draggedAway(_:)``.
    let cellIdentifier: SingleDiscussionView.CellIdentifier?

    /// What the transcript reads to know that it must refuse a drop — see ``TheDragOutOfTheDiscussion``. Nothing when this cell is drawn outside the screen, a
    /// preview having no transcript to protect.
    @Environment(\.theDragOutOfTheDiscussion) private var theDragOutOfTheDiscussion

    /// How the screen is told that this press became a drag, so the menu stands aside.
    @Environment(\.pressesOnMessages) private var pressesOnMessages

    /// Whether the reader is choosing messages, in which case this interaction stands down.
    ///
    /// **The one gesture on a cell that the screen's `allowsHitTesting` does not reach.** That rule takes the message's *content* out of hit testing, and this
    /// interaction is not in the content: it is UIKit's, installed on the row's own cell. So it is told, rather than silenced.
    @Environment(\.theReaderIsChoosingMessages) private var theReaderIsChoosingMessages

    /// An object rather than state: it is read from a UIKit callback, outside any SwiftUI update.
    @State private var whatIsDragged = WhatThisMessageHandsOver()

    func body(content: Content) -> some View {
        content
            // The platform list follows the versions the **screen** runs on — not the versions this interaction needs, which is every one of them. It
            // is a value rather than availability, so a version missing from it costs no error and no warning and simply never attaches the
            // interaction. It went to `.v17` and back within a week as the screen's minimum moved; move it whenever that moves. See the note on
            // ``TakesWhateverIsDroppedOnTheMessages``.
            .introspect(.listCell, on: .iOS(.v18, .v26, .v27)) { cell in
                whatIsDragged.nowShowing(attachments: attachments,
                                         dataSource: dataSource,
                                         saying: theDragOutOfTheDiscussion,
                                         andTelling: pressesOnMessages,
                                         about: cellIdentifier)
                whatIsDragged.installsItself(on: cell)
            }
            // **A `task(id:)` rather than the introspection above**, which would be the obvious place and cannot be trusted for this: that closure runs when
            // SwiftUI updates the representable, and whether an environment change alone brings it round again is not something to find out from a bug report.
            // This runs on appear and on every change of the value, which is exactly the contract wanted, and its body is one boolean write.
            .task(id: theReaderIsChoosingMessages) {
                whatIsDragged.maySlipAway(!theReaderIsChoosingMessages)
            }
    }

}


extension View {

    /// Lets every file this message carries be dragged out of the discussion, at once — see ``TheAttachmentsOfAMessageDraggedOut``.
    func attachmentsCanBeDraggedOutOfTheDiscussion(_ attachments: [MessageAttachment], cellIdentifier: SingleDiscussionView.CellIdentifier?, dataSource: any SingleDiscussionCellViewDataSource) -> some View {
        modifier(TheAttachmentsOfAMessageDraggedOut(attachments: attachments, dataSource: dataSource, cellIdentifier: cellIdentifier))
    }

}


/// Ours, so that a reused cell can be swept of this feature's interactions and of nothing else's.
///
/// The same device as ``APanThatRepliesToAMessage`` and for the same reason, which is that **an interaction on a cell cannot otherwise be told from anybody
/// else's**: a `List` is a `UICollectionView`, and both it and SwiftUI put interactions of their own on the views this reaches. Sweeping every
/// `UIDragInteraction` off a cell would take theirs with ours.
final class ADragOfTheAttachmentsOfAMessage: UIDragInteraction {}


/// What a cell hands over when it is dragged — see ``TheAttachmentsOfAMessageDraggedOut``.
@MainActor
final class WhatThisMessageHandsOver: NSObject {

    private var attachments: [MessageAttachment] = []
    private weak var dataSource: (any SingleDiscussionCellViewDataSource)?

    /// What is told that a drag is leaving this discussion, so that the transcript can refuse to take it back — see ``TheDragOutOfTheDiscussion``.
    private weak var theDragOutOfTheDiscussion: TheDragOutOfTheDiscussion?

    /// What is told that this press became a drag, so that the context menu stands aside.
    private weak var pressesOnMessages: PressesOnMessages?

    private var cellIdentifier: SingleDiscussionView.CellIdentifier?

    /// Kept so that a reused cell is not given a second interaction, which would drag everything twice.
    private weak var interaction: UIDragInteraction?

    /// Whether this message's files may be carried away at all — false while the reader is choosing messages, Step 42b.
    ///
    /// Remembered as well as applied, because a cell is reused: the interaction installed on the next cell has to be told the same thing, and the only place
    /// that knows it at that moment is here.
    private var mayBeDragged = true


    /// Points this object at the message the cell shows *now*, cells being reused as the reader scrolls, and at what it must tell when a drag leaves.
    func nowShowing(attachments: [MessageAttachment],
                    dataSource: any SingleDiscussionCellViewDataSource,
                    saying theDragOutOfTheDiscussion: TheDragOutOfTheDiscussion?,
                    andTelling pressesOnMessages: PressesOnMessages?,
                    about cellIdentifier: SingleDiscussionView.CellIdentifier?) {
        self.attachments = attachments
        self.dataSource = dataSource
        self.theDragOutOfTheDiscussion = theDragOutOfTheDiscussion
        self.pressesOnMessages = pressesOnMessages
        self.cellIdentifier = cellIdentifier
    }


    /// Puts the interaction on the row's own cell, and re-points it as cells are reused.
    func installsItself(on view: UIView) {
        guard interaction?.view !== view else { return }
        // **Two removals, and they cover different cells** — the same pair, for the same reason, as ``WhatASwipeToReplyAsksFor/installsItself(on:)``, where it was
        // measured. This one follows *this object* to whatever cell it was on before, which the sweep below cannot reach: that looks only at the cell being moved
        // to. On its own it is close to useless here, and for a reason that is worth stating rather than inferring — the object holding it is a `@State` of the
        // **row**, so a recycled cell is handed a *fresh* one whose `interaction` is nil and whose removal does nothing at all. Measured on an iPhone 13,
        // 2026-08-31, over 111 installs in a scroll: this branch was taken **0 times**, matching the swipe's 0 in 182.
        if let interaction { interaction.view?.removeInteraction(interaction) }
        // **And this one takes off every interaction this feature ever put on the cell being moved *to*.** That is the half that does the work: without it the
        // orphans of other rows stay on the cell and their number grows for as long as the reader scrolls.
        //
        // **What that costs was measured rather than reasoned, and it is the milder of the two harms** — which is worth saying because the first version of this
        // comment claimed the worse one, transcribing it from the swipe. `UIDragInteraction.delegate` is `weak`; an orphan whose owner is still held would point
        // at the message that cell *used* to show and hand over **its** files, which is the attachment form of the wrong-message reply. Over 264 installs on an
        // iPhone 13, 2026-08-31, that never once happened: an orphan was there on 241 of them and **every one of the 264 reported `stillLive=0`**, a released
        // owner and a nil delegate. So what this prevents is an unbounded pile of inert interactions on a reused cell, and not — on the evidence there is —
        // files served from the wrong message. The live-delegate state remains reachable in principle, SwiftUI being free to hold a row longer than its cell;
        // it has simply never been seen.
        let leftBehind = view.interactions.compactMap { $0 as? ADragOfTheAttachmentsOfAMessage }
        leftBehind.forEach { view.removeInteraction($0) }
        let interaction = ADragOfTheAttachmentsOfAMessage(delegate: self)
        // **Lets the press be felt by something else while this lifts**, and it defaults to `false`, which is why the SwiftUI press that opens the
        // context menu was never offered the touch at all rather than losing a fight for it. It matters on the cell, where the two share a press; on the lifted
        // copy nothing else is listening, and it costs nothing to say.
        interaction.allowsSimultaneousRecognitionDuringLift = true
        interaction.isEnabled = mayBeDragged
        view.addInteraction(interaction)
        self.interaction = interaction
    }


    /// Says whether the files of this message may be carried away — false while the reader is choosing messages, Step 42b.
    ///
    /// `isEnabled` rather than removing the interaction: a cell is reused, and an interaction taken off and put back is one more thing that can be put back
    /// twice. Switching it off leaves the arbitration of Step 41 exactly as it is for the moment the mode ends.
    func maySlipAway(_ mayBeDragged: Bool) {
        self.mayBeDragged = mayBeDragged
        interaction?.isEnabled = mayBeDragged
    }


}


// MARK: - UIDragInteractionDelegate

extension WhatThisMessageHandsOver: UIDragInteractionDelegate {

    /// One item per attachment, as `NewSingleDiscussionViewController.collectionView(_:itemsForBeginning:at:)` gives one per attachment of the
    /// message. An empty array refuses the drag.
    nonisolated func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: any UIDragSession) -> [UIDragItem] {
        MainActor.assumeIsolated {
            guard let dataSource else { return [] }
            return attachments.map { attachment in
                let item = UIDragItem(itemProvider: Self.itemProvider(for: attachment, dataSource: dataSource))
                item.previewProvider = Self.previewProvider(for: attachment, dataSource: dataSource)
                return item
            }
        }
    }


    /// The items rise as a pile under the reader's touch, each a little behind the one before it.
    ///
    /// **Where they are targeted is what makes several files read as several.** Untargeted, the previews land exactly on one another and look
    /// like a single picture; targeted at each attachment's own tile, they scatter, the tiles of a grid being far apart. A tilt per item was
    /// tried and does nothing: `UIDragPreviewTarget`'s transform does not reach the previews as they are carried.
    func dragInteraction(_ interaction: UIDragInteraction, previewForLifting item: UIDragItem, session: any UIDragSession) -> UITargetedDragPreview? {
        // **Where a finger drags, the pile is not drawn at all.** The same press opens the context menu, and UIKit's pre-lift raises these previews *before* the
        // overlay raises the message — one press showing two lifts, of two different things, which reads as a glitch. Answering nil gives the default preview, the
        // dragged view itself, so what rises is the message the overlay is about to lift rather than a stack of file icons beside it.
        //
        // A pointer keeps the pile: a press without movement is never a drag there, so nothing competes, and the pile is what tells a reader how many files they
        // are carrying — measured and tuned in 26b.
        guard Self.aPointerDragsHere else { return nil }
        guard let cell = interaction.view else { return nil }
        guard let preview = item.previewProvider?() else { return nil }
        let touch = session.location(in: cell)
        let rank = session.items.firstIndex(where: { $0 === item }) ?? 0
        let centre = CGPoint(x: touch.x + CGFloat(rank) * Self.gapBetweenTheItemsOfThePile,
                             y: touch.y + CGFloat(rank) * Self.gapBetweenTheItemsOfThePile)
        return UITargetedDragPreview(view: preview.view,
                                     parameters: preview.parameters,
                                     target: UIDragPreviewTarget(container: cell, center: centre))
    }


    /// Says that files are on their way out, which is what makes the transcript refuse a drop for as long as they are.
    ///
    /// The pair legacy has on its collection view's drag delegate, `dragSessionWillBegin` and `dragSessionDidEnd`. It exists to prevent one accident: a
    /// message's own attachments let go again over the discussion they came from, re-attaching to the draft what is already there. See
    /// ``TheDragOutOfTheDiscussion``.
    func dragInteraction(_ interaction: UIDragInteraction, sessionWillBegin session: any UIDragSession) {
        theDragOutOfTheDiscussion?.isInProgress = true
        // **The press that started this belonged to the context menu too, and the movement has just decided between them.** UIKit does this for itself when both
        // ends are its own; ours has to say so. See ``PressOnAMessage/draggedAway(_:)``.
        if let cellIdentifier { pressesOnMessages?.report(.draggedAway(cellIdentifier)) }
    }


    /// However it ended — dropped somewhere, refused, or cancelled — the discussion takes drops again.
    func dragInteraction(_ interaction: UIDragInteraction, session: any UIDragSession, didEndWith operation: UIDropOperation) {
        theDragOutOfTheDiscussion?.isInProgress = false
    }

}


// MARK: - What each item carries, and what it looks like

extension WhatThisMessageHandsOver {

    /// The file of one attachment: its name and type now, its bytes when something accepts the drop.
    ///
    /// **The type comes from the database and only the name from the file name**, which is what
    /// `NSItemProvider.init?(fyleElement:)` does on the legacy screen — `fyleElement.contentType.identifier`, the stored `uti`. Reading the *name* for
    /// both was this file's own bug: a name with no extension left nothing to derive a type from, the type fell back to `public.data`, which has no
    /// preferred extension for the system to append, and the file landed in the Finder called `9eea385b-…` and nothing else. See
    /// ``MessageAttachment/contentType`` and ``MessageAttachment/nameForAnotherApplication``.
    ///
    /// The bytes come from a hardlink, which is fetched asynchronously — hence the load handler, so a drag over a window that refuses it costs nothing.
    ///
    /// `Transferable` cannot do this: its representation is static, one per Swift type, so it can carry neither a name nor a type that varies by
    /// attachment. Declaring `public.data` produced files called `data`.
    static func itemProvider(for attachment: MessageAttachment, dataSource: any SingleDiscussionCellViewDataSource) -> NSItemProvider {

        let provider = NSItemProvider()
        provider.suggestedName = attachment.nameForAnotherApplication

        provider.registerFileRepresentation(forTypeIdentifier: attachment.contentType.identifier, fileOptions: [], visibility: .all) { completion in
            Task { @MainActor in
                do {
                    // Not coordinated: a hardlink is this app's own file, and nothing else writes to it.
                    completion(try await dataSource.getTheFileOfAnAttachment(attachment), false, nil)
                } catch {
                    // Nothing to give — still downloading, or the message has gone. Better refused than handed an empty file.
                    completion(nil, false, error)
                }
            }
            return nil
        }

        return provider

    }


    /// What one item looks like while it is carried: its own thumbnail, or an icon for an attachment that has none.
    ///
    /// **Whatever size has already been decoded**, since the cache is keyed on the exact size and 50 by 50 is one nothing here displays. Never a
    /// decode: a drag must not wait. The image is resolved now rather than in the closure, which is called outside any actor.
    static func previewProvider(for attachment: MessageAttachment, dataSource: any SingleDiscussionCellViewDataSource) -> () -> UIDragPreview? {
        // `UIImage` written directly, which new code otherwise must not do. A `UIDragPreview` is made of a
        // `UIView`, so this file is UIKit throughout and is rewritten for AppKit anyway.
        let thumbnail = dataSource.cachedImageOfAnySizeForAttachment(attachment)
        let image: UIImage? = thumbnail.map { UIImage(cgImage: $0) } ?? UIImage(systemIcon: .doc)
        return {
            let imageView = UIImageView(image: image)
            imageView.frame = CGRect(origin: .zero, size: Self.sizeOfAPreview(for: image))
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            return UIDragPreview(view: imageView)
        }
    }


    /// The picture's own proportions, its longest side held to `CellWithMessage.sizeForUIDragItemPreview`.
    private static func sizeOfAPreview(for image: UIImage?) -> CGSize {
        guard let image, image.size.width > 0, image.size.height > 0 else { return Self.sizeOfAPreview }
        let ratio = Self.sizeOfAPreview.width / max(image.size.width, image.size.height)
        return CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
    }


    /// `CellWithMessage.sizeForUIDragItemPreview`, unchanged.
    private static let sizeOfAPreview = CGSize(width: 50, height: 50)

    /// How far one item of the pile sits behind the one before it.
    private static let gapBetweenTheItemsOfThePile: CGFloat = 6

    /// Whether a drag here begins with a pointer, which cannot be confused with a press — see ``dragInteraction(_:previewForLifting:session:)``.
    fileprivate static var aPointerDragsHere: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

}
