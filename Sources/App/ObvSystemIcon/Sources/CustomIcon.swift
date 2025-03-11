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


public enum CustomIcon: SymbolIcon {

    case checkmarkCircleFill
    case checkmarkCircle
    case checkmarkDoubleCircleFill
    case checkmarkDoubleCircleHalfFill
    case checkmarkDoubleCircle
    case checkmark
    
    public var name: String {
        switch self {
        case .checkmarkCircleFill: return "checkmark.circle.fill"
        case .checkmarkCircle: return "checkmark.circle"
        case .checkmarkDoubleCircleFill: return "checkmark.double.circle.fill"
        case .checkmarkDoubleCircleHalfFill: return "checkmark.double.circle.half.fill"
        case .checkmarkDoubleCircle: return "checkmark.double.circle"
        case .checkmark: return "checkmark"
        }
    }
}
