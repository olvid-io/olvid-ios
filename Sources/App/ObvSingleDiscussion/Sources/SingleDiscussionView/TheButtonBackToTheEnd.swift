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


/// The way back to the end of a discussion, for a reader who has scrolled away from it — the legacy `ScrollToBottomButton`, Step 37.
///
/// A control and nothing more: it draws itself, says when it was pressed, and knows when it is wanted. **What "far from the end" means, and what "the end"
/// is, both belong to the list** — see ``SingleDiscussionCellsListView``, which owns the geometry and the `ScrollViewProxy`. Keeping the two apart is what
/// lets the rule be read beside the other scrolling rules rather than inside a button.
///
/// An `arrowDown` in the label colour on a 48pt circle: glass from iOS 26, and before it a `systemBackground` under a shadow with `systemFill` washed over
/// it while held. **It stands in the same column as the composition bar's trailing button**, both 48pt circles inset by the same amount — see
/// ``insetFromTheTrailingEdge``, where the one number they must agree on is written down.
///
/// **It is placed by the reader's safe area, not against the composition bar.** Legacy pins itself 24pt above `composeMessageContainerView`; here the bar is
/// inserted into the safe area, so the same numbers are ordinary padding on an overlay and the bar's height never has to be named. That also settles what a
/// search does to it for nothing: the search bar takes the composition bar's place inside the same inset, so the button rises with it. **If it ever appears
/// behind a bar, this is the paragraph to doubt.**
///
/// **It stops taking taps when it is not shown.** A `UIButton` at `alpha` 0 is not hit-tested — UIKit refuses views under 0.01 — so the legacy button stops
/// accepting taps as it fades. Without saying so here, an invisible 48pt circle would sit over the last messages of every discussion and swallow presses.
///
/// **The fade is the animation's business.** The 0.2s is attached to the value that decides visibility, so showing and hiding are both safe to say twice —
/// which they are, the rule behind them being answered on every change of the scroll's geometry.
struct TheButtonBackToTheEnd: View {

    /// Whether the reader is far enough from the end of the discussion to be offered the way back, and has not been offered it while the
    /// discussion was still opening. Decided by ``SingleDiscussionCellsListView``.
    let isShown: Bool

    /// Pressed: take the reader to the end.
    let goBack: () -> Void

    var body: some View {
        Button(action: goBack) {
            // A fixed glyph in a fixed circle, as legacy has it. The arrow says the whole of what this control means, and nothing about it
            // is text, so it does not grow with the reader's text size — where a label that was the only way to know something would have
            // to.
            Image(systemIcon: .arrowDown)
                .font(.system(size: Self.glyph))
                .foregroundStyle(Color(UIColor.label))
                .frame(width: Self.diameter, height: Self.diameter)
                // **Without this, only the arrow itself answers a tap.** SwiftUI hit-tests what is *drawn*, not the frame around it: the 48pt frame is empty space,
                // and the circle a reader aims at is painted by the style's `.background`, which takes no part in hit testing any more than it does in sizing. So a
                // tap on the edge of the button did nothing at all, and the control felt broken without looking it.
                //
                // The mirror image of the deliberate *absence* of a `contentShape` on a message — see ``AMessageThatCanBeLifted``, where leaving the empty half of a
                // row untappable is the whole point. Here the shape *is* the control.
                .contentShape(.circle)
        }
        .buttonStyle(TheCircleOfTheButtonBackToTheEnd())
        .opacity(isShown ? 1 : 0)
        // Nothing to press while there is nothing to see: see the note above about a `UIButton` at `alpha` 0.
        .allowsHitTesting(isShown)
        .animation(.easeInOut(duration: Self.theFade), value: isShown)
        // Legacy names it nothing at all, an image being all a `UIButton` is given. An icon-only control that says only "Button" to
        // VoiceOver is the one thing worth adding here.
        .accessibilityLabel(Text("BUTTON_BACK_TO_THE_LATEST_MESSAGES"))
        // 24pt above the bar, as legacy has it, and in the same column as the bar's own trailing button — see ``insetFromTheTrailingEdge``.
        // Applied here rather than by the list, so that whoever places this overlay has only an alignment to choose.
        .padding(.trailing, Self.insetFromTheTrailingEdge)
        .padding(.bottom, Self.gapAboveTheBar)
    }


