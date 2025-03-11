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

import UIKit
import PhotosUI

class ViewController: UIViewController, PHPickerViewControllerDelegate, ObvImageEditorViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    @IBAction func libraryButtonTapped(_ sender: Any) {

        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 1
        let phPickerViewController = PHPickerViewController(configuration: configuration)
        phPickerViewController.delegate = self

        present(phPickerViewController, animated: true)
        
    }

    
    @IBAction func cameraButtonTapped(_ sender: Any) {
        
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.allowsEditing = false
        picker.sourceType = .camera
        picker.cameraDevice = .front

        present(picker, animated: true)

    }
    
    
    // MARK: - PHPickerViewControllerDelegate
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        
        picker.dismiss(animated: true) {
            
            guard let itemProvider = results.first?.itemProvider else { return }
            
            let canLoadImage = itemProvider.canLoadObject(ofClass: UIImage.self)
            guard canLoadImage else { return }
            
            itemProvider.loadObject(ofClass: UIImage.self) { item, error in
                if let error {
                    assertionFailure(error.localizedDescription)
                    return
                }
                guard let uiImage = item as? UIImage else { return }
                
                Task { [weak self] in
                    await self?.presentObvImageEditor(for: uiImage)
                }
                
            }
            
        }
        
    }
    
    
    // MARK: - UIImagePickerControllerDelegate
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        assert(Thread.isMainThread)
        picker.dismiss(animated: true) {
            guard let image = info[.originalImage] as? UIImage else { return }
            Task { [weak self] in
                await self?.presentObvImageEditor(for: image)
            }
        }
    }
    
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        assert(Thread.isMainThread)
        picker.dismiss(animated: true)
    }

    
    
    @MainActor
    func presentObvImageEditor(for image: UIImage) async {
    
        let imageEditorViewController = ObvImageEditorViewController(originalImage: image, showZoomButtons: true, maxReturnedImageSize: (1024, 1024), delegate: self)
        present(imageEditorViewController, animated: true)
        
    }
    
    
    func userCancelledImageEdition(_ imageEditor: ObvImageEditorViewController) async {
        imageEditor.dismiss(animated: true)
    }
    
    func userConfirmedImageEdition(_ imageEditor: ObvImageEditorViewController, image: UIImage) async {
        presentedViewController?.dismiss(animated: true)
        imageEditor.dismiss(animated: true) { [weak self] in
            self?.presentImage(image: image)
        }
    }
    
    func presentImage(image: UIImage) {
        let vc = SimpleImageViewerViewController(image: image)
        present(vc, animated: true)
    }

}
