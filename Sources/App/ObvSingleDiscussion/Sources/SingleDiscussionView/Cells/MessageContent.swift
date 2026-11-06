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

import Foundation


/// What a message shows, which is not always its text and its attachments: some messages replace all of that with one thing of their own.
///
/// **The choice is made once, by the data source, and never by a view.** The legacy cells configure every part of themselves and then blank most of it again —
/// four branches, each clearing a different set — which puts the decision in the view and makes it impossible to see at a glance what a message will look like.
/// Here it is a value, so a view draws exactly one of these and nothing has to be undone.
///
/// It grows one case at a time, and the compiler names every place that must answer for a new one: `location` arrives with Step 9, `poll` with Step 10, and
/// `wiped` and `tapToRead` with Step 11.
public enum MessageContent: Equatable, Sendable {

    /// A message showing what was written and what was attached — the ordinary case, and by far the most common one.
    case ordinary(Ordinary)

    /// Every file this message carries — what a drag out of the discussion hands over, and nothing for the kinds that carry none. A message
    /// waiting to be tapped offers nothing on purpose: what it holds has not been shown to the reader yet, so it is not theirs to take away.
    var everyFileAttached: [MessageAttachment] {
        switch self {
        case .ordinary(let ordinary): ordinary.everyFileAttached
        case .location, .poll, .tapToRead, .wiped: []
        }
    }

    /// A message whose whole content is a place. It shows a map and nothing else: no body, since the body of such a message is a Google Maps URL meant for
    /// clients too old to know what a location is, and no attachments, since it has none.
    case location(LocationInMessage)

    /// A message whose whole content is a poll. As with a location, the body is a fallback written for clients too old to know what a poll is — the question and the
    /// answers as plain text — and is not shown here.
    case poll(PollInMessage)

    /// A message the reader has to ask to see: read-once, or visible for a while only. It shows an invitation to tap and its attachments covered, and **nothing of
    /// what it says** — see ``TapToRead``.
    case tapToRead(TapToRead)

    /// A message that is gone: one sentence saying so, and nothing else. See ``WipedMessage``.
    case wiped(WipedMessage)


    /// The text of a message and everything attached to it, each part identified rather than resolved: a picture, a waveform or a preview is asked for by the
    /// view that draws it, so that one arriving updates that view alone and not the message it belongs to.
    public struct Ordinary: Equatable, Sendable {

        /// The body as it is shown, which is not always the body as it was sent: the URL a link preview renders is taken off the end of it, and a message that was
        /// nothing but that URL therefore has no body at all.
        ///
        /// **Attributed, and resolved before it gets here.** What a reader wrote may carry markdown and mentions, and what they did not write may still be worth
        /// making tappable — a phone number, an address. All of that is one value, produced where the message is, carrying only what a
        /// *view* cannot decide: the intents, the links and the ranges. Colour and font are the bubble's, applied where it is drawn, because they depend on which
        /// side of the discussion the message is on and on the reader's settings rather than on the message.
        let textBody: AttributedString?

        /// Where the rendering of a link in the body is to come from, if there is to be one. Not a `MessageAttachment` alone, because a preview reaches a reader
        /// by two routes — see ``LinkPreviewInMessage``.
        let linkPreview: LinkPreviewInMessage?

        /// The animated image of this message, if it has one: the **first** attachment that is a GIF or a WebP. Pulled out of ``images`` *before* they are
        /// counted, as the legacy screen pulls it out, so a message carrying one GIF and one photograph shows a single image beside it and not a grid of two.
        ///
        /// Not a `MessageAttachment` alone, it being the one attachment whose size is not a constant — see ``GifInMessage``.
        let gif: GifInMessage?

        /// The images attached to this message, in the order they were attached. The GIF is not among them: it is ``gif``, shown on its own.
        let images: [MessageAttachment]

        /// The first video attached to this message, shown as a preview of a frame with a play glyph on it. Only the first, as with the document and the
        /// recording: the others are among ``cards``.
        ///
        /// **Chosen by content type and not by availability**, which is the whole of what settled this step's open question. A video large enough not to be fetched
        /// automatically — which is most of them — still gets its preview, and shows the download control on it, because that is exactly what an *image* too large
        /// to fetch already does: ``images`` is built from the joins of image type whatever state they are in. One shape, chosen once, with nothing that changes
        /// under the reader as a file arrives.
        let video: MessageAttachment?

        /// The first paginated document attached to this message, shown as the top of its first page. Only the first: the others are among ``cards``, as on the
        /// legacy screen.
        let document: MessageAttachment?

        /// The first audio attachment of this message, shown as a player. Only the first, as on the legacy screen: further recordings are among ``cards``.
        let audio: MessageAttachment?

        /// Everything else attached to this message — a further document, an archive, a further video, a further recording — each shown as a card, in the order
        /// they were attached.
        let cards: [MessageAttachment]

        /// Every file this message carries, in the order they were attached — what a drag out of the discussion hands over. See
        /// ``TheAttachmentsOfAMessageDraggedOut``.
        ///
        /// The link preview is **not** among them, being a rendering of something the body already says rather than a file the reader was sent;
        /// legacy leaves it out of its own drag items for the same reason. Everything else is, the GIF and the audio included.
        var everyFileAttached: [MessageAttachment] {
            var files: [MessageAttachment] = []
            if let gif { files.append(gif.attachment) }
            files.append(contentsOf: images)
            if let video { files.append(video) }
            if let document { files.append(document) }
            if let audio { files.append(audio) }
            files.append(contentsOf: cards)
            return files
        }

        public init(textBody: AttributedString?, linkPreview: LinkPreviewInMessage?, gif: GifInMessage?, images: [MessageAttachment], video: MessageAttachment?, document: MessageAttachment?, audio: MessageAttachment?, cards: [MessageAttachment]) {
            self.textBody = textBody
            self.linkPreview = linkPreview
            self.gif = gif
            self.images = images
            self.video = video
            self.document = document
            self.audio = audio
            self.cards = cards
        }

    }

}
