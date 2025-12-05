/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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


public struct ObvBadgeNumberOfNewMessages: View {
    
    let numberOfNewReceivedMessages: Int
    
    public init(numberOfNewReceivedMessages: Int) {
        self.numberOfNewReceivedMessages = numberOfNewReceivedMessages
    }
    
    private var valueAsString: String {
        if numberOfNewReceivedMessages > 99 {
            return "99+"
        } else {
            return String(numberOfNewReceivedMessages)
        }
    }
    
    public var body: some View {
        Text(valueAsString)
            .monospacedDigit()
            .bold()
            .contentTransitionOniOS16(.numericText(value: Double(numberOfNewReceivedMessages)))
            .foregroundColor(.white)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8.0)
            .padding(.vertical, 4.0)
            .background(Capsule().foregroundColor(Color(uiColor: .red)))
            .transition(.scale.animation(.easeInOut(duration: 0.15)))
    }
    
}
