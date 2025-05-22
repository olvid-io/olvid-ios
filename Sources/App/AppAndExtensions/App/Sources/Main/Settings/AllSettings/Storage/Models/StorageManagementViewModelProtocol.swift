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
import ObvUICoreData
import SwiftUI

@available(iOS 17.0, *)
protocol StorageManagementViewModelProtocol: StorageManagerRouterAwarenessProtocol {
    
    var files: [FyleMessageJoinWithStatus] { get }
    
    var largestFilesLocalizedThreshold: String { get }
    
    var filesPerDiscussions: [PersistedDiscussion: [FyleMessageJoinWithStatus]] { get }
    
    var discussionsSorted: [PersistedDiscussion] { get }
    
    var chartModel: StorageManagementChartViewModel? { get }
    
    var sentByMeModel: StorageManagementInlineFilesViewModel? { get }
    
    var largestFilesModel: StorageManagementInlineFilesViewModel? { get }
    
    var cacheManager: DiscussionCacheManager { get }
    
    var discussionSortOrder: StorageManagementSortOrder { get }
    
    var discussionSortDirection: StorageManagementSortDirection { get }
    
    @MainActor func updateDiscussionSortOrder(sortOrder: StorageManagementSortOrder)
    
    @MainActor func goToFilesSentByMe()
    
    @MainActor func goToLargestFiles()
    
    @MainActor func goToAllFiles()
    
    @MainActor func goToDiscussion(_ persistedDiscussion: PersistedDiscussion)
    
    @MainActor func onTaskForChartModel() async
    @MainActor func onTaskForSentByMeModel() async
    @MainActor func onTaskForLargestFilesModel() async

}
