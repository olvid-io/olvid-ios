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
import CoreData
import MobileCoreServices
import os.log
import ObvCrypto
import PDFKit
import AVFoundation
import VisionKit
import PhotosUI
import OlvidUtils


final class ComposeMessageViewDocumentPickerAdapterWithDraft: NSObject {
    
    // API
    
    private let draft: PersistedDraft
    
    // Delegate
    
    weak var delegate: UIViewController?
    
    // Variables
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
    private let internalOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "ComposeMessageViewDocumentPickerAdapterWithDraft internal queue"
        return queue
    }()

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return df
    }()

    // Initializer
    
    init(draft: PersistedDraft) {
        self.draft = draft
        super.init()
    }
    
}

extension ComposeMessageViewDocumentPickerAdapterWithDraft {
    
    func addAttachmentFromAirDropFile(at url: URL) {
        
        // Get the filename
        let fileName = url.lastPathComponent

        // Save the file to a temp location
        let tempURL = ObvMessengerConstants.containerURL.forTempFiles.appendingPathComponent(fileName)
        do {
            _ = url.startAccessingSecurityScopedResource()
            try FileManager.default.copyItem(at: url, to: tempURL)
            url.stopAccessingSecurityScopedResource()
        } catch {
            os_log("Could not save AirDrop file to temp URL", log: log, type: .error)
            return
        }

        // Add an attachment
        
        self.delegate?.showHUD(type: .spinner)
        
        let op = LoadFileRepresentationsThenCreateDraftFyleJoinsCompositeOperation(draftObjectID: draft.typedObjectID, fileURLs: [tempURL], log: log)
        op.completionBlock = { [weak self] in
            DispatchQueue.main.async {
                self?.delegate?.hideHUD()
            }
        }
        internalOperationQueue.addOperation(op)

    }
    
}

extension ComposeMessageViewDocumentPickerAdapterWithDraft: ComposeMessageViewDocumentPickerDelegate {

    // This method is typically called when performing a drop on the growing text field.
    func addAttachments(itemProviders: [NSItemProvider]) {
        assert(Thread.isMainThread)
        guard !itemProviders.isEmpty else { return }
        self.delegate?.showHUD(type: .spinner)
        let op = LoadFileRepresentationsThenCreateDraftFyleJoinsCompositeOperation(draftObjectID: draft.typedObjectID, itemProviders: itemProviders, log: log)
        op.completionBlock = { [weak self] in
            DispatchQueue.main.async {
                self?.delegate?.hideHUD()
            }
        }
        internalOperationQueue.addOperation(op)
    }
    
    
    func addAttachmentFromPasteboard() {
        os_log("Adding %d attachments from the pasteboard", log: log, type: .info, UIPasteboard.general.itemProviders.count)
        addAttachments(itemProviders: UIPasteboard.general.itemProviders)
    }
    
    
    private func addAttachment(atURL url: URL) {
        assert(Thread.isMainThread)
        self.delegate?.showHUD(type: .spinner)
        let op = LoadFileRepresentationsThenCreateDraftFyleJoinsCompositeOperation(draftObjectID: draft.typedObjectID, fileURLs: [url], log: log)
        op.completionBlock = { [weak self] in
            DispatchQueue.main.async {
                self?.delegate?.hideHUD()
            }
        }
        internalOperationQueue.addOperation(op)
    }

    
    func addAttachment(_ sender: UIView) {
        
        let alert = UIAlertController(title: Strings.addAttachment, message: nil, preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: Strings.addAttachmentDocument, style: .default, handler: { [weak self] (action) in
            // See UTCoreTypes.h for types
            // Since we have kUTTypeItem, other elements in the array may be useless
            let documentTypes = [kUTTypeImage, kUTTypeMovie, kUTTypePDF, kUTTypeData, kUTTypeItem] as [String]
            let documentPicker = UIDocumentPickerViewController(documentTypes: documentTypes, in: .import)
            documentPicker.delegate = self
            documentPicker.allowsMultipleSelection = true
            DispatchQueue.main.async {
                self?.delegate?.present(documentPicker, animated: true)
            }
        }))
        
