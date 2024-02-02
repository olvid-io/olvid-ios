/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import UI_SystemIcon


public enum CircledInitialsIcon: Hashable {

    case lockFill
    case person
    case person3Fill
    case personFillXmark
    case plus
    
    public var icon: SystemIcon {
        switch self {
        case .lockFill: return .lock(.fill)
        case .person: return .person
        case .person3Fill: return .person3Fill
        case .personFillXmark: return .personFillXmark
        case .plus: return .plus
        }
    }

}
