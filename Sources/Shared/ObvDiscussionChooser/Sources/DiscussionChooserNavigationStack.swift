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
import ObvAppTypes
import ObvDesignSystem

@MainActor
public protocol DiscussionChooserNavigationStackActions {
    func userChoseDiscussions(_ view: DiscussionChooserNavigationStack, chosenDiscussionIdentifiers: [ObvDiscussionIdentifier]) async throws
}

public struct DiscussionChooserNavigationStack: View {

    let currentOwnedCryptoId: ObvCryptoId
    let dataSources: DiscussionChooserView.DataSources
    let actions: DiscussionChooserNavigationStackActions

    @Binding var toggleToDismiss: Bool

    @State var selectedDiscussionIdentifiers: [ObvDiscussionIdentifier] = []

    public init(currentOwnedCryptoId: ObvCryptoId,
                initialSelectedDiscussionIdentifiers: [ObvDiscussionIdentifier]? = nil,
                dataSources: DiscussionChooserView.DataSources,
                actions: DiscussionChooserNavigationStackActions,
                toggleToDismiss: Binding<Bool>) {
        self.currentOwnedCryptoId = currentOwnedCryptoId
        self.dataSources = dataSources
        self.actions = actions
        if let initialSelectedDiscussionIdentifiers {
            selectedDiscussionIdentifiers = initialSelectedDiscussionIdentifiers
        }
        self._toggleToDismiss = toggleToDismiss
    }

    /// What the chooser paints behind its content: the app theme's page colour, which is the partner of the card
    /// colour ``ObvCardView`` fills each row with.
    ///
    /// **Read, never composed.** This used to branch on `@Environment(\.colorScheme)` and return
    /// `UIColor.secondarySystemBackground` in light and `.black` in dark — which are *exactly* the two values this one
    /// property resolves to, so it was a hand-copy of the theme with the usual consequence: nothing keeps a copy in
    /// step, and the copy cannot carry what it never read.
    ///
    /// What it could not carry is **elevation**. Apple's dark mode has two levels, base and elevated, and the system
    /// raises modally presented content to the elevated level so that it reads as floating; a *dynamic* colour resolves
    /// that on its own, where a branch on `colorScheme` — which reports light against dark and nothing about elevation
    /// — can only ever produce the base value. Because both this and the card's colour are dynamic, elevation lifts
    /// **both** together, black and `#1C1C1E` becoming `#1C1C1E` and `#2C2C2E`: the sheet separates from what is behind
    /// it *and* the cards stay visible against it.
    ///
    /// **Do not read these names as UIKit's — `AppThemeColorScheme` inverts them** (`AppThemeColorScheme.swift:165`).
    /// The theme's `systemBackground` is UIKit's `secondarySystemBackground` in light and UIKit's `systemBackground` in
    /// dark, and its `secondarySystemBackground` is the other way about. So the theme's *secondary* is the lighter,
    /// card-coloured one and the theme's *primary* is the page. Reaching for `UIColor.secondarySystemBackground` here
    /// on the strength of the name gives the page the card's own colour and the rows vanish in dark mode, which is
    /// precisely what it did.
    ///
    /// The background does have to be painted rather than left to the presentation: the content is a `ScrollView`
    /// rather than a `List`, and the hosting controller presents this as a bare `UIHostingController`, so nothing else
    /// would fill it. Hence the name.
    private var backgroundColorInUIKitMode: UIColor {
        AppTheme.shared.colorScheme.systemBackground
    }

    @ViewBuilder
    var content: some View {
        ZStack {
            Color(backgroundColorInUIKitMode).ignoresSafeArea(.all)
            DiscussionChooserSearchableView(currentOwnedCryptoId: self.currentOwnedCryptoId,
                                            dataSources: dataSources,
                                            selectedDiscussionIdentifiers: $selectedDiscussionIdentifiers)
        }
    }

    private var navigationTitle: String {
        if selectedDiscussionIdentifiers.isEmpty {
            return String(localizedInThisBundle: "DEFAULT_DISCUSSIONS_CHOOSER_TITLE")
        } else {
            return String(localizedInThisBundle: "\(selectedDiscussionIdentifiers.count)_DISCUSSIONS_CHOOSER_TITLE")
        }
    }

