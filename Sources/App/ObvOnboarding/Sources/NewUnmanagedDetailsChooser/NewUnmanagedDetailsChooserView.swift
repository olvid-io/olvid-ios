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

import SwiftUI
import ObvTypes
import ObvUIObvCircledInitials
import ObvUIObvPhotoButton


protocol NewUnmanagedDetailsChooserViewModelProtocol: ObservableObject, ObvPhotoButtonViewModelProtocol {
    // The circledInitialsConfiguration is part of InitialCircleViewNewModelProtocol
    func updatePhoto(with photo: UIImage?) async
    var showPositionAndOrganisation: Bool { get }
}


protocol NewUnmanagedDetailsChooserViewActions: AnyObject {
    func userDidChooseUnmanagedDetails(ownedIdentityCoreDetails: ObvIdentityCoreDetails, photo: UIImage?)
    func userIndicatedHerProfileIsManagedByOrganisation()
    // The following two methods leverages the view controller to show
    // the appropriate UI allowing the user to create her profile picture.
    func userWantsToTakePhoto() async -> UIImage?
    func userWantsToChoosePhoto() async -> UIImage?
    func userWantsToChoosePhotoWithDocumentPicker() async -> UIImage?
}


struct NewUnmanagedDetailsChooserView<Model: NewUnmanagedDetailsChooserViewModelProtocol>: View, ObvPhotoButtonViewActionsProtocol {
    
    @ObservedObject var model: Model
    let actions: NewUnmanagedDetailsChooserViewActions
    
    @State private var firstname = ""
    @State private var lastname = ""
    @State private var position = ""
    @State private var company = ""
    @State private var isButtonDisabled = true
    @State private var isInterfaceDisabled = false
    @State private var photoAlertToShow: PhotoAlertType?
    
    private enum PhotoAlertType {
        case camera
        case photoLibrary
    }
    
    private func resetIsButtonDisabled() {
        isButtonDisabled = firstname.trimmingWhitespacesAndNewlines().isEmpty && lastname.trimmingWhitespacesAndNewlines().isEmpty
    }
    
    private var coreDetails: ObvIdentityCoreDetails? {
        return try? .init(
            firstName: firstname,
            lastName: lastname,
            company: company,
            position: position,
            signedUserDetails: nil)
    }
    
    
    private func createProfileButtonTapped() {
        guard let coreDetails else { return }
        withAnimation {
            isInterfaceDisabled = true
        }
        actions.userDidChooseUnmanagedDetails(ownedIdentityCoreDetails: coreDetails, photo: model.circledInitialsConfiguration.photo)
    }
    
    // PhotoButtonViewActionsProtocol
    
    func userWantsToAddProfilPictureWithCamera() {
        Task {
            guard let image = await actions.userWantsToTakePhoto() else { return }
            await model.updatePhoto(with: image)
        }
    }
    
    
    func userWantsToAddProfilPictureWithPhotoLibrary() {
        Task {
            guard let image = await actions.userWantsToChoosePhoto() else { return }
            await model.updatePhoto(with: image)
        }
    }

    
    func userWantsToAddProfilePictureWithDocumentPicker() {
        Task {
            guard let image = await actions.userWantsToChoosePhotoWithDocumentPicker() else { return }
            await model.updatePhoto(with: image)
        }
    }
    
