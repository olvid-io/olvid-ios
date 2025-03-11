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


public enum DurationOptionAlt: Int, Identifiable, CaseIterable, Equatable {
    
    case none = 0
    case sixHour = 21_600
    case twelveHours = 43_200
    case oneDay = 86_400
    case twoDays = 172_800
    case sevenDays = 604_800
    case fifteenDays = 1_296_000
    case thirtyDays = 2_592_000
    case ninetyDays = 7_776_000
    case oneHundredAndHeightyDays = 15_552_000
    case oneYear = 31_536_000
    case threeYears = 94_608_000
    case fiveYears = 157_766_400 // not 157_680_000, so as to make sure the date formatter shows 5 year

    public var id: Int { self.rawValue }
        
    public var timeInterval: TimeInterval? {
        switch self {
        case .none: return nil
        default: return TimeInterval(self.rawValue)
        }
    }
    
}
