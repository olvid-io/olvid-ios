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


/// A close button. By default Esc presses it too, through `.keyboardShortcut(.cancelAction)`.
public struct ObvButtonWithCancelRole: View {

    private let action: () -> Void
    private let escapeKeyPressesIt: Bool

    /// - Parameter escapeKeyPressesIt: Pass `false` where Esc must not do what this button does.
    public init(escapeKeyPressesIt: Bool = true, action: @escaping () -> Void) {
        self.action = action
        self.escapeKeyPressesIt = escapeKeyPressesIt
    }

    public var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Button(role: .cancel, action: action)
            } else {
                Button(action: action) {
                    Image(systemIcon: .xmarkCircleFill)
                        .font(Font.system(size: 24, weight: .semibold, design: .default))
                }
            }
        }
        .keyboardShortcut(escapeKeyPressesIt ? .cancelAction : nil)
    }

}
