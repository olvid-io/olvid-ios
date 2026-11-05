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
import ObvTypes
import ObvDesignSystem
import ObvAppTypes


// MARK: - Data source

/// Provides the (search-filtered) list of discussion identifiers to display. Only identifiers are
/// streamed here; each row resolves its own display model lazily (see `DiscussionItemViewDataSource`),
/// so memory stays bounded even with a very large number of discussions.
@MainActor
public protocol DiscussionChooserViewDataSource: Sendable {
    func getAsyncStreamOfDiscussionIdentifiers(_ view: DiscussionChooserInnerView, currentOwnedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<[ObvDiscussionIdentifier]>)
    func filterAsyncStreamOfDiscussionIdentifiers(_ view: DiscussionChooserInnerView, streamUUID: UUID, searchTerm: String?)
    func finishAsyncStreamOfDiscussionIdentifiers(_ view: DiscussionChooserInnerView, streamUUID: UUID)
}


// MARK: - DiscussionChooserInnerView

public struct DiscussionChooserInnerView: View {

    let currentOwnedCryptoId: ObvCryptoId
    let dataSources: DiscussionChooserView.DataSources

    init(currentOwnedCryptoId: ObvCryptoId,
         dataSources: DiscussionChooserView.DataSources,
         selectedDiscussionIdentifiers: Binding<[ObvDiscussionIdentifier]>,
         searchText: Binding<String>
    ) {
        self.currentOwnedCryptoId = currentOwnedCryptoId
        self.dataSources = dataSources
        _selectedDiscussionIdentifiers = selectedDiscussionIdentifiers
        _searchText = searchText
    }

    /// The (search-filtered) identifiers to display. `nil` until the first emission.
    @State private var discussionIdentifiers: [ObvDiscussionIdentifier]?
    /// Kept as state (unlike the per-cell streams) because `filter…` needs it from `onChange(of: searchText)`.
    @State private var streamUUIDForIdentifiers: UUID?

    @Binding var selectedDiscussionIdentifiers: [ObvDiscussionIdentifier]
    @Binding var searchText: String

    @Environment(\.isSearching) var isSearching

    private func performSearchWith(newSearchText: String?) {
        guard let streamUUIDForIdentifiers else { return }
        dataSources.discussionChooserViewDataSource.filterAsyncStreamOfDiscussionIdentifiers(self, streamUUID: streamUUIDForIdentifiers, searchTerm: newSearchText)
    }

    /// Consumes the identifier stream. The UUID is kept in state (see above) so `filter…` can reach it,
    /// but the lifetime follows the `DiscussionItemView` pattern: `.task` cancellation on disappear ends
    /// the `for await` and `defer` finishes the stream.
    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSources.discussionChooserViewDataSource.getAsyncStreamOfDiscussionIdentifiers(self, currentOwnedCryptoId: currentOwnedCryptoId)
            self.streamUUIDForIdentifiers = streamUUID
            defer { dataSources.discussionChooserViewDataSource.finishAsyncStreamOfDiscussionIdentifiers(self, streamUUID: streamUUID) }
            for await identifiers in stream {
                withAnimation { self.discussionIdentifiers = identifiers }
            }
        } catch {
            assertionFailure()
        }
    }

    public var body: some View {
        Group {
            if let discussionIdentifiers {
                if discussionIdentifiers.isEmpty {
                    if isSearching {
                        ObvContentUnavailableView.search
                    } else {
                        ObvContentUnavailableView(title: String(localizedInThisBundle: "CONTENT_UNAVAILABLE_RECENT_DISCUSSIONS_TEXT"),
                                                  systemIcon: .bubbleLeftAndBubbleRight,
                                                  description: nil)
                    }
                } else {
                    // The selected-discussions strip is the list's first section rather than a view above
                    // it. The card inset and the spacing between the two are then computed by the list
                    // itself, so they agree on every platform, size class and orientation — matching them
                    // by hand did not survive iPad landscape or macOS. It also means the strip scrolls with
                    // the list. It is always present (even with nothing selected, where it shows an
                    // invitation) so selecting the first discussion does not shove the list down.
                    List {
                        Section {
                            SelectedDiscussionsView(selectedDiscussionIdentifiers: $selectedDiscussionIdentifiers,
                                                    dataSource: dataSources.discussionItemViewDataSource,
                                                    avatarViewDataSource: dataSources.avatarViewDataSource)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color(.secondarySystemGroupedBackground))
                        }
                        Section {
                            ForEach(discussionIdentifiers, id: \.self) { discussionIdentifier in
                                DiscussionItemView(discussionIdentifier: discussionIdentifier,
                                                   dataSource: dataSources.discussionItemViewDataSource,
                                                   avatarViewDataSource: dataSources.avatarViewDataSource,
                                                   selectedDiscussionIdentifiers: $selectedDiscussionIdentifiers)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color(.secondarySystemGroupedBackground))
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .topScrollContentMargin(8)
                }
            } else {
                ObvCenteredProgressView()
            }
        }
        .onChange(of: searchText) { newSearchText in performSearchWith(newSearchText: newSearchText) }
        .task(onTask)
    }
}


