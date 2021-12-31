/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
struct ObvChevron: View {
    
    var selected: Bool
    
    private static let normalColor = Color(AppTheme.shared.colorScheme.secondaryLabel)
    private static let selectedColor = Color(AppTheme.shared.colorScheme.olvidLight)

    private var color: Color {
        self.selected ? ObvChevron.selectedColor : ObvChevron.normalColor
    }
    
    var body: some View {
        ZStack {
            Image(systemIcon: .chevronRightCircle)
                .imageScale(.large)
                .foregroundColor(.white)
                .colorMultiply(selected ? Color.clear : ObvChevron.normalColor)
                .animation(.spring())
                .clipShape(Circle().scale(0.7))
            Image(systemIcon: .chevronRightCircleFill)
                .imageScale(.large)
                .foregroundColor(.white)
                .colorMultiply(selected ? ObvChevron.selectedColor : Color.clear)
                .animation(.spring())
        }
    }
}


@available(iOS 13, *)
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


@available(iOS 13, *)
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
