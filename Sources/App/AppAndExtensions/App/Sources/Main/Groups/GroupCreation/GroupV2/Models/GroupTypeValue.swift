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
import ObvTypes
import ObvUICoreData


enum GroupTypeValue: Int, Comparable, CaseIterable, Identifiable {
    case standard = 0
    case managed = 1
    case readOnly = 2
    case advanced = 3
    public var id: Self { self }
    public static func < (lhs: GroupTypeValue, rhs: GroupTypeValue) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}


extension PersistedGroupV2.GroupType {
    
    var value: GroupTypeValue {
        switch self {
        case .standard: return .standard
        case .managed: return .managed
        case .readOnly: return .readOnly
        case .advanced: return .advanced
        }
    }
    
}
