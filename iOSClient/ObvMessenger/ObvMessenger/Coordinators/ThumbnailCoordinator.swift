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
import os.log
import QuickLookThumbnailing
import MobileCoreServices


enum ThumbnailType {
    case normal
    case visibilityRestricted
    case wiped
}


final class ThumbnailCoordinator {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: ThumbnailCoordinator.self))
    
    /// This directory will contain all the thumbnails
    private let currentDirectory: URL
    
    /// Directories created in previous sessions. We delete all these directories in a background thread.
    private let previousDirectories: [URL]
    
    private let queueForDeletingPreviousDirectories = DispatchQueue(label: "Queue for deleting previous directories containing thumbnails")
    
    private let queueForNotifications: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    
    private var observationTokens = [NSObjectProtocol]()
    
    private var thumbnails = Set<Thumbnail>()

    private var appType: ObvMessengerConstants.AppType
    
    init(appType: ObvMessengerConstants.AppType) {
        self.appType = appType
        let url = ObvMessengerConstants.containerURL.forThumbnails(within: appType)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        self.previousDirectories = try! FileManager.default.contentsOfDirectory(atPath: url.path).map { url.appendingPathComponent($0) }
        self.currentDirectory = url.appendingPathComponent(UUID().description)
        try! FileManager.default.createDirectory(at: self.currentDirectory, withIntermediateDirectories: true, attributes: nil)
        deletePreviousDirectories()
        observeRequestThumbnailNotifications()
        observeUserIsLeavingDiscussionNotifications()
    }
    
    
    deinit {
        self.deleteCurrentDirectory()
    }
    
    
    private func deleteCurrentDirectory() {
        do {
            try FileManager.default.removeItem(at: currentDirectory)
        } catch let error {
            os_log("Could not delete directory at %{public}@: %{public}@", log: log, type: .error, currentDirectory.path, error.localizedDescription)
        }
    }

    
    private func deletePreviousDirectories() {
        let log = self.log
        queueForDeletingPreviousDirectories.async { [weak self] in
            guard let _self = self else { return }
            for url in _self.previousDirectories {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch let error {
                    os_log("Could not delete directory at %{public}@: %{public}@", log: log, type: .error, url.path, error.localizedDescription)
                }
            }
        }
    }
    
    
    /// Each time the user leaves a discussion, we wipe the cache of thumbnails
    private func observeUserIsLeavingDiscussionNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeCurrentUserActivityDidChange(queue: queueForNotifications) { [weak self] (previousUserActivity, currentUserActivity) in
            // Check that the discussion changed
            guard let previousDiscussionObjectID = previousUserActivity.persistedDiscussionObjectID, previousDiscussionObjectID != currentUserActivity.persistedDiscussionObjectID else { return }
            self?.thumbnails.removeAll()
        })
    }
    
    
    private func observeRequestThumbnailNotifications() {

        let log = self.log
        
        observationTokens.append(ObvMessengerInternalNotification.observeRequestThumbnail(queue: queueForNotifications, block: { [weak self] (fyleElement, size, thumbnailType, completionHandler) in
            guard let _self = self else { return }

            switch thumbnailType {
            
            case .visibilityRestricted:
                
                // If we are dealing with a "visibilityRestricted" attachment, we do not return a proper preview, but a static symbol image
                guard let image = UIImage(systemName: "timer") else { assertionFailure(); return }
                let thumbnail = Thumbnail(fyleURL: fyleElement.fyleURL, fileName: fyleElement.fileName, size: size, image: image, isSymbol: true)
                completionHandler(thumbnail)
                return
                
            case .wiped:
                
                // If we are dealing with a "readOnce" attachment, we do not return a proper preview, but a static symbol image
                guard let image = UIImage(systemName: "flame.fill") else { assertionFailure(); return }
                let thumbnail = Thumbnail(fyleURL: fyleElement.fyleURL, fileName: fyleElement.fileName, size: size, image: image, isSymbol: true)
                completionHandler(thumbnail)
                return
                
            case .normal:
                
                guard fyleElement.fullFileIsAvailable else {
                    self?.createSymbolThumbnail(uti: fyleElement.uti) { (image) in
                        guard let image = image else {
                            os_log("Could not generate an appropriate thumbnail for uti %{public}@", log: log, type: .fault, fyleElement.uti)
                            assertionFailure()
                            return
                        }
                        let thumbnail = Thumbnail(fyleURL: fyleElement.fyleURL, fileName: fyleElement.fileName, size: size, image: image, isSymbol: true)
                        self?.queueForNotifications.addOperation {
                            completionHandler(thumbnail)
                        }
                        return
                    }
                    return
                }
                
                // If a thumbnail already exists, return it.
                if let thumbnail = _self.thumbnails.filter({ $0.fyleURL == fyleElement.fyleURL && $0.fileName == fyleElement.fileName && $0.size == size }).first {
                    completionHandler(thumbnail)
                    return
                }
                
                // If we reach this point, no previous thumbnail exists for the fyle. We create it.
                
                let completionHandlerForRequestHardLinkToFyle = { [weak self] (result: Result<HardLinkToFyle, Error>) in
                    guard let _self = self else { return }
                    switch result {
                    case .success(let hardLinkToFyle):
                        _self.createThumbnail(hardLinkToFyle: hardLinkToFyle, size: size, uti: hardLinkToFyle.uti) { (image, isSymbol) in
                            let thumbnail = Thumbnail(fyleURL: hardLinkToFyle.fyleURL, fileName: hardLinkToFyle.fileName, size: size, image: image, isSymbol: isSymbol)
                            if !isSymbol {
                                self?.thumbnails.insert(thumbnail)
                            }
                            completionHandler(thumbnail)
                        }
                    case .failure(let error):
                        assertionFailure(error.localizedDescription)
                    }
                }
                ObvMessengerInternalNotification.requestHardLinkToFyle(fyleElement: fyleElement, completionHandler: completionHandlerForRequestHardLinkToFyle)
                    .postOnDispatchQueue()
            }
            
        }))
        
    }
    

    private func createThumbnail(hardLinkToFyle: HardLinkToFyle, size: CGSize, uti: String, completionHandler: @escaping (UIImage, Bool) -> Void) {
        assert(size != CGSize.zero)
        guard let hardlinkURL = hardLinkToFyle.hardlinkURL else {
            os_log("The hardlink within the hardLinkToFyle is nil, which is unexpected", log: log, type: .fault)
            assert(false)
            return
        }
        let scale = UIScreen.main.scale
        let request = QLThumbnailGenerator.Request(fileAt: hardlinkURL, size: size, scale: scale, representationTypes: .thumbnail)
        let generator = QLThumbnailGenerator.shared
        generator.generateRepresentations(for: request) { [weak self] (thumbnail, type, error) in
            guard let log = self?.log else { return }
            if thumbnail == nil || error != nil {
                os_log("The thumbnail generation failed. We try to set an appropriate generic thumbnail", log: log, type: .error)
                self?.createSymbolThumbnail(uti: uti) { (thumbnail) in
                    guard let thumbnail = thumbnail else {
                        os_log("Could not generate an appropriate thumbnail for uti %{public}@", log: log, type: .fault, uti)
                        return
                    }
                    self?.queueForNotifications.addOperation {
                        completionHandler(thumbnail, true)
                    }
                }
                return
            } else {
                self?.queueForNotifications.addOperation {
                    completionHandler(thumbnail!.uiImage, false)
                }
            }
        }

    }
    

    private func createSymbolThumbnail(uti: String, completionHandler: @escaping (UIImage?) -> Void) {
        // See CoreServices > UTCoreTypes
        if ObvUTIUtils.uti(uti, conformsTo: "org.openxmlformats.wordprocessingml.document" as CFString) {
            // Word (docx) document
            let image = UIImage(systemName: "doc.fill")
            completionHandler(image)
        } else if ObvUTIUtils.uti(uti, conformsTo: kUTTypeArchive) {
            // Zip archive
            let image = UIImage(systemName: "rectangle.compress.vertical")
            completionHandler(image)
        } else if ObvUTIUtils.uti(uti, conformsTo: kUTTypeWebArchive) {
            // Web archive
            let image = UIImage(systemName: "archivebox.fill")
            completionHandler(image)
        } else {
            let image = UIImage(systemName: "paperclip")
            completionHandler(image)
        }
    }
    
}



// MARK: - Thumbnail

final class Thumbnail: NSObject {
    
    let fyleURL: URL
    let fileName: String
    let size: CGSize
    let image: UIImage
    let isSymbol: Bool
    
    fileprivate init(fyleURL: URL, fileName: String, size: CGSize, image: UIImage, isSymbol: Bool) {
        self.fyleURL = fyleURL
        self.fileName = fileName
        self.size = size
        self.image = image
        self.isSymbol = isSymbol
        super.init()
    }
}


fileprivate extension UIImage {

    func addImagePadding(x: CGFloat, y: CGFloat) -> UIImage? {
        let width: CGFloat = size.width + x
        let height: CGFloat = size.height + y
        UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: height), false, 0)
        let origin: CGPoint = CGPoint(x: (width - size.width) / 2, y: (height - size.height) / 2)
        draw(at: origin)
        let imageWithPadding = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return imageWithPadding
    }
}
