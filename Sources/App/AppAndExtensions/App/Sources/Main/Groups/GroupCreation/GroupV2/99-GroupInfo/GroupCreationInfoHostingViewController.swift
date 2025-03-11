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
import SwiftUI
import OSLog
import ObvTypes
import ObvUICoreData
import ObvUIObvCircledInitials
import ObvImageEditor
import PhotosUI
import Combine


protocol GroupCreationInfoHostingViewControllerDelegate: AnyObject {
    func userDidChooseGroupInfos(in controller: GroupCreationInfoHostingViewController, name: String?, description: String?, photo: UIImage?) async
    @MainActor func userWantsToCancelGroupCreationFlow(in controller: GroupCreationInfoHostingViewController)
}


final class GroupCreationInfoHostingViewController: UIHostingController<GroupInfoView<GroupInfoViewModel>>, GroupInfoViewViewActions, ObvImageEditorViewControllerDelegate, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    private weak var delegate: GroupCreationInfoHostingViewControllerDelegate?

    init(model: GroupInfoViewModel, delegate: GroupCreationInfoHostingViewControllerDelegate) {
        let actions = Actions()
        let view = GroupInfoView(model: model, actions: actions)
        super.init(rootView: view)
        self.delegate = delegate
        actions.delegate = self
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemGroupedBackground
        
        self.navigationItem.rightBarButtonItem = .init(systemItem: .cancel, primaryAction: .init(handler: { [weak self] _ in
            guard let self else { return }
            delegate?.userWantsToCancelGroupCreationFlow(in: self)
        }))

    }
    
    // GroupInfoViewViewActions
    
    func userDidChooseGroupInfos(name: String?, description: String?, photo: UIImage?) async {
        await delegate?.userDidChooseGroupInfos(in: self, name: name, description: description, photo: photo)
    }
    
    
    private var continuationForPicker: CheckedContinuation<UIImage?, Never>?

    
    @MainActor
    func userWantsToTakePhoto() async -> UIImage? {
        
        removeAnyPreviousContinuation()
        
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return nil }
        
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.allowsEditing = false
        picker.sourceType = .camera
        picker.cameraDevice = .front

        let imageFromPicker = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            self.continuationForPicker = continuation
            present(picker, animated: true)
        }

        guard let imageFromPicker else { return nil }
        
        let resizedImage = await resizeImageFromPicker(imageFromPicker: imageFromPicker)
        
        return resizedImage

    }

    @MainActor
    func userWantsToChoosePhoto() async -> UIImage? {
        
        removeAnyPreviousContinuation()
        
        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else { return nil }

        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 1
        configuration.filter = .images
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        
        let imageFromPicker = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            self.continuationForPicker = continuation
            present(picker, animated: true)
        }
        
        guard let imageFromPicker else { return nil }
        
        let resizedImage = await resizeImageFromPicker(imageFromPicker: imageFromPicker)
        
        return resizedImage
        
    }
    
    
    private var continuationForDocumentPicker: CheckedContinuation<UIImage?, Never>?

    @MainActor
    func userWantsToChoosePhotoWithDocumentPicker() async -> UIImage? {
        
        removeAnyPreviousContinuation()

        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.jpeg, .png], asCopy: true)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        documentPicker.shouldShowFileExtensions = false

        let imageFromPicker = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            self.continuationForDocumentPicker = continuation
            present(documentPicker, animated: true)
        }

        guard let imageFromPicker else { return nil }

        let resizedImage = await resizeImageFromPicker(imageFromPicker: imageFromPicker)
        
        return resizedImage

    }

    
    private func removeAnyPreviousContinuation() {
        if let continuationForPicker {
            continuationForPicker.resume(returning: nil)
            self.continuationForPicker = nil
        }
    }

    
    // PHPickerViewControllerDelegate
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let continuationForPicker else { assertionFailure(); return }
        self.continuationForPicker = nil
        if results.count == 1, let result = results.first {
            result.itemProvider.loadObject(ofClass: UIImage.self) { item, error in
                guard error == nil else {
                    continuationForPicker.resume(returning: nil)
                    return
                }
                guard let image = item as? UIImage else {
                    continuationForPicker.resume(returning: nil)
                    return
                }
                continuationForPicker.resume(returning: image)
            }
        } else {
            continuationForPicker.resume(with: .success(nil))
        }
    }

    
    // UIImagePickerControllerDelegate
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        assert(Thread.isMainThread)
        picker.dismiss(animated: true)
        guard let continuationForPicker else { assertionFailure(); return }
        self.continuationForPicker = nil
        let image = info[.originalImage] as? UIImage
        continuationForPicker.resume(returning: image)
    }
    
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        assert(Thread.isMainThread)
        picker.dismiss(animated: true)
        guard let continuationForPicker else { assertionFailure(); return }
        self.continuationForPicker = nil
        continuationForPicker.resume(returning: nil)
    }
    
    
    // ObvImageEditorViewControllerDelegate
    
    func userCancelledImageEdition(_ imageEditor: ObvImageEditorViewController) async {
        imageEditor.dismiss(animated: true)
        guard let continuationForPicker else { assertionFailure(); return }
        self.continuationForPicker = nil
        continuationForPicker.resume(returning: nil)
    }
    
    func userConfirmedImageEdition(_ imageEditor: ObvImageEditorViewController, image: UIImage) async {
        imageEditor.dismiss(animated: true)
        guard let continuationForPicker else { assertionFailure(); return }
        self.continuationForPicker = nil
        continuationForPicker.resume(returning: image)
    }


    // Resizing the photos received from the camera or the photo library
    
    private func resizeImageFromPicker(imageFromPicker: UIImage) async -> UIImage? {
        
        let imageEditor = ObvImageEditorViewController(originalImage: imageFromPicker,
                                                       showZoomButtons: Utils.targetEnvironmentIsMacCatalyst,
                                                       maxReturnedImageSize: (1024, 1024),
                                                       delegate: self)
        
        removeAnyPreviousContinuation()

        let resizedImage = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
            self.continuationForPicker = continuation
            present(imageEditor, animated: true)
        }
        
        return resizedImage

    }

    
    
}

