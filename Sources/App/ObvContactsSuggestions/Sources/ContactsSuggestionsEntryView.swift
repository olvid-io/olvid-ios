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


/// The entry at the top of the list of contacts that opens the contacts suggestions. Shown only while there is something to suggest.
public struct ContactsSuggestionsEntryView: View {

    /// The number of cards in the deck, as on the badge of the contacts tab; 0 hides the badge.
    private let badgeCount: Int
    /// Whether a card is new since the user last opened the deck: the badge is then red, and grey otherwise, as on the contacts tab.
    private let hasANewCard: Bool
    private let action: () -> Void

    public init(badgeCount: Int, hasANewCard: Bool, action: @escaping () -> Void) {
        self.badgeCount = badgeCount
        self.hasANewCard = hasANewCard
        self.action = action
    }

    @ScaledMetric(relativeTo: .title2) private var iconSize: CGFloat = 26

    /// The diameter of the picture of a contact cell beneath, which does not scale: the icon is centred where the picture is, and the texts start
    /// where the name does.
    private static let widthOfTheIconColumn: CGFloat = 60

    /// The radius of the cells of the list of contacts beneath the entry.
    private static var cornerRadius: CGFloat { ObvCardViewParameters.defaultCornerRadius }

    // The colours are absolute rather than `.primary` and `.secondary`, which resolve against the style around the view: placed in a list's
    // section header, which is drawn in the secondary style, those dimmed the whole entry.
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemIcon: .rectangleStackBadgePlus)
                    .font(.system(size: iconSize))
                    .foregroundStyle(Color(uiColor: AppTheme.shared.colorScheme.olvidLight))
                    .frame(width: Self.widthOfTheIconColumn)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SUGGESTED_CONTACTS")
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: .label))
                    Text("INVITE_USERS_EASILY")
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack {
                    if badgeCount > 0 {
                        // The red of the other badges drawn in SwiftUI, such as the sidebar's, beside the entry on an iPad.
                        ObvBadgeNumberOfNewMessages(numberOfNewReceivedMessages: badgeCount, color: Color(uiColor: hasANewCard ? .red : .systemGray))
                    }
                    // The chevron of a contact cell, so that both sit on the same vertical line.
                    ObvChevron(selected: false)
                        .accessibilityHidden(true)
                }
            }
            // A list's section header sets a smaller font of its own: what takes its size from the font around it, such as the chevron, is given the
            // one of the cells beneath.
            .font(.body)
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            }
            // A stroke rather than `rainbowBorder`, which fills a whole rectangle with the gradient under the entry: as the entry appeared, that rectangle
            // showed before the entry's own background did.
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(AngularGradient.rainbow, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

}
