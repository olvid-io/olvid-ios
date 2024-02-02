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

import SwiftUI
import UIKit
import ObvTypes
import PhotosUI
import UI_ObvImageEditor


protocol EditNicknameAndCustomPictureViewControllerDelegate: AnyObject {
    func userWantsToSaveNicknameAndCustomPicture(controller: EditNicknameAndCustomPictureViewController, identifier: EditNicknameAndCustomPictureView.Model.IdentifierKind, nickname: String, customPhoto: UIImage?) async
    func userWantsToDismissEditNicknameAndCustomPictureViewController(controller: EditNicknameAndCustomPictureViewController) async
}



/// This view controller is used in the single contact a single group v2 and allows the user to edit the nickname and custom photo of the contact or the group.
final class EditNicknameAndCustomPictureViewController: UIHostingController<EditNicknameAndCustomPictureView>, EditNicknameAndCustomPictureViewActionsProtocol, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, ObvImageEditorViewControllerDelegate {

    
    private weak var delegate: EditNicknameAndCustomPictureViewControllerDelegate?
    
    
    init(model: EditNicknameAndCustomPictureView.Model, delegate: EditNicknameAndCustomPictureViewControllerDelegate) {
        let actions = EditNicknameAndCustomPictureViewActions()
        let view = EditNicknameAndCustomPictureView(actions: actions, model: model)
        super.init(rootView: view)
        self.delegate = delegate
        actions.delegate = self
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    // EditNicknameAndCustomPictureViewActionsProtocol
    
    private var continuationForPicker: CheckedContinuation<UIImage?, Never>?


    func userWantsToSaveNicknameAndCustomPicture(identifier: EditNicknameAndCustomPictureView.Model.IdentifierKind, nickname: String, customPhoto: UIImage?) async {
        await delegate?.userWantsToSaveNicknameAndCustomPicture(controller: self, identifier: identifier, nickname: nickname, customPhoto: customPhoto)
    }

    
    func userWantsToDismissEditNicknameAndCustomPictureView() async {
        await delegate?.userWantsToDismissEditNicknameAndCustomPictureViewController(controller: self)
    }

    
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


private final class EditNicknameAndCustomPictureViewActions: EditNicknameAndCustomPictureViewActionsProtocol {
        
    weak var delegate: EditNicknameAndCustomPictureViewActionsProtocol?
    
    func userWantsToTakePhoto() async -> UIImage? {
        return await delegate?.userWantsToTakePhoto()
    }
    
    func userWantsToChoosePhoto() async -> UIImage? {
        return await delegate?.userWantsToChoosePhoto()
    }
    
    func userWantsToSaveNicknameAndCustomPicture(identifier: EditNicknameAndCustomPictureView.Model.IdentifierKind, nickname: String, customPhoto: UIImage?) async {
        await delegate?.userWantsToSaveNicknameAndCustomPicture(identifier: identifier, nickname: nickname, customPhoto: customPhoto)
    }
    
    func userWantsToDismissEditNicknameAndCustomPictureView() async {
        await delegate?.userWantsToDismissEditNicknameAndCustomPictureView()
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
