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
import ObvSystemIcon

@available(iOS 17.0, *)
@Observable
class StorageManagementMediaCellViewModel: StorageManagementMediaCellViewModelProtocol {
    
    fileprivate static let minFileSize = CGSize(width: 100, height: 100)
    
    let attachment: FyleMessageJoinWithStatus
    
    let cacheManager: DiscussionCacheManager
    
    init(attachment: FyleMessageJoinWithStatus, cacheManager: DiscussionCacheManager) {
        self.attachment = attachment
        self.cacheManager = cacheManager
        self.isSelected = false
        
        prefetchCachedDataIfPossible()
    }
    
    var image: Image? // Will be propagated via onTask()
    var duration: String? // Will be propagated via onTask()

    var placeHolderImage: Image {
        if let icon = attachment.attachmentType.icon {
            return icon
        } else {
            return Image(systemIcon: .photo)
        }
    }
    
    var expirationIndicatorIcon: Image? {
        if let receivedAttachment = attachment as? ReceivedFyleMessageJoinWithStatus {
            let message = receivedAttachment.receivedMessage
            
            var imageSystemIcon: SystemIcon?
            
            if message.readingRequiresUserAction {
                if message.readOnce {
                    imageSystemIcon = .flameFill
                } else if message.visibilityDuration != nil {
                    imageSystemIcon = .eyes
                }
            }
            
            guard let imageSystemIcon = imageSystemIcon else { return nil }
            return Image(systemIcon: imageSystemIcon)
        }
        
        return nil
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = .useAll
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        
        return formatter.string(fromByteCount: attachment.totalByteCount)
    }
    
    var icon: Image? {
        attachment.attachmentType.icon
    }
    
    var isSelected: Bool
    
    func onTask() async throws {
        async let imageRequested: Void = self.requestImage()
        async let durationRequested: Void = self.requestDuration()
        
        (_, _) = try await (imageRequested, durationRequested)
    }

    private func prefetchCachedDataIfPossible() {
        if let thumbnail = cacheManager.getCachedPreparedImage(for: attachment.typedObjectID, size: .full(minSize: Self.minFileSize)) {
            self.image = Image(uiImage: thumbnail)
        }
        if (attachment.attachmentType == .audio || attachment.attachmentType == .video), let duration = cacheManager.getCachedDurationFormatted(for: attachment.typedObjectID) {
            self.duration = duration
        }
    }
}

@available(iOS 17.0, *)
extension StorageManagementMediaCellViewModel {
    
    @MainActor
    fileprivate func requestImage() async throws {
        defer {
            if let thumbnail = cacheManager.getCachedPreparedImage(for: attachment.typedObjectID, size: .full(minSize: Self.minFileSize)) {
                self.image = Image(uiImage: thumbnail)
            }
        }
        
        guard cacheManager.getCachedPreparedImage(for: attachment.typedObjectID, size: .full(minSize: Self.minFileSize)) == nil else {
            return
        }
        
        try await self.cacheManager.requestPreparedImage(objectID: attachment.typedObjectID, size: .full(minSize: Self.minFileSize))
    }
    
    @MainActor
    fileprivate func requestDuration() async throws {
        defer {
            if (attachment.attachmentType == .audio || attachment.attachmentType == .video), let duration = cacheManager.getCachedDurationFormatted(for: attachment.typedObjectID) {
                self.duration = duration
            }
        }

        guard (attachment.attachmentType == .audio || attachment.attachmentType == .video), cacheManager.getCachedDurationFormatted(for: attachment.typedObjectID) == nil else {
            return
        }

        try await self.cacheManager.requestDurationFormatted(objectID: attachment.typedObjectID)
    }
}

@available(iOS 17.0, *)
extension FyleMessageJoinWithStatus.FyleMessageJoinType {
    
    var icon: Image? {
        switch self {
        case .audio:
            return Image(systemIcon: .micFill)
        case .video:
            return Image(systemIcon: .videoFill)
        case .other:
            return Image(systemIcon: .docFill)
        default:
            return nil
        }
    }
    
}
