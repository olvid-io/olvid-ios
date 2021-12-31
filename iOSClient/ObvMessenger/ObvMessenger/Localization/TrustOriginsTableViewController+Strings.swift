/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

extension TrustOriginsTableViewController {
    
    struct Strings {
        
        struct TrustOrigin {
            static let direct = NSLocalizedString("One-to-one verification", comment: "")
            static let mediator = { (mediatorDisplayName: String) in
                return String.localizedStringWithFormat(NSLocalizedString("Introduced by %@", comment: ""), mediatorDisplayName)
            }
            static let mediatorDeleted = NSLocalizedString("Introduced by a former contact", comment: "")
            static let group = NSLocalizedString("Introduced as part of a group discussion", comment: "")
            static let keycloak = { (keycloakServer: String) in
                return String.localizedStringWithFormat(NSLocalizedString("Introduced by keycloak server %@", comment: ""), keycloakServer) }
        }
        
    }
    
}
