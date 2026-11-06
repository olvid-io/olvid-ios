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


/// The card of entries a lifted message offers — what a `UIMenu` would have drawn, drawn here instead.
///
/// **This is the bill the custom overlay was known to come with.** `UIMenu` gives placement, clamping, dismissal, destructive styling, VoiceOver and Catalyst
/// pointer behaviour for nothing; owning the overlay means owning all of it. What is here is the drawing and the styling; the placement and the clamping are
/// ``MessageContextMenuOverlay``'s, and the dismissal is the screen's.
///
/// It renders ``WhatAMessageOffers`` and decides nothing: which entries there are, and in what order, was settled at press time by the data source — see step 21a.
/// The wording and the icons are this module's copies of the legacy ones, as ``MessageForwardedBadgeView``'s icon is, this module knowing nothing of the app's
/// constants.
struct MessageContextMenuCard: View {

    let offers: WhatAMessageOffers

    /// How tall one entry is. Passed in rather than computed here, because the overlay needs the same number to know where the card will fit — see
    /// ``MessageContextMenuOverlay``.
    let rowHeight: CGFloat

    /// How tall the card is to be, decided by the overlay: what it wants, or what is left under the message, whichever is smaller.
    let height: CGFloat

    let chose: (MessageAction) -> Void

    /// The column the icons stand in, wide enough for the widest of them at the reader's text size.
    @ScaledMetric(relativeTo: .body) private var widthOfTheIcons: CGFloat = 24

    var body: some View {
        // Scrollable, and that is not defensive: a message the reader sent, with attachments and a reaction, offers eleven entries — some 500pt at the ordinary
        // text size and half as much again at an accessibility one. The card is given whatever room is left below the bubble and scrolls within it.
        ScrollView {
            // **No separators**, the rows being told apart by the air around them, as in the system's own menus from iOS 26. That keeps
            // ``heightWanted(by:rowHeight:)`` exact as well: a `Divider`'s thickness is undocumented and platform-dependent, and there is now no hairline for the
            // arithmetic to leave out.
            VStack(spacing: 0) {
                ForEach(Array(offers.entries.enumerated()), id: \.offset) { _, entry in
                    row(for: entry)
                }
            }
            // Air above the first entry, so that it does not sit against the card's rounded top edge.
            .padding(.top, Self.verticalInset)
            // **Half an entry of nothing at the end, and it is what makes the fade below honest.** The fade has to sit over the card's bottom edge, and a fade
            // that is always there dims whatever is at that edge once the reader has scrolled to it — which is `Delete`, the one entry all of this exists to
            // reach. With half an entry of padding the content is exactly half an entry taller than the card, so at the end of the scroll the band under the fade
            // is *empty*: `Delete` stands whole above it. At the top of the scroll the same band holds the peeking half entry, which is the thing being pointed at.
            //
            // It also disposes of a question nobody here has had to answer — whether a SwiftUI `mask` takes hit-testing with it. Unmeasured, and it cannot matter:
            // at the one scroll position where the fade could reach `Delete`, it is over this padding instead.
            //
            // One number in three roles, and that is why it works rather than being a coincidence: the padding, the depth of the fade and the half entry
            // ``MessageContextMenuOverlay/cutOnAHalfEntry(_:rowHeight:)`` leaves are all `rowHeight / 2`. A card that shows everything has the same air under
            // its last entry as above its first.
            .padding(.bottom, itIsCut ? rowHeight / 2 : Self.verticalInset)
        }
        // **A scroll view takes every point of height it is offered**, so the height it is to have is decided outside and given to it exactly — see
        // ``MessageContextMenuOverlay``, which takes the smaller of what this wants and what is left under the message. `scrollBounceBehavior(.basedOnSize)` would
        // have said the same thing more directly and is iOS 16.4, where this module is iOS 16.
        .frame(width: Self.width, height: height)
        // Applied to the scrolling content and not to the card, so the material behind it is not faded with it. Only when there is something to say: a mask costs
        // an offscreen composite, which is nothing for one card and is still not worth paying for a menu that shows everything it has.
        .modifier(TheFadeAtTheBottomEdge(depth: itIsCut ? rowHeight / 2 : 0, of: height))
        .modifier(TheSurfaceOfTheCard())
    }


