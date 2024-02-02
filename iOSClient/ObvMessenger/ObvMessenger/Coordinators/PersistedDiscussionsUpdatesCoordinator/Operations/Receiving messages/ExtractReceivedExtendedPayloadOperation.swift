/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import OlvidUtils
import os.log
import ObvEngine
import ObvTypes
import ObvEncoder
import CoreGraphics
import ObvUICoreData
import CoreData


/// This operation does not need a context and thus, is not a contextual operation. Since it is used in the notification extension at a location where we have no context available, we definitely don't want it to be a contextual operation.
final class ExtractReceivedExtendedPayloadOperation: OperationWithSpecificReasonForCancel<ExtractReceivedExtendedPayloadOperationReasonForCancel> {

    enum Input {
        case messageSentByContact(obvMessage: ObvMessage)
        case messageSentByOtherDeviceOfOwnedIdentity(obvOwnedMessage: ObvOwnedMessage)
    }
    
    let input: Input

    init(input: Input) {
        self.input = input
        super.init()
    }

    var attachementImages: [NotificationAttachmentImage]?

    override func main() {

        let extendedMessagePayload: Data?
        switch input {
        case .messageSentByContact(obvMessage: let obvMessage):
            extendedMessagePayload = obvMessage.extendedMessagePayload
        case .messageSentByOtherDeviceOfOwnedIdentity(obvOwnedMessage: let obvOwnedMessage):
            extendedMessagePayload = obvOwnedMessage.extendedMessagePayload
        }
        
        guard let extendedMessagePayload else {
            return cancel(withReason: .extendedMessagePayloadIsNil)
        }

        guard let encodedExtendedPayload = ObvEncoded(withRawData: extendedMessagePayload) else {
            return cancel(withReason: .couldNotParseExtendedPayloadAsObvEncoded)
        }

        guard var listOfEncodedElements = [ObvEncoded](encodedExtendedPayload) else {
            return cancel(withReason: .couldNotParseExtendedPayloadAsArrayOfObvEncoded)
        }

        // Check the version of the received encoded payload
        guard listOfEncodedElements.count > 0 else {
            return cancel(withReason: .couldNotDetermineExtendedPayloadVersion)
        }
        guard let extendedPayloadVersion = Int(listOfEncodedElements.removeFirst()) else {
            return cancel(withReason: .couldNotDetermineExtendedPayloadVersion)
        }

        // For now, we only support version 0 of the extended payload
        let result: Result<[NotificationAttachmentImage], ExtractReceivedExtendedPayloadOperationReasonForCancel>
        switch extendedPayloadVersion {
        case 0:
            result = processExtendedPayloadVersion0(listOfEncodedElements: listOfEncodedElements)
        default:
            result = .failure(.unhandledExtendedPayloadVersion)
        }

        switch result {
        case .success(let attachementImages):
            self.attachementImages = attachementImages
        case .failure(let reason):
            return cancel(withReason: reason)
        }
        
    }

    private func processExtendedPayloadVersion0(listOfEncodedElements: [ObvEncoded]) -> Result<[NotificationAttachmentImage], ExtractReceivedExtendedPayloadOperationReasonForCancel> {

        guard listOfEncodedElements.count == 2 else {
            return .failure(.unexpectedNumberOfElements)
        }

        let encodedListOfAttachmentNumbers = listOfEncodedElements[0]
        let encodedJpegDataOfSingleImage = listOfEncodedElements[1]

        guard let listOfEncodedAttachmentNumbers = [ObvEncoded](encodedListOfAttachmentNumbers) else {
            return .failure(.decodingError)
        }

        guard !listOfEncodedAttachmentNumbers.isEmpty else { return .success([]) }

        let attachmentNumbers = listOfEncodedAttachmentNumbers.compactMap({ Int($0) })
        guard attachmentNumbers.count == listOfEncodedAttachmentNumbers.count else {
            return .failure(.decodingError)
        }
        
        let expectedAttachmentsCount: Int
        switch input {
        case .messageSentByContact(obvMessage: let obvMessage):
            expectedAttachmentsCount = obvMessage.expectedAttachmentsCount
        case .messageSentByOtherDeviceOfOwnedIdentity(obvOwnedMessage: let obvOwnedMessage):
            expectedAttachmentsCount = obvOwnedMessage.expectedAttachmentsCount
        }

        guard let max = attachmentNumbers.max(), let min = attachmentNumbers.min(), max < expectedAttachmentsCount, min >= 0 else {
            return .failure(.unexpectedAttachmentNumber)
        }

        guard let jpegDataOfSingleImage = Data(encodedJpegDataOfSingleImage) else {
            return .failure(.decodingError)
        }

        guard let dataProvider = CGDataProvider(data: jpegDataOfSingleImage as CFData), let singleImage = CGImage(jpegDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            return .failure(.couldNotExtractSingleImage)
        }

        guard let attachmentNumbersAndDownsizedImages = extractDownsizedImagesFromSingleImage(singleImage, attachmentNumbers: attachmentNumbers) else {
            return .failure(.couldNotExtractDownsizedImages)
        }

        guard !attachmentNumbersAndDownsizedImages.isEmpty else { return .success([]) }

        return .success(attachmentNumbersAndDownsizedImages)
    }

