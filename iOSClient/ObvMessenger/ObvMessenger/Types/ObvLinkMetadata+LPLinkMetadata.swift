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
import LinkPresentation
import AVFoundation

/// Makes it possible to create an ``ObvLinkMetadata`` from a standard ``LPLinkMetadata``
extension ObvLinkMetadata {
    
    public static let maxIconSize = CGSize(width: 1080, height: 1080)
    
    public static func from(linkMetadata: LPLinkMetadata) async -> ObvLinkMetadata {
        
        let title = linkMetadata.title
        let url = linkMetadata.url
        let desc = linkMetadata.value(forKey: "summary") as? String
        let remoteVideoURL = linkMetadata.remoteVideoURL
        
        var imageProvided: UIImage? = nil
        
        // We check that an imageProvider exists and we load it.
        if let imageProvider = linkMetadata.imageProvider {
            imageProvided = try? await loadImage(from: imageProvider)
        }
        
        // if imageProvider failed, we check that a remote video URL exists and we try to generate a thumbnail
        if imageProvided == nil, let remoteVideoURL = remoteVideoURL {
            let image = try? await AVAsset(url: remoteVideoURL).generateThumbnail()
            imageProvided = image?.downsizeIfRequired(maxWidth: maxIconSize.width, maxHeight: maxIconSize.height)
        }
        
        // If no image provider and no remote video url exist or fail to load, we try to load an icon
        if imageProvided == nil, let iconProvider = linkMetadata.iconProvider {
            imageProvided = try? await loadImage(from: iconProvider)
        }
        
        let preview = ObvLinkMetadata(title: title, desc: desc, url: url, pngData: imageProvided?.pngData())
        return preview
        
    }


    private static func loadImage(from provider: NSItemProvider) async throws -> UIImage? {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage?, (any Error)>) in
            provider.loadObject(ofClass: UIImage.self) { image, error in
                if let error = error {
                    return continuation.resume(throwing: error)
                }
                
                guard let image = image as? UIImage else {
                    return continuation.resume(returning: nil)
                }
                
                let downSizedImage = image.downsizeIfRequired(maxWidth: maxIconSize.width, maxHeight: maxIconSize.height)
                return continuation.resume(returning: downSizedImage)
            }
        }
    }
    
}


private extension AVAsset {
    
    func generateThumbnail() async throws -> UIImage? {
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage?, (any Error)>) in
                let imageGenerator = AVAssetImageGenerator(asset: self)
                
                imageGenerator.appliesPreferredTrackTransform = true
                
                let time = CMTime(seconds: 0.0, preferredTimescale: 600)
                let times = [NSValue(time: time)]
                
                imageGenerator.generateCGImagesAsynchronously(forTimes: times, completionHandler: { timeAsked, image, timeResulted, result, error in
                    if let image = image {
                        return continuation.resume(returning: UIImage(cgImage: image))
                    } else if let error = error {
                        return continuation.resume(throwing: error)
                    } else {
                        return continuation.resume(returning: nil)
                    }
                })
            }
        }
}