        if UIImagePickerController.isSourceTypeAvailable(.photoLibrary) {
            alert.addAction(UIAlertAction(title: Strings.addAttachmentPhotoAndVideoLibrary, style: .default, handler: { [weak self] (action) in
                if #available(iOS 14.0, *) {
                    var configuration = PHPickerConfiguration()
                    configuration.selectionLimit = 0
                    let picker = PHPickerViewController(configuration: configuration)
                    picker.delegate = self
                    assert(Thread.isMainThread)
                    self?.delegate?.present(picker, animated: true)
                } else {
                    let imagePicker = UIImagePickerController()
                    imagePicker.sourceType = .photoLibrary
                    imagePicker.mediaTypes = [kUTTypeImage, kUTTypeMovie] as [String]
                    imagePicker.delegate = self
                    imagePicker.allowsEditing = false
                    imagePicker.videoExportPreset = AVAssetExportPresetPassthrough
                    DispatchQueue.main.async {
                        self?.delegate?.present(imagePicker, animated: true)
                    }
                }
            }))
        }
        
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            alert.addAction(UIAlertAction(title: CommonString.Word.Camera, style: .default, handler: { [weak self] (action) in
                switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
                case .authorized:
                    self?.setupAndPresentCaptureSession()
                case .notDetermined:
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        if granted {
                            DispatchQueue.main.async {
                                self?.setupAndPresentCaptureSession()
                            }
                        }
                    }
                case .denied,
                     .restricted:
                    let NotificationType = MessengerInternalNotification.UserTriedToAccessCameraButAccessIsDenied.self
                    NotificationCenter.default.post(name: NotificationType.name, object: nil)
                @unknown default:
                    assertionFailure("A recent AVCaptureDevice.authorizationStatus is not properly handled")
                    return
                }
            }))
        }
        
        if #available(iOS 13, *), UIImagePickerController.isSourceTypeAvailable(.camera), VNDocumentCameraViewController.isSupported {
            alert.addAction(UIAlertAction(title: CommonString.Title.scanDocument, style: .default, handler: { [weak self] (action) in
                switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
                case .authorized:
                    self?.setupAndPresentDocumentCameraViewController()
                case .notDetermined:
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        if granted {
                            DispatchQueue.main.async {
                                self?.setupAndPresentDocumentCameraViewController()
                            }
                        }
                    }
                case .denied,
                     .restricted:
                    let NotificationType = MessengerInternalNotification.UserTriedToAccessCameraButAccessIsDenied.self
                    NotificationCenter.default.post(name: NotificationType.name, object: nil)
                @unknown default:
                    assertionFailure("A recent AVCaptureDevice.authorizationStatus is not properly handled")
                    return
                }
            }))
        }
        
        alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
        
        DispatchQueue.main.async { [weak self] in
            alert.popoverPresentationController?.sourceView = sender
            self?.delegate?.present(alert, animated: true)
        }
        
    }
    
    
    
    private func setupAndPresentDocumentCameraViewController() {
        assert(Thread.isMainThread)
        let documentCameraViewController = VNDocumentCameraViewController()
        documentCameraViewController.delegate = self
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.present(documentCameraViewController, animated: true)
        }
    }
    
    
    private func setupAndPresentCaptureSession() {
        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = .camera
        imagePicker.mediaTypes = [kUTTypeImage, kUTTypeMovie] as [String]
        imagePicker.delegate = self
        imagePicker.allowsEditing = false
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.present(imagePicker, animated: true)
        }
    }
    
}


// MARK: - UIDocumentPickerDelegate

extension ComposeMessageViewDocumentPickerAdapterWithDraft: UIDocumentPickerDelegate {
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        
        self.delegate?.showHUD(type: .spinner)
        
        let op = LoadFileRepresentationsThenCreateDraftFyleJoinsCompositeOperation(draftObjectID: draft.typedObjectID, fileURLs: urls, log: log)
        op.completionBlock = { [weak self] in
            DispatchQueue.main.async {
                self?.delegate?.hideHUD()
            }
        }
        internalOperationQueue.addOperation(op)

    }
    
}


// MARK: - PHPickerViewControllerDelegate (for iOS >= 14.0)

@available(iOS 14, *)
extension ComposeMessageViewDocumentPickerAdapterWithDraft: PHPickerViewControllerDelegate {
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }
        let itemProviders = results.map { $0.itemProvider }
        addAttachments(itemProviders: itemProviders)
    }
    
}

// MARK: - UIImagePickerControllerDelegate (for iOS < 14.0 and for the Camera)

