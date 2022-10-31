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


/// This view is used when displaying an ContactIdentityCardView, for example, to show a small white label on a green background on the top left corner.
struct TopLeftTextForCardView: View {
    
    let text: Text
    let backgroundColor = Color.green
    let textColor = Color.white
    
    var body: some View {
        text
            .font(.footnote)
            .fontWeight(.medium)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .foregroundColor(.white)
            .background(
                ObvRoundedRectangle(tl: 16, tr: 0, bl: 0, br: 16)
                    .foregroundColor(.green)
            )
    }
    
}
