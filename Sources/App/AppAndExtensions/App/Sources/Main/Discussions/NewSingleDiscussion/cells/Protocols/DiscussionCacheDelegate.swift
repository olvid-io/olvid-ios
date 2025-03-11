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

import ObvUICoreData
import UIKit


protocol DiscussionCacheDelegate: AnyObject {
    
    // Cached images for hardlinks
    func getCachedImageForHardlink(hardlink: HardLinkToFyle, size: ObvDiscussionThumbnailSize) -> UIImage?
    @discardableResult func requestImageForHardlink(hardlink: HardLinkToFyle, size: ObvDiscussionThumbnailSize) async throws -> UIImage

    // Cached data detection (used to decide wether data detection should be actived on text views)
    func getCachedDataDetection(attributedString: AttributedString) -> [ObvDiscussionDataDetected]?
    func requestDataDetection(attributedString: AttributedString, completionWhenDataDetectionCached: @escaping ((Bool) -> Void))

    // Cached URL
    func getFirstHttpsURL(text: String) -> URL?
    
    // Request missing preview for a message if needed
    func requestMissingPreviewIfNeededForMessage(with objectID: TypeSafeManagedObjectID<PersistedMessageReceived>)
    
    // Cached hardlinks
    func getCachedHardlinkForFyleMessageJoinWithStatus(with objectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) -> HardLinkToFyle?
    /// The completion returns `true` iff a new hardlink is cached. This gives a chance to the cell to set `cellNeedsToUpdateItsConfiguration` to `true`
    /// Note that "link previews" are excluded and not considered as "relevant" when computing hardlinks.
    func requestAllRelevantHardlinksForMessage(with objectID: TypeSafeManagedObjectID<PersistedMessage>, completionWhenHardlinksCached: @escaping ((Bool) -> Void))
    
    // Reply-to
    @MainActor func requestReplyToBubbleViewConfiguration(message: PersistedMessage, completionWhenCellNeedsUpdateConfiguration: @escaping () -> Void) -> ReplyToBubbleView.Configuration?
    
    // Downsized thumbnails
    func getCachedDownsizedThumbnail(objectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) -> UIImage?
    func removeCachedDownsizedThumbnail(objectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>)
    func requestDownsizedThumbnail(objectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>, data: Data, completionWhenImageCached: @escaping ((Result<Void, Error>) -> Void))
    
    // Images (and thumbnails) for FyleMessageJoinWithStatus
    func getCachedPreparedImage(for objectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>, size: ObvDiscussionThumbnailSize) -> UIImage?
    func requestPreparedImage(objectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>, size: ObvDiscussionThumbnailSize) async throws
    
}


enum ObvDiscussionThumbnailSize: Hashable {
    case full(minSize: CGSize)
    case cropBottom(mandatoryWidth: CGFloat, maxHeight: CGFloat)
    
    /// This implementation, a priori not mandatory, is required to prevent a crash when compiling on Xcode 16 for a real device in production.
    func hash(into hasher: inout Hasher) {
        switch self {
        case .full(let minSize):
            hasher.combine("full")
            hasher.combine(minSize.width)
            hasher.combine(minSize.height)
        case .cropBottom(let mandatoryWidth, let maxHeight):
            hasher.combine("cropBottom")
            hasher.combine(mandatoryWidth)
            hasher.combine(maxHeight)
        }
    }
    
}


/// See the comments in ``DiscussionCacheManager``
struct ObvDiscussionDataDetected: Hashable, Equatable {
    
    let range: NSRange
    let resultType: NSTextCheckingResult.CheckingType
    let link: URL
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(range)
        hasher.combine(resultType.rawValue)
        hasher.combine(link)
    }
}
