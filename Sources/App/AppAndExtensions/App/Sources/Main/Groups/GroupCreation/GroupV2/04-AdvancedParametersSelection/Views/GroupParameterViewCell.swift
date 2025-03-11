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
import ObvDesignSystem
import ObvSystemIcon
import ObvUICoreData



struct GroupParameterViewCell: View {
    
    let model: Model

    struct Model {
        
        let parameter: GroupParameterType

        enum GroupParameterType: Comparable, Identifiable {
                        
            case admins
            case remoteDelete(policy: PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy)
            case readOnly(isReadyOnly: Binding<Bool>)
            
            var id: Int { self.rawValue }
            
            private var rawValue: Int {
                switch self {
                case .admins: return 0
                case .remoteDelete: return 1
                case .readOnly: return 2
                }
            }
            
            static func < (lhs: GroupParameterType, rhs: GroupParameterType) -> Bool {
                lhs.rawValue < rhs.rawValue
            }

            static func == (lhs: GroupParameterViewCell.Model.GroupParameterType, rhs: GroupParameterViewCell.Model.GroupParameterType) -> Bool {
                switch lhs {
                case .admins:
                    switch rhs {
                    case .admins: return true
                    default: return false
                    }
                case .remoteDelete(let lhsPolicy):
                    switch rhs {
                    case .remoteDelete(policy: let rhsPolicy): return lhsPolicy == rhsPolicy
                    default: return false
                    }
                case .readOnly:
                    // Always return false here as we cannot compare bindings
                    return false
                }
            }

        }
        
    }
    
    
    init(model: Model) {
        self.model = model
    }
    
    
    private var icon: SystemIcon {
        switch model.parameter {
        case .admins: return .person2
        case .readOnly: return .eye
        case .remoteDelete: return .exclamationmarkBubble
        }
    }

    
    private var iconColor: Color {
        switch model.parameter {
        case .admins: return Color(UIColor.systemBlue)
        case .readOnly: return Color(UIColor.systemMint)
        case .remoteDelete: return Color(UIColor.systemPurple)
        }
    }

    
    private var titleKey: LocalizedStringKey {
        switch model.parameter {
        case .admins: return "DISCUSSION_ADMIN_CHOICE"
        case .readOnly: return "DISCUSSION_READ_ONLY"
        case .remoteDelete: return "DISCUSSION_MODERATION"
        }
    }

    
    private var subtitle: LocalizedStringKey? {
        switch model.parameter {
        case .remoteDelete(policy: let policy):
            switch policy {
            case .admins: return "TEXT_GROUP_REMOTE_DELETE_SETTING_ADMINS"
            case .everyone: return "TEXT_GROUP_REMOTE_DELETE_SETTING_EVERYONE"
            case .nobody: return "TEXT_GROUP_REMOTE_DELETE_SETTING_NOBODY"
            }
        default:
            return nil
        }
    }

    
    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Image(systemIcon: icon)
                    .foregroundColor(iconColor)
                    .frame(minWidth: 50.0)
                switch model.parameter {
                case .readOnly(isReadyOnly: let isReadyOnly):
                    Toggle(isOn: isReadyOnly) {
                        Text(titleKey)
                    }
                case .admins, .remoteDelete:
                    VStack(alignment: .leading) {
                        Text(titleKey)
                        if let subtitle {
                            Text(subtitle)
                                .font(.footnote)
                                .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        }
                    }
                    Spacer()
                    ObvChevron(selected: false)
                }
            }
            .padding(.vertical, 8)
            //.padding(.horizontal, 8)
        }
        .background(Color(.secondarySystemGroupedBackground))
    }
}



// MARK: - Previews

struct GroupParameterViewCell_Previews: PreviewProvider {
    
    private struct Preview: View {

        @State private var isReadOnly = false
        
        var body: some View {
            VStack(spacing: 0) {
                GroupParameterViewCell(model: .init(parameter: .admins))
                GroupParameterViewCell(model: .init(parameter: .remoteDelete(policy: .nobody)))
                GroupParameterViewCell(model: .init(parameter: .readOnly(isReadyOnly: $isReadOnly)))
            }
        }
        
    }
    
    static var previews: some View {
        Preview()
            .padding(EdgeInsets(top: 100.0, leading: 0.0, bottom: 100.0, trailing: 0.0))
            .background(Color(.systemGroupedBackground))
    }
    
}
