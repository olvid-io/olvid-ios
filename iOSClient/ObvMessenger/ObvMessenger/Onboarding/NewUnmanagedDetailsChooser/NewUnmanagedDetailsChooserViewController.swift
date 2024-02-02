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
import SwiftUI
import PhotosUI
import ObvTypes
import UI_ObvCircledInitials
import UI_ObvImageEditor


protocol NewUnmanagedDetailsChooserViewControllerDelegate: AnyObject {
    func userWantsToCloseOnboarding(controller: NewUnmanagedDetailsChooserViewController) async
    func userDidChooseUnmanagedDetails(controller: NewUnmanagedDetailsChooserViewController, ownedIdentityCoreDetails: ObvIdentityCoreDetails, photo: UIImage?) async
    func userIndicatedHerProfileIsManagedByOrganisation(controller: NewUnmanagedDetailsChooserViewController) async
}


final class NewUnmanagedDetailsChooserViewController: UIHostingController<NewUnmanagedDetailsChooserView<NewUnmanagedDetailsChooserViewModel>>, NewUnmanagedDetailsChooserViewActions, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, ObvImageEditorViewControllerDelegate {
    
    weak var delegate: NewUnmanagedDetailsChooserViewControllerDelegate?
    
    private let showCloseButton: Bool

    init(model: NewUnmanagedDetailsChooserViewModel, delegate: NewUnmanagedDetailsChooserViewControllerDelegate, showCloseButton: Bool) {
        self.showCloseButton = showCloseButton
        let actions = Actions()
        let view = NewUnmanagedDetailsChooserView(model: model, actions: actions)
        super.init(rootView: view)
        self.delegate = delegate
        actions.delegate = self
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation(animated: false)
    }

    
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        configureNavigation(animated: animated)
    }

    
    private func configureNavigation(animated: Bool) {
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.setNavigationBarHidden(false, animated: animated)
        if showCloseButton {
            let handler: UIActionHandler = { [weak self] _ in self?.closeAction() }
            let closeButton = UIBarButtonItem(systemItem: .close, primaryAction: .init(handler: handler))
            navigationItem.rightBarButtonItem = closeButton
        }
    }
    
    
    private func closeAction() {
        Task { [weak self] in
            guard let self else { return }
            await delegate?.userWantsToCloseOnboarding(controller: self)
        }
    }

    
    // NewUnmanagedDetailsChooserViewActions
    
    func userDidChooseUnmanagedDetails(ownedIdentityCoreDetails: ObvTypes.ObvIdentityCoreDetails, photo: UIImage?) {
        Task(priority: .userInitiated) {
            await delegate?.userDidChooseUnmanagedDetails(controller: self, ownedIdentityCoreDetails: ownedIdentityCoreDetails, photo: photo)
        }
    }
    
    func userIndicatedHerProfileIsManagedByOrganisation() {
        Task {
            await delegate?.userIndicatedHerProfileIsManagedByOrganisation(controller: self)
        }
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




fileprivate final class Actions: NewUnmanagedDetailsChooserViewActions {
        
    weak var delegate: NewUnmanagedDetailsChooserViewActions?
    
    func userDidChooseUnmanagedDetails(ownedIdentityCoreDetails: ObvTypes.ObvIdentityCoreDetails, photo: UIImage?) {
        delegate?.userDidChooseUnmanagedDetails(ownedIdentityCoreDetails: ownedIdentityCoreDetails, photo: photo)
    }
    
    func userIndicatedHerProfileIsManagedByOrganisation() {
        delegate?.userIndicatedHerProfileIsManagedByOrganisation()
    }

    func userWantsToTakePhoto() async -> UIImage? {
        await delegate?.userWantsToTakePhoto()
    }

    func userWantsToChoosePhoto() async -> UIImage? {
        await delegate?.userWantsToChoosePhoto()
    }

}


// MARK: - NewUnmanagedDetailsChooserViewModel

final class NewUnmanagedDetailsChooserViewModel: NewUnmanagedDetailsChooserViewModelProtocol {
        
    @Published var circledInitialsConfiguration: CircledInitialsConfiguration
    let showPositionAndOrganisation: Bool
    var photoThatCannotBeRemoved: UIImage? { nil }

    init(showPositionAndOrganisation: Bool) {
        self.showPositionAndOrganisation = showPositionAndOrganisation
        self.circledInitialsConfiguration = .icon(.person)
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
