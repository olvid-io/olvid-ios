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


/// The rendering of a link the message's text contains: a picture, what the page says of itself, its title and its domain.
///
/// Matches `SinglePreviewView` of the legacy screen, part for part and in its order — which is worth stating, because that order surprises: the **description sits
/// above the title**, with the icon and the domain beside and beneath it. It is what a reader sees today.
///
/// Tapping it opens **the link**, and not the file behind it — which is what the legacy screen does too, a preview being the rendering of a URL rather than an
/// attachment a reader would want to look at. So it needs no hardlink and no QuickLook — but it does need the app, and this is the whole of why: the URL of an
/// *attached* preview is whatever the sender encoded into the file, and nothing between the file and here compares it against the link in the message body. It
/// therefore goes to `actions.userWantsToOpenURLFromAMessage(_:)`, which reaches `UIApplication.userSelectedURL(_:within:)` — the one place that refuses a scheme
/// outside `https`/`tel`/`calshow` and asks the reader before leaving the app. It went straight to the environment's `openURL` until 2026-09-01, which opened a
/// sender-chosen URL, of any scheme, on a single tap and without a word. The body of a message has always been careful here (see `MessageBodyView`); the card was
/// the one part of a message that was not.
struct LinkPreviewView: View {

    let source: LinkPreviewInMessage

    /// Whether whatever holds the metadata can be read now.
    ///
    /// False for an attachment whose file has not arrived, and always true for a preview still to be fetched — there is no file to wait for there, the fetch
    /// being what the request itself sets off.
    let theMetadataCanBeRead: Bool

    let dataSource: any SingleDiscussionCellViewDataSource

    /// Where a tap on the card goes. **Not** the environment's `openURL`: see this view's own documentation, and `MessageBodyView`, which installs an
    /// `OpenURLAction` over its text for the same reason. A card is a sibling of that text rather than a descendant of it, so the body's action never covered it.
    let actions: any SingleDiscussionCellViewActions

    @State private var metadata: LinkPreviewMetadata?

    @Environment(\.displayScale) private var displayScale

    /// `SinglePreviewView.cellSize.width`.
    static let width = CGFloat(280)

    /// Half the width, which is what the legacy screen reserves for a preview that is still coming.
    private static let heightWhileItIsComing = width / 2

    /// `SinglePreviewView`'s 40×40 `iconPreviewImageView`.
    private static let sideOfTheIcon = CGFloat(40)

    /// `titleEdges` of the legacy screen — 8 above and below, 15 either side.
    private static let horizontalInsetOfTheLabels = CGFloat(15)
    private static let verticalInsetOfTheLabels = CGFloat(8)

    /// Between the description and the row beneath it, and between the icon and the labels beside it. Both are 8 on the legacy screen.
    private static let gap = CGFloat(8)

    /// `ObvMessengerConstants.LinkPreview.numberOfLinesForDescriptions`. Lifted for the few domains whose preview *is* the text of a post — which the app decides,
    /// holding the list, and says through ``LinkPreviewMetadata/showsTheWholeDescription``.
    private static let numberOfLinesOfTheDescription = 5

    /// 14pt, and **not** scaled by the reader's text size: the legacy screen builds these three fonts with `UIFont(descriptor:size: 14)`, which fixes them. Kept
    /// as it is, this step being a transcription of that screen; making the whole cell scale is one decision to take at once rather than font by font.
    private static let textFont = Font.system(size: 14, design: .rounded)
    private static let titleFont = Font.system(size: 14, weight: .bold, design: .rounded)

    /// What is asked for: the width of the card, in pixels. An icon is over-served by it and costs nothing, being under 400px by the very definition that makes it
    /// an icon.
    private var maxPixelSize: Int {
        Int(Self.width * displayScale)
    }

    var body: some View {
        // A single-root container, so that this view stays *unary* whichever of its states it is in. See `SingleDiscussionCellView`.
        VStack(spacing: 0) {
            if let card {
                pictureAtTheTop(of: card)
                labels(of: card)
            } else if showsThePlaceholderWhileItIsComing {
                placeholder
            }
        }
        .frame(width: Self.width)
        .background(card == nil ? Color(UIColor.systemFill) : Color(UIColor.secondarySystemBackground))
        .contentShape(.rect)
        .onTapGesture {
            guard let url = card?.url else { return }
            Task { await actions.userWantsToOpenURLFromAMessage(url) }
        }
        .task(id: TaskIdentity(source: source, theMetadataCanBeRead: theMetadataCanBeRead, maxPixelSize: maxPixelSize)) {
            await asksForTheMetadata()
        }
    }


    /// What is drawn, and from which of the two sources there are.
    ///
    /// **The shape decides whenever there is one**, which is every attached preview whose file has arrived — so the text, the domain and the space the picture will
    /// occupy are all there on the first frame, and the metadata that follows only fills the pictures in. Where there is no shape, the metadata is the only source
    /// there has ever been: a preview still to be *fetched* cannot be described before it is fetched.
    ///
    /// Nil means nothing is drawn — a preview that has not been read yet, or one that turns out to say nothing at all.
    private var card: Card? {
        if case .attached(_, let shape) = source, let shape {
            guard !shape.saysNothing else { return nil }
            return .init(shape: shape, pictures: metadata?.image)
        }
        guard let metadata, !metadata.saysNothing else { return nil }
        return .init(metadata: metadata)
    }


