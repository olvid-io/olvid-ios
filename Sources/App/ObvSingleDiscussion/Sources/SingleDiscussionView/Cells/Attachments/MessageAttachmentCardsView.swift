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


/// The attachments of a message that are shown as cards, stacked as `AttachmentsView` stacks them on the legacy screen.
///
/// A **hairline** between two cards, and not a gap: the attachments of a message read as one block, exactly as its images do. The corners are rounded here, on
/// the group, which is what leaves those hairlines running from edge to edge.
struct MessageAttachmentCardsView: View {

    /// Which corners this part joins to another part of the same message — see ``TheColumnOfPartsOfAMessage``. Fully rounded unless the cell says otherwise.
    @Environment(\.cornersOfThisPartOfTheMessage) private var corners

    let cards: [MessageAttachment]
    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    @Environment(\.displayScale) private var displayScale

    /// `OlvidVerticalStackView(gap: 1)` on the legacy screen.
    private static let hairline = CGFloat(1)

    var body: some View {
        // Nothing at all when there are no cards, and not an empty stack: an empty container is still a subview of the cell's stack and is given a gap of its own —
        // see `MessageAudioPlayerView` for the whole of that reasoning.
        Group {
            if !cards.isEmpty {
                VStack(spacing: Self.hairline) {
                    ForEach(cards) { card in
                        cardView(card, isTheFirstCard: card.id == cards.first?.id, isTheLastCard: card.id == cards.last?.id)
                    }
                }
                .clipShape(MessageBubbleMetrics.shape(corners))
            }
        }
    }


    /// Builds one card, handing it whatever has already been decoded at the thumbnail's size. The lookup happens here, and not in the view built, so that
    /// nothing is fetched from within a view's initializer.
    private func cardView(_ attachment: MessageAttachment, isTheFirstCard: Bool, isTheLastCard: Bool) -> some View {
        let pixelSize = CGSize(width: AttachmentCardView.sizeToRequestForTheThumbnail.width * displayScale,
                               height: AttachmentCardView.sizeToRequestForTheThumbnail.height * displayScale)
        return AttachmentCardView(attachment: attachment,
                                  initialImage: dataSource.cachedImageForAttachment(attachment, pixelSize: pixelSize),
                                  // Which corners the clip above rounds for this card, and therefore which its thumbnail is rounded at.
                                  isTheFirstCard: isTheFirstCard,
                                  isTheLastCard: isTheLastCard,
                                  dataSource: dataSource,
                                  actions: actions)
    }

}
