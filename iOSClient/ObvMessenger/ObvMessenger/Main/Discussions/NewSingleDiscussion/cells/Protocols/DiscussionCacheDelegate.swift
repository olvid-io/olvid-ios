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

import ObvUICoreData
import UIKit


@available(iOS 14, *)
protocol DiscussionCacheDelegate: AnyObject {
    
    // Cached images for hardlinks
    func getCachedImageForHardlink(hardlink: HardLinkToFyle, size: CGSize) -> UIImage?
    @discardableResult func requestImageForHardlink(hardlink: HardLinkToFyle, size: CGSize) async throws -> UIImage

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
    func requestReplyToBubbleViewConfiguration(message: PersistedMessage, completionWhenCellNeedsUpdateConfiguration: @escaping () -> Void) -> ReplyToBubbleView.Configuration?
    
    // Downsized thumbnails
    func getCachedDownsizedThumbnail(objectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) -> UIImage?
    func removeCachedDownsizedThumbnail(objectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>)
    func requestDownsizedThumbnail(objectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>, data: Data, completionWhenImageCached: @escaping ((Result<Void, Error>) -> Void))
    
    // Images (and thumbnails) for FyleMessageJoinWithStatus
    func getCachedPreparedImage(for objectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>, size: CGSize) -> UIImage?
    func requestPreparedImage(objectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>, size: CGSize) async throws
    
}
