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

import UIKit

@available(iOS 14, *)
protocol DiscussionCacheDelegate: AnyObject {
    
    // Cached images for hardlinks
    func getCachedImageForHardlink(hardlink: HardLinkToFyle, size: CGSize) -> UIImage?
    func requestImageForHardlink(hardlink: HardLinkToFyle, size: CGSize, completionWhenImageCached: @escaping ((Bool) -> Void))
    
    // Cached data detection (used to decide wether data detection should be actived on text views)
    func getCachedDataDetection(text: String) -> UIDataDetectorTypes?
    func requestDataDetection(text: String, completionWhenDataDetectionCached: @escaping ((Bool) -> Void))

    // Cached URL
    func getFirstHttpsURL(text: String) -> URL?
    
    // Cached hardlinks
    func getCachedHardlinkForFyleMessageJoinWithStatus(with objectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) -> HardLinkToFyle?
    /// The completion returns `true` iff a new hardlink is cached. This gives a chance to the cell to set `cellNeedsToUpdateItsConfiguration` to `true`
    func requestAllHardlinksForMessage(with objectID: TypeSafeManagedObjectID<PersistedMessage>, completionWhenHardlinksCached: @escaping ((Bool) -> Void))
    
    // Reply-to
    func getCachedReplyToBubbleViewConfiguration(message: PersistedMessage) -> ReplyToBubbleView.Configuration?
    func requestReplyToBubbleViewConfiguration(message: PersistedMessage, completion completionConfigCached: @escaping (Result<Void, Error>) -> Void)
    
    // Downsized thumbnails
    func getCachedDownsizedThumbnail(objectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) -> UIImage?
    func removeCachedDownsizedThumbnail(objectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>)
    func requestDownsizedThumbnail(objectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>, data: Data, completionWhenImageCached: @escaping ((Result<Void, Error>) -> Void))
    
}
