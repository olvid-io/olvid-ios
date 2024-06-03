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
  

import UIKit
import QuickLookThumbnailing


extension URL {
    
    private static func makeError(message: String) -> Error { NSError(domain: "URL+Thumbnail", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    
    // Returns a thumbnail that is appropriate for the URL.
    // The requested size is considered as a "minimum" size: the returned image width and height will respectively be greater or equal to the width and height of the requested size.
    @MainActor
    func byPreparingThumbnail(ofSize size: CGSize) async throws -> UIImage {
        
        let scale = UIScreen.main.scale

        if let image = UIImage(contentsOfFile: self.path) {
            
            guard size.width < image.size.width && size.height < image.size.height else { return image }

            // In certain cases (e.g., when the UIImage actually is a photo taken from an iPhone), requesting a thumbnail with the exact requested size leads to unwanted results
            // Where the UIImageView would display borders at the top/bottom or on the sides of the images. To avoid this behaviour, we do not return a thumbnail
            // Of the requested size. Instead, we return an image that has the exact same ratio as the input image, but that respect at least one of size.width or size.height.
            
            let sourceRatio = image.size.width / image.size.height
            let finalThumbnailSize = CGSize(width: max(size.width, size.height * sourceRatio) * scale,
                                            height: max(size.height, size.width / sourceRatio) * scale)

            guard let thumbnail = await image.byPreparingThumbnail(ofSize: finalThumbnailSize) else {
                throw Self.makeError(message: "The preparingThumbnail of the UIImage returned a nil thumbnail")
            }
            
            return thumbnail
            
        } else {

            let request = QLThumbnailGenerator.Request(fileAt: self,
                                                       size: size,
                                                       scale: scale,
                                                       representationTypes: .thumbnail)
            let generator = QLThumbnailGenerator.shared
            
            let thumbnail = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
                generator.generateRepresentations(for: request) { thumbnail, type, error in
                    if let thumbnail = thumbnail?.uiImage {
                        continuation.resume(returning: thumbnail)
                    } else {
                        let error = error ?? Self.makeError(message: "The QLThumbnailGenerator returned a nil thumbnail without specifying an error")
                        continuation.resume(throwing: error)
                    }
                }
            }

            return thumbnail

        }

    }
    
    
    /// Returns a thumbnail with a width as close as possible to the specified ``mandatoryWidth``, and which height is less or equal than the ``maxHeight``.
    /// The bottom part of the thumbnail might be cropped to make it possible to obtain the desired size.
    @MainActor
    func byPreparingCropBottomThumbnail(mandatoryWidth: CGFloat, maxHeight: CGFloat) async throws -> UIImage {
     
        let scale = UIScreen.main.scale

        if let image = UIImage(contentsOfFile: self.path) {
            
            guard image.size.height > 0 && image.size.width > 0 else {
                assertionFailure()
                throw Self.makeError(message: "Cannot prepare thumbnail for an image that has a width or a height of 0")
            }
            
            let sourceRatio = image.size.width / image.size.height
            
            let uncroppedThumbnailSize = CGSize(width: mandatoryWidth * scale,
                                                height: mandatoryWidth * scale / sourceRatio)
            
            guard let uncroppedThumbnail = await image.byPreparingThumbnail(ofSize: uncroppedThumbnailSize) else {
                assertionFailure()
                throw Self.makeError(message: "The preparingThumbnail of the UIImage returned a nil thumbnail")
            }
            
            assert(uncroppedThumbnail.size.width == mandatoryWidth)
            
            if uncroppedThumbnail.size.height > maxHeight {
                guard let ciImage = uncroppedThumbnail.ciImage else {
                    assertionFailure()
                    throw Self.makeError(message: "Crop method failed")
                }
                let croppedCIImage = ciImage.cropped(to: CGRect(origin: .zero, size: CGSize(width: mandatoryWidth * scale, height: maxHeight * scale)))
                let croppedThumbnail = UIImage(ciImage: croppedCIImage)
                assert(croppedThumbnail.size.width == mandatoryWidth && croppedThumbnail.size.height <= maxHeight)
                return croppedThumbnail
            } else {
                return uncroppedThumbnail
            }
            
        } else {
            
            let generator = QLThumbnailGenerator.shared

            // Generate a representation with the exact mandatory width
            
            let representation: QLThumbnailRepresentation
            
            do {
                let requestedSize = CGSize(width: mandatoryWidth, height: maxHeight)
                let request = QLThumbnailGenerator.Request(fileAt: self,
                                                           size: requestedSize,
                                                           scale: scale,
                                                           representationTypes: .thumbnail)
                let firstRepresentation = try await generator.generateBestRepresentation(for: request)
                if firstRepresentation.uiImage.size.width == mandatoryWidth {
                    representation = firstRepresentation
                } else {
                    let ratio = mandatoryWidth / CGFloat(firstRepresentation.uiImage.size.width)
                    let requestedSize = CGSize(width: mandatoryWidth, height: ceil(firstRepresentation.uiImage.size.height * ratio))
                    let request = QLThumbnailGenerator.Request(fileAt: self,
                                                               size: requestedSize,
                                                               scale: scale,
                                                               representationTypes: .thumbnail)
                    let secondRepresentation = try await generator.generateBestRepresentation(for: request)
                    assert(abs(secondRepresentation.uiImage.size.width - mandatoryWidth) < 1.0, "Distance: \(abs(secondRepresentation.uiImage.size.width - mandatoryWidth))")
                    representation = secondRepresentation
                }

            }
            
            let uncroppedThumbnail = representation.uiImage
            
            // Crop the thumbnail if required
            
            let returnedThumbnail: UIImage
            
            if uncroppedThumbnail.size.height <= maxHeight {
                returnedThumbnail = uncroppedThumbnail
            } else {
                let cropZone = CGRect(origin: .zero, size: CGSize(width: representation.uiImage.size.width * scale, height: maxHeight * scale))
                guard let cutImageRef: CGImage = representation.cgImage.cropping(to:cropZone) else {
                    assertionFailure()
                    throw Self.makeError(message: "Crop failed")
                }
                returnedThumbnail = UIImage(cgImage: cutImageRef, scale: scale, orientation: .up)
            }

            assert(abs(returnedThumbnail.size.width - mandatoryWidth) < 1.0)
            assert(returnedThumbnail.size.height <= maxHeight)
            
            return returnedThumbnail
            
        }
                
    }
    
    
    @MainActor
    func byPreparingThumbnailPreparedForDisplay(ofSize size: CGSize) async throws -> UIImage {
        let thumbnail = try await self.byPreparingThumbnail(ofSize: size)
        let preparedThumbnail = await thumbnail.byPreparingForDisplay() ?? thumbnail
        return preparedThumbnail
    }
    
    
    @MainActor
    func bybyPreparingCropBottomThumbnailPreparedForDisplay(mandatoryWidth: CGFloat, maxHeight: CGFloat) async throws -> UIImage {
        let thumbnail = try await self.byPreparingCropBottomThumbnail(mandatoryWidth: mandatoryWidth, maxHeight: maxHeight)
        let preparedThumbnail = await thumbnail.byPreparingForDisplay() ?? thumbnail
        return preparedThumbnail
    }
    
}
