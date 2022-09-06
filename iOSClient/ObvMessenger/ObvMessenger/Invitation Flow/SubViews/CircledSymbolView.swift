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

struct CircledSymbolView: View {

    let systemIcon: ObvSystemIcon
    var radius: CGFloat = 28

    var body: some View {
        ZStack {
            Rectangle()
                .foregroundColor(Color(.clear))
            Circle()
                .foregroundColor(.white)
                .frame(width: radius, height: radius)
            Circle()
                .foregroundColor(.blue)
                .frame(width: radius*0.9, height: radius*0.9)
            Image(systemIcon: systemIcon)
                .foregroundColor(.white)
                .font(.system(size: 12))
                .offset(CGSize(width: 0.0, height: -0.5))
        }.frame(width: 44, height: 44)
    }
}


struct CircledCameraView: View {

    var body: some View {
        CircledSymbolView(systemIcon: .camera(.fill))
    }
}


struct CircledCameraView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            CircledCameraView()
                .background(Color.red)
                .previewLayout(.sizeThatFits)
        }
    }
}
