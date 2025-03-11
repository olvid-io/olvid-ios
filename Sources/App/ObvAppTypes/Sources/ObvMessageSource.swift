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

import Foundation


/// Represents the source of a received `ObvMessage`.
///
/// An `ObvMessage` it ypically received from the engine. In certain situations, e.g., when tapping a user notification while offline, it can be extracted and thus received from a user notification.
public enum ObvMessageSource: Int {
    case engine = 0
    case userNotification = 1
}


extension ObvMessageSource: CustomDebugStringConvertible {
    
    public var debugDescription: String {
        switch self {
        case .engine: return "ObvMessageSource.engine"
        case .userNotification: return "ObvMessageSource.userNotification"
        }
    }
    
}
