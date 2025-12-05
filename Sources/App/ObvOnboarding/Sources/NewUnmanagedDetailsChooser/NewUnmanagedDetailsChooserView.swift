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
import ObvDesignSystem


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
                
                ObvHeaderView(title: "ONBOARDING_NAME_CHOOSER_TITLE".localizedInThisBundle,
                              subtitle: "LETS_CREATE_YOUR_PROFILE".localizedInThisBundle)
                    .padding(.bottom, 20)

                ObvPhotoButtonView(actions: self, model: model)
                    .padding(.bottom, 10)
                
                InternalTextField("ONBOARDING_NAME_CHOOSER_TEXTFIELD_FIRSTNAME", text: $firstname)
                    .autocorrectionDisabled()
                    .onChange(of: firstname) { _ in resetIsButtonDisabled() }
                    .padding(.bottom, 10)
                InternalTextField("ONBOARDING_NAME_CHOOSER_TEXTFIELD_LASTNAME", text: $lastname)
                    .autocorrectionDisabled()
                    .onChange(of: lastname) { _ in resetIsButtonDisabled() }
                    .padding(.bottom, 10)
                if model.showPositionAndOrganisation {
                    InternalTextField("ONBOARDING_NAME_CHOOSER_TEXTFIELD_POSITION", text: $position)
                        .padding(.bottom, 10)
                    InternalTextField("ONBOARDING_NAME_CHOOSER_TEXTFIELD_COMPANY", text: $company)
                        .padding(.bottom, 10)
                }
                
                HStack(alignment: .firstTextBaseline) {
                    Image(systemIcon: .lightbulbMax)
                        .foregroundStyle(.yellow)
                    Text("PROTECT_PRIVACY_EXPLANATION")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .font(.callout)
                .padding(.top, 10)

                CreateProfileButton(action: createProfileButtonTapped, isInterfaceDisabled: isInterfaceDisabled)
                    .disabled(isButtonDisabled)
                    .padding(.vertical, 20)

                HStack {
                    Text("ONBOARDING_NAME_CHOOSER_MANAGED_PROFILE_LABEL")
                        .foregroundStyle(.secondary)
                    Button("ONBOARDING_NAME_CHOOSER_MANAGED_PROFILE_BUTTON_TITLE".localizedInThisBundle, action: actions.userIndicatedHerProfileIsManagedByOrganisation)
                }
                .font(.subheadline)
                .padding(.top, 20)
                                
            }
            .padding(.horizontal)
            .disabled(isInterfaceDisabled)
        }.onAppear(perform: {
            isInterfaceDisabled = false
        })
    }
}


// MARK: - Internal view

private struct CreateProfileButton: View {
    
    let action: () -> Void
    let isInterfaceDisabled: Bool

    private let title = String(localizedInThisBundle: "ONBOARDING_NAME_CHOOSER_BUTTON_TITLE")
        
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Text(title)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.glassProminent)
            .buttonSizing(.flexible)
        } else {
            Button(action: action) {
                HStack {
                    Spacer(minLength: 0)
                    if isInterfaceDisabled {
                        ProgressView()
                    }
                    Text(title)
                        .padding(.vertical, 12)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.borderedProminent)
        }
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


#if DEBUG

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

@MainActor
private final class ModelForPreviews: NewUnmanagedDetailsChooserViewModelProtocol {
    
    var photoThatCannotBeRemoved: UIImage? { nil }
    @Published var circledInitialsConfiguration: CircledInitialsConfiguration
    let showPositionAndOrganisation: Bool
    
    init(showPositionAndOrganisation: Bool) {
        self.showPositionAndOrganisation = showPositionAndOrganisation
        self.circledInitialsConfiguration = .icon(.person)
    }
    
    func updatePhoto(with photo: UIImage?) async {
        if let photo {
            self.circledInitialsConfiguration = .photo(photo: .image(image: photo))
        } else {
            self.circledInitialsConfiguration = .icon(.person)
        }
    }
    
}

@MainActor
private let actionsForPreviews = ActionsForPreviews()

@MainActor
private let modelForPreviews = ModelForPreviews(showPositionAndOrganisation: false)

#Preview {
    NewUnmanagedDetailsChooserView(model: modelForPreviews,
                                   actions: actionsForPreviews)
    .environment(\.locale, .init(identifier: "fr"))
}

#endif
