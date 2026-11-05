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


/// A message the reader has to ask to see, and the invitation to ask.
///
/// The bubble is `TapToReadBubble` of the legacy screen — a `handTap` glyph beside an *italic* body label — and it is drawn **only when the message has something
/// written in it**, as there. A message whose content is only attachments shows no bubble: its covered attachments are the whole of what there is to tap.
///
/// **Nothing inside is interactive.** The covered attachments keep their shapes and their sizes, so that revealing the message does not move the discussion, but they
/// are drawn through `.allowsHitTesting(false)` and the whole cell carries one gesture. That is what makes "a tap anywhere reveals it" true by construction rather
/// than by remembering to add a gesture to each of the four presentations — and it is also why no control inside can steal the tap.
struct MessageTapToReadView: View {

    let message: TapToRead
    let style: MessageBubbleStyle
    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    var body: some View {
        // A single-root container, so that this view stays *unary*. See `SingleDiscussionCellView`.
        VStack(alignment: alignment, spacing: MessageBubbleMetrics.gap) {
            if message.showsTheBubble {
                bubble
            }
            MessageGifView(gif: message.covered.gif, dataSource: dataSource, actions: actions)
            MessageImagesView(images: message.covered.images, dataSource: dataSource, actions: actions)
            MessageDocumentPreviewView(document: message.covered.document, dataSource: dataSource, actions: actions)
            MessageAttachmentCardsView(cards: message.covered.cards, dataSource: dataSource, actions: actions)
            MessageAudioPlayerView(audio: message.covered.audio, dataSource: dataSource, actions: actions)
        }
        // Read by every presentation of an attachment, and by the two that draw text beside one.
        .environment(\.attachmentsAreCoveredUntilRead, true)
        // Nothing within may be tapped for itself: what a reader taps is the *message*.
        .allowsHitTesting(false)
        // **In front, as a sibling**, rather than a gesture further along this chain. A transparent layer over the whole thing takes every tap wherever it lands, so
        // nothing depends on how `allowsHitTesting(false)` composes with what follows it — and nothing inside can win a tap, which is what a covered message requires.
        // The legacy screen goes to the trouble of accepting taps outside the bounds of each covered attachment; one layer over the cell covers that and more.
        .overlay {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onTapGesture {
                    Task { await actions.userWantsToRevealMessage(message) }
                }
        }
    }


    private var alignment: HorizontalAlignment {
        switch style {
        case .sent: return .trailing
        case .received: return .leading
        }
    }


    /// `TapToReadBubble`: the glyph, then the sentence in italics, in a bubble of the cell's own colour.
    private var bubble: some View {
        MessageBubbleView(style: style) {
            HStack(spacing: Self.gapBetweenTheGlyphAndTheSentence) {
                Image(systemIcon: .handTap)
                    .font(.body)
                Text("Tap to see the message")
                    .font(.body.italic())
            }
        }
    }


    /// `OlvidHorizontalStackView(gap: 2.0)` of the legacy bubble.
    private static let gapBetweenTheGlyphAndTheSentence = CGFloat(2)

}
