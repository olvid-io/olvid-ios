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
import ObvContactsSuggestions


/// What a list of contacts shows above its contacts to lead to the contacts suggestions, and what tapping it does.
///
/// Kept apart from the list's own model so that the lists that never show it need not know about it.
@MainActor
final class ContactsSuggestionsEntryState: ObservableObject {

    enum Kind {
        /// The entry above the one-to-one contacts, which opens the deck of the suggestions. It shows only while there is something to suggest.
        case entryAboveTheContacts
        /// The card above the other known users, which explains who they are. Its row opening the deck of all of them shows only while that deck
        /// has a card.
        case cardAboveTheOtherKnownUsers
    }

    let kind: Kind
    /// Whether the entry shows, or, for the card, whether its row opening the deck shows.
    @Published var isVisible = false
    /// The count on the badge of the contacts tab, repeated on the entry so that it says what that badge counts. The card has no badge.
    @Published var badgeCount = 0
    /// The colour of that badge: red when a card is new, grey otherwise.
    @Published var hasANewCard = false
    let action: () -> Void

    init(kind: Kind, action: @escaping () -> Void) {
        self.kind = kind
        self.action = action
    }

}


/// The entry or the card as the header of the section of contacts, or an empty header when the entry has nothing to suggest.
///
/// A header rather than a row of its own: an inset grouped list clips each row to the rounded shape of its cell, whose radius is not the entry's,
/// and that cut the gradient border at the corners. A header is not clipped, so the border follows the entry's own corners.
struct ContactsSuggestionsEntryHeader: View {

    @ObservedObject var entry: ContactsSuggestionsEntryState

    var body: some View {
        switch entry.kind {
        case .entryAboveTheContacts:
            if entry.isVisible {
                ContactsSuggestionsEntryView(badgeCount: entry.badgeCount, hasANewCard: entry.hasANewCard, action: entry.action)
                    .textCase(nil)
                    .padding(.bottom, 16)
                    .listRowInsets(EdgeInsets())
            } else {
                // Part of the trick that removes the top padding above the grouped list.
                Color.clear.frame(height: 0).listRowInsets(EdgeInsets())
            }
        case .cardAboveTheOtherKnownUsers:
            ContactsSuggestionsOtherKnownUsersCard(showsTheRowOpeningTheDeck: entry.isVisible, action: entry.action)
                .textCase(nil)
                .padding(.bottom, 16)
                .listRowInsets(EdgeInsets())
        }
    }

}


/// The entry above a screen that has no list, such as the explanation shown when there are no one-to-one contacts yet.
struct ContactsSuggestionsEntryAboveContent<Content: View>: View {

    @ObservedObject var entry: ContactsSuggestionsEntryState
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if entry.isVisible {
                ContactsSuggestionsEntryView(badgeCount: entry.badgeCount, hasANewCard: entry.hasANewCard, action: entry.action)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            content()
                .frame(maxHeight: .infinity)
        }
    }

}
