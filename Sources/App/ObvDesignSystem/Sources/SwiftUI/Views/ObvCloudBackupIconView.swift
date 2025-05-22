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


public struct ObvCloudBackupIconView: View {
    
    private let withIntroAnimation: Bool
    private let size: Size
    
    public enum Size {
        case small
        case large
    }
    
    public init(withIntroAnimation: Bool = true, size: Size = .large) {
        self.withIntroAnimation = withIntroAnimation
        self.size = size
    }
        
    @State private var rotationAngle: Double = 360
    @State private var scale: CGFloat = 0.2
    @State private var blurRadius: CGFloat = 5
    
    private var cloudFillSize: CGSize {
        switch size {
        case .small:
            return CGSize(width: 16, height: 16)
        case .large:
            return CGSize(width: 64, height: 64)
        }
    }
    
    private var cloudFillFontSize: CGFloat {
        switch size {
        case .small:
            return 18
        case .large:
            return 72
        }
    }
    
    private var arrowCounterclockwise: CGFloat {
        switch size {
        case .small:
            return 7
        case .large:
            return 28
        }
    }
    
    private var offset: CGPoint {
        switch size {
        case .small:
            return CGPoint(x: 0, y: 0)
        case .large:
            return CGPoint(x: 0, y: 2)
        }
    }
    
    public var body: some View {
        ZStack(alignment: .center) {
            Image(systemIcon: .cloudFill)
                .foregroundStyle(.green)
                .font(.system(size: cloudFillFontSize))
                .frame(width: cloudFillSize.width, height: cloudFillSize.height)
            Image(systemIcon: .arrowCounterclockwise)
                .foregroundStyle(.white)
                .font(.system(size: arrowCounterclockwise, weight: .black))
                .offset(x: offset.x, y: offset.y)
                .rotationEffect(.degrees(rotationAngle))
        }
        .scaleEffect(scale)
        .opacity(scale)
        .blur(radius: blurRadius)
        .onAppear {
            if withIntroAnimation {
                withAnimation(.bouncy(duration: 1)) {
                    rotationAngle = 0
                    scale = 1.0
                    blurRadius = 0.0
                }
            } else {
                rotationAngle = 0
                scale = 1.0
                blurRadius = 0.0
            }
        }
    }
}


// MARK: - Previews

#Preview("Large") {
    ObvCloudBackupIconView()
}

#Preview("Small") {
    ObvCloudBackupIconView(size: .small)
}
