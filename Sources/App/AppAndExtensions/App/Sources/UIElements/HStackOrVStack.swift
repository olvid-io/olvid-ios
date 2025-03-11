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


//struct HStackOrVStack<Content: View>: View {
//    
//    let useHStack: Bool
//    let hstackAlignment: VerticalAlignment = .center
//    let hstackSpacing: CGFloat? = nil
//    let vstackAlignment: HorizontalAlignment = .center
//    let vstackSpacing: CGFloat? = nil
//    let content: () -> Content
//    
//    var body: some View {
//        Group {
//            if useHStack {
//                HStack(alignment: hstackAlignment, spacing: hstackSpacing, content: content)
//            } else {
//                VStack(alignment: vstackAlignment, spacing: vstackSpacing, content: content)
//            }
//        }
//    }
//    
//}


struct HStackOrVStack<Content: View>: View {
    
    let useHStack: Bool
    let hstackAlignment: VerticalAlignment
    let hstackSpacing: CGFloat?
    let vstackAlignment: HorizontalAlignment
    let vstackSpacing: CGFloat?
    let content: Content

    init(useHStack: Bool, hstackAlignment: VerticalAlignment = .center, hstackSpacing: CGFloat? = nil, vstackAlignment: HorizontalAlignment = .center, vstackSpacing: CGFloat? = nil, @ViewBuilder _ content: () -> Content) {
        self.useHStack = useHStack
        self.hstackAlignment = hstackAlignment
        self.hstackSpacing = hstackSpacing
        self.vstackAlignment = vstackAlignment
        self.vstackSpacing = vstackSpacing
        self.content = content()
    }

    var body: some View {
        if useHStack {
            HStack(alignment: hstackAlignment, spacing: hstackSpacing) { content }
        } else {
            VStack(alignment: vstackAlignment, spacing: vstackSpacing) { content }
        }
    }
    
}
