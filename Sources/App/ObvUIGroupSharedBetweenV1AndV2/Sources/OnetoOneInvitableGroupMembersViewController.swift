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

import UIKit
import SwiftUI
import ObvTypes
import ObvAppTypes
import ObvDesignSystem


public final class OnetoOneInvitableGroupMembersViewController: UIHostingController<OnetoOneInvitableGroupMembersView> {
    
    public let groupIdentifier: ObvGroupIdentifier
    
    public init(groupIdentifier: ObvGroupIdentifier,
                dataSource: OnetoOneInvitableGroupMembersViewDataSource,
                onetoOneInvitableGroupMembersViewCellDataSource: OnetoOneInvitableGroupMembersViewCellDataSource,
                avatarViewDataSource: any ObvAvatarViewDataSource,
                actions: OnetoOneInvitableGroupMembersViewActionsProtocol) {
        self.groupIdentifier = groupIdentifier
        let rootView = OnetoOneInvitableGroupMembersView(
            groupIdentifier: groupIdentifier,
            dataSource: dataSource,
            onetoOneInvitableGroupMembersViewCellDataSource: onetoOneInvitableGroupMembersViewCellDataSource,
            avatarViewDataSource: avatarViewDataSource,
            actions: actions)
        super.init(rootView: rootView)
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public var groupV1Identifier: ObvGroupV1Identifier? {
        switch groupIdentifier {
        case .groupV1(let obvGroupV1Identifier):
            return obvGroupV1Identifier
        case .groupV2:
            return nil
        }
    }
 
    public var groupV2Identifier: ObvGroupV2Identifier? {
        switch groupIdentifier {
        case .groupV1:
            return nil
        case .groupV2(let obvGroupV2Identifier):
            return obvGroupV2Identifier
        }
    }
    
}
