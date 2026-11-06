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

import UIKit
import QuickLook
import ObvSingleDiscussion
import ObvUICoreData


/// Opens the attachments of a message for the SwiftUI discussion screen, and animates the opening out of the picture that was tapped.
///
/// **QuickLook is presented as a view controller, not wrapped in a SwiftUI representable**, and that is the whole design. Its dismissal — the picture shrinking
/// under the finger, turning, and flying back into place — belongs to `QLPreviewController` and exists only while it *is* the presented controller; wrapped in a
/// `.fullScreenCover` it is a child view with nothing to dismiss, and the gesture does nothing at all. Measured, both ways.
///
/// An `NSObject` because `QLPreviewControllerDelegate` requires one, and a type of its own for the same reason: the screen's actions have no business inheriting
/// from `NSObject` to satisfy QuickLook.
@MainActor
final class SwiftUISingleDiscussionAttachmentPresenter: NSObject {

    /// Weak, as everywhere on this screen: the SwiftUI view tree holds the actions strongly, and the actions hold this.
    weak var viewController: UIViewController?

    /// Where the attachments of this screen are drawn, written by the views that draw them and read here.
    let attachmentFrames = AttachmentFrames()

    /// The viewer while it is open, and nil the rest of the time. Held because nothing else does: it owns the fetched results controller the pages come from.
    private var filesViewer: FilesViewer?

    /// What the viewer flies out of, and back into: a view that is not the attachment's tile but looks like it, at the place the tile is.
    ///
    /// There is no `UIView` for a SwiftUI thumbnail and QuickLook animates a view, so one is made when the animation asks for it and destroyed when the viewer
    /// closes. The tile it stands for draws nothing meanwhile, or the reader would see the picture twice.
    private var standInForTheTile: UIView?

    /// The transcript's scroll view, and each tile's frame **in its content coordinates**, both taken before the viewer is presented — see the note where they
    /// are filled in. A stand-in placed here travels with the content, so the picture flies back to where its tile *is* rather than where it was.
    private weak var theScrollViewTheTilesLiveIn: UIScrollView?
    private var whereTheTilesWereInTheContent = [MessageAttachment.Identifier: CGRect]()

    /// Where the tiles were when the viewer opened, which is where they still are.
    ///
    /// **Read instead of ``attachmentFrames`` once the viewer is up**, because showing something full-screen takes the discussion out of the view hierarchy: every
    /// tile's `onDisappear` runs and the live registry empties, so asking it on the way out would find nothing to fly back into. The discussion cannot have moved
    /// in the meantime — it has been underneath the viewer the whole time.
    private var whereTheTilesWere = [MessageAttachment.Identifier: AttachmentOnScreen]()


    /// Opens an attachment, and every other attachment of its message beside it — a tap on one photograph opening a viewer over the whole message, as on the
    /// legacy screen.
    ///
    /// **`FilesViewer` is reused whole**, which is what makes this short: it owns the paging, loads a hardlink per item as that item is reached, and says which
    /// join is on screen. What is added here is only what the legacy screen adds — the notification that an attachment was opened, and the view the animation
    /// flies from.
    func userWantsToOpenAttachment(_ attachment: MessageAttachment) {

        guard case .objectID(let joinObjectID) = attachment.identifier else { assertionFailure(); return }
        guard let viewController else { assertionFailure(); return }

        // The view context, this being about what is on screen. A join that has gone since the model was built opens nothing.
        guard let join = try? ObvStack.shared.viewContext.existingObject(with: joinObjectID) as? FyleMessageJoinWithStatus else { return }
        guard let message = join.message else { return }

        // Every join of the message, and not the one tapped: what opens is a viewer the reader can swipe through.
        guard let frc = try? FyleMessageJoinWithStatus.getFetchedResultsControllerForAllJoinsWithinMessage(message) else { assertionFailure(); return }
        do {
            try frc.performFetch()
        } catch {
            assertionFailure()
            return
        }

        // Taken before anything is presented, while the tiles are still on screen to be seen. See ``whereTheTilesWere``.
        self.whereTheTilesWere = attachmentFrames.everythingOnScreen()

        // **And converted here, now, while nothing is scaled** — 2026-08-30, and the timing is the whole of it. A stand-in built at dismissal time by
        // `convert(_:from: nil)` picks up whatever transform the hierarchy carries *at that instant*, and a sheet scales its presenting view controller: measured
        // at **0.911** on an interactive dismissal caught mid-restore, so the stand-in came out 200pt asked for, 219.5pt built, and grew to 219.5 on screen as
        // the scale went back to 1. What the reader saw was a picture that landed too large and then shrank without an animation when it was removed.
        //
        // Converting *now* costs nothing and cannot go wrong: the viewer is not up, the presenter is not scaled, and the answer is in the scroll view's own
        // content coordinates, which do not move when the reader scrolls. The tile's frame relative to the content is a fact about the discussion rather than
        // about the moment it is asked for.
        if let scrollView = Self.looksForTheScrollView(under: viewController.view) {
            theScrollViewTheTilesLiveIn = scrollView
            whereTheTilesWereInTheContent = whereTheTilesWere.mapValues { scrollView.convert($0.frame, from: nil) }
        } else {
            theScrollViewTheTilesLiveIn = nil
            whereTheTilesWereInTheContent = [:]
        }

        let filesViewer = FilesViewer(frc: frc, qlPreviewControllerDelegate: self)
        self.filesViewer = filesViewer
        do {
            try filesViewer.tryToShowFyleMessageJoinWithStatus(join, within: viewController)
        } catch {
            // The join is not among the fetched ones, which can only mean it has just gone. Nothing is shown, and nothing is left behind.
            self.filesViewer = nil
        }

    }

}


