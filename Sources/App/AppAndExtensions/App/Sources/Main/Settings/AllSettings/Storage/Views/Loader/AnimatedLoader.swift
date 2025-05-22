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
import ObvDesignSystem

struct AnimatedLoader: View {
    @State private var degree:Int = 270
    @State private var length = 0.6
    
    var strokeWidth: CGFloat = 3.0
    
    var body: some View {
        Circle()
            .trim(from: 0.0, to: length)
            .stroke(LinearGradient(colors:[Color(uiColor: AppTheme.shared.colorScheme.newReceivedCellBackground),
                                           Color(uiColor: AppTheme.shared.colorScheme.adaptiveOlvidBlue)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    lineWidth: strokeWidth)
            .rotationEffect(Angle(degrees: Double(degree)))
            .onAppear{
                withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    length = 0
                }
                
                withAnimation(Animation.linear(duration: 1).repeatForever(autoreverses: false)) {
                    degree = 270 + 360
                }
            }
    }
}

#Preview {
    AnimatedLoader()
}
