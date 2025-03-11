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


extension TimeInterval {
    
    static func formatForExistenceOrVisibilityDuration(timeInterval: TimeInterval?, unitsStyle: DateComponentsFormatter.UnitsStyle) -> String {
        guard let timeInterval else { return NSLocalizedString("Unlimited", comment: "")}
        let df = DateComponentsFormatter()
        df.unitsStyle = unitsStyle
        if timeInterval < TimeInterval(minutes: 1) {
            df.allowedUnits = [.second]
        } else if timeInterval == TimeInterval(hours: 1) {
            df.allowedUnits = [.hour]
        } else if timeInterval < TimeInterval(hours: 2) {
            df.allowedUnits = [.minute]
        } else if timeInterval == TimeInterval(days: 1) {
            df.allowedUnits = [.day]
        } else if timeInterval < TimeInterval(days: 2) {
            df.allowedUnits = [.hour]
        } else if timeInterval < TimeInterval(days: 181) {
            df.allowedUnits = [.day]
        } else if timeInterval == TimeInterval(years: 1) {
            df.allowedUnits = [.year]
        } else if timeInterval < TimeInterval(months: 24) {
            df.allowedUnits = [.month]
        } else {
            df.allowedUnits = [.year]
        }
        return df.string(from: timeInterval) ?? NSLocalizedString("Unknown", comment: "")
    }
    
}
