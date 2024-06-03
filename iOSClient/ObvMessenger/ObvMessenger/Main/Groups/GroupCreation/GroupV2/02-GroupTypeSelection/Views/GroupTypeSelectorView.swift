/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvTypes
import ObvUICoreData


struct GroupTypeSelectorView: View {

    @Binding var selectedGroupType: GroupTypeValue?

    var body: some View {
        List {
            ForEach(GroupTypeValue.allCases) { groupType in
                GroupTypeViewCell(model: .init(groupType: groupType, isSelected: groupType == selectedGroupType))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .onTapGesture {
                        selectedGroupType = groupType
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .listStyle(.plain)
    }
    
}


// MARK: - Previews

struct GroupTypeSelectorView_Previews: PreviewProvider {
    
    struct PreviewContainer: View {

        @State private var selectedGroupType: GroupTypeValue?
        
        var body: some View {
            GroupTypeSelectorView(selectedGroupType: $selectedGroupType)
        }
        
    }
    
    static var previews: some View {
        PreviewContainer()
        .previewLayout(.sizeThatFits)
    }

}
