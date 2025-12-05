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
import ObvAppTypes


/// A simple list of `SingleGroupMemberView`
public struct SingleGroupMembersListView: View {

    let model: Model
    let dataSources: DataSources
    
    public struct Model {
        let groupIdentifier: ObvGroupIdentifier
        let mode: SingleGroupMemberView.Mode
        let singleGroupMemberViewModelIdentifiers: [SingleGroupMemberView.Model.Identifier]
        let showOwnedIdentity: Bool // Never shown in group creation mode
        @Binding var selectedMembers: Set<SingleGroupMemberView.Model.Identifier> // Must be a binding
        @Binding var membersWithUpdatedAdminPermission: Set<MemberIdentifierAndPermissions> // Must be a binding

        init(groupIdentifier: ObvGroupIdentifier,
             mode: SingleGroupMemberView.Mode,
             singleGroupMemberViewModelIdentifiers: [SingleGroupMemberView.Model.Identifier],
             showOwnedIdentity: Bool,
             selectedMembers: Binding<Set<SingleGroupMemberView.Model.Identifier>> = .constant([]),
             membersWithUpdatedAdminPermission: Binding<Set<MemberIdentifierAndPermissions>> = .constant([])) {
            self.groupIdentifier = groupIdentifier
            self.mode = mode
            self.singleGroupMemberViewModelIdentifiers = singleGroupMemberViewModelIdentifiers
            self.showOwnedIdentity = showOwnedIdentity
            self._selectedMembers = selectedMembers
            self._membersWithUpdatedAdminPermission = membersWithUpdatedAdminPermission
        }
    }
    
    public struct DataSources {
        let ownedIdentityAsGroupMemberViewDataSource: OwnedIdentityAsGroupMemberViewDataSource
        let avatarViewDataSource: ObvAvatarViewDataSource
        let singleGroupMemberViewDataSource: SingleGroupMemberViewDataSource
        
        public init(ownedIdentityAsGroupMemberViewDataSource: OwnedIdentityAsGroupMemberViewDataSource,
                    avatarViewDataSource: ObvAvatarViewDataSource,
                    singleGroupMemberViewDataSource: SingleGroupMemberViewDataSource) {
            self.ownedIdentityAsGroupMemberViewDataSource = ownedIdentityAsGroupMemberViewDataSource
            self.avatarViewDataSource = avatarViewDataSource
            self.singleGroupMemberViewDataSource = singleGroupMemberViewDataSource
        }
        
    }
    
    private let leadingPaddingForDivider: CGFloat = 70.0

    public var body: some View {
        LazyVStack {
            if model.showOwnedIdentity {
                VStack {
                    OwnedIdentityAsGroupMemberView(groupIdentifier: model.groupIdentifier,
                                                   dataSource: dataSources.ownedIdentityAsGroupMemberViewDataSource,
                                                   avatarViewDataSource: dataSources.avatarViewDataSource)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    if !model.singleGroupMemberViewModelIdentifiers.isEmpty {
                        Divider()
                            .padding(.leading, leadingPaddingForDivider)
                    }
                }
            }
            ForEach(model.singleGroupMemberViewModelIdentifiers) { memberIdentifier in
                VStack {
                    SingleGroupMemberView(mode: model.mode,
                                          modelIdentifier: memberIdentifier,
                                          dataSource: dataSources.singleGroupMemberViewDataSource,
                                          avatarViewDataSource: dataSources.avatarViewDataSource,
                                          selectedMembers: model.$selectedMembers,
                                          membersWithUpdatedAdminPermission: model.$membersWithUpdatedAdminPermission)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    if memberIdentifier != model.singleGroupMemberViewModelIdentifiers.last {
                        Divider()
                            .padding(.leading, leadingPaddingForDivider)
                    }
                }
            }
        }
    }
    
}
