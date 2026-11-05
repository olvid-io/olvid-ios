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


/// The parts of one message, drawn as one block.
///
/// A message carrying more than one part — a body *and* an attachment, a link preview above its text — was drawn as a stack of separate shapes, each fully
/// rounded. Legacy joins them: the corners where two parts meet take the small radius, so the column reads as one thing.
///
/// **The rule, and the spine.** Transcribed from `SentMessageCell` and `ReceivedMessageCell`:
///
/// ```swift
/// let topMaskedCorner: UIRectCorner = isFirstVisibleView ? [.topLeft, .topRight] : [.topLeft]      // sent
/// let bottomMaskedCorner: UIRectCorner = isLastVisibleView ? [.bottomRight, .bottomLeft] : [.bottomLeft]
/// ```
///
/// `maskedCorner` names the corners that get the **large** radius; every other corner gets the small one, so a join is 4pt rather than square. Note what
/// those two lines never do: they never drop `.topLeft` or `.bottomLeft`, so on a message sent only the **right** corners are joined, and the received cell
/// mirrors it. **The joint is always on the side the message hangs from, and the opposite side stays fully rounded top to bottom.** That is the spine, and it
/// is what makes a column read as one shape.
///
/// **Leading and trailing here, where legacy says left and right**, a sent bubble aligning to the trailing edge and flipping with the layout direction.
///
/// **Answered from the model, not from the views.** Legacy's `shownArrangedSubviews` asks a laid-out stack which parts are showing; that cannot be done here,
/// a cell being a stack of `Group`s several of which deliberately draw nothing. So *which part is first, which is last* is a question about the **model**, and
/// it is answered once, before anything is drawn.
///
/// **A part counts only if it draws a bubble**, which is legacy's `compactMap({ $0 as? ViewWithMaskedCorners })`. The case where that bites is a message of
/// up to three emoji: drawn large and bare, with no bubble, so it neither takes a join nor gives one — "👍" with a photograph is a big emoji above a fully
/// rounded picture, exactly as on the legacy screen.
struct TheColumnOfPartsOfAMessage {

    /// The parts a message may draw, in the order the cells draw them. The order matters and is the cells' own: change one and the other must follow.
    enum Part: CaseIterable {
        case body
        case linkPreview
        case gif
        case images
        /// After the images and before the document. A video is a picture of a frame, so it belongs with what is looked at rather than with what is
        /// listed, and a message carrying both shows its photographs first because that is the order they were attached in far more often than not.
        case video
        case document
        case cards
        case audio
    }

    /// Which parts this message actually draws a bubble for, in order.
    private let shown: [Part]

    /// The side the spine is on: the edge the message aligns to.
    private let style: MessageBubbleStyle

    init(_ ordinary: MessageContent.Ordinary, style: MessageBubbleStyle) {
        self.style = style
        self.shown = Part.allCases.filter { part in
            switch part {
            case .body:
                // Drawn, *and* drawn as a bubble: a body of a few emoji is shown bare and joins nothing. See ``MessageBodyView``.
                guard let body = ordinary.textBody else { return false }
                return !String(body.characters).isShownAsEmojiAlone
            case .linkPreview: return ordinary.linkPreview != nil
            case .gif: return ordinary.gif != nil
            case .images: return !ordinary.images.isEmpty
            case .video: return ordinary.video != nil
            case .document: return ordinary.document != nil
            case .cards: return !ordinary.cards.isEmpty
            case .audio: return ordinary.audio != nil
            }
        }
    }


    /// The corners this part is to be drawn with. Every corner is rounded fully for a part that stands alone, and a part this message does not draw is answered
    /// the same way — it draws nothing, so nothing depends on it.
    func corners(of part: Part) -> RectangleCornerRadii {

        guard let index = shown.firstIndex(of: part) else { return MessageBubbleMetrics.allCornersRounded }

        let large = MessageBubbleMetrics.cornerRadius
        let small = MessageBubbleMetrics.smallCornerRadius

        let atTheTop = index == shown.startIndex ? large : small
        let atTheBottom = index == shown.index(before: shown.endIndex) ? large : small

        switch style {
        case .sent:
            // The spine is on the trailing edge, which a sent message aligns to. The leading corners are never joined.
            return .init(topLeading: large, bottomLeading: large, bottomTrailing: atTheBottom, topTrailing: atTheTop)
        case .received:
            return .init(topLeading: atTheTop, bottomLeading: atTheBottom, bottomTrailing: large, topTrailing: large)
        }

    }

}


// MARK: - The environment

extension EnvironmentValues {

    /// The corners the part of a message being drawn is to have — see ``TheColumnOfPartsOfAMessage``.
    ///
    /// **The corners rather than the part's place**, which is what keeps this to one value: the shape depends on where a part sits *and* on which side of the
    /// discussion the message is, and the cell knows both while several of the part views know neither — ``MessageImagesView`` is handed no style at all. Resolving
    /// it at the cell means no view has to be given anything it did not need before.
    ///
    /// Fully rounded by default, so that a part drawn anywhere else is unchanged: the copy the context menu lifts, every preview, and the bubble of
    /// ``WhatWillHappenWhenThisMessageIsRead``.
    var cornersOfThisPartOfTheMessage: RectangleCornerRadii {
        get { self[CornersOfThisPartOfTheMessageKey.self] }
        set { self[CornersOfThisPartOfTheMessageKey.self] = newValue }
    }

}


private struct CornersOfThisPartOfTheMessageKey: EnvironmentKey {
    static var defaultValue: RectangleCornerRadii { MessageBubbleMetrics.allCornersRounded }
}


extension View {

    /// Says which corners this part of a message is to be drawn with — see ``TheColumnOfPartsOfAMessage``.
    func drawnAsPartOfTheMessage(_ corners: RectangleCornerRadii) -> some View {
        environment(\.cornersOfThisPartOfTheMessage, corners)
    }

}
