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
import ObvAppTypes

struct ProfileAndRecipientsView: View {

    var model: ShareExtensionView.Model
    var avatarDataSource: ObvAvatarViewDataSource
    var singleRecipientSummaryViewDataSource: any SingleRecipientSummaryViewDataSource
    @ObservedObject var sharedState: SharedState

    @Binding var showOwnedIdentityChooserView: Bool
    @Binding var showDiscussionChooserView: Bool

    /// Namespace owned by `ShareExtensionView`, which applies the matching transition to the sheet each row
    /// presents. Shared so the sheet appears to grow out of the row that opened it.
    let chooserNamespace: Namespace.ID

    /// Identifies the card as the zoom-transition source.
    ///
    /// **One case, because there is one source view.** Both sheets would grow from the same card, and nothing requires
    /// an id to serve a single destination — the two choosers are never presented at once. It replaced a case per row
    /// because a row stopped being a view when the label became a grid cell of its own (see ``card``), and two
    /// `matchedTransitionSource` modifiers stacked on one view cannot be expected to register anyway, the outer one
    /// being applied to a view that is already a source.
    ///
    /// **The Xcode preview does not render a sheet's zoom transition, and that cost an afternoon.** In the preview the
    /// sheet slides up from the bottom — on this code, and equally on the code before the card became a grid — which
    /// read as a regression and was chased as one through three changes. It animates correctly on a simulator, checked
    /// on 2026-09-02. So the instrument was the fault and not the code, twice over: it showed nothing working, and it
    /// showed nothing working *before* the change either, which is the only reason the mistake was caught.
    ///
    /// Two things follow, and they are the reason this note is here rather than in a commit message. **Judge this
    /// transition on a simulator, through the real share sheet, never in a preview** — a preview that cannot render a
    /// thing cannot be asked whether the thing broke. And **establish the baseline before believing in a regression**:
    /// the source's placement was never the cause of anything, and one run of the committed code would have said so at
    /// the outset.
    enum ChooserTransitionSource: Hashable {
        case card
    }

    @ViewBuilder
    private func profileIcon(imageOrIcon: SharedState.ImageOrIcon) -> some View {
        ProfileIconView(imageOrIcon: imageOrIcon, avatarDataSource: avatarDataSource)
    }

    @ViewBuilder
    private func buttonContainerIfNeeded(action: (@MainActor () -> Void)? = nil,
                                         actionAvailable: Bool,
                                         @ViewBuilder label: () -> any View) -> some View {
        if actionAvailable, let action {
            Button(action: action) {
                AnyView(label())
            }
            .disabled(sharedState.isSending)
        } else {
            AnyView(label())
        }
    }
    
    var body: some View {
        // Hug the content when it fits the available width; only grow (and truncate the names) when it
        // would otherwise overflow. `ViewThatFits` picks the fixed-size (hugging) layout when it fits,
        // otherwise falls back to the flexible layout that fills the width and lets the names truncate.
        ViewThatFits(in: .horizontal) {
            card.fixedSize()
            card
        }
    }

