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

/// A View Builder allowing to create a card around the content.
@available(iOS 13, *)
struct ObvCardView<Content: View>: View {
    
    let shadow: Bool
    let backgroundColor: Color
    let padding: CGFloat?
    let cornerRadius: CGFloat
    let content: Content
    
    private let shadowColor = Color(.displayP3, white: 0.0, opacity: 0.1)

    /// - parameter shadow: `true` to display a shadow, `false` otherwise. Default is `true`.
    /// - parameter backgroundColor: The background color of the card. Default is secondary system background.
    /// - parameter padding: If `nil`, a default padding is applied. Otherwise, the specified padding is used.
    /// - parameter cornerRadius: If `nil`, a default corner radius is applied. Otherwise, the specified corned radius is used.
    /// - parameter content: The content inside the card.
    init(shadow: Bool = true,
         backgroundColor: Color = Color(AppTheme.shared.colorScheme.secondarySystemBackground),
         padding: CGFloat? = nil,
         cornerRadius: CGFloat = 16.0,
         @ViewBuilder content: () -> Content) {
        self.shadow = shadow
        self.backgroundColor = backgroundColor
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(.all, padding)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: shadow ? shadowColor : .clear, radius: 10)
    }

    
}


@available(iOS 13, *)
struct ObvCardView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            
            ObvCardView {
                Text(verbatim: "A simple test")
                    .font(.body)
            }
            .previewLayout(.sizeThatFits)
            .padding()
            
            ObvCardView {
                Text(verbatim: "A simple test")
                    .font(.body)
            }
            .previewLayout(.sizeThatFits)
            .padding()
            .environment(\.colorScheme, .dark)
            
            ObvCardView(shadow: false) {
                Text(verbatim: "A simple test")
                    .font(.body)
            }
            .previewLayout(.sizeThatFits)
            .padding()
            .background(Color.gray)

            ObvCardView(shadow: false, backgroundColor: Color.red, padding: 30) {
                Text(verbatim: "A simple test")
                    .font(.body)
            }
            .previewLayout(.sizeThatFits)
            .padding()
            .background(Color.gray)

        }
    }
}
