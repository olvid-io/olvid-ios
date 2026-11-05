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


/// The reader's favourite emojis, offered above a lifted message so that reacting to it takes one gesture.
///
/// **A long press shows this *and* the menu, which the legacy screen does not do**: there a long press gives the menu and
/// a double tap gives this, and the two never appear together.
///
/// **Transcribed from `ReactionContextView`**, which is already SwiftUI but lives in the app target and cannot be reached
/// from here — so its metrics are copied rather than shared, as ``MessageForwardedBadgeView``'s icon is. The numbers are
/// its: a 25pt corner radius on `tertiarySystemBackground`, emojis at 33pt spaced by 10, 10pt of horizontal inset and 2pt
/// of vertical, and a `+` at 20pt on a `systemFill` circle. Most have since moved: the emojis are 30pt, the insets are
/// roomier, the radius is a capsule that follows them, and the `+` is an `…` at 18pt, shrunk with the emojis. From iOS 26 the capsule is Liquid Glass.
///
/// **Two departures, both deliberate.** The reader's own reaction is drawn as *chosen* and choosing it again takes it
/// away — the legacy bar has no notion of either, and how "chosen" looks had to be invented, so it is the same
/// `systemFill` circle the `…` already sits on rather than any new colour. And the bloom starts from the corner the bar
/// hangs from, where the legacy background always scales from its bottom-trailing corner whichever side it is pinned to.
struct TheFavouriteEmojisBar: View {

    let emojis: TheEmojisOnOffer

    /// Which side the message hangs from, and therefore which corner this blooms out of.
    let side: TheSideAMessageHangsFrom

    /// 21b's single flag. Everything visible here hangs on it, staggered by a delay per emoji rather than by an animation
    /// of its own — see *The architecture, as decided*.
    let appeared: Bool

    /// An emoji chosen. **Nil means take the reader's reaction away**, which is what choosing the one already chosen means.
    let chose: (String?) -> Void

    /// The `…`, and the sentence that stands in for the bar when the reader has no favourites yet: both open the full
    /// picker.
    let wantsTheWholePicker: () -> Void

    var body: some View {
        theEmojisAndThePlus
            // Taking no part in the sizing — see ``TheCapsuleOfTheBar``.
            .modifier(TheCapsuleOfTheBar())
            // **The whole bar scales as one, and the emojis are tight to the capsule because of it.** Scaling the capsule
            // alone left every emoji at its final place, at full spacing, while the capsule behind them was still small —
            // so they hung outside it and read as flying in from nowhere. Scaling the container scales the *positions*
            // too, so at every instant an emoji sits exactly where the capsule has reached. The pop of each one is then
            // its own scale below, about its own centre, which is a pop and not a journey.
            .scaleEffect(appeared ? 1 : 0, anchor: side.bottomOfTheNearEdge)
            .animation(theArrival(after: Self.whenTheCapsuleArrives), value: appeared)
    }


    private var theEmojisAndThePlus: some View {
        HStack(spacing: Self.gapBetweenTheEmojis) {
            if emojis.favourites.isEmpty {
                theSentenceThatStandsInForThem
            } else {
                // The offset is a stable identity here: this list is read once, at press time, and never reordered while
                // the bar is up.
                ForEach(Array(emojis.favourites.enumerated()), id: \.offset) { index, emoji in
                    button(for: emoji, comingInAfter: index)
                }
            }
            thePlus
        }
        .padding(.horizontal, Self.horizontalInset)
        .padding(.vertical, Self.verticalInset)
    }


    private func button(for emoji: String, comingInAfter index: Int) -> some View {
        Button {
            // Choosing the one already chosen takes it away. The model would merely write it again — see
            // ``TheEmojisOnOffer/theReadersOwn``.
            chose(emoji == emojis.theReadersOwn ? nil : emoji)
        } label: {
            Text(verbatim: emoji)
                .font(.system(size: Self.emojiFontSize))
                .background {
                    // Invented, the legacy bar having no chosen state — and in the fill the `…` already uses, so that the
                    // bar gains no vocabulary of its own.
                    if emoji == emojis.theReadersOwn {
                        Circle()
                            .fill(Color(UIColor.systemFill))
                            .scaleEffect(Self.howMuchTheChosenMarkOverflowsTheEmoji)
                    }
                }
        }
        .buttonStyle(.plain)
        .scaleEffect(appeared ? 1 : 0)
        .rotationEffect(.degrees(appeared ? 0 : Self.rotationTheyComeInFrom))
        .animation(theArrival(after: Self.whenTheFirstOneArrives + Self.stagger * Double(index)), value: appeared)
    }


    private var thePlus: some View {
        Button(action: wantsTheWholePicker) {
            // `…` rather than legacy's `+`: what it opens is the whole picker, which is *more* emojis than the bar has room for.
            Image(systemIcon: .ellipsis)
                .font(.system(size: Self.plusFontSize))
                // Square, so the circle behind it stays a circle: the ellipsis is much wider than it is tall, where the `+` it replaced was not.
                .frame(width: Self.plusFontSize, height: Self.plusFontSize)
                .padding(Self.paddingAroundThePlus)
                .background { Circle().fill(Color(UIColor.systemFill)) }
        }
        .buttonStyle(.plain)
        .scaleEffect(appeared ? 1 : 0)
        .rotationEffect(.degrees(appeared ? 0 : Self.rotationTheyComeInFrom))
        // Last in, after every emoji, as in the legacy bar.
        .animation(theArrival(after: Self.whenTheFirstOneArrives + Self.stagger * Double(emojis.favourites.count)), value: appeared)
    }


