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
import ObvDesignSystem


protocol GroupModerationViewModelProtocol: ObservableObject {
    var currentPolicy: PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy { get }
}


protocol GroupModerationViewActionsProtocol: AnyObject {
    func userWantsToChangeRemoteDeleteAnythingPolicy(to policy: PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy)
}


struct GroupModerationView<Model: GroupModerationViewModelProtocol>: View {
    
    @ObservedObject var model: Model
    let actions: GroupModerationViewActionsProtocol
    
    private func title(for policy: PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy) -> LocalizedStringKey {
        switch policy {
        case .admins: return "TEXT_GROUP_REMOTE_DELETE_SETTING_ADMINS"
        case .everyone: return "TEXT_GROUP_REMOTE_DELETE_SETTING_EVERYONE"
        case .nobody: return "TEXT_GROUP_REMOTE_DELETE_SETTING_NOBODY"
        }
    }
    
    var body: some View {
        VStack {
            List {
                Section("PREV_DISCUSSION_REMOTE_DELETE_TITLE") {
                    ForEach(PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy.allCases.sorted()) { policy in
                        HStack() {
                            Text(title(for: policy))
                            Spacer()
                            if policy == model.currentPolicy {
                                Image(systemIcon: .checkmark)
                                    .foregroundColor(Color("Blue01"))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            actions.userWantsToChangeRemoteDeleteAnythingPolicy(to: policy)
                        }
                    }
                    
                }
            }
            
        }
    }
}


// MARK: - Previews

struct GroupModerationView_Previews: PreviewProvider {
    
    
    private final class ModelForPreview: GroupModerationViewModelProtocol, GroupModerationViewActionsProtocol {
        
        @Published private(set) var currentPolicy = ObvUICoreData.PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy.nobody
        
        func userWantsToChangeRemoteDeleteAnythingPolicy(to policy: ObvUICoreData.PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy) {
            self.currentPolicy = policy
        }
        
    }
    
    
    private static let modelForPreview = ModelForPreview()
    

    static var previews: some View {
        Group {
            GroupModerationView(model: modelForPreview, actions: modelForPreview)
        }
        .previewLayout(.sizeThatFits)
    }
}
