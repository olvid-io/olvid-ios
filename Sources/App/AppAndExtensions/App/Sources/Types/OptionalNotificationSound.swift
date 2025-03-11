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
import ObvSettings
import ObvUserNotificationsSounds

enum OptionalNotificationSound: Identifiable, Hashable {
    case none // Global default setting
    case some(NotificationSound)

    var id: String {
        switch self {
        case .none: return "_None"
        case .some(let sound): return sound.identifier
        }
    }
    init(_ value: NotificationSound?) {
        if let value = value {
            self = .some(value)
        } else {
            self = .none
        }
    }
    var value: NotificationSound? {
        switch self {
        case .none: return nil
        case .some(let sound): return sound
        }
    }
}
