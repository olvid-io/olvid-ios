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
import ObvUICoreData
import ObvDesignSystem
import ObvUI

@MainActor
final class GroupTypeViewModel<UserModel: SingleUserViewForHorizontalUsersLayoutModelProtocol>: HorizontalUsersViewModelProtocol {

    let selectedUsersOrdered: [UserModel] // Group members
    let preselectedGroupType: GroupTypeValue?
    
    init(selectedUsersOrdered: [UserModel], preselectedGroupType: GroupTypeValue?) {
        self.selectedUsersOrdered = selectedUsersOrdered
        self.preselectedGroupType = preselectedGroupType
    }
    
}


protocol GroupTypeViewActionsProtocol: AnyObject {
    func userDidSelectGroupType(selectedGroupType: GroupTypeValue) async
}


struct GroupTypeView<UserModel: SingleUserViewForHorizontalUsersLayoutModelProtocol>: View {
    
    let model: GroupTypeViewModel<UserModel>
    let actions: GroupTypeViewActionsProtocol
    
    
    private func userDidSelectGroupType() {
        guard let selectedGroupType else { return }
        Task {
            await actions.userDidSelectGroupType(selectedGroupType: selectedGroupType)
        }
    }
    
    
    @State private var selectedGroupType: GroupTypeValue?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            if !model.selectedUsersOrdered.isEmpty {
                
                HStack(spacing: 2.0) {
                    Text("CHOSEN_MEMBERS")
                        .textCase(.uppercase)
                    Text(verbatim: "(\(model.selectedUsersOrdered.count))")
                }
                .font(.footnote)
                .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                .padding(EdgeInsets(top: 0.0, leading: 40.0, bottom: 6.0, trailing: 40.0))
                
                HorizontalUsersView(model: model,
                                    configuration: HorizontalUsersViewConfiguration(textOnEmptySetOfUsers: "", canEditUsers: false),
                                    actions: nil)
                    .padding(EdgeInsets(top: 0.0, leading: 20.0, bottom: 0.0, trailing: 20.0))
                
            }
            
            Text("GROUP_TYPE_TITLE")
                .textCase(.uppercase)
                .font(.footnote)
                .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                .padding(EdgeInsets(top: 30.0, leading: 40.0, bottom: 6.0, trailing: 40.0))
            
            GroupTypeSelectorView(selectedGroupType: $selectedGroupType)
            
            VStack {
                OlvidButton(style: .blue, title: Text(CommonString.Word.Next), systemIcon: nil, action: userDidSelectGroupType)
                    .disabled(selectedGroupType == nil)
                    .padding()
            }.background(.ultraThinMaterial)
        }
        .onAppear {
            if selectedGroupType == nil {
                selectedGroupType = model.preselectedGroupType
            }
        }
    }
}


// MARK: - Previews

struct GroupTypeView_Previews: PreviewProvider {
    
    private static let allGroupTypes: [PersistedGroupV2.GroupType] = [
        .standard,
        .managed,
        .readOnly,
        .advanced(isReadOnly: false, remoteDeleteAnythingPolicy: .nobody),
    ]
    
    private final class ActionsForPreview: GroupTypeViewActionsProtocol {
        func userDidSelectGroupType(selectedGroupType: GroupTypeValue) async {}
    }
    
    private static let actionsForPreview = ActionsForPreview()

    static var previews: some View {
        GroupTypeView(model: .init(selectedUsersOrdered: [PersistedObvContactIdentity](), preselectedGroupType: nil), actions: actionsForPreview)
            .previewLayout(.sizeThatFits)
    }

}
