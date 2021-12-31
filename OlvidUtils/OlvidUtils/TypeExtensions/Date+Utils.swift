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

public extension Date {

    /// The interval in milliseconds between the date value and 00:00:00 UTC on 1 January 1970.
    var epochInMs: Int64 { Int64(timeIntervalSince1970 * 1000) }

    /// Returns a `Date` initialized relative to 00:00:00 UTC on 1 January 1970 by a given number of milliseconds.
    init(epochInMs: Int64) {
        self.init(timeIntervalSince1970: Double(epochInMs) / 1000)
    }

}
