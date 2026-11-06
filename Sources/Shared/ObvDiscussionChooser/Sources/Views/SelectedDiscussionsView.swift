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
import ObvAppTypes
import ObvDesignSystem
import ObvSystemIcon

struct SelectedDiscussionsView: View {

    @Binding var selectedDiscussionIdentifiers: [ObvDiscussionIdentifier]
    let dataSource: any DiscussionItemViewDataSource
    let avatarViewDataSource: any ObvAvatarViewDataSource
    @State private var previousCount: Int = 0
    private let lastCellForScrollingId = "lastCellForScrolling"

    var body: some View {
        Group {
            if selectedDiscussionIdentifiers.isEmpty {
                invitationView
            } else {
                selectedChipsView
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12.0)
        // No background, corner radius or horizontal inset of its own: this is presented as a section of
        // the discussions `List`, which draws the card and insets it. Matching those by hand never held up
        // — the inset varies with platform and width — so the list is left to compute both.
    }

    /// Shown when nothing is selected yet, inviting the user to pick discussions. It reserves exactly the
    /// height of one chip (via a hidden template), so the strip keeps the same height whether it shows the
    /// invitation or the chips — adding the first discussion doesn't resize it.
    private var invitationView: some View {
        ZStack {
            SelectedChipHeightTemplate()
                .hidden()
            VStack(spacing: 8) {
                Image(systemIcon: .handTap)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(String(localizedInThisBundle: "SELECT_DISCUSSIONS_INVITATION"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var selectedChipsView: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(selectedDiscussionIdentifiers, id: \.self) { discussionIdentifier in
                        SelectedDiscussionItemView(
                            discussionIdentifier: discussionIdentifier,
                            dataSource: dataSource,
                            avatarViewDataSource: avatarViewDataSource,
                            onRemove: {
                                withAnimation {
                                    removeDiscussion(discussionIdentifier)
                                }
                            }
                        )
                    }
                    Color.clear
                        .frame(width: 32.0, height: 1.0)
                        .id(lastCellForScrollingId)
                }
                .padding(.horizontal)
            }
            .onChange(of: selectedDiscussionIdentifiers.count) { newCount in
                if newCount > previousCount {
                    withAnimation {
                        proxy.scrollTo(lastCellForScrollingId, anchor: .trailing)
                    }
                }
                previousCount = newCount
            }
            .onAppear {
                previousCount = selectedDiscussionIdentifiers.count
            }
        }
    }

    private func removeDiscussion(_ discussionIdentifier: ObvDiscussionIdentifier) {
        selectedDiscussionIdentifiers.removeAll { $0 == discussionIdentifier }
    }
}

// MARK: - Selected discussion chip

/// A chip for one selected discussion. Like `DiscussionItemView`, it is given only the identifier and
/// resolves its own `DiscussionItemView.Model` lazily; the stream is finished on task cancellation.
private struct SelectedDiscussionItemView: View {

    let discussionIdentifier: ObvDiscussionIdentifier
    let dataSource: any DiscussionItemViewDataSource
    let avatarViewDataSource: any ObvAvatarViewDataSource
    let onRemove: () -> Void

    @State private var model: DiscussionItemView.Model?

    private let avatarSize: ObvAvatarSize = .custom(frameSize: selectedChipAvatarSize)
    private let removeButtonSize: CGFloat = 20
    private var maxTitleWidth: CGFloat { selectedChipMaxTitleWidth }

    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfDiscussionItemViewModel(discussionIdentifier: discussionIdentifier)
            defer { dataSource.finishAsyncStreamOfDiscussionItemViewModel(discussionIdentifier: discussionIdentifier, streamUUID: streamUUID) }
            for await receivedModel in stream {
                if self.model == nil {
                    self.model = receivedModel
                } else {
                    withAnimation { self.model = receivedModel }
                }
            }
        } catch {
            assertionFailure()
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // Avatar and title mirror the loaded layout and are redacted until the model arrives, so the
                // chip keeps its shape/size (no jump). The remove button only needs the identifier, so it
                // stays functional even while loading and is therefore kept out of the redaction.
                avatarView
                    .redacted(reason: model == nil ? .placeholder : [])

                Button(action: onRemove) {
                    Image(systemIcon: .xmarkCircleFill)
                        .font(.system(size: removeButtonSize))
                        .foregroundStyle(.white, .gray)
                }
                .frame(width: removeButtonSize, height: removeButtonSize)
                .overlay(
                    Circle()
                        .strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 1.5)
                )
            }

            Text(model?.title ?? "Placeholder title")
                .font(.caption)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
                .frame(width: maxTitleWidth)
                .redacted(reason: model == nil ? .placeholder : [])
        }
        .task(onTask)
    }

    @ViewBuilder
    private var avatarView: some View {
        if let model {
            ObvAvatarView(model: model.avatarViewModel,
                          style: .circle,
                          size: avatarSize,
                          dataSource: avatarViewDataSource)
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5)
            )
        } else {
            Circle()
                .fill(Color(UIColor.systemFill))
                .frame(width: avatarSize.frameSize.width, height: avatarSize.frameSize.height)
        }
    }
}


// MARK: - Chip metrics

/// Shared between the chip and the height template so both compute the exact same footprint.
private let selectedChipAvatarSize = CGSize(width: 56.0, height: 56.0)
private let selectedChipMaxTitleWidth: CGFloat = selectedChipAvatarSize.width + 32.0

/// An invisible stand-in with the exact vertical footprint of a `SelectedDiscussionItemView` (avatar plus a
/// two-line title). Placed behind the invitation so the strip reserves the chip height even when empty.
private struct SelectedChipHeightTemplate: View {
    var body: some View {
        VStack(spacing: 8) {
            Color.clear
                .frame(width: selectedChipAvatarSize.width, height: selectedChipAvatarSize.height)
            Text(verbatim: " ")
                .font(.caption)
                .lineLimit(2, reservesSpace: true)
                .frame(width: selectedChipMaxTitleWidth)
        }
    }
}
