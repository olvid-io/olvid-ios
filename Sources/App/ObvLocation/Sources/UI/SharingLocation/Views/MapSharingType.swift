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

enum MapSharingType {
    case continuous
    case landmark
    
    mutating func toggle() {
        switch self {
        case .continuous:
            self = .landmark
        case .landmark:
            self = .continuous
        }
    }
    
    var icon: Image {
        switch self {
        case .continuous:
            return Image(systemIcon: .mappin)
        case .landmark:
            return Image(systemIcon: .locationFill)
        }
    }
    
    var text: Text {
        switch self {
        case .continuous:
            return Text("SEND_CONTINUOUS")
        case .landmark:
            return Text("SEND_LANDMARK")
        }
    }
    
    var localizedName: String {
        switch self {
        case .continuous:
            return String(localized: "SEND_CONTINUOUS", bundle: Bundle(for: ObvLocationResources.self))
        case .landmark:
            return String(localized: "SEND_LANDMARK", bundle: Bundle(for: ObvLocationResources.self))
        }
    }
    
    var background: AnyShapeStyle {
        switch self {
        case .continuous:
            return AnyShapeStyle(Color.blue)
        case .landmark:
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }
}
