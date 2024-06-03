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
import SwiftUI
import UI_SystemIcon



protocol GroupParametersListViewModelProtocol: ObservableObject {
    var remoteDeleteAnythingPolicy: PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy { get }
    var isReadOnly: Bool { get }
    var groupHasNoOtherMembers: Bool { get }
}


protocol GroupParametersListViewActionsProtocol: AnyObject {
    func userWantsToChangeReadOnlyParameter(isReadOnly: Bool)
    func userWantsToNavigateToAdminsChoice()
    func userWantsToNavigateToRemoteDeleteAnythingPolicyChoice()
}


struct GroupParametersListView<Model: GroupParametersListViewModelProtocol>: View {
    
    @ObservedObject var model: Model
    let actions: GroupParametersListViewActionsProtocol
    private var isReadyOnly: Binding<Bool>

    
    init(model: Model, actions: GroupParametersListViewActionsProtocol) {
        self.model = model
        self.actions = actions
        self.isReadyOnly = Binding(get: { model.isReadOnly }, set: { actions.userWantsToChangeReadOnlyParameter(isReadOnly: $0) })
    }
    
    
    var body: some View {
        
        List {
            Section("GROUP_PARAMETERS_TITLE") {
                
                if !model.groupHasNoOtherMembers {
                    GroupParameterViewCell(model: .init(parameter: .admins))
                        .contentShape(Rectangle())
                        .onTapGesture(perform: actions.userWantsToNavigateToAdminsChoice)
                }
                GroupParameterViewCell(model: .init(parameter: .remoteDelete(policy: model.remoteDeleteAnythingPolicy)))
                    .contentShape(Rectangle())
                    .onTapGesture(perform: actions.userWantsToNavigateToRemoteDeleteAnythingPolicyChoice)
                GroupParameterViewCell(model: .init(parameter: .readOnly(isReadyOnly: isReadyOnly)))
                
            }
        }
        .frame(maxWidth: .infinity)
        .listStyle(.insetGrouped)
    }
    
}



// MARK: - Previews

struct GroupParametersListView_Previews: PreviewProvider {
    
    private final class ModelForPreviews: GroupParametersListViewModelProtocol, GroupParametersListViewActionsProtocol {
        
        let groupHasNoOtherMembers = false
        
        let remoteDeleteAnythingPolicy: ObvUICoreData.PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy
        @Published private(set) var isReadOnly: Bool
        
        init(remoteDeleteAnythingPolicy: ObvUICoreData.PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy, isReadOnly: Bool) {
            self.remoteDeleteAnythingPolicy = remoteDeleteAnythingPolicy
            self.isReadOnly = isReadOnly
        }
        
        func userWantsToChangeReadOnlyParameter(isReadOnly: Bool) {
            self.isReadOnly = isReadOnly
        }

        func userWantsToNavigateToAdminsChoice() {}

        func userWantsToNavigateToRemoteDeleteAnythingPolicyChoice() {}

    }
    
    
    private static let modelForPreviews = ModelForPreviews(remoteDeleteAnythingPolicy: .nobody, isReadOnly: false)
    
    
    static var previews: some View {
        Group {
            VStack {
                Spacer()
                GroupParametersListView(model: modelForPreviews, actions: modelForPreviews)
                Spacer()
            }
            .background(Color(.systemGroupedBackground))
            .previewLayout(.sizeThatFits)
        }
    }
}