extension ComposeMessageViewDocumentPickerAdapterWithDraft: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        
        picker.dismiss(animated: true)
        delegate?.showHUD(type: .spinner)

        let dateFormatter = self.dateFormatter
        let log = self.log

        DispatchQueue(label: "Queue for processing the UIImagePickerController result").async { [weak self] in
            
            defer {
                DispatchQueue.main.async {
                    self?.delegate?.hideHUD()
                }
            }

            // Fow now, we only authorize images and videos
            
            guard let chosenMediaType = info[.mediaType] as? String else { return }
            guard ([kUTTypeImage, kUTTypeMovie] as [String]).contains(chosenMediaType) else { return }
            
            let pickerURL: URL?
            if let imageURL = info[.imageURL] as? URL {
                pickerURL = imageURL
            } else if let mediaURL = info[.mediaURL] as? URL {
                pickerURL = mediaURL
            } else {
                // This should only happen when shooting a photo
                pickerURL = nil
            }
            
            if let url = pickerURL {
                // Copy the file to a temporary location. This does not seems to be required the pickerURL comes from an info[.imageURL], but this seems to be required when it comes from a info[.mediaURL]. Nevertheless, we do it for both, since the filename provided by the picker is terrible in both cases.
                let fileExtension = url.pathExtension.lowercased()
                let filename = ["Media @ \(dateFormatter.string(from: Date()))", fileExtension].joined(separator: ".")
                let localURL = ObvMessengerConstants.containerURL.forTempFiles.appendingPathComponent(filename)
                do {
                    try FileManager.default.copyItem(at: url, to: localURL)
                } catch {
                    os_log("Could not copy file provided by the Photo picker to a local URL: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    return
                }
                assert(!localURL.path.contains("PluginKitPlugin")) // This is a particular case, but we know the loading won't work in that case
                DispatchQueue.main.async {
                    self?.addAttachment(atURL: localURL)
                }
            } else if let originalImage = info[.originalImage] as? UIImage {
                let uti = String(kUTTypeJPEG)
                guard let fileExtention = ObvUTIUtils.preferredTagWithClass(inUTI: uti, inTagClass: .FilenameExtension) else { return }
                let name = "Photo @ \(dateFormatter.string(from: Date()))"
                let tempFileName = [name, fileExtention].joined(separator: ".")
                let url = ObvMessengerConstants.containerURL.forTempFiles.appendingPathComponent(tempFileName)
                guard let pickedImageJpegData = originalImage.jpegData(compressionQuality: 1.0) else { return }
                do {
                    try pickedImageJpegData.write(to: url)
                } catch let error {
                    os_log("Could not save file to temp location: %@", log: log, type: .error, error.localizedDescription)
                    return
                }
                DispatchQueue.main.async {
                    self?.addAttachment(atURL: url)
                }
            } else {
                assertionFailure()
            }
            
        }
        
    }
    
}


// MARK: - VNDocumentCameraViewControllerDelegate


extension ComposeMessageViewDocumentPickerAdapterWithDraft: VNDocumentCameraViewControllerDelegate {
    
    
    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {

        controller.dismiss(animated: true)
        
        guard scan.pageCount > 0 else { return }
        
        self.delegate?.showHUD(type: .spinner)

        let dateFormatter = self.dateFormatter
        
        DispatchQueue(label: "Queue for creating a pdf from scanned document").async {
            
            let pdfDocument = PDFDocument()
            for pageNumber in 0..<scan.pageCount {
                let image = scan.imageOfPage(at: pageNumber)
                guard let pdfPage = PDFPage(image: image) else { return }
                pdfDocument.insert(pdfPage, at: pageNumber)
            }
            
            // Write the pdf to a temporary location
            let name = "Scan @ \(dateFormatter.string(from: Date()))"
            let tempFileName = [name, String(kUTTypePDF)].joined(separator: ".")
            let url = ObvMessengerConstants.containerURL.forTempFiles.appendingPathComponent(tempFileName)
            guard pdfDocument.write(to: url) else { return }

            DispatchQueue.main.async { [weak self] in
                self?.delegate?.hideHUD()
                self?.addAttachment(atURL: url)
            }
            
        }
        
    }

    
    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
    }

    
    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        controller.dismiss(animated: true)
    }

    
}