    public var body: some View {
        Group {

            if #available(iOS 26, *) {

                NavigationStack {
                    content
                        .navigationTitle(navigationTitle)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button {
                                    toggleToDismiss.toggle()
                                } label: {
                                    Image(systemIcon: .xmark)
                                }
                            }
                            .sharedBackgroundVisibility(.automatic)

                            ToolbarItem(placement: .confirmationAction) {
                                Button {
                                    Task {
                                        try? await actions.userChoseDiscussions(self, chosenDiscussionIdentifiers: selectedDiscussionIdentifiers)
                                        toggleToDismiss.toggle()
                                    }
                                } label: {
                                    Image(systemIcon: .checkmark)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                            }
                            .sharedBackgroundVisibility(.automatic)
                        }
                }

            } else if #available(iOS 17, *) {

                NavigationStack {
                    content
                        .navigationTitle(navigationTitle)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button {
                                    toggleToDismiss.toggle()
                                } label: {
                                    Text(verbatim: String(localizedInThisBundle: "BUTTON_TITLE_CANCEL"))
                                }
                            }

                            ToolbarItem(placement: .confirmationAction) {
                                Button {
                                    Task {
                                        try? await actions.userChoseDiscussions(self, chosenDiscussionIdentifiers: selectedDiscussionIdentifiers)
                                        toggleToDismiss.toggle()
                                    }
                                } label: {
                                    Text(verbatim: String(localizedInThisBundle: "BUTTON_TITLE_CONFIRM"))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                            }
                        }
                }

            } else {

                VStack {
                    HeaderView(navigationStack: self,
                               actions: actions,
                               selectedDiscussionIdentifiers: $selectedDiscussionIdentifiers,
                               toggleToDismiss: $toggleToDismiss)
                    .padding(.horizontal)
                    .padding(.top, 4)
                    DiscussionChooserSearchableView(currentOwnedCryptoId: self.currentOwnedCryptoId,
                                                    dataSources: dataSources,
                                                    selectedDiscussionIdentifiers: $selectedDiscussionIdentifiers)
                }
            }
        }
    }
}

// MARK: - Internal view: HeaderView (pre-iOS 17 only)

/// Not used in iOS17+
@available(iOS, deprecated: 17.0)
private struct HeaderView: View {

    let navigationStack: DiscussionChooserNavigationStack
    let actions: DiscussionChooserNavigationStackActions
    @Binding var selectedDiscussionIdentifiers: [ObvDiscussionIdentifier]
    @Binding var toggleToDismiss: Bool

    private var navigationTitle: String {
        if selectedDiscussionIdentifiers.isEmpty {
            return String(localizedInThisBundle: "DEFAULT_DISCUSSIONS_CHOOSER_TITLE")
        } else {
            return String(localizedInThisBundle: "\(selectedDiscussionIdentifiers.count)_DISCUSSIONS_CHOOSER_TITLE")
        }
    }

    var body: some View {
        HStack {
            Button(action: { toggleToDismiss.toggle() }) {
                Text(verbatim: String(localizedInThisBundle: "BUTTON_TITLE_CANCEL"))
            }
            Spacer()
            Text(navigationTitle)
                .font(.headline)
                .lineLimit(nil)
                .multilineTextAlignment(.center)
            Spacer()
            Button(action: {
                Task {
                    try? await actions.userChoseDiscussions(navigationStack, chosenDiscussionIdentifiers: selectedDiscussionIdentifiers)
                    toggleToDismiss.toggle()
                }
            }) {
                Text(verbatim: String(localizedInThisBundle: "BUTTON_TITLE_CONFIRM"))
            }
        }
    }

}

// MARK: - Previews

#if DEBUG

@MainActor
private let actionsForPreviews = ActionsForPreviews()

@MainActor
private let dataSourceForPreviews = DataSourceForPreviews()

@MainActor
private let dataSources = DiscussionChooserView.DataSources(discussionChooserViewDataSource: dataSourceForPreviews,
                                                            discussionItemViewDataSource: dataSourceForPreviews,
                                                            avatarViewDataSource: dataSourceForPreviews)

#Preview("Select discussions") {
    DiscussionChooserNavigationStack(currentOwnedCryptoId: ObvCryptoId.sampleDatas[0],
                                     dataSources: dataSources,
                                     actions: actionsForPreviews,
                                     toggleToDismiss: .constant(false))
}

#Preview("Sheet") {
    Text(verbatim: "Test")
        .sheet(isPresented: .constant(true)) {
            DiscussionChooserNavigationStack(currentOwnedCryptoId: ObvCryptoId.sampleDatas[0],
                                             dataSources: dataSources,
                                             actions: actionsForPreviews,
                                             toggleToDismiss: .constant(false))
            .presentationDetents([.medium, .large])
            .interactiveDismissDisabled()
        }
}

#endif
