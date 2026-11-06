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


/// Where the attachments of this screen are drawn, and which of them is on its way to or from the viewer.
///
/// **This exists so that a viewer can fly out of the right picture and back into it.** QuickLook animates from a
/// `UIView`, asked for *per item* so that the answer changes as the reader swipes — and this screen has no `UIView`
/// for an attachment, only a SwiftUI view. So each attachment says where it is drawn, in window coordinates, and
/// whoever presents the viewer looks that up and stands something there.
///
/// **The frames are deliberately not published.** They change on every frame of a scroll, and a discussion redrawing
/// itself because a picture moved would be absurd. Nothing in SwiftUI reads them: they are written by the views and
/// read by the app, at the two moments that matter — a viewer opening, and a viewer closing. Only
/// ``attachmentBeingPresented`` is observed, and it changes twice per presentation.
///
/// `@unchecked Sendable` is the price of that: the frames are written from SwiftUI's preference machinery, which
/// promises nothing about where it runs, so they live behind a lock. ``attachmentBeingPresented`` is main-actor by
/// convention — it is set by whoever presents the viewer, which is a view controller.
public final class AttachmentFrames: ObservableObject, @unchecked Sendable {

    /// The attachment currently flying to or from the viewer, whose own tile therefore draws nothing: the picture the
    /// reader sees moving is a stand-in placed over it, and both at once would be one picture too many.
    @Published public var attachmentBeingPresented: MessageAttachment.Identifier?

    private let lock = NSLock()
    private var onScreen = [MessageAttachment.Identifier: AttachmentOnScreen]()

    public init() {}

    /// What an attachment currently looks like on this screen, or nil, which **withdraws** it.
    ///
    /// Withdrawing matters as much as reporting: an attachment scrolled out of sight has nowhere to fly back to, and a
    /// frame left behind would send the animation to a rectangle with nothing in it.
    nonisolated public func attachment(_ identifier: MessageAttachment.Identifier, isOnScreenAs shown: AttachmentOnScreen?) {
        lock.lock()
        defer { lock.unlock() }
        if let shown {
            onScreen[identifier] = shown
        } else {
            onScreen.removeValue(forKey: identifier)
        }
    }

    /// What an attachment looks like on this screen, and nil for one that is not on it at all.
    nonisolated public func attachment(_ identifier: MessageAttachment.Identifier) -> AttachmentOnScreen? {
        lock.lock()
        defer { lock.unlock() }
        return onScreen[identifier]
    }

    /// Everything on screen, as it is now.
    ///
    /// **For whoever is about to cover this screen.** Showing something full-screen takes the discussion out of the
    /// view hierarchy, which runs every tile's `onDisappear` and empties this — so a viewer that asked again on its
    /// way out would find nothing to fly back into. What it needs is what was there when it opened, and the list
    /// cannot have moved since: it has been underneath something the whole time.
    nonisolated public func everythingOnScreen() -> [MessageAttachment.Identifier: AttachmentOnScreen] {
        lock.lock()
        defer { lock.unlock() }
        return onScreen
    }

}


/// An attachment as it is drawn: where, and with what in it.
///
/// **The picture travels with the frame**, rather than being fetched again when the viewer opens, because the tile
/// showing it has the right one already — decoded at the very size it is drawn at. Asking the cache for it a second
/// time would mean reconstructing the pixel size the tile happened to ask for, and getting nothing on a miss.
public struct AttachmentOnScreen: Equatable, @unchecked Sendable {

    /// In the coordinate space of the window.
    public let frame: CGRect

    /// What is drawn in it, and nil for a tile still showing its placeholder.
    public let picture: CGImage?

    /// The tile's own rounding, so that what flies is not a square where a rounded thing was — seen as the corners snapping round at the very end of the
    /// animation, when the real tile came back.
    public let cornerRadius: CGFloat

    /// Which corners that radius applies to.
    ///
    /// **Not always all four**, because on this screen the rounding usually belongs to a *group* rather than to the thing inside it: a document preview is round
    /// at the top and nearly square where it meets its labels, and a card's thumbnail is round only on the side that touches the edge of the stack of cards. The
    /// corners are named left and right rather than leading and trailing, that being what a layer understands; a view that mirrors resolves them before reporting.
    public let roundedCorners: RoundedCorners

    public struct RoundedCorners: OptionSet, Hashable, Sendable {

