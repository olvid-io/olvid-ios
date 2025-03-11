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


protocol GroupParametersViewModelProtocol: GroupParametersListViewModelProtocol, HorizontalUsersViewModelProtocol, ObservableObject {
    var selectedUsersOrdered: [UserModel] { get }
}


protocol GroupParametersViewActionsProtocol: AnyObject, GroupParametersListViewActionsProtocol {
    func userWantsToNavigateToNextScreen()
}


struct GroupParametersView<Model: GroupParametersViewModelProtocol>: View {
    
    @ObservedObject var model: Model
    let actions: GroupParametersViewActionsProtocol
    
    private let configuration = HorizontalUsersViewConfiguration(textOnEmptySetOfUsers: "", canEditUsers: false)
    
    var body: some View {
            
        VStack(alignment: .leading, spacing: 0) {
            
            if !model.selectedUsersOrdered.isEmpty {
                
                VStack(alignment: .leading, spacing: 0) {
                    
                    HStack(spacing: 2.0) {
                        Text("CHOSEN_MEMBERS")
                            .textCase(.uppercase)
                        Text(verbatim: "(\(model.selectedUsersOrdered.count))")
                    }
                    .font(.footnote)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    .padding(EdgeInsets(top: 0.0, leading: 30.0, bottom: 6.0, trailing: 40.0))
                    
                    HorizontalUsersView(model: model, configuration: configuration, actions: nil)
                        .padding(.horizontal, 20)
                    
                }
                .padding(.top, 30)
                
            }
            
            GroupParametersListView(model: model, actions: actions)
            
            VStack {
                OlvidButton(style: .blue, title: Text(CommonString.Word.Next), systemIcon: nil, action: actions.userWantsToNavigateToNextScreen)
                    .padding()
            }.background(.ultraThinMaterial)

        }
        
    }
}



// MARK: - Previews

struct GroupParametersView_Previews: PreviewProvider {
    
    private final class ModelForPreview: GroupParametersViewModelProtocol, GroupParametersViewActionsProtocol {
        let groupHasNoOtherMembers = false
        let canEditContacts = false
        let remoteDeleteAnythingPolicy: ObvUICoreData.PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy = .nobody
        private(set) var isReadOnly = false
        let selectedUsersOrdered = [PersistedObvContactIdentity]()
        
        func userWantsToChangeReadOnlyParameter(isReadOnly: Bool) {
            self.isReadOnly = isReadOnly
        }
        
        func userWantsToNavigateToAdminsChoice() {}
        
        func userWantsToNavigateToRemoteDeleteAnythingPolicyChoice() {}
        
        func userWantsToNavigateToNextScreen() {}

    }
    
    private static let modelForPreview = ModelForPreview()
    
    static var previews: some View {
        GroupParametersView(model: modelForPreview, actions: modelForPreview)
    }
    
}
