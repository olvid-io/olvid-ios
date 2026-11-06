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

struct MapLandmarkView: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                
                ZStack {
                    DropPin()
                        .fill(.shadow(.inner(color: .init(.sRGBLinear, white: 0, opacity: 0.15), radius: 5.0, x: 0.0, y: -5.0)))
                }
                .foregroundColor(.red)
                .shadow(radius: 3.0, x: 0.0, y: 3.0)
                
                Image(systemIcon: .mappin)
                    .font(.system(size: 24))
                    .foregroundColor(.white)
            }
            .frame(width: 45.0, height: 70.0)
            
            ZStack {
                Circle()
                    .fill(.shadow(.inner(color: .init(.sRGBLinear, white: 0, opacity: 0.15), radius: 1.0, x: 0.0, y: -3.0)))
                    .foregroundColor(.red)
            }
            .frame(width: 6.0, height: 6.0)
            .shadow(radius: 2.0, x: 0.0, y: 1.0)
            
        }
    }
}

/// The teardrop of a map pin, as a shape so that whoever draws one decides how large it is.
///
/// Public because the single discussion screen draws its own, at the size the message cell uses — see `MessageLocationView` in `ObvSingleDiscussion`. The bezier
/// lives here, and only here; the sizes belong to each screen.
public struct DropPin: Shape {
    
    public init() {}
    
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let radius = rect.width / 2.0
        let arrowSize: CGFloat = 6.0
        let arrowOffset: CGFloat = 2.0
        let arrowBasePosX: CGFloat = rect.midY + radius - arrowOffset
        let arrowTopPosX: CGFloat = rect.midY + radius + arrowSize
        let arrowRoundedBezierValue: CGFloat = 3.0
        
        // Circle
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        path.closeSubpath()
        
        // Arrow
        path.move(to: CGPoint(x: rect.midX, y: arrowTopPosX))
        
        path.addCurve(to: CGPoint(x: rect.midX - 10, y: arrowBasePosX),
                      control1: CGPoint(x: rect.midX - arrowRoundedBezierValue, y: arrowTopPosX),
                      control2: CGPoint(x: rect.midX - arrowRoundedBezierValue, y: arrowBasePosX))
        
        path.addLine(to: CGPoint(x: rect.midX + 10, y: arrowBasePosX))
        
        path.addCurve(to: CGPoint(x: rect.midX, y: arrowTopPosX),
                      control1: CGPoint(x: rect.midX + arrowRoundedBezierValue, y: arrowBasePosX),
                      control2: CGPoint(x: rect.midX + arrowRoundedBezierValue, y: arrowTopPosX))
        
        return path
    }
}


#if DEBUG

#Preview {
    MapLandmarkView()
}

#endif
