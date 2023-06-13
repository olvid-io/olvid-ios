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

import Foundation
import CoreData
import os.log
import OlvidUtils
import UIKit
import MobileCoreServices
import ObvEncoder
import ObvMetaManager
import ObvUICoreData


private enum ComputeExtendedPayloadOperationInput {
    case message(messageSentPermanentID: ObvManagedObjectPermanentID<PersistedMessageSent>)
    case unprocessedPersistedMessageSentProvider(_: UnprocessedPersistedMessageSentProvider)
}

final class ComputeExtendedPayloadOperation: ContextualOperationWithSpecificReasonForCancel<ComputeExtendedPayloadOperationReasonForCancel>, ExtendedPayloadProvider {

    private let input: ComputeExtendedPayloadOperationInput
    private let maxNumberOfDownsizedImages = 25

    private static let errorDomain = "ComputeExtendedPayloadOperation"
    fileprivate static func makeError(message: String) -> Error { NSError(domain: ComputeExtendedPayloadOperation.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    init(provider: UnprocessedPersistedMessageSentProvider) {
        self.input = .unprocessedPersistedMessageSentProvider(provider)
        super.init()
    }

    init(messageSentPermanentID: ObvManagedObjectPermanentID<PersistedMessageSent>) {
        self.input = .message(messageSentPermanentID: messageSentPermanentID)
        super.init()
    }

    private(set) var extendedPayload: Data?

    override func main() {

        let messageSentPermanentID: ObvManagedObjectPermanentID<PersistedMessageSent>
        switch input {
        case .message(let _messageSentPermanentID):
            messageSentPermanentID = _messageSentPermanentID
        case .unprocessedPersistedMessageSentProvider(let provider):
            guard let _messageSentPermanentID = provider.messageSentPermanentID else {
                return cancel(withReason: .persistedMessageSentObjectIDIsNil)
            }
            messageSentPermanentID = _messageSentPermanentID
        }

        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {

            let persistedMessageSent: PersistedMessageSent
            do {
                guard let _persistedMessageSent = try PersistedMessageSent.getManagedObject(withPermanentID: messageSentPermanentID, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindPersistedMessageSentInDatabase)
                }
                persistedMessageSent = _persistedMessageSent
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }

            guard persistedMessageSent.status == .unprocessed || persistedMessageSent.status == .processing else {
                return
            }

            guard !persistedMessageSent.fyleMessageJoinWithStatuses.isEmpty else { return }

            // Compute up to 25 downsized images

            var attachmentNumbersAnddownsizedImages = [(attachmentNumber: Int, downsizedImage: CGImage)]()
            for join in persistedMessageSent.fyleMessageJoinWithStatuses {
                guard let fyle = join.fyle else { continue }
                guard ObvUTIUtils.uti(join.uti, conformsTo: kUTTypeImage) else { continue }

                // Return a centered squared image
                guard let squareImage = extractSquaredImageFromImage(at: fyle.url) else { continue }

                // Resize the squared image to a resolution larger, but close to 40x40 pixels
                guard let downsizedImage = downsizeImage(squareImage) else { continue }

                attachmentNumbersAnddownsizedImages.append((join.index, downsizedImage))

                guard attachmentNumbersAnddownsizedImages.count < maxNumberOfDownsizedImages else { break }
            }

            guard !attachmentNumbersAnddownsizedImages.isEmpty else { return }

            // Compute a single image composed of the downsized image, from left to right, from down to bottom.

            guard let singleImage = createSingleImageComposedOfImages(attachmentNumbersAnddownsizedImages.map({ $0.downsizedImage })) else {
                assertionFailure("Could not compute single image from downsized images")
                return
            }

            // Export single image to jpeg, try to remove EXIF attributes, and encode the result

            guard let jpegDataOfSingleImage = UIImage(cgImage: singleImage).jpegData(compressionQuality: 0.75) else {
                assertionFailure("Could not export single image to Jpeg")
                return
            }

            let jpegDataOfSingleImageWithoutAttributes = removeJpegAttributesFromJpegDataOfSingleImage(jpegDataOfSingleImage)

            let encodedImageData = (jpegDataOfSingleImageWithoutAttributes ?? jpegDataOfSingleImage).obvEncode()

            let encodedListOfAttachmentNumbers = attachmentNumbersAnddownsizedImages.map({ $0.attachmentNumber }).map({ $0.obvEncode() }).obvEncode()
            let encodedExtendedPayload = [
                0.obvEncode(),
                encodedListOfAttachmentNumbers,
                encodedImageData,
            ].obvEncode()

            self.extendedPayload = encodedExtendedPayload.rawData
        }

    }


    /// Returns a square image extracted from the image at `url`, as well as the appropriate orientation allowing to turn this `CGImage` back into an `UIImage`.
    private func extractSquaredImageFromImage(at url: URL) -> CGImage? {
        guard let uiImage = UIImage(contentsOfFile: url.path) else { return nil }

        let imageOrientation = uiImage.imageOrientation
        debugPrint(imageOrientation.rawValue)
        
        guard let image = uiImage.cgImage else { return nil }
        
        // Return a centered squared image
        let rect: CGRect
        if image.width > image.height {
            let difference = image.width - image.height
            let origin = CGPoint(x: difference / 2, y: 0)
            let size = CGSize(width: image.height, height: image.height)
            rect = CGRect(origin: origin, size: size)
        } else {
            let difference = image.height - image.width
            let origin = CGPoint(x: 0, y: difference / 2)
            let size = CGSize(width: image.width, height: image.width)
            rect = CGRect(origin: origin, size: size)
        }
        guard let squareImage = image.cropping(to: rect) else { return nil }
        
        let squareImageWithCorrectOrientation: CGImage
        switch imageOrientation {
        case .up:
            // Best case since we have nothing to do (case with sample images)
            squareImageWithCorrectOrientation = squareImage
        case .down:
            // Transforms found via trial and error...
            UIGraphicsBeginImageContext(rect.size)
            let context = UIGraphicsGetCurrentContext()
            context?.translateBy(x: rect.size.width/2, y: rect.size.height/2)
            context?.scaleBy(x: -1, y: 1)
            context?.translateBy(x: -rect.size.width/2, y: -rect.size.height/2)
            context?.draw(squareImage, in: CGRect(origin: CGPoint(x: 0, y: 0), size: rect.size))
            squareImageWithCorrectOrientation = context?.makeImage() ?? squareImage
            UIGraphicsEndImageContext()
        case .left:
            // Transforms found via trial and error...
            UIGraphicsBeginImageContext(rect.size)
            let context = UIGraphicsGetCurrentContext()
            context?.translateBy(x: rect.size.width/2, y: rect.size.height/2)
            context?.rotate(by: CGFloat.pi / 2.0)
            context?.scaleBy(x: -1, y: 1)
            context?.translateBy(x: -rect.size.width/2, y: -rect.size.height/2)
            context?.draw(squareImage, in: CGRect(origin: CGPoint(x: 0, y: 0), size: rect.size))
            squareImageWithCorrectOrientation = context?.makeImage() ?? squareImage
            UIGraphicsEndImageContext()
        case .right:
            // Transforms found via trial and error...
            UIGraphicsBeginImageContext(rect.size)
            let context = UIGraphicsGetCurrentContext()
            context?.translateBy(x: rect.size.width/2, y: rect.size.height/2)
            context?.rotate(by: -CGFloat.pi / 2.0)
            context?.scaleBy(x: -1, y: 1)
            context?.translateBy(x: -rect.size.width/2, y: -rect.size.height/2)
            context?.draw(squareImage, in: CGRect(origin: CGPoint(x: 0, y: 0), size: rect.size))
            squareImageWithCorrectOrientation = context?.makeImage() ?? squareImage
            UIGraphicsEndImageContext()
        case .upMirrored:
            assertionFailure()
            squareImageWithCorrectOrientation = squareImage
        case .downMirrored:
            assertionFailure()
            squareImageWithCorrectOrientation = squareImage
        case .leftMirrored:
            assertionFailure()
            squareImageWithCorrectOrientation = squareImage
        case .rightMirrored:
            assertionFailure()
            squareImageWithCorrectOrientation = squareImage
        @unknown default:
            assertionFailure()
            squareImageWithCorrectOrientation = squareImage
        }
        
        return squareImageWithCorrectOrientation
    }
    
    
    private func downsizeImage(_ image: CGImage) -> CGImage? {
        return image.downsizeToSize(ObvMessengerConstants.downsizedImageSize)
    }
    
    
    private func createSingleImageComposedOfImages(_ downsizedImages: [CGImage]) -> CGImage? {
        
        guard !downsizedImages.isEmpty else {
            return nil
        }
        guard downsizedImages.count <= maxNumberOfDownsizedImages else {
            return nil
        }
        
        guard downsizedImages.count > 1 else {
            return downsizedImages.first
        }
        
        let downsizedImageSize = ObvMessengerConstants.downsizedImageSize
        
        let numberOfColumns: Int = Int(sqrt(Double(downsizedImages.count)).rounded(.awayFromZero))
        let numberOfRows: Int = (downsizedImages.count - 1) / numberOfColumns + 1

        let singleImageSize = CGSize(width: downsizedImageSize.width * CGFloat(numberOfColumns), height: downsizedImageSize.width * CGFloat(numberOfRows))
        
        let context = CGContext(data: nil,
                                width: Int(singleImageSize.width),
                                height: Int(singleImageSize.height),
                                bitsPerComponent: 8,
                                bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        context?.interpolationQuality = .high

        var index = 0
        for row in 0..<numberOfRows {
            guard index < downsizedImages.count else { break }
            for column in 0..<numberOfColumns {
                guard index < downsizedImages.count else { break }
                let downsizedImage = downsizedImages[index]
                let origin = CGPoint(x: CGFloat(column) * downsizedImageSize.width, y: CGFloat(numberOfRows - 1 - row) * downsizedImageSize.height)
                let size = CGSize(width: downsizedImageSize.width, height: downsizedImageSize.height)
                let rect = CGRect(origin: origin, size: size)
                context?.draw(downsizedImage, in: rect)
                index += 1
            }
        }
        
        guard let singleImage = context?.makeImage() else { return nil }

        return singleImage

    }
 
    
    
    private func removeJpegAttributesFromJpegDataOfSingleImage(_ jpegDataOfSingleImage: Data) -> Data? {
        
        enum JpegMarker: UInt8 {
            case marker = 0xff
            case marker_soi = 0xd8
            case marker_sos = 0xda
            case marker_app1 = 0xe1
            case marker_com = 0xfe
            case marker_eoi = 0xd9
            case marker_app0 = 0xe0
            case marker_app2 = 0xe2
            case marker_app3 = 0xe3
            case marker_app4 = 0xe4
            case marker_app5 = 0xe5
            case marker_app6 = 0xe6
            case marker_app7 = 0xe7
            case marker_app8 = 0xe8
            case marker_app9 = 0xe9
            case marker_app10 = 0xea
            case marker_app11 = 0xeb
            case marker_app12 = 0xec
            case marker_app13 = 0xed
            case marker_app14 = 0xee
            case marker_app15 = 0xef
        }
        
        var output = Data()

        guard jpegDataOfSingleImage.count >= 2 && jpegDataOfSingleImage[0] == JpegMarker.marker.rawValue && jpegDataOfSingleImage[1] == JpegMarker.marker_soi.rawValue else {
            return nil
        }
        
        output.append(contentsOf: [JpegMarker.marker.rawValue, JpegMarker.marker_soi.rawValue])
                
        var index = 2
        
        while true {

            guard index < jpegDataOfSingleImage.count else { return nil }
            let firstMarker = jpegDataOfSingleImage[index]
            guard firstMarker == JpegMarker.marker.rawValue else { return nil }
            index += 1

            guard index < jpegDataOfSingleImage.count else { return nil }
            let secondMarker = jpegDataOfSingleImage[index]
            index += 1

            switch secondMarker {
            case JpegMarker.marker_app2.rawValue,
                JpegMarker.marker_com.rawValue,
                JpegMarker.marker_app0.rawValue,
                JpegMarker.marker_app1.rawValue,
                JpegMarker.marker_app3.rawValue,
                JpegMarker.marker_app4.rawValue,
                JpegMarker.marker_app5.rawValue,
                JpegMarker.marker_app6.rawValue,
                JpegMarker.marker_app7.rawValue,
                JpegMarker.marker_app8.rawValue,
                JpegMarker.marker_app9.rawValue,
                JpegMarker.marker_app10.rawValue,
                JpegMarker.marker_app11.rawValue,
                JpegMarker.marker_app12.rawValue,
                JpegMarker.marker_app13.rawValue,
                JpegMarker.marker_app14.rawValue,
                JpegMarker.marker_app15.rawValue:
                
                guard index < jpegDataOfSingleImage.count else { return nil }
                let firstByteOfLength = jpegDataOfSingleImage[index]
                index += 1

                guard index < jpegDataOfSingleImage.count else { return nil }
                let secondByteOfLength = jpegDataOfSingleImage[index]
                index += 1
                
                let totalLength = (UInt16(firstByteOfLength) << 8) + UInt16(secondByteOfLength)
                guard totalLength >= 2 else { return nil }
                let length = totalLength - 2
                
                // Skip length bytes
                index += Int(length)
                
            case JpegMarker.marker_eoi.rawValue,
                JpegMarker.marker_sos.rawValue:
                
                output.append(contentsOf: [firstMarker, secondMarker])
                
                // Copy all the remaining data
                if index < jpegDataOfSingleImage.count {
                    output.append(jpegDataOfSingleImage[index..<jpegDataOfSingleImage.count])
                }
                return output

            default:
                // Copy JPEG segment
                
                output.append(contentsOf: [firstMarker, secondMarker])
                
                guard index < jpegDataOfSingleImage.count else { return nil }
                let firstByteOfLength = jpegDataOfSingleImage[index]
                index += 1

                guard index < jpegDataOfSingleImage.count else { return nil }
                let secondByteOfLength = jpegDataOfSingleImage[index]
                index += 1

                let totalLength = (UInt16(firstByteOfLength) << 8) + UInt16(secondByteOfLength)
                guard totalLength >= 2 else { return nil }
                let length = totalLength - 2

                output.append(contentsOf: [firstByteOfLength, secondByteOfLength])

                if index + Int(length) <= jpegDataOfSingleImage.count {
                    output.append(jpegDataOfSingleImage[index..<index + Int(length)])
                }
                index += Int(length)

            }
        }
        
    }
    
    
}


enum ComputeExtendedPayloadOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case contextIsNil
    case coreDataError(error: Error)
    case persistedMessageSentObjectIDIsNil
    case couldNotFindPersistedMessageSentInDatabase

    
    var logType: OSLogType {
        switch self {
        case .coreDataError, .contextIsNil, .persistedMessageSentObjectIDIsNil:
            return .fault
        case .couldNotFindPersistedMessageSentInDatabase:
            return .error
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil: return "Context is nil"
        case .coreDataError(error: let error): return "Core Data error: \(error.localizedDescription)"
        case .persistedMessageSentObjectIDIsNil:
            return "persistedMessageSentObjectID is nil"
        case .couldNotFindPersistedMessageSentInDatabase:
            return "Could not find the PersistedMessageSent in database"
        }
    }

}



// MARK: - Utils

private extension Data.Iterator {
    
    // Consumes two bytes and returns the conrresponding UInt16
    mutating func nextUnsignedShort() -> (unsignedShort: UInt16, twoBytes: [UInt8])? {
        guard let byte1 = next(), let byte2 = next() else { return nil }
        let us = (UInt16(byte1) << 8) + UInt16(byte2)
        return (us, [byte1, byte2])
    }
    
    
    mutating func skip(numberOfBytes: UInt16) throws {
        for _ in 0..<numberOfBytes {
            guard next() != nil else { throw ComputeExtendedPayloadOperation.makeError(message: "Not enough bytes") }
        }
    }
    
}