// MARK: - FilesViewerPreviewDelegate

/// `@preconcurrency` because `QLPreviewControllerDelegate` promises nothing about isolation while this class is main-actor bound. Without it, a `@MainActor` type
/// conforming to it is a warning today and an error under the Swift 6 language mode.
extension SwiftUISingleDiscussionAttachmentPresenter: @preconcurrency FilesViewerPreviewDelegate {

    /// Says that a received attachment has been *seen*, which the rest of the app acts on — the same notification the legacy screen posts from the same place.
    ///
    /// Not cosmetic, and the reason a plain `quickLookPreview(_:)` modifier could never have done: only the viewer knows which item is on screen.
    func previewController(hasDisplayed joinID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) {
        ObvMessengerInternalNotification.userHasOpenedAReceivedAttachment(receivedFyleJoinID: joinID).postOnDispatchQueue()
    }


    /// The view the viewer flies out of, and back into.
    ///
    /// **Asked per item, and answered per item**, which is the whole of why the viewer is presented this way: the reader swipes to another attachment, dismisses,
    /// and the picture returns to *that* attachment's tile rather than to the one they tapped. Which attachment that is comes from the viewer itself rather than
    /// from the argument, exactly as the legacy screen reads it.
    ///
    /// Nil when the tile is not on screen — scrolled away while the viewer was open, or an attachment this screen draws no picture for. QuickLook then falls back
    /// to its own presentation, which is what the legacy screen does in the same case.
    func previewController(_ controller: QLPreviewController, transitionViewFor item: QLPreviewItem) -> UIView? {

        guard let join = filesViewer?.currentPreviewFyleMessageJoinWithStatus else { return nil }
        let identifier = MessageAttachment.Identifier.objectID(join.objectID)

        guard let shown = whereTheTilesWere[identifier], let host = viewController?.view, host.window != nil else {
            // Nothing to fly from, so nothing to hide either: a tile left invisible would be a hole in the discussion.
            attachmentFrames.attachmentBeingPresented = nil
            return nil
        }

        attachmentFrames.attachmentBeingPresented = identifier

        standInForTheTile?.removeFromSuperview()
        // **Inside the transcript's own scroll view, at a frame settled before the viewer went up** — 2026-08-30, and nothing is converted here, deliberately.
        //
        // `NewSingleDiscussionViewController` hands QuickLook `getAllShownHardLink()[i].viewShowingHardLink`: **the real, live view inside the cell**, a view in
        // the collection view's hierarchy, which therefore travels with the content for nothing. This screen cannot do that — its tile is SwiftUI and there is no
        // `UIView` to hand over — so it builds a stand-in. The whole history of this line is a series of attempts to put that stand-in somewhere that behaves
        // like legacy's cell, and only this one does.
        //
        // Adding it to the **window** was the first, and it is the whole of two defects: a window subview sits *above* the presented `QLPreviewController`, so
        // what should have been a picture flying out of the transcript was a picture lying over the viewer — over its close button, in the report that found it —
        // and QuickLook's own zoom had nothing in its own hierarchy to animate against, which is why a video appeared to get no transition at all while an image
        // seemed to work.
        //
        // See the note at `addSubview` below for why it is here rather than in the hosting view, and the one where ``whereTheTilesWereInTheContent`` is filled
        // in for why the frame is taken before the presentation rather than now.
        let whereItGoes: UIView = theScrollViewTheTilesLiveIn ?? host
        let itsFrame = whereTheTilesWereInTheContent[identifier] ?? host.convert(shown.frame, from: nil)
        let standIn = UIView(frame: itsFrame)
        // The picture goes onto the layer rather than into a `UIImageView`, which would want a `UIImage`: what the tile reported is a `CGImage`, and a layer takes
        // one directly.
        standIn.layer.contents = shown.picture
        standIn.layer.masksToBounds = true
        standIn.layer.cornerRadius = shown.cornerRadius
        standIn.layer.cornerCurve = .continuous
        standIn.layer.maskedCorners = Self.cornersToMask(shown.roundedCorners)
        switch shown.crop {
        case .centred:
            standIn.layer.contentsGravity = .resizeAspectFill
        case .fromTheTop:
            // There is no gravity for "fill, anchored to the top", so the part of the picture to show is chosen instead and stretched to the whole layer — which
            // comes to the same thing, the chosen part having the layer's proportions.
            standIn.layer.contentsGravity = .resize
            standIn.layer.contentsRect = Self.partOfThePictureShown(ofSize: shown.picture.map({ CGSize(width: $0.width, height: $0.height) }),
                                                                    inATileOfSize: shown.frame.size)
        }
        // **Inert, and that is the defect of 2026-08-27 rather than a precaution.** A stand-in is a picture of a tile; it exists to be looked at for the length of
        // a flight and has never had anything to answer. It is added to the *window*, above everything QuickLook draws — so while it was hit-testable it was a
        // decoration lying over the viewer's own controls, and the reader found it lying over the close button, which then could not be dismissed at all.
        //
        // **The third of this shape in one afternoon**, which is what makes it worth a comment rather than a line: the download control's disc had its hit area
        // only by accident of the material behind it, the progress arcs were hit-testable rings drawn over that control, and this. The rule is already known —
        // legacy's own snapshot and blur are both `isUserInteractionEnabled = false` so the touch reaches what is beneath them — and every one
        // of these was a decoration that had never been told it was one.
        standIn.isUserInteractionEnabled = false
        // **The fourth arrangement, and the first with a measurement behind it** — 2026-08-30. It went into the window, then into the hosting view (which warns
        // at runtime that *adding a `UIView` as a subview of `UIHostingController.view` is not supported*), and two of Apple's own remedies were built and both
        // broke the flight. All four of those moved the stand-in *sideways* in the hierarchy while leaving it somewhere that does not scroll — which is a defect
        // of its own: the picture flies back to where the tile was when the viewer opened, so a reader who scrolls during the flight watches it land where the
        // tile no longer is.
        //
        // **This puts it inside the scroll view the tiles themselves live in**, at that view's own coordinates, so it travels with the content for nothing. What
        // made it worth doing rather than guessing at is that **QuickLook tracks the transition view rather than snapshotting its frame** — established on
        // 2026-08-30 by walking the stand-in 4pt a frame during a dismissal and watching the picture follow it off the screen. Had it snapshotted, no parenting
        // could have helped and the only honest fix would have been to abandon the flight when the reader scrolls.
        //
        // Above the cells, because the real tile is hidden under it and a stand-in drawn behind them would be a hole.
        standIn.layer.zPosition = 1
        whereItGoes.addSubview(standIn)

        standInForTheTile = standIn

        return standIn

    }


