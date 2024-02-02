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

import SwiftUI
import UI_ObvImageEditor

struct CircledCameraButtonView: View {
    
    enum ActiveSheet: Identifiable {
        case libraryPicker
        case cameraPicker
        case editor
        var id: Int { hashValue }
    }

    struct ProfilePictureAction {
        let title: String
        let handler: () -> Void

        var toAction: UIAction {
            UIAction(title: title) { _ in handler() }
        }
    }

    @Binding var profilePicture: UIImage?
    
    @State private var activeSheet: ActiveSheet?
    @State private var pictureState: UIImage? = nil
    @State private var isSheetPresented: Bool = false
    @State private var isFileImporterPresented: Bool = false
    @State private var profilePictureMenuIsPresented: Bool = false

    private func userTappedMenuButtonForPhotoLibrary() {
        self.activeSheet = .libraryPicker
        self.isSheetPresented = true
        self.isFileImporterPresented = false
    }

    
    private func userTappedMenuButtonForFilesApp() {
        self.activeSheet = nil
        self.isSheetPresented = false
        self.isFileImporterPresented = true
    }
    
    private func userTappedMenuButtonForCamera() {
        self.activeSheet = .cameraPicker
        self.isSheetPresented = true
        self.isFileImporterPresented = false
    }
    
    
    private func userTappedMenuButtonForRemovingPicture() {
        self.profilePicture = nil
        self.isSheetPresented = false
        self.isFileImporterPresented = false
    }
    
    
    /// Called when the file importer is dismissed.
    @MainActor
    private func processFileImporterResult(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            assert(urls.count == 1)
            guard let url = urls.first else { return }
            let gotAccess = url.startAccessingSecurityScopedResource()
            guard gotAccess else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let image = UIImage(contentsOfFile: url.path) else { return }
            withAnimation {
                self.pictureState = image
                self.activeSheet = .editor
                self.isSheetPresented = true
            }
        case .failure(let failure):
            assertionFailure(failure.localizedDescription)
        }
    }
    
    
    /// Called when the user taps the accept or reject button of the image editor. If the user accepted the edited image, this edited image is passed as a parameter.
    @MainActor
    private func userAcceptedOrRejectedEditedImage(_ editedImage: UIImage?) async {
        withAnimation {
            self.activeSheet = nil
            self.isSheetPresented = false
            if let editedImage {
                self.profilePicture = editedImage
            }
        }
    }
    
    var body: some View {
        
        Menu {
            Button(action: userTappedMenuButtonForPhotoLibrary) {
                Label("PHOTO_LIBRARY", systemIcon: .photoOnRectangleAngled)
            }
            Button(action: userTappedMenuButtonForFilesApp) {
                Label("FILES_APP", systemIcon: .doc)
            }
            if UIImagePickerController.isCameraDeviceAvailable(.front) {
                Button(action: userTappedMenuButtonForCamera) {
                    Label("TAKE_PICTURE", systemIcon: .camera(.none))
                }
            }
            Button(action: userTappedMenuButtonForRemovingPicture) {
                Label("REMOVE_PICTURE", systemIcon: .trash)
            }
        } label: {
            CircledCameraView()
                .frame(width: 44, height: 44)
        }
        .sheet(isPresented: $isSheetPresented) {
            switch activeSheet {
            case .libraryPicker:
                ImagePicker(image: $pictureState, useCamera: false) {
                    withAnimation {
                        activeSheet = .editor
                    }
                }
                .ignoresSafeArea()
            case .cameraPicker:
                ImagePicker(image: $pictureState, useCamera: true) {
                    withAnimation {
                        activeSheet = .editor
                    }
                }
                .ignoresSafeArea()
            case .editor:
                if let pictureState {
                    ObvImageEditorViewControllerRepresentable(
                        originalImage: pictureState,
                        showZoomButtons: false,
                        maxReturnedImageSize: (1080, 1080))
                    { editedImage in
                        Task { await userAcceptedOrRejectedEditedImage(editedImage) }
                    }
                    .ignoresSafeArea()
                }
            case nil:
                EmptyView()
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.jpeg],
            allowsMultipleSelection: false) { result in
                Task { await processFileImporterResult(result) }
            }
    }
    
}


struct CircledCameraButtonView_Previews: PreviewProvider {
    static var previews: some View {
        CircledCameraButtonView(profilePicture: Binding<UIImage?>.constant(nil))
    }
}
