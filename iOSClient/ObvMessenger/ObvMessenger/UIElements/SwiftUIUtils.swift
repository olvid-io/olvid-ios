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


extension List {

    @ViewBuilder
    func obvListStyle() -> some View {
        if #available(iOS 15.0, *) {
            self.listStyle(InsetGroupedListStyle())
        } else {
            self.listStyle(DefaultListStyle())
        }
    }

}



struct ObvProgressView: View {
    var body: some View {
        if #available(iOS 14, *) {
            ProgressView()
        } else {
            ObvActivityIndicator(isAnimating: .constant(true), style: .large, color: nil)
        }
    }
}



extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}


struct DottedCircle: View {
    let radius: CGFloat
    let pi = Double.pi
    let dotCount = 14
    let dotLength: CGFloat = 4
    let spaceLength: CGFloat

    init(radius: CGFloat) {
        self.radius = radius
        let circumerence: CGFloat = CGFloat(2.0 * pi) * radius
        self.spaceLength = circumerence / CGFloat(dotCount) - dotLength
    }

    var body: some View {
        Circle()
            .stroke(.gray, style: StrokeStyle(lineWidth: 2, lineCap: .butt, lineJoin: .miter, miterLimit: 0, dash: [dotLength, spaceLength], dashPhase: 0))
            .frame(width: radius * 2, height: radius * 2)
    }
}