    /// `Constants.size` of the legacy button, which is square — and, not by coincidence, `ComposeView.buttonSize`. See
    /// ``insetFromTheTrailingEdge``.
    private static let diameter: CGFloat = 48

    /// The arrow inside it. Legacy asks for no configuration and gets the default symbol size for a button, which is this.
    private static let glyph: CGFloat = 20

    /// `scrollToBottomButton.bottomAnchor == composeMessageContainerView.topAnchor - 24`.
    private static let gapAboveTheBar: CGFloat = 24

    /// **`ComposeView.horizontalPadding`, so that this button and the round one at the trailing end of the composition bar stand in the
    /// same column.** Both are 48pt circles, so equal insets align their edges and their centres alike.
    ///
    /// Legacy asks for a flat 16 (`trailingAnchor == collectionView.safeAreaLayoutGuide.trailingAnchor - 16`), which is 4pt out on an
    /// iPhone, where the bar insets itself by 12. Close enough to look like a mistake rather than a decision, so it is corrected here.
    ///
    /// **Two numbers, copied**, and the comment is the only thing holding them together: `ObvSingleDiscussion` does not depend on
    /// `ObvComposition`, and could not read them if it did — the bar reaches this screen as a view the app has already built, which
    /// answers no questions about its own metrics. If the bar's inset or its buttons ever change, this is what has to follow.
    private static var insetFromTheTrailingEdge: CGFloat {
        #if targetEnvironment(macCatalyst)
        return 16
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? 16 : 12
        #endif
    }

    /// `UIView.animate(withDuration: 0.2)` in `_updateVisibility(isHidden:)`.
    private static let theFade: TimeInterval = 0.2

}


/// What the arrow sits on: a circle of glass from iOS 26, and the legacy circle before it.
///
/// A `ButtonStyle` rather than a `background` on the label, because the older half needs `isPressed`, which only a style is given.
///
/// **From iOS 26 the whole of the legacy chrome goes**, and that is the point rather than a shortcut: `.regular.interactive()` already
/// answers a press, so the wash it drew by hand is redundant; and glass carries its own edge, so a drop shadow under it reads as a sticker
/// on the screen instead of a control floating over the messages. The bar this button lines up with is glass on 26 too — see
/// `ComposeView.glassButtonStyle` — so following it is what keeps the two looking like one family.
///
/// **Not in a `GlassEffectContainer`.** That exists to let nearby pieces of glass flow into one another, and this has nothing to flow
/// into: it is alone over the transcript, 24pt clear of a bar that is a hierarchy of its own. Same reasoning as
/// ``TheSearchOfThisDiscussion``'s three capsules, from the other direction.
///
/// **Before iOS 26, the legacy drawing, part for part**: `systemBackground` under a shadow of the label colour at 12%, and `systemFill`
/// washed over it while held — the order legacy gets from `backgroundLayer` at `zPosition` -1 with `highlightOverlayLayer` above it. Both
/// shapes are in a `.background`, so neither takes any part in sizing the 48pt frame the label already has.
private struct TheCircleOfTheButtonBackToTheEnd: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26.0, *) {
            configuration.label
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            configuration.label
                .background {
                    Circle()
                        .fill(Color(UIColor.systemBackground))
                        .overlay {
                            // A `Group`, so that a button at rest adds no subview rather than an invisible one.
                            Group {
                                if configuration.isPressed {
                                    Circle().fill(Color(UIColor.systemFill))
                                }
                            }
                        }
                        // `shadowColor = label.withAlphaComponent(0.12)`, `shadowRadius = 16`, `shadowOffset = (0, 8)`.
                        .shadow(color: Color(UIColor.label).opacity(0.12), radius: 16, y: 8)
                }
        }
    }

}


#if DEBUG

#Preview {
    // Over something to be lifted off, so that the shadow and the circle can be told from the background they are drawn on.
    ZStack {
        Color(UIColor.secondarySystemBackground)
        VStack(spacing: 32) {
            TheButtonBackToTheEnd(isShown: true, goBack: {})
            TheButtonBackToTheEnd(isShown: false, goBack: {})
        }
    }
    .ignoresSafeArea()
}

#endif