    private func extractDownsizedImagesFromSingleImage(_ singleImage: CGImage, attachmentNumbers: [Int]) -> [NotificationAttachmentImage]? {

        let downsizedImageSize = ObvMessengerConstants.downsizedImageSize

        let numberOfColumns: Int = Int(sqrt(Double(attachmentNumbers.count)).rounded(.awayFromZero))
        let numberOfRows: Int = (attachmentNumbers.count - 1) / numberOfColumns + 1

        let expectedSingleImageSize = CGSize(width: downsizedImageSize.width * CGFloat(numberOfColumns), height: downsizedImageSize.width * CGFloat(numberOfRows))

        guard expectedSingleImageSize == CGSize(width: singleImage.width, height: singleImage.height) else {
            return nil
        }

        var attachmentImages = [NotificationAttachmentImage]()

        var index = 0
        for row in 0..<numberOfRows {
            guard index < attachmentNumbers.count else { break }
            for column in 0..<numberOfColumns {
                guard index < attachmentNumbers.count else { break }
                let origin = CGPoint(x: CGFloat(column) * downsizedImageSize.width, y: CGFloat(row) * downsizedImageSize.height)
                let size = CGSize(width: downsizedImageSize.width, height: downsizedImageSize.height)
                let rect = CGRect(origin: origin, size: size)
                guard let downsizedImage = singleImage.cropping(to: rect) else { continue }
                attachmentImages.append(.cgImage(attachmentNumber: attachmentNumbers[index], downsizedImage))
                index += 1
            }
        }

        return attachmentImages

    }

}

enum ExtractReceivedExtendedPayloadOperationReasonForCancel: LocalizedErrorWithLogType {
    case couldNotParseExtendedPayloadAsObvEncoded
    case couldNotParseExtendedPayloadAsArrayOfObvEncoded
    case couldNotDetermineExtendedPayloadVersion
    case unhandledExtendedPayloadVersion
    case unexpectedNumberOfElements
    case decodingError
    case unexpectedAttachmentNumber
    case couldNotExtractSingleImage
    case couldNotExtractDownsizedImages
    case extendedMessagePayloadIsNil


    var logType: OSLogType { .error }


    var errorDescription: String? {
        switch self {
        case .couldNotParseExtendedPayloadAsObvEncoded: return "Could not parse extended payload as ObvEncoded"
        case .couldNotParseExtendedPayloadAsArrayOfObvEncoded: return "Could not parse extended payload as list of encoded"
        case .couldNotDetermineExtendedPayloadVersion: return "Could not determine extended payload version"
        case .unhandledExtendedPayloadVersion: return "Unhandled extended payload version"
        case .unexpectedNumberOfElements: return "Unexpected number of elements in extended payload"
        case .decodingError: return "Decoding error"
        case .unexpectedAttachmentNumber: return "Unexpected attachment number"
        case .couldNotExtractSingleImage: return "Could not extract single image"
        case .couldNotExtractDownsizedImages: return "Could not extract downsized images"
        case .extendedMessagePayloadIsNil: return "Extended message payload is nil"
        }
    }


}
