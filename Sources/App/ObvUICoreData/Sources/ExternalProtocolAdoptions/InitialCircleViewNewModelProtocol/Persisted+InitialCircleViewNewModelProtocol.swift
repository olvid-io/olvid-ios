/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import CoreData
import ObvUIObvCircledInitials


extension PersistedGroupV2Member: InitialCircleViewNewModelProtocol {
    
    public var circledInitialsConfiguration: CircledInitialsConfiguration {
        
        if let contact {
            
            return contact.circledInitialsConfiguration
            
        } else {
            
            guard let cryptoId else {
                return .icon(.lockFill)
            }
            
            var components = PersonNameComponents()
            components.givenName = firstName
            components.familyName = lastName

            let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)

            return .contact(initial: name,
                            photo: nil,
                            showGreenShield: false,
                            showRedShield: false,
                            cryptoId: cryptoId,
                            tintAdjustementMode: .disabled)
            
        }
        
    }
    
}
