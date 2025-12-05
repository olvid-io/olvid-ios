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


struct ObvcontentMargins: ViewModifier {
    
    private let edges: Edge.Set
    private let insets: EdgeInsets

    init(edges: Edge.Set, insets: EdgeInsets) {
        self.edges = edges
        self.insets = insets
    }
    
    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content
                .contentMargins(edges, insets)
        } else {
            content
        }
    }
    
}


extension View {
    
    /// Wrapper around Apple's `contentMargins(_ edges: Edge.Set = .all, _ insets: EdgeInsets, for placement: ContentMarginPlacement = .automatic)` API, which is only available on iOS 17+.
    public func contentMarginsOniOS17(_ edges: Edge.Set = .all, _ insets: EdgeInsets) -> some View {
        self.modifier(ObvcontentMargins(edges: edges, insets: insets))
    }
    
}
