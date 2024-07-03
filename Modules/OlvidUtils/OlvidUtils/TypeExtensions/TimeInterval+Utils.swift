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

public extension TimeInterval {
    
    /// Initialize a TimeInterval with the specified parameters. This method assumes 365 days/year for the `year` parameter and 30 days/month for the `month` parameter.
    init(years: Int? = nil, months: Int? = nil, days: Int? = nil, hours: Int? = nil, minutes: Int? = nil, seconds: Int? = nil) {
        var totalSeconds = 0
        if let years = years { totalSeconds += years * 31_536_000 } // Assuming 365 days/year
        if let months = months { totalSeconds += months * 2_592_000 } // Assuming 30 days/month
        if let days = days { totalSeconds += days * 86_400 }
        if let hours = hours { totalSeconds += hours * 3_600 }
        if let minutes = minutes { totalSeconds += minutes * 60 }
        if let seconds = seconds { totalSeconds += seconds }
        self.init(totalSeconds)
    }
    
    var toMilliseconds: Int {
        Int(self * 1000)
    }
    
    var toSeconds: Int {
        Int(self)
    }

}
