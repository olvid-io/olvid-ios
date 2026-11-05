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
import CoreGraphics


/// Where the link preview of a message is to come from, which is the one thing about a preview that is known from the message alone.
///
/// Two cases because a preview reaches a reader by two routes, and they are not the same thing at all: one is a file the sender attached, the other is something
/// this device may go and fetch on its own. A view has to tell them apart in order to know what to reserve — an attachment is *coming*, and its space is held with
/// a spinner, whereas a preview that has still to be fetched may never exist and is given no space until it does.
public enum LinkPreviewInMessage: Hashable, Sendable {

    /// The sender attached a preview, which arrives as an attachment like any other — except that it is always downloaded, whatever size the reader has set as
    /// the limit, and therefore never offers a control to ask for it.
    ///
    /// The shape is what the card *measures*, read while the message's model was built, and nil only while the file holding it has not arrived. See
    /// ``LinkPreviewShape``.
    case attached(MessageAttachment, shape: LinkPreviewShape?)

    /// The sender attached none, the reader has asked for missing previews to be fetched, and this is the link to fetch one for.
    ///
    /// **No shape, and there cannot be one**: there is no file, the fetch is what the request sets off, and the site may answer nothing at all. So this is the one
    /// preview that is given no space until it exists — as on the legacy screen, where a message grows when a preview appears for it.
    case toBeFetched(url: URL)

}


/// Everything a link preview draws except its pictures, which is to say everything that decides how tall its card is.
///
/// **Why this is in the message's model rather than in the answer to a request.** A card's height is its picture's proportions, plus however many lines its
/// description takes, plus however many its title takes — none of it a constant, and all of it read from the *file* an attached preview is. So it used to arrive
/// with the metadata, milliseconds after the row had been laid out at 280×140 with a spinner in it, and the row then grew or shrank to whatever the card really
/// was. On a discussion opening at its end, that landed after the list had been placed and revealed.
///
/// It is the same lesson as ``GifInMessage/canvasSize`` and ``PollInMessage/Shape``: **the model carries what decides the height, and what is asked for separately
/// is only what changes inside it.** Here what is asked for is reduced to the two pictures — everything else a reader sees is here, and is therefore drawn on the
/// frame the row first appears on rather than a moment later.
///
/// Nothing in it can go stale: an attached preview *is* a file, and a file does not change.
public struct LinkPreviewShape: Hashable, Sendable {

    public let title: String?

    /// What the page says of itself. `desc` rather than `description`, as `ObvLinkMetadata` names it, `description` being taken.
    public let desc: String?

    /// The host, without a leading `www.` — all the legacy screen shows of the URL.
    public let domain: String?

    /// Where tapping the card goes. Carried so that it goes there from the first frame: it used to do nothing at all until the metadata had been read.
    public let url: URL?

    /// Whether the description runs on rather than being clamped to a few lines — decided app-side from a list of domains, and part of the height for that reason.
    public let showsTheWholeDescription: Bool

    public let picture: Picture

    /// What kind of picture the card holds, **without the picture itself**: a `CGImage` must not travel in a message's model, which is compared for equality and
    /// held in a bounded cache of every model this screen has shown. What is needed here is only the space one takes.
    public enum Picture: Hashable, Sendable {

        case none

        /// A small picture, drawn as a 40pt square beside the title. Its own proportions do not matter, the square being fixed.
        case icon

        /// A picture drawn the full width of the card, whose height is therefore the width divided by this.
        case large(aspectRatio: CGFloat)

    }

    /// Whether there is nothing at all to show, in which case the card is not drawn: a bubble containing only its own insets says less than no bubble. The same
    /// question ``LinkPreviewMetadata/saysNothing`` answers, asked of the same facts one step earlier.
    public var saysNothing: Bool {
        guard title == nil, desc == nil, domain == nil else { return false }
        if case .none = picture { return true }
        return false
    }

    public init(title: String?, desc: String?, domain: String?, url: URL?, showsTheWholeDescription: Bool, picture: Picture) {
        self.title = title
        self.desc = desc
        self.domain = domain
        self.url = url
        self.showsTheWholeDescription = showsTheWholeDescription
        self.picture = picture
    }

}


/// What a link preview says, once whatever holds it has been read.
///
/// Not `Equatable`, and not part of any message's model: it is asked for by the view that draws it, arrives once, and never changes — the same shape
/// ``AudioRecording`` has, for the same reasons.
public struct LinkPreviewMetadata: Sendable {

    public let title: String?

    /// What the page says of itself. `desc` rather than `description`, as `ObvLinkMetadata` names it, `description` being taken.
    public let desc: String?

    /// The host of the link, without a leading `www.` — which is all the legacy screen shows of the URL.
    public let domain: String?

    /// Where tapping the preview goes.
    public let url: URL?

    public let image: LinkPreviewImage

    /// Whether the description is shown in full rather than clamped to a few lines.
    ///
    /// Decided where the metadata is read, and not here: it depends on a list of domains that lives in `ObvMessengerConstants.LinkPreview` on the app side —
    /// the handful of social networks whose preview *is* the text of a post, and which the legacy screen therefore lets run on.
    public let showsTheWholeDescription: Bool

    public init(title: String?, desc: String?, domain: String?, url: URL?, image: LinkPreviewImage, showsTheWholeDescription: Bool) {
        self.title = title
        self.desc = desc
        self.domain = domain
        self.url = url
        self.image = image
        self.showsTheWholeDescription = showsTheWholeDescription
    }

    /// Whether there is nothing at all to show, in which case the preview is not drawn: a bubble containing only its own insets says less than no bubble.
    public var saysNothing: Bool {
        guard title == nil, desc == nil, domain == nil else { return false }
        if case .none = image { return true }
        return false
    }

}


/// The picture a link preview carries, and how big it is to be drawn.
///
/// **The two cases are a rule about the file, not a choice of layout**, which is why they are decided where the picture is decoded rather than in the view: the
/// legacy screen shows an image under 400px in *both* dimensions as a small square beside the title — a site's logo, typically — and anything larger as the
/// picture at the top of the card. A view cannot make that choice without the size of the original, which downsampling has by then thrown away.
public enum LinkPreviewImage: Sendable {

    case none

    /// A small picture, drawn as a square beside the title.
    case icon(CGImage)

    /// A picture drawn the full width of the card, as tall as its own proportions make it.
    case large(CGImage, aspectRatio: CGFloat)

}


/// What a link preview holds, read from whatever carries it.
///
/// A protocol of its own, alongside ``AttachmentProgressDataSource`` and ``AudioPlaybackDataSource``, so that what this screen asks of its app remains legible
/// one question at a time.
@MainActor
public protocol LinkPreviewDataSource: AnyObject {

    /// What the preview of a message says, and the picture to draw it with.
    ///
    /// **A single answer, and not a stream**, for the reason ``SingleDiscussionCellViewDataSource/recordingForAudioAttachment(_:numberOfSamples:)`` gives: there is
    /// no cruder version worth showing first, and nothing here changes once it is known.
    ///
    /// Nil while there is nothing to answer with — the file not being here yet, the fetch having failed, the metadata being unreadable — and the view then shows
    /// what its source justifies: an attachment on its way is given its space, a preview that may never be fetched is given none.
    ///
    /// `maxPixelSize` bounds the larger dimension of the picture, in pixels, as everything else on this screen is asked for. Reading a file and decoding an image
    /// is real work and belongs off the main actor, with the answer remembered: what reaches the view is ready to draw.
    func linkPreviewMetadata(for source: LinkPreviewInMessage, maxPixelSize: Int) async -> LinkPreviewMetadata?

}
