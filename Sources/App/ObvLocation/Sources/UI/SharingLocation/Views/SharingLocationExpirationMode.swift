/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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

public enum SharingLocationExpirationMode: String, CaseIterable {
    
    case liveForTwoMinutes
    case anHour
    case infinity
    
    public var expirationDate: ObvLocationSharingExpirationDate {
        switch self {
        case .infinity:
            return .never
        case .anHour:
            let date = Date.now.addingTimeInterval(.init(hours: 1))
            return .after(date: date)
        case .liveForTwoMinutes:
            let date = Date.now.addingTimeInterval(.init(minutes: 2))
            return .after(date: date)
        }
    }
    
    public var isLiveSharing: Bool {
        switch self {
        case .liveForTwoMinutes: return true
        case .anHour: return false
        case .infinity: return false
        }
    }
    
    @ViewBuilder
    var text: some View {
        switch self {
        case .infinity:
            Text("SHARE_TIME_INDEFINITELY")
        case .anHour:
            Text("SHARE_TIME_ONE_HOUR")
        case .liveForTwoMinutes:
            Text("SHARE_TIME_LIVE_TWO_MINUTES")
        }
    }
    
    @ViewBuilder
    var image: some View {
        switch self {
        case .infinity:
            Image(systemIcon: .infinity)
        case .anHour:
            Image(systemIcon: .clock)
        case .liveForTwoMinutes:
            Image(systemIcon: .locationViewfinder)
        }
    }
}
