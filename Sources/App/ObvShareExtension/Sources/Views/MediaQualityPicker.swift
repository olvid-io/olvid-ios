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

// MARK: - MediaQualityPicker

/// A SwiftUI view that provides a toggle button for switching between standard and HD media quality.
///
/// The picker is an "HD" badge inside the glass capsule its caller applies. When HD is enabled the badge
/// is filled and carries a checkmark; when disabled it is outlined. Both states are drawn in `label` and
/// `systemBackground`, so the control follows the appearance rather than assuming a dark backdrop.
///
/// The view animates smoothly between states using ease-in-out animations.
struct MediaQualityPicker: View {
    /// The shared state object that manages the current media quality setting
    @ObservedObject var sharedState: SharedState

    /// Told about each switch so the choice survives to the next share
    let actions: any ShareExtensionViewActions

    /// Computed property that determines if HD quality is currently enabled
    private var isHDEnabled: Bool {
        sharedState.mediaQuality == .high
    }

    var body: some View {
        Button {
            let chosenMediaQuality: ObvMediaQuality = isHDEnabled ? .standard : .high
            // Toggle between standard and high quality with animation
            withAnimation(.easeInOut(duration: 0.2)) {
                sharedState.mediaQuality = chosenMediaQuality
            }
            // The assignment stays here rather than in the action: it belongs to the animation above, which
            // the app layer has no business owning. The action only has to remember the answer.
            actions.userChoseMediaQuality(chosenMediaQuality)
        } label: {
            ZStack {
                // "HD" badge - filled when enabled, outlined when disabled

                if isHDEnabled {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(uiColor: .label))
                        .frame(width: 22, height: 14)

                    Text("HD")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(uiColor: .label), lineWidth: 1.0)
                        .frame(width: 22, height: 14)

                    Text("HD")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(uiColor: .label))
                }


                // Checkmark indicator shown only when HD is enabled. Inverted against the badge it overlaps,
                // so it reads whichever of the two it sits on.
                if isHDEnabled {
                    ZStack {
                        Circle()
                            .fill(Color(uiColor: .systemBackground))
                            .frame(width: 14, height: 14)

                        Image(systemIcon: .checkmark)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color(uiColor: .label))
                    }
                    .offset(x: 10, y: 6) // Position in bottom-right corner of badge
                }
            }
            // The same box the close button beside it asks for, so the two glass capsules match. This view
            // draws no background of its own: `glassButtonStyle()` is what makes the circle, and an opaque
            // one painted inside it read as a grey blob ringed by the glass's own hairline — invisible in
            // dark mode, where the two happened to agree, and wrong in light mode.
            .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isHDEnabled) // Smooth state transitions
    }
}
