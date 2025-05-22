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
import ObvUICoreData
import ObvUIObvCircledInitials

@available(iOS 17.0, *)
@Observable
class StorageManagementDiscussionCellViewModel: StorageManagementDiscussionCellViewModelProtocol {
    
    var circledInitialsConfiguration: CircledInitialsConfiguration {
        return discussion.circledInitialsConfiguration ?? .icon(.lockFill)
    }
    
    var title: String {
        return discussion.title
    }
    
    var formattedSize: String {
        let totalByteCount = files.compactMap(\.totalByteCount).reduce(0, +)
        
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = .useAll
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        
        return formatter.string(fromByteCount: totalByteCount)
    }
    
    let discussion: PersistedDiscussion
    
    let files: [FyleMessageJoinWithStatus]
    
    init(discussion: PersistedDiscussion,
         files: [FyleMessageJoinWithStatus]) {
        self.discussion = discussion
        self.files = files
    }
}
