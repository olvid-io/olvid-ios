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


public enum ObvMuteDurationOption: Int, Identifiable, CustomStringConvertible, CaseIterable, Equatable {

    case oneHour = 3_600
    case eightHours = 28_800
    case sevenDays = 604_800
    case indefinitely = -1

    public var id: Int { self.rawValue }

    public var description: String {
        switch self {
        case .oneHour: return String(localizedInThisBundle: "ONE_HOUR")
        case .eightHours: return String(localizedInThisBundle: "EIGHT_HOURS")
        case .sevenDays: return String(localizedInThisBundle: "SEVEN_DAYS")
        case .indefinitely: return String(localizedInThisBundle: "INDEFINITELY")
        }
    }

    public var endDateFromNow: Date {
        switch self {
        case .oneHour, .eightHours, .sevenDays:
            let interval = TimeInterval(self.rawValue)
            return Date().addingTimeInterval(interval)
        case .indefinitely:
            return Date.distantFuture
        }
    }
    
}
