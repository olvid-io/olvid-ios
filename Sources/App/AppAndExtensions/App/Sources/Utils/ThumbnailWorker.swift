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

import UIKit
import MobileCoreServices
import CoreGraphics
import AVKit
import PDFKit
import ObvUICoreData
import ObvSettings


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
                return UTType.jpeg.preferredFilenameExtension ?? "jpeg"
            case .png:
                return UTType.png.preferredFilenameExtension ?? "png"
            }
        }
    }
    
    private func createThumbnailDirectory() throws -> URL {
        let thumbnailsDirectory = ObvUICoreDataConstants.ContainerURL.forThumbnailsWithinMainApp.url // Should work even if called from the share extension
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
    
    
    func removeAllThumnails() {
        guard let url = try? createThumbnailDirectory() else { return }
        try? FileManager.default.removeItem(at: url)
    }
    
}
