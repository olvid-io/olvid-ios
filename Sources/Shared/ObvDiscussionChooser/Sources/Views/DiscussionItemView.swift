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
import ObvTypes
import ObvDesignSystem


// MARK: - Data source

/// Resolves a discussion identifier into a `DiscussionItemView.Model` (via an async stream, so the row
/// updates live). View-less on purpose: the list rows, the selected chips, and the "To:" row all resolve
/// discussions by identifier through this same data source.
@MainActor
public protocol DiscussionItemViewDataSource: Sendable {
    func getAsyncStreamOfDiscussionItemViewModel(discussionIdentifier: ObvDiscussionIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<DiscussionItemView.Model>)
    func finishAsyncStreamOfDiscussionItemViewModel(discussionIdentifier: ObvDiscussionIdentifier, streamUUID: UUID)
}


// MARK: - DiscussionItemView

/// A selectable list row for a single discussion. It is given only the discussion **identifier** and
/// resolves its own `Model` lazily from `DiscussionItemViewDataSource` — so full display models exist only
/// for the rows currently on screen, not for the whole list.
public struct DiscussionItemView: View {

    let discussionIdentifier: ObvDiscussionIdentifier
    let dataSource: any DiscussionItemViewDataSource
    let avatarViewDataSource: any ObvAvatarViewDataSource
    @Binding var selectedDiscussionIdentifiers: [ObvDiscussionIdentifier]

    public init(discussionIdentifier: ObvDiscussionIdentifier,
                dataSource: any DiscussionItemViewDataSource,
                avatarViewDataSource: any ObvAvatarViewDataSource,
                selectedDiscussionIdentifiers: Binding<[ObvDiscussionIdentifier]>) {
        self.discussionIdentifier = discussionIdentifier
        self.dataSource = dataSource
        self.avatarViewDataSource = avatarViewDataSource
        self._selectedDiscussionIdentifiers = selectedDiscussionIdentifiers
    }

    public struct Model: Sendable, Identifiable, Equatable {

        public let identifier: ObvDiscussionIdentifier
        public let avatarViewModel: ObvAvatarViewModel
        public let title: String
        let subtitle: String
        let showGreenShield: Bool
        let showRedShield: Bool

        public var id: Data { Data(identifier.description.utf8) }

        public init(identifier: ObvDiscussionIdentifier,
                    avatarViewModel: ObvAvatarViewModel,
                    title: String,
                    subtitle: String,
                    showGreenShield: Bool,
                    showRedShield: Bool) {
            self.identifier = identifier
            self.avatarViewModel = avatarViewModel
            self.title = title
            self.subtitle = subtitle
            self.showGreenShield = showGreenShield
            self.showRedShield = showRedShield
        }
    }

    @State private var model: Model?

    private static let kCircleToTextAreaPadding = CGFloat(8.0)

    private var isSelected: Bool {
        selectedDiscussionIdentifiers.contains(discussionIdentifier)
    }

    private func toggleSelection() {
        withAnimation {
            if let index = selectedDiscussionIdentifiers.firstIndex(of: discussionIdentifier) {
                selectedDiscussionIdentifiers.remove(at: index)
            } else {
                selectedDiscussionIdentifiers.insert(discussionIdentifier, at: 0)
            }
        }
    }

    /// Consumes the model stream. The stream UUID is a local (not a `@State`): when the view disappears
    /// the `.task` is cancelled, the `for await` ends, and `defer` finishes the stream.
    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSource.getAsyncStreamOfDiscussionItemViewModel(discussionIdentifier: discussionIdentifier)
            defer { dataSource.finishAsyncStreamOfDiscussionItemViewModel(discussionIdentifier: discussionIdentifier, streamUUID: streamUUID) }
            for await receivedModel in stream {
                withAnimation { self.model = receivedModel }
            }
        } catch {
            assertionFailure()
        }
    }

    public var body: some View {
        Group {
            if let model {
                HStack(alignment: .center, spacing: Self.kCircleToTextAreaPadding) {
                    ObvAvatarView(model: model.avatarViewModel,
                                  style: .circle,
                                  size: .normal,
                                  dataSource: avatarViewDataSource)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5)
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(model.title)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .font(.system(.headline, design: .rounded))
                            if model.showGreenShield {
                                Image(systemIcon: .checkmarkShieldFill)
                                    .foregroundColor(.green)
                            }
                            if model.showRedShield {
                                Image(systemIcon: .exclamationmarkShieldFill)
                                    .foregroundColor(.red)
                            }
                        }
                        if !model.subtitle.isEmpty {
                            Text(model.subtitle)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .font(.subheadline)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemIcon: isSelected ? .checkmarkCircleFill : .circle)
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? Color.green : Color.secondary)
                        .animation(nil, value: isSelected)
                }
                .contentShape(Rectangle()) // Makes the whole row tappable, including the Spacer
                .onTapGesture { toggleSelection() }
                .sensoryFeedbackOniOS17(.selection, trigger: isSelected)
            } else {
                // Skeleton shown until the first model arrives. Mirrors the loaded row's layout and applies
                // `.redacted(reason: .placeholder)`, so the row keeps its shape/height (no layout jump).
                HStack(alignment: .center, spacing: Self.kCircleToTextAreaPadding) {
                    Circle()
                        .fill(Color(UIColor.systemFill))
                        .frame(width: ObvAvatarSize.normal.frameSize.width, height: ObvAvatarSize.normal.frameSize.height)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: "Placeholder discussion title")
                            .lineLimit(1)
                            .font(.system(.headline, design: .rounded))
                        Text(verbatim: "Placeholder subtitle")
                            .lineLimit(1)
                            .font(.subheadline)
                    }
                    Spacer(minLength: 0)
                    Image(systemIcon: .circle)
                        .font(.system(size: 22))
                }
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
            }
        }
        .task(onTask)
    }
}


// MARK: - Previews

#if DEBUG

@MainActor
private let dataSourceForPreviews = DataSourceForPreviews()

@available(iOS 17.0, *)
#Preview("Not selected") {
    @Previewable @State var selectedDiscussionIdentifiers = [ObvDiscussionIdentifier]()
    List {
        DiscussionItemView(discussionIdentifier: ObvDiscussionIdentifier.sampleDatas[0],
                           dataSource: dataSourceForPreviews,
                           avatarViewDataSource: dataSourceForPreviews,
                           selectedDiscussionIdentifiers: $selectedDiscussionIdentifiers)
    }
}

@available(iOS 17.0, *)
#Preview("Selected") {
    @Previewable @State var selectedDiscussionIdentifiers = [ObvDiscussionIdentifier.sampleDatas[0]]
    List {
        DiscussionItemView(discussionIdentifier: ObvDiscussionIdentifier.sampleDatas[0],
                           dataSource: dataSourceForPreviews,
                           avatarViewDataSource: dataSourceForPreviews,
                           selectedDiscussionIdentifiers: $selectedDiscussionIdentifiers)
    }
}

#endif
