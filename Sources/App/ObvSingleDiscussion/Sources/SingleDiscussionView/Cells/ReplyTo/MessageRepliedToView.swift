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
import ObvDesignSystem


/// The header above a message that answers another one: a bar in the answered sender's colour, a picture of what they attached, their name, and what they said.
///
/// **The arrangement is the new design's and the colours are the legacy screen's.** `ReplyToBubbleView` stacks the name *above* a row of thumbnail-and-body; the design
/// puts the picture first and the two lines beside it, and writes the bare name where legacy writes the sentence "Replying to David". The thumbnail is legacy's own
/// 40pt; the bar is not — the design draws it at 4pt where `MessageCellConstants.replyToLineWidth` is 6, and it is the one metric here that departs from legacy.
///
/// One thing of legacy's is deliberately dropped: a body of three emoji or fewer was drawn there at 40pt. That fits a bubble free to grow and not a header of two
/// lines.
struct MessageRepliedToView: View {

    let repliedTo: MessageRepliedTo

    let dataSource: any SingleDiscussionCellViewDataSource
    let actions: any SingleDiscussionCellViewActions

    @Environment(\.displayScale) private var displayScale

    /// How the list is asked to take the reader to the message being answered. See ``WhereTheReaderWantsToGo``.
    @Environment(\.whereTheReaderWantsToGo) private var whereTheReaderWantsToGo

    private var colors: MessageRepliedToStyle { .init(sender: repliedTo.sender) }

    var body: some View {
        // Tappable only when there is somewhere to go, which the model says by carrying a row: a message that was deleted or has not arrived is quoted by a sentence
        // and nothing more. `.buttonStyle(.plain)`, without which a `List` row takes the tap for itself and the action never runs.
        //
        // What is hidden behind the message is not hittable, so a tap there belongs to the message. Which is right: the part of the header a reader can see is the part
        // they can act on.
        if let row = repliedTo.rowOfTheMessageRepliedTo, let whereTheReaderWantsToGo {
            Button {
                whereTheReaderWantsToGo.goTo(row)
            } label: {
                header
            }
            .buttonStyle(.plain)
        } else {
            header
        }
    }


    private var header: some View {
        AtMostAFractionOfTheOfferedWidth(fraction: MessageBubbleMetrics.maxWidthRatio) {
            HStack(spacing: 0) {
                // The bar down the leading edge, in the answered sender's colour, the full height of the header — `line` in the legacy view.
                colors.bar
                    .frame(width: MessageRepliedToMetrics.barWidth)
                whatIsQuoted
                    .padding(.horizontal, MessageBubbleMetrics.horizontalInset - MessageRepliedToMetrics.barWidth / 2)
                    .padding(.vertical, MessageBubbleMetrics.verticalInset)
            }
            .background(fillBehindTheHeader)
            .clipShape(MessageBubbleMetrics.shape)
            // The thin line the design draws all around the card, and the only thing that separates a header from a message in **light** mode: a fill can be stepped
            // towards the page in the dark, where there is room between a bubble and black, but a light bubble on a white page has nowhere to go. A line has, being ink
            // rather than surface. `separator` is the system's own hairline, translucent and adapting on its own, so it reads against either appearance.
            //
            // Drawn after the clip and inset by half its width, so all of it lands inside the shape — and hidden where the message covers the header, which is what
            // being behind should look like.
            .overlay {
                MessageBubbleMetrics.shape
                    .strokeBorder(Color(UIColor.separator), lineWidth: MessageRepliedToMetrics.widthOfTheLineAround)
            }
        }
    }


    /// What the header is drawn on: the page, the bubble's own colour, and **one step back towards the page over it**.
    ///
    /// Three layers, and each earns its place. The app theme gives the reply-to background and the bubble background the *same* value — `systemFill` in dark,
    /// `EdmondSurfaceDark` in light — so nothing whatever distinguished a header from the message in front of it. The step is taken towards the **page**, which is the
    /// direction "behind" means in either appearance: the thing further away recedes towards the background, so a header comes out darker than the message in dark
    /// mode and lighter than it in light mode, always the one of the two that is nearer the page. The page underneath makes the whole opaque, as it does for a bubble,
    /// so the message can be drawn over it cleanly.
    ///
    /// **How far it steps is not one number.** It depends on the appearance and on who wrote the message being answered, which is why the layers are a view of their
    /// own — a colour scheme is read by a `View` and not by a computed property here. See `FillBehindTheHeader` and
    /// ``MessageRepliedToMetrics/stepBackTowardsThePage(for:colorScheme:)``.
    private var fillBehindTheHeader: some View {
        FillBehindTheHeader(sender: repliedTo.sender, fill: colors.fill)
    }