    /// Whether the space of a preview is held while it is being read.
    ///
    /// An attachment is on its way and will arrive, so it is given its 280×140 and a spinner, as on the legacy screen. A preview still to be *fetched* may never
    /// exist — the site may answer nothing — so it is given no space at all until it does, which is also what the legacy screen does with a message whose preview
    /// has not been created yet: it shows nothing, and grows when one appears.
    private var showsThePlaceholderWhileItIsComing: Bool {
        switch source {
        case .attached: return true
        case .toBeFetched: return false
        }
    }


    /// The space held while an attached preview is on its way — 280×140 and a spinner, as on the legacy screen.
    ///
    /// At its **own** size, and not `.large`: SwiftUI's large circular indicator is markedly bigger than the 37pt of the legacy `UIActivityIndicatorView(style: .large)`,
    /// and in a box this size it read as a loading screen rather than as a card filling in.
    private var placeholder: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .frame(width: Self.width, height: Self.heightWhileItIsComing)
    }


    /// The picture, the full width of the card and as tall as its own proportions make it — and nothing at all when the preview carries none, or carries one small
    /// enough to belong beside the title instead.
    ///
    /// **The space is held whether or not the picture is here**, which is what the aspect ratio in the shape is for: the card is its final height from the first
    /// frame, and the picture appears inside a box that was already the right one — exactly as a photograph does on this screen.
    private func pictureAtTheTop(of card: Card) -> some View {
        VStack(spacing: 0) {
            if case .large(let aspectRatio, let image) = card.picture, aspectRatio > 0 {
                Color(UIColor.systemFill)
                    .frame(width: Self.width, height: Self.width / aspectRatio)
                    .overlay {
                        if let image {
                            Image(decorative: image, scale: displayScale)
                                .resizable()
                                .scaledToFill()
                        }
                    }
                    .clipped()
            }
        }
    }


    private func labels(of card: Card) -> some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            if let desc = card.desc {
                Text(verbatim: desc)
                    .font(Self.textFont)
                    .foregroundStyle(Color(UIColor.label))
                    .lineLimit(card.showsTheWholeDescription ? nil : Self.numberOfLinesOfTheDescription)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .top, spacing: Self.gap) {
                if case .icon(let image) = card.picture {
                    Color(UIColor.systemFill)
                        .frame(width: Self.sideOfTheIcon, height: Self.sideOfTheIcon)
                        .overlay {
                            if let image {
                                Image(decorative: image, scale: displayScale)
                                    .resizable()
                                    .scaledToFit()
                            }
                        }
                }
                VStack(alignment: .leading, spacing: 0) {
                    if let title = card.title {
                        Text(verbatim: title)
                            .font(Self.titleFont)
                            .foregroundStyle(Color(UIColor.label))
                    }
                    if let domain = card.domain {
                        Text(verbatim: domain)
                            .font(Self.textFont)
                            .foregroundStyle(Color(UIColor.secondaryLabel))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, Self.horizontalInsetOfTheLabels)
        .padding(.vertical, Self.verticalInsetOfTheLabels)
    }


    /// What the card draws, gathered from whichever source could say — so that there is one drawing path and not two.
    private struct Card {

        let title: String?
        let desc: String?
        let domain: String?
        let url: URL?
        let showsTheWholeDescription: Bool
        let picture: Picture

        /// The space a picture takes, and the picture if it has been decoded yet. The two are separate here and joined in ``LinkPreviewMetadata``, which is the
        /// whole point: the space is known from the message's model, and the picture arrives afterwards.
        enum Picture {
            case none
            case icon(CGImage?)
            case large(aspectRatio: CGFloat, image: CGImage?)
        }

        /// From the message's own account of the preview, with the pictures if they have arrived.
        init(shape: LinkPreviewShape, pictures: LinkPreviewImage?) {
            self.title = shape.title
            self.desc = shape.desc
            self.domain = shape.domain
            self.url = shape.url
            self.showsTheWholeDescription = shape.showsTheWholeDescription
            switch shape.picture {
            case .none:
                self.picture = .none
            case .icon:
                // Taken only when the metadata agrees about *which* kind of picture there is. It always does — both answers are read from one file by one rule —
                // and were they ever to disagree, the shape is the one the row was measured from.
                if case .icon(let image) = pictures {
                    self.picture = .icon(image)
                } else {
                    self.picture = .icon(nil)
                }
            case .large(let aspectRatio):
                if case .large(let image, _) = pictures {
                    self.picture = .large(aspectRatio: aspectRatio, image: image)
                } else {
                    self.picture = .large(aspectRatio: aspectRatio, image: nil)
                }
            }
        }

        /// From the metadata alone, which is all there is for a preview still to be fetched.
        init(metadata: LinkPreviewMetadata) {
            self.title = metadata.title
            self.desc = metadata.desc
            self.domain = metadata.domain
            self.url = metadata.url
            self.showsTheWholeDescription = metadata.showsTheWholeDescription
            switch metadata.image {
            case .none:
                self.picture = .none
            case .icon(let image):
                self.picture = .icon(image)
            case .large(let image, let aspectRatio):
                self.picture = .large(aspectRatio: aspectRatio, image: image)
            }
        }

    }


    private func asksForTheMetadata() async {
        guard theMetadataCanBeRead else { return }
        let read = await dataSource.linkPreviewMetadata(for: source, maxPixelSize: maxPixelSize)
        guard let read else { return }
        metadata = read
    }


    /// What makes the request worth making again — including the source itself, since a row is a view SwiftUI reuses for whatever message comes to occupy it.
    private struct TaskIdentity: Hashable {
        let source: LinkPreviewInMessage
        let theMetadataCanBeRead: Bool
        let maxPixelSize: Int
    }

}
