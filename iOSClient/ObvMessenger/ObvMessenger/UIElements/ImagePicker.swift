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

import SwiftUI
import PhotosUI

@available(iOS 13.0, *)
class ImagePickerCoordinator: NSObject, UINavigationControllerDelegate {
    let parent: ImagePicker

    init(_ parent: ImagePicker) {
        self.parent = parent
    }

}

@available(iOS 13.0, *)
extension ImagePickerCoordinator: UIImagePickerControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        if let image = info[.originalImage] as? UIImage {
            DispatchQueue.main.async { [weak self] in
                self?.parent.image = image
                self?.parent.completionHandler?()
            }
        }
    }
}

@available(iOS 14.0, *)
extension ImagePickerCoordinator: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard results.count == 1 else {
            picker.dismiss(animated: true)
            return
        }
        let itemProvider = results[0].itemProvider
        itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
            guard error == nil else { return }
            guard let image = object as? UIImage else { return }
            self?.parent.image = image
            self?.parent.completionHandler?()
        }
    }
}

@available(iOS 13.0, *)
struct ImagePicker: UIViewControllerRepresentable {

    @Binding var image: UIImage?

    var useCamera: Bool
    var completionHandler: (() -> Void)?

    func makeCoordinator() -> ImagePickerCoordinator {
        ImagePickerCoordinator(self)
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> UIViewController {
        if !useCamera, #available(iOS 14.0, *) {
            var configuration = PHPickerConfiguration()
            configuration.selectionLimit = 1
            configuration.filter = .images
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = context.coordinator
            return picker
        } else {
            let picker = UIImagePickerController()
            picker.delegate = context.coordinator
            picker.allowsEditing = false
            if useCamera {
                picker.sourceType = .camera
                picker.cameraDevice = .front
            }
            return picker
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: UIViewControllerRepresentableContext<ImagePicker>) {

    }
}
