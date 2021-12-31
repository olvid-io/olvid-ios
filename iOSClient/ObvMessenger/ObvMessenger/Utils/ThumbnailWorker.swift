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
import MobileCoreServices
import CoreGraphics
import AVKit
import PDFKit


final class ThumbnailWorker: NSObject {
    
    @objc dynamic var thumbnailCreated = false
    private(set) var fyleElement: FyleElement
    private static let thumbnailCreationQueue = DispatchQueue(label: "ThumbnailWorkerQueue")
    
    private(set) var lastComputedThumnbnail: (type: ThumbnailType, isSymbol: Bool)?
    
    init(fyleElement: FyleElement) {
        self.fyleElement = fyleElement
        super.init()
    }
    
    
    enum ThumbnailImageType: CaseIterable {
        case jpeg
        case png
        
        var fileExtension: String {
            switch self {
            case .jpeg:
                return ObvUTIUtils.jpegExtension()
            case .png:
                return ObvUTIUtils.pngExtension()
            }
        }
    }
    
    
    private func createThumbnailDirectory() throws -> URL {
        let thumbnailsDirectory = ObvMessengerConstants.containerURL.forThumbnails(within: .mainApp) // Should work even if called from the share extension
        let thumbnailDirectory = thumbnailsDirectory.appendingPathComponent(fyleElement.sha256.hexString())
        if !FileManager.default.fileExists(atPath: thumbnailDirectory.path) {
            try FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        return thumbnailDirectory
    }
    
    
    private func getThumbnailURL(maxPixelSize: Int, thumbnailType: ThumbnailImageType) throws -> URL {
        let thumbnailDirectory = try createThumbnailDirectory()
        let fileName = ["\(maxPixelSize)", thumbnailType.fileExtension].joined(separator: ".")
        return thumbnailDirectory.appendingPathComponent(fileName)
    }

    
    func getCachedThumbnailForIOS12orReturnNilOnIOS13(maxPixelSize: Int) throws -> UIImage? {
        if #available(iOS 13, *) {
            return nil
        }
        var thumb: UIImage?
        for imageType in ThumbnailImageType.allCases {
            let url = try getThumbnailURL(maxPixelSize: maxPixelSize, thumbnailType: imageType)
            if FileManager.default.fileExists(atPath: url.path) {
                thumb = UIImage(contentsOfFile: url.path)
            }
            if thumb != nil {
                break
            }
        }
        return thumb
    }
    
    
    @available(iOS 13.0, *)
    func createThumbnail(size: CGSize, thumbnailType: ThumbnailType, fyleIsAvailable: Bool, _ completionHandler: @escaping ((Thumbnail) -> Void)) {
        assert(size != CGSize.zero)
        self.fyleElement = self.fyleElement.replacingFullFileIsAvailable(with: fyleIsAvailable)
        let completionHandlerForRequestThumbnail = { [weak self] (thumbnail: Thumbnail) in
            completionHandler(thumbnail)
            self?.lastComputedThumnbnail = (thumbnailType, thumbnail.isSymbol)
        }
        ObvMessengerInternalNotification.requestThumbnail(
            fyleElement: self.fyleElement,
            size: size,
            thumbnailType: thumbnailType,
            completionHandler: completionHandlerForRequestThumbnail).postOnDispatchQueue()
    }
    
    
    func createThumbnail(maxPixelSize: Int, _ completionHandler: ((UIImage) -> Void)? = nil) {

        if #available(iOS 13, *) {
            assert(false)
        }
        
