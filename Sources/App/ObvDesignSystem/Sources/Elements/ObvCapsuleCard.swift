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


/// A card laying out a coloured circular icon on the leading edge, then arbitrary content, on a rounded
/// continuous-corner surface.
///
/// This is the visual idiom used by the subscription marketing rows and the onboarding scanned-license screen,
/// and is meant to be reused wherever a "feature row" look is needed.
///
/// The icon is pinned to the top of the card while the content is vertically centred, so the card reads well both
/// for single-line content (icon and content visually aligned on a common centre) and for taller, multi-line
/// content (icon stays at the top, next to the first line). The card always sizes to its content and never
/// stretches to fill the available height. The icon sits in a fixed-size circle so that the content of several
/// stacked cards lines up on a common left edge regardless of the icon's intrinsic width.
public struct ObvCapsuleCard<Content: View>: View {

    private let systemIcon: SystemIcon
    private let iconBackgroundColor: Color
    private let content: Content

    /// - Parameters:
    ///   - systemIcon: The icon shown, in white, inside the leading coloured circle.
    ///   - iconBackgroundColor: The fill of the leading circle.
    ///   - content: The content shown trailing the icon (e.g. a title and a subtitle).
    public init(systemIcon: SystemIcon, iconBackgroundColor: Color, @ViewBuilder content: () -> Content) {
        self.systemIcon = systemIcon
        self.iconBackgroundColor = iconBackgroundColor
        self.content = content()
    }

    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    private var cardBackgroundColor: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color(UIColor.systemBackground)
    }

    private let cornerRadius: CGFloat = 26.0
    private let iconDiameter: CGFloat = 44.0

    public var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(spacing: 0) {
                Image(systemIcon: systemIcon)
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .frame(width: iconDiameter, height: iconDiameter)
                    .background(iconBackgroundColor, in: Circle())
                Spacer(minLength: 0)
            }
            .padding(.trailing, 12)
            content
            Spacer(minLength: 0)
        }
        // Lock the card to its content height: the icon is top-pinned with a (vertically greedy) Spacer, so
        // without this the card would stretch to fill any excess height offered by its container.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical)
        .padding(.leading, 8)
        .padding(.trailing)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: .continuous))
    }
}


// MARK: - Previews

#if DEBUG

/// Wraps preview content in a scrollable, padded screen with the usual onboarding/shop background.
private struct CapsuleCardPreviewScreen<Content: View>: View {

    let colorScheme: ColorScheme
    @ViewBuilder let content: Content

    init(colorScheme: ColorScheme = .light, @ViewBuilder content: () -> Content) {
        self.colorScheme = colorScheme
        self.content = content()
    }

    private var background: Color {
        colorScheme == .dark ? Color(UIColor.systemBackground) : Color(UIColor.secondarySystemBackground)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                content
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .environment(\.colorScheme, colorScheme)
    }
}


/// A title + subtitle "feature row", the most common shape.
private func featureRow(_ icon: SystemIcon, _ color: Color, _ title: String, _ subtitle: String) -> some View {
    ObvCapsuleCard(systemIcon: icon, iconBackgroundColor: color) {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .font(.system(.headline, design: .rounded, weight: .bold))
            Text(verbatim: subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.leading)
    }
}


// Idea 1 — a stack of feature rows. Note how the titles line up on a common left edge despite the icons having
// different intrinsic widths (laptop+phone vs heart vs two-figures).
#Preview("Feature rows") {
    CapsuleCardPreviewScreen {
        featureRow(.macbookAndIphone, .green, "Multi-device", "Keep your messages in sync across all your devices.")
        featureRow(.phoneFill, .orange, "Secure calls & video", "Make end-to-end encrypted voice and video calls.")
        featureRow(.figureTwoAndChildHoldinghands, .blue, "Family Sharing", "Gift Olvid+ to five of your family members.")
        featureRow(.heart, .red, "Support a truly free app", "No ads, no hidden costs — just a sustainable model.")
    }
}


// Idea 2 — short single-line rows, vertically centred against the icon.
#Preview("Single line") {
    CapsuleCardPreviewScreen {
        ObvCapsuleCard(systemIcon: .checkmarkSealFill, iconBackgroundColor: .green) {
            Text(verbatim: "Standard Olvid server")
                .font(.subheadline)
        }
        ObvCapsuleCard(systemIcon: .serverRack, iconBackgroundColor: .blue) {
            Text(verbatim: "server.example.org")
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}


// Idea 3 — a trailing accessory (chevron, granted/denied badge, toggle), pushed to the trailing edge by a Spacer
// inside the content. The accessory centres against the text block, the icon stays at the top.
#Preview("Trailing accessory") {
    CapsuleCardPreviewScreen {
        ObvCapsuleCard(systemIcon: .gearshapeFill, iconBackgroundColor: .gray) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Advanced settings")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text(verbatim: "Tap to configure")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemIcon: .chevronRight)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        ObvCapsuleCard(systemIcon: .macbookAndIphone, iconBackgroundColor: .green) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Multi-device")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text(verbatim: "Included in your plan.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemIcon: .checkmarkCircleFill)
                    .font(.title2)
                    .foregroundStyle(.green)
            }
        }
        ObvCapsuleCard(systemIcon: .bell(.fill), iconBackgroundColor: .pink) {
            HStack(alignment: .center, spacing: 8) {
                Text(verbatim: "Notifications")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Spacer(minLength: 0)
                Toggle("", isOn: .constant(true))
                    .labelsHidden()
            }
        }
    }
}


// Idea 4 — status / alert cards reusing the same shape for success, info, warning and error.
#Preview("Status cards") {
    CapsuleCardPreviewScreen {
        ObvCapsuleCard(systemIcon: .checkmarkCircleFill, iconBackgroundColor: .green) {
            Text(verbatim: "Your license was added successfully.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        ObvCapsuleCard(systemIcon: .infoCircle, iconBackgroundColor: .blue) {
            Text(verbatim: "This key works on any Olvid server.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        ObvCapsuleCard(systemIcon: .exclamationmarkTriangleFill, iconBackgroundColor: .orange) {
            Text(verbatim: "This license has already been used and can no longer be activated.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        ObvCapsuleCard(systemIcon: .xmark, iconBackgroundColor: .red) {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: "We couldn't check this license. Please check your connection.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button { } label: {
                    Label { Text(verbatim: "Try again") } icon: { Image(systemIcon: .arrowClockwise) }
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
        }
    }
}


// Idea 5 — the same feature rows in dark mode (cards become the lighter surface).
#Preview("Dark mode") {
    CapsuleCardPreviewScreen(colorScheme: .dark) {
        featureRow(.macbookAndIphone, .green, "Multi-device", "Keep your messages in sync across all your devices.")
        featureRow(.giftcardFill, .purple, "Redeem a code", "Have a promo code? Apply it here.")
        featureRow(.starFill, .yellow, "Your plan", "You're subscribed to Olvid+.")
    }
}

#endif
