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


/// A rainbow angular gradient cycling through red, yellow, green, blue, and purple.
/// Typically used as the fill for a rainbow border around a selected card.
public extension AngularGradient {
    static var rainbow: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [.red, .yellow, .green, .blue, .purple, .red]),
            center: .center
        )
    }
}


public extension View {

    /// Adds a 1pt rainbow border around the view when `isActive` is `true`.
    ///
    /// The border is rendered as a `RoundedRectangle` filled with ``AngularGradient/rainbow``
    /// placed in the background, with the view padded by 1pt so the border is visible around it.
    ///
    /// - Parameters:
    ///   - cornerRadius: The corner radius of the **content** view (i.e. the inner rounded rectangle).
    ///     The border shape uses `cornerRadius + 1` so it perfectly wraps the content.
    ///   - isActive: When `false`, no border is drawn and no padding is added.
    func rainbowBorder(cornerRadius: CGFloat, isActive: Bool) -> some View {
        self
            .padding(1)
            .background {
                if isActive {
                    RoundedRectangle(
                        cornerSize: .init(width: cornerRadius + 1, height: cornerRadius + 1),
                        style: .continuous
                    )
                    .foregroundStyle(AngularGradient.rainbow)
                }
            }
    }

}