        public let rawValue: Int

        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let topLeft = RoundedCorners(rawValue: 1 << 0)
        public static let topRight = RoundedCorners(rawValue: 1 << 1)
        public static let bottomLeft = RoundedCorners(rawValue: 1 << 2)
        public static let bottomRight = RoundedCorners(rawValue: 1 << 3)

        public static let all: RoundedCorners = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        public static let top: RoundedCorners = [.topLeft, .topRight]
        public static let left: RoundedCorners = [.topLeft, .bottomLeft]
        public static let right: RoundedCorners = [.topRight, .bottomRight]

    }

    /// Which part of the picture the tile shows, when the picture does not have the tile's proportions.
    public let crop: Crop

    /// How a picture too big for its tile is cut down.
    ///
    /// Almost everything on this screen fills and centres. A **document preview does not**: it shows the top of the first page and cuts off whatever does not
    /// fit — `cropBottom(mandatoryWidth:maxHeight:)` on the legacy screen — so a stand-in that centred showed the middle of the page flying back into a tile
    /// showing its top.
    public enum Crop: Equatable, Sendable {
        case centred
        case fromTheTop
    }

    public init(frame: CGRect, picture: CGImage?, cornerRadius: CGFloat, roundedCorners: RoundedCorners, crop: Crop) {
        self.frame = frame
        self.picture = picture
        self.cornerRadius = cornerRadius
        self.roundedCorners = roundedCorners
        self.crop = crop
    }

    /// The picture is compared by identity: it is immutable, and a new one is a different object.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.frame == rhs.frame && lhs.picture === rhs.picture && lhs.cornerRadius == rhs.cornerRadius
            && lhs.roundedCorners == rhs.roundedCorners && lhs.crop == rhs.crop
    }

}


// MARK: - What a tile reads to know whether it is the one flying

extension EnvironmentValues {

    /// The attachment currently flying to or from the viewer, mirrored out of ``AttachmentFrames`` by the screen.
    ///
    /// An environment *value* rather than the object itself, so that only the root of the screen observes the object
    /// and a tile is invalidated by the one thing it cares about — this is a `List`, and a discussion has a great many
    /// tiles.
    public var attachmentBeingPresented: MessageAttachment.Identifier? {
        get { self[AttachmentBeingPresentedKey.self] }
        set { self[AttachmentBeingPresentedKey.self] = newValue }
    }

}


private struct AttachmentBeingPresentedKey: EnvironmentKey {
    static let defaultValue: MessageAttachment.Identifier? = nil
}


// MARK: - Making an attachment a way in and out of the viewer

/// The tap, which is one rectangle.
private struct OpensTheAttachmentViewer: ViewModifier {

    let attachment: MessageAttachment
    let phase: AttachmentState.Phase?
    let actions: any SingleDiscussionCellViewActions

    @Environment(\.attachmentsAreCoveredUntilRead) private var isCovered

    /// Whether tapping this opens the viewer.
    ///
    /// The file has to be here — there is nothing to preview otherwise, and the legacy screen gives that tap to the
    /// download control instead, which ours does by construction: the control is drawn as an *overlay above* the
    /// content, and SwiftUI hit-tests front to back, so it wins its own area without anything having to arbitrate.
    /// And a message the reader has not asked to see opens nothing: it reveals itself, which
    /// ``MessageTapToReadView`` arranges for the whole cell — asked again here because a guard that matters this much
    /// should be stated where it applies.
    private var opens: Bool {
        !isCovered && phase == .available
    }

    func body(content: Content) -> some View {
        content
            // The whole of it, and not only what is drawn in it: a picture that has not arrived leaves its box empty,
            // and an empty box must still be tappable once the file is there.
            .contentShape(Rectangle())
            .onTapGesture {
                guard opens else { return }
                Task { await actions.userWantsToOpenAttachment(attachment) }
            }
    }

}


/// Where the viewer flies from and back to, which is not always the same rectangle as the tap — see the two modifiers below.
private struct TheAttachmentViewerFliesFromHere: ViewModifier {

    let attachment: MessageAttachment

    /// What is drawn here, so that the stand-in the viewer flies is the same picture rather than a guess at it.
    let picture: CGImage?

    let cornerRadius: CGFloat
    let roundedCorners: AttachmentOnScreen.RoundedCorners
    let crop: AttachmentOnScreen.Crop

    let frames: AttachmentFrames

    @Environment(\.attachmentBeingPresented) private var attachmentBeingPresented

    private var howItLooks: (CGRect) -> AttachmentOnScreen {
        { frame in .init(frame: frame, picture: picture, cornerRadius: cornerRadius, roundedCorners: roundedCorners, crop: crop) }
    }

