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

struct SquircleShape: Shape {
    var curvature: CGFloat = 3
    
    func path(in rect: CGRect) -> Path {
        let a = rect.width / 2
        let b = rect.height / 2

        var path = Path()

        path.move(to: CGPoint(x: rect.midX + a, y: rect.midY))

        for angle in stride(from: 0.0, to: 360.0, by: 1.0) {
            let radians = angle * .pi / 180
            let x = pow(abs(cos(radians)), 2 / curvature) * a * sign(cos(radians))
            let y = pow(abs(sin(radians)), 2 / curvature) * b * sign(sin(radians))
            path.addLine(to: CGPoint(x: rect.midX + x, y: rect.midY + y))
        }

        path.closeSubpath()

        return path
    }

    private func sign(_ value: CGFloat) -> CGFloat {
        return value >= 0 ? 1 : -1
    }
}
