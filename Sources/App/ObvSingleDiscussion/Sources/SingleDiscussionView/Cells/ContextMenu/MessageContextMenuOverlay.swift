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


/// Everything the reader sees while a message is lifted: the backdrop over the discussion, a copy of the message drawn on top of it, and the card of what that
/// message offers.
///
/// **Nothing here is a context menu.** `.contextMenu` lifts the whole row on an opaque, full-width platter — wherever the modifier is attached and whatever the
/// row's background — which is not what this screen draws and not what the legacy one draws either. Four arrangements were tried before this was written; the
/// screenshots are in the plan. So the screen owns the backdrop, the copy and the card together, and nothing is left to the system to place.
///
/// **The copy is live, and it is a second rendering rather than a picture.** A snapshot freezes whatever is animating — a GIF above all — for as long as the menu
/// is open. The live copy has an artefact of its own, recorded rather than hidden: `AnimatedImageFrames.stream` starts a new detached task per consumer, from
/// frame 0, so a lifted GIF restarts rather than continuing. The fix is named in the plan and needs nothing here to change.
///
/// **Room is left above the message for the reaction bar of Step 22a**, which is why a message near the top of the screen moves further down than the card alone
/// would require. Drawing the bar is that sub-step's; reserving its space is this one's, so that adding it later moves nothing.
///
/// **A message taller than the screen is scaled down rather than allowed to push the menu off it.** See the note above *Where everything goes*, which has the
/// measurements and says why this does not overlap where the legacy screen does.
struct MessageContextMenuOverlay: View {

    /// What the lifted message is, which is what the copy is drawn from. Read from the data source's cache at press time — the same seed a cell is created with —
    /// so the copy paints on its first frame rather than as a skeleton.
    let model: SingleDiscussionCellView.Model

    /// What this message offers, asked of the data source when the press was recognised. Never empty: a message offering nothing is never lifted.
    let offers: WhatAMessageOffers

    /// What the reader may react with — see ``TheEmojisOnOffer``. Read, but drawn only when ``WhatAMessageOffers/offersToReact``
    /// says this message may be reacted to at all.
    let emojis: TheEmojisOnOffer

    /// Where the real message is, resolved from its anchor in this overlay's own space.
    let whereTheMessageIs: CGRect

    /// The space this overlay has to place things in.
    let within: CGSize

    /// The one thing the eye ever sees move. Everything else — hiding the real message, placing the copy over it — has already happened, invisibly and without
    /// animation, before this is set.
    let appeared: Bool

    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    /// **What was chosen, and where this overlay's copy stands as it is chosen**. The second half is carried with *every* action rather than with
    /// *Reply* alone: whether an entry wants the copy handed over is the screen's business, and an overlay that knew Reply was special would be deciding one
    /// view removed. See ``TheCopyTheMenuHandsOver``.
    let chose: (MessageAction, TheCopyTheMenuHandsOver) -> Void
    let dismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How tall one entry of the card is, at the reader's text size. `@ScaledMetric` rather than a measurement, deliberately: measuring the card would write state
    /// while the lift is animating, and the position would then be corrected a frame late — a second, smaller movement, plainly visible.
    @ScaledMetric(relativeTo: .body) private var heightOfAnEntry: CGFloat = 44

    private var side: TheSideAMessageHangsFrom { model.theSideItHangsFrom }

