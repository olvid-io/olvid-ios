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



private struct ObvLineLimitAndReserveSpace: ViewModifier {
    
    let limit: Int
    let reservesSpace: Bool
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .lineLimit(limit, reservesSpace: reservesSpace)
        } else {
            content
                .lineLimit(limit)
        }
    }

}


extension View {
    
    /// Wrapper around Apple's `lineLimit(_:reservesSpace:)` API, which
    /// is onylavailable on iOS16+.
    
    public func lineLimitOniOS16(_ limit: Int, reservesSpace: Bool) -> some View {
        self.modifier(ObvLineLimitAndReserveSpace(limit: limit, reservesSpace: reservesSpace))
    }
    
}