        ThumbnailWorker.thumbnailCreationQueue.async { [weak self] in
            guard let _self = self else { return }
            if ObvUTIUtils.uti(_self.fyleElement.uti, conformsTo: kUTTypePNG),
               let imageSource = CGImageSourceCreateWithURL(_self.fyleElement.fyleURL as CFURL, nil) {
                
                let options = [kCGImageSourceTypeIdentifierHint: kUTTypePNG,
                               kCGImageSourceCreateThumbnailWithTransform: true,
                               kCGImageSourceCreateThumbnailFromImageAlways: true,
                               kCGImageSourceThumbnailMaxPixelSize: maxPixelSize as CFNumber] as CFDictionary
                guard let cgImageThumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options) else { return }
                guard let thumbnailURL = try? _self.getThumbnailURL(maxPixelSize: maxPixelSize, thumbnailType: .png) else { return }
                guard let destination = CGImageDestinationCreateWithURL(thumbnailURL as CFURL, kUTTypePNG, 1, nil) else { return }
                CGImageDestinationAddImage(destination, cgImageThumbnail, nil)
                guard CGImageDestinationFinalize(destination) else { return }
                _self.thumbnailCreated = true
                
            } else if ObvUTIUtils.uti(_self.fyleElement.uti, conformsTo: kUTTypeJPEG),
                      let imageSource = CGImageSourceCreateWithURL(_self.fyleElement.fyleURL as CFURL, nil) {
                
                let options = [kCGImageSourceTypeIdentifierHint: kUTTypeJPEG,
                               kCGImageSourceCreateThumbnailWithTransform: true,
                               kCGImageSourceCreateThumbnailFromImageAlways: true,
                               kCGImageSourceThumbnailMaxPixelSize: maxPixelSize as CFNumber] as CFDictionary
                guard let cgImageThumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options) else { return }
                guard let thumbnailURL = try? _self.getThumbnailURL(maxPixelSize: maxPixelSize, thumbnailType: .jpeg) else { return }
                guard let destination = CGImageDestinationCreateWithURL(thumbnailURL as CFURL, kUTTypeJPEG, 1, nil) else { return }
                CGImageDestinationAddImage(destination, cgImageThumbnail, nil)
                guard CGImageDestinationFinalize(destination) else { return }
                _self.thumbnailCreated = true
                
            } else if ObvUTIUtils.uti(_self.fyleElement.uti, conformsTo: kUTTypeMovie) {
                
                let completionHandler = { (hardLinkToFyle: HardLinkToFyle) in
                    
                    guard let hardlinkURL = hardLinkToFyle.hardlinkURL else { return }
                    ThumbnailWorker.thumbnailCreationQueue.async {
                        let asset = AVAsset(url: hardlinkURL)
                        let assetImgGenerate = AVAssetImageGenerator(asset: asset)
                        assetImgGenerate.appliesPreferredTrackTransform = true
                        let time = CMTimeMakeWithSeconds(Float64(1), preferredTimescale: Int32(100))
                        let cgImageThumbnail: CGImage
                        do {
                            cgImageThumbnail = try assetImgGenerate.copyCGImage(at: time, actualTime: nil)
                        } catch {
                            return
                        }
                        guard let thumbnailURL = try? _self.getThumbnailURL(maxPixelSize: maxPixelSize, thumbnailType: .jpeg) else { return }
                        guard let destination = CGImageDestinationCreateWithURL(thumbnailURL as CFURL, kUTTypeJPEG, 1, nil) else { return }
                        CGImageDestinationAddImage(destination, cgImageThumbnail, nil)
                        guard CGImageDestinationFinalize(destination) else { return }
                        _self.thumbnailCreated = true
                        
                        if let thumbnail = try? _self.getCachedThumbnailForIOS12orReturnNilOnIOS13(maxPixelSize: maxPixelSize) {
                            DispatchQueue.main.async {
                                completionHandler?(thumbnail)
                            }
                        }

                    }
                }
                ObvMessengerInternalNotification.requestHardLinkToFyle(fyleElement: _self.fyleElement, completionHandler: completionHandler).postOnDispatchQueue()
            } else if ObvUTIUtils.uti(_self.fyleElement.uti, conformsTo: kUTTypePDF),
                      let pdfDocument = PDFDocument(url: _self.fyleElement.fyleURL), let firstPage = pdfDocument.page(at: 0) {
                
                let preview = firstPage.thumbnail(of: CGSize(width: maxPixelSize, height: maxPixelSize), for: .cropBox)
                guard let thumbnailURL = try? _self.getThumbnailURL(maxPixelSize: maxPixelSize, thumbnailType: .jpeg) else { return }
                do {
                    try preview.jpegData(compressionQuality: 1.0)?.write(to: thumbnailURL)
                } catch {
                    return
                }
                _self.thumbnailCreated = true
                
            }

            if let thumbnail = try? _self.getCachedThumbnailForIOS12orReturnNilOnIOS13(maxPixelSize: maxPixelSize) {
                DispatchQueue.main.async {
                    completionHandler?(thumbnail)
                }
            }
        }
        
    }
    
    
    func removeAllThumnails() {
        guard let url = try? createThumbnailDirectory() else { return }
        try? FileManager.default.removeItem(at: url)
    }
    
}
