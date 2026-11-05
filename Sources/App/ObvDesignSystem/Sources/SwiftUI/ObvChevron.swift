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
import ObvSystemIcon


public struct ObvChevron: View {
    
    var selected: Bool
    
    public init(selected: Bool) {
        self.selected = selected
    }
    
    private static let normalColor = Color(AppTheme.shared.colorScheme.secondaryLabel)
    private static let selectedColor = Color(AppTheme.shared.colorScheme.olvidLight)

    private var color: Color {
        self.selected ? ObvChevron.selectedColor : ObvChevron.normalColor
    }
    
    public var body: some View {
        ZStack {
            Image(systemIcon: .chevronRightCircle)
                .imageScale(.large)
                .foregroundColor(.white)
                .colorMultiply(selected ? Color.clear : ObvChevron.normalColor)
                .animation(.spring(), value: 0.3)
                .clipShape(Circle().scale(0.7))
            Image(systemIcon: .chevronRightCircleFill)
                .imageScale(.large)
                .foregroundColor(.white)
                .colorMultiply(selected ? ObvChevron.selectedColor : Color.clear)
                .animation(.spring(), value: 0.3)
        }
    }
}



fileprivate struct ObvChevronForTesting: View {
    
    @State private var selected: Bool = false
    
    var body: some View {
        ObvChevron(selected: self.selected)
            .onTapGesture {
                withAnimation {
                    self.selected.toggle()
                }
            }
    }
    
}



struct ObvChevron_Previews: PreviewProvider {
    
    @State private var tapped: Bool = false
    
    static var previews: some View {
        Group {
            ObvChevron(selected: false)
                .previewLayout(PreviewLayout.sizeThatFits)
                .padding()
                .previewDisplayName("Light mode")
            ObvChevron(selected: true)
                .previewLayout(PreviewLayout.sizeThatFits)
                .padding()
                .previewDisplayName("Light mode (tapped)")
            ObvChevron(selected: false)
                .previewLayout(PreviewLayout.sizeThatFits)
                .padding()
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
                .previewDisplayName("Dark mode")
            ObvChevron(selected: true)
                .previewLayout(PreviewLayout.sizeThatFits)
                .padding()
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
                .previewDisplayName("Dark mode (tapped)")
            ObvChevronForTesting()
                .previewLayout(PreviewLayout.sizeThatFits)
                .padding()
                .previewDisplayName("Light mode")
            ObvChevronForTesting()
                .previewLayout(PreviewLayout.sizeThatFits)
                .padding()
                .background(Color(.systemBackground))
                .environment(\.colorScheme, .dark)
                .previewDisplayName("Dark mode")
        }
    }
}