    /// The two rows, as a two-column grid: the labels in the first column, everything else in the second.
    ///
    /// **The design asks for one thing only — that the two avatar circles share a leading edge** — and that is a
    /// constraint *across* the rows, so no arrangement of each row on its own can satisfy it. What has to be equal is
    /// the width of the label column; once it is, everything to its right lines up for free, the avatar being a fixed
    /// diameter and the chevrons being pushed out by a `Spacer`. So the grid needs two columns rather than four.
    ///
    /// **`Grid` rather than two `VStack`s side by side**, which is the shorter thing that looks like it would work: a
    /// `VStack(alignment: .trailing)` of the two labels is naturally as wide as the wider of them and trailing-aligns
    /// them, and a `VStack` of the two rows beside it would put both avatars at the same x. But the two columns would
    /// then have *independent* row heights — a label is one line of `.subheadline`, a row is the avatar's diameter —
    /// so each label would sit at its own vertical offset and no longer line up with the row it names. Sizing and
    /// aligning cells across **both** axes is precisely what a `Grid` does and what the lazy grids cannot, because it
    /// holds every view at once rather than only the visible ones.
    private var card: some View {

        Grid(alignment: .leading, horizontalSpacing: 8.0, verticalSpacing: 10.0) {

            GridRow {
                Text("SHARE_PROFILE_TITLE")
                    .font(.subheadline)
                    // Trailing-aligns the *whole* first column: per WWDC22, `gridColumnAlignment` applied to any one
                    // cell sets the alignment of every cell in that column, so it is deliberately written once here
                    // and not repeated on the row below. The grid's own `.leading` covers the second column.
                    .gridColumnAlignment(.trailing)

                profileCell
            }

            GridRow {
                Text("SHARE_RECIPIENTS_TITLE")
                    .font(.subheadline)

                recipientsCell
            }

        }
        // **One source, on the card**, rather than one per row: a row stopped being a view when the label became a
        // cell of its own, so there is nothing row-shaped left to mark. So a sheet grows out of the whole card rather
        // than out of the row that was tapped, which is the one thing this arrangement gives up — there being no way
        // to keep per-row precision, a row-spanning source having to be the button again, which is precisely what a
        // label cell of its own cannot coexist with.
        //
        // One `matchedTransitionSource` and one id, because two stacked on a single view cannot both register: the
        // outer would be applied to a view that is already a source. Both sheets share the id, which is fine — they
        // are never presented at once. See ``ChooserTransitionSource``.
        .matchedTransitionSourceOnIOS18(id: ChooserTransitionSource.card, in: chooserNamespace)
        .foregroundStyle(.secondary)
        .padding(16)
        .glassRoundedRectangleStyle(cornerRadius: 16)
    }


    /// Everything on the profile row except its label: the avatar, the name, and the chevron when there is somewhere
    /// to go.
    ///
    /// **The label is no longer inside the button**, and it could not be: it has to be a cell of its own for the grid
    /// to give the column a common width, and a `Button` wrapping the row would occupy a single cell and take that
    /// width away. What it costs is the label's own width as a tap target — about 40pt of a row that keeps the avatar,
    /// the name and the chevron, which is how a form row behaves anyway.
    private var profileCell: some View {
        buttonContainerIfNeeded(action: { showOwnedIdentityChooserView.toggle() },
                                actionAvailable: model.hasMultipleOwnedIdentities) {
            HStack(spacing: 8.0) {

                if let fromIdentityAvatar = model.fromIdentityAvatar {
                    profileIcon(imageOrIcon: .avatarModel(fromIdentityAvatar))
                } else {
                    profileIcon(imageOrIcon: .icon(Image(systemIcon: .personFillBadgePlus)))
                }

                Group {
                    if let fromIdentityText = model.fromIdentityText {
                        Text(fromIdentityText)
                    } else {
                        Text("SHARE_PROFILE_SELECT")
                    }
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

                if model.hasMultipleOwnedIdentities {
                    Spacer()
                    // `Text(Image(...))` rather than a bare `Image`: an image is laid out as an image, and its
                    // box is taller than a line of the font it was given, so beside text it makes the row taller
                    // than one line box. As a glyph on the line the row is exactly one line box tall whatever it
                    // carries. It also takes its size from the font rather than from `imageScale`, which is why
                    // that modifier is gone: the chevron is now the same size as the labels it sits with, where
                    // `.small` looked undersized against `.subheadline`.
                    Text(Image(systemIcon: .chevronRight))
                        .font(.subheadline)
                }
            }
        }
    }


    /// Everything on the recipients row except its label. See ``profileCell`` for why the label is not in here.
    ///
    /// `RecipientsSummaryView` stays one cell, avatar and title together: only the label column has to be sized by the
    /// grid, and the names align on their own because the avatar beside them is a fixed diameter.
    private var recipientsCell: some View {
        buttonContainerIfNeeded(action: { showDiscussionChooserView.toggle() },
                                actionAvailable: model.hasAtLeastOneDiscussionAvailable) {
            HStack(spacing: 8.0) {

                RecipientsSummaryView(
                    selectedDiscussionIdentifiers: sharedState.selectedDiscussionIdentifiers,
                    dataSource: singleRecipientSummaryViewDataSource,
                    avatarDataSource: avatarDataSource
                )

                if model.hasAtLeastOneDiscussionAvailable {
                    Spacer()
                    // See the profile row above for why this is a `Text` and carries no `imageScale`.
                    Text(Image(systemIcon: .chevronRight))
                        .font(.subheadline)
                }
            }
        }
    }

}


// MARK: - Profile icon

/// The small circular avatar/icon used by both the "From:" and "To:" rows.
private struct ProfileIconView: View {

