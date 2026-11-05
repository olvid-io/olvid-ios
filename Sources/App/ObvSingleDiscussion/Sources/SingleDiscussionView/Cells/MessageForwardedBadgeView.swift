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


/// Says that a message was not written here but forwarded from somewhere else — the legacy `ForwardView`.
///
/// Above the bubble and below the missed-message bubble, on both sides of the discussion. The icon is `ObvMessengerConstants.forwardIcon`, copied rather than
/// reached for, this module knowing nothing of the app's constants — as its translations are copied for the same reason.
struct MessageForwardedBadgeView: View {

    var body: some View {
        HStack(spacing: Self.gapBetweenTheIconAndTheWord) {
            Image(systemIcon: .arrowshapeTurnUpForward)
            Text("Forwarded")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }


    /// The 2pt between the icon and the label in `ForwardView`.
    private static let gapBetweenTheIconAndTheWord: CGFloat = 2

}


#if DEBUG

#Preview {
    MessageForwardedBadgeView()
        .padding()
}

#endif