    private func row(for entry: WhatAMessageOffers.Entry) -> some View {
        Button {
            chose(entry.action)
        } label: {
            HStack(spacing: Self.gapBetweenTheIconAndTheWords) {
                // A glyph on the line rather than an `Image`, so that the row is one line box tall whatever the symbol, and in a column of its own width so that
                // the titles line up however wide each symbol is.
                Text(Image(systemIcon: icon(of: entry)))
                    .frame(width: widthOfTheIcons)
                title(of: entry)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .font(.body)
            .foregroundStyle(entry.isDestructive ? Color(UIColor.systemRed) : Color(UIColor.label))
            .padding(.horizontal, Self.horizontalInset)
            .frame(minHeight: rowHeight)
            // So that the whole row answers the tap and not only the words in it.
            .contentShape(Rectangle())
        }
        // A style of its own rather than `.plain`, for the highlight under the finger, and for the same reason `.plain` was there: without an explicit style the
        // row would become the *card's* button rather than a target of its own — the rule every button on this screen follows, and the one that cost a poll its
        // votes when it was forgotten.
        .buttonStyle(AnEntryOfTheCard())
    }


    /// What an entry is called. The legacy wording, copied into this module's own catalogue.
    private func title(of entry: WhatAMessageOffers.Entry) -> Text {
        switch entry {
        case .showInfo:
            return Text("MESSAGE_INFO")
        case .react(alreadyReacted: let alreadyReacted):
            // "Change" when there is one to change, which is the same fact that chooses the icon.
            return alreadyReacted ? Text("CHANGE_MY_REACTION") : Text("ADD_A_REACTION")
        case .deleteOwnReaction:
            return Text("DELETE_OWN_REACTION")
        case .copyText:
            return Text("COPY_TEXT")
        case .sharePhotos(count: let count):
            return Text("SHARE_COUNT_PHOTOS_\(count)")
        case .shareAttachments(count: let count):
            return Text("SHARE_COUNT_ATTACHMENTS_\(count)")
        case .saveAttachments(count: let count):
            return Text("SAVE_COUNT_ATTACHMENTS_\(count)")
        case .reply:
            return Text("REPLY")
        case .edit:
            return Text("EDIT")
        case .forward:
            return Text("FORWARD")
        case .call:
            return Text("CALL")
        case .select:
            // **`SELECT`, not the ellipsis's `SELECT_MESSAGES`.** That one names what the mode is; this one starts it *with this message*, and a menu entry
            // beside *Reply* and *Forward* reads as a thing done to the message it is attached to. One word, as its neighbours are.
            return Text("SELECT")
        case .delete:
            return Text("DELETE")
        }
    }


    /// The icon of an entry, one for one with the legacy menu's.
    private func icon(of entry: WhatAMessageOffers.Entry) -> SystemIcon {
        switch entry {
        case .showInfo: return .infoCircle
        case .react(alreadyReacted: let alreadyReacted): return alreadyReacted ? .arrowClockwiseHeart : .heart
        case .deleteOwnReaction: return .heartSlash
        case .copyText: return .docOnDoc
        case .sharePhotos, .shareAttachments: return .squareAndArrowUp
        case .saveAttachments: return .squareAndArrowDownOnSquare
        case .reply: return .arrowshapeTurnUpLeft2
        case .edit: return .pencil(.circle)
        case .forward: return .arrowshapeTurnUpForward
        case .call: return .phoneFill
        // The same glyph the ellipsis entry uses, so the two doors into the mode look like one thing.
        case .select: return .checkmarkCircle
        case .delete: return .trash
        }
    }


    /// Whether this card is showing less than it has — which is what puts the fade over its bottom edge and the half entry of padding under its last one.
    ///
    /// **Asked of the same estimate the overlay cut on**, so the two cannot come to disagree about whether there is more below. It inherits that estimate's one
    /// blind spot, named in ``heightWanted(by:rowHeight:)``: an entry whose wording wraps makes the content taller than the arithmetic says, and such a card
    /// scrolls without the fade to announce it. The half entry the cut leaves is still there, which is the stronger of the two cues anyway.
    private var itIsCut: Bool {
        height + 0.5 < Self.heightWanted(by: offers, rowHeight: rowHeight)
    }


    /// What a `UIMenu` is wide, near enough. There is no way to ask the system for it.
    static let width: CGFloat = 250

    /// The air above the first entry, and under the last when the card shows everything it has. Public to the overlay, which has to cut a card that cannot
    /// show everything on a half entry *below* this.
    static let verticalInset: CGFloat = 8

    private static let horizontalInset: CGFloat = 18

    private static let gapBetweenTheIconAndTheWords: CGFloat = 12

    /// How tall the card would like to be, which is what the overlay uses to decide where the message can sit.
    ///
    /// **Exact whenever every entry fits on one line**, which is the ordinary case: there are no separators, the air at both ends is ``verticalInset``, and a
    /// row is `rowHeight` tall unless its own words make it taller.
    ///
    /// It remains an estimate for the case it cannot see — an entry whose wording wraps, which a long word in German or a large accessibility size can cause.
    /// Being wrong there costs a card that scrolls slightly sooner than it needed to, which is why it is worth no more than a multiplication, and why the card
    /// scrolls at all. Measuring instead would mean laying the content out before the overlay can decide where the message sits, which is a frame the reader
    /// would see.
    static func heightWanted(by offers: WhatAMessageOffers, rowHeight: CGFloat) -> CGFloat {
        CGFloat(offers.entries.count) * rowHeight + 2 * verticalInset
    }

}


/// What the card is made of: Liquid Glass from iOS 26, and before that the material and corner radius of a `UIMenu` of the same era.
///
/// **The glass is only worth having over a backdrop that lets the discussion through** — it takes its tint from what is behind it, and over an opaque wash it
/// reads as a white card. See ``MessageContextMenuOverlay``'s backdrop, which is lighter from iOS 26 for that reason.
///
/// Not interactive: `.interactive()` answers a touch anywhere on the glass, where what should answer is the one entry under the finger — see
/// ``AnEntryOfTheCard``.
private struct TheSurfaceOfTheCard: ViewModifier {

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadiusOfTheGlass, style: .continuous))
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Self.cornerRadiusOfTheGlass, style: .continuous))
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: Self.cornerRadiusOfAMenu, style: .continuous)
                        .fill(.regularMaterial)
                }
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadiusOfAMenu, style: .continuous))
        }
    }

    /// The rounder corners of the system's own menus from iOS 26.
    private static let cornerRadiusOfTheGlass: CGFloat = 28

    /// `UIMenu`'s corner radius before iOS 26, near enough.
    private static let cornerRadiusOfAMenu: CGFloat = 13

}