    /// The picture, and the two lines beside it.
    ///
    /// **It hugs what it quotes**, between ``MessageRepliedToMetrics/leastWidth`` and whatever ``AtMostAFractionOfTheOfferedWidth`` allows — which is legacy's own
    /// arrangement, four constraints saying *at most the bubble's maximum, at least 100pt, and otherwise wide enough for the name and for the body*, commented
    /// there as *"expands as much as possible to show the name, thumbnail, and body"*.
    ///
    /// **It used to end in `.frame(maxWidth: .infinity, alignment: .leading)`, which made it greedy**, so a two-word quote was drawn as wide as the longest one
    /// the screen allows — reported by the reader on 2026-08-28. The cap above it was innocent and says so in its own documentation: it *"lets it be as narrow as
    /// it likes"*. Nothing else wanted the width, the column being left-aligned by the `VStack` and the bar by being first in the row.
    private var whatIsQuoted: some View {
        // `.top`, as the legacy horizontal stack is: a body of two lines grows downwards from the picture rather than centring against it.
        HStack(alignment: .top, spacing: MessageRepliedToMetrics.gapBesideThePicture) {
            if let thumbnail = repliedTo.thumbnail {
                picture(of: thumbnail)
            }
            VStack(alignment: .leading, spacing: MessageRepliedToMetrics.gapBetweenTheLines) {
                if let name = repliedTo.sender.name {
                    Text(verbatim: name)
                        .font(MessageSenderMetrics.fontOfTheName)
                        .foregroundStyle(colors.name)
                        .lineLimit(1)
                }
                whatItSays
            }
        }
        // Leading, so that what little there is stays against the bar rather than centring in the floor's width.
        .frame(minWidth: MessageRepliedToMetrics.leastWidth, alignment: .leading)
    }


    /// What the answered message says, or what became of it — and nothing at all when it has nothing to say, which is a message of attachments alone whose file has no
    /// name to show.
    @ViewBuilder private var whatItSays: some View {
        if let sentence {
            sentence
                .font(.body)
                .foregroundStyle(colors.words)
                // Two lines, as `bodyLabel` allows, so that a long message is quoted by its beginning rather than by one line of it.
                .lineLimit(MessageRepliedToMetrics.numberOfLinesOfWhatItSays)
        }
    }


    /// The sentence of the second line. The words of the message itself are drawn verbatim; the three states it may be in instead are worded here, as the wiped bubble
    /// words its own.
    private var sentence: Text? {
        switch repliedTo.whatItSays {
        case .theseWords(let words):
            return words.isEmpty ? nil : Text(verbatim: words)
        case .itWasWipedBy(contactNamed: let contactName):
            if let contactName {
                return Text("WIPED_MESSAGE_BY_\(contactName)")
            } else {
                return Text("Remotely wiped")
            }
        case .itWasDeleted:
            return Text("Deleted message")
        case .itIsNotHereYet:
            return Text("UNAVAILABLE_MESSAGE")
        }
    }


    /// The picture of what the answered message had attached.
    ///
    /// Through `FollowedAttachment`, as every other attachment of this screen is, so that a picture already decoded is shown at once and one still on its way appears
    /// when it lands. **Without the state control and without the viewer**: a header is a quotation, so there is nothing here to download and nothing to open — the
    /// legacy thumbnail is inert in exactly the same way.
    private func picture(of thumbnail: MessageAttachment) -> some View {
        let side = MessageRepliedToMetrics.sideOfThePicture
        let size = CGSize(width: side, height: side)
        let pixelSize = CGSize(width: side * displayScale, height: side * displayScale)
        return FollowedAttachment(attachment: thumbnail,
                                  sizeToRequest: size,
                                  initialImage: dataSource.cachedImageForAttachment(thumbnail, pixelSize: pixelSize),
                                  dataSource: dataSource,
                                  actions: actions,
                                  showsTheStateControl: false) { image, _ in
            Color.secondary.opacity(0.15)
                .overlay {
                    if let image {
                        Image(decorative: image, scale: displayScale)
                            .resizable()
                            .scaledToFill()
                    }
                }
        }
        .frame(width: side, height: side)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: MessageRepliedToMetrics.cornerRadiusOfThePicture, style: .continuous))
    }

}


/// The three layers behind a reply header, in a view of their own because the step towards the page is not the same in the two appearances, and only a `View` can read
/// the colour scheme. It is used through `.background(...)`, which inherits the environment, so the appearance it reads is the one the header is drawn in.
private struct FillBehindTheHeader: View {

