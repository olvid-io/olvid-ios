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

@available(iOS 13, *)
struct InitialCircleView: View {

    let circledTextView: Text?
    let imageSystemName: String
    let circleBackgroundColor: UIColor?
    let circleTextColor: UIColor?
    let circleDiameter: CGFloat

    init(circledTextView: Text?, imageSystemName: String, circleBackgroundColor: UIColor?, circleTextColor: UIColor?, circleDiameter: CGFloat = 70.0) {
        self.circledTextView = circledTextView
        self.imageSystemName = imageSystemName
        self.circleBackgroundColor = circleBackgroundColor
        self.circleTextColor = circleTextColor
        self.circleDiameter = circleDiameter
    }
        
    private var imageSystemSizeAdjustement: CGFloat {
        switch imageSystemName {
        case "person": return 2
        case "person.3": return 3
        case "person.3.fill": return 3
        case "person.fill": return 1.8
        default: assertionFailure(); return 1
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
                Image(systemName: imageSystemName)
                    .font(Font.system(size: circleDiameter/imageSystemSizeAdjustement, weight: .semibold, design: .default))
                    .foregroundColor(textColor)
            }
        }
    }
}


@available(iOS 13, *)
struct InitialCircleView_Previews: PreviewProvider {
    
    private struct TestData: Identifiable {
        let id = UUID()
        let circledTextView: Text?
        let imageSystemName: String
        let circleBackgroundColor: UIColor?
        let circleTextColor: UIColor?
        let circleDiameter: CGFloat
    }
    
    private static let testData = [
        TestData(circledTextView: Text("SV"),
                 imageSystemName: "person",
                 circleBackgroundColor: nil,
                 circleTextColor: nil,
                 circleDiameter: 70),
        TestData(circledTextView: Text("A"),
                 imageSystemName: "person",
                 circleBackgroundColor: .red,
                 circleTextColor: .blue,
                 circleDiameter: 70),
        TestData(circledTextView: Text("MF"),
                 imageSystemName: "person",
                 circleBackgroundColor: nil,
                 circleTextColor: nil,
                 circleDiameter: 120),
        TestData(circledTextView: nil,
                 imageSystemName: "person.fill",
                 circleBackgroundColor: .purple,
                 circleTextColor: .green,
                 circleDiameter: 70),
        TestData(circledTextView: nil,
                 imageSystemName: "person.fill",
                 circleBackgroundColor: .purple,
                 circleTextColor: .green,
                 circleDiameter: 120),
        TestData(circledTextView: nil,
                 imageSystemName: "person",
                 circleBackgroundColor: .purple,
                 circleTextColor: .green,
                 circleDiameter: 70),
    ]
    
    static var previews: some View {
        Group {
            ForEach(testData) {
                InitialCircleView(circledTextView: $0.circledTextView,
                                  imageSystemName: $0.imageSystemName,
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
                                  imageSystemName: $0.imageSystemName,
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
