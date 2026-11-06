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

extension View {

    /// Prevents a crash on macOS 26 caused by using the `.popover` modifier on a `ToolbarItem`.
    ///
    /// This custom `ViewModifier` provides a platform-specific workaround:
    /// - Uses a `.sheet` modifier on macOS (Catalyst) to avoid the crash.
    /// - Falls back to the standard `.popover` modifier on all other platforms.
    public func popoverOrSheetOnCatalyst<PresentedContent>(isPresented: Binding<Bool>, arrowEdge: Edge? = nil, @ViewBuilder content: @escaping () -> PresentedContent) -> some View where PresentedContent : View {
        self.modifier(PopoverOrSheetOnCatalyst.init(isPresented: isPresented, arrowEdge: arrowEdge, presentedContent: content()))
    }

}

// MARK: - Internal ViewModifier

/// Prevents a crash on macOS 26 caused by using the `.popover` modifier on a `ToolbarItem`.
///
/// This custom `ViewModifier` provides a platform-specific workaround:
/// - Uses a `.sheet` modifier on macOS (Catalyst) to avoid the crash.
/// - Falls back to the standard `.popover` modifier on all other platforms.
private struct PopoverOrSheetOnCatalyst<PresentedContent: View>: ViewModifier {

    @Binding var isPresented: Bool
    let arrowEdge: Edge?
    let presentedContent: PresentedContent

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content.sheet(isPresented: $isPresented) {
            presentedContent
        }
        #else
        content.popover(isPresented: $isPresented, arrowEdge: arrowEdge) {
            presentedContent
        }
        #endif

    }

}
