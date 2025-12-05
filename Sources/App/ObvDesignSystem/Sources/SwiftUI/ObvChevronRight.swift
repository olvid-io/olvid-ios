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


public struct ObvChevronRight: View {
    
    let isHiglihted: Bool
    
    public init(isHiglihted: Bool = false) {
        self.isHiglihted = isHiglihted
    }
    
    @ViewBuilder
    var content: some View {
        ZStack {
            Image(systemIcon: .chevronRightCircle).opacity(0)
            Image(systemIcon: .chevronRight).opacity(0)
            Image(systemIcon: isHiglihted ? .chevronRightCircle : .chevronRight)
        }
        .foregroundStyle(isHiglihted ? .primary : .tertiary)
        .foregroundColor(isHiglihted ? .accentColor : .primary)
        .font(.callout)
    }
    
    public var body: some View {
        if #available(iOS 17, *) {
            content
                .contentTransition(.symbolEffect(.replace))
        } else {
            content
        }
    }
}


#Preview {
    HStack {
        ObvChevronRight(isHiglihted: false)
        ObvChevronRight(isHiglihted: true)
    }
}




@available(iOS 17.0, *)
struct ReplaceSymbolAnimationView: View {

    @State var isHiglihted = false
    
    var body: some View {
        HStack {
            Toggle(String(describing: "isHiglihted"), isOn: $isHiglihted)
            ObvChevronRight(isHiglihted: isHiglihted)
        }
    }
}


@available(iOS 17.0, *)
#Preview {
    ReplaceSymbolAnimationView()
}
