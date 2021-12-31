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

import Foundation
import OlvidUtils
import os.log
import ObvEngine
import ObvEncoder


final class ProcessReceivedExtendedPayloadOperation: ContextualOperationWithSpecificReasonForCancel<ProcessReceivedExtendedPayloadOperationReasonForCancel> {

    private let obvMessage: ObvMessage
    private let extendedMessagePayload: Data
    
    static var downsizedImageSize: CGSize {
        ComputeExtendedPayloadOperation.downsizedImageSize
    }
    
    init(obvMessage: ObvMessage, extendedMessagePayload: Data) {
        self.obvMessage = obvMessage
        self.extendedMessagePayload = extendedMessagePayload
        super.init()
    }
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {
            
            do {
                
                guard let message = try PersistedMessageReceived.get(messageIdentifierFromEngine: obvMessage.messageIdentifierFromEngine, from: obvMessage.fromContactIdentity, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindReceivedMessageInDatabase)
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
                let result: Result<Void, ProcessReceivedExtendedPayloadOperationReasonForCancel>
                switch extendedPayloadVersion {
                case 0:
                    result = processExtendedPayloadVersion0(listOfEncodedElements: listOfEncodedElements, message: message)
                default:
                    result = .failure(.unhandledExtendedPayloadVersion)
                }
                
                switch result {
                case .success:
                    break
                case .failure(let reason):
                    return cancel(withReason: reason)
                }
                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
            
        }
        
    }
    
    
    private func processExtendedPayloadVersion0(listOfEncodedElements: [ObvEncoded], message: PersistedMessageReceived) -> Result<Void, ProcessReceivedExtendedPayloadOperationReasonForCancel> {
        
        guard listOfEncodedElements.count == 2 else {
            return .failure(.unexpectedNumberOfElements)
        }
        
        let encodedListOfAttachmentNumbers = listOfEncodedElements[0]
        let encodedJpegDataOfSingleImage = listOfEncodedElements[1]
        
        guard let listOfEncodedAttachmentNumbers = [ObvEncoded](encodedListOfAttachmentNumbers) else {
            return .failure(.decodingError)
        }
        
        guard !listOfEncodedAttachmentNumbers.isEmpty else { return .success(()) }
        
        let attachmentNumbers = listOfEncodedAttachmentNumbers.compactMap({ Int($0) })
        guard attachmentNumbers.count == listOfEncodedAttachmentNumbers.count else {
            return .failure(.decodingError)
        }
        
        guard let max = attachmentNumbers.max(), let min = attachmentNumbers.min(), max < message.fyleMessageJoinWithStatuses.count, min >= 0 else {
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
        
        guard !attachmentNumbersAndDownsizedImages.isEmpty else { return .success(()) }
        
        return saveDownsizedImage(attachmentNumbersAndDownsizedImages: attachmentNumbersAndDownsizedImages, message: message)
        
    }
    
    
    private func saveDownsizedImage(attachmentNumbersAndDownsizedImages: [(attachmentNumber: Int, downsizedImage: CGImage)], message: PersistedMessageReceived) -> Result<Void, ProcessReceivedExtendedPayloadOperationReasonForCancel> {
        
        guard let obvContext = self.obvContext else {
            return .failure(.contextIsNil)
        }
        
        var result: Result<Void, ProcessReceivedExtendedPayloadOperationReasonForCancel> = .success(())
        obvContext.performAndWait {
            
            for (attachmentNumber, downsizedImage) in attachmentNumbersAndDownsizedImages {
                guard attachmentNumber < message.fyleMessageJoinWithStatuses.count else {
                    result = .failure(.unexpectedAttachmentNumber)
                    break
                }

                guard let jpegDataOfDownsizedImage = UIImage(cgImage: downsizedImage).jpegData(compressionQuality: 0.75) else {
                    continue
                }

                let fyleMessageJoinWithStatus = message.fyleMessageJoinWithStatuses[attachmentNumber]
                
                fyleMessageJoinWithStatus.setDownsizedThumbnailIfRequired(data: jpegDataOfDownsizedImage)
            }
            
        }
        
        return result
        
    }
    
    
    private func extractDownsizedImagesFromSingleImage(_ singleImage: CGImage, attachmentNumbers: [Int]) -> [(attachmentNumber: Int, downsizedImage: CGImage)]? {
        
        let downsizedImageSize = ProcessReceivedExtendedPayloadOperation.downsizedImageSize
        
        let numberOfColumns: Int = Int(sqrt(Double(attachmentNumbers.count)).rounded(.awayFromZero))
        let numberOfRows: Int = (attachmentNumbers.count - 1) / numberOfColumns + 1

        let expectedSingleImageSize = CGSize(width: downsizedImageSize.width * CGFloat(numberOfColumns), height: downsizedImageSize.width * CGFloat(numberOfRows))
        
        guard expectedSingleImageSize == CGSize(width: singleImage.width, height: singleImage.height) else {
            return nil
        }
        
        var attachmentNumbersAnddownsizedImages = [(attachmentNumber: Int, downsizedImage: CGImage)]()
        
        var index = 0
        for row in 0..<numberOfRows {
            guard index < attachmentNumbers.count else { break }
            for column in 0..<numberOfColumns {
                guard index < attachmentNumbers.count else { break }
                let origin = CGPoint(x: CGFloat(column) * downsizedImageSize.width, y: CGFloat(row) * downsizedImageSize.height)
                let size = CGSize(width: downsizedImageSize.width, height: downsizedImageSize.height)
                let rect = CGRect(origin: origin, size: size)
                guard let downsizedImage = singleImage.cropping(to: rect) else { continue }
                attachmentNumbersAnddownsizedImages.append((attachmentNumbers[index], downsizedImage))
                index += 1
            }
        }

        return attachmentNumbersAnddownsizedImages
        
    }
    
}


enum ProcessReceivedExtendedPayloadOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case contextIsNil
    case coreDataError(error: Error)
    case couldNotFindReceivedMessageInDatabase
    case couldNotParseExtendedPayloadAsObvEncoded
    case couldNotParseExtendedPayloadAsArrayOfObvEncoded
    case couldNotDetermineExtendedPayloadVersion
    case unhandledExtendedPayloadVersion
    case unexpectedNumberOfElements
    case decodingError
    case unexpectedAttachmentNumber
    case couldNotExtractSingleImage
    case couldNotExtractDownsizedImages

    
    var logType: OSLogType {
        switch self {
        case .coreDataError, .contextIsNil:
            return .fault
        case .couldNotFindReceivedMessageInDatabase, .couldNotParseExtendedPayloadAsObvEncoded, .couldNotParseExtendedPayloadAsArrayOfObvEncoded, .couldNotDetermineExtendedPayloadVersion, .unhandledExtendedPayloadVersion, .unexpectedNumberOfElements, .decodingError, .unexpectedAttachmentNumber, .couldNotExtractSingleImage, .couldNotExtractDownsizedImages:
            return .error
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .contextIsNil: return "Context is nil"
        case .coreDataError(error: let error): return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindReceivedMessageInDatabase: return "Could not find received message in database"
        case .couldNotParseExtendedPayloadAsObvEncoded: return "Could not parse extended payload as ObvEncoded"
        case .couldNotParseExtendedPayloadAsArrayOfObvEncoded: return "Could not parse extended payload as list of encoded"
        case .couldNotDetermineExtendedPayloadVersion: return "Could not determine extended payload version"
        case .unhandledExtendedPayloadVersion: return "Unhandled extended payload version"
        case .unexpectedNumberOfElements: return "Unexpected number of elements in extended payload"
        case .decodingError: return "Decoding error"
        case .unexpectedAttachmentNumber: return "Unexpected attachment number"
        case .couldNotExtractSingleImage: return "Could not extract single image"
        case .couldNotExtractDownsizedImages: return "Could not extract downsized images"
        }
    }

}