// MARK: - DiscussionChooserSearchableView

private extension View {

    /// Sets the space an inset-grouped `List` leaves above its first section.
    ///
    /// That style reserves room for a section header above the first section. With a titled group that is
    /// right, but the first section here is the selected-discussions strip, so the reserved space just
    /// reads as a large empty gap. Applies on every platform: the gap comes from the list style, not from
    /// anything device-specific.
    ///
    /// `contentMargins(_:_:for:)` is the supported way to change this. Negative padding would leave the
    /// real margin in place and drag the content up over it, which misreports the layout to the scroll
    /// view — it shows up in the scroll indicators and the resting offset, and clips during rubber-banding.
    ///
    /// No-op below iOS 17, where the API does not exist; the spacing there stays the system default.
    @ViewBuilder
    func topScrollContentMargin(_ margin: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            self.contentMargins(.top, margin, for: .scrollContent)
        } else {
            self
        }
    }


    /// Keeps the navigation bar's own buttons on screen while the search field has focus.
    ///
    /// By default a `UISearchController` hides the navigation bar as it presents
    /// (`hidesNavigationBarDuringPresentation`), which takes the chooser's close *and confirm* buttons with it and
    /// substitutes its own Cancel. The ordinary way through this screen is to search, tap a discussion and accept —
    /// and that put the confirm button behind cancelling the search first.
    ///
    /// No-op below iOS 17.1, where the modifier does not exist. That leaves only iOS 17.0 exposed: the pre-iOS-17
    /// branch of ``DiscussionChooserNavigationStack`` draws its own `HeaderView` rather than a toolbar, so its buttons
    /// are ordinary views that search has no power over.
    @ViewBuilder
    func keepsTheToolbarWhileSearching() -> some View {
        if #available(iOS 17.1, *) {
            self.searchPresentationToolbarBehavior(.avoidHidingContent)
        } else {
            self
        }
    }

}


public struct DiscussionChooserSearchableView: View {

    let currentOwnedCryptoId: ObvCryptoId
    let dataSources: DiscussionChooserView.DataSources

    /// Where the search field lives.
    ///
    /// Pinned to the navigation bar everywhere except iPhone. The default `.automatic` placement puts it in
    /// a drawer whose display mode lets it come and go: it hides as the list scrolls, and focusing it
    /// re-lays out the navigation bar, shoving the content down a few points. Pinning it removes that
    /// layout change at its source instead of compensating for it with an offset.
    ///
    /// Left automatic on iPhone: on iOS 26 the field belongs in the bottom bar there, and naming the
    /// navigation-bar drawer explicitly would drag it back up to the navigation bar.
    ///
    /// Keyed on the device idiom rather than the horizontal size class, because this view is presented in a
    /// **sheet** — and a sheet on iPad is compact width, so a size-class test reports `.compact` there and
    /// would leave iPad on the automatic placement, which is exactly what it did.
    private var searchFieldPlacement: SearchFieldPlacement {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            return .automatic
        default:
            return .navigationBarDrawer(displayMode: .always)
        }
    }

    init(currentOwnedCryptoId: ObvCryptoId,
         dataSources: DiscussionChooserView.DataSources,
         selectedDiscussionIdentifiers: Binding<[ObvDiscussionIdentifier]>) {
        self.currentOwnedCryptoId = currentOwnedCryptoId
        self.dataSources = dataSources
        _selectedDiscussionIdentifiers = selectedDiscussionIdentifiers
    }

    @State private var searchText: String = ""
    @Binding var selectedDiscussionIdentifiers: [ObvDiscussionIdentifier]

    public var body: some View {
        DiscussionChooserInnerView(currentOwnedCryptoId: currentOwnedCryptoId,
                                   dataSources: dataSources,
                                   selectedDiscussionIdentifiers: $selectedDiscussionIdentifiers,
                                   searchText: $searchText)
        .searchable(text: $searchText,
                    placement: searchFieldPlacement,
                    prompt: Text(verbatim: String(localizedInThisBundle: "SEARCH_DISCUSSIONS_PLACEHOLDER")))
        .keepsTheToolbarWhileSearching()
    }
}