    func userWantsToRemoveProfilePicture() {
        Task {
            await model.updatePhoto(with: nil)
        }
    }
    
    
    var body: some View {
        ScrollView {
            VStack {
                
                NewOnboardingHeaderView(title: "ONBOARDING_NAME_CHOOSER_TITLE", subtitle: "LETS_CREATE_YOUR_PROFILE")
                    .padding(.bottom, 20)

                ObvPhotoButtonView(actions: self, model: model)
                    .padding(.bottom, 10)

                InternalTextField("ONBOARDING_NAME_CHOOSER_TEXTFIELD_FIRSTNAME", text: $firstname)
                    .onChange(of: firstname) { _ in resetIsButtonDisabled() }
                    .padding(.bottom, 10)
                InternalTextField("ONBOARDING_NAME_CHOOSER_TEXTFIELD_LASTNAME", text: $lastname)
                    .onChange(of: lastname) { _ in resetIsButtonDisabled() }
                    .padding(.bottom, 10)
                if model.showPositionAndOrganisation {
                    InternalTextField("ONBOARDING_NAME_CHOOSER_TEXTFIELD_POSITION", text: $position)
                        .padding(.bottom, 10)
                    InternalTextField("ONBOARDING_NAME_CHOOSER_TEXTFIELD_COMPANY", text: $company)
                        .padding(.bottom, 10)
                }
                
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }.opacity(isInterfaceDisabled ? 1.0 : 0.0)
                
                HStack {
                    Text("ONBOARDING_NAME_CHOOSER_MANAGED_PROFILE_LABEL")
                        .foregroundStyle(.secondary)
                    Button("ONBOARDING_NAME_CHOOSER_MANAGED_PROFILE_BUTTON_TITLE".localizedInThisBundle, action: actions.userIndicatedHerProfileIsManagedByOrganisation)
                }
                .font(.subheadline)
                .padding(.top, 10)
                
                InternalButton("ONBOARDING_NAME_CHOOSER_BUTTON_TITLE", action: createProfileButtonTapped)
                .disabled(isButtonDisabled)
                .padding(.vertical, 20)
                
            }
            .padding(.horizontal)
            .disabled(isInterfaceDisabled)
        }.onAppear(perform: {
            isInterfaceDisabled = false
        })
    }
}


// MARK: - Button used in this view only

private struct InternalButton: View {
    
    private let key: LocalizedStringKey
    private let action: () -> Void
    @Environment(\.isEnabled) var isEnabled
    
    init(_ key: LocalizedStringKey, action: @escaping () -> Void) {
        self.key = key
        self.action = action
    }
        
    var body: some View {
        Button(action: action) {
            Text(key)
                .foregroundStyle(.white)
            .padding(.horizontal, 30)
            .padding(.vertical, 24)
        }
        .background(Color.blue01)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isEnabled ? 1.0 : 0.6)
    }
    
}




// MARK: - Text field used in this view only

private struct InternalTextField: View {
    
    private let key: LocalizedStringKey
    private let text: Binding<String>
    
    init(_ key: LocalizedStringKey, text: Binding<String>) {
        self.key = key
        self.text = text
    }
    
    var body: some View {
        TextField(text: text) {
            Text(key) // This makes sure the localization is search for in this bundle
        }
        .padding()
        .background(Color.textFieldBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
}


// MARK: - Previews

struct NewUnmanagedDetailsChooserView_Previews: PreviewProvider {
    
    private final class ActionsForPreviews: NewUnmanagedDetailsChooserViewActions {
        func userWantsToTakePhoto() async -> UIImage? {
            return UIImage(systemIcon: .checkmarkShield)
            
        }
        
        func userWantsToChoosePhoto() async -> UIImage? {
            return UIImage(systemIcon: .checkmarkSealFill)
        }
        
        func userWantsToChoosePhotoWithDocumentPicker() async -> UIImage? {
            return UIImage(systemIcon: .airpods)
        }
        
        func userDidChooseUnmanagedDetails(ownedIdentityCoreDetails: ObvTypes.ObvIdentityCoreDetails, photo: UIImage?) {}
        func userIndicatedHerProfileIsManagedByOrganisation() {}
    }

    private static let actions = ActionsForPreviews()
    
    final class ModelForPreviews: NewUnmanagedDetailsChooserViewModelProtocol {

        var photoThatCannotBeRemoved: UIImage? { nil }
        @Published var circledInitialsConfiguration: CircledInitialsConfiguration
        let showPositionAndOrganisation: Bool
        
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
        
    private static let model = ModelForPreviews(showPositionAndOrganisation: false)

    static var previews: some View {
        NewUnmanagedDetailsChooserView(model: model, actions: actions)
    }
    
}
