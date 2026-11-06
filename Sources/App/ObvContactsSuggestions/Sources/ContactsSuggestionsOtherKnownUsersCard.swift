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
import ObvSystemIcon
import ObvDesignSystem


/// The card at the top of the list of the other known users: it says who they are, and opens the deck of all of them, the ``ContactSuggestion/Scope/allOtherKnownUsers``
/// one. Android shows the same card, with the same text.
public struct ContactsSuggestionsOtherKnownUsersCard: View {

    /// Whether the deck of all the other known users has a card. Without one, the card only explains the list.
    private let showsTheRowOpeningTheDeck: Bool
    private let action: () -> Void

    public init(showsTheRowOpeningTheDeck: Bool, action: @escaping () -> Void) {
        self.showsTheRowOpeningTheDeck = showsTheRowOpeningTheDeck
        self.action = action
    }

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 20

    /// The radius of the cells of the list beneath the card.
    private static var cornerRadius: CGFloat { ObvCardViewParameters.defaultCornerRadius }

    // The colours are absolute rather than `.primary` and `.secondary`, which resolve against the style around the view: placed in a list's section
    // header, which is drawn in the secondary style, those dimmed the whole card.
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("THE_USERS_BELOW_ARE_NOT_PART_OF_YOUR_CONTACTS")
                .font(.callout)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
            if showsTheRowOpeningTheDeck {
                Divider()
                    .padding(.horizontal, 16)
                Button(action: action) {
                    HStack(spacing: 12) {
                        Image(systemIcon: .rectangleStackBadgePlus)
                            .font(.system(size: iconSize))
                            .accessibilityHidden(true)
                        Text("INVITE_THESE_USERS_WITH_A_SWIPE")
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        // The chevron of a contact cell, so that both sit on the same vertical line.
                        ObvChevron(selected: false)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Color(uiColor: AppTheme.shared.colorScheme.olvidLight))
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        // A list's section header sets a smaller font of its own: what takes its size from the font around it, such as the chevron, is given the one
        // of the cells beneath.
        .font(.body)
        .background {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }

}
