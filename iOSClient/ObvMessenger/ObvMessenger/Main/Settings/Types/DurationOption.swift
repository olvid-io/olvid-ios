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

enum DurationOption: Int, Identifiable, CustomStringConvertible, CaseIterable, Equatable {

    case none = 0
    case fiveSeconds = 5
    case tenSeconds = 10
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case thirtyMinutes = 1_800
    case oneHour = 3_600
    case sixHour = 21_600
    case twelveHours = 43_200
    case oneDay = 86_400
    case sevenDays = 604_800
    case thirtyDays = 2_592_000
    case ninetyDays = 7_776_000
    case oneHundredAndHeightyDays = 15_552_000
    case oneYear = 31_536_000
    case threeYears = 94_608_000
    case fiveYears = 157_680_000

    var id: Int { self.rawValue }
    
    var description: String {
        switch self {
        case .none: return CommonString.Word.Unlimited
        case .fiveSeconds: return NSLocalizedString("FIVE_SECONDS", comment: "")
        case .tenSeconds: return NSLocalizedString("TEN_SECONDS", comment: "")
        case .thirtySeconds: return NSLocalizedString("THIRTY_SECONDS", comment: "")
        case .oneMinute: return NSLocalizedString("ONE_MINUTE", comment: "")
        case .fiveMinutes: return NSLocalizedString("FIVE_MINUTE", comment: "")
        case .thirtyMinutes: return NSLocalizedString("THIRTY_MINUTES", comment: "")
        case .oneHour: return NSLocalizedString("ONE_HOUR", comment: "")
        case .sixHour: return NSLocalizedString("SIX_HOUR", comment: "")
        case .twelveHours: return NSLocalizedString("TWELVE_HOURS", comment: "")
        case .oneDay: return NSLocalizedString("ONE_DAY", comment: "")
        case .sevenDays: return NSLocalizedString("SEVEN_DAYS", comment: "")
        case .thirtyDays: return NSLocalizedString("THIRTY_DAYS", comment: "")
        case .ninetyDays: return NSLocalizedString("NINETY_DAYS", comment: "")
        case .oneHundredAndHeightyDays: return NSLocalizedString("ONE_HUNDRED_AND_HEIGHTY_DAYS", comment: "")
        case .oneYear: return NSLocalizedString("ONE_YEAR", comment: "")
        case .threeYears: return NSLocalizedString("THREE_YEAR", comment: "")
        case .fiveYears: return NSLocalizedString("FIVE_YEAR", comment: "")
        }
    }
    
    var timeInterval: TimeInterval? {
        switch self {
        case .none: return nil
        default: return TimeInterval(self.rawValue)
        }
    }

    // Returns self.timeInterval <= other
    func le(_ other: TimeInterval?) -> Bool {
        guard let other = other else { return true }
        guard let timeInterval = timeInterval else { return false }
        return timeInterval <= other
    }
    
}


enum DurationOptionAlt: Int, Identifiable, CustomStringConvertible, CaseIterable, Equatable {
    
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
    case fiveYears = 157_680_000

    var id: Int { self.rawValue }
    
    var description: String {
        switch self {
        case .none: return CommonString.Word.Unlimited
        case .sixHour: return NSLocalizedString("SIX_HOUR", comment: "")
        case .twelveHours: return NSLocalizedString("TWELVE_HOURS", comment: "")
        case .oneDay: return NSLocalizedString("ONE_DAY", comment: "")
        case .twoDays: return NSLocalizedString("TWO_DAYS", comment: "")
        case .sevenDays: return NSLocalizedString("SEVEN_DAYS", comment: "")
        case .fifteenDays: return NSLocalizedString("FIFTEEN_DAYS", comment: "")
        case .thirtyDays: return NSLocalizedString("THIRTY_DAYS", comment: "")
        case .ninetyDays: return NSLocalizedString("NINETY_DAYS", comment: "")
        case .oneHundredAndHeightyDays: return NSLocalizedString("ONE_HUNDRED_AND_HEIGHTY_DAYS", comment: "")
        case .oneYear: return NSLocalizedString("ONE_YEAR", comment: "")
        case .threeYears: return NSLocalizedString("THREE_YEAR", comment: "")
        case .fiveYears: return NSLocalizedString("FIVE_YEAR", comment: "")
        }
    }
    
    var timeInterval: TimeInterval? {
        switch self {
        case .none: return nil
        default: return TimeInterval(self.rawValue)
        }
    }
    
}


enum DurationOptionAltOverride: Int, Identifiable, CustomStringConvertible, CaseIterable, Equatable {
    
    case useAppDefault = -1
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
    case fiveYears = 157_680_000

    var id: Int { self.rawValue }
    
    var description: String {
        switch self {
        case .useAppDefault: return NSLocalizedString("Default", comment: "")
        case .none: return CommonString.Word.Unlimited
        case .sixHour: return NSLocalizedString("SIX_HOUR", comment: "")
        case .twelveHours: return NSLocalizedString("TWELVE_HOURS", comment: "")
        case .oneDay: return NSLocalizedString("ONE_DAY", comment: "")
        case .twoDays: return NSLocalizedString("TWO_DAYS", comment: "")
        case .sevenDays: return NSLocalizedString("SEVEN_DAYS", comment: "")
        case .fifteenDays: return NSLocalizedString("FIFTEEN_DAYS", comment: "")
        case .thirtyDays: return NSLocalizedString("THIRTY_DAYS", comment: "")
        case .ninetyDays: return NSLocalizedString("NINETY_DAYS", comment: "")
        case .oneHundredAndHeightyDays: return NSLocalizedString("ONE_HUNDRED_AND_HEIGHTY_DAYS", comment: "")
        case .oneYear: return NSLocalizedString("ONE_YEAR", comment: "")
        case .threeYears: return NSLocalizedString("THREE_YEAR", comment: "")
        case .fiveYears: return NSLocalizedString("FIVE_YEAR", comment: "")
        }
    }
    
    var timeInterval: TimeInterval? {
        switch self {
        case .none, .useAppDefault: return nil
        default: return TimeInterval(self.rawValue)
        }
    }
    
}

enum MuteDurationOption: Int, Identifiable, CustomStringConvertible, CaseIterable, Equatable {

    case oneHour = 3_600
    case eightHours = 28_800
    case sevenDays = 604_800
    case indefinitely = -1

    var id: Int { self.rawValue }

    var description: String {
        switch self {
        case .oneHour: return NSLocalizedString("ONE_HOUR", comment: "")
        case .eightHours: return NSLocalizedString("EIGHT_HOURS", comment: "")
        case .sevenDays: return NSLocalizedString("SEVEN_DAYS", comment: "")
        case .indefinitely: return NSLocalizedString("INDEFINITELY", comment: "")
        }
    }

}