    func body(content: Content) -> some View {
        content
            // Says where it is and what is in it, for as long as it is anywhere. Reported through a preference rather
            // than watched with `onGeometryChange`, which is iOS 18 and this screen is iOS 16. The picture rides along
            // so that a picture arriving after the layout settled is still noticed: the value changes, so the
            // preference does.
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: AttachmentFramePreference.self,
                                    value: [attachment.identifier: howItLooks(proxy.frame(in: .global))])
                        // **Said again on every appearance, and not only when it changes.** A preference is delivered when its *value* changes, and coming back
                        // from something shown over this screen changes nothing: the tile is where it was, holding the picture it held. So the withdrawal below
                        // would stand and nothing would ever put it back — the viewer opened once with a flight and every time after that without one, until the
                        // row was scrolled away and rebuilt. Reported from inside the reader, where the geometry is in hand and no state has to remember it.
                        .onAppear {
                            frames.attachment(identifier, isOnScreenAs: howItLooks(proxy.frame(in: .global)))
                        }
                }
            }
            .onPreferenceChange(AttachmentFramePreference.self) { reported in
                guard let shown = reported[identifier] else { return }
                frames.attachment(identifier, isOnScreenAs: shown)
            }
            // Withdrawn when the tile goes, so that nothing flies back to where it used to be. This runs when the screen is merely *covered* as well, which is why
            // the appearance above has to put it back — and why the presenter works from a snapshot taken before it covered anything.
            .onDisappear {
                frames.attachment(identifier, isOnScreenAs: nil)
            }
            // Nothing while a stand-in is flying in its place. See ``AttachmentFrames/attachmentBeingPresented``.
            .opacity(attachmentBeingPresented == identifier ? 0 : 1)
    }

    /// Captured out of the attachment so that the closures above hold a value rather than the whole of it — `onPreferenceChange` takes a `@Sendable` closure.
    private var identifier: MessageAttachment.Identifier { attachment.identifier }

}


private struct AttachmentFramePreference: PreferenceKey {
    static let defaultValue = [MessageAttachment.Identifier: AttachmentOnScreen]()
    static func reduce(value: inout [MessageAttachment.Identifier: AttachmentOnScreen], nextValue: () -> [MessageAttachment.Identifier: AttachmentOnScreen]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}


extension View {

    /// A tap here opens this attachment, and every other attachment of its message beside it.
    ///
    /// Applied where the phase is known, and **beneath the state control**, which `FollowedAttachment` draws as an
    /// overlay above its content — which is what gives a file still on its way the right behaviour without a
    /// precedence being written anywhere.
    ///
    /// Not every attachment is openable: an audio player is not, tapping it plays; an animated image is not, the
    /// legacy screen having no way into a viewer from a GIF either. Those views simply do not apply this.
    func opensTheAttachmentViewer(_ attachment: MessageAttachment,
                                  phase: AttachmentState.Phase?,
                                  actions: any SingleDiscussionCellViewActions) -> some View {
        modifier(OpensTheAttachmentViewer(attachment: attachment, phase: phase, actions: actions))
    }

    /// This is the picture the viewer flies out of, and back into: it says where it is drawn, and draws nothing while a
    /// stand-in is flying in its place.
    ///
    /// **Not always the same view as the one that takes the tap.** On a card, the legacy screen accepts a tap anywhere
    /// in the card — `SingleAttachmentView` asks its subviews with `acceptTapOutsideBounds: true` — while
    /// `getAllShownHardLink()` hands back the *thumbnail* alone. Two rectangles for two jobs, which is why these are
    /// two modifiers.
    /// `cornerRadius` and `crop` are what the stand-in needs to be mistaken for the tile: everything on this screen fills
    /// and centres its picture except a document preview, which shows the top of a page, and a tile that is rounded must
    /// not fly as a square.
    func theAttachmentViewerFliesFromHere(_ attachment: MessageAttachment,
                                          showing picture: CGImage?,
                                          cornerRadius: CGFloat = 0,
                                          roundedCorners: AttachmentOnScreen.RoundedCorners = .all,
                                          crop: AttachmentOnScreen.Crop = .centred,
                                          actions: any SingleDiscussionCellViewActions) -> some View {
        modifier(TheAttachmentViewerFliesFromHere(attachment: attachment,
                                                  picture: picture,
                                                  cornerRadius: cornerRadius,
                                                  roundedCorners: roundedCorners,
                                                  crop: crop,
                                                  frames: actions.attachmentFrames))
    }

}