    var body: some View {
        ZStack(alignment: .topLeading) {

            backdrop

            // In the space kept for it since 21b, aligned to its bottom so that it sits `gap` above the message however
            // tall it turns out to be — the one metric that decides this is ``roomLeftAboveForTheReactionBar``.
            //
            // A `Group`, so that a message which may not be reacted to contributes no subview here at all.
            Group {
                if offers.offersToReact {
                    TheFavouriteEmojisBar(emojis: emojis,
                                          side: side,
                                          appeared: appeared,
                                          chose: { emoji in chose(.reactWith(emoji: emoji), theCopyAsItStands) },
                                          wantsTheWholePicker: { chose(.react, theCopyAsItStands) })
                }
            }
            .frame(width: whereTheMessageIs.width, height: Self.roomLeftAboveForTheReactionBar, alignment: side.whereTheBarSits)
            .offset(x: whereTheMessageIs.minX, y: whereTheMessage.y - Self.gap - Self.roomLeftAboveForTheReactionBar)

            theCopyOfTheMessage
                .frame(width: whereTheMessageIs.width, height: whereTheMessageIs.height, alignment: side.alignment)
                // Up a little as it rises, or **down** when the message is taller than the band leaves room for. About the top of the near edge, so that the corner
                // this is placed by does not move whatever the scale — see ``TheSideAMessageHangsFrom/topOfTheNearEdge``.
                .scaleEffect(scaleOfTheCopy, anchor: side.topOfTheNearEdge)
                // Named rather than written out: the composition bar's treatment takes this very copy over, in one frame with animations disabled, so a shadow
                // the two ends disagree about is a shadow seen to snap. See ``TheShadowAHeldMessageCasts``. `.none` until the copy has appeared, so the shadow
                // rises with the message.
                .casts(appeared ? .whileLiftedByTheMenu : .none)
                .offset(x: whereTheMessageIs.minX, y: whereTheMessage.y)
                // Inert. The reader is choosing from the card now, and a tap that reached the copy would play a recording or open a photograph from behind the
                // backdrop — while a tap that falls through to the backdrop puts the message back, which is what a tap on a lifted message should do.
                .allowsHitTesting(false)

            MessageContextMenuCard(offers: offers, rowHeight: heightOfAnEntry, height: heightOfTheCard, chose: { chose($0, theCopyAsItStands) })
                // Lined up with the near edge of the message, within the width the message occupies — which for a bubble is the edge it hangs from.
                .frame(width: whereTheMessageIs.width, alignment: side.alignment)
                // **Scaled before it is offset, and that order is the whole of it.** `offset` moves what is drawn and not
                // the layout frame, so a `scaleEffect` applied *after* it resolves its anchor against the frame's
                // un-offset position — near the top of the overlay. The card then grew out of a point far above itself,
                // the more visibly the further down the screen it sat, which is where it was noticed. The lifted copy has
                // always had this order, which is why the lift never showed the fault.
                .scaleEffect(appeared ? 1 : 0.3, anchor: side.topOfTheNearEdge)
                .opacity(appeared ? 1 : 0)
                .offset(x: whereTheMessageIs.minX, y: whereTheCardGoes)

        }
        // Nothing behind this exists for VoiceOver while it is up, and the escape gesture puts the message back.
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, dismiss)
    }


    /// What separates the lifted message from the discussion it came out of.
    ///
    /// **Lighter from iOS 26**, because the card and the bar are glass there and glass takes its tint from what is behind it: over `.regularMaterial`, which
    /// washes the discussion to an even off-white, the glass has nothing to refract and reads as a white card. `.ultraThinMaterial` still separates the lifted
    /// message from the rest, and lets the colours of the discussion through for the glass to pick up.
    private var backdrop: some View {
        Rectangle()
            .fill(theMaterialOfTheBackdrop)
            .ignoresSafeArea()
            .opacity(appeared ? 1 : 0)
            .onTapGesture { dismiss() }
            // Dragging anywhere on the backdrop puts the message back, as it does in Messages.
            .gesture(DragGesture(minimumDistance: 20).onEnded { _ in dismiss() })
    }


    private var theMaterialOfTheBackdrop: Material {
        if #available(iOS 26.0, *) {
            return .ultraThinMaterial
        } else {
            return .regularMaterial
        }
    }


    /// The message, drawn a second time.
    ///
    /// **The very same views the cell draws**, and that is the whole reason each kind of cell exposes its content as a view of its own: two renderings of one
    /// definition cannot drift apart, where a copy written here would drift the first time a bubble changed.
    @ViewBuilder
    private var theCopyOfTheMessage: some View {
        Group {
            switch model {
            case .sentMessage(let model):
                SentMessageCellView.MessageItself(model: model, dataSource: dataSource, actions: actions)
            case .receivedMessage(let model):
                ReceivedMessageCellView.MessageItself(model: model, dataSource: dataSource, actions: actions)
            case .systemMessage(let model):
                SystemMessageCellView.MessageItself(model: model)
            }
        }
    }


    // MARK: Where everything goes
    //
    // **Everything below divides one band between two things, and the message is what gives way.** The band runs from under the room kept for the reaction bar to
    // the bottom margin; the card takes what it wants of it, up to a share; the message gets the rest and is *scaled down* if it does not fit.
    //
    // The first arrangement did not scale anything: it clamped the message to the top of the band and placed the card under it wherever that fell. For a message
    // taller than the band that is off the bottom of the screen — measured on an iPhone 16 Pro, a 700pt message put the card 112pt past the bottom edge and a
    // 1200pt one put it out of sight altogether, so a long message offered no menu at all. The comment then claimed the message was "allowed to overflow the card
    // rather than to overlap it", which was a way of saying the menu had been pushed off the screen.
    //
    // The legacy screen shrinks its preview to fit and lets the menu overlap it. Scaling makes the overlap unnecessary: the card's share is taken out of the
    // message's allowance *before* the scale is computed, so both fit whole and neither is covered. What overlapping would buy is the card's height back for the
    // message — on the sizes where any of this matters, the difference between a scale of 0.14 and one of 0.10, which is a smudge either way.


    /// Where the copy of the message sits: exactly where the real one is until ``appeared``, and then wherever there is room for what goes above and below it.
    private var whereTheMessage: CGPoint {
        appeared ? whereTheMessageEndsUp : whereTheMessageIs.origin
    }


    /// The place the message is lifted to.
    ///
    /// **Its own place, whenever that works** — which is the common case, and is what makes the lift read as the message staying still while everything else
    /// recedes. It moves only when what has to be placed around it would otherwise fall off the screen: down, when there is no room above for the reaction bar to
    /// come; up, when the card below would not fit. A message that has had to be scaled ends up at the top of the band, there being nowhere else for it to go.
    private var whereTheMessageEndsUp: CGPoint {
        let highestItMayGo = topOfTheBand
        let lowestItMayGo = within.height - Self.margin - heightOfTheCard - Self.gap - heightOfTheMessageWhenItIsUp
        let y = min(max(whereTheMessageIs.minY, highestItMayGo), max(highestItMayGo, lowestItMayGo))
        return CGPoint(x: whereTheMessageIs.minX, y: y)
    }


    /// Where the card is drawn: under the message, at whatever height the message has *once it is up* — which is not the height it has in the transcript when it
    /// has had to be scaled.
    private var whereTheCardGoes: CGFloat {
        whereTheMessage.y + (appeared ? heightOfTheMessageWhenItIsUp : whereTheMessageIs.height) + Self.gap
    }


    /// Where this overlay's copy stands, for whoever takes the message next.
    ///
    /// **A displacement from the anchor and not a frame**, because the treatment that receives it does not share this one's coordinate space: its modifier is
    /// applied before the composition bar goes into the safe area and this one's after. Both resolve the same anchor, so the anchor is what the two of them can
    /// agree in. See ``TheCopyTheMenuHandsOver``.
    private var theCopyAsItStands: TheCopyTheMenuHandsOver {
        .init(carriedBy: whereTheMessage.y - whereTheMessageIs.minY, scale: scaleOfTheCopy)
    }


    /// How much the copy is scaled. **One** at rest, so the swap at the beginning and the end of the gesture cannot be seen: the copy is placed at exactly the
    /// frame the real message had, at exactly its size.
    private var scaleOfTheCopy: CGFloat {
        appeared ? scaleOfTheCopyWhenItIsUp : 1
    }


    /// Down to fit when the message is taller than the band leaves room for, and otherwise the small growth that says it has left the page.
    ///
    /// The two are one number because they are one `scaleEffect`, and because they never both apply: a message being shrunk to fit has no business also growing 4%.
    private var scaleOfTheCopyWhenItIsUp: CGFloat {
        guard whereTheMessageIs.height > 0 else { return 1 }
        let scaleThatWouldMakeItFit = heightLeftForTheMessage / whereTheMessageIs.height
        guard scaleThatWouldMakeItFit < 1 else { return reduceMotion ? 1 : Self.howMuchALiftedMessageGrows }
        return scaleThatWouldMakeItFit
    }


    private var heightOfTheMessageWhenItIsUp: CGFloat {
        whereTheMessageIs.height * scaleOfTheCopyWhenItIsUp
    }


    /// The band everything is placed in: from under the room kept for the reaction bar, down to the bottom margin.
    private var topOfTheBand: CGFloat {
        Self.margin + Self.roomLeftAboveForTheReactionBar + Self.gap
    }

    private var heightOfTheBand: CGFloat {
        max(0, within.height - Self.margin - topOfTheBand)
    }


    /// How tall the card is: what it wants, and never more than what is left of the band once the message has taken what it **needs**.
    ///
    /// **The share is a floor under the message, not a ceiling over the card, and that is the whole of this.** It used to be the other way round — the card took
    /// what it wanted up to 55% of the band — and the fault that hid in it is that a share of the *band* is not a share of anything the message asked for. A
    /// one-line bubble is 44pt tall and was being given a 288pt allowance, of which it used 44; the rest became air above the reaction bar, while the card was
    /// clipped by more than two entries. Computed over the four overlay heights this screen meets, an eleven-entry menu at the ordinary text size:
    ///
    /// | overlay | band | card wants | card got | entries shown | band left empty |
    /// |---|---|---|---|---|---|
    /// | 700 | 614 | 484 | 337.7 | 7.68 | **222** |
    /// | 749 | 663 | 484 | 364.7 | 8.29 | **244** |
    /// | 800 | 714 | 484 | 392.7 | 8.93 | **267** |
    /// | 900 | 814 | 528 | 447.7 | 10.18 | **312** |
    ///
    /// Two hundred points of the band stood empty while `Delete` — last of the entries — sat below the fold. **The report was that readers do not realise the
    /// menu scrolls; the answer is that mostly it did not need to.** Asking what the message *needs* rather than what its share comes to gives the card its full
    /// 484 in every row of that table, with the message untouched at 44.
    ///
    /// A message that genuinely wants more than its share still gets it, and the card still scrolls — which it can and the message cannot. Both floors are the
    /// ones that were always here: a card is never smaller than about four entries, and the message keeps ``leastTheMessageIsGiven`` whatever the card wants. The
    /// second is a guard rather than a case, and what it prevents is a message scaled to nothing, which is worse than any menu.
    private var heightOfTheCard: CGFloat {

        let wanted = MessageContextMenuCard.heightWanted(by: offers, rowHeight: heightOfAnEntry)

        // Never less than about four entries, and never so much that the message is left below its own floor. The order matters: the message's floor is applied
        // second, so it holds whatever the card's does.
        let mostItMayHave = max(0, min(max(Self.leastTheCardIsGiven, heightOfTheBand - Self.gap - whatTheMessageNeeds),
                                       heightOfTheBand - Self.gap - Self.leastTheMessageIsGiven))

        guard wanted > mostItMayHave else { return wanted }

        // **Stretched to what it wants when the shortfall is less than one entry**, measured on an iPhone 13 on 2026-08-30 and kept: an eight-entry menu wanting
        // 352 was cut by **9.35pt**, which hides no entry, reveals nothing when scrolled, and does nothing but clip the last row and put an indicator beside it.
        // A scroll worth having reveals at least one thing the reader can tap. The message's floor is consulted again rather than trusted, so the stretch cannot
        // reach past it — where it would, the cut below is taken instead.
        let asMuchAsCanBeSpared = max(0, heightOfTheBand - Self.gap - Self.leastTheMessageIsGiven)
        if wanted - mostItMayHave < heightOfAnEntry, wanted <= asMuchAsCanBeSpared { return wanted }

        // Cut below the air the card keeps above its first entry, so that the half entry is half of an *entry* and not of an entry shifted by that air.
        let inset = MessageContextMenuCard.verticalInset
        return Self.cutOnAHalfEntry(mostItMayHave - inset, rowHeight: heightOfAnEntry) + inset
    }


    /// What the message needs of the band: its own height, and never more than its share.
    ///
    /// **Its own height is the term that was missing**, and it is what makes the share cost nothing in the common case — a bubble asks for 44pt and is given 44pt,
    /// so the whole of the rest is the card's. The share binds only a message tall enough to want it, which is the one case where dividing the band is a real
    /// question. See ``heightOfTheCard``.
    private var whatTheMessageNeeds: CGFloat {
        min(whereTheMessageIs.height, max(Self.leastTheMessageIsGiven, heightOfTheBand * Self.theShareOfTheBandTheMessageKeeps))
    }


    /// Where a card that cannot show everything is cut: through the **middle of an entry**, always.
    ///
    /// **A card cut anywhere else looks finished, and that is why readers were not scrolling it.** The share left the 800pt case with 392.7pt of a 44pt-per-entry
    /// menu — **8.93 entries**, so the ninth showed 41 of its 44 points and read as a complete row with nothing under it. The cue was not weak, it was
    /// misleading. A half entry cannot be read as anything but a list that continues, and it is what iOS's own scrolling menus show.
    ///
    /// It cuts *down*, never up, so the message keeps whatever the rounding gives back. Below one and a half entries there is nothing to round to and the height
    /// is returned as it stands — a card that small has worse problems than its bottom edge.
    private static func cutOnAHalfEntry(_ height: CGFloat, rowHeight: CGFloat) -> CGFloat {
        guard rowHeight > 0 else { return height }
        let wholeEntriesAboveTheHalf = ((height - rowHeight / 2) / rowHeight).rounded(.down)
        guard wholeEntriesAboveTheHalf >= 1 else { return height }
        return wholeEntriesAboveTheHalf * rowHeight + rowHeight / 2
    }


    /// What is left of the band for the message once the card and the air between them are placed. The message is scaled to this when it does not already fit.
    private var heightLeftForTheMessage: CGFloat {
        max(0, heightOfTheBand - Self.gap - heightOfTheCard)
    }


    /// The air between the message and what is drawn above and below it.
    private static let gap: CGFloat = 10

    /// The air kept between all of it and the edges of the screen.
    private static let margin: CGFloat = 12

    /// Kept clear above the lifted message for the bar of favourite emojis of Step 22a. Reserved now so that drawing it later moves nothing.
    ///
    /// **56, up from 52, when the bar's insets grew** — some 50pt with its emojis at 30pt, so a little to spare. A bar taller than this overflows upward rather than moving anything, so the
    /// number only matters near the top of the screen — where it decides whether the bar is pushed into the margin.
    private static let roomLeftAboveForTheReactionBar: CGFloat = 56

    /// See ``whatTheMessageNeeds``. Rather less than half, a menu being the thing the reader pressed for — the complement of the 0.55 the card used to be capped
    /// at, so that a message tall enough to be bound by this is divided from the card as it was before, to within two terms it is worth naming rather than
    /// rounding away: the card is now charged the ``gap`` the message used to be charged, and gives back up to one entry to ``cutOnAHalfEntry(_:rowHeight:)``.
    /// Both come out of a card that was scrolling either way, and both go to the message, which cannot scroll.
    private static let theShareOfTheBandTheMessageKeeps: CGFloat = 0.45

    /// Below this a card is too few entries to be worth drawing. Roughly four.
    private static let leastTheCardIsGiven: CGFloat = 180

    /// What the message keeps whatever the card wants — see ``heightOfTheCard``. A bubble's worth.
    private static let leastTheMessageIsGiven: CGFloat = 60

    /// Enough to read as having left the page, and not enough to read as a zoom.
    /// **Restored to 1.04**, the experiment having cleared it: with the growth taken to 1 the shrink was still there, so nothing about the copy's scale is
    /// involved — measured on a Mac, 2026-08-26.
    private static let howMuchALiftedMessageGrows: CGFloat = 1.04

}


extension SingleDiscussionCellView.Model {

    /// The edge of the discussion this cell's message hangs from — see ``TheSideAMessageHangsFrom``.
    var theSideItHangsFrom: TheSideAMessageHangsFrom {
        switch self {
        case .sentMessage: return .trailing
        case .receivedMessage: return .leading
        case .systemMessage: return .centre
        }
    }

}
