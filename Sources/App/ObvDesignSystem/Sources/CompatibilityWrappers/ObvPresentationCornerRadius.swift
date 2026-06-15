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


private struct ObvPresentationCornerRadiusViewModifier: ViewModifier {

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content
                .presentationCornerRadius(cornerRadius)
        } else {
            content
        }
    }

}


extension View {

    /// Wrapper around Apple's `presentationCornerRadius(_ cornerRadius: CGFloat?)` API, which is only available on iOS 16.4+.
    public func presentationCornerRadiusOniOS16Dot4(_ cornerRadius: CGFloat) -> some View {
        self.modifier(ObvPresentationCornerRadiusViewModifier(cornerRadius: cornerRadius))
    }

}
