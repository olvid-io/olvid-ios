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


/// Metrics of the header, from `SingleDiscussionTitleView` and `makeSingleDiscussionTitleView(configuration:)`.
enum DiscussionHeaderMetrics {

    /// The 32×32 avatar of the iOS 26 header. Before that the legacy view lets the avatar grow to the bar's full height, less a 2pt inset.
    static let avatarSize: CGFloat = 32

    /// The inset the legacy pre-26 view keeps around its avatar.
    static let avatarInset: CGFloat = 2

    /// 8pt between the avatar and the labels on iOS 26, 6pt before it.
    static let gapAfterTheAvatar: CGFloat = 8
    static let gapAfterTheAvatarBeforeIOS26: CGFloat = 6

    /// The insets of the glass capsule on iOS 26. Asymmetric, and deliberately so — that is what the legacy view asks for.
    static let capsuleLeadingInset: CGFloat = 8
    static let capsuleTrailingInset: CGFloat = 16
    static let capsuleVerticalInset: CGFloat = 6

    /// The iOS 26 fonts: 17pt semibold over 15pt semibold. Before that the legacy view uses the preferred `.headline` and `.subheadline`, which is why the two
    /// paths do not share one font.
    static let titleSize: CGFloat = 17
    static let subtitleSize: CGFloat = 15

    /// What the header asks the navigation bar for, before iOS 26: **an ideal width it may be compressed below**, which is the SwiftUI expression of the legacy
    /// constraint — a width of `max(screen.width, screen.height)` at `defaultHigh`.
    ///
    /// **It has to be an *ideal* width.** Measured, on iOS 18 and on iOS 26: `frame(maxWidth: .infinity)` is ignored outright and the header is centred, hugging
    /// its content; `frame(width:)` is granted in full and pushes the header off the side of the screen; `frame(idealWidth:maxWidth:)` is asked for and then
    /// compressed to the space the bar has, which puts the avatar hard left and shortens the back button — exactly what the legacy constraint does.
    static let widthAskedOfTheBar: CGFloat = 2_000

}


/// Who the reader is talking to, drawn in the navigation bar: the avatar, the title, and the subtitle under it.
///
/// **A value in, a tap out.** The stream that keeps it current is run by ``SingleDiscussionView``, which needs the title anyway — the back button of the next
/// screen is built from it — so this view neither opens a stream nor knows a data source.
///
/// **Two shapes, as the legacy screen has two.** From iOS 26 it is a glass capsule hugging its content, centred in the bar, which is what
/// `makeSingleDiscussionTitleView(configuration:)` draws; before that it takes the whole bar with the avatar hard left, which is what `SingleDiscussionTitleView`
/// does with a constraint. Both were confirmed on a device before being written — see ``DiscussionHeaderMetrics/widthAskedOfTheBar``.
///
/// The glass is drawn here and not left to the bar: on iOS 26 a principal toolbar item is **not** dressed by SwiftUI, which was the second thing the spike
/// answered.
struct SingleDiscussionHeaderView: View {

    let header: DiscussionHeader

    /// The app's own photo cache, which the cells of this screen already draw people with.
    let avatarDataSource: any ObvAvatarViewDataSource

    /// What tapping the header asks for — the contact, or the group. The legacy screen puts a `UITapGestureRecognizer` on its title view for this.
    let tapped: () -> Void

    var body: some View {
        Button(action: tapped) {
            if #available(iOS 26.0, *) {
                glassCapsule
            } else {
                theWholeBar
            }
        }
        // Without it the header is drawn as a button — tinted, and on iOS 26 in a capsule of the system's own, inside the one this draws.
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: header.subtitle.isEmpty ? header.title : "\(header.title), \(header.subtitle)"))
    }


    /// From iOS 26: a capsule of glass around the avatar and the labels, no wider than what it holds.
    @available(iOS 26.0, *)
    private var glassCapsule: some View {
        avatarAndLabels(gapAfterTheAvatar: DiscussionHeaderMetrics.gapAfterTheAvatar)
            .padding(.leading, DiscussionHeaderMetrics.capsuleLeadingInset)
            .padding(.trailing, DiscussionHeaderMetrics.capsuleTrailingInset)
            .padding(.vertical, DiscussionHeaderMetrics.capsuleVerticalInset)
            .glassEffect(.regular.interactive(), in: .capsule)
    }


    /// Before iOS 26: the whole bar, with the avatar hard left. See ``DiscussionHeaderMetrics/widthAskedOfTheBar`` for why the width is asked for as an *ideal*.
    private var theWholeBar: some View {
        avatarAndLabels(gapAfterTheAvatar: DiscussionHeaderMetrics.gapAfterTheAvatarBeforeIOS26)
            .padding(.vertical, DiscussionHeaderMetrics.avatarInset)
            .frame(idealWidth: DiscussionHeaderMetrics.widthAskedOfTheBar, maxWidth: .infinity, alignment: .leading)
    }


    private func avatarAndLabels(gapAfterTheAvatar: CGFloat) -> some View {
        HStack(spacing: gapAfterTheAvatar) {
            ObvAvatarView(model: header.avatar,
                          style: .topBar,
                          size: .custom(frameSize: .init(width: DiscussionHeaderMetrics.avatarSize, height: DiscussionHeaderMetrics.avatarSize)),
                          dataSource: avatarDataSource)
            labels
            // Only reached before iOS 26, where this view is as wide as the bar: it is what pushes the labels against the avatar rather than spreading them.
            Spacer(minLength: 0)
        }
    }


    private var labels: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: header.title)
                .font(titleFont)
                .foregroundStyle(Color(UIColor.label))
            // A `Group` rather than a container: a discussion with nothing to say about itself must draw **one** line, and a container holding nothing is still a
            // subview with the stack's spacing around it.
            if !header.subtitle.isEmpty {
                Text(verbatim: header.subtitle)
                    .font(subtitleFont)
                    .foregroundStyle(Color(UIColor.secondaryLabel))
            }
        }
        .lineLimit(1)
        // The bar is not a place a title may push things out of: whatever is too long is shortened, and the avatar keeps its size.
        .truncationMode(.tail)
    }


    /// 17pt semibold from iOS 26, and the preferred `.headline` before it — the two legacy paths, kept apart because they really do differ.
    private var titleFont: Font {
        if #available(iOS 26.0, *) {
            return .system(size: DiscussionHeaderMetrics.titleSize, weight: .semibold)
        } else {
            return .headline
        }
    }


    private var subtitleFont: Font {
        if #available(iOS 26.0, *) {
            return .system(size: DiscussionHeaderMetrics.subtitleSize, weight: .semibold)
        } else {
            return .subheadline
        }
    }

}


#if DEBUG

#Preview {
    NavigationStack {
        List { Text(verbatim: "The bar above is what this previews.") }
            .navigationTitle(Text(verbatim: DiscussionHeader.sampleData.title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    SingleDiscussionHeaderView(header: .sampleData,
                                               avatarDataSource: singleDiscussionCellViewDataSourceForPreviews,
                                               tapped: {})
                }
            }
    }
}


/// A discussion with nothing to say about itself: one line, and no blank second one.
#Preview {
    NavigationStack {
        List { Text(verbatim: "A header with no subtitle.") }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    SingleDiscussionHeaderView(header: .sampleDataWithoutSubtitle,
                                               avatarDataSource: singleDiscussionCellViewDataSourceForPreviews,
                                               tapped: {})
                }
            }
    }
}

#endif