    let imageOrIcon: SharedState.ImageOrIcon
    let avatarDataSource: any ObvAvatarViewDataSource

    /// The circle's diameter, grown with the reader's text size.
    ///
    /// A hard 30pt is balanced beside `.subheadline` labels at the default setting and steadily too small above
    /// it. The label it sits next to is the only way to know who the message is going to, so it *must* scale —
    /// which is the opposite of the fixed-container rule, and means the container has to follow or the row stops
    /// reading as an icon-and-name pair. `relativeTo: .subheadline` so it grows in step with the text beside it
    /// rather than with `.body`, and one property so the frame and the avatar's own size cannot drift apart.
    @ScaledMetric(relativeTo: .subheadline) private var diameter: CGFloat = 30.0

    var body: some View {
        ZStack(alignment: .center) {
            switch imageOrIcon {
            case .avatarModel(let avatarModel):
                ObvAvatarView(model: avatarModel,
                              style: .circle,
                              size: .custom(frameSize: CGSize(width: diameter, height: diameter)),
                              dataSource: avatarDataSource)
            case .icon(let image):
                // Left as an `Image` deliberately: it is centred inside the circle rather than set beside text, so
                // the line-box concern that applies to the chevrons does not arise here. An SF Symbol takes its
                // size from the environment's font, which already scales, so it keeps pace with the circle.
                image
                    .imageScale(.small)
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: diameter, height: diameter)
        .background(Color.clear)
        .clipShape(Circle())
        .overlay {
            // `separator` rather than `secondary`, at the designer's request that this ring be *"une couleur
            // secondaire un peu plus discrète"*: `Color.secondary` resolves to `secondaryLabel`, which is a colour for
            // reading text and far too present for a hairline. `separator` is the system's semantic colour for a line
            // meant to be seen and not noticed, and it adapts to light and dark on its own. The same choice as
            // `TheShortcutThatAppearsOnHover`, which rings a circle this way, and as `LinkMetadataView`, which borders
            // its card with it.
            //
            // `strokeBorder` rather than `stroke`: a stroke is centred on the path, so half its width falls outside
            // the frame — which both grows the circle's visual bounds and leaves the photograph's own antialiased edge
            // showing through beneath it. A border is drawn wholly inside, so it covers that edge. The glass styles in
            // this module already use `strokeBorder` for the same reason, and at a full point the difference is half a
            // point of ring rather than a quarter, so it matters more here than it would at a hairline.
            //
            // **1pt rather than the conventional 0.5**, because 0.5 is not a crisp line on the devices we ship to: at
            // 3× it is one and a half physical pixels, so it is antialiased across two rows and renders paler and
            // softer than asked for — and differently from a 2× screen, where it lands on exactly one pixel. 1pt is a
            // whole number of pixels on both. It does spend most of the weight the colour change above saved — ink
            // being roughly width × alpha, so 0.30 with `secondary` at half a point, 0.125 with `separator` at half a
            // point, and 0.25 here — and it is still the better trade, because a *wider, paler* line reads as less
            // conspicuous than a *narrower, darker* one at the same ink, and because the placeholder circle has
            // nothing inside it: there the ring is the whole of the shape and has to hold it.
            Circle()
                .strokeBorder(Color(uiColor: .separator), lineWidth: 1.0)
        }
    }
}


// MARK: - Recipients summary (To: row)

/// The icon + title shown for the current recipient selection. For a single selection it resolves the
/// discussion's avatar/title on demand through the discussion item data source, so nothing here holds a
/// discussion display model.
private struct RecipientsSummaryView: View {

