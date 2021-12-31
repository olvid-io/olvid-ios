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

@available(iOS 13.0, *)
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
    
    @State private var activeSheet: ActiveSheet? = nil
    @State private var sheetIsPresented: Bool = false // Only for iOS13
    @State private var pictureState: UIImage? = nil
    @State private var profilePictureMenuIsPresented: Bool = false

    var profilePictureEditionActionsSheet: [ActionSheet.Button] {
        var result: [ActionSheet.Button] = []
        for action in buildCameraButtonActions() {
            result += [Alert.Button.default(Text(action.title), action: action.handler)]
        }
        result.append(Alert.Button.cancel({ profilePictureMenuIsPresented = false }))
        return result
    }

    private func buildCameraButtonActions() -> [ProfilePictureAction] {
        var actions: [ProfilePictureAction] = []
        actions += [ProfilePictureAction(title: NSLocalizedString("CHOOSE_PICTURE", comment: "")) {
            self.activeSheet = .libraryPicker
            if #available(iOS 14.0, *) {

            } else {
                self.sheetIsPresented = true
            }
        }]
        if UIImagePickerController.isCameraDeviceAvailable(.front) {
            actions += [ProfilePictureAction(title: NSLocalizedString("TAKE_PICTURE", comment: "")) {
                self.activeSheet = .cameraPicker
                if #available(iOS 14.0, *) {

                } else {
                    self.sheetIsPresented = true
                }
            }]
        }
        actions += [ProfilePictureAction(title: NSLocalizedString("REMOVE_PICTURE", comment: "")) {
            self.profilePicture = nil
        }]
        return actions
    }
    
    var body: some View {
        if #available(iOS 14.0, *) {
            iOS14Body
        } else {
            iOS13Body
        }
    }
    
    @available(iOS 14, *)
    private var iOS14Body: some View {
        UIButtonWrapper(title: nil, actions: buildCameraButtonActions().map { $0.toAction }) {
            CircledCameraView()
        }
        .frame(width: 44, height: 44)
        .sheet(item: $activeSheet) { item in
            switch item {
            case .cameraPicker:
                ImagePicker(image: $pictureState, useCamera: true) {
                    activeSheet = .editor
                }
            case .libraryPicker:
                ImagePicker(image: $pictureState, useCamera: false) {
                    activeSheet = .editor
                }
            case .editor:
                ImageEditor(image: $pictureState) {
                    activeSheet = nil
                    if let image = pictureState {
                        withAnimation {
                            self.profilePicture = image
                        }
                    }
                }
            }
        }
    }
    
    
    private var iOS13Body: some View {
        Button(action: { profilePictureMenuIsPresented.toggle() }) {
            CircledCameraView()
        }
        .frame(width: 44, height: 44)
        .actionSheet(isPresented: $profilePictureMenuIsPresented, content: {
            ActionSheet(title: Text("PROFILE_PICTURE"), message: nil, buttons: profilePictureEditionActionsSheet)
        })
        .sheet(isPresented: $sheetIsPresented, onDismiss: {
            if activeSheet != nil && !sheetIsPresented {
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(700)) {
                    sheetIsPresented = true
                }
            }
        }, content: {
            if let item = activeSheet {
                switch item {
                case .cameraPicker:
                    ImagePicker(image: $pictureState, useCamera: true) {
                        activeSheet = .editor
                        sheetIsPresented = false
                    }
                case .libraryPicker:
                    ImagePicker(image: $pictureState, useCamera: false) {
                        activeSheet = .editor
                        sheetIsPresented = false
                    }
                case .editor:
                    ImageEditor(image: $pictureState) {
                        activeSheet = nil
                        sheetIsPresented = false
                        if let image = pictureState {
                            withAnimation {
                                self.profilePicture = image
                            }
                        }
                    }
                }
            }
        })
    }
    
}


@available(iOS 13.0, *)
struct CircledCameraButtonView_Previews: PreviewProvider {
    static var previews: some View {
        CircledCameraButtonView(profilePicture: Binding<UIImage?>.constant(nil))
    }
}
