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
import ObvDesignSystem
import ObvTypes
import ObvAppTypes


struct GroupTypeViewCellHeader: View {

    struct Model: Identifiable {
        
        var id: GroupTypeValue { self.groupType }
        let groupType: GroupTypeValue
        let isSelected: Bool
        
    }

    let model: Model
    
    private var title: LocalizedStringKey {
        switch model.groupType {
        case .standard:
            return "LABEL_GROUP_STANDARD_TITLE"
        case .managed:
            return "LABEL_GROUP_MANAGED_TITLE"
        case .readOnly:
            return "LABEL_GROUP_READ_ONLY_TITLE"
        case .advanced:
            return "LABEL_GROUP_ADVANCED_TITLE"
        }
    }
    
    private var description: LocalizedStringKey {
        switch model.groupType {
        case .standard:
            return "LABEL_GROUP_STANDARD_SUBTITLE"
        case .managed:
            return "LABEL_GROUP_MANAGED_SUBTITLE"
        case .readOnly:
            return "LABEL_GROUP_READ_ONLY_SUBTITLE"
        case .advanced:
            return "LABEL_GROUP_ADVANCED_SUBTITLE"
        }
    }
    
    private var backgroundColor: Color {
        Color(.secondarySystemGroupedBackground)
    }
    
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10.0) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)
                Text(description)
                    .font(.footnote)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
    }
}



// MARK: - Previews

private let modelForPreviewsNotSelected = GroupTypeViewCellHeader.Model(groupType: .standard, isSelected: false)
private let modelForPreviewsSelected = GroupTypeViewCellHeader.Model(groupType: .standard, isSelected: true)

@available(iOS 17.0, *)
#Preview("Not selected", traits: .sizeThatFitsLayout) {
    GroupTypeViewCellHeader(model: modelForPreviewsNotSelected)
        .background(Color(.systemGroupedBackground))
}


@available(iOS 17.0, *)
#Preview("Selected", traits: .sizeThatFitsLayout) {
    GroupTypeViewCellHeader(model: modelForPreviewsSelected)
        .background(Color(.systemGroupedBackground))
}