    let selectedDiscussionIdentifiers: [ObvDiscussionIdentifier]
    let dataSource: any SingleRecipientSummaryViewDataSource
    let avatarDataSource: any ObvAvatarViewDataSource

    var body: some View {
        switch selectedDiscussionIdentifiers.count {
        case 0:
            SummaryLabel(imageOrIcon: .icon(Image(systemIcon: .personFillBadgePlus)),
                         title: String(localizedInThisBundle: "DEFAULT_DISCUSSIONS_TITLE"),
                         shorterTitle: String(localizedInThisBundle: "DEFAULT_DISCUSSIONS_TITLE_SHORT"),
                         avatarDataSource: avatarDataSource)
        case 1:
            SingleRecipientSummaryView(discussionIdentifier: selectedDiscussionIdentifiers[0],
                                       dataSource: dataSource,
                                       avatarDataSource: avatarDataSource)
        default:
            SummaryLabel(imageOrIcon: .icon(Image(systemIcon: .person2Fill)),
                         title: String(localizedInThisBundle: "\(selectedDiscussionIdentifiers.count)_DISCUSSIONS_TITLE"),
                         avatarDataSource: avatarDataSource)
        }
    }
}


/// Resolves a discussion identifier into a `SingleRecipientSummaryView.Model`. This view owns its model and
/// its data source contract rather than reusing the discussion chooser's (`DiscussionItemViewDataSource`),
/// so it doesn't depend on another module's view model.
@MainActor
public protocol SingleRecipientSummaryViewDataSource: Sendable {
    func getAsyncStreamOfSingleRecipientSummaryViewModel(discussionIdentifier: ObvDiscussionIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<SingleRecipientSummaryView.Model>)
    func finishAsyncStreamOfSingleRecipientSummaryViewModel(discussionIdentifier: ObvDiscussionIdentifier, streamUUID: UUID)
}

/// The single selected discussion's avatar + title, streamed from its identifier. Redacted while loading,
/// following the same per-cell streaming pattern as the discussion chooser rows and chips.
public struct SingleRecipientSummaryView: View {

    let discussionIdentifier: ObvDiscussionIdentifier
    let dataSource: any SingleRecipientSummaryViewDataSource
    let avatarDataSource: any ObvAvatarViewDataSource

    /// This view's own model, holding only what the "To:" row shows.
    public struct Model: Sendable, Equatable {
        public let avatarViewModel: ObvAvatarViewModel
        public let title: String
        public init(avatarViewModel: ObvAvatarViewModel, title: String) {
            self.avatarViewModel = avatarViewModel
            self.title = title
        }
    }

    @State private var model: Model?

    /// True when the data source could not find the discussion, which happens when the app deletes it while the
    /// share sheet is up. The row then invites the reader to select again rather than staying a skeleton.
    @State private var discussionWasNotFound = false

    private func onTask() async {
        // The task runs again when `discussionIdentifier` changes. The model then belongs to the previous
        // discussion, so it is dropped and the row is redacted until the new one arrives.
        model = nil
        discussionWasNotFound = false
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfSingleRecipientSummaryViewModel(discussionIdentifier: discussionIdentifier)
            defer { dataSource.finishAsyncStreamOfSingleRecipientSummaryViewModel(discussionIdentifier: discussionIdentifier, streamUUID: streamUUID) }
            for await receivedModel in stream {
                // An `AsyncStream` still hands over an element it had buffered once the task is cancelled. By then
                // the task for the next discussion has reset `model`, so writing this one would put the previous
                // discussion's title and avatar back in the row.
                guard !Task.isCancelled else { break }
                withAnimation { self.model = receivedModel }
            }
        } catch {
            // A task cancelled by a change of discussion may throw too, and the row by then belongs to the next one.
            guard !Task.isCancelled else { return }
            discussionWasNotFound = true
        }
    }

