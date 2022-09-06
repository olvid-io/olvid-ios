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

struct InitialCircleView: View {

    let circledTextView: Text?
    let systemImage: CircledInitialsIcon
    let circleBackgroundColor: UIColor?
    let circleTextColor: UIColor?
    let circleDiameter: CGFloat

    init(circledTextView: Text?, systemImage: CircledInitialsIcon, circleBackgroundColor: UIColor?, circleTextColor: UIColor?, circleDiameter: CGFloat = 70.0) {
        self.circledTextView = circledTextView
        self.systemImage = systemImage
        self.circleBackgroundColor = circleBackgroundColor
        self.circleTextColor = circleTextColor
        self.circleDiameter = circleDiameter
    }
        
    private var systemImageSizeAdjustement: CGFloat {
        switch systemImage {
        case .person: return 2
        case .person3Fill: return 3
        case .personFillXmark: return 2
        case .lockFill: return 2
        }
    }
    
    private var textColor: Color {
        Color(circleTextColor ?? AppTheme.shared.colorScheme.secondaryLabel)
    }
    
    private var backgroundColor: Color {
        Color(circleBackgroundColor ?? AppTheme.shared.colorScheme.systemFill)
    }

    var body: some View {
        ZStack {
            Circle()
                .frame(width: circleDiameter, height: circleDiameter)
                .foregroundColor(backgroundColor)
            if let circledTextView = self.circledTextView {
                circledTextView
                    .font(Font.system(size: circleDiameter/2.0, weight: .black, design: .rounded))
                    .foregroundColor(textColor)
            } else {
                Image(systemName: systemImage.icon.systemName)
                    .font(Font.system(size: circleDiameter/systemImageSizeAdjustement, weight: .semibold, design: .default))
                    .foregroundColor(textColor)
            }
        }
    }
}



struct InitialCircleView_Previews: PreviewProvider {
    
    private struct TestData: Identifiable {
        let id = UUID()
        let circledTextView: Text?
        let systemImage: CircledInitialsIcon
        let circleBackgroundColor: UIColor?
        let circleTextColor: UIColor?
        let circleDiameter: CGFloat
    }
    
    private static let testData = [
        TestData(circledTextView: Text("SV"),
                 systemImage: .person,
                 circleBackgroundColor: nil,
                 circleTextColor: nil,
                 circleDiameter: 70),
        TestData(circledTextView: Text("A"),
                 systemImage: .person,
                 circleBackgroundColor: .red,
                 circleTextColor: .blue,
                 circleDiameter: 70),
        TestData(circledTextView: Text("MF"),
                 systemImage: .person,
                 circleBackgroundColor: nil,
                 circleTextColor: nil,
                 circleDiameter: 120),
        TestData(circledTextView: nil,
                 systemImage: .person,
                 circleBackgroundColor: .purple,
                 circleTextColor: .green,
                 circleDiameter: 70),
        TestData(circledTextView: nil,
                 systemImage: .person,
                 circleBackgroundColor: .purple,
                 circleTextColor: .green,
                 circleDiameter: 120),
        TestData(circledTextView: nil,
                 systemImage: .person,
                 circleBackgroundColor: .purple,
                 circleTextColor: .green,
                 circleDiameter: 70),
    ]
    
    static var previews: some View {
        Group {
            ForEach(testData) {
                InitialCircleView(circledTextView: $0.circledTextView,
                                  systemImage: $0.systemImage,
                                  circleBackgroundColor: $0.circleBackgroundColor,
                                  circleTextColor: $0.circleTextColor,
                                  circleDiameter: $0.circleDiameter)
                    .padding()
                    .background(Color(.systemBackground))
                    .environment(\.colorScheme, .dark)
                    .previewLayout(.sizeThatFits)
            }
            ForEach(testData) {
                InitialCircleView(circledTextView: $0.circledTextView,
                                  systemImage: $0.systemImage,
                                  circleBackgroundColor: $0.circleBackgroundColor,
                                  circleTextColor: $0.circleTextColor,
                                  circleDiameter: $0.circleDiameter)
                    .padding()
                    .background(Color(.systemBackground))
                    .environment(\.colorScheme, .light)
                    .previewLayout(.sizeThatFits)
            }
        }
    }
}
