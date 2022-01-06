/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

@available(iOS 13.0, *)
struct MutedBadgeView: View {
    static let size: CGFloat = 20.0
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: MutedBadgeView.size, height: MutedBadgeView.size)
            .overlay(Image(systemName: "mic.slash.fill")
                        .font(Font.system(size: MutedBadgeView.size*0.4).bold()))
            .foregroundColor(.white)
    }
}

@available(iOS 13.0, *)
struct MutedBadgeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MutedBadgeView()
                .previewLayout(.sizeThatFits)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .light)
                .previewDisplayName("Static example in light mode")
            MutedBadgeView()
                .previewLayout(.sizeThatFits)
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
                .previewDisplayName("Static example in dark mode")
        }
    }
}
