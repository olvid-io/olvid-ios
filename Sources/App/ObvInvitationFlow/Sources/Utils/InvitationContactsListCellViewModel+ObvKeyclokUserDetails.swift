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

import Foundation
import ObvTypes
import ObvDesignSystem
import ObvAppTypes

extension ObvKeycloakUserDetails {
    
    func toInvitationContactsListCellViewModel(contactsSortOrder: ContactsSortOrder) -> InvitationContactsListCellView.Model {

        let character = circledText([firstName, lastName])
        
        let avatarModel = ObvAvatarViewModel(characterOrIcon: character != nil ? .character(character!) : .icon(.person),
                                             colors: .init(foreground: AppTheme.shared.colorScheme.secondaryLabel, background: AppTheme.shared.colorScheme.systemFill),
                                             photoURL: nil,
                                             showGreenShield: true)
        let coreDetails = ObvIdentityCoreDetails.withAcceptableDefaults(
            firstName: firstName,
            lastName: lastName,
            company: company,
            position: position,
            signedUserDetails: nil)
        return InvitationContactsListCellView.Model(
            avatarModel: avatarModel,
            coreDetails: coreDetails,
            customDisplayName: nil,
            isKeycloakManaged: true,
            wasRecentlyOnline: true,
            contactsSortOrder: contactsSortOrder)
    }
    
    func circledText(_ components: [String?]) -> Character? {
        let component = components
            .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty })
            .first
        if let char = component?.first {
            return char
        } else {
            return nil
        }
    }

}
