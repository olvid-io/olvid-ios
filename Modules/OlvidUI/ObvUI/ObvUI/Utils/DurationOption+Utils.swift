/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvUICoreData


extension DurationOption: CustomStringConvertible {
    
    public var description: String {
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
    
}
