/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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

import SwiftUI
import ObvAppTypes

enum SharingLocationExpirationMode: String, CaseIterable {
    
    case anHour
    case infinity
    
    var expirationDate: ObvLocationSharingExpirationDate {
        switch self {
        case .infinity:
            return .never
        case .anHour:
            let date = Date.now.addingTimeInterval(.init(hours: 1))
            return .after(date: date)
        }
    }
    
    var text: Text {
        switch self {
        case .infinity:
            return Text("SHARE_TIME_INDEFINITELY")
        case .anHour:
            return Text("SHARE_TIME_ONE_HOUR")
        }
    }
    
    var image: Image {
        switch self {
        case .infinity:
            return Image(systemIcon: .infinity)
        case .anHour:
            return Image(systemIcon: .clock)
        }
    }
}
