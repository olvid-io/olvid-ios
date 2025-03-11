/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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

import CoreData
import ObvUICoreData
import os.log
import UIKit
import ObvDesignSystem


extension PersistedDiscussion {
    
    public func identityColors(with style: IdentityColorStyle) throws -> (background: UIColor, text: UIColor)? {
        switch try kind {
        case .oneToOne(withContactIdentity: let contactIdentity):
            guard let cryptoId = contactIdentity?.cryptoId else { return nil }
            return AppTheme.shared.identityColors(for: cryptoId, using: style)
        case .groupV1(withContactGroup: let group):
            guard let groupUid = group?.groupUid else { return nil }
            return AppTheme.shared.groupColors(forGroupUid: groupUid, using: style)
        case .groupV2(withGroup: let group):
            guard let groupIdentifier = group?.groupIdentifier else { return nil }
            return AppTheme.shared.groupV2Colors(forGroupIdentifier: groupIdentifier)
        }
    }
    
}