    let sender: MessageRepliedTo.Sender
    let fill: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MessageBubbleMetrics.shape
            .fill(Color(UIColor.systemBackground))
            .overlay { MessageBubbleMetrics.shape.fill(fill) }
            .overlay { MessageBubbleMetrics.shape.fill(Color(UIColor.systemBackground).opacity(MessageRepliedToMetrics.stepBackTowardsThePage(for: sender, colorScheme: colorScheme))) }
    }

}


/// The colours of a reply header, which come from whoever wrote the message being answered — the legacy screen's, case for case.
struct MessageRepliedToStyle {

    let sender: MessageRepliedTo.Sender

    /// The bar down the leading edge.
    var bar: Color {
        switch sender {
        case .aContact(name: _, color: let color): return color
        case .theReader: return Color(AppTheme.shared.colorScheme.adaptiveOlvidBlueReversed)
        case .aContactNoLongerKnown, .nobody: return Color(UIColor.systemFill)
        }
    }

    /// The fill of the whole header.
    var fill: Color {
        switch sender {
        case .theReader: return Color(AppTheme.shared.colorScheme.adaptiveOlvidBlue)
        case .aContact, .aContactNoLongerKnown, .nobody: return Color(AppTheme.shared.colorScheme.newReceivedCellReplyToBackground)
        }
    }

    /// The name on the first line.
    ///
    /// White on the reader's own blue, as legacy has it. For a contact who can no longer be found legacy is white **too**, over its light reply-to background — which
    /// is a defect rather than a decision: unreadable in light mode.
    ///
    /// Such a contact takes the **secondary** label, which is dynamic and therefore right in both appearances, and which reads as what it is: a name nobody can be
    /// given rather than a name. It is the same colour the line under it has, and the same a message with nobody at all to name gets.
    var name: Color {
        switch sender {
        case .aContact(name: _, color: let color): return color
        case .theReader: return Color(UIColor.white)
        case .aContactNoLongerKnown, .nobody: return Color(UIColor.secondaryLabel)
        }
    }

    /// What the message said, on the second line.
    ///
    /// The secondary label, a quotation being secondary to the message that quotes it — and on the reader's own blue that same colour resolved *against a dark
    /// appearance*, as legacy resolves it, a secondary label being made for a dark surface rather than for a blue one.
    ///
    /// **In light mode on that blue it is white instead, and nothing less will do.** Legacy's trick was said here to keep the words legible on blue whatever the
    /// appearance, and it does not: the dark secondary label is white at three fifths, which comes to 4.3:1 over the `#003396` a header reaches in dark mode and to
    /// **1.9:1** over the `#628BF8` it reaches in light mode — that blue with a quarter of the white page over it, reported as unreadable and measured as such. Full
    /// white is 3.2:1 on it, the most that surface allows, the same the bold name above it has always had, and what every other word this screen draws on Olvid blue
    /// already takes: the body of a sent message is `UIColor.white`. So the light appearance gives up the secondary tone and lets the two fonts' weights say which
    /// line is the name and which the quotation. The surface is the other half of it — a header of the reader's own is the one case where the step towards the page
    /// pales the very colour the words need, see ``MessageRepliedToMetrics/stepBackTowardsThePage(for:colorScheme:)``.
    ///
    /// It depends on the message being *answered* and not on the message doing the answering: a header keeps its own fill inside either kind of cell, exactly as it
    /// does on the legacy screen.
    var words: Color {
        switch sender {
        case .theReader:
            // Resolved per appearance rather than from the environment: a style is a plain value, built wherever a view wants one.
            return Color(UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor.secondaryLabel.resolvedColor(with: .init(userInterfaceStyle: .dark)) : UIColor.white
            })
        case .aContact, .aContactNoLongerKnown, .nobody:
            return Color(UIColor.secondaryLabel)
        }
    }

}


/// Metrics of a reply header. Most of these values are the legacy screen's, see `MessageCellConstants` and `ReplyToBubbleView`; ``barWidth`` is the design's own and
/// says so where it is declared.
enum MessageRepliedToMetrics {

    /// The bar down the leading edge, **4pt, which is the design's and not legacy's** — `MessageCellConstants.replyToLineWidth` is 6.
    ///
    /// It is what the content's horizontal inset is measured against, `horizontalInset - barWidth / 2`, so taking the bar in by two points pushes that inset out by
    /// one. And the header's corners clip it: at a ``MessageBubbleMetrics/cornerRadius`` of 14 a narrower bar is cut away over more of its top and bottom than
    /// legacy's was, so it tapers out earlier.
    static let barWidth: CGFloat = 4

    /// `MessageCellConstants.replyToImageSize`
    static let sideOfThePicture: CGFloat = 40

    /// The 8pt of the legacy `horizontalStack`.
    static let gapBesideThePicture: CGFloat = 8