    public var body: some View {
        SummaryLabel(imageOrIcon: model.map { .avatarModel($0.avatarViewModel) } ?? .icon(Image(systemIcon: .personFillBadgePlus)),
                     title: model?.title ?? (discussionWasNotFound ? String(localizedInThisBundle: "DEFAULT_DISCUSSIONS_TITLE") : "Placeholder title"),
                     shorterTitle: discussionWasNotFound ? String(localizedInThisBundle: "DEFAULT_DISCUSSIONS_TITLE_SHORT") : nil,
                     avatarDataSource: avatarDataSource)
        .redacted(reason: model == nil && !discussionWasNotFound ? .placeholder : [])
        // Keyed on the identifier: when the selection goes from one discussion straight to another, this view keeps
        // its identity and only the identifier changes. Without the id the task would not run again and the row
        // would keep showing the previous discussion.
        .task(id: discussionIdentifier, onTask)
    }
}


/// An icon + title pair styled for the recipients row.
private struct SummaryLabel: View {

    let imageOrIcon: SharedState.ImageOrIcon
    let title: String

    /// A shorter wording to fall back on when ``title`` cannot be drawn in full, or nil where there is only one
    /// wording to offer.
    ///
    /// **A `var` with a default rather than a `let`**: a `let` with a default is excluded from the memberwise
    /// initialiser altogether, so it could not then be passed at all.
    var shorterTitle: String? = nil

    let avatarDataSource: any ObvAvatarViewDataSource

    var body: some View {
        HStack(spacing: 8.0) {

            ProfileIconView(imageOrIcon: imageOrIcon, avatarDataSource: avatarDataSource)

            if let shorterTitle {
                // The full wording when it fits, the short one when it does not — `ViewThatFits` takes the first
                // candidate that fits and this is exactly what it is for. It matters because the space here is not a
                // constant: the card shares its row with the close button and, on a photo or video share only, the HD
                // picker, which costs some 48pt including its spacing. So the same string fits on one kind of share
                // and not on another, and no single wording is right for both.
                ViewThatFits(in: .horizontal) {
                    // **`fixedSize` makes the fit test exact, and without it this does nothing.** A `Text` is willing
                    // to compress by truncating, so its minimum width is an ellipsis rather than its content — and a
                    // candidate that can always shrink always "fits", whereupon the long wording is chosen and then
                    // truncated, which is the state this is meant to replace. Fixed horizontally, it must be drawn
                    // whole or not at all.
                    titleText(title)
                        .fixedSize(horizontal: true, vertical: false)

                    // **Last, and deliberately not fixed.** A `ViewThatFits` where nothing fits draws its *last*
                    // candidate, so the last one has to be the one that degrades safely: this may still truncate, in
                    // some locale on some device narrower than any we ship, and truncating "Select" is a far better
                    // failure than a wording that overflows its card.
                    titleText(shorterTitle)
                }
            } else {
                titleText(title)
            }
        }
    }

    private func titleText(_ string: String) -> some View {
        Text(string)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}


// MARK: - Previews

#if DEBUG

@MainActor
private let sharedStateForPreviews = SharedState(initialMediaQuality: .standard)

@MainActor
private let dataSourceAndActionsForPreviews = ShareExtensionDataSourceAndActionsForPreviews(sharedState: sharedStateForPreviews)

@MainActor
private let dataSources = ShareExtensionView.DataSources(dataSource: dataSourceAndActionsForPreviews,
                                                         avatarViewDataSource: dataSourceAndActionsForPreviews)

#Preview {
    ShareExtensionView(sharedState: sharedStateForPreviews,
                       dataSources: dataSources,
                       actions: dataSourceAndActionsForPreviews,
                       initialModel: dataSourceAndActionsForPreviews.getInitialShareExtensionViewModel(currentOwnedCryptoId: sharedStateForPreviews.selectedOwnedCryptoId))
}

#endif
