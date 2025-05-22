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
import ObvUIObvCircledInitials
import ObvDesignSystem



/// Legacy view. Use InitialCircleViewNew instead.
public struct InitialCircleView: View {

    public struct Model: Identifiable {
        
        public let id: UUID
        
        public struct Content {
            let text: String?
            let icon: CircledInitialsIcon
            
            public init(text: String?, icon: CircledInitialsIcon) {
                self.text = text
                self.icon = icon
            }
            
        }
        
        public struct Colors: Sendable {
            let background: UIColor
            let foreground: UIColor
            
            public init(background: UIColor?, foreground: UIColor?) {
                self.background = background ?? AppTheme.shared.colorScheme.systemFill
                self.foreground = foreground ?? AppTheme.shared.colorScheme.secondaryLabel
            }
            
        }
        
        let content: Content
        let colors: Colors
        let circleDiameter: CGFloat

        public init(content: Content, colors: Colors, circleDiameter: CGFloat) {
            self.id = UUID()
            self.content = content
            self.colors = colors
            self.circleDiameter = circleDiameter
        }
        
    }
    
    
    let model: Model
    
    
    public init(model: Model) {
        self.model = model
    }

    
    private var iconSizeAdjustement: CGFloat {
        switch model.content.icon {
        case .person: return 2
        case .person3Fill: return 3
        case .personFillXmark: return 2
        case .lockFill: return 2
        case .plus: return 1
        case .personBadgePlus: return 2
        case .personFillBadgeMinus: return 2
        case .personFillBadgePlus: return 2
        }
    }
    
    
    public var body: some View {
        ZStack {
            Circle()
                .frame(width: model.circleDiameter, height: model.circleDiameter)
                .foregroundColor(Color(model.colors.background))
            if let text = model.content.text {
                Text(text)
                    .font(Font.system(size: model.circleDiameter/2.0, weight: .black, design: .rounded))
                    .foregroundColor(Color(model.colors.foreground))
            } else {
                Image(systemName: model.content.icon.icon.name)
                    .font(Font.system(size: model.circleDiameter/iconSizeAdjustement, weight: .semibold, design: .default))
                    .foregroundColor(Color(model.colors.foreground))
            }
        }
    }
}


struct InitialCircleView_Previews: PreviewProvider {
    

    private static let testModels = [
        InitialCircleView.Model(content: .init(text: "SV",
                                               icon: .person),
                                colors: .init(background: nil,
                                              foreground: nil),
                                circleDiameter: 60),
        InitialCircleView.Model(content: .init(text: "A",
                                               icon: .person),
                                colors: .init(background: .red,
                                              foreground: .blue),
                                circleDiameter: 70),
        InitialCircleView.Model(content: .init(text: "MF",
                                               icon: .person),
                                colors: .init(background: nil,
                                              foreground: nil),
                                circleDiameter: 120),
        InitialCircleView.Model(content: .init(text: nil,
                                               icon: .person),
                                colors: .init(background: .purple,
                                              foreground: .green),
                                circleDiameter: 70),
        InitialCircleView.Model(content: .init(text: nil,
                                               icon: .person),
                                colors: .init(background: .purple,
                                              foreground: .green),
                                circleDiameter: 120),
    ]
    
    static var previews: some View {
        Group {
            ForEach(testModels) { model in
                InitialCircleView(model: model)
                    .padding()
                    .background(Color(.systemBackground))
                    .environment(\.colorScheme, .dark)
                    .previewLayout(.sizeThatFits)
            }
            ForEach(testModels) { model in
                InitialCircleView(model: model)
                    .padding()
                    .background(Color(.systemBackground))
                    .environment(\.colorScheme, .light)
                    .previewLayout(.sizeThatFits)
            }
        }
    }
}