    /// The 4pt of the legacy `mainStack`.
    static let gapBetweenTheLines: CGFloat = 4

    /// The rounding of the picture, `imageView.layer.cornerRadius` there.
    static let cornerRadiusOfThePicture: CGFloat = 8

    /// `bodyLabel.numberOfLines`
    static let numberOfLinesOfWhatItSays: Int = 2

    /// How far the bubble of the message covers the bottom of the header behind it.
    ///
    /// **This is the one place on this screen where a stack is given a negative spacing, and it is not a fudge**: the header is *behind* the message, and an overlap is
    /// what that means. It is applied as `spacing: -overlap` in the two cells, where the message follows the header in the stack and is therefore drawn over it. The
    /// rule it looks like it breaks — see ``MessageBubbleMetrics/gapAboveTheDateRow`` — is about a gap that looks too large, which is never solved by pulling views
    /// together.
    ///
    /// Eight points, which is the air below the picture inside the header: enough that the header's bottom corners disappear behind the bubble, and not enough to touch
    /// what the header draws.
    static let overlapUnderTheBubble: CGFloat = 8

    /// How far the header's fill is taken back towards the page, away from the message's — see ``MessageRepliedToView/fillBehindTheHeader``.
    ///
    /// **A quarter everywhere except a contact's message in light mode, which takes three**, and what separates the two is how much room the step has to travel in.
    /// In dark mode a received bubble is itself only a little way from the page — `systemFill` over black comes to about `#2B2B2E` — so a quarter of the page over it
    /// is a visible step, where a tenth would have moved it by two or three values and been invisible and a tenth of the *ink* would have moved it by twenty. Going
    /// the way the design asks for costs a larger number to travel a shorter distance.
    ///
    /// **In light mode there is almost no distance at all**, which is the part to know before anyone tunes this. The header's colour and the bubble's are the same
    /// asset, `EdmondSurfaceDark`, 245 on a scale of 255, and the page is white: the whole of the room the step has is ten values. A quarter of it left the header at
    /// 247.5, two and a half values off the message; three quarters puts it at 252.5, which is the page to within one percent of luminance. So in light mode the fill
    /// is not what separates a header from the discussion behind it — the hairline around it is, being ink rather than surface, and it is the only thing that can
    /// separate two surfaces this close together.
    ///
    /// The reader's own messages keep the quarter in both appearances: their blue is far from either page, so a small step reads on it. What that quarter costs is
    /// the words drawn over it, `#2E64F5` becoming `#628BF8` in light mode — see ``MessageRepliedToStyle/words``.
    static func stepBackTowardsThePage(for sender: MessageRepliedTo.Sender, colorScheme: ColorScheme) -> CGFloat {
        switch sender {
        case .theReader:
            return 0.25
        case .aContact, .aContactNoLongerKnown, .nobody:
            return colorScheme == .dark ? 0.25 : 0.75
        }
    }

    /// The thin line all around the header, which the design draws and which is what tells a header from a message in light mode.
    static let widthOfTheLineAround: CGFloat = 1

    /// The narrowest a header is drawn, however little it quotes — `MessageCellConstants.replyToBubbleMinWidth`.
    ///
    /// Measured on the content, as legacy measures it: this is the floor on the picture and the lines beside it, and the horizontal insets and the bar are outside
    /// it. A quote of one word would otherwise be a sliver, and a card narrower than it is tall reads as a fragment rather than as something quoted.
    static let leastWidth: CGFloat = 100

}


extension MessageRepliedTo.Sender {

    /// The name to draw, and nil when there is nobody to name.
    var name: String? {
        switch self {
        case .aContact(name: let name, color: _): return name
        case .aContactNoLongerKnown(name: let name): return name
        case .theReader(name: let name): return name
        case .nobody: return nil
        }
    }

}


#if DEBUG

/// Every shape a header takes, in light mode — where a colour taken from a dark mock is most likely to be wrong.
#Preview {
    MessageRepliedToHeadersForPreviews()
}


/// The same in dark mode, which is the appearance the design was drawn in.
#Preview {
    MessageRepliedToHeadersForPreviews()
        .preferredColorScheme(.dark)
}


private struct MessageRepliedToHeadersForPreviews: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MessageRepliedTo.sampleData.enumerated()), id: \.offset) { _, repliedTo in
                MessageRepliedToView(repliedTo: repliedTo,
                                     dataSource: singleDiscussionCellViewDataSourceForPreviews,
                                     actions: singleDiscussionCellViewDataSourceForPreviews)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        // The background of a discussion, which the headers are drawn against and must stay legible on.
        .background(Color(UIColor.systemBackground))
    }

}

#endif
