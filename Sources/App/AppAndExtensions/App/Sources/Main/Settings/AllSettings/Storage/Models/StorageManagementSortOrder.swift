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

import Foundation
import SwiftUI

enum StorageManagementSortOrder: Int, CaseIterable {
    case size = 0
    case name = 1
    case date = 2
    case type = 3
    
    var title: Text {
        switch self {
        case .size:
            Text("STORAGE_DISCUSSION_MENU_SIZE")
        case .name:
            Text("STORAGE_DISCUSSION_MENU_NAME")
        case .date:
            Text("STORAGE_DISCUSSION_MENU_LAST_OPENED")
        case .type:
            Text("STORAGE_DISCUSSION_MENU_TYPE")
        }
    }
    
    static let discussions = [StorageManagementSortOrder.size, .name, .date]
    
    static let files = [StorageManagementSortOrder.size, .type]
}

enum StorageManagementSortDirection: Int {
    case descending
    case ascending
    
    mutating func toggle() {
        self = self == .ascending ? .descending : .ascending
    }
    
    func compare<T: Comparable>(lhs: T, rhs: T) -> Bool {
        switch self {
        case .descending:
            return lhs >= rhs
        case .ascending:
            return lhs < rhs
        }
    }
    
    var icon: Image {
        switch self {
        case .descending:
            Image(systemIcon: .arrowDown)
        default:
            Image(systemIcon: .arrowUp)
        }
    }
    
}