    /// The scroll view the transcript's rows are drawn in, so that a view added to it travels with them.
    ///
    /// **Found by walking the hierarchy rather than asked of the module**, and deliberately: this is one view needed at one moment by one animation, where the
    /// alternative is a new hole in `SingleDiscussionView`'s interface for the app to reach through. The list is a `List`, which is a `UICollectionView` from
    /// iOS 16, and Step 26 already reaches the same object by introspection for its drop delegate.
    ///
    /// Nil is a real answer and the caller falls back to the hosting view — which is where this used to be, so the worst case is exactly the behaviour of the
    /// previous four arrangements.
    private static func looksForTheScrollView(under view: UIView) -> UIScrollView? {
        if let scrollView = view as? UICollectionView { return scrollView }
        for subview in view.subviews {
            if let found = looksForTheScrollView(under: subview) { return found }
        }
        return nil
    }


    /// The corners a tile rounds, as a layer expresses them.
    private static func cornersToMask(_ corners: AttachmentOnScreen.RoundedCorners) -> CACornerMask {
        var mask = CACornerMask()
        if corners.contains(.topLeft) { mask.insert(.layerMinXMinYCorner) }
        if corners.contains(.topRight) { mask.insert(.layerMaxXMinYCorner) }
        if corners.contains(.bottomLeft) { mask.insert(.layerMinXMaxYCorner) }
        if corners.contains(.bottomRight) { mask.insert(.layerMaxXMaxYCorner) }
        return mask
    }


    /// Which part of a picture a tile that crops from the top is showing, in the unit coordinates `contentsRect` wants — its origin being the picture's top left.
    ///
    /// The picture fills the tile's width and is cut off at the bottom, so what is shown is a band across the top whose height is the fraction of the picture that
    /// fits. A picture that is *wider* in proportion than the tile is cut equally on both sides instead, as filling always does.
    private static func partOfThePictureShown(ofSize picture: CGSize?, inATileOfSize tile: CGSize) -> CGRect {
        guard let picture, picture.width > 0, picture.height > 0, tile.width > 0, tile.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let heightShown = min(1, (tile.height * picture.width) / (tile.width * picture.height))
        let widthShown = min(1, (tile.width * picture.height) / (tile.height * picture.width))
        return CGRect(x: (1 - widthShown) / 2, y: 0, width: widthShown, height: heightShown)
    }


    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        standInForTheTile?.removeFromSuperview()
        standInForTheTile = nil
        attachmentFrames.attachmentBeingPresented = nil
        whereTheTilesWere = [:]
        whereTheTilesWereInTheContent = [:]
        theScrollViewTheTilesLiveIn = nil
        filesViewer = nil
    }

}