// MARK: UIDocumentPickerDelegate

extension GroupCreationInfoHostingViewController: UIDocumentPickerDelegate {
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        
        controller.dismiss(animated: true)
        guard let continuationForDocumentPicker else { assertionFailure(); return }
        self.continuationForDocumentPicker = nil
        guard let url = urls.first else { return continuationForDocumentPicker.resume(returning: nil) }

        let needToCallStopAccessingSecurityScopedResource = url.startAccessingSecurityScopedResource()
                
        let image = UIImage(contentsOfFile: url.path)

        if needToCallStopAccessingSecurityScopedResource {
            url.stopAccessingSecurityScopedResource()
        }

        return continuationForDocumentPicker.resume(returning: image)

    }
    
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        
        controller.dismiss(animated: true)
        guard let continuationForDocumentPicker else { return }
        self.continuationForDocumentPicker = nil
        continuationForDocumentPicker.resume(returning: nil)
        
    }
    
}



fileprivate final class Actions: GroupInfoViewViewActions {
        
    weak var delegate: GroupInfoViewViewActions?
    
    func userDidChooseGroupInfos(name: String?, description: String?, photo: UIImage?) async {
        await delegate?.userDidChooseGroupInfos(name: name, description: description, photo: photo)
    }
    
    func userWantsToTakePhoto() async -> UIImage? {
        await delegate?.userWantsToTakePhoto()
    }
    
    func userWantsToChoosePhoto() async -> UIImage? {
        await delegate?.userWantsToChoosePhoto()
    }
    
    func userWantsToChoosePhotoWithDocumentPicker() async -> UIImage? {
        return await delegate?.userWantsToChoosePhotoWithDocumentPicker()
    }

}


// MARK: - GroupInfoViewModel
@MainActor
final class GroupInfoViewModel: GroupInfoViewModelProtocol {
            
    @Published var circledInitialsConfiguration: CircledInitialsConfiguration
    var photoThatCannotBeRemoved: UIImage? { nil }
    let selectedUsersOrdered: [PersistedUser] // Group members
    let canEditContacts = false
    let initialName: String?
    let initialDescription: String?
    let editOrCreate: GroupInfoViewEditOrCreate

    init(selectedUsersOrdered: [PersistedUser], initialName: String?, initialDescription: String?, initialCircledInitialsConfiguration: CircledInitialsConfiguration?, editOrCreate: GroupInfoViewEditOrCreate) {
        self.selectedUsersOrdered = selectedUsersOrdered
        self.circledInitialsConfiguration = initialCircledInitialsConfiguration ?? .icon(.person3Fill)
        self.initialName = initialName
        self.initialDescription = initialDescription
        self.editOrCreate = editOrCreate
    }

    @MainActor
    func updatePhoto(with photo: UIImage?) async {
        if let photo {
            self.circledInitialsConfiguration = .photo(photo: .image(image: photo))
        } else {
            self.circledInitialsConfiguration = .icon(.person)
        }
    }
    
}


// MARK: Utils

fileprivate struct Utils {
    
    static var targetEnvironmentIsMacCatalyst: Bool {
      #if targetEnvironment(macCatalyst)
        return true
      #else
        return false
      #endif
    }
    
}