    /// What the bar says when the reader has chosen no favourites: an invitation, tappable, in place of the emojis.
    private var theSentenceThatStandsInForThem: some View {
        Button(action: wantsTheWholePicker) {
            Text("ADD_TO_CONFIGURE_PREFERRED_EMOJIS_LIST")
                .font(Font.system(.callout, design: .rounded).weight(.semibold))
                .multilineTextAlignment(.center)
                // **No `frame(maxWidth: .infinity)`**, which the legacy view has: there it centres the sentence inside a
                // container already forced to its intrinsic size, and here it would simply make the bar as wide as the row
                // — the same defect the capsule had, in the one state nobody looks at.
                .frame(height: Self.heightOfTheSentence)
        }
        .buttonStyle(.plain)
        .scaleEffect(appeared ? 1 : 0)
        .animation(theArrival(after: Self.whenTheFirstOneArrives), value: appeared)
    }


    /// The bloom, staggered — **on the way in only.**
    ///
    /// The stagger is what makes the bar recognisable arriving and what made it absurd leaving: the same delays applied in
    /// both directions, so the capsule vanished at 0.05s while the last emoji waited until 0.30s and the `+` until 0.35s,
    /// against an overlay taken down at 0.34s. What the reader saw was five emojis hanging in mid-air with nothing behind
    /// them. Going away, everything goes together and quickly.
    private func theArrival(after delay: TimeInterval) -> Animation {
        appeared ? Self.theBloom.delay(delay) : Self.theDeparture
    }


    // MARK: The legacy numbers

    private static let gapBetweenTheEmojis: CGFloat = 10
    /// **Not legacy's 10 and 2, which left the emojis tight against the capsule.** About 11pt of air above and below them, as the system's own reaction bars
    /// have from iOS 26, and a little more at the ends than legacy so that they keep pace with a taller bar.
    private static let horizontalInset: CGFloat = 12
    private static let verticalInset: CGFloat = 7
    /// 30 rather than legacy's 33, as the system's own reaction bars draw them from iOS 26, so that the air around them reads as a margin.
    private static let emojiFontSize: CGFloat = 30
    /// 18 and 5 rather than legacy's 20 and 6, shrunk with the emojis (30/33) so that the circle keeps its proportion to them: 28pt, from 32.
    private static let plusFontSize: CGFloat = 18
    private static let paddingAroundThePlus: CGFloat = 5
    private static let heightOfTheSentence: CGFloat = 40

    /// The spring each element arrives on — **the overlay's own, and not the legacy bar's.**
    ///
    /// Legacy blooms on `interpolatingSpring(stiffness: 170, damping: 15)`, which works out at a damping ratio of about
    /// 0.58 and takes some 0.53s to settle. That is right for a bar which, on that screen, appears *alone*: a double tap
    /// shows it and there is nothing on screen keeping a different time. Here it appears beside the menu card, and the two
    /// were plainly out of step — the card settled in about 0.30s and the bar was still moving at 0.88s, the delays below
    /// being the smaller half of the difference and the softer spring the larger.
    ///
    /// So the character is kept — the stagger, the rotation, the pop — and the *clock* is the one the lift and the card
    /// already share. Which is the through-line of this whole sub-step: legacy's values are right in legacy's context, and
    /// this screen puts two things together that legacy never did.
    private static let theBloom: Animation = TheContextMenuOfAMessage.theLift

    /// Undelayed, and shorter than the return of the message it sits above, so the bar is gone before the overlay is.
    private static let theDeparture: Animation = .easeOut(duration: 0.15)

    /// When the capsule — and with it the whole bar — starts to grow.
    private static let whenTheCapsuleArrives: TimeInterval = 0.0

    private static let whenTheFirstOneArrives: TimeInterval = 0.05
    private static let stagger: TimeInterval = 0.03
    private static let rotationTheyComeInFrom: Double = -45

    /// Enough for the mark to read as a disc behind the emoji rather than as a ring around it.
    private static let howMuchTheChosenMarkOverflowsTheEmoji: CGFloat = 1.15

}



/// What the bar is drawn on: Liquid Glass from iOS 26, as the menu card under the message is, and before that legacy's capsule.
///
/// **A `background` or a glass effect, and emphatically not a `ZStack`.** A `Shape` is infinitely flexible: put in a stack beside the emojis it takes every point
/// of width it is offered and the stack sizes to *it*, so the bar spanned the whole row. Legacy escapes this by forcing `reactionView.frame` to its
/// `intrinsicContentSize` in UIKit; in SwiftUI the answer is that the surface must not take part in the sizing at all — which `glassEffect(_:in:)` does not.
private struct TheCapsuleOfTheBar: ViewModifier {

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .capsule)
        } else {
            content
                .background {
                    Capsule()
                        .fill(Color(UIColor.tertiarySystemBackground))
                }
        }
    }

}

#if DEBUG

#Preview {
    VStack(spacing: 24) {
        TheFavouriteEmojisBar(emojis: .init(favourites: ["❤️", "👍", "👎", "😂", "‼️"], theReadersOwn: "👍", theEmojiADoubleTapSends: "❤️"),
                              side: .trailing,
                              appeared: true,
                              chose: { _ in },
                              wantsTheWholePicker: {})
        TheFavouriteEmojisBar(emojis: .init(favourites: ["❤️", "👍", "👎", "😂", "‼️"], theReadersOwn: nil, theEmojiADoubleTapSends: "❤️"),
                              side: .leading,
                              appeared: true,
                              chose: { _ in },
                              wantsTheWholePicker: {})
        TheFavouriteEmojisBar(emojis: .none,
                              side: .leading,
                              appeared: true,
                              chose: { _ in },
                              wantsTheWholePicker: {})
            .frame(width: 300)
    }
    .padding()
    .background(Color(UIColor.systemGroupedBackground))
}

#endif
