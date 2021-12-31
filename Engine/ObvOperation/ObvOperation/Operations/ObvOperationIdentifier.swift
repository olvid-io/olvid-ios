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
import ObvTypes

public struct ObvOperationIdentifier: CustomDebugStringConvertible {
    
    let className: String
    let uid: UID
    
    public var debugDescription: String {
        return "ObvOperationIdentifier(className: \(className), uid: \(uid.debugDescription), hashValue: \(self.hashValue))"
    }

}


extension ObvOperationIdentifier: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(className)
        hasher.combine(uid)
    }
    
}


extension ObvOperationIdentifier: Equatable {
    
    public static func == (lhs: ObvOperationIdentifier, rhs: ObvOperationIdentifier) -> Bool {
        return (lhs.className == rhs.className) && (lhs.uid == rhs.uid)
    }
    
}
