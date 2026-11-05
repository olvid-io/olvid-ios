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
import ObvCrypto
import ObvDesignSystem

#if DEBUG

@MainActor
final class ContactsSuggestionsPreviewHelper: ContactsSuggestionsViewDataSource, ContactsSuggestionsViewActions {

    private static let ownedCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)

    let identifiers: [ContactSuggestion.Identifier] = (0..<3).map { index in
        .invitation(ownedCryptoId: ContactsSuggestionsPreviewHelper.ownedCryptoId, invitationUUID: UUID(), contactCryptoId: ContactsSuggestionsPreviewHelper.ownedCryptoId)
    }

    var deck: ContactSuggestion.Deck {
        .init(identifiers: identifiers, hasANewCard: true)
    }

    func deckStream(ownedCryptoId: ObvCryptoId, scope: ContactSuggestion.Scope) -> AsyncStream<ContactSuggestion.Deck> {
        let deck = self.deck
        return AsyncStream { continuation in
            continuation.yield(deck)
        }
    }

    func model(for identifier: ContactSuggestion.Identifier) async -> ContactSuggestion.Model? {
        let index = identifiers.firstIndex(of: identifier) ?? 0
        return .init(
            avatar: .init(characterOrIcon: .character("V"), colors: .init(foreground: .white, background: .systemTeal), photoURL: nil),
            name: ["Valentine Dupond", "Bruno Guédon", "Camille Martin"][index % 3],
            positionAtCompany: "Product Designer @ Olvid",
            badge: index == 0 ? .invitationReceived : .none,
            commonGroups: .init(pictures: [], nameOfFirstGroup: "Ski 2025", numberOfGroups: 3),
            contactForDetails: nil)
    }

    func ownedAvatar(ownedCryptoId: ObvCryptoId) async -> ObvAvatarViewModel? {
        .init(characterOrIcon: .character("A"), colors: .init(foreground: .white, background: .systemIndigo), photoURL: nil)
    }

    func userAccepted(_ identifier: ContactSuggestion.Identifier) async throws {}
    func userDeclined(_ identifier: ContactSuggestion.Identifier) async throws {}
    func cardsWereSeen(_ identifiers: [ContactSuggestion.Identifier]) {}
    func userWantsToSeeDetails(of contactIdentifier: ObvContactIdentifier) {}
    func userWantsToSeeOtherKnownUsers() {}
    func userWantsToClose() {}
    func onboardingWasShown() {}

}


/// Returns no picture, so every avatar of the previews shows its initials.
private final class AvatarViewDataSourceForPreviews: ObvAvatarViewDataSource {
    func fetchAvatar(_ view: ObvAvatarView, photoURL: URL, avatarSize: ObvAvatarSize) async throws -> UIImage? { nil }
    func fetchAvatarFromCache(_ view: ObvAvatarView, photoURL: URL, avatarSize: ObvAvatarSize) -> UIImage? { nil }
    func fetchAvatarForLegacyViews(photoURL: URL, avatarSize: ObvAvatarSize) async throws -> UIImage? { nil }
    func fetchAvatarFromCacheForLegacyViews(photoURL: URL, avatarSize: ObvAvatarSize) -> UIImage? { nil }
    func fetchPictureAsStored(photoURL: URL) async throws -> CGImage? { nil }
}


@available(iOS 17.0, *)
#Preview {
    let helper = ContactsSuggestionsPreviewHelper()
    NavigationStack {
        ContactsSuggestionsView(ownedCryptoId: try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!),
                                scope: .suggestions,
                                initialDeck: helper.deck,
                                showsOnboarding: true,
                                dataSources: .init(dataSource: helper, avatarViewDataSource: AvatarViewDataSourceForPreviews()),
                                actions: helper)
    }
}


@available(iOS 17.0, *)
#Preview("Entry") {
    VStack(spacing: 16) {
        ContactsSuggestionsEntryView(badgeCount: 3, hasANewCard: true, action: {})
        ContactsSuggestionsEntryView(badgeCount: 3, hasANewCard: false, action: {})
    }
    .padding()
}


@available(iOS 17.0, *)
#Preview("Card above the other known users") {
    VStack(spacing: 16) {
        ContactsSuggestionsOtherKnownUsersCard(showsTheRowOpeningTheDeck: true, action: {})
        ContactsSuggestionsOtherKnownUsersCard(showsTheRowOpeningTheDeck: false, action: {})
    }
    .padding()
    .background(Color(uiColor: .systemGroupedBackground))
}

#endif
