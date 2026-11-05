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


/// Gives the deck all the height it is offered but a margin above and below it — unless the content of a card needs more, in which case the card keeps
/// its natural height and the margins give way, in proportion, down to nothing.
///
/// The content of a card comes first: a larger text size must never cut a name or a line of groups to keep the margins.
struct CardHeightLayout: Layout {

    let preferredTopMargin: CGFloat
    let preferredBottomMargin: CGFloat

    private var preferredMargins: CGFloat {
        preferredTopMargin + preferredBottomMargin
    }

    /// The height the cards need to show everything they hold, at the given width.
    private func contentHeight(of deck: LayoutSubview, width: CGFloat?) -> CGFloat {
        deck.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let deck = subviews.first else { return .zero }
        let contentHeight = contentHeight(of: deck, width: proposal.width)
        let width = proposal.width ?? deck.sizeThatFits(.unspecified).width
        // Take what is offered, but never less than the content.
        let height = max(proposal.height ?? (contentHeight + preferredMargins), contentHeight)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let deck = subviews.first else { return }
        // The width that was proposed, not the bounds' (both are the same here, the layout taking all the width it is offered).
        let width = proposal.width ?? bounds.width
        let contentHeight = contentHeight(of: deck, width: width)
        let room = bounds.height - contentHeight

        let topMargin: CGFloat
        let cardHeight: CGFloat
        if room >= preferredMargins {
            topMargin = preferredTopMargin
            cardHeight = bounds.height - preferredMargins
        } else {
            // Not enough room for both the content and the margins: the content wins, and what room is left is shared as the margins were.
            let spare = max(0, room)
            topMargin = preferredMargins > 0 ? spare * preferredTopMargin / preferredMargins : 0
            cardHeight = contentHeight
        }

        deck.place(at: CGPoint(x: bounds.minX, y: bounds.minY + topMargin),
                   anchor: .topLeading,
                   proposal: ProposedViewSize(width: width, height: cardHeight))
    }

}