/// An entry of the card: a wash under the finger while it is down, inset from the card's edges as the system's menus draw it.
///
/// Drawn in `.background`, so it takes no part in sizing the row — whose height ``MessageContextMenuCard/heightWanted(by:rowHeight:)`` has to be able to
/// compute.
private struct AnEntryOfTheCard: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.1 : 0))
                    .padding(.horizontal, Self.inset)
            }
    }

    private static let inset: CGFloat = 6
    private static let cornerRadius: CGFloat = 12

}


/// The fade over the bottom edge of a card that has more below — see ``MessageContextMenuCard/itIsCut``.
///
/// **A modifier of its own so that the mask is applied once and conditionally**, the condition being carried as a depth of zero: a `mask` costs an offscreen
/// composite, and a card showing everything it has should not pay it. A depth of zero yields a gradient that is opaque from end to end, so the branch is in the
/// numbers rather than in the view tree — which keeps the card's own body one chain.
///
/// `.black.opacity(0)` and never `.clear`, as everything on this screen that fades does: the house rule is about a colour fading to transparent *black* and
/// leaving a halo, and a mask reads only the alpha, so the two are the same here. Written the same way regardless, there being no reason for one fade on this
/// screen to be spelt differently from the others.
private struct TheFadeAtTheBottomEdge: ViewModifier {

    /// How deep the fade is. **Zero for a card that has nothing below**, which makes this nothing but an opaque mask.
    let depth: CGFloat

    /// How tall the card is, the gradient's stops being fractions of it.
    let of: CGFloat

    func body(content: Content) -> some View {
        content
            .mask {
                LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
            }
    }

    private var stops: [Gradient.Stop] {
        guard depth > 0, of > 0 else { return [.init(color: .black, location: 0), .init(color: .black, location: 1)] }
        let whereItStartsToGo = max(0, min(1, (of - depth) / of))
        return [.init(color: .black, location: 0),
                .init(color: .black, location: whereItStartsToGo),
                .init(color: .black.opacity(0), location: 1)]
    }

}


extension WhatAMessageOffers.Entry {

    /// Whether this entry is drawn as destructive. Only one is, as in the legacy menu, where `Delete` alone carries `.destructive`.
    ///
    /// Deleting one's own reaction is deliberately **not** destructive: legacy gives it no attribute, and it takes nothing away that cannot be put back with two
    /// taps.
    var isDestructive: Bool {
        switch self {
        case .delete: return true
        case .showInfo, .react, .deleteOwnReaction, .copyText, .sharePhotos, .shareAttachments, .saveAttachments, .reply, .edit, .forward, .call, .select: return false
        }
    }

}
