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
import ObvDesignSystem


public struct HUDView: View {
    
    public enum Category {
        case progress
        case checkmark
        case xmark
    }
    
    let category: Category
    
    public init(category: Category) {
        self.category = category
    }

    public var body: some View {
        switch category {
        case .progress:
            HUDInnerView(category: .progress)
        case .checkmark:
            HUDInnerView(category: .checkmark)
        case .xmark:
            HUDInnerView(category: .xmark)
        }
    }
    
}


fileprivate struct HUDInnerView: View {
    
    let category: HUDView.Category
    
    private static let inAndOutAnimationScaleFactor: CGFloat = 0.7
    
    private let width: CGFloat = 150
    private var height: CGFloat { width }
    
    @State var scale: CGFloat = HUDInnerView.inAndOutAnimationScaleFactor
    
    var body: some View {
        Group {
            switch category {
            case .progress:
                ProgressView()
                    .controlSize(.large)
                    .frame(width: width, height: height, alignment: .center)
            case .checkmark:
                Image(systemIcon: .checkmarkCircle)
                    .font(Font.system(size: 80))
                    .foregroundColor(Color(AppTheme.shared.colorScheme.tertiaryLabel))
            case .xmark:
                Image(systemIcon: .xmarkCircle)
                    .font(Font.system(size: 80))
                    .foregroundColor(Color(AppTheme.shared.colorScheme.tertiaryLabel))
            }
        }
        .frame(width: width, height: height, alignment: .center)
        .background(BlurView(style: .systemUltraThinMaterial))
        .cornerRadius(16)
        .scaleEffect(scale)
        .onAppear(perform: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0)) {
                self.scale = 1.0
            }
            if category == .checkmark {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        })
        .onDisappear(perform: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0)) {
                self.scale = HUDInnerView.inAndOutAnimationScaleFactor
            }
        })
    }
}



struct HUDView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            HUDView(category: .progress)
                .padding()
            ZStack {
                Text(verbatim: "Some string for testing only")
                    .frame(width: 200, height: 200
                           , alignment: .center)
                HUDView(category: .checkmark)
                    .padding()
            }
        }
        .previewLayout(.sizeThatFits)
    }
}
