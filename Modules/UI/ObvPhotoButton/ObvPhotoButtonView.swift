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
import UI_ObvCircledInitials
import UI_SystemIcon_SwiftUI


public protocol ObvPhotoButtonViewActionsProtocol {
    func userWantsToAddProfilPictureWithCamera()
    func userWantsToAddProfilPictureWithPhotoLibrary()
    func userWantsToRemoveProfilePicture()
}


public protocol ObvPhotoButtonViewModelProtocol: InitialCircleViewNewModelProtocol {

    var photoThatCannotBeRemoved: UIImage? { get }
    
}


/// View used during onboarding when editing the unmanaged details of an owned identity. Also used when editing the custom photo of a contact.
public struct ObvPhotoButtonView<Model: ObvPhotoButtonViewModelProtocol>: View {

    private let actions: ObvPhotoButtonViewActionsProtocol
    @ObservedObject private var model: Model
    @State private var isPopoverPresented = false
    private let circleDiameter: CGFloat = 128

    public init(actions: ObvPhotoButtonViewActionsProtocol, model: Model) {
        self.actions = actions
        self.model = model
    }
    
    private func buttonTapped() {
        isPopoverPresented = true
    }
    
    public var body: some View {
        InitialCircleViewNew(model: model, state: .init(circleDiameter: circleDiameter))
            .frame(width: circleDiameter, height: circleDiameter)
            .overlay(alignment: .init(horizontal: .trailing, vertical: .bottom)) {
                Menu {
                    if UIImagePickerController.isCameraDeviceAvailable(.front) {
                        Button(action: actions.userWantsToAddProfilPictureWithCamera, label: {
                            Label("ONBOARDING_PROFILE_PICTURE_CHOOSER_BUTTON_TITLE_TAKE_PICTURE", systemIcon: .camera(.none))
                        })
                    }
                    Button(action: actions.userWantsToAddProfilPictureWithPhotoLibrary, label: {
                        Label("ONBOARDING_PROFILE_PICTURE_CHOOSER_BUTTON_TITLE_CHOOSE_PICTURE", systemIcon: .photo)
                    })
                    if model.circledInitialsConfiguration.photo != nil && model.circledInitialsConfiguration.photo != model.photoThatCannotBeRemoved {
                        Button(action: actions.userWantsToRemoveProfilePicture, label: {
                            Label("ONBOARDING_PROFILE_PICTURE_CHOOSER_BUTTON_TITLE_REMOVE_PICTURE", systemIcon: .trash)
                        })
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(.background)
                            .frame(width: circleDiameter/4+10, height: circleDiameter/4+10)
                        Circle()
                            .fill(.white)
                            .frame(width: circleDiameter/4-1, height: circleDiameter/4-1)
                        Image(systemIcon: .camera(.circleFill))
                            .font(.system(size: circleDiameter/4))
                            .foregroundStyle(Color("Blue01"))
                            .offset(x: 0, y: 0)
                    }
                }

            }
    }
    
}
